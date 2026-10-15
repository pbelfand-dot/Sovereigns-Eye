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
## The village's stores or building sites changed (UI refresh).
signal territory_changed
## Entered or left building placement (type "" = left).
signal placing_changed(type: String)
## A building (or building site) was clicked; -1 = none.
signal building_selected(building_id: int)
## The heir reached someone and they talk: {lines, first, opinion}.
signal conversation_started(character_id: int, result: Dictionary)
signal conversation_ended

## How close the heir must be to speak with someone (meters).
const TALK_RANGE := 2.6

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
var soundscape: Soundscape
var npcs: Dictionary = {}

var paused := false
var speed_index := 0
var selected: NPC
var hovered: NPC

var _worker_slots: Dictionary = {}
var _forest_spots: Array[Vector3] = []
var _npc_root: Node3D

## Building placement (Build menu): the type being placed, its preview and
## quarter-turns away from facing the road.
var placing_type := ""
var selected_building := -1
## Who the heir is speaking with (-1 = no one) / walking over to.
var talking_to := -1
var _pending_talk := -1
var _reveal: EyeReveal
var _over_building := false
var _hand_cursor := false
var _selection_frame: Node3D
var _ghost: BuildGhost
var _turn := 0
var _placement: Dictionary = {}
var _placement_check: Dictionary = {}


func _ready() -> void:
	state = Game.state
	if state == null:
		# Running world.tscn directly from the editor (F6): make a world.
		state = WorldGenerator.generate(DEFAULT_SEED)
		Game.state = state
	TerrainHeight.configure(state.layout.terrain_seed, state.layout.flat_radius)
	TerritorySystem.initialize(state)

	sky = SkyController.new()
	sky.name = "Sky"
	add_child(sky)
	builder = VillageBuilder.new()
	builder.name = "Village"
	builder.territory = state.territory
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
	camera_rig.right_clicked.connect(_on_right_clicked)

	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(self)

	soundscape = Soundscape.new()
	soundscape.name = "Soundscape"
	add_child(soundscape)
	soundscape.setup(self)

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
		_advance_construction(game_minutes)
	for npc: NPC in npcs.values():
		npc.brain.update(game_minutes)
		npc.tick(delta, scale_now)
	sky.set_time(state.minutes)
	if not placing_type.is_empty():
		_update_ghost()
	elif not is_revealing():
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
	var crews_before := _crews()
	for e: Dictionary in TerritorySystem.daily_update(state):
		_announce(e)
		if e.has("hired"):
			_on_hired(int(e["hired"]))
	for e: Dictionary in GrowthSystem.daily_update(state):
		_on_growth_event(e)
	_replan_crew_changes(crews_before)
	territory_changed.emit()
	day_passed.emit(day)


## Shows a court event as a notification in the right color.
func _announce(e: Dictionary) -> void:
	if str(e.get("text", "")).is_empty():
		return
	var color := Game.COLOR_INFO
	match str(e.get("kind", "")):
		"rank", "potential":
			color = Game.COLOR_TALENT
		"good", "join", "knight":
			color = Game.COLOR_GOOD
		"bad", "leave":
			color = Game.COLOR_BAD
	Game.notify.emit(str(e["text"]), color)


# --- Building (Phase 3) -------------------------------------------------------------------

func _advance_construction(game_minutes: float) -> void:
	if state.territory.sites.is_empty():
		return
	var finished := TerritorySystem.advance(state, game_minutes)
	builder.update_sites()
	for site in finished:
		_finish_site(site)


## Character id -> building site id, for everyone on a crew.
func _crews() -> Dictionary:
	var out := {}
	for s in state.territory.sites:
		for id in s.builders:
			out[id] = s.id()
	return out


## Builders who joined, left or switched sites re-plan their day.
func _replan_crew_changes(before: Dictionary) -> void:
	var after := _crews()
	for id: int in before:
		if after.get(id, -1) != before[id]:
			court_changed(id)
	for id: int in after:
		if before.get(id, -1) != after[id]:
			court_changed(id)


func _finish_site(site: ConstructionSite) -> void:
	var crews_before := _crews()
	var events := TerritorySystem.complete(state, site)
	var b := site.building
	builder.remove_site(b.id)
	if site.is_upgrade():
		builder.replace_building_node(b)
	else:
		builder.add_building_node(b)
		for f in state.layout.fields_of_building(b.id):
			builder.add_field(f)
		_layout_changed()
		builder.refresh_props()
	Audio.play("court_good")
	for e in events:
		_announce(e)
		if e.has("hired"):
			_on_hired(int(e["hired"]))
	_replan_crew_changes(crews_before)
	territory_changed.emit()


