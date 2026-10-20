class_name VillageWorld
extends Node3D
## Root of the playable world scene.
##
## Builds the village from Game.state, spawns an NPC body for every
## character, runs the clock and routes input.
##
## Two ways of being in the world:
##   "walk"     you are the heir, on foot (HeirController + a following
##              camera): look at someone nearby and use the Sovereign's Eye
##              (Q), walk up and talk (E) to learn what they want and make
##              an offer (Recruitment).
##   "overview" the map table (Tab / M): the old overhead view for building
##              and planning. Leaving it puts you back in the heir's boots.

signal selection_changed(character: CharacterData)
signal speed_changed(time_scale: float)
signal day_passed(day_index: int)
## The village's stores or building sites changed (UI refresh).
signal territory_changed
## Entered or left building placement (type "" = left).
signal placing_changed(type: String)
## A building (or building site) was clicked; -1 = none.
signal building_selected(building_id: int)
## The heir speaks with someone: {lines, first, opinion}.
signal conversation_started(character_id: int, result: Dictionary)
signal conversation_ended
## "walk" or "overview" (the map table).
signal mode_changed(mode: String)
## Who the heir is looking at changed (-1 = no one).
signal focus_changed(character_id: int)
## You died and go on as someone else (Phase 4.3): their body is yours now.
signal player_changed(character_id: int)
## No one of the house is left (Succession): the game is over.
signal house_ended(text: String)
## Letting the years pass: `done` of `total` days so far.
signal time_passing(done: int, total: int)

## Beyond this distance from the camera (m), bodies animate every third
## frame (they are a few pixels tall by then).
const ANIM_LOD_DISTANCE := 55.0

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
## True while the years are let pass (pass_time): news is gathered, not shown.
var passing := false
## The raid being fought in the village (Phase 5.1), or null.
var battle: Battle
## The house's castle, standing or rising (Phase 5.3).
var castle_view: CastleView
var cart_view: CartView
## Music that overrides the time of day ("battle", then "victory"/"defeat").
var music_override := ""
var _music_override_left := 0.0
var _passed: Dictionary = {}
## pass_time is running while the heir is away (a journey): only a
## succession or the house's end stops it.
var _away := false
var selected: NPC
var hovered: NPC

var _worker_slots: Dictionary = {}
var _forest_spots: Array[Vector3] = []
var _npc_root: Node3D

## Building placement (Build menu): the type being placed, its preview and
## quarter-turns away from facing the road.
var placing_type := ""
var selected_building := -1
## Who the heir is speaking with (-1 = no one).
var talking_to := -1
var _reveal: EyeReveal
## "walk" (as the heir) or "overview" (the map table).
var mode := "overview"
var heir_ctl: HeirController
## The person the heir is looking at: the Eye and a word go to them.
var focus: NPC
var _preferred_focus := -1
## Buildings faded because they stand between the camera and the heir.
var _faded: Dictionary = {}
var _paused_hint_at := -100.0
var _over_building := false
var _hand_cursor := false
var _selection_frame: Node3D
var _ghost: BuildGhost
var _turn := 0
var _placement: Dictionary = {}
var _placement_check: Dictionary = {}
## Who has said what lately (data/barks.json), on a real-time clock.
var barks: Barks
var _bark_clock := 0.0
var _bark_wait := 0.0


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
	builder.castle_pads = CastleSystem.pads(state)
	builder.castle_yard = CastleSystem.yard(state)
	add_child(builder)
	builder.build(state.layout)
	castle_view = CastleView.new()
	add_child(castle_view)
	castle_view.setup(state)
	cart_view = CartView.new()
	cart_view.name = "Carts"
	add_child(cart_view)
	cart_view.setup(self)
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
	camera_rig.obstruction = view_blocked_at
	_setup_heir()

	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(self)

	soundscape = Soundscape.new()
	soundscape.name = "Soundscape"
	add_child(soundscape)
	soundscape.setup(self)

	Game.before_save.connect(sync_to_state)
	if heir_away():
		_home_from_away.call_deferred()
	if state.house and state.house.ended:
		_end_house.call_deferred("The house is ended.")
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
		if LifeSystem.is_unseen(c) and not state.is_player(c):
			continue  # babies stay at home until they can walk about (unless you're one)
		if c.is_away() and not state.is_player(c):
			continue  # away from the village (a camp, fostering)
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
	if passing:
		return  # pass_time drives the days; no one moves meanwhile
	var scale_now := time_scale()
	var game_minutes := delta * GAME_MINUTES_PER_SECOND * scale_now
	if game_minutes > 0.0:
		state.minutes += game_minutes
		_check_new_day()
		_advance_construction(game_minutes)
	_check_raid()
	if _music_override_left > 0.0:
		_music_override_left -= delta
		if _music_override_left <= 0.0:
			music_override = ""
	var heir := player_npc()
	if heir_ctl:
		heir_ctl.enabled = mode == "walk" and talking_to < 0 and not is_revealing() and not (ui and ui.is_menu_open()) and not (battle and battle.heir_down())
		heir_ctl.update(delta)
		if heir_ctl.enabled and paused and heir_ctl.move_input().length() > 0.5:
			_hint_paused()
	var eye := camera_rig.camera.global_position if camera_rig and camera_rig.camera else Vector3.ZERO
	var near := ANIM_LOD_DISTANCE * ANIM_LOD_DISTANCE
	for npc: NPC in npcs.values():
		if npc != heir and not npc.fighting:
			npc.brain.update(game_minutes)
		npc.anim_lod = 1 if npc == heir or npc.global_position.distance_squared_to(eye) < near else 3
		npc.tick(delta, scale_now)
	sky.set_time(state.minutes)
	if not placing_type.is_empty():
		_update_ghost()
	elif not is_revealing():
		_update_hover()
		if mode == "walk" and talking_to < 0:
			_update_focus()
	_update_barks(delta)
	_update_fades()


