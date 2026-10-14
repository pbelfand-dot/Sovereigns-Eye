extends Node
## Renders a set of screenshots for review (main menu, village overview,
## character card tabs, ledger, night). Needs a real display/GPU (not
## --headless).
##
##   godot --path . res://tools/capture.tscn -- <seed> <output_dir> [court|art]
##
## "court" skips the village tour and only renders the Phase 2 screens
## (recruit view, retainer view, court panel, player card, a month later),
## which is much faster on software renderers. "art" only renders the
## village overview, the square, a meadow close-up and a forest edge (for
## art changes).

var out_dir := "user://captures"
var seed_text := "12345"
var court_only := false
var art_only := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_text = args[0]
	if args.size() > 1:
		out_dir = args[1]
	court_only = args.has("court")
	art_only = args.has("art")
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