## A growth event: settlers to spawn, or a home or upgrade site to show.
func _on_growth_event(e: Dictionary) -> void:
	_announce(e)
	if e.has("arrived"):
		for id: int in e["arrived"]:
			spawn_character(id)
		_compute_worker_slots()
	if e.has("hired"):
		_on_hired(int(e["hired"]))
	if e.has("site"):
		var site := state.territory.get_site(int(e["site"]))
		if site:
			builder.add_site(site)
			if not site.is_upgrade():
				_layout_changed()
				builder.refresh_props()


## Gives a character who joined the village (a settler) a body and a brain.
func spawn_character(character_id: int) -> NPC:
	var c := state.get_character(character_id)
	if c == null or npcs.has(character_id):
		return npcs.get(character_id, null)
	var npc := NPC.new()
	_npc_root.add_child(npc)
	npc.setup(c)
	npc.brain = NPCBrain.new(npc, self)
	npcs[c.id] = npc
	return npc


## Someone took a new job: new clothes, new workplace, new routine.
func _on_hired(character_id: int) -> void:
	var npc := npc_of(character_id)
	if npc:
		npc.refresh_model()
	_compute_worker_slots()
	court_changed(character_id)


## Roads, doors and the ground follow the layout after building changes.
func _layout_changed() -> void:
	graph.build(state.layout)
	builder.refresh_ground()


func is_placing() -> bool:
	return not placing_type.is_empty()


## Enters placement mode for a building type from the Build menu.
func start_placing(type: String) -> void:
	cancel_placing()
	var allowed := TerritorySystem.can_build(state, type)
	if not allowed["ok"]:
		Audio.play("ui_error")
		Game.notify.emit(str(allowed["reason"]), Game.COLOR_BAD)
		return
	placing_type = type
	_turn = 0
	_ghost = BuildGhost.new()
	add_child(_ghost)
	_ghost.setup(type)
	_placement = {}
	if hovered:
		hovered.set_hovered(false)
		hovered = null
	_hand_cursor = false
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	placing_changed.emit(type)


func cancel_placing() -> void:
	if placing_type.is_empty():
		return
	placing_type = ""
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_hand_cursor = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	placing_changed.emit("")


## Turns the building being placed by a quarter (T).
func turn_ghost() -> void:
	_turn = (_turn + 1) % 4


## Why the current spot does or doesn't work ("" while there is no spot).
func placement_reason() -> String:
	return str(_placement_check.get("reason", ""))


func placement_trees() -> int:
	return (_placement_check.get("trees", []) as Array).size()


func _update_ghost() -> void:
	var vp := get_viewport()
	if vp.gui_get_hovered_control() != null:
		_ghost.visible = false
		return
	var g: Variant = camera_rig.ground_point(vp.get_mouse_position())
	if g == null:
		_ghost.visible = false
		return
	preview_at(g)


## Shows the building being placed snapped to the spot nearest `point`.
func preview_at(point: Vector3) -> void:
	_ghost.visible = true
	_placement = TerritorySystem.snap(state, placing_type, point, _turn)
	_placement_check = TerritorySystem.check_placement(state, placing_type, _placement["pos"], _placement["rot"])
	_ghost.show_at(_placement["pos"], _placement["rot"], _placement_check, state.layout.trees)


## Places the previewed building (left click). Shift keeps placing.
func confirm_placement() -> void:
	if _placement.is_empty():
		return
	var result := place_building(placing_type, _placement["pos"], _placement["rot"])
	if result["ok"] and not Input.is_key_pressed(KEY_SHIFT):
		cancel_placing()
	elif result["ok"] and not TerritorySystem.can_build(state, placing_type)["ok"]:
		cancel_placing()


## Orders a building at a spot and shows its site. Returns TerritorySystem.place()'s result.
func place_building(type: String, pos: Vector3, rot: float) -> Dictionary:
	var crews_before := _crews()
	var result := TerritorySystem.place(state, type, pos, rot)
	if not result["ok"]:
		Audio.play("ui_error")
		Game.notify.emit(str(result["text"]), Game.COLOR_BAD)
		return result
	var site: ConstructionSite = result["site"]
	builder.add_site(site)
	_layout_changed()
	builder.refresh_props()
	Audio.play("coins")
	Audio.play("work_wood")
	Game.notify.emit(str(result["text"]), Game.COLOR_GOOD)
	_replan_crew_changes(crews_before)
	territory_changed.emit()
	return result


## Abandons a building site from the Build panel.
func cancel_site(building_id: int) -> void:
	var site := state.territory.get_site(building_id)
	if site == null:
		return
	var crews_before := _crews()
	var result := TerritorySystem.cancel(state, site)
	builder.remove_site(building_id)
	if site.is_upgrade():
		builder.set_building_visible(building_id, true)
	else:
		_layout_changed()
		builder.refresh_props()
	Game.notify.emit(str(result["text"]), Game.COLOR_INFO)
	_replan_crew_changes(crews_before)
	territory_changed.emit()