## Villagers say a few words as the heir walks past them, checked a few
## times a second (data/barks.json). Only on foot, with time running, one
## voice at a time, and never over a conversation, the Eye or a menu.
func _update_barks(delta: float) -> void:
	_bark_clock += delta
	_bark_wait -= delta
	if _bark_wait > 0.0:
		return
	_bark_wait = 0.25
	var heir := player_npc()
	if heir == null or mode != "walk" or paused or talking_to >= 0 or is_revealing() or battle != null \
			or (ui and ui.is_menu_open()) or not GameSettings.remarks():
		return
	if barks == null:
		barks = Barks.new(state.world_seed)
	# One voice at a time: no one talks over someone still speaking.
	for npc: NPC in npcs.values():
		if npc.is_speaking():
			return
	var from := heir.global_position
	for npc: NPC in npcs.values():
		if npc == heir or not npc.visible:
			continue
		var d := Vector2(npc.global_position.x - from.x, npc.global_position.z - from.z).length()
		if not barks.passing(npc.character, d, _bark_clock) or WorldGeometry.line_blocked(state, from, npc.global_position):
			continue
		var text := barks.remark(state, npc.character, _bark_clock)
		if not text.is_empty():
			npc.say(text, Barks.duration(text, barks.cfg))
			return


## Everyone stops mid-remark (a conversation or the Eye begins).
func hush_remarks() -> void:
	for npc: NPC in npcs.values():
		npc.hush()


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
		if e.has("moved"):
			recruited(int(e["character"]))
		elif str(e.get("kind", "")) == "bad" and e.has("character"):
			court_changed(int(e["character"]))
	var crews_before := _crews()
	for e: Dictionary in TerritorySystem.daily_update(state):
		_announce(e)
		if e.has("hired"):
			_on_hired(int(e["hired"]))
	for e: Dictionary in Market.daily_update(state):
		_announce(e)
	for e: Dictionary in Trade.daily_update(state):
		_on_life_event(e)
	for e: Dictionary in LifeSystem.daily_update(state):
		_on_life_event(e)
	for e: Dictionary in MatchSystem.daily_update(state):
		_on_life_event(e)
	for e: Dictionary in Succession.daily_update(state):
		_on_life_event(e)
	for e: Dictionary in Military.daily_update(state):
		_on_life_event(e)
	for e: Dictionary in Realm.daily_update(state):
		_on_life_event(e)
	for e: Dictionary in CastleSystem.daily_update(state):
		_announce(e)
	for e: Dictionary in GrowthSystem.daily_update(state):
		_on_growth_event(e)
	_replan_crew_changes(crews_before)
	territory_changed.emit()
	day_passed.emit(day)


