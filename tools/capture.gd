extends Node
## Renders a set of screenshots for review (main menu, village overview,
## character card tabs, ledger, night). Needs a real display/GPU (not
## --headless).
##
##   godot --path . res://tools/capture.tscn -- <seed> <output_dir> [court|art|menus|build|growth|charter|talk|life|matches|succession|battle|realm]
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
## "eye" plays the Sovereign's Eye on foot for one person of each tier and
## saves stills at its beats: the Eye open, the sealed card and its clues,
## the card turned with its sparks, and the end. Run it with --fixed-fps 30
## so the stills land on the same frames every time.

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
var farm_only := false
var square_only := false
var smithy_only := false
var home_only := false
var thatch_only := false
var training_only := false
var chapel_only := false
var castle_only := false
var harbour_only := false
var eye_only := false
var barks_only := false
var life_only := false
var matches_only := false
var succession_only := false
var battle_only := false
var battle_stats := false
var realm_only := false
var keep_only := false


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
	farm_only = args.has("farm")
	square_only = args.has("square")
	smithy_only = args.has("smithy")
	home_only = args.has("home")
	thatch_only = args.has("thatch")
	training_only = args.has("training")
	chapel_only = args.has("chapel")
	castle_only = args.has("castle")
	harbour_only = args.has("harbour")
	eye_only = args.has("eye")
	barks_only = args.has("barks")
	life_only = args.has("life")
	matches_only = args.has("matches")
	succession_only = args.has("succession")
	battle_only = args.has("battle")
	battle_stats = args.has("battle_stats")
	realm_only = args.has("realm")
	keep_only = args.has("keep")
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
	if farm_only:
		await _farm_shots()
		get_tree().quit()
		return
	if square_only:
		await _square_shots()
		get_tree().quit()
		return
	if smithy_only:
		await _smithy_shots()
		get_tree().quit()
		return
	if home_only:
		await _home_shots()
		get_tree().quit()
		return
	if thatch_only:
		await _thatch_shots()
		get_tree().quit()
		return
	if training_only:
		await _training_shots()
		get_tree().quit()
		return
	if chapel_only:
		await _chapel_shots()
		get_tree().quit()
		return
	if castle_only:
		await _castle_shots()
		get_tree().quit()
		return
	if harbour_only:
		await _harbour_shots()
		get_tree().quit()
		return
	if barks_only:
		await _bark_shots()
		get_tree().quit()
		return
	if life_only:
		await _life_shots()
		get_tree().quit()
		return
	if matches_only:
		await _match_shots()
		get_tree().quit()
		return
	if succession_only:
		await _succession_shots()
		get_tree().quit()
		return
	if battle_stats:
		await _battle_stats()
		get_tree().quit()
		return
	if battle_only:
		await _battle_shots()
		get_tree().quit()
		return
	if realm_only:
		await _realm_shots()
		get_tree().quit()
		return
	if keep_only:
		await _keep_shots()
		get_tree().quit()
		return
	if eye_only:
		await _eye_shots()
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


## Farm & Field in the game: for each fence tier (hamlet wattle, village
## rails, town pales) a field from the map table, its gate at 3/4 and the
## follow camera on foot by the gate; then each crop over the heir's
## shoulder, the haystacks, the log pile and a scarecrow; and the village
## from the map table with and without its fields (the perf numbers are in
## the log). Cameras pick an angle with no building in the way.
## Files: farm_<tier>_<view>.png, farm_crop_<crop>.png, farm_<prop>.png.
## FARM_TIERS=0,3 renders only those tiers; FARM_VIEWS=tiers only the tier shots.
func _farm_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	var heir := world.player_npc()
	# refresh_fields() replaces the holder, so look it up each time.
	var fields := func() -> Node3D: return world.builder.get_node("Fields")
	# The field nearest the square, and one of each crop.
	var c := st.layout.square_center
	var main_i := 0
	var by_crop := {}
	var centroid := Vector3.ZERO
	for i in st.layout.fields.size():
		var f: Dictionary = st.layout.fields[i]
		centroid += f["center"] / float(st.layout.fields.size())
		if (f["center"] as Vector3).distance_to(c) < (st.layout.fields[main_i]["center"] as Vector3).distance_to(c):
			main_i = i
		if not by_crop.has(f["crop"]):
			by_crop[f["crop"]] = i
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(4)
	# On foot: the heir outside a field side, facing in at a slant, the
	# follow camera behind. Takes the side with a clear view, `prefer` first.
	var on_foot := func(i: int, prefer: int, back: float, cam: float) -> void:
		var f: Dictionary = st.layout.fields[i]
		var xf: Transform3D = (fields.call() as Node3D).get_child(i).global_transform
		var size: Vector2 = f["size"]
		var off := float(FarmKit.cfg()["fence"]["offset"])
		var outs := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
		var best := {}
		for k in 4:
			var side: int = (prefer + k) % 4
			var o: Vector3 = outs[side]
			var half := (size.y if side % 2 == 0 else size.x) * 0.5 + off
			var along := Vector3(o.z, 0, -o.x)
			var at := xf * (o * (half + back) + along * 1.2)
			var face := (xf.basis * (-o * 1.0 - along * 0.45)).normalized()
			face.y = 0
			var yaw := atan2(-face.x, -face.z)
			var clear := _clearance(st, at, yaw, cam * 0.8)
			if best.is_empty() or (clear >= 1.0 and float(best["clear"]) < 1.0):
				best = {"at": at, "yaw": yaw, "clear": clear}
		world.set_view_mode("walk", true)
		heir.teleport(best["at"])
		heir.rotation.y = best["yaw"]
		world.camera_rig.set_yaw(best["yaw"], true)
		world.camera_rig.look_at_point(heir.global_position, cam, true)
		await settle.call()
	var map_table := func(focus: Vector3, dist: float, prefer: float) -> void:
		world.set_view_mode("overview", true)
		world.camera_rig.set_yaw(_clear_yaw(st, focus, dist * 0.7, prefer), true)
		world.camera_rig.look_at_point(focus, dist, true)
		await settle.call()
	var only := OS.get_environment("FARM_TIERS").split(",", false)
	for tier in [0, 1, 3]:
		if not only.is_empty() and not str(tier) in only:
			continue
		st.territory.charter = tier
		world.builder.refresh_props()
		world.builder.refresh_fields()
		world.territory_changed.emit()
		await _wait(2)
		var f: Dictionary = st.layout.fields[main_i]
		var node: Node3D = fields.call().get_child(main_i)
		var gate := node.get_node_or_null("Gate") as Node3D
		var gate_pos: Vector3 = gate.global_position if gate else node.global_position
		var out := gate_pos - node.global_position
		out.y = 0
		out = out.normalized()
		var tag := "farm_%d_" % tier
		heir.teleport(c)
		await map_table.call(f["center"], 24.0, atan2(out.x, out.z) + 0.6)
		await _shot(tag + "field.png")
		await map_table.call(gate_pos, 9.5, atan2(out.x, out.z) + 0.75)
		await _shot(tag + "gate.png")
		var gate_side := FarmKit.gate_side(f["size"], node.global_transform.affine_inverse() * gate_pos)
		await on_foot.call(main_i, gate_side, 2.4, 11.0)
		await _shot(tag + "gameplay.png")
	# FARM_VIEWS=tiers stops here (renderer checks: --rendering-method mobile).
	if OS.get_environment("FARM_VIEWS") == "tiers":
		return
	# Each crop over the heir's shoulder, from the side away from the farmhouse.
	for crop: String in by_crop:
		var i: int = by_crop[crop]
		var node: Node3D = fields.call().get_child(i)
		var gate := node.get_node_or_null("Gate") as Node3D
		var away := 0
		if gate:
			away = (FarmKit.gate_side(st.layout.fields[i]["size"], node.global_transform.affine_inverse() * gate.global_position) + 2) % 4
		await on_foot.call(i, away, 0.9, 5.5)
		await _shot("farm_crop_%s.png" % crop)
	# Haystacks, the log pile and a scarecrow.
	heir.teleport(c)
	var shown := {}
	for type: String in ["haystack", "lumber"]:
		for p: Dictionary in st.layout.props_of_type(type):
			var model := PropKit.variant_model(type, p["pos"])
			if shown.has(model):
				continue
			shown[model] = true
			await map_table.call(p["pos"], 9.5, float(p["rot"]) + 0.6)
			await _shot("farm_%s.png" % model.get_slice(":", 1).to_lower())
	for node: Node in fields.call().get_children():
		var sc := node.get_node_or_null("Scarecrow") as Node3D
		if sc:
			await map_table.call(sc.global_position + Vector3(0, 1.0, 0), 9.5, sc.global_rotation.y + 0.4)
			await _shot("farm_scarecrow.png")
			break
	# The village from the map table, with and without its fields.
	st.territory.charter = 1
	world.builder.refresh_fields()
	world.set_view_mode("overview", true)
	world.camera_rig.set_yaw(0.6, true)
	world.camera_rig.look_at_point(c.lerp(centroid, 0.6), 75.0, true)
	await _wait(6)
	await _shot("farm_overview.png")
	fields.call().visible = false
	await _wait(4)
	await _shot("farm_overview_nofields.png")
	fields.call().visible = true