## Moves the camera to a building site.
func focus_site(building_id: int) -> void:
	var site := state.territory.get_site(building_id)
	if site:
		camera_rig.follow_target = null
		camera_rig.look_at_point(site.building.position, 38.0)


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
	# Buildings can be clicked too: show the hand over them.
	if hovered == null and not over_ui and Engine.get_process_frames() % 4 == 0:
		_over_building = pick_building(vp.get_mouse_position()) >= 0
	var hand := hovered != null or (_over_building and not over_ui)
	if hand != _hand_cursor:
		_hand_cursor = hand
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hand else Input.CURSOR_ARROW)


## Right click with the heir selected: walk there.
func _on_right_clicked(screen_pos: Vector2) -> void:
	if is_placing() or selected == null or not state.is_player(selected.character):
		return
	var g: Variant = camera_rig.ground_point(screen_pos)
	if g == null:
		return
	if talking_to >= 0 or _pending_talk >= 0:
		end_conversation()
	selected.brain.set_errand({"type": "walk", "pos": g, "minutes": 90.0})
	Audio.play("ui_tick")
	Game.notify.emit("%s walks over there." % selected.character.first_name, Game.COLOR_INFO)


func _on_clicked(screen_pos: Vector2) -> void:
	if is_revealing():
		return
	if is_placing():
		confirm_placement()
		return
	var npc := pick_npc(screen_pos)
	if npc:
		select_character(npc.character.id)
		return
	var building := pick_building(screen_pos)
	if building >= 0:
		select_building(building)
	else:
		deselect()


## The building (or building site) under a screen position, or -1. Rays are
## tested against each building's box, so clicking a roof picks its house.
func pick_building(screen_pos: Vector2) -> int:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var candidates: Array[BuildingData] = []
	candidates.append_array(state.layout.buildings)
	for s in state.territory.sites:
		if not s.is_upgrade():
			candidates.append(s.building)
	var best := -1
	var best_d := INF
	for b in candidates:
		var inv := b.basis().inverse()
		var local_from := inv * (from - TerrainHeight.on_ground(b.position))
		var local_dir := inv * dir
		var box := AABB(Vector3(-b.footprint.x * 0.5, 0.0, -b.footprint.y * 0.5), Vector3(b.footprint.x, building_height(b), b.footprint.y))
		var hit: Variant = box.intersects_ray(local_from, local_dir)
		if hit != null:
			var d := (hit as Vector3).distance_to(local_from)
			if d < best_d:
				best_d = d
				best = b.id
	return best


## Roughly how tall a building looks (for picking).
func building_height(b: BuildingData) -> float:
	if VillageKit.has_prefab(b.type):
		return float(VillageKit.prefab(b.type, b.variant, b.tier).get("height", 5.0)) * 0.9
	return float(b.type_def().get("wall_height", 3.0)) + 2.0


func select_building(building_id: int) -> void:
	if selected:
		selected.set_selected(false)
		selected = null
		camera_rig.follow_target = null
		selection_changed.emit(null)
	selected_building = building_id
	_show_selection_frame()
	Audio.play("ui_select")
	building_selected.emit(building_id)


