extends Node
## Renders a set of screenshots for review (main menu, village overview,
## character card tabs, ledger, night). Needs a real display/GPU (not
## --headless).
##
##   godot --path . res://tools/capture.tscn -- <seed> <output_dir> [court|art|menus|build|growth|charter|talk]
##
## "court" skips the village tour and only renders the Phase 2 screens
## (recruit view, retainer view, court panel, player card, a month later),
## which is much faster on software renderers. "art" only renders the
## village overview, the square, a meadow close-up and a forest edge (for
## art changes). "build" renders Phase 3: building sites at several stages,
## a finished farmstead, the Build panel and a placement preview. "growth"
## renders step 2: the village at the start and after 45 simulated days,
## a home being upgraded, home levels, a building card and settlers arriving.
## "talk" renders a conversation on foot: the offer terms, a refusal with
## the terms still open, and the better offer that is accepted.

var out_dir := "user://captures"
var seed_text := "12345"
var court_only := false
var art_only := false
var menus_only := false
var build_only := false
var growth_only := false
var charter_only := false
var talk_only := false
var commons_only := false


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
	growth_only = args.has("growth")
	charter_only = args.has("charter")
	talk_only = args.has("talk")
	commons_only = args.has("commons")
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
	if growth_only:
		await _growth_shots()
		get_tree().quit()
		return
	if charter_only:
		await _charter_shots()
		get_tree().quit()
		return
	if talk_only:
		await _talk_shots()
		get_tree().quit()
		return
	if commons_only:
		await _commons_shots()
		get_tree().quit()
		return
	if court_only:
		Game.state = WorldGenerator.generate(seed_text)
		Game.state.minutes += 6.0 * 60.0  # early afternoon: people at work
		var court_world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
		add_child(court_world)
		await _wait(5)
		court_world.set_view_mode("overview", true)
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
	world.set_view_mode("overview", true)
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
		# As if the heir had talked to them and used the Eye already.
		best.character.met = true
		best.character.appraised = true
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
		if not Recruitment.eligible(st, c)["ok"]:
			continue
		c.appraised = true
		Recruitment.accept(st, c, {"wage": 3, "position": "household"})
		var office := str(office_for.get(CourtSystem.focus_of(c), "steward"))
		if c.age >= 16 and st.house.holder_of(office) < 0:
			CourtSystem.appoint(st, office, c)
		world.court_changed(c.id)
		recruited.append(c)
	# A prospect who hasn't joined yet: the recruit view with its odds.
	for c: CharacterData in people:
		if not c.retainer and Recruitment.eligible(st, c)["ok"]:
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