## The Market Square in the game, for every charter: the square from the
## map table, its kerb on foot where a road comes in, the trough beside the
## well, and (from Market Town on) the market cross at 3/4 and on foot.
## SQUARE_TIERS=0,2 renders only those. Files: square_<tier>_<view>.png.
func _square_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.5 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	var heir := world.player_npc()
	var c := st.layout.square_center
	var r := st.layout.square_radius
	var cross: Vector3 = st.layout.props_of_type("market_cross")[0]["pos"]
	var trough: Vector3 = st.layout.props_of_type("trough")[0]["pos"]
	var mouth := c + Vector3(r, 0, 0)
	for road: Dictionary in st.layout.roads:
		if str(road.get("name", "")) == "east":
			mouth = (road["points"] as PackedVector3Array)[0]
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(4)
	var only := OS.get_environment("SQUARE_TIERS").split(",", false)
	for tier in CharterSystem.tiers().size():
		if tier > 0:
			CharterSystem.raise_banners(st, int(CharterSystem.tier_def(tier).get("banners", 0)) - int(CharterSystem.tier_def(tier - 1).get("banners", 0)))
		st.territory.charter = tier
		if not only.is_empty() and not str(tier) in only:
			continue
		world.builder.refresh_props()
		world.builder.refresh_square()
		world.territory_changed.emit()
		await _wait(2)
		var tag := "square_%d_" % tier
		# The square from the map table.
		world.set_view_mode("overview", true)
		heir.teleport(c + Vector3(1.7, 0, 0.9))
		world.camera_rig.set_yaw(0.6, true)
		world.camera_rig.look_at_point(c, 32.0, true)
		await settle.call()
		await _shot(tag + "square.png")
		# On foot, coming in from the east road: the kerb either side.
		world.set_view_mode("walk", true)
		var inward := (c - mouth).normalized()
		heir.teleport(mouth - inward * 3.0 + Vector3(inward.z, 0, -inward.x) * 3.2)
		var to := mouth + Vector3(inward.z, 0, -inward.x) * 4.0 - heir.global_position
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y + 0.35, true)
		world.camera_rig.look_at_point(heir.global_position, 6.5, true)
		await settle.call()
		await _shot(tag + "kerb.png")
		# The trough beside the well.
		world.set_view_mode("overview", true)
		var tr_out := (trough - c).normalized()
		world.camera_rig.set_yaw(_clear_yaw(st, trough, 9.5 * 0.7, atan2(tr_out.x, tr_out.z) + 0.5), true)
		world.camera_rig.look_at_point(trough, 9.5, true)
		await settle.call()
		await _shot(tag + "trough.png")
		if PropKit.present("market_cross", tier):
			var cr_out := (cross - c).normalized()
			world.camera_rig.set_yaw(atan2(-cr_out.x, -cr_out.z) + 0.55, true)
			world.camera_rig.look_at_point(cross + Vector3(0, 2.3, 0), 14.0, true)  # the Town cross is 6 m tall
			await settle.call()
			await _shot(tag + "cross.png")
			# On foot: the heir walking up to the cross across the square.
			world.set_view_mode("walk", true)
			var approach := cross + (c - cross).normalized() * 4.2 + Vector3(-cr_out.z, 0, cr_out.x) * 1.2
			heir.teleport(approach)
			var to_c := cross - approach
			heir.rotation.y = atan2(-to_c.x, -to_c.z)
			world.camera_rig.set_yaw(heir.rotation.y, true)
			world.camera_rig.look_at_point(heir.global_position, 9.0, true)
			await settle.call()
			await _shot(tag + "cross_gameplay.png")
		world.set_view_mode("overview", true)


## The smith's forge yard in the game: for a village (hearth) and a town
## (forge, grindstone) the yard at 3/4 from the map table, the heir walking
## up to the anvil with the follow camera, and the smithy from the map table;
## then the town forge at night. SMITHY_TIERS=1,3 renders only those.
## Files: smithy_<tier>_<view>.png.
func _smithy_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.5 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	var heir := world.player_npc()
	var yard: Dictionary = st.layout.props_of_type("forge")[0]
	var at: Vector3 = yard["pos"]
	var front := Basis(Vector3.UP, float(yard["rot"])) * Vector3(0, 0, 1)
	var smithy: BuildingData = null
	for b in st.layout.buildings:
		if b.type == "smithy":
			smithy = b
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(4)
	var only := OS.get_environment("SMITHY_TIERS").split(",", false)
	for tier in [1, 3]:
		if not only.is_empty() and not str(tier) in only:
			continue
		st.territory.charter = tier
		world.builder.refresh_props()
		world.territory_changed.emit()
		await _wait(2)
		var tag := "smithy_%d_" % tier
		world.set_view_mode("overview", true)
		heir.teleport(at + front * 3.4 + Vector3(front.z, 0, -front.x) * 1.5)
		world.camera_rig.set_yaw(atan2(front.x, front.z) + 0.55, true)
		world.camera_rig.look_at_point(at + Vector3(0, 0.8, 0), 9.5, true)
		await settle.call()
		await _shot(tag + "yard.png")
		# On foot: the heir walking up to the anvil.
		world.set_view_mode("walk", true)
		heir.teleport(at + front * 4.2 + Vector3(front.z, 0, -front.x) * 0.8)
		var to := at - heir.global_position
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y + 0.3, true)
		world.camera_rig.look_at_point(heir.global_position, 7.0, true)
		await settle.call()
		await _shot(tag + "gameplay.png")
		world.set_view_mode("overview", true)
		world.camera_rig.set_yaw(_clear_yaw(st, smithy.position, 14.0, atan2(front.x, front.z) + 0.9), true)
		world.camera_rig.look_at_point(smithy.position.lerp(at, 0.5), 20.0, true)
		await settle.call()
		await _shot(tag + "smithy.png")
	# The town forge at night: the embers glow.
	if only.is_empty() or "3" in only:
		st.minutes += 11.0 * 60.0
		world.set_view_mode("walk", true)
		heir.teleport(at + front * 4.2 + Vector3(front.z, 0, -front.x) * 0.8)
		var to_n := at - heir.global_position
		heir.rotation.y = atan2(-to_n.x, -to_n.z)
		world.camera_rig.set_yaw(heir.rotation.y + 0.3, true)
		world.camera_rig.look_at_point(heir.global_position, 7.0, true)
		await settle.call()
		await _wait(6)
		await _shot("smithy_3_night.png")
		world.set_view_mode("overview", true)


## The Home Yard (3D/props/home-yard): one cottage's yard as a Cottage, a
## Timber House and a Townhouse (every cottage in the village takes the
## level, so the street matches), from the front, the back and on foot; and
## a farmhouse's. HOME_TIERS=0,2 limits the levels.
func _home_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	var heir := world.player_npc()
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(4)
	var set_tier := func(tier: int) -> void:
		for b in st.layout.buildings:
			if b.type == "cottage":
				b.tier = tier
				world.builder.replace_building_node(b)
		world.builder.refresh_props()
		world.territory_changed.emit()
		await _wait(2)
	# The cottage with the fullest yard (as a Timber House), and the farmhouse's.
	await set_tier.call(1)
	var best: BuildingData = null
	var farm: BuildingData = null
	var count := {}
	for r: Dictionary in world.builder.yard_rects:
		count[r["building"]] = int(count.get(r["building"], 0)) + 1
	for b in st.layout.buildings:
		if b.type == "cottage" and (best == null or int(count.get(b.id, 0)) > int(count.get(best.id, 0))):
			best = b
		if b.type == "farmhouse" and (farm == null or int(count.get(b.id, 0)) > int(count.get(farm.id, 0))):
			farm = b
	var only := OS.get_environment("HOME_TIERS").split(",", false)
	for tier in [0, 1, 2]:
		if not only.is_empty() and not str(tier) in only:
			continue
		await set_tier.call(tier)
		var tag := "home_%d_" % tier
		var fwd := best.forward()
		var yaw := atan2(fwd.x, fwd.z)
		heir.teleport(best.position + fwd * (best.footprint.y * 0.5 + 6.0) + Vector3(fwd.z, 0, -fwd.x) * 4.0)
		world.set_view_mode("overview", true)
		world.camera_rig.set_yaw(_clear_yaw(st, best.position, 14.0, yaw + 0.6), true)
		world.camera_rig.look_at_point(best.position + Vector3(0, 0.8, 0), 15.0, true)
		await settle.call()
		await _shot(tag + "front.png")
		world.camera_rig.set_yaw(_clear_yaw(st, best.position, 14.0, yaw + PI - 0.6), true)
		world.camera_rig.look_at_point(best.position + Vector3(0, 0.8, 0), 15.0, true)
		await settle.call()
		await _shot(tag + "back.png")
		# On foot: the heir coming up to the door, past the bench.
		world.set_view_mode("walk", true)
		heir.teleport(best.door_position() + fwd * 2.5 + Vector3(fwd.z, 0, -fwd.x) * 1.0)
		heir.rotation.y = atan2(fwd.x, fwd.z)
		world.camera_rig.set_yaw(_clear_yaw(st, heir.global_position, 9.0, heir.rotation.y + 0.35), true)
		world.camera_rig.look_at_point(heir.global_position, 7.0, true)
		await settle.call()
		await _shot(tag + "gameplay.png")
		world.set_view_mode("overview", true)
	if farm and (only.is_empty() or "1" in only):
		var ffwd := farm.forward()
		world.camera_rig.set_yaw(_clear_yaw(st, farm.position, 16.0, atan2(ffwd.x, ffwd.z) + PI - 0.7), true)
		world.camera_rig.look_at_point(farm.position + Vector3(0, 0.8, 0), 18.0, true)
		await settle.call()
		await _shot("home_farm.png")