## Shows a court event as a notification in the right color.
func _announce(e: Dictionary) -> void:
	if str(e.get("text", "")).is_empty():
		return
	if passing:
		(_passed["news"] as Array).append(str(e["text"]))
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
	_advance_castle(game_minutes)
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
		builder.refresh_props()  # the home's yard grows with its level
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
	if passing and e.has("arrived"):
		_passed["counts"]["arrived"] += (e["arrived"] as Array).size()
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


## The years turn (LifeSystem): birthdays redraw a body, new work or a new
## home re-plans the day, a child old enough to walk about appears, and the
## departed leave the world.
func _on_life_event(e: Dictionary) -> void:
	_announce(e)
	if passing:
		_note_passing(e)
	if e.has("aged"):
		var npc := npc_of(int(e["aged"]))
		if npc:
			npc.refresh_model()
	if e.has("seen"):
		spawn_character(int(e["seen"]))
	if e.has("visitor"):
		spawn_character(int(e["visitor"]))
	if e.has("job"):
		_on_hired(int(e["job"]))
	for id: int in e.get("moved", []):
		court_changed(id)
	if e.has("player") and int(e["player"]) >= 0:
		take_over(int(e["player"]))
	if e.has("ended"):
		_end_house(str(e.get("text", "")))
	if e.has("gone"):
		remove_character_body(int(e["gone"]))
	for id: int in e.get("away", []):
		_leaves_village(id)
	for id: int in e.get("back", []):
		_comes_back(id)
	if e.has("battle") and (e["battle"] as Dictionary).get("camp", false):
		# A fight at a camp: the report when it comes (after a journey).
		if passing:
			_passed["report"] = e["battle"]
		elif ui:
			ui.show_battle_report(e["battle"])


# --- The castle (Phase 5.3) ------------------------------------------------------------------

## The works go on; pieces rise as they're done; the castle stands at last.
func _advance_castle(game_minutes: float) -> void:
	if state.castle == null or state.castle.works.is_empty():
		return
	var finished := CastleSystem.advance(state, game_minutes)
	if finished:
		for e: Dictionary in CastleSystem.complete(state):
			_announce(e)
		if not passing:
			Audio.play("knighted")
	if castle_view:
		castle_view.refresh()


## Orders the house's castle (the Court panel): the steward chooses the
## ground, it's levelled and cleared, a lane laid to the gate. {ok, text}
func order_castle(kind: String) -> Dictionary:
	var had_site := state.castle.has_site()
	var r := CastleSystem.order(state, kind)
	if not r["ok"]:
		return r
	if not had_site:
		builder.castle_pads = CastleSystem.pads(state)
		builder.castle_yard = CastleSystem.yard(state)
		builder.refresh_terrain()
		_layout_changed()
		for npc: NPC in npcs.values():
			npc.global_position = TerrainHeight.on_ground(npc.global_position)
	castle_view.refresh()
	for id in state.castle.builders:
		var npc := npc_of(id)
		if npc:
			npc.brain.replan()
	if ui:
		ui.refresh()
	return r


# --- Raids (Phase 5.1) ------------------------------------------------------------------------

## The band due today strikes at its hour: the fight is played out here.
func _check_raid() -> void:
	if battle != null or passing or state.house == null or state.house.ended:
		return
	if not Military.due(state) or state.day() > int(state.military.raid["day"]):
		return
	if Calendar.hour_f(state.minutes) < float(Military.strike_hour()):
		return
	start_battle()


## The raiders come in and the warband turns out (Battle).
func start_battle() -> Battle:
	if battle != null:
		return battle
	end_conversation()
	hush_remarks()
	if paused or speed_index > 0:
		set_speed(0)
	battle = Battle.new()
	add_child(battle)
	battle.finished.connect(_on_battle_finished)
	battle.start(self)
	music_override = "battle"
	_music_override_left = 0.0
	var raid := state.military.raid
	Game.notify.emit("%s attack from the %s road! Your warband turns out; the village runs for shelter. Walk up to a raider and press %s to strike." % [
		Military._cap(str(raid.get("name", "Raiders"))), raid.get("road", ""), key_hint("interact")], Game.COLOR_BAD)
	if ui:
		ui.refresh()
	return battle


func _on_battle_finished(report: Dictionary, events: Array) -> void:
	battle = null
	music_override = "victory" if report.get("won", false) else "defeat"
	_music_override_left = 40.0
	apply_life_events(events)
	if ui:
		ui.show_battle_report(report)


# --- Letting the years pass (Phase 4.3) --------------------------------------------------------

