class_name VillageWorld
extends Node3D
## Root of the playable world scene.
##
## Builds the village from Game.state, spawns an NPC body for every
## character, runs the clock and routes input: picking NPCs, appraising them,
## game speed, saving/loading hotkeys.

signal selection_changed(character: CharacterData)
signal speed_changed(time_scale: float)
signal day_passed(day_index: int)

## In-game minutes per real second at 1x speed (1 hour = 40 s, 1 day = 16 min).
const GAME_MINUTES_PER_SECOND := 1.5
const SPEEDS := [1.0, 2.0, 4.0, 8.0]
const DEFAULT_SEED := "12345"

var state: WorldState
var builder: VillageBuilder
var graph: RoadGraph
var sky: SkyController
var camera_rig: StrategyCamera
var ui: GameUI
var npcs: Dictionary = {}

var paused := false
var speed_index := 0
var selected: NPC
var hovered: NPC

var _worker_slots: Dictionary = {}
var _forest_spots: Array[Vector3] = []
var _npc_root: Node3D


func _ready() -> void:
	state = Game.state
	if state == null:
		# Running world.tscn directly from the editor (F6): make a world.
		state = WorldGenerator.generate(DEFAULT_SEED)
		Game.state = state
	TerrainHeight.configure(state.layout.terrain_seed, state.layout.flat_radius)

	sky = SkyController.new()
	sky.name = "Sky"
	add_child(sky)
	builder = VillageBuilder.new()
	builder.name = "Village"
	add_child(builder)
	builder.build(state.layout)
	graph = RoadGraph.new()
	graph.build(state.layout)
	_compute_worker_slots()
	_compute_forest_spots()
	_spawn_npcs()

	camera_rig = StrategyCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.bounds_radius = state.layout.extent - 10.0
	add_child(camera_rig)
	camera_rig.look_at_point(state.layout.square_center + Vector3(0, 0, 6), 62.0, true)
	camera_rig.clicked.connect(_on_clicked)

	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(self)

	Game.before_save.connect(sync_to_state)
	sky.set_time(state.minutes)
	print("World ready: %s (seed %s), %d villagers, %d buildings" % [state.village_name, state.seed_text, state.characters.size(), state.layout.buildings.size()])
	PortraitPrompt.write_prompt_file(state)


func _exit_tree() -> void:
	if Game.before_save.is_connected(sync_to_state):
		Game.before_save.disconnect(sync_to_state)


# --- Setup ---------------------------------------------------------------------------

func _spawn_npcs() -> void:
	_npc_root = Node3D.new()
	_npc_root.name = "NPCs"
	add_child(_npc_root)
	for c in state.characters:
		var npc := NPC.new()
		_npc_root.add_child(npc)
		npc.setup(c)
		npc.brain = NPCBrain.new(npc, self)
		npcs[c.id] = npc
		if state.is_player(c):
			npc.set_player_marker(true)


func _compute_worker_slots() -> void:
	var counts := {}
	for c in state.characters:
		if c.work_building_id < 0:
			continue
		var n := int(counts.get(c.work_building_id, 0))
		_worker_slots[c.id] = n
		counts[c.work_building_id] = n + 1


func _compute_forest_spots() -> void:
	for t in state.layout.trees:
		var d := Vector2(t.x, t.y).length()
		if d > 46.0 and d < 82.0:
			_forest_spots.append(Vector3(t.x, 0, t.y))
	if _forest_spots.is_empty():
		_forest_spots.append(Vector3(60, 0, 0))


## Index of this worker among the people sharing their workplace.
func worker_slot(c: CharacterData) -> int:
	return int(_worker_slots.get(c.id, 0))


func random_forest_spot(rng: RandomNumberGenerator) -> Vector3:
	return _forest_spots[rng.randi_range(0, _forest_spots.size() - 1)]


func npc_of(character_id: int) -> NPC:
	return npcs.get(character_id, null)


# --- Time ------------------------------------------------------------------------------

func time_scale() -> float:
	return 0.0 if paused else float(SPEEDS[speed_index])


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	paused = false
	speed_changed.emit(time_scale())


func toggle_pause() -> void:
	paused = not paused
	speed_changed.emit(time_scale())


func _process(delta: float) -> void:
	var scale_now := time_scale()
	var game_minutes := delta * GAME_MINUTES_PER_SECOND * scale_now
	if game_minutes > 0.0:
		state.minutes += game_minutes
		_check_new_day()
	for npc: NPC in npcs.values():
		npc.brain.update(game_minutes)
		npc.tick(delta, scale_now)
	sky.set_time(state.minutes)
	_update_hover()


func _check_new_day() -> void:
	var day := Calendar.day_index(state.whole_minutes())
	if day <= state.last_daily_update:
		return
	state.last_daily_update = day
	var rng := Seeds.rng(state.world_seed, "day_%d" % day)
	for c in state.characters:
		MoodSystem.daily_update(c, state, rng)
	var court_rng := Seeds.rng(state.world_seed, "court_day_%d" % day)
	for e: Dictionary in CourtSystem.daily_update(state, court_rng):
		_announce(e)
		if str(e.get("kind", "")) == "bad" and e.has("character"):
			court_changed(int(e["character"]))
	day_passed.emit(day)