## Thatch & Repair (3D/buildings/thatch-repair): the same street with every
## cottage a Cottage (weathered thatch, patched walls, plank shutters), a
## Timber House (neat thatch) and a Townhouse (tiles); a poor cottage close
## to and on foot; a farmhouse; and the whole village from above.
func _thatch_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	var heir := world.player_npc()
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(4)
	var set_tier := func(tier: int) -> void:
		for b in st.layout.buildings:
			if b.type == "cottage":
				b.tier = tier
				world.builder.replace_building_node(b)
		world.builder.refresh_props()
		world.territory_changed.emit()
		await _wait(2)
	# The cottage that best shows its repairs: wattle showing on its front
	# (+z, the door side) or the front half of its right (+x) wall, which the
	# close-up sees (a cottage is 6 x 4 m); else any patch there.
	var poor: BuildingData = null
	var farm: BuildingData = null
	var best := -1
	for b in st.layout.buildings:
		if b.type == "farmhouse" and farm == null:
			farm = b
		if b.type != "cottage":
			continue
		var score := 0
		for part: Array in VillageKit.prefab(b.type, b.variant, 0).get("detail_parts", []):
			var at := (part[1] as Transform3D).origin
			if str(part[0]).contains("Patch") and (at.z > 1.9 or (at.x > 2.9 and at.z > 0.0)):
				score = maxi(score, 2 if str(part[0]).contains("Wattle") else 1)
		if score > best:
			best = score
			poor = b
	var fwd := poor.forward()
	var yaw := atan2(fwd.x, fwd.z)
	# THATCH_VIEWS=cottage takes only the close-up (renderer checks: --rendering-method mobile).
	var only_cottage := OS.get_environment("THATCH_VIEWS") == "cottage"
	for tier in ([] if only_cottage else [0, 1, 2]):
		await set_tier.call(tier)
		world.set_view_mode("overview", true)
		world.camera_rig.set_yaw(_clear_yaw(st, poor.position, 30.0, yaw + 0.5), true)
		world.camera_rig.look_at_point(poor.position + Vector3(0, 1.0, 0), 34.0, true)
		await settle.call()
		await _shot("thatch_street_%d.png" % tier)
	await set_tier.call(0)
	world.camera_rig.set_yaw(_clear_yaw(st, poor.position, 12.0, yaw + 0.75), true)
	world.camera_rig.look_at_point(poor.position + Vector3(0, 1.4, 0), 13.0, true)
	await settle.call()
	await _shot("thatch_cottage.png")
	if only_cottage:
		return
	world.set_view_mode("walk", true)
	heir.teleport(poor.door_position() + fwd * 3.0 + Vector3(fwd.z, 0, -fwd.x) * 1.6)
	heir.rotation.y = yaw
	world.camera_rig.set_yaw(_clear_yaw(st, heir.global_position, 9.0, yaw + 0.3), true)
	world.camera_rig.look_at_point(heir.global_position, 7.0, true)
	await settle.call()
	await _shot("thatch_onfoot.png")
	world.set_view_mode("overview", true)
	if farm:
		var ffwd := farm.forward()
		world.camera_rig.set_yaw(_clear_yaw(st, farm.position, 18.0, atan2(ffwd.x, ffwd.z) + 0.6), true)
		world.camera_rig.look_at_point(farm.position + Vector3(0, 1.5, 0), 20.0, true)
		await settle.call()
		await _shot("thatch_farm.png")
	world.camera_rig.set_yaw(0.5, true)
	world.camera_rig.look_at_point(Vector3(0, 0, 4), 120.0, true)
	await settle.call()
	await _wait(10)
	await _shot("thatch_village.png")


## The Training Yard (3D/props/training-yard): the barracks' yard at each
## charter (Hamlet muster to Town guard) from outside, soldiers drilling in
## it, and on foot. TRAINING_CHARTERS=0,3 limits the charters.
func _training_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	var heir := world.player_npc()
	var yards := st.layout.props_of_type("training") + st.layout.props_of_type("training_small")
	if yards.is_empty():
		push_warning("no training yard in this village")
		return
	var yard: Dictionary = yards[0]
	var at: Vector3 = yard["pos"]
	var out := Basis(Vector3.UP, float(yard["rot"])) * Vector3(0, 0, 1)
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(4)
	var only := OS.get_environment("TRAINING_CHARTERS").split(",", false)
	for charter in [0, 1, 2, 3]:
		if not only.is_empty() and not str(charter) in only:
			continue
		st.territory.charter = charter
		world.builder.refresh_props()
		world.territory_changed.emit()
		# Let the soldiers walk out to the yard.
		world.set_speed(2)
		for k in 160:
			world._process(0.1)
		world.set_speed(0)
		await _wait(2)
		var tag := "training_%d_" % charter
		world.set_view_mode("overview", true)
		heir.teleport(at + out * 9.0 + Vector3(out.z, 0, -out.x) * 4.0)
		world.camera_rig.set_yaw(_clear_yaw(st, at, 16.0, atan2(out.x, out.z) + 0.45), true)
		world.camera_rig.look_at_point(at + Vector3(0, 0.6, 0), 17.0, true)
		await settle.call()
		await _shot(tag + "yard.png")
		world.set_view_mode("walk", true)
		heir.teleport(at + out * 5.5 + Vector3(out.z, 0, -out.x) * 1.5)
		var to := at - heir.global_position
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y + 0.25, true)
		world.camera_rig.look_at_point(heir.global_position, 7.5, true)
		await settle.call()
		await _shot(tag + "gameplay.png")
		world.set_view_mode("overview", true)


