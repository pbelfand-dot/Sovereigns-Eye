extends Node
## Renders a set of screenshots for review (main menu, village overview,
## character card tabs, ledger, night). Needs a real display/GPU (not
## --headless).
##
##   godot --path . res://tools/capture.tscn -- <seed> <output_dir> [court|art|menus|build]
##
## "court" skips the village tour and only renders the Phase 2 screens
## (recruit view, retainer view, court panel, player card, a month later),
## which is much faster on software renderers. "art" only renders the
## village overview, the square, a meadow close-up and a forest edge (for
## art changes). "build" renders Phase 3: building sites at several stages,
## a finished farmstead, the Build panel and a placement preview.

var out_dir := "user://captures"
var seed_text := "12345"
var court_only := false
var art_only := false
var menus_only := false
var build_only := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_text = args[0]
	if args.size() > 1:
		out_dir = args[1]
	court_only = args.has("court")
	art_only = args.has("art")
	menus_only = args.has("menus")
	build_only = args.has("build")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(file_name))
	print("saved %s  (primitives %d, draw calls %d, objects %d)" % [out_dir.path_join(file_name),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	if menus_only:
		await _menu_shots()
		get_tree().quit()
		return
	if build_only:
		await _build_shots()
		get_tree().quit()
		return
	if court_only:
		Game.state = WorldGenerator.generate(seed_text)
		Game.state.minutes += 6.0 * 60.0  # early afternoon: people at work
		var court_world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
		add_child(court_world)
		await _wait(5)
		court_world.paused = true
		await _court_shots(court_world)
		get_tree().quit()
		return
	if not art_only:
		var menu: Control = load("res://scenes/main/main.tscn").instantiate()
		add_child(menu)
		await _wait(10)
		await _shot("01_main_menu.png")
		menu.queue_free()

	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 2.5 * 60.0  # mid-morning
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.set_speed(3)
	for i in 300:
		world._process(0.1)
	world.set_speed(0)
	world.camera_rig.set_yaw(0.5, true)
	world.camera_rig.look_at_point(Vector3(0, 0, -8), 105.0, true)
	await _wait(20)
	await _shot("02_village_overview.png")

	world.camera_rig.set_yaw(-0.4, true)
	world.camera_rig.look_at_point(Vector3(2, 0, 4), 34.0, true)
	await _wait(20)
	await _shot("03_town_square.png")
	if art_only:
		world.camera_rig.set_yaw(1.1, true)
		world.camera_rig.look_at_point(Vector3(30, 0, 22), 22.0, true)
		await _wait(20)
		await _shot("03b_meadow.png")
		world.camera_rig.set_yaw(-2.2, true)
		world.camera_rig.look_at_point(Vector3(-62, 0, -48), 30.0, true)
		await _wait(20)
		await _shot("03c_forest_edge.png")
		var stalls := Game.state.layout.props_of_type("stall")
		if not stalls.is_empty():
			var at: Vector3 = stalls[0]["pos"]
			world.camera_rig.set_yaw(float(stalls[0]["rot"]) + PI, true)
			world.camera_rig.look_at_point(at, 11.0, true)
			await _wait(20)
			await _shot("03d_market_stall.png")
		for type: String in ["smithy", "tavern"]:
			var list := Game.state.layout.buildings_of_type(type)
			if list.is_empty():
				continue
			var b: BuildingData = list[0]
			world.camera_rig.set_yaw(b.rotation + 0.5, true)
			world.camera_rig.look_at_point(b.position + b.forward() * 3.0, 20.0, true)
			await _wait(20)
			await _shot("03e_%s.png" % type)
		get_tree().quit()
		return

	# Pick the most talented villager who is outdoors, and appraise them.
	var best: NPC = null
	for npc: NPC in world.npcs.values():
		if npc.visible and (best == null or npc.character.best_potential() > best.character.best_potential()):
			best = npc
	if best:
		world.paused = true
		world.select_character(best.character.id, true)
		world.camera_rig.look_at_point(best.global_position, 16.0, true)
		await _wait(30)
		await _shot("04_card_appraisal.png")
		var tabs := world.ui._card._tabs
		var tab_names := ["", "court", "personality", "relationships", "history"]
		for t in range(1, 5):
			tabs.current_tab = t
			await _wait(8)
			await _shot("04_card_tab_%s.png" % tab_names[t])
		tabs.current_tab = 0

	for c in world.state.characters:
		if Seeds.derive(1, str(c.id)) % 3 == 0:
			c.appraised = true
	world.deselect()
	world.ui.toggle_ledger()
	await _wait(10)
	await _shot("08_ledger.png")
	world.ui.toggle_ledger()

	await _court_shots(world)

	world.state.minutes += 12.0 * 60.0
	world.camera_rig.look_at_point(Vector3(0, 0, 0), 60.0, true)
	await _wait(20)
	await _shot("09_night.png")

	world.ui.open_pause_menu()
	await _wait(5)
	await _shot("10_pause_menu.png")
	get_tree().quit()


## Phase 2: recruit the best prospects, give them offices, show the court,
## the player's own card, then a month of training.
func _court_shots(world: VillageWorld) -> void:
	var st := world.state
	var people := st.characters.duplicate()
	people.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.best_potential() > b.best_potential())
	var office_for := {"administration": "steward", "leadership": "marshal", "combat": "marshal", "politics": "chancellor", "intelligence": "scholar"}
	var recruited: Array[CharacterData] = []
	for c: CharacterData in people:
		if recruited.size() >= 3:
			break
		if not CourtSystem.recruit_check(st, c)["ok"]:
			continue
		c.appraised = true
		CourtSystem.try_recruit(st, c, 0.0)
		var office := str(office_for.get(CourtSystem.focus_of(c), "steward"))
		if c.age >= 16 and st.house.holder_of(office) < 0:
			CourtSystem.appoint(st, office, c)
		world.court_changed(c.id)
		recruited.append(c)
	# A prospect who hasn't joined yet: the recruit view with its odds.
	for c: CharacterData in people:
		if not c.retainer and CourtSystem.recruit_check(st, c)["ok"]:
			c.appraised = true
			world.select_character(c.id, true)
			world.ui._card._tabs.current_tab = 1
			await _wait(20)
			await _shot("11_court_recruit.png")
			break
	if not recruited.is_empty():
		world.select_character(recruited[0].id, true)
		world.ui._card._tabs.current_tab = 1
		await _wait(20)
		await _shot("12_court_retainer.png")
	world.deselect()
	world.ui.toggle_court()
	await _wait(10)
	await _shot("13_court_panel.png")
	world.ui.toggle_court()
	if st.player():
		world.select_character(st.player_id, true)
		world.ui._card._tabs.current_tab = 1
		await _wait(20)
		await _shot("14_player_card.png")
		# The crest over your own character, from the normal strategy distance.
		world.deselect()
		var you := world.npc_of(st.player_id)
		if you and you.visible:
			world.camera_rig.look_at_point(you.global_position, 45.0, true)
			# Park the mouse in a corner so the hover label doesn't cover the crest.
			get_viewport().warp_mouse(Vector2(4, get_viewport().get_visible_rect().size.y - 4))
			await _wait(20)
			await _shot("14b_player_crest.png")
	# A month passes: retainers train toward their potential.
	for i in 30:
		st.minutes += Calendar.MINUTES_PER_DAY
		world._check_new_day()
	if not recruited.is_empty():
		world.select_character(recruited[0].id, true)
		world.ui._card._tabs.current_tab = 1
	await _wait(20)
	await _shot("15_after_a_month.png")
	world.deselect()


## Main menu Sound panel and the in-game pause menu (volume sliders).
func _menu_shots() -> void:
	var menu: Control = load("res://scenes/main/main.tscn").instantiate()
	add_child(menu)
	await _wait(10)
	menu.call("_show_sound")
	await _wait(5)
	await _shot("16_menu_sound.png")
	menu.queue_free()
	Game.state = WorldGenerator.generate(seed_text)
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui.open_pause_menu()
	await _wait(5)
	await _shot("17_pause_sound.png")



## Phase 3: orders a Stonecutter's Yard, a Woodcutters' Lodge, a Granary and a
## Farmstead beside the roads, shows them at different stages, finishes the
## farm, then the Build panel and a placement preview.
func _build_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 4.0 * 60.0  # late morning: crews at work
	var st := Game.state
	st.house.gold = 2000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 600.0
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	var plan := [["quarry", 0.05], ["workshop", 0.4], ["storehouse", 0.75], ["farmhouse", 1.0]]
	var sites: Array[ConstructionSite] = []
	for entry: Array in plan:
		var spot := TerritorySystem.find_spot(st, str(entry[0]), 18.0, 70.0)
		if spot.is_empty():
			print("no spot for ", entry[0])
			continue
		var res := world.place_building(str(entry[0]), spot["pos"], spot["rot"])
		if res["ok"]:
			var site: ConstructionSite = res["site"]
			site.work_done = site.work_needed * float(entry[1]) - 0.001
			sites.append(site)
	world.builder.update_sites()
	# Let the crews walk over to their sites.
	world.set_speed(1)
	for i in 240:
		world._process(0.1)
	world.set_speed(0)
	world.paused = true
	for site in sites.duplicate():
		if not st.territory.sites.has(site):
			sites.erase(site)
		elif site.progress() >= 0.99:
			site.work_done = site.work_needed
			world._finish_site(site)
			sites.erase(site)
	world.builder.update_sites()
	await _wait(5)
	var center := Vector3.ZERO
	for site in sites:
		center += site.building.position
	if not sites.is_empty():
		center /= sites.size()
	world.camera_rig.set_yaw(0.4, true)
	world.camera_rig.look_at_point(center, 95.0, true)
	await _wait(20)
	await _shot("20_build_overview.png")
	for i in sites.size():
		var b := sites[i].building
		world.camera_rig.set_yaw(b.rotation + 0.6, true)
		world.camera_rig.look_at_point(b.position, 24.0, true)
		await _wait(20)
		await _shot("21_site_%d_%s.png" % [roundi(sites[i].progress() * 100.0), b.type])
	for id in st.territory.built:
		var b := st.get_building(id)
		if b and b.type == "farmhouse":
			world.camera_rig.set_yaw(b.rotation + 0.7, true)
			world.camera_rig.look_at_point(b.position, 42.0, true)
			await _wait(20)
			await _shot("22_new_farmstead.png")
	world.camera_rig.set_yaw(0.4, true)
	world.camera_rig.look_at_point(center, 70.0, true)
	world.ui.toggle_build()
	await _wait(10)
	await _shot("23_build_panel.png")
	world.ui.toggle_build()
	# Placement preview: a valid spot, then a blocked one.
	var spot := TerritorySystem.find_spot(st, "bakery", 20.0, 80.0)
	if not spot.is_empty():
		world.set_process(false)
		world.start_placing("bakery")
		world.preview_at(spot["pos"])
		world.camera_rig.set_yaw(0.3, true)
		world.camera_rig.look_at_point(spot["pos"], 30.0, true)
		await _wait(20)
		await _shot("24_place_ok.png")
		var smithy := st.layout.buildings_of_type("smithy")[0]
		world.preview_at(smithy.position)
		world.camera_rig.look_at_point(smithy.position, 30.0, true)
		await _wait(20)
		await _shot("25_place_blocked.png")
		world.cancel_placing()