## The Village Commons in the game, for every charter: the square from the
## map table, the well on foot with the real follow camera, 3/4 views from
## front and back with the heir beside it for scale, a close look, the
## charter banners and a signpost. Files: commons_<tier>_<view>.png
func _commons_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.5 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	var c := st.layout.square_center
	var heir := world.player_npc()
	var signs := st.layout.props_of_type("signpost")
	# No toasts over the art (the welcome tip, charter news).
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	# COMMONS_TIERS=3 (comma list) renders only those charters.
	var only := OS.get_environment("COMMONS_TIERS").split(",", false)
	for tier in CharterSystem.tiers().size():
		if tier > 0:
			CharterSystem.raise_banners(st, int(CharterSystem.tier_def(tier).get("banners", 0)) - int(CharterSystem.tier_def(tier - 1).get("banners", 0)))
		st.territory.charter = tier
		if not only.is_empty() and not str(tier) in only:
			continue
		world.builder.refresh_props()
		world.territory_changed.emit()
		var tag := "commons_%d_" % tier
		# The square from the map table.
		world.set_view_mode("overview", true)
		heir.teleport(c + Vector3(1.7, 0, 0.9))
		heir.rotation.y = 0.9
		world.camera_rig.set_yaw(0.6, true)
		world.camera_rig.look_at_point(c, 30.0, true)
		await _wait(5)
		await _shot(tag + "square.png")
		# 3/4 views from front and back, heir beside the well for scale.
		for v: Array in [["front34", 0.55], ["rear34", 0.55 + PI]]:
			world.camera_rig.set_yaw(float(v[1]), true)
			world.camera_rig.look_at_point(c, 9.5, true)
			await _wait(4)
			await _shot(tag + str(v[0]) + ".png")
		# On foot with the real follow camera: walking up to the well.
		world.set_view_mode("walk", true)
		var approach := c + Vector3(3.0, 0, 3.6)
		heir.teleport(approach)
		var to := c - approach
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y, true)
		world.camera_rig.look_at_point(heir.global_position, 11.0, true)
		for i in 4:
			world._process(0.05)
		await _wait(4)
		await _shot(tag + "gameplay.png")
		# A close look over the heir's shoulder.
		heir.teleport(c + Vector3(1.55, 0, 1.15))
		to = c - heir.global_position
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y + 0.5, true)
		world.camera_rig.look_at_point(heir.global_position, 5.0, true)
		for i in 4:
			world._process(0.05)
		await _wait(4)
		await _shot(tag + "close.png")
		world.set_view_mode("overview", true)
		# A banner on the square (or by the manor in a hamlet).
		var banners := st.layout.props_of_type("banner")
		if not banners.is_empty():
			var bp: Dictionary = banners[banners.size() - 1]
			world.camera_rig.set_yaw(float(bp["rot"]) + 0.5, true)
			world.camera_rig.look_at_point(bp["pos"], 11.0, true)
			await _wait(4)
			await _shot(tag + "banner.png")
		if not signs.is_empty():
			var sp: Dictionary = signs[0]
			world.camera_rig.set_yaw(float(sp["rot"]) + 0.7, true)
			world.camera_rig.look_at_point(sp["pos"], 9.0, true)
			await _wait(4)
			await _shot(tag + "signpost.png")


## A conversation on foot: the terms, a refusal (terms still open) and
## the better offer they accept.
func _talk_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	var st := world.state
	var heir := world.player_npc()
	var target: NPC = null
	for npc: NPC in world.npcs.values():
		var c := npc.character
		if npc != heir and not CourtSystem.is_kin(st, c) and c.age >= 18 and c.inside_building_id < 0 and npc.visible:
			var d := heir.global_position.distance_to(npc.global_position)
			if target == null or d < heir.global_position.distance_to(target.global_position):
				target = npc
	if target == null:
		return
	var spot := target.global_position + Vector3(0, 0, 2.0)
	for i in 16:
		var p := target.global_position + Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0)) * 2.0
		if not WorldGeometry.inside_building(st, p, 0.6) and not WorldGeometry.line_blocked(st, p, target.global_position):
			spot = p
			break
	target.brain.set_errand({"type": "hold", "face": spot})
	heir.teleport(spot)
	var to := target.global_position - spot
	heir.rotation.y = atan2(-to.x, -to.z)
	world.camera_rig.set_yaw(heir.rotation.y, true)
	world._process(0.05)
	var c := target.character
	c.player_opinion = -30.0
	world.try_talk(c.id)
	var panel := world.ui.conversation_panel()
	await _wait(3)
	panel._on_ask()
	panel.flush()
	panel._on_make()
	panel._set_wage(1)
	await _wait(4)
	await _shot("30_offer_terms.png")
	panel._on_propose()
	panel.flush()
	await _wait(4)
	await _shot("31_offer_refused.png")
	c.player_opinion = 70.0
	panel._set_wage(Recruitment.wage_need(c) + 1)
	panel._on_propose()
	if not c.retainer and not panel.counter.is_empty():
		panel._on_agree()
	panel.flush()
	await _wait(4)
	await _shot("32_offer_accepted.png")
	panel._on_make()
	await _wait(4)
	await _shot("33_new_terms.png")


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


