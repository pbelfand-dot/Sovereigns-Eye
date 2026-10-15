extends Node
## A short scripted look at charters, for review videos: a village that has
## earned its next charter (played forward by a steward bot first), the
## Charter checklist, the petition to the Crown, banners going up, and a
## Market Hall placed, built and staffed by merchants.
##
##   godot --path . --resolution 1280x720 --write-movie out.avi --fixed-fps 30 \
##     res://tools/charter_demo.tscn -- <seed>

var world: VillageWorld
var _keys: Label
var _note: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if not args.is_empty() else "12345"
	GameSettings.memory_only = true
	var st := WorldGenerator.generate(seed_text)
	TerritorySystem.initialize(st)
	_play_forward(st)
	st.minutes = floorf(st.minutes / Calendar.MINUTES_PER_DAY) * Calendar.MINUTES_PER_DAY + 11.0 * 60.0
	Game.state = st
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_keys = _caption(layer, 100.0, 24)
	_note = _caption(layer, 134.0, 17)
	_run.call_deferred()


func _caption(layer: CanvasLayer, top: float, size: int) -> Label:
	var l := UITheme.label("", size, UITheme.ACCENT, size > 18)
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.offset_left = -620.0
	l.offset_right = -18.0
	l.offset_top = top
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.95))
	layer.add_child(l)
	return l


func _say(keys: String, note: String = "") -> void:
	_keys.text = keys
	_note.text = note


func _wait(seconds: float) -> void:
	for i in maxi(1, roundi(seconds * 30.0)):
		await get_tree().process_frame


## Plays the village forward (data only) until it has earned a Market Town
## charter, petitioning for the Village charter on the way.
func _play_forward(st: WorldState) -> void:
	for office: String in ["chancellor", "steward"]:
		var attr := str(CourtSystem.office_def(office).get("primary", "politics"))
		var best: CharacterData = null
		for c in st.characters:
			if c.age >= 18 and Recruitment.eligible(st, c)["ok"] and (best == null or c.get_current(attr) > best.get_current(attr)):
				best = c
		if best:
			Recruitment.accept(st, best, {"wage": 3, "position": "office", "office": office})
	for d in 160:
		for k in 48:
			st.minutes += 30.0
			for s in TerritorySystem.advance(st, 30.0):
				TerritorySystem.complete(st, s)
		var day := Calendar.day_index(st.whole_minutes())
		var rng := Seeds.rng(st.world_seed, "day_%d" % day)
		for c in st.characters:
			MoodSystem.daily_update(c, st, rng)
		CourtSystem.daily_update(st, Seeds.rng(st.world_seed, "court_day_%d" % day))
		TerritorySystem.daily_update(st)
		GrowthSystem.daily_update(st)
		if st.territory.sites.size() < 3:
			if GrowthSystem.food_days(st) < 8.0:
				_try(st, "farmhouse")
			elif st.territory.amount("stone") < 80.0 and TerritorySystem.count_built(st, "quarry") < 2:
				_try(st, "quarry")
			else:
				for type: String in ["bakery", "storehouse", "tavern", "chapel"]:
					if TerritorySystem.count_built(st, type) == 0 and _try(st, type):
						break
		if CharterSystem.current(st) == 0:
			CharterSystem.petition(st)
		elif CharterSystem.can_petition(st)["ok"] and st.territory.sites.is_empty():
			break
	# Nobody walked during the fast-forward: start everyone at home, so the
	# village wakes up spread out rather than at the edge of the map.
	for c in st.characters:
		var home := st.get_building(c.home_building_id)
		if home and not st.is_player(c):
			c.position = TerrainHeight.on_ground(home.door_position())
			c.inside_building_id = home.id
	print("charter_demo: day %d, %s, %d people, can petition: %s" % [st.day(), CharterSystem.title(st), st.characters.size(), CharterSystem.can_petition(st)])


func _try(st: WorldState, type: String) -> bool:
	if not TerritorySystem.can_build(st, type)["ok"]:
		return false
	var spot := TerritorySystem.find_spot(st, type)
	return not spot.is_empty() and bool(TerritorySystem.place(st, type, spot["pos"], spot["rot"])["ok"])


func _run() -> void:
	await _wait(0.3)
	var st := world.state
	world.ui._help.visible = false
	world.set_view_mode("overview", true)
	world.camera_rig.set_yaw(0.5, true)
	world.camera_rig.look_at_point(st.layout.square_center + Vector3(0, 0, 4), 70.0, true)
	_say("Tab  -  the map table", "%s has grown into a busy village." % st.village_name)
	await _wait(3.0)
	_say("B  -  Build panel", "The Charter: what the Crown asks for a Market Town.")
	world.ui.toggle_build()
	await _wait(4.0)
	_say("Petition the Crown", "Every requirement met, the fee paid.")
	await _wait(1.2)
	world.petition_charter()
	world.ui.toggle_build()
	world.camera_rig.look_at_point(st.layout.square_center, 34.0)
	_say("", "A Market Town: banners go up around the square.")
	await _wait(4.0)
	world.ui.toggle_build()
	_say("Market Hall", "Now unlocked: a hall where merchants trade.")
	await _wait(2.5)
	world.ui.toggle_build()
	var spot := TerritorySystem.find_spot(st, "market", 20.0)
	if spot.is_empty():
		push_error("charter_demo: no spot for the Market Hall")
		get_tree().quit(1)
		return
	world.start_placing("market")
	world.camera_rig.look_at_point(spot["pos"], 40.0)
	await _wait(1.5)
	var from: Vector3 = spot["pos"] + Vector3(8, 0, 6)
	for i in 30:
		world.preview_at(from.lerp(spot["pos"], i / 29.0))
		await _wait(1.0 / 30.0)
	_say("Click  -  place it", "Beside a road; a lane is laid to its door.")
	await _wait(1.2)
	world.confirm_placement()
	world.cancel_placing()
	var site: ConstructionSite = null
	for s in st.territory.sites:
		if s.building.type == "market":
			site = s
	world.camera_rig.set_yaw(world.camera_rig._target_yaw + 0.4)
	world.camera_rig.look_at_point(spot["pos"], 26.0)
	_say("", "Villagers raise it: scaffold, walls, roof.")
	if site:
		for i in 150:
			site.work_done = minf(site.work_needed * (i + 1) / 150.0, site.work_needed - 0.01)
			world.builder.update_sites()
			await _wait(1.0 / 30.0)
		site.work_done = site.work_needed
		world._finish_site(site)
	_say("", "Finished: two merchants take up trade there.")
	world.set_speed(3)
	await _wait(5.0)
	world.set_speed(0)
	world.ui.toggle_build()
	_say("", "Trade and dues: gold every day, and room for 150 people.")
	await _wait(4.0)
	world.ui.toggle_build()
	_say("", "")
	await _wait(0.5)
	get_tree().quit()