## Let `days` pass (a season, a year) a few days a frame, quietly: the news is
## gathered for a summary instead of shown, and it stops early for what needs
## you (data/succession.json "pass_time" stop_on). Returns Succession.summary.
func pass_time(days: int, away: bool = false) -> Dictionary:
	if passing or battle != null or (state.house and state.house.ended):
		return {}
	_away = away
	passing = true
	end_conversation()
	hush_remarks()
	var before := Succession.snapshot(state)
	_passed = {"news": [], "stop": "", "counts": {"born": 0, "died": 0, "left": 0, "wed": 0, "arrived": 0}}
	var per_frame := maxi(1, int(Succession.section("pass_time").get("days_per_frame", 2)))
	var done := 0
	while done < days:
		var crews_before := _crews()
		for k in 48:
			state.minutes += 30.0
			for site in TerritorySystem.advance(state, 30.0):
				_finish_site(site)
			_advance_castle(30.0)
		builder.update_sites()
		_replan_crew_changes(crews_before)
		_check_new_day()
		done += 1
		time_passing.emit(done, days)
		if not str(_passed["stop"]).is_empty():
			break
		if done % per_frame == 0 and is_inside_tree():
			await get_tree().process_frame
	passing = false
	var me := player_npc()
	for npc: NPC in npcs.values():
		if npc != me:
			npc.brain.replan()
	var summary := Succession.summary(state, before, _passed["news"], _passed["counts"], str(_passed["stop"]), done)
	if _passed.has("report"):
		summary["report"] = _passed["report"]
	if ui:
		ui.refresh()
	return summary


## What a day's event means while the years pass: the tallies, and whether
## it should stop the skip.
func _note_passing(e: Dictionary) -> void:
	var counts: Dictionary = _passed["counts"]
	if e.has("born"):
		counts["born"] += 1
	if e.has("moved") and str(e.get("kind", "")) == "good":
		counts["wed"] += 1  # a wedding (LifeSystem.marry, MatchSystem.wed)
	var stop := ""
	if e.has("gone"):
		var d := state.get_departed(int(e["gone"]))
		if d:
			counts["died" if d.departed_how == "died" else "left"] += 1
			if d.departed_how == "died" and d.family_id == state.ruling_family_id:
				stop = "kin_death"
	for key: String in ["regency_end", "health", "visitor", "raid_warning", "raid", "succession", "ended"]:
		if e.has(key):
			stop = key
	# Away from the village, only what ends the journey stops it.
	var stops: Array = ["succession", "ended"] if _away else Succession.section("pass_time").get("stop_on", [])
	if not stop.is_empty() and str(_passed["stop"]).is_empty() and stops.has(stop):
		_passed["stop"] = stop


## Applies what a match, a wedding or a suitor's leaving changed (events
## from MatchSystem or LifeSystem): new homes and clothes, bodies that come
## or go. The UI calls this after an action.
func apply_life_events(events: Array) -> void:
	for e: Dictionary in events:
		_on_life_event(e)
	if ui:
		ui.refresh()


## Takes a departed villager's body out of the world (and out of any talk,
## selection or focus).
func remove_character_body(character_id: int) -> void:
	if talking_to == character_id:
		end_conversation()
	var npc := npc_of(character_id)
	if npc == null:
		return
	if selected == npc:
		deselect()
	if focus == npc:
		_set_focus(null)
	if hovered == npc:
		hovered = null
	if _preferred_focus == character_id:
		_preferred_focus = -1
	if heir_ctl and heir_ctl.npc == npc:
		heir_ctl = null
		set_view_mode("overview", true)
	npcs.erase(character_id)
	npc.queue_free()
	_compute_worker_slots()


## Someone rides out (a camp, fostering) or you do (a journey): their body
## leaves the village; yours waits out of sight.
func _leaves_village(character_id: int) -> void:
	if character_id != state.player_id:
		remove_character_body(character_id)
		return
	var me := player_npc()
	end_conversation()
	set_view_mode("overview", true)
	if me:
		me.visible = false