## The chapel and its churchyard (3D/props/chapel-grounds) at each charter:
## from the square, from behind, from the side and on foot by the east
## wall; then close views of the bell in the tower and the gable cross.
## CHAPEL_CHARTERS=0,3 takes only those charters; CHAPEL_SIZE=small shows a
## shallow churchyard in place of the full one.
func _chapel_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world := await _boot_world()
	var st := world.state
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	var heir := world.player_npc()
	var chapels := st.layout.buildings_of_type("chapel")
	if chapels.is_empty():
		push_warning("no chapel in this village")
		return
	var b: BuildingData = chapels[0]
	var at := b.position
	var back := b.basis() * Vector3(0, 0, -1)
	var side := Vector3(back.z, 0, -back.x)
	var yards := st.layout.props_of_type("churchyard") + st.layout.props_of_type("churchyard_small")
	if OS.get_environment("CHAPEL_SIZE") == "small":
		# Every village here has room for a full churchyard; show the shallow one too.
		for y: Dictionary in yards:
			var half: Vector2 = VillageLayoutGenerator.YARD_HALF["churchyard_small"]
			y["type"] = "churchyard_small"
			y["pos"] = at + back * (b.footprint.y * 0.5 + VillageLayoutGenerator.CHURCHYARD_SETBACKS[0] + half.y)
		world.builder.refresh_ground()
	var yard_at := at + back * 12.0
	var depth := 4.6
	for y: Dictionary in yards:
		if (y["pos"] as Vector3).distance_to(at) < 20.0:
			yard_at = y["pos"]
			depth = VillageLayoutGenerator.YARD_HALF[y["type"]].y
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(4)
	var only := OS.get_environment("CHAPEL_CHARTERS").split(",", false)
	for charter in [0, 1, 2, 3]:
		if not only.is_empty() and not str(charter) in only:
			continue
		st.territory.charter = charter
		world.builder.refresh_props()
		world.territory_changed.emit()
		await _wait(2)
		var tag := "chapel_%d_" % charter
		world.set_view_mode("overview", true)
		heir.teleport(yard_at + back * (depth + 3.0) + side * 6.0)
		for view: Array in [["front", PI, at, 30.0], ["yard", 0.35, yard_at, 20.0], ["side", PI * 0.5 + 0.4, at + back * 4.0, 28.0]]:
			world.camera_rig.set_yaw(atan2(back.x, back.z) + float(view[1]), true)
			world.camera_rig.look_at_point(view[2], float(view[3]), true)
			await settle.call()
			await _shot(tag + str(view[0]) + ".png")
		# On foot, outside the east wall, looking back over the graves to the chapel.
		world.set_view_mode("walk", true)
		heir.teleport(yard_at + back * (depth + 1.6) + side * 1.2)
		var to := yard_at - heir.global_position
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y + 0.35, true)
		world.camera_rig.look_at_point(heir.global_position, 8.0, true)
		await settle.call()
		await _shot(tag + "gameplay.png")
		world.set_view_mode("overview", true)
	# Close views: the bell in the tower's top stage, the iron cross on the
	# spire, the stone cross on the east gable.
	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	var front := -back
	var tower := at + front * 4.5
	for view: Array in [["tower", tower + front * 9.0 + side * 6.0 + Vector3(0, 13.0, 0), tower + Vector3(0, 12.5, 0)],
			["belfry", tower + front * 16.0 + side * 3.0 + Vector3(0, 5.0, 0), tower + Vector3(0, 10.6, 0)],
			["spire", tower + front * 8.0 + side * 5.0 + Vector3(0, 19.0, 0), tower + Vector3(0, 17.2, 0)],
			["gable", at + back * 15.0 + side * 5.0 + Vector3(0, 11.0, 0), at + back * 6.0 + Vector3(0, 10.4, 0)]]:
		cam.global_position = view[1]
		cam.look_at(view[2])
		cam.make_current()
		await settle.call()
		await _shot("chapel_close_%s.png" % view[0])
	world.camera_rig.camera.make_current()
	cam.queue_free()


## The Lord's Castle family (3D/buildings/lords-castle) as two demo castles
## beside the village (scripts/castle/castle_layout.gd), placed by hand. The
## hills are levelled for it (the pieces stand on flat ground), the trees in
## and round the castles' footprints and the scatter in them cleared. Each castle over its walls to the village, from the front, from
## above, inside, close to its gate and on foot. CASTLE_KINDS=stone takes
## only that one.
func _castle_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	Game.state.layout.flat_radius = 400.0
	var Demo: GDScript = load("res://scripts/castle/castle_layout.gd")
	var st := Game.state
	var spots: Dictionary = Demo.find_spots(st.layout)
	if spots.is_empty():
		push_warning("no room for the demo castles round this village")
		return
	for kind: String in spots:
		for i: int in Demo.trees_in(st.layout, spots[kind], kind):
			if not st.territory.cleared_trees.has(i):
				st.territory.cleared_trees.append(i)
	var world := await _boot_world()
	world.ui._help.visible = false
	world.paused = false
	world.set_speed(0)
	for t in world.ui.find_children("*", "ToastStack", true, false):
		(t as CanvasItem).visible = false
	# Nothing grows through the walls: scatter in a footprint is put out of sight.
	for mmi: MultiMeshInstance3D in world.builder.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := mmi.multimesh
		for i in mm.instance_count:
			var xf := mmi.global_transform * mm.get_instance_transform(i)
			for kind: String in spots:
				var l: Vector3 = (spots[kind] as Transform3D).affine_inverse() * xf.origin
				if Demo.footprint(kind).grow(1.0).has_point(Vector2(l.x, l.z)):
					xf.origin.y -= 200.0
					mm.set_instance_transform(i, mmi.global_transform.affine_inverse() * xf)
					break
	for kind: String in spots:
		var node: Node3D = Demo.build(kind)
		node.transform = spots[kind]
		world.add_child(node)
	var heir := world.player_npc()
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.far = 900.0
	add_child(cam)
	var settle := func() -> void:
		for k in 4:
			world._process(0.05)
		await _wait(6)
	# The art views show the castles alone: no interface, the heir out of
	# them, and no name over anyone (hover goes by the game's own camera,
	# so that looks at the empty ground under the art camera meanwhile).
	var view := func(file_name: String, from: Vector3, to: Vector3, fov: float = 45.0) -> void:
		cam.fov = fov
		world.ui.visible = false
		heir.visible = false
		for npc: NPC in world.npcs.values():
			npc._label.modulate.a = 0.0
			npc._ring.transparency = 1.0
		world.camera_rig.look_at_point(Vector3(to.x, 0, to.z), 12.0, true)
		cam.global_position = from
		cam.look_at(to)
		cam.make_current()
		await settle.call()
		await _shot(file_name)
		world.ui.visible = true
		heir.visible = true
		for npc: NPC in world.npcs.values():
			npc._label.modulate.a = 1.0
			npc._ring.transparency = 0.0
	var only := OS.get_environment("CASTLE_KINDS").split(",", false)
	for kind: String in Demo.KINDS:
		if not only.is_empty() and not kind in only:
			continue
		var xf: Transform3D = spots[kind]
		var c := func(x: float, y: float, z: float) -> Vector3:
			return xf * Vector3(x, y, z)
		var tag := "castle_%s_" % kind
		# From behind it, over its walls to the village.
		var away := Vector3(xf.origin.x, 0, xf.origin.z).normalized()
		await view.call(tag + "village.png", xf.origin + away * 75.0 + Vector3(0, 38, 0), xf.origin.lerp(Vector3.ZERO, 0.45))
		if kind == "stone":
			await view.call(tag + "front.png", c.call(0, 12, 72), c.call(0, 7, 0))
			await view.call(tag + "aerial.png", c.call(52, 48, 58), c.call(0, 3, -2))
			await view.call(tag + "rear.png", c.call(-46, 26, -60), c.call(0, 6, -4))
			# From the court's far corner by the gate, a wider lens: the court is small.
			await view.call(tag + "court.png", c.call(13, 2.0, 12.5), c.call(-4, 8.5, -4), 62.0)
			await view.call(tag + "gate.png", c.call(7, 3.0, 36), c.call(0, 5.5, 19))
		else:
			await view.call(tag + "front.png", c.call(0, 12, 82), c.call(0, 5, 14))
			await view.call(tag + "aerial.png", c.call(48, 42, 64), c.call(0, 3, 12))
			await view.call(tag + "motte.png", c.call(24, 9, 24), c.call(0, 6.5, 6))
			await view.call(tag + "tower.png", c.call(9, 13, 20), c.call(0, 10, 0))
			await view.call(tag + "gate.png", c.call(7, 3.0, 47), c.call(0, 4.0, 36))
		# On foot before the gate, the heir looking up at it.
		world.camera_rig.camera.make_current()
		world.set_view_mode("walk", true)
		var gate_z: float = Demo.gate_z(kind)
		heir.teleport(c.call(1.5, 0, gate_z + 8.0))
		var to: Vector3 = c.call(0, 0, gate_z) - heir.global_position
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y + 0.12, true)
		world.camera_rig.look_at_point(heir.global_position, 12.0, true)
		await settle.call()
		await _shot(tag + "gameplay.png")
		world.set_view_mode("overview", true)
	cam.queue_free()