## Runs the village's days without bodies (as the tests do), with a player
## who orders a few buildings early on.
static func simulate(st: WorldState, days: int, plan: Dictionary) -> void:
	for d in days:
		if plan.has(d):
			var spot := TerritorySystem.find_spot(st, str(plan[d]), 18.0, 70.0)
			if not spot.is_empty():
				TerritorySystem.place(st, str(plan[d]), spot["pos"], spot["rot"])
		for k in 48:
			st.minutes += 30.0
			for s in TerritorySystem.advance(st, 30.0):
				TerritorySystem.complete(st, s)
		var day := Calendar.day_index(st.whole_minutes())
		st.last_daily_update = day
		var rng := Seeds.rng(st.world_seed, "day_%d" % day)
		for c in st.characters:
			MoodSystem.daily_update(c, st, rng)
		CourtSystem.daily_update(st, Seeds.rng(st.world_seed, "court_day_%d" % day))
		TerritorySystem.daily_update(st)
		GrowthSystem.daily_update(st)


func _boot_world() -> VillageWorld:
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.set_view_mode("overview", true)
	world.set_speed(1)
	for i in 120:
		world._process(0.1)
	world.set_speed(0)
	world.paused = true
	return world


func _growth_shots() -> void:
	# Day one.
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 4.0 * 60.0
	var world := await _boot_world()
	world.ui._help.visible = false
	world.camera_rig.set_yaw(0.5, true)
	world.camera_rig.look_at_point(Vector3(0, 0, 4), 120.0, true)
	await _wait(20)
	await _shot("30_growth_day_1.png")
	world.queue_free()
	await _wait(3)

	# 45 days later, with a player who built stone, wood, food and a bakery.
	var st := WorldGenerator.generate(seed_text)
	st.house.gold = 400
	var days := int(OS.get_environment("GROWTH_DAYS")) if OS.get_environment("GROWTH_DAYS").is_valid_int() else 45
	simulate(st, days, {1: "quarry", 4: "quarry", 7: "workshop", 10: "farmhouse", 14: "storehouse", 18: "bakery", 24: "farmhouse"})
	print("after %d days: %d people" % [days, st.characters.size()])
	print("after 45 days: %d people, %d settler families, %d homes" % [st.characters.size(), st.territory.settler_families, GrowthSystem.homes(st).size()])
	# Open one upgrade to show it going up (if the village hasn't one running).
	var upgrading: ConstructionSite = null
	for s in st.territory.sites:
		if s.is_upgrade():
			upgrading = s
	if upgrading == null:
		for b in GrowthSystem.homes(st):
			if GrowthSystem.can_level(b) and b.tier < GrowthSystem.max_tier() and not st.residents_of(b.id).is_empty() and st.territory.get_site(b.id) == null:
				upgrading = TerritorySystem.open_upgrade(st, b, b.tier + 1, {}, 20.0)
				break
	if upgrading:
		upgrading.work_done = upgrading.work_needed * 0.55
	st.minutes = floorf(st.minutes / Calendar.MINUTES_PER_DAY) * Calendar.MINUTES_PER_DAY + 11.0 * 60.0
	Game.state = st
	world = await _boot_world()
	world.ui._help.visible = false
	world.camera_rig.set_yaw(0.5, true)
	world.camera_rig.look_at_point(Vector3(0, 0, 4), 120.0, true)
	await _wait(20)
	await _shot("31_growth_later.png")
	if upgrading:
		var b := upgrading.building
		world.camera_rig.set_yaw(b.rotation + 0.6, true)
		world.camera_rig.look_at_point(b.position, 22.0, true)
		await _wait(20)
		await _shot("32_home_upgrading.png")
	for tier in [1, 2]:
		for b in GrowthSystem.homes(st):
			if b.tier == tier and st.territory.get_site(b.id) == null:
				world.camera_rig.set_yaw(b.rotation + 0.5, true)
				world.camera_rig.look_at_point(b.position, 20.0, true)
				await _wait(20)
				await _shot("33_home_tier_%d.png" % tier)
				break
	# A home's card with its needs.
	var shown := false
	for b in GrowthSystem.homes(st):
		if GrowthSystem.can_level(b) and b.tier < GrowthSystem.max_tier() and not st.residents_of(b.id).is_empty() and st.territory.get_site(b.id) == null:
			world.camera_rig.set_yaw(b.rotation + 0.5, true)
			world.camera_rig.look_at_point(b.position, 30.0, true)
			world.select_building(b.id)
			await _wait(15)
			await _shot("34_home_card.png")
			world.deselect()
			shown = true
			break
	if not shown:
		print("no home for the card shot")
	world.ui.toggle_build()
	await _wait(10)
	await _shot("35_build_panel_growth.png")
	world.ui.toggle_build()
	# Settlers arriving: a cottage for them, then they walk in.
	var home := GrowthSystem.empty_homes(st)
	if home.is_empty():
		var site := GrowthSystem.order_home(st)
		if site == null:
			for r: String in TerritorySystem.RESOURCES:
				st.territory.stock[r] = 600.0
			site = GrowthSystem.order_home(st)
		if site:
			world._on_growth_event({"text": "", "kind": "info", "site": site.id()})
			site.work_done = site.work_needed
			world._finish_site(site)
	var fam := GrowthSystem.settle(st)
	if fam:
		world._on_growth_event({"text": "The %s has come to settle in %s. New faces to appraise!" % [fam.display_name(), st.village_name], "kind": "join", "arrived": fam.member_ids.duplicate()})
		world.paused = false
		world.set_speed(0)
		for i in 60:
			world._process(0.1)
		world.paused = true
		var lead := world.npc_of(fam.member_ids[0])
		if lead:
			world.camera_rig.set_yaw(0.3, true)
			world.camera_rig.look_at_point(lead.global_position, 16.0, true)
			lead.character.met = true
			lead.character.appraised = true
			world.select_character(lead.character.id)
			await _wait(25)
			await _shot("36_settlers_arriving.png")