## Shows a court event as a notification in the right color.
func _announce(e: Dictionary) -> void:
	var color := Game.COLOR_INFO
	match str(e.get("kind", "")):
		"rank", "potential":
			color = Game.COLOR_TALENT
		"good", "join", "knight":
			color = Game.COLOR_GOOD
		"bad", "leave":
			color = Game.COLOR_BAD
	Game.notify.emit(str(e["text"]), color)


## Call after someone's court role changes so their body re-plans its day
## (new workplace, schedule) and the UI refreshes.
func court_changed(character_id: int) -> void:
	var npc := npc_of(character_id)
	if npc and npc.brain:
		npc.brain.replan()
	if ui:
		ui.refresh()


# --- Picking & appraisal ------------------------------------------------------------------

## Finds the NPC under a screen position. Screen-space test against each
## body's projected outline: generous for small, distant characters and
## cheap even with hundreds of NPCs.
func pick_npc(screen_pos: Vector2) -> NPC:
	var cam := camera_rig.camera
	var best: NPC = null
	var best_score := INF
	for npc: NPC in npcs.values():
		if not npc.visible:
			continue
		var foot := npc.global_position
		var head := foot + Vector3(0, 1.9 * npc.model.body_height, 0)
		if cam.is_position_behind(foot) or cam.is_position_behind(head):
			continue
		var a := cam.unproject_position(foot)
		var b := cam.unproject_position(head)
		var closest := Geometry2D.get_closest_point_to_segment(screen_pos, a, b)
		var dist := screen_pos.distance_to(closest)
		var radius := maxf(12.0, a.distance_to(b) * 0.35)
		if dist > radius:
			continue
		# Prefer the closest-to-camera person when bodies overlap.
		var score := dist / radius + cam.global_position.distance_to(foot) * 0.002
		if score < best_score:
			best_score = score
			best = npc
	return best


func _update_hover() -> void:
	var vp := get_viewport()
	var over_ui := vp.gui_get_hovered_control() != null
	var target: NPC = null
	if not over_ui:
		target = pick_npc(vp.get_mouse_position())
	if target != hovered:
		if hovered:
			hovered.set_hovered(false)
		hovered = target
		if hovered:
			hovered.set_hovered(true)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hovered else Input.CURSOR_ARROW)


func _on_clicked(screen_pos: Vector2) -> void:
	var npc := pick_npc(screen_pos)
	if npc:
		select_character(npc.character.id)
	else:
		deselect()


func select_character(character_id: int, focus_camera: bool = false) -> void:
	var c := state.get_character(character_id)
	if c == null:
		return
	if selected:
		selected.set_selected(false)
	selected = npc_of(character_id)
	if selected:
		selected.set_selected(true)
	appraise(c)
	if focus_camera:
		focus_on(character_id)
	selection_changed.emit(c)


func deselect() -> void:
	if selected:
		selected.set_selected(false)
	selected = null
	camera_rig.follow_target = null
	selection_changed.emit(null)


## Moves the camera to a character (following them if they are outdoors).
func focus_on(character_id: int) -> void:
	var npc := npc_of(character_id)
	if npc == null:
		return
	if npc.visible:
		camera_rig.follow_target = npc
		camera_rig.look_at_point(npc.global_position, minf(camera_rig._target_distance, 28.0))
	else:
		var b := state.get_building(npc.character.inside_building_id)
		camera_rig.follow_target = null
		camera_rig.look_at_point(b.position if b else npc.global_position, 32.0)


## Uses the Appraisal skill on a character. The first appraisal of someone
## exceptional is announced: that discovery is the heart of the game.
func appraise(c: CharacterData) -> void:
	if c.appraised:
		return
	c.appraised = true
	if Appraisal.is_exceptional(c):
		var best := c.best_attribute()
		var p := c.get_potential(best)
		Game.notify.emit("Exceptional talent discovered! %s - %s %s (%d)" % [
			c.full_name(), GameData.attribute_def(best).get("name", best), Appraisal.rank_id(p), p], Game.COLOR_TALENT)


func appraised_count() -> int:
	var n := 0
	for c in state.characters:
		if c.appraised:
			n += 1
	return n


# --- Input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if ui and ui.is_menu_open():
		return
	if event.is_action_pressed("toggle_pause"):
		toggle_pause()
	elif event.is_action_pressed("speed_1"):
		set_speed(0)
	elif event.is_action_pressed("speed_2"):
		set_speed(1)
	elif event.is_action_pressed("speed_3"):
		set_speed(2)
	elif event.is_action_pressed("speed_4"):
		set_speed(3)
	elif event.is_action_pressed("quicksave"):
		Game.save_game("quicksave")
	elif event.is_action_pressed("quickload"):
		if SaveManager.exists("quicksave"):
			Game.load_game("quicksave")
		else:
			Game.notify.emit("No quicksave yet (press F5 to quicksave).", Game.COLOR_BAD)
	elif event.is_action_pressed("focus_selected") and selected:
		focus_on(selected.character.id)
	elif event.is_action_pressed("debug_reveal_all"):
		for c in state.characters:
			c.appraised = true
		Game.notify.emit("Debug: every villager appraised.", Game.COLOR_INFO)
		ui.refresh()
	else:
		return
	get_viewport().set_input_as_handled()


## Writes live NPC positions back into the WorldState before saving.
func sync_to_state() -> void:
	for npc: NPC in npcs.values():
		npc.sync_to_data()