## The Harbour & Ships family (3D/props/harbour) in a harbour of its own
## (tools/harbour_demo.gd): the game has no sea yet, so the demo brings its
## shore and water, under the game's sky, with villagers on the quays for
## scale. From the sea, the stone quay and the cog, the cog's stern, the
## hoist, the timber quay, the jetty, the shore, the water stairs and the
## trading ship under sail.
func _harbour_shots() -> void:
	var Demo: GDScript = load("res://tools/harbour_demo.gd")
	var sky := SkyController.new()
	add_child(sky)
	sky.set_time(10.5 * 60.0)
	add_child(Demo.build(true))
	var w := WorldGenerator.generate(seed_text)
	var adults := w.characters.filter(func(c: CharacterData) -> bool: return c.age >= 18 and c.age < 70)
	var people: Array[CharacterModel] = []
	for i in HARBOUR_PEOPLE.size():
		var m := HumanModel.for_character(adults[(i * 7) % adults.size()])
		add_child(m)
		m.position = HARBOUR_PEOPLE[i][0]
		m.rotation.y = float(HARBOUR_PEOPLE[i][1])
		people.append(m)
	for f in 30:
		for m in people:
			m.animate("idle", f * 0.1, 1.0 / 30.0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.far = 900.0
	add_child(cam)
	cam.make_current()
	for view: Array in HARBOUR_VIEWS:
		cam.global_position = view[1]
		cam.look_at(view[2])
		await _wait(6)
		await _shot("harbour_%s.png" % view[0])


## Villagers on the quays and the shore: [position, yaw].
const HARBOUR_PEOPLE := [
	[Vector3(-3.4, 1.4, -0.7), 0.5], [Vector3(-1.5, 1.4, -2.9), 2.6], [Vector3(-20.6, 1.4, -1.4), 0.3],
	[Vector3(5.0, 1.4, -1.0), -0.4], [Vector3(20.4, 1.28, 9.4), PI], [Vector3(29.0, 1.4, -7.6), -0.7],
]
## [name, camera, looking at].
const HARBOUR_VIEWS := [
	["overview", Vector3(46, 30, 78), Vector3(-6, 0, 10)],
	["quay", Vector3(-31, 6, 17), Vector3(-10, 2.5, 2)],
	["stern", Vector3(-25, 3.5, 10), Vector3(-17.5, 1.8, 3.9)],
	["hoist", Vector3(3.5, 5.0, 10), Vector3(-3, 3.2, 0.5)],
	["timber", Vector3(15, 3.0, 9), Vector3(7, 1.0, 0)],
	["jetty", Vector3(28, 3.5, -4), Vector3(20, 1.0, 8)],
	["shore", Vector3(35, 3.2, 7), Vector3(35, 1.2, -6)],
	["steps", Vector3(-17, 3.5, 7.5), Vector3(-22, 0.6, 0.5)],
	["sail", Vector3(-32, 5, 72), Vector3(-4, 5, 46)],
]


## How far the ground line from `focus` out to a camera `dist` m away along
## `yaw` keeps from the nearest building (m; negative: through one).
func _clearance(st: WorldState, focus: Vector3, yaw: float, dist: float) -> float:
	var a := Vector3(focus.x, 0, focus.z)
	var b := a + Vector3(sin(yaw), 0, cos(yaw)) * dist
	var worst := INF
	for bd: BuildingData in st.layout.buildings:
		var at := Vector3(bd.position.x, 0, bd.position.z)
		worst = minf(worst, Geometry3D.get_closest_point_to_segment(at, a, b).distance_to(at) - bd.radius())
	return worst


## The yaw nearest `prefer` from which a camera `dist` m out sees `focus`
## past every building (with 1.5 m to spare when it can).
func _clear_yaw(st: WorldState, focus: Vector3, dist: float, prefer: float) -> float:
	var best := prefer
	var best_score := -INF
	for k in 36:
		var yaw := prefer + k * TAU / 36.0
		var score := minf(_clearance(st, focus, yaw, dist), 1.5) - absf(angle_difference(prefer, yaw)) * 0.2
		if score > best_score:
			best_score = score
			best = yaw
	return best


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


## One person of each tier, met on foot: the heir stands a few paces off
## and looks at them with the Eye. The beats: "eye" when the Eye has opened,
## "card" at the last clue on the sealed card (or the light sweep), "crack"
## as the seal breaks, "burst" just after the card turns and the sparks fly,
## "final" at the end with the choices. EYE_TIERS=skilled,legendary limits
## the tiers; EYE_CALM=1 turns on reduced motion and reduced flashes.
## The years turn (Phase 4.1): the village lives a few years (data only),
## then a card with kin who have died and children born since, and the
## house chronicle with its births, weddings, deaths and the succession.
func _life_shots() -> void:
	var years := int(OS.get_environment("LIFE_YEARS")) if OS.get_environment("LIFE_YEARS").is_valid_int() else 8
	Game.state = WorldGenerator.generate(seed_text)
	var st := Game.state
	simulate(st, years * Calendar.days_per_year(), {})
	print("life: %d years, %d living, %d departed, the heir %s (%s)" % [years, st.characters.size(), st.departed.size(), st.player().full_name(), CourtSystem.role_name(st, st.player())])
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	world.paused = true
	for n in world.ui.find_children("*", "", true, false):
		if n is ToastStack:
			for t in n.get_children():
				t.queue_free()
	# Someone with kin both departed and newly born.
	var best: CharacterData = null
	var best_score := -1
	for c in st.characters:
		var gone := 0
		var young := 0
		for r in c.relationships:
			var d := st.get_departed(int(r["target"]))
			if d and d.departed_how == "died" and str(r["type"]) in LifeSystem.KIN + ["late_spouse"]:
				gone += 1
			var k := st.get_character(int(r["target"]))
			if k and str(r["type"]) == "child" and k.age < 6:
				young += 1
		var score := mini(gone, 2) * 3 + mini(young, 2) * 2 + (2 if world.npc_of(c.id) else 0)
		if score > best_score:
			best_score = score
			best = c
	if best:
		print("life: card of %s" % best.full_name())
		world.select_character(best.id, true)
		await _wait(10)
		world.ui._card.show_tab("Relationships")
		await _wait(10)
		await _shot("life_card.png")
	world.deselect()
	world.ui.toggle_court()
	await _wait(10)
	for sc in world.ui._court.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 100000
	await _wait(5)
	await _shot("life_chronicle.png")


## The house's matches (Phase 4.2): a suitor from a neighbouring house met
## on foot with the answer to give, the court panel's Marriages, and grown
## kin's card with the matches to choose from (one refused, with reasons).
func _match_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	var st := Game.state
	st.minutes += 3.0 * 60.0
	var heir := st.player()
	var spouse := LifeSystem.spouse_of(st, heir)
	if spouse:
		heir.remove_relationship(spouse.id)
		spouse.remove_relationship(heir.id)
	heir.age = clampi(heir.age, 18, 30)
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	var events: Array[Dictionary] = []
	var suitor := MatchSystem.offer(st, heir, Seeds.rng(st.world_seed, "capture_suitor"), events)
	for n in world.ui.find_children("*", "", true, false):
		if n is ToastStack:
			for t in n.get_children():
				t.queue_free()
	world.apply_life_events(events)
	await _wait(3)
	var me := world.player_npc()
	# Out on the square, where there's room to see them.
	me.teleport(st.layout.square_center + Vector3(4.0, 0, 6.0))
	var npc := world.npc_of(suitor.id)
	var spot := me.global_position + Vector3(0, 0, 2.2)
	for i in 16:
		var p := me.global_position + Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0)) * 2.2
		if not WorldGeometry.inside_building(st, p, 0.6) and not WorldGeometry.line_blocked(st, p, me.global_position):
			spot = p
			break
	npc.teleport(spot)
	var to := spot - me.global_position
	me.rotation.y = atan2(-to.x, -to.z)
	world.camera_rig.set_yaw(me.rotation.y, true)
	world._process(0.05)
	print("matches: %s of %s for %s (%s)" % [suitor.full_name(), st.realm.house_title(suitor.house_id), heir.full_name(), MatchSystem.letter(st, suitor)])
	world.try_talk(suitor.id)
	var panel := world.ui.conversation_panel()
	await _wait(3)
	panel.flush()
	for n in world.ui.find_children("*", "", true, false):
		if n is ToastStack:
			for t in n.get_children():
				t.queue_free()
	await _wait(6)
	await _shot("match_suitor.png")
	world.end_conversation()
	for n in world.ui.find_children("*", "", true, false):
		if n is ToastStack:
			for t in n.get_children():
				t.queue_free()
	world.ui.toggle_court()
	await _wait(10)
	await _shot("match_court.png")
	world.ui.toggle_court()
	# Grown kin, matched from their card: one refusal with its reasons.
	var fam := st.ruling_family()
	var kin: CharacterData = null
	for id in fam.member_ids:
		var k := st.get_character(id)
		if k and not st.is_player(k) and k.id != fam.head_id and LifeSystem.spouse_of(st, k) == null and k.age <= 50 and (kin == null or k.age > kin.age):
			kin = k
	if kin == null:
		return
	kin.age = maxi(kin.age, 18)
	world.select_character(kin.id, true)
	await _wait(10)
	for n in world.ui.find_children("*", "", true, false):
		if n is ToastStack:
			for t in n.get_children():
				t.queue_free()
	world.ui._card.show_tab("Court")
	world.ui._card._matching = true
	var list := MatchSystem.candidates(st, kin, 6)
	if not list.is_empty():
		var cold: CharacterData = list[-1]
		cold.add_relationship(kin.id, "rival", -50)
		world.ui._card._on_arrange(cold.id)
		world.ui._card._matching = true
		world.ui._card._build_court()
	await _wait(10)
	for n in world.ui.find_children("*", "", true, false):
		if n is ToastStack:
			for t in n.get_children():
				t.queue_free()
	await _wait(2)
	await _shot("match_kin.png")