## Someone comes home: a body at the manor's door (or yours, back in your
## boots).
func _comes_back(character_id: int) -> void:
	var c := state.get_character(character_id)
	if c == null:
		return
	var manor := state.get_building(CourtSystem._building_of_type(state, "manor"))
	var door := manor.door_position() if manor else state.layout.square_center
	c.position = TerrainHeight.on_ground(door)
	c.inside_building_id = -1
	if character_id != state.player_id:
		var npc := spawn_character(character_id)
		if npc:
			npc.teleport(c.position)
		return
	var me := player_npc()
	if me == null:
		me = spawn_character(character_id)
	if me:
		me.visible = true
		me.teleport(c.position)
		me.set_inside(false)
	if heir_ctl:
		set_view_mode("walk", true)
	else:
		_setup_heir()


## Away from the village: on a journey or riding with the warband.
func heir_away() -> bool:
	return state.player() != null and state.player().is_away()


## Gives a character who joined the village (a settler) a body and a brain.
func spawn_character(character_id: int) -> NPC:
	var c := state.get_character(character_id)
	if c == null or npcs.has(character_id) or (LifeSystem.is_unseen(c) and not state.is_player(c)) or (c.is_away() and not state.is_player(c)):
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
	set_view_mode("overview")
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


## Petitions the Crown for the next charter (Build panel). On success the
## new banners go up around the square.
func petition_charter() -> void:
	var result := CharterSystem.petition(state)
	if not result["ok"]:
		Audio.play("ui_error")
		Game.notify.emit(str(result["text"]), Game.COLOR_BAD)
		return
	builder.refresh_props()
	builder.refresh_fields()
	builder.refresh_square()
	Audio.play(str(CharterSystem.cfg().get("ceremony", {}).get("sound", "knighted")))
	Game.notify.emit(str(result["text"]), Game.COLOR_TALENT)
	territory_changed.emit()
	if ui:
		ui.refresh()


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
		set_view_mode("overview")
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
	if target != null and mode == "walk" and target == player_npc():
		target = null
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


## Right click (with "Click to move" on in the settings): the heir walks
## there along the roads, or up to the person clicked.
func _on_right_clicked(screen_pos: Vector2) -> void:
	if mode != "walk" or heir_ctl == null or is_placing() or talking_to >= 0 or not GameSettings.click_to_move():
		return
	var npc := pick_npc(screen_pos)
	if npc and npc != player_npc():
		heir_ctl.walk_to(npc.global_position, float(Discovery.scan_config().get("talk_range", 3.0)) * 0.6)
		Audio.play("ui_tick")
		return
	var g: Variant = camera_rig.ground_point(screen_pos)
	if g != null:
		heir_ctl.walk_to(g)
		Audio.play("ui_tick")


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


## Buildings between the camera and the heir fade so the heir is never
## hidden (on foot only; the map table looks from high above).
func _update_fades() -> void:
	var want := {}
	if mode == "walk" and camera_rig.camera:
		var to := camera_rig.camera.global_position
		var from := camera_rig.focus_point()
		for b in state.layout.buildings:
			if _segment_hits_building(b, from, to) < 1.0:
				want[b.id] = true
	var alpha := float(StrategyCamera.cfg().get("fade_alpha", 0.72))
	for id: int in want:
		if not _faded.has(id):
			_fade_building(id, alpha)
	for id: int in _faded.keys():
		if not want.has(id):
			_fade_building(id, 0.0)
	_faded = want


func _fade_building(building_id: int, amount: float) -> void:
	var node: Node3D = builder.building_nodes.get(building_id, null)
	if node == null:
		return
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		var tw := gi.create_tween()
		tw.tween_property(gi, "transparency", amount, 0.25)


func is_faded(building_id: int) -> bool:
	return _faded.has(building_id)


## How far along from-to (0..1) a building's box is hit (1.0 = missed).
func _segment_hits_building(b: BuildingData, from: Vector3, to: Vector3) -> float:
	var length := from.distance_to(to)
	if length < 0.01:
		return 1.0
	var mid := (from + to) * 0.5
	if Vector2(b.position.x - mid.x, b.position.z - mid.z).length() > b.footprint.length() * 0.5 + 1.0 + length * 0.5:
		return 1.0
	var inv := b.basis().inverse()
	var base := TerrainHeight.on_ground(b.position)
	var a := inv * (from - base)
	var z := inv * (to - base)
	var box := AABB(Vector3(-b.footprint.x * 0.5 - 0.3, -1.0, -b.footprint.y * 0.5 - 0.3), Vector3(b.footprint.x + 0.6, building_height(b) + 1.5, b.footprint.y + 0.6))
	var hit: Variant = box.intersects_segment(a, z)
	return 1.0 if hit == null else a.distance_to(hit) / length