func _show_selection_frame() -> void:
	if _selection_frame:
		_selection_frame.queue_free()
		_selection_frame = null
	var b := state.get_building(selected_building)
	if b == null:
		var site := state.territory.get_site(selected_building)
		b = site.building if site else null
	if b == null:
		return
	_selection_frame = Node3D.new()
	_selection_frame.name = "SelectionFrame"
	add_child(_selection_frame)
	_selection_frame.position = TerrainHeight.on_ground(b.position) + Vector3(0, 0.12, 0)
	_selection_frame.rotation.y = b.rotation
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#e9bf62")
	var hx := b.footprint.x * 0.5 + 0.9
	var hz := b.footprint.y * 0.5 + 0.9
	for side in 4:
		var along_x := side < 2
		var size := Vector3(hx * 2.0 + 0.25, 0.08, 0.25) if along_x else Vector3(0.25, 0.08, hz * 2.0 + 0.25)
		var pos := Vector3(0, 0, hz * (1 if side == 0 else -1)) if along_x else Vector3(hx * (1 if side == 2 else -1), 0, 0)
		var mi := Mats.box(_selection_frame, size, pos, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func select_character(character_id: int, focus_camera: bool = false) -> void:
	var c := state.get_character(character_id)
	if c == null:
		return
	if selected_building >= 0:
		selected_building = -1
		_show_selection_frame()
		building_selected.emit(-1)
	if selected:
		selected.set_selected(false)
	selected = npc_of(character_id)
	if selected:
		selected.set_selected(true)
	if focus_camera:
		focus_on(character_id)
	selection_changed.emit(c)


func deselect() -> void:
	if selected:
		selected.set_selected(false)
	selected = null
	camera_rig.follow_target = null
	selection_changed.emit(null)
	if selected_building >= 0:
		selected_building = -1
		_show_selection_frame()
		building_selected.emit(-1)


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


# --- Meeting people & the Sovereign's Eye ----------------------------------------------------

func player_npc() -> NPC:
	return npc_of(state.player_id)


## Sends the heir to speak with someone. They walk over; the conversation
## opens when they arrive (at once if they're already standing together).
func request_talk(character_id: int) -> void:
	var c := state.get_character(character_id)
	var heir := player_npc()
	var target := npc_of(character_id)
	if c == null or heir == null or target == null or state.is_player(c):
		return
	if talking_to >= 0:
		end_conversation()
	_pending_talk = character_id
	heir.brain.set_errand({"type": "talk", "target": character_id})
	var near := heir.visible and target.visible and heir.global_position.distance_to(target.global_position) <= TALK_RANGE * 1.5
	if near:
		heir_arrived(character_id)
		return
	Game.notify.emit("%s sets off to speak with %s.%s" % [heir.character.first_name, c.first_name, "  (Unpause to let them walk.)" if time_scale() <= 0.0 else ""], Game.COLOR_INFO)
	camera_rig.follow_target = heir


## The heir reached the person: both stop and the conversation opens.
func heir_arrived(character_id: int) -> void:
	if _pending_talk != character_id:
		return
	_pending_talk = -1
	var heir := player_npc()
	var target := npc_of(character_id)
	if heir == null or target == null:
		return
	if target.character.inside_building_id >= 0:
		target.brain._leave_building()
	heir.brain.set_errand({"type": "hold", "face": target.global_position})
	target.brain.set_errand({"type": "hold", "face": heir.global_position})
	talking_to = character_id
	camera_rig.follow_target = null
	camera_rig.look_at_point((heir.global_position + target.global_position) * 0.5, minf(camera_rig.view_distance(), 18.0))
	var result := Discovery.meet(state, target.character)
	Audio.play("card_open")
	conversation_started.emit(character_id, result)
	court_changed(character_id)


## Ends the conversation; both go back to their day.
func end_conversation() -> void:
	if _pending_talk >= 0:
		var heir := player_npc()
		if heir:
			heir.brain.set_errand({})
		_pending_talk = -1
	if talking_to < 0:
		return
	var target := npc_of(talking_to)
	if target:
		target.brain.set_errand({})
	var heir2 := player_npc()
	if heir2:
		heir2.brain.set_errand({})
	talking_to = -1
	conversation_ended.emit()


func is_revealing() -> bool:
	return _reveal != null and is_instance_valid(_reveal)


## Looks at someone with the Sovereign's Eye: the full reveal the first
## time, a quick card after that.
func use_eye(character_id: int) -> void:
	var c := state.get_character(character_id)
	if c == null or is_revealing():
		return
	var check := Discovery.can_use_eye(state, c)
	if not check["ok"]:
		Audio.play("ui_error")
		Game.notify.emit(str(check["reason"]), Game.COLOR_BAD)
		return
	if talking_to >= 0:
		end_conversation()
	var first := not c.appraised
	_reveal = EyeReveal.new()
	add_child(_reveal)
	_reveal.finished.connect(_on_reveal_finished.bind(c.id, first))
	_reveal.play(self, c, not first)
	appraise(c)


func _on_reveal_finished(action: String, character_id: int, first: bool) -> void:
	_reveal = null
	var c := state.get_character(character_id)
	if c == null:
		return
	if first and Appraisal.is_exceptional(c):
		var best := c.best_attribute()
		var p := c.get_potential(best)
		Game.notify.emit("Exceptional talent discovered! %s - %s %s (%d)" % [
			c.full_name(), GameData.attribute_def(best).get("name", best), Appraisal.rank_id(p), p], Game.COLOR_TALENT)
	match action:
		"recruit", "appoint":
			select_character(character_id)
			ui.show_card_tab("court")
		"follow":
			select_character(character_id, true)
		"card":
			select_character(character_id)
	if ui:
		ui.refresh()


## Marks a person appraised (their gifts are now known to the player).
func appraise(c: CharacterData) -> void:
	if c.appraised:
		return
	c.appraised = true
	c.met = true


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
			c.met = true
		Game.notify.emit("Debug: every villager appraised.", Game.COLOR_INFO)
		ui.refresh()
	else:
		return
	get_viewport().set_input_as_handled()


## Writes live NPC positions back into the WorldState before saving.
func sync_to_state() -> void:
	for npc: NPC in npcs.values():
		npc.sync_to_data()