## Succession (Phase 4.3): the family tree after some generations
## (SUCC_YEARS, default 60, data only), the summary after letting a year
## pass, then (seed 2, whose heir is 13) the lord dying young and the Court
## panel with the child's regent.
func _succession_shots() -> void:
	var years := int(OS.get_environment("SUCC_YEARS")) if OS.get_environment("SUCC_YEARS").is_valid_int() else 60
	Game.state = WorldGenerator.generate(seed_text)
	var st := Game.state
	simulate(st, years * Calendar.days_per_year(), {"matches": true})
	print("succession: %d years, you are %s (%s), rulers %s" % [years, st.player().full_name(), CourtSystem.role_name(st, st.player()),
		st.house.rulers.map(func(r: Dictionary) -> String: return st.get_person(int(r["id"])).first_name)])
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	world.paused = true
	_clear_toasts(world)
	world.ui.toggle_tree()
	await _wait(10)
	await _shot("succession_tree.png")
	world.ui.toggle_tree()
	await world.ui.pass_time(Calendar.days_per_year())
	await _wait(6)
	await _shot("succession_years.png")
	world.queue_free()
	await _wait(3)
	# A lord who dies young: the 13-year-old heir rules through a regent.
	Game.state = WorldGenerator.generate("2")
	st = Game.state
	st.minutes += 3.0 * 60.0
	var lord := Succession.ruler(st)
	var events: Array[Dictionary] = []
	LifeSystem.die(st, lord, "a fever", events)
	print("succession: %s" % events.map(func(e: Dictionary) -> String: return str(e["text"])).filter(func(t: String) -> bool: return not t.is_empty()))
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	_clear_toasts(world)
	world.ui.toggle_court()
	await _wait(10)
	await _shot("succession_regency.png")


## A raid fought in the village (Phase 5.1): the band on its road, the
## warband meeting it, the melee, and the report. The camera keeps over the
## fighting. BATTLE_LEVY=1 calls the levy first; BATTLE_SPEED=2 runs at 2x.
func _battle_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	var st := Game.state
	st.minutes += 70.0 * Calendar.MINUTES_PER_DAY
	Military.plan_raid(st, Seeds.rng(st.world_seed, "capture_raid"))
	st.military.raid["day"] = st.day()
	if OS.get_environment("BATTLE_LEVY") == "1":
		Military.call_levy(st)
	st.minutes = float(st.day() * Calendar.MINUTES_PER_DAY + Military.strike_hour() * 60) - 1.0
	print("battle: %s, %d raiders vs %d (odds %.2f)" % [st.military.raid["name"], st.military.raid["size"], Military.warband(st).size(), Military.odds(st)])
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	# Before: the Court panel's Defence, the band on its way.
	world.set_speed(0)
	world.paused = true
	st.minutes -= 60.0
	_clear_toasts(world)
	world.ui.toggle_court()
	await _wait(8)
	Input.warp_mouse(Vector2(4, 890))
	await _shot("battle_0_defence.png")
	world.ui.toggle_court()
	st.minutes += 60.0
	world.paused = false
	world.set_view_mode("overview", true)
	_clear_toasts(world)
	for i in 30:
		await get_tree().process_frame
		if world.battle:
			break
	if world.battle == null:
		print("battle: didn't start")
		return
	if OS.get_environment("BATTLE_SPEED") == "2":
		world.set_speed(1)
	# Stills on the fight's own beats: the line formed with the band on its
	# road, the charge, the melee, and late in the fight.
	var charge := -1
	var taken := {}
	for frame in 6000:
		var b := world.battle
		if b == null:
			break
		world.ui._map_banner.visible = false
		Input.warp_mouse(Vector2(4, 890))
		if charge < 0 and not b.mustering:
			charge = frame
		var sum := Vector3.ZERO
		var n := 0
		for f: Dictionary in b.ours + b.theirs:
			var npc: NPC = f.get("npc")
			if npc and is_instance_valid(npc) and not f["down"] and not f.get("fled", false) and (f.get("engaged", false) or b.mustering and f["side"] == "house"):
				sum += npc.global_position
				n += 1
		var at := sum / n if n > 0 else b._rally
		if frame == 0:
			# From behind the line, looking out along the band's road.
			var out := b._way_out - b._rally
			world.camera_rig.set_yaw(atan2(-out.x, -out.z), true)
		world.camera_rig.look_at_point(at, 30.0 if b.mustering else 15.0, frame < 2)
		var shot := ""
		if frame == 40:
			shot = "battle_1_line.png"
		elif charge >= 0 and frame == charge + 20:
			shot = "battle_2_charge.png"
		elif charge >= 0 and frame == charge + 110:
			shot = "battle_3_melee.png"
		elif charge >= 0 and frame == charge + 230:
			shot = "battle_4_late.png"
		if not shot.is_empty() and not taken.has(shot):
			taken[shot] = true
			print("battle: %s at frame %d (charge at %d, %.0fs in)" % [shot, frame, charge, b.elapsed])
			_clear_toasts(world)
			await _shot(shot)
		else:
			await get_tree().process_frame
	await _wait(10)
	_clear_toasts(world)
	await _shot("battle_5_report.png")
	print("battle: report %s" % world.state.military.last_report)


## The wider realm (Phase 5.2): the realm map (the village, a house, a
## camp), a visit (the young seen with the Eye, a gift given), the report
## of a fight at a camp, and the Court panel's Defence with the camps.
func _realm_shots() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	var st := Game.state
	st.minutes += 70.0 * Calendar.MINUTES_PER_DAY + 3.0 * 60.0
	st.house.gold = 420
	st.house.renown = 30
	var made := Military.make_camp(st, Seeds.rng(st.world_seed, "capture_camp_a"))
	Military.reveal_camp(st, made["camp"], "Your woodcutters have found where")
	var regards := [34, 12, -14, 0]
	for i in st.realm.houses.size():
		st.realm.houses[i]["standing"] = regards[i % regards.size()]
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	world.paused = true
	_clear_toasts(world)
	Input.warp_mouse(Vector2(4, 890))
	var ui := world.ui
	ui.toggle_realm()
	await _wait(6)
	await _shot("realm_0_map.png")
	var h := st.realm.houses[0]
	# A visit first (so the house's young are known), then the map on the house.
	Realm.set_out(st, int(h["id"]))
	world.apply_life_events([{"text": "", "away": [st.player_id]}])
	st.minutes += float(int(h["days"])) * Calendar.MINUTES_PER_DAY
	var welcome := Realm.arrive(st)
	var young := st.realm.household(int(h["id"]))
	for c in young.slice(0, 2):
		Realm.look(st, c.id)
	ui._realm.visible = false
	ui._visit_overlay.visible = true
	ui._visit.open(welcome)
	ui._visit._did(Realm.give_gift(st, 75), "coins")
	await _wait(6)
	await _shot("realm_1_visit.png")
	ui._visit_overlay.visible = false
	Realm.take_leave(st)
	var events: Array[Dictionary] = []
	Realm.come_home(st, events)
	world.apply_life_events(events)
	_clear_toasts(world)
	ui.show_realm("house", int(h["id"]))
	await _wait(6)
	await _shot("realm_2_house.png")
	var camp := st.military.camps[0]
	ui.show_realm("camp", int(camp["id"]))
	await _wait(6)
	await _shot("realm_3_camp.png")
	# The warband rides out; the fight on arrival.
	ui.toggle_realm()
	var r := Military.ride_out(st, int(camp["id"]))
	world.apply_life_events([{"text": "", "away": r["away"]}])
	var report: Dictionary = {}
	for d in int(camp["days"]):
		st.minutes += Calendar.MINUTES_PER_DAY
		for e: Dictionary in Military.daily_update(st):
			if e.has("battle"):
				report = e["battle"]
	print("realm: camp fight %s" % report)
	_clear_toasts(world)
	ui.show_battle_report(report)
	await _wait(6)
	await _shot("realm_4_camp_report.png")
	ui._report_overlay.visible = false
	ui.toggle_court()
	await _wait(6)
	await _shot("realm_5_defence.png")