## How far along the line from `from` to `to` (0..1) the first building
## stands in the way, or 1.0 when the view is clear (the follow camera).
func view_blocked_at(from: Vector3, to: Vector3) -> float:
	var best := CastleSystem.view_blocked_at(state, from, to)
	for b in WorldGeometry.solid_buildings(state):
		best = minf(best, _segment_hits_building(b, from, to))
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
		if mode == "overview":
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
	if mode == "overview":
		camera_rig.follow_target = null
	selection_changed.emit(null)
	if selected_building >= 0:
		selected_building = -1
		_show_selection_frame()
		building_selected.emit(-1)


## Moves the camera to a character (following them if they are outdoors).
## Finding someone far away is done on the map table; your own heir is
## found by stepping back into their boots.
func focus_on(character_id: int) -> void:
	var npc := npc_of(character_id)
	if npc == null:
		return
	if character_id == state.player_id and heir_ctl:
		set_view_mode("walk")
		return
	set_view_mode("overview")
	if npc.visible:
		camera_rig.follow_target = npc
		camera_rig.look_at_point(npc.global_position, minf(camera_rig._target_distance, 28.0))
	else:
		var b := state.get_building(npc.character.inside_building_id)
		camera_rig.follow_target = null
		camera_rig.look_at_point(b.position if b else npc.global_position, 32.0)


# --- Walking as the heir ---------------------------------------------------------------------

func player_npc() -> NPC:
	return npc_of(state.player_id)


func _setup_heir() -> void:
	var heir := player_npc()
	if heir == null:
		set_view_mode("overview", true)
		return
	heir.brain.set_errand({})
	heir_ctl = HeirController.new(self, heir)
	set_view_mode("walk", true)


## You go on as `character_id` (Succession.pass_on): the old body is let
## go (it leaves with the death's "gone"), the new one is yours, on foot.
func take_over(character_id: int) -> void:
	end_conversation()
	if heir_ctl and is_instance_valid(heir_ctl.npc):
		heir_ctl.npc.driven = false
		heir_ctl.npc.set_player_marker(false)
	heir_ctl = null
	var npc := npc_of(character_id)
	if npc == null:
		npc = spawn_character(character_id)
	if npc == null:
		set_view_mode("overview", true)
		return
	npc.set_player_marker(true)
	npc.brain.set_errand({})
	heir_ctl = HeirController.new(self, npc)
	if mode == "walk":
		set_view_mode("walk", true)
	player_changed.emit(character_id)
	if ui:
		ui.refresh()


## The house is ended: time stops and the game says so.
func _end_house(text: String) -> void:
	end_conversation()
	heir_ctl = null
	set_view_mode("overview", true)
	paused = true
	speed_changed.emit(time_scale())
	house_ended.emit(text)


## "walk" (as the heir) or "overview" (the map table). Leaving the map
## table always puts you back in the heir's boots.
func set_view_mode(new_mode: String, force: bool = false) -> void:
	if new_mode == "walk" and heir_ctl == null:
		new_mode = "overview"
	if new_mode == mode and not force:
		return
	var heir := player_npc()
	if new_mode == "overview":
		end_conversation()
		hush_remarks()
		_set_focus(null)
		if heir_ctl:
			heir_ctl.cancel_auto_walk()
		camera_rig.set_mode("strategy")
		if heir:
			camera_rig.look_at_point(heir.global_position, -1.0, force)
	else:
		cancel_placing()
		camera_rig.set_mode("follow", heir)
		camera_rig.look_at_point(heir.global_position, -1.0, true)
	mode = new_mode
	if heir:
		# On foot the camera finds you; the crest is for the map table.
		heir.show_crest(mode == "overview")
	mode_changed.emit(mode)


## Trying to walk while the game is paused: say why nothing happens.
func _hint_paused() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _paused_hint_at > 6.0:
		_paused_hint_at = now
		Game.notify.emit("The game is paused. Press %s to walk on." % key_hint("toggle_pause"), Game.COLOR_INFO)


## How to press an action on the device in use ("E", "A"...).
func key_hint(action: String) -> String:
	return InputSetup.key_name(action, ui != null and ui.using_pad())


func toggle_overview() -> void:
	set_view_mode("walk" if mode == "overview" else "overview")
	Audio.play("ui_select")


