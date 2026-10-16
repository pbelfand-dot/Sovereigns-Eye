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
var farm_only := false
var square_only := false
var smithy_only := false
var home_only := false
var thatch_only := false
var training_only := false
var chapel_only := false


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