## The house's castle (Phase 5.3): the Court panel's Castle section, the
## motte and bailey rising with its crew at work, standing, the stone castle
## rising in its place and standing; then a noble house's host: its demand
## in Defence (a friendly house's men sent, another asked), on the realm
## map, the fight before the gate and its report.
func _keep_shots() -> void:
	# KEEP_ONLY=fight: set everything up the same, draw only the fight.
	var only_fight := OS.get_environment("KEEP_ONLY") == "fight"
	Game.state = WorldGenerator.generate(seed_text)
	var st := Game.state
	st.minutes += 70.0 * Calendar.MINUTES_PER_DAY + 3.0 * 60.0
	st.territory.charter = 1
	st.house.gold = 2400
	st.house.renown = 30
	TerritorySystem.add(st, "wood", 500.0)
	TerritorySystem.add(st, "stone", 800.0)
	var world := await _boot_world()
	world.ui._help.visible = false
	_clear_toasts(world)
	Input.warp_mouse(Vector2(4, 890))
	world.ui.toggle_court()
	await _wait(8)
	if not only_fight:
		await _shot("keep_0_court.png")
	world.ui.toggle_court()
	var r := world.order_castle("timber")
	print("keep: %s" % r["text"])
	var xf := st.castle.transform()
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.far = 900.0
	add_child(cam)
	var view := func(file_name: String, from_local: Vector3, to_local: Vector3) -> void:
		if only_fight:
			return
		world.ui.visible = false
		# No names over anyone in the art views (hover follows the game camera).
		for npc: NPC in world.npcs.values():
			npc.quiet = true
			npc.refresh_markers()
		var to := xf * to_local
		var from := xf * from_local
		from.y = TerrainHeight.height_at(from.x, from.z) + from_local.y
		world.camera_rig.look_at_point(to, 30.0, true)
		cam.global_position = from
		cam.look_at(to)
		cam.make_current()
		for k in 4:
			world._process(0.05)
		await _wait(8)
		await _shot(file_name)
		world.ui.visible = true
	# The crew at the works, half of it up.
	var place_crew := func() -> void:
		var i := 0
		for id in st.castle.builders:
			var npc := world.npc_of(id)
			if npc:
				npc.teleport(TerrainHeight.on_ground(CastleSystem.work_spot(st, i)))
				npc.face_point(xf.origin)
				npc.set_anim("work")
			i += 1
	st.castle.work_done = st.castle.work_needed * 0.45
	world.castle_view.refresh()
	place_crew.call()
	await view.call("keep_1_rising.png", Vector3(34, 22, 70), Vector3(0, 2, 14))
	CastleSystem.complete(st)
	world.castle_view.refresh()
	await view.call("keep_2_motte.png", Vector3(40, 30, 78), Vector3(0, 3, 12))
	st.territory.charter = 2
	r = world.order_castle("stone")
	print("keep: %s" % r["text"])
	st.castle.work_done = st.castle.work_needed * 0.55
	world.castle_view.refresh()
	place_crew.call()
	await view.call("keep_3_stone_rising.png", Vector3(40, 30, 78), Vector3(0, 3, 6))
	CastleSystem.complete(st)
	world.castle_view.refresh()
	await view.call("keep_4_stone.png", Vector3(46, 34, 84), Vector3(0, 4, 4))
	world.camera_rig.camera.make_current()
	world.camera_rig.look_at_point(st.layout.square_center, 40.0, true)
	# A house that holds yours in contempt; one that would help, one that might if asked.
	var foe := st.realm.houses[0]
	foe["standing"] = -60
	var friend := Realm.rival_of(st, int(foe["id"]))
	friend["standing"] = 55
	friend["days"] = 2
	for h in st.realm.houses:
		if h != foe and h != friend:
			h["standing"] = 22
			h["days"] = 3
			break
	var warn := Military.plan_host(st, int(foe["id"]), Seeds.rng(st.world_seed, "capture_host"))
	print("keep: %s" % warn["text"])
	_clear_toasts(world)
	world.ui.toggle_court()
	await _wait(8)
	if not only_fight:
		await _shot("keep_5_host_defence.png")
	world.ui.toggle_court()
	world.ui.show_realm("house", int(foe["id"]))
	await _wait(8)
	if not only_fight:
		await _shot("keep_6_host_map.png")
	world.ui.toggle_realm()
	# The fight before the gate, stepped by hand (only the stills are drawn).
	st.military.raid["day"] = st.day()
	st.minutes = float(st.day() * Calendar.MINUTES_PER_DAY + Military.strike_hour() * 60) + 1.0
	world.paused = false
	world.set_speed(1)
	world._process(0.016)
	if world.battle == null:
		print("keep: the host didn't strike")
		return
	var b := world.battle
	# From the road the host comes by, looking at the line with the castle behind it.
	var out := b._way_out - b._rally
	world.camera_rig.set_yaw(atan2(out.x, out.z) + 0.45, true)
	var frame_on := func(file_name: String, distance: float) -> void:
		var sum := Vector3.ZERO
		var n := 0
		for f: Dictionary in b.ours + b.theirs:
			var npc: NPC = f.get("npc")
			if npc and is_instance_valid(npc) and not f["down"] and not f.get("fled", false) and (f.get("engaged", false) or b.mustering and f["side"] == "house"):
				sum += npc.global_position
				n += 1
		if n == 0:
			# No one at blows yet: everyone still on their feet.
			for f: Dictionary in b.ours + b.theirs:
				var npc: NPC = f.get("npc")
				if npc and is_instance_valid(npc) and not f["down"] and not f.get("fled", false):
					sum += npc.global_position
					n += 1
		world.camera_rig.look_at_point(sum / n if n > 0 else b._rally, distance, true)
		world.ui._map_banner.visible = false
		_clear_toasts(world)
		Input.warp_mouse(Vector2(4, 890))
		await _wait(6)
		await _shot(file_name)
	var t := 0.0
	var charge := -1.0
	var met := -1.0
	var taken := {}
	for i in 8000:
		if world.battle == null:
			break
		world._process(0.05)
		if world.battle:
			world.battle._process(0.05)
		t += 0.05
		if world.battle == null:
			break
		if charge < 0.0 and not b.mustering:
			charge = t
		if met < 0.0 and (b.ours + b.theirs).filter(func(f: Dictionary) -> bool: return f.get("engaged", false) and not f["down"]).size() >= 4:
			met = t
		if not taken.has("line") and t >= 2.0:
			taken["line"] = true
			await frame_on.call("keep_7_gate.png", 34.0)
		elif met >= 0.0 and not taken.has("melee") and t >= met + 3.0:
			taken["melee"] = true
			await frame_on.call("keep_8_melee.png", 18.0)
	print("keep: fight over in %.0f s (charge at %.0f, the lines met at %.0f)" % [t, charge, met])
	await _wait(10)
	_clear_toasts(world)
	await _shot("keep_9_report.png")
	print("keep: report %s" % st.military.last_report)


## How raids fought in the village turn out against the captains' odds
## (Military.odds, fought out of sight), with and without the levy, on a few
## seeds (BATTLE_SEEDS="1,2,3"). Runs headless: the fight is stepped by hand.
## BATTLE_KEEP=timber or stone fights at the house's castle, BATTLE_HOST=1
## against a noble house's host (Phase 5.3).
func _battle_stats() -> void:
	var seeds := OS.get_environment("BATTLE_SEEDS").split(",", false) if not OS.get_environment("BATTLE_SEEDS").is_empty() else PackedStringArray(["12345", "9", "4242", "7", "31"])
	var keep := OS.get_environment("BATTLE_KEEP")
	var host := OS.get_environment("BATTLE_HOST") == "1"
	for s in seeds:
		for levy: bool in [false, true]:
			Game.state = WorldGenerator.generate(s)
			var st := Game.state
			st.minutes += 70.0 * Calendar.MINUTES_PER_DAY
			if not keep.is_empty():
				var gold := st.house.gold
				st.house.gold = 99999
				st.territory.charter = 2
				for k: String in CastleSystem.KINDS:
					CastleSystem.order(st, k)
					CastleSystem.complete(st)
					if k == keep:
						break
				st.house.gold = gold
			if host:
				st.realm.houses[0]["standing"] = -60
				Military.plan_host(st, int(st.realm.houses[0]["id"]), Seeds.rng(st.world_seed, "capture_host"))
			else:
				Military.plan_raid(st, Seeds.rng(st.world_seed, "capture_raid"))
			st.military.raid["day"] = st.day()
			if levy:
				Military.call_levy(st)
			var odds := Military.odds(st)
			st.minutes = float(st.day() * Calendar.MINUTES_PER_DAY + Military.strike_hour() * 60) + 1.0
			var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
			add_child(world)
			await _wait(2)
			world._process(0.016)
			var res := {}
			var b := world.battle
			print("battle_stats: %s rally %.0f m from the square, %.1f m clear of buildings" % [s, b._rally.distance_to(st.layout.square_center), b._clearance(b._rally)])
			var tally := {"ours_swings": 0, "ours_hits": 0, "theirs_swings": 0, "theirs_hits": 0}
			b.finished.connect(func(r: Dictionary, _e: Array) -> void:
				res.merge(r)
				for f: Dictionary in b.ours:
					tally["ours_swings"] += int(f.get("swings", 0))
					tally["ours_hits"] += int(f.get("hits", 0))
				for f: Dictionary in b.theirs:
					tally["theirs_swings"] += int(f.get("swings", 0))
					tally["theirs_hits"] += int(f.get("hits", 0)))
			var t := 0.0
			var muster := -1.0
			for i in 8000:
				world._process(0.05)
				if world.battle:
					world.battle._process(0.05)
					if muster < 0.0 and not world.battle.mustering:
						muster = t
				t += 0.05
				if world.battle == null:
					break
			var ours: Array = res.get("ours", [])
			print("battle_stats: %s levy=%s odds %.2f -> %s in %.0fs (charge at %.0fs): raiders fell %d/%d, ours fell %d/%d, died %d  %s" % [s, levy, odds,
				"WON " if res.get("won", false) else "lost", t, muster, res.get("raiders_fallen", 0), res.get("size", 0),
				ours.filter(func(l: Dictionary) -> bool: return l["fell"]).size(), ours.size(), ours.filter(func(l: Dictionary) -> bool: return l["died"]).size(), tally])
			world.queue_free()
			await _wait(2)