## Who the heir is looking at: someone in reach and in sight, in front of
## them. The person under the mouse wins; the one in focus, and someone you
## just looked at with the Eye, are kept a little longer so focus doesn't
## flicker between neighbours.
func _update_focus() -> void:
	var heir := player_npc()
	if heir == null:
		return
	var sc := Discovery.scan_config()
	var reach := float(sc.get("range", 10.0))
	var cone := deg_to_rad(float(sc.get("focus_cone", 75.0)))
	var keep := float(sc.get("keep_bonus", 1.5))
	var from := heir.global_position
	if hovered and hovered != heir and _in_sight(from, hovered, reach):
		_set_focus(hovered)
		return
	var preferred := npc_of(_preferred_focus)
	if preferred and from.distance_to(preferred.global_position) > reach * 2.0:
		_preferred_focus = -1
	var facing := Vector3(-sin(heir.rotation.y), 0, -cos(heir.rotation.y))
	var ranked: Array = []
	for npc: NPC in npcs.values():
		if npc == heir or not npc.visible:
			continue
		var to := npc.global_position - from
		to.y = 0.0
		var d := to.length()
		if d > reach or d < 0.01:
			continue
		var ang := facing.angle_to(to / d)
		var kept := npc == focus or npc.character.id == _preferred_focus
		if ang > (cone * 1.5 if kept else cone):
			continue
		var score := d + ang * 3.0 - (keep if kept else 0.0)
		ranked.append([score, npc])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var best: NPC = null
	for r: Array in ranked:
		if not WorldGeometry.line_blocked(state, from, (r[1] as NPC).global_position):
			best = r[1]
			break
	_set_focus(best)


func _in_sight(from: Vector3, npc: NPC, reach: float) -> bool:
	return npc.visible and Vector2(npc.global_position.x - from.x, npc.global_position.z - from.z).length() <= reach \
		and not WorldGeometry.line_blocked(state, from, npc.global_position)


func _set_focus(npc: NPC) -> void:
	if npc == focus:
		return
	if focus and is_instance_valid(focus):
		focus.set_focused(false)
	focus = npc
	if focus:
		focus.set_focused(true)
	focus_changed.emit(focus.character.id if focus else -1)


## Can the heir talk with them right now?
func talk_check(character_id: int) -> Dictionary:
	var c := state.get_character(character_id)
	var heir := player_npc()
	var target := npc_of(character_id)
	if c == null or heir == null or target == null:
		return {"ok": false, "reason": ""}
	if mode != "walk":
		return {"ok": false, "reason": "Step down from the map table first (%s)." % key_hint("toggle_overview")}
	return Discovery.talk_check(state, heir.global_position, c, target.global_position)


## Can the heir look at them with the Eye right now?
func scan_check(character_id: int) -> Dictionary:
	var c := state.get_character(character_id)
	var heir := player_npc()
	var target := npc_of(character_id)
	if c == null or heir == null or target == null:
		return {"ok": false, "reason": ""}
	if mode != "walk":
		return {"ok": false, "reason": "The Eye works face to face: step down from the map table (%s) and walk over." % key_hint("toggle_overview")}
	return Discovery.scan_check(state, heir.global_position, c, target.global_position)


## Starts a conversation with someone the heir is standing beside (E).
## Returns false (and says why) when they're too far.
func try_talk(character_id: int) -> bool:
	var check := talk_check(character_id)
	if not check["ok"]:
		if not str(check["reason"]).is_empty():
			Audio.play("ui_error")
			Game.notify.emit(str(check["reason"]), Game.COLOR_INFO)
		return false
	if talking_to >= 0:
		end_conversation()
	var heir := player_npc()
	var target := npc_of(character_id)
	heir_ctl.cancel_auto_walk()
	target.brain.set_errand({"type": "hold", "face": heir.global_position})
	heir.face_point(target.global_position)
	heir.set_anim("talk")
	talking_to = character_id
	hush_remarks()
	_set_focus(target)
	var cam_cfg := StrategyCamera.cfg()
	camera_rig.close_in(float(cam_cfg.get("talk_distance", 7.0)), float(cam_cfg.get("talk_shift", -1.15)))
	var result := Discovery.meet(state, target.character)
	Audio.play("card_open")
	conversation_started.emit(character_id, result)
	court_changed(character_id)
	return true