## Phase 3.3: the Charter section of the Build panel, then a Market Town's
## new banners around the square and its Market Hall.
func _charter_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 4.0 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.ui.toggle_build()
	await _wait(10)
	await _shot("40_charter_panel.png")
	world.ui.toggle_build()
	# Grant the Village and Market Town charters (as if earned), then raise a
	# Market Hall.
	st.house.gold = 5000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 900.0
	for i in 2:
		st.territory.charter = i + 1
		CharterSystem.raise_banners(st, int(CharterSystem.tier_def(i + 1).get("banners", 0)) - int(CharterSystem.tier_def(i).get("banners", 0)))
	world.builder.refresh_props()
	var spot := TerritorySystem.find_spot(st, "market", 20.0)
	var hall: BuildingData = null
	if not spot.is_empty():
		var res := TerritorySystem.place(st, "market", spot["pos"], spot["rot"])
		if res["ok"]:
			var site: ConstructionSite = res["site"]
			world.builder.add_site(site)
			site.work_done = site.work_needed
			world._finish_site(site)
			hall = site.building
	world.territory_changed.emit()
	world.camera_rig.set_yaw(0.6, true)
	world.camera_rig.look_at_point(st.layout.square_center, 44.0, true)
	await _wait(25)
	await _shot("41_charter_banners.png")
	if hall:
		world.camera_rig.set_yaw(hall.rotation + 0.45, true)
		world.camera_rig.look_at_point(hall.position, 24.0, true)
		await _wait(25)
		await _shot("42_market_hall.png")
		world.camera_rig.look_at_point(hall.position, 13.0, true)
		await _wait(25)
		await _shot("43_market_hall_close.png")
	else:
		print("no spot for the Market Hall")
	world.ui.toggle_build()
	await _wait(10)
	await _shot("44_charter_panel_market_town.png")