func _clear_toasts(world: VillageWorld) -> void:
	for n in world.ui.find_children("*", "", true, false):
		if n is ToastStack:
			for t in n.get_children():
				t.queue_free()


## Villagers' remarks as the heir walks past (Barks): a few people at work
## and about the square, each spoken to through the real system.
func _bark_shots() -> void:
	GameSettings.memory_only = true
	GameSettings.set_bool("gameplay/remarks", true)
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	var st := world.state
	var heir := world.player_npc()
	world.barks = Barks.new(st.world_seed)
	world.barks.cfg["chance"] = 1.0
	world.barks.cfg["chance_traits"] = {}
	world.barks.cfg["gap"] = 0.0
	var shots := 0
	var seen := {}
	for p in st.characters:
		if shots >= 4:
			break
		var npc := world.npc_of(p.id)
		if st.is_player(p) or npc == null or not npc.visible or seen.has(p.occupation_id):
			continue
		var spot := Vector3.INF
		for i in 16:
			var q := npc.global_position + Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0)) * 3.2
			if not WorldGeometry.inside_building(st, q, 0.8) and not WorldGeometry.line_blocked(st, q, npc.global_position):
				spot = q
				break
		if spot == Vector3.INF:
			continue
		seen[p.occupation_id] = true
		npc.brain.set_errand({"type": "hold", "face": spot})
		heir.teleport(spot + (spot - npc.global_position).normalized() * 12.0)
		world._process(0.3)
		heir.teleport(spot)
		var to := npc.global_position - spot
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.follow_target = heir
		world.camera_rig.set_yaw(heir.rotation.y + 0.6, true)
		for n in world.ui.find_children("*", "", true, false):
			if n is ToastStack:
				for t in n.get_children():
					t.queue_free()
		for i in 6:
			world._process(0.1)
		await _wait(24)
		if npc.is_speaking():
			print("barks: %s (%s): %s" % [p.full_name(), p.occupation_name(), npc.speech()])
			shots += 1
			await _shot("bark_%d.png" % shots)
		world.hush_remarks()


func _eye_shots() -> void:
	GameSettings.memory_only = true
	GameSettings.set_bool("accessibility/captions", true)
	GameSettings.set_bool("accessibility/reduced_motion", OS.get_environment("EYE_CALM") == "1")
	GameSettings.set_bool("accessibility/reduce_flashes", OS.get_environment("EYE_CALM") == "1")
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui._help.visible = false
	world.set_speed(0)
	var st := world.state
	var heir := world.player_npc()
	var only := OS.get_environment("EYE_TIERS")
	for tier_id: String in ["ordinary", "skilled", "exceptional", "legendary"]:
		if not only.is_empty() and not tier_id in only.split(","):
			continue
		GameSettings.set_bool("eye/seen_" + tier_id, false)
		var c: CharacterData = null
		for p in st.characters:
			if st.is_player(p) or CourtSystem.is_kin(st, p) or p.age < 18 or Discovery.tier_id(p) != tier_id:
				continue
			var npc := world.npc_of(p.id)
			if npc == null or not npc.visible:
				continue
			if c == null or (p.best_potential() > c.best_potential()) == (tier_id != "ordinary"):
				c = p
		if c == null:
			print("eye: no %s person outdoors" % tier_id)
			continue
		var target := world.npc_of(c.id)
		var spot := target.global_position + Vector3(0, 0, 3.0)
		for i in 16:
			var p := target.global_position + Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0)) * 3.0
			if not WorldGeometry.inside_building(st, p, 0.6) and not WorldGeometry.line_blocked(st, p, target.global_position):
				spot = p
				break
		target.brain.set_errand({"type": "hold", "face": spot})
		heir.teleport(spot)
		var to := target.global_position - spot
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.follow_target = heir
		world.camera_rig.set_yaw(heir.rotation.y + 0.5, true)
		# As in play: the person faced is the one in focus.
		world._preferred_focus = c.id
		world._set_focus(target)
		world._process(0.05)
		# The welcome notice has had its say by the time anyone is looked at.
		for n in world.ui.find_children("*", "", true, false):
			if n is ToastStack:
				for t in n.get_children():
					t.queue_free()
		await _wait(20)
		var check := world.scan_check(c.id)
		if not check["ok"]:
			print("eye: can't look at %s: %s" % [c.full_name(), check["reason"]])
			continue
		world.use_eye(c.id)
		var reveal: EyeReveal = world._reveal
		# When each beat falls, from the tier's own steps.
		var steps := EyeReveal.steps_for(reveal.tier, false, reveal.reduced, reveal.no_flash)
		var scale := float(Discovery.eye_config().get("reduced_motion_time", 0.7)) if reveal.reduced else 1.0
		var beats := {}
		var t := 0.0
		for s: Dictionary in steps:
			var type := str(s.get("type", ""))
			var dt := 0.0 if type in ["focus", "particles", "sound"] else float(s.get("time", 0.0)) * scale
			if type == "eye":
				beats["eye"] = t + dt * 0.92
			elif type in ["clue", "sweep"]:
				beats["card"] = t + dt * 0.9
			elif type == "shake":
				beats["crack"] = t + dt * 0.95
			elif type == "particles":
				beats["burst"] = t + 0.3
			t += dt
		var elapsed := 0.0
		var order := beats.keys()
		order.sort_custom(func(a: String, b: String) -> bool: return float(beats[a]) < float(beats[b]))
		for beat: String in order:
			while elapsed < float(beats[beat]) and not reveal.done:
				await get_tree().process_frame
				elapsed += get_process_delta_time()
			await _shot("eye_%s_%s.png" % [tier_id, beat])
		while not reveal.done:
			await get_tree().process_frame
		await _wait(45)
		await _shot("eye_%s_final.png" % tier_id)
		print("eye: %s  %s (%s, best %d), %.2f s" % [tier_id, c.full_name(), c.occupation_id, c.best_potential(), t])
		reveal._finish("close")
		await _wait(10)


## Main menu Sound panel and the in-game pause menu (volume sliders).
func _menu_shots() -> void:
	var menu: Control = load("res://scenes/main/main.tscn").instantiate()
	add_child(menu)
	await _wait(60)  # past the fade-in
	await _shot("14_main_menu.png")
	menu.call("_show_new_game")
	await _wait(5)
	await _shot("15_menu_new_game.png")
	menu.call("_show_menu")
	menu.call("_show_sound")
	await _wait(5)
	await _shot("16_menu_sound.png")
	menu.call("_show_keys")
	await _wait(5)
	await _shot("16_menu_keys.png")
	menu.queue_free()
	Game.state = WorldGenerator.generate(seed_text)
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.ui.open_pause_menu()
	await _wait(5)
	await _shot("17_pause_sound.png")
	# The keys, one of them waiting for its new key.
	GameSettings.memory_only = true
	world.ui._open_keys()
	world.ui._keys.assign("sovereign_eye", KEY_G)
	world.ui._keys._capture("interact")
	await _wait(5)
	await _shot("18_pause_keys.png")
	world.ui._keys.cancel()
	InputSetup.reset_keys()



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
		LifeSystem.daily_update(st)
		for e: Dictionary in MatchSystem.daily_update(st):
			# plan "matches": the house takes a suitor of B rank or better.
			if e.has("visitor") and plan.get("matches", false):
				var suitor := st.get_character(int(e["visitor"]))
				if suitor.best_potential() >= 65:
					MatchSystem.accept(st, suitor)
				else:
					MatchSystem.decline(st, suitor)
		Succession.daily_update(st)
		var war: Array[Dictionary] = Military.daily_update(st)
		if Military.due(st):
			Military.fight(st, war)
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