## Someone joined (Recruitment.accept): their family may have moved home
## and their work changed, so everyone affected re-plans their day.
func recruited(character_id: int) -> void:
	var c := state.get_character(character_id)
	if c == null:
		return
	for p in state.residents_of(c.home_building_id):
		var npc := npc_of(p.id)
		if npc and npc.brain and p.id != state.player_id:
			npc.brain.replan()
	court_changed(character_id)


## Ends the conversation; they go back to their day.
func end_conversation() -> void:
	if talking_to < 0:
		return
	var target := npc_of(talking_to)
	if target:
		target.brain.set_errand({})
	var heir := player_npc()
	if heir:
		heir.face_point(null)
		heir.set_anim("idle")
	talking_to = -1
	camera_rig.restore_view()
	conversation_ended.emit()


func is_revealing() -> bool:
	return _reveal != null and is_instance_valid(_reveal)


## Looks at someone with the Sovereign's Eye (Q): they must be near and in
## sight. The full reveal the first time, a quick card after that.
func use_eye(character_id: int) -> void:
	var c := state.get_character(character_id)
	if c == null or is_revealing():
		return
	var check := scan_check(character_id)
	if not check["ok"]:
		Audio.play("ui_error")
		Game.notify.emit(str(check["reason"]), Game.COLOR_BAD)
		return
	var heir := player_npc()
	var target := npc_of(character_id)
	if heir and target and talking_to < 0:
		heir.face_point(target.global_position)
	_preferred_focus = character_id
	var first := not c.appraised
	hush_remarks()
	_reveal = EyeReveal.new()
	add_child(_reveal)
	_reveal.finished.connect(_on_reveal_finished.bind(c.id, first))
	_reveal.play(self, c, not first)
	appraise(c)


func _on_reveal_finished(action: String, character_id: int, first: bool) -> void:
	_reveal = null
	if mode == "walk":
		# The reveal may have moved the camera: back to the heir.
		camera_rig.follow_target = player_npc()
		if talking_to < 0:
			player_npc().face_point(null)
	var c := state.get_character(character_id)
	if c == null:
		return
	if first and Appraisal.is_exceptional(c):
		var best := c.best_attribute()
		var p := c.get_potential(best)
		Game.notify.emit("Exceptional talent discovered! %s - %s %s (%d)" % [
			c.full_name(), GameData.attribute_def(best).get("name", best), Appraisal.rank_id(p), p], Game.COLOR_TALENT)
	match action:
		"talk":
			if talking_to != character_id:
				if talk_check(character_id)["ok"]:
					try_talk(character_id)
				else:
					Game.notify.emit("Walk up to %s and press %s to talk." % [c.first_name, key_hint("interact")], Game.COLOR_INFO)
		"appoint":
			select_character(character_id)
			ui.show_card_tab("court")
		"card":
			select_character(character_id)
	if ui:
		ui.refresh()


## Marks a person appraised (their gifts are now known to the player).
func appraise(c: CharacterData) -> void:
	if c.appraised:
		return
	c.appraised = true


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
			Game.notify.emit("No quicksave yet (press %s to quicksave)." % InputSetup.key_name("quicksave", false), Game.COLOR_BAD)
	elif event.is_action_pressed("toggle_overview"):
		if not is_placing():
			toggle_overview()
	elif event.is_action_pressed("sovereign_eye") and mode == "walk":
		if talking_to >= 0:
			use_eye(talking_to)
		elif focus:
			use_eye(focus.character.id)
		else:
			Audio.play("ui_error")
			Game.notify.emit("Look at someone near you to use the Sovereign's Eye.", Game.COLOR_INFO)
	elif event.is_action_pressed("interact") and mode == "walk" and battle and battle.heir_strike():
		pass
	elif event.is_action_pressed("interact") and mode == "walk":
		if talking_to < 0 and focus:
			try_talk(focus.character.id)
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


## A game loaded with you away (it can't be saved so; a safeguard): you're
## home, whatever was left at the seat.
func _home_from_away() -> void:
	var events: Array[Dictionary] = []
	if not state.realm.trip.is_empty():
		Realm.come_home(state, events)
	var me := state.player()
	if me and me.is_away():
		me.away_at = ""
		me.away_until = -1
		if not state.military.expedition.is_empty():
			state.military.expedition["heir"] = false
		events.append({"text": "", "back": [me.id]})
	apply_life_events(events)


## Writes live NPC positions back into the WorldState before saving.
func sync_to_state() -> void:
	for npc: NPC in npcs.values():
		npc.sync_to_data()
