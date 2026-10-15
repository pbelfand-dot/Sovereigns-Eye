extends TestCase
## Boots the real world scene headlessly and drives it: NPCs must move,
## clicking must find them, the card and ledger must fill, and a save made
## mid-day must restore positions and moods.

const SLOT := "test_smoke"


func _boot(seed_text: String) -> VillageWorld:
	Game.state = WorldGenerator.generate(seed_text)
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	return world


## Advances the simulation by `real_seconds` in fixed steps.
func _simulate(world: VillageWorld, real_seconds: float, step: float = 0.1) -> void:
	var n := int(real_seconds / step)
	for i in n:
		world._process(step)


func test_world_boots_and_villagers_live() -> void:
	var world: VillageWorld = await _boot("smoke-seed")
	check_eq(world.npcs.size(), world.state.characters.size(), "one body per character")
	check(world.builder.building_nodes.size() >= 15, "buildings were built")

	var start := {}
	for id: int in world.npcs:
		start[id] = world.npcs[id].global_position
	world.set_speed(3)
	var start_minutes := world.state.minutes
	_simulate(world, 30.0)  # 30 s at 8x = 6 in-game hours
	check(world.state.minutes >= start_minutes + 300.0, "clock advanced (%.0f -> %.0f)" % [start_minutes, world.state.minutes])

	var moved := 0
	var outdoors := 0
	var with_activity := 0
	for id: int in world.npcs:
		var npc: NPC = world.npcs[id]
		if npc.global_position.distance_to(start[id]) > 2.0:
			moved += 1
		if npc.visible:
			outdoors += 1
		if not npc.character.activity_text.is_empty():
			with_activity += 1
	check(moved >= 30, "most villagers walked somewhere (%d moved)" % moved)
	check(outdoors >= 15, "daytime village is busy (%d outdoors)" % outdoors)
	check_eq(with_activity, world.npcs.size(), "everyone is doing something")

	# Picking (on the map table): project a visible villager to the screen
	# and click there.
	world.set_view_mode("overview")
	var target: NPC = null
	for npc: NPC in world.npcs.values():
		if npc.visible and not npc.is_moving() and npc != world.player_npc():
			var cam := world.camera_rig.camera
			world.camera_rig.look_at_point(npc.global_position, 25.0, true)
			if not cam.is_position_behind(npc.global_position):
				target = npc
				break
	check(target != null, "found a visible villager")
	if target:
		var screen := world.camera_rig.camera.unproject_position(target.global_position + Vector3(0, 1.0, 0))
		var picked := world.pick_npc(screen)
		check(picked == target, "clicking a villager selects them")
		world._on_clicked(screen)
		check(not target.character.appraised, "selecting someone doesn't reveal them")
		check(world.ui._card.visible, "character card opens")
		check_eq(world.ui._card._name_label.text, target.character.full_name(), "card shows the right person")
		check(not world.ui._card._banner.visible, "no talent banner before the Eye")
		check(world.ui._card._appraisal_box.get_child_count() >= 2, "the unseen card explains how to learn more")
		check(world.ui._card._history_box.get_child_count() >= 1, "history rows are built")

	world.ui.toggle_ledger()
	check_eq(world.ui._ledger._list.get_child_count(), world.state.characters.size(), "ledger lists everyone")

	# Run past midnight so the daily mood update fires.
	var day_before := world.state.last_daily_update
	_simulate(world, 90.0)
	check(world.state.last_daily_update > day_before, "a new day began and moods updated")
	world.queue_free()
	await frames(1)


func test_save_restores_live_state() -> void:
	var world: VillageWorld = await _boot("save-seed")
	world.set_speed(3)
	_simulate(world, 20.0)
	var probe: CharacterData = world.state.characters[5]
	world.appraise(probe)
	check(Game.save_game(SLOT), "save through Game succeeds")
	var npc := world.npc_of(probe.id)
	var saved_pos := npc.global_position
	var saved_inside := probe.inside_building_id
	var saved_happiness := probe.happiness
	world.queue_free()
	await frames(1)

	var loaded := SaveManager.load_state(SLOT)
	check(loaded != null, "save loads")
	if loaded:
		var c := loaded.get_character(probe.id)
		check(c.position.distance_to(saved_pos) < 0.05, "position restored")
		check_eq(c.inside_building_id, saved_inside, "indoor/outdoor state restored")
		check(absf(c.happiness - saved_happiness) < 0.02, "happiness restored")
		check(c.appraised, "appraisal remembered")
		Game.state = loaded
		var world2: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
		runner.add_child(world2)
		# Checked before any frame runs: once time flows they walk on.
		var respawn := world2.npc_of(probe.id).global_position
		check(respawn.distance_to(saved_pos) < 0.1, "NPC respawns where it was saved (%s vs %s, inside %d)" % [respawn, saved_pos, saved_inside])
		await frames(2)
		world2.queue_free()
		await frames(1)
	SaveManager.delete(SLOT)


func test_building_rises_in_the_live_world() -> void:
	var world: VillageWorld = await _boot("smoke-build")
	var st := world.state
	st.house.gold = 500
	var spot := TerritorySystem.find_spot(st, "quarry")
	check(not spot.is_empty(), "a spot for a yard")
	if spot.is_empty():
		world.queue_free()
		return
	world.start_placing("quarry")
	check(world.is_placing(), "the Build menu starts placement")
	world.preview_at(spot["pos"])
	check(world.placement_reason().is_empty(), "the preview accepts a good spot")
	world.confirm_placement()
	check(not world.is_placing(), "placing ends after a click")
	check_eq(st.territory.sites.size(), 1, "a site is opened")
	if st.territory.sites.is_empty():
		world.queue_free()
		return
	var site := st.territory.sites[0]
	check(world.builder.site_nodes.has(site.id()), "the site is drawn")
	# Most of the work done already, so the test stays quick.
	site.work_done = site.work_needed * 0.7
	world.set_speed(3)
	var crew_at_work := false
	for i in 400:
		world._process(0.1)
		if not crew_at_work:
			for id in site.builders:
				var npc := world.npc_of(id)
				if npc and npc.character.activity_text.begins_with("Building"):
					crew_at_work = true
		if st.territory.sites.is_empty():
			break
	check(crew_at_work, "the crew walks over and builds")
	check(st.territory.sites.is_empty(), "the yard is finished within a few days")
	check(world.builder.building_nodes.has(site.id()), "the finished building is drawn")
	check(not world.builder.site_nodes.has(site.id()), "the site is cleared away")
	var path := world.graph.find_path(st.layout.square_center, site.building.door_position())
	check(path.size() >= 2, "the new door is on the road network")
	world.queue_free()
	await frames(2)


func test_settlers_walk_into_the_live_world() -> void:
	var world: VillageWorld = await _boot("smoke-settlers")
	var st := world.state
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 600.0
	var site := GrowthSystem.order_home(st)
	check(site != null, "the village orders a cottage")
	if site == null:
		world.queue_free()
		return
	world._on_growth_event({"text": "test", "kind": "info", "site": site.id()})
	check(world.builder.site_nodes.has(site.id()), "the cottage site is drawn")
	site.work_done = site.work_needed
	world._finish_site(site)
	check(world.builder.building_nodes.has(site.id()), "the finished cottage is drawn")
	var fam := GrowthSystem.settle(st)
	check(fam != null, "a family settles")
	if fam == null:
		world.queue_free()
		return
	var start := {}
	for id in fam.member_ids:
		start[id] = st.get_character(id).position
	world._on_growth_event({"text": "test", "kind": "join", "arrived": fam.member_ids.duplicate()})
	for id in fam.member_ids:
		check(world.npc_of(id) != null, "settler %d has a body" % id)
	world.set_speed(2)
	for i in 200:
		world._process(0.1)
	var walked := 0
	for id in fam.member_ids:
		var npc := world.npc_of(id)
		if npc and npc.global_position.distance_to(start[id]) > 8.0:
			walked += 1
	check_eq(walked, fam.member_ids.size(), "every settler walks in from the edge of the map")
	world.queue_free()
	await frames(2)


func test_buildings_can_be_clicked() -> void:
	var world: VillageWorld = await _boot("smoke-pick-building")
	var tavern := world.state.layout.buildings_of_type("tavern")[0]
	world.set_view_mode("overview")
	world.camera_rig.look_at_point(tavern.position, 40.0, true)
	await frames(2)
	var cam := world.camera_rig.camera
	var screen := cam.unproject_position(TerrainHeight.on_ground(tavern.position) + Vector3(0, 3.0, 0))
	check_eq(world.pick_building(screen), tavern.id, "clicking the tavern picks the tavern")
	world._on_clicked(screen)
	check_eq(world.selected_building, tavern.id, "the tavern is selected")
	check(world.ui.is_building_card_open(), "its card opens")
	world.deselect()
	check(not world.ui.is_building_card_open(), "deselecting closes it")
	check(world.pick_building(cam.unproject_position(world.state.layout.square_center)) == -1, "the empty square picks nothing")
	world.queue_free()
	await frames(2)


## Puts the heir `dist` meters from `target` on open ground, facing them,
## and the camera behind the heir. Returns false if there's no clear spot.
func _stand_near(world: VillageWorld, target: NPC, dist: float) -> bool:
	var heir := world.player_npc()
	var st := world.state
	for i in 16:
		var a := TAU * i / 16.0
		var p := target.global_position + Vector3(cos(a), 0, sin(a)) * dist
		if WorldGeometry.inside_building(st, p, 0.6) or WorldGeometry.line_blocked(st, p, target.global_position):
			continue
		heir.teleport(p)
		var to := target.global_position - p
		heir.rotation.y = atan2(-to.x, -to.z)
		world.camera_rig.set_yaw(heir.rotation.y, true)
		return true
	return false


## A villager standing still on open ground near the square (held so they
## don't wander off mid-test).
func _still_villager(world: VillageWorld) -> NPC:
	var st := world.state
	var spot := Vector3.INF
	for r in range(8, 40, 2):
		for k in 12:
			var p := st.layout.square_center + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * r
			if not WorldGeometry.inside_building(st, p, 8.0) and WorldGeometry.resolve(st, p, 0.6) == p:
				spot = p
				break
		if spot != Vector3.INF:
			break
	if spot == Vector3.INF:
		return null
	for npc: NPC in world.npcs.values():
		var c := npc.character
		if npc == world.player_npc() or CourtSystem.is_kin(st, c) or c.age < 18 or c.retainer:
			continue
		npc.brain.set_errand({"type": "hold", "face": spot + Vector3(0, 0, 1)})
		npc.brain.update(0.0)
		npc.teleport(spot)
		return npc
	return null


func test_walk_scan_talk_and_recruit_in_the_live_world() -> void:
	var world: VillageWorld = await _boot("smoke-eye")
	var st := world.state
	GameSettings.memory_only = true
	for t: String in ["ordinary", "skilled", "exceptional", "legendary"]:
		GameSettings.set_bool("eye/seen_" + t, true)
	check_eq(world.mode, "walk", "you start on foot as the heir")
	check_eq(world.camera_rig.mode, "follow", "the camera follows the heir")
	check(world.camera_rig.follow_target == world.player_npc(), "following the heir")
	var heir := world.player_npc()
	var target := _still_villager(world)
	check(target != null and heir != null, "found the heir and a villager")
	if target == null or heir == null:
		world.queue_free()
		return
	var c := target.character
	check(not c.met and not c.appraised, "a stranger at first")
	world.set_speed(0)

	# Too far: the Eye won't reach.
	check(_stand_near(world, target, 24.0), "found a spot far away")
	world._process(0.05)
	world.use_eye(c.id)
	check(not world.is_revealing(), "the Eye can't reach someone across the village")

	# Near and in sight: they come into focus, and the Eye works, no talk needed.
	check(_stand_near(world, target, 6.0), "found a spot nearby")
	for i in 3:
		world._process(0.05)
	await frames(1)
	check(world.focus == target, "the person in front of the heir is in focus")
	check(world.ui._prompt.visible, "a prompt shows what you can do")
	check(world.ui._prompt_keys.text.contains("Sovereign's Eye"), "including the Eye: %s" % world.ui._prompt_keys.text)
	check(world.ui._prompt_keys.text.contains("walk closer"), "talking needs you closer")
	world.use_eye(c.id)
	check(world.is_revealing(), "the Eye's reveal plays without talking first")
	check(not c.met, "no conversation was needed")
	await frames(2)
	world._reveal._skipping = true
	for i in 30:
		await frames(1)
		if world._reveal.done:
			break
	check(c.appraised, "they're appraised")
	world._reveal._finish("talk")
	await frames(1)
	check(world.talking_to < 0, "from 6 paces you still have to walk up to talk")

	# Walk up (camera-relative movement, real time) and talk.
	world.set_speed(0)
	world.paused = false
	var start := heir.global_position
	world.heir_ctl.scripted_move = Vector2(0, 1)
	for i in 30:
		world._process(0.05)
		if Vector2(heir.global_position.x - target.global_position.x, heir.global_position.z - target.global_position.z).length() < 2.2:
			break
	world.heir_ctl.scripted_move = null
	world._process(0.05)
	check(heir.global_position.distance_to(start) > 1.5, "the heir walks forward")
	check(world.talk_check(c.id)["ok"], "and arrives close enough to talk")
	c.player_opinion = 80.0
	c.traits = ["loyal"] as Array[String]
	check(world.try_talk(c.id), "E opens the conversation")
	check_eq(world.talking_to, c.id, "they're talking")
	await frames(1)
	var panel := world.ui.conversation_panel()
	check(panel.visible, "the conversation shows")
	panel._on_ask()
	check(not c.known_motives.is_empty(), "asking about their life reveals what they want")
	panel._on_make()
	panel.offer = {"wage": 2, "home": -1, "position": "household", "appeal": false}
	panel._on_propose()
	check(c.retainer, "a fond, loyal villager accepts a fair offer")
	panel.flush()
	check(panel._log.get_child_count() >= 4, "the talk and their answer are written out")
	world.end_conversation()
	check(world.talking_to < 0, "farewell ends it")

	# The map table and back.
	world.toggle_overview()
	check_eq(world.mode, "overview", "Tab opens the map table")
	check_eq(world.camera_rig.mode, "strategy", "with the overhead camera")
	check(world.ui._map_banner.visible, "and says how to get back")
	world._process(0.05)
	check(not world.heir_ctl.enabled, "the heir doesn't walk while you plan")
	world.toggle_overview()
	check_eq(world.mode, "walk", "back in the heir's boots")
	check(world.camera_rig.follow_target == heir, "following the heir again")
	world.start_placing("cottage")
	check_eq(world.mode, "overview", "building is done from the map table")
	world.cancel_placing()
	world.queue_free()
	await frames(2)


func test_the_heir_cannot_walk_through_walls() -> void:
	var world: VillageWorld = await _boot("smoke-walls")
	var st := world.state
	var heir := world.player_npc()
	var b := st.layout.buildings[0]
	for bd in st.layout.buildings:
		if bd.type in ["cottage", "farmhouse", "smithy", "bakery"]:
			b = bd
			break
	# Stand 6 m in front of its door and walk straight at it for a while.
	var front := b.basis() * Vector3(0, 0, 1)
	heir.teleport(b.position + front * (b.footprint.y * 0.5 + 6.0))
	world.camera_rig.set_yaw(atan2(front.x, front.z), true)
	world._process(0.01)
	world.heir_ctl.scripted_move = Vector2(0, 1)
	world.heir_ctl.scripted_run = true
	for i in 80:
		world._process(0.05)
		if WorldGeometry.inside_building(st, heir.global_position, 0.3):
			check(false, "never inside %s (step %d)" % [b.name, i])
			break
	world.heir_ctl.scripted_move = null
	var gap := (heir.global_position - b.position).dot(front) - b.footprint.y * 0.5
	check(gap >= 0.25 and gap < 1.2, "stops against the wall (%.2f m away)" % gap)
	# Turn the camera round so the house stands between it and the heir:
	# the camera rises over the roof instead of hiding the heir.
	world.camera_rig.set_yaw(atan2(front.x, front.z) + PI, true)
	for i in 40:
		world.camera_rig._process(0.1)
	world._process(0.05)
	var cam := world.camera_rig.camera.global_position
	var focus := world.camera_rig.focus_point()
	check(world.camera_rig._lift > deg_to_rad(10.0), "the camera rises over the roof")
	var hidden: Array[String] = []
	for bd in st.layout.buildings:
		if world._segment_hits_building(bd, focus, cam) < 1.0 and not world.is_faded(bd.id):
			hidden.append(bd.name)
	check(hidden.is_empty(), "nothing hides the heir: whatever is still in the way fades (%s)" % ", ".join(hidden))
	check(world.is_faded(b.id) or world.view_blocked_at(focus, cam) >= 1.0, "the house behind is cleared or faded")
	world.toggle_overview()
	world._process(0.05)
	check(world._faded.is_empty(), "the map table shows every building whole")
	# The edge of the map holds too.
	heir.teleport(Vector3(st.layout.extent - 7.0, 0, 0))
	world.camera_rig.set_yaw(-PI * 0.5, true)
	world.heir_ctl.scripted_move = Vector2(0, 1)
	for i in 60:
		world._process(0.05)
	world.heir_ctl.scripted_move = null
	check(Vector2(heir.global_position.x, heir.global_position.z).length() <= st.layout.extent - 5.9, "the heir stays inside the map")
	world.queue_free()
	await frames(2)


func test_click_to_move_and_touch_controls() -> void:
	var world: VillageWorld = await _boot("smoke-touch")
	var st := world.state
	var heir := world.player_npc()
	GameSettings.memory_only = true
	# Click to move (accessibility): walks along the roads to the spot.
	var goal := st.layout.square_center + Vector3(4, 0, 3)
	heir.teleport(st.layout.square_center + Vector3(-10, 0, 8))
	world.heir_ctl.walk_to(goal)
	for i in 200:
		world._process(0.05)
		if not world.heir_ctl.is_auto_walking():
			break
	check(Vector2(heir.global_position.x - goal.x, heir.global_position.z - goal.z).length() < 1.5, "click-to-move arrives")
	# The touch stick drives the heir like the left stick.
	GameSettings.set_bool("controls/touch_controls", true)
	world._process(0.05)
	var touch := world.ui._touch
	touch._process(0.0)
	check(touch.visible, "on-screen controls can be switched on")
	var stick := touch._stick
	await frames(1)
	var c := stick.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.index = 1
	down.pressed = true
	down.position = c
	stick._input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = c + Vector2(0, -stick.radius())
	stick._input(drag)
	check(stick.value.y > 0.9, "pushing the stick up means forward (%s)" % stick.value)
	var before := heir.global_position
	for i in 10:
		touch._process(0.0)
		world._process(0.05)
	check(heir.global_position.distance_to(before) > 0.5, "the heir walks with the stick")
	var up := InputEventScreenTouch.new()
	up.index = 1
	up.pressed = false
	up.position = drag.position
	stick._input(up)
	check(stick.value == Vector2.ZERO, "letting go stops")
	# Two fingers on open ground pinch to zoom.
	var mid := Vector2(640, 260)
	var dist_before := world.camera_rig._target_distance
	for i in 2:
		var t := InputEventScreenTouch.new()
		t.index = i
		t.pressed = true
		t.position = mid + Vector2(-40 if i == 0 else 40, 0)
		touch._input(t)
	var spread := InputEventScreenDrag.new()
	spread.index = 1
	spread.position = mid + Vector2(160, 0)
	spread.relative = Vector2(120, 0)
	touch._input(spread)
	check(world.camera_rig._target_distance < dist_before, "spreading two fingers zooms in")
	check(world.camera_rig.pinching, "and isn't taken for a camera turn")
	for i in 2:
		var t2 := InputEventScreenTouch.new()
		t2.index = i
		t2.pressed = false
		touch._input(t2)
	check(not world.camera_rig.pinching, "lifting the fingers ends the pinch")
	GameSettings.set_bool("controls/touch_controls", false)
	world.queue_free()
	await frames(2)


func test_a_charter_in_the_live_world() -> void:
	var world: VillageWorld = await _boot("smoke-charter")
	var st := world.state
	st.house.gold = 5000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 900.0
	await frames(1)
	check(world.ui._charter_label.text.contains("Hamlet"), "the top bar names the charter: %s" % world.ui._charter_label.text)
	world.ui.toggle_build()
	await frames(1)
	var panel_text := _all_text(world.ui._build)
	check(panel_text.contains("Charter: Hamlet"), "the Build panel shows the charter")
	check(panel_text.contains("Petition the Crown"), "with the petition")
	# Earn it (as if by play), then petition from the panel.
	st.house.renown = 20
	for c in st.characters:
		c.happiness = 70.0
	var homes := 0
	for b in GrowthSystem.homes(st):
		if GrowthSystem.can_level(b) and homes < 2:
			b.tier = 1
			homes += 1
	var next_id := 1000
	while st.characters.size() < 60:
		var copy := CharacterData.from_dict(st.characters[st.characters.size() % 40].to_dict())
		copy.id = next_id
		next_id += 1
		st.add_character(copy)
	var banners_before := st.layout.props_of_type("banner").size()
	world.petition_charter()
	await frames(2)
	check_eq(CharterSystem.title(st), "Village", "the petition is granted in the live world")
	check_eq(st.layout.props_of_type("banner").size(), banners_before + 2, "banners go up")
	check(world.ui._charter_label.text.contains("Village"), "the top bar updates")
	check(_all_text(world.ui._build).contains("Charter: Village"), "and the Build panel")
	world.ui.toggle_build()
	# A Village may raise a tavern: placement goes to the map table.
	world.start_placing("tavern")
	check_eq(world.mode, "overview", "placing a tavern opens the map table")
	check(world.is_placing(), "and places it")
	world.cancel_placing()
	# The charter survives a save and load.
	world.sync_to_state()
	var back := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	check_eq(back.territory.charter, 1, "saved with the game")
	world.queue_free()
	await frames(2)


## A real left click on a control, through the viewport like a player's.
func _click(world: VillageWorld, control: Control, device := 0) -> void:
	var at := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	move.device = device
	world.get_viewport().push_input(move, true)
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		ev.device = device
		world.get_viewport().push_input(ev, true)
		await frames(1)


## Talking is for making offers: the buttons answer real clicks and taps,
## the offer stays on screen, and a refusal never closes the door.
func test_offers_can_always_be_made_by_clicking() -> void:
	var world: VillageWorld = await _boot("smoke-offer")
	var st := world.state
	GameSettings.memory_only = true
	world.ui._help.visible = false
	var target := _still_villager(world)
	check(target != null, "found a villager")
	if target == null:
		world.queue_free()
		return
	var c := target.character
	world.set_speed(0)
	check(_stand_near(world, target, 2.0), "found a spot beside them")
	world._process(0.05)
	check(world.try_talk(c.id), "the conversation opens")
	await frames(3)
	var panel := world.ui.conversation_panel()
	panel.flush()
	await frames(1)
	check(panel.visible, "the conversation shows")
	check(not panel._make.disabled, "an offer can be made to a stranger, first thing")
	check(not panel._blocked.visible, "nothing says otherwise")

	# Click "Make an offer...": the terms open, on screen.
	await _click(world, panel._make)
	check(panel._offer_box.visible, "clicking Make an offer opens the terms")
	await frames(1)
	var screen := world.get_viewport().get_visible_rect()
	check(screen.encloses(panel.get_global_rect()), "the whole conversation fits on screen (%s in %s)" % [panel.get_global_rect(), screen])
	check(screen.encloses(panel._propose.get_global_rect()), "Propose is on screen")
	check(not panel._propose.disabled, "and can be pressed: %s" % panel._propose.tooltip_text)

	# A stingy offer to someone who doesn't care for you: refused, and the
	# terms stay open to improve.
	c.player_opinion = -40.0
	c.traits = [] as Array[String]
	for i in 10:
		if int(panel.offer.get("wage", 0)) == 0:
			break
		await _click(world, panel._wage_label.get_parent().get_child(1))
	check_eq(int(panel.offer.get("wage", -1)), 0, "the - button lowers the wage")
	await _click(world, panel._propose)
	panel.flush()
	await frames(2)
	check(not c.retainer, "a stingy offer to someone who dislikes you is turned down")
	var bar := panel._scroll.get_v_scroll_bar()
	check(bar.max_value > bar.page, "the talk is longer than the log (it scrolls)")
	check(bar.value >= bar.max_value - bar.page - 1.0, "the log follows to their answer (%d of %d, page %d)" % [roundi(bar.value), roundi(bar.max_value), roundi(bar.page)])
	var last := panel._log.get_child(panel._log.get_child_count() - 1) as Control
	check(panel._scroll.get_global_rect().grow(1.0).encloses(last.get_global_rect()), "the newest line is in view")
	check(panel.visible, "the conversation goes on")
	check(panel._offer_box.visible, "the terms stay open after a refusal")
	check(not panel._propose.disabled, "and you can propose again at once")
	check(not panel._make.disabled, "Make an offer is never locked")

	# Better terms, the same day: they take them.
	c.player_opinion = 80.0
	c.traits = ["loyal"] as Array[String]
	for i in 4:
		await _click(world, panel._wage_label.get_parent().get_child(3))
	check(int(panel.offer.get("wage", 0)) >= 4, "the + button raises the wage")
	await _click(world, panel._propose)
	panel.flush()
	if not c.retainer and panel._agree.visible:
		await _click(world, panel._agree)
	check(c.retainer, "a better offer is accepted right after a refusal")
	check(not panel._offer_box.visible, "the terms close once agreed")

	# Retainers can be offered new terms too.
	check(not panel._make.disabled, "you can still offer a retainer new terms")
	check_eq(panel._make.text, "Offer new terms...", "worded for someone already sworn")
	await _click(world, panel._make)
	check(panel._offer_box.visible, "and the terms open again")
	world.end_conversation()

	# On a touch screen, with the on-screen controls showing, a tap on the
	# offer buttons reaches them (taps arrive as emulated mouse clicks).
	GameSettings.set_bool("controls/touch_controls", true)
	var other := _still_villager(world)
	if other:
		check(_stand_near(world, other, 2.0), "found a spot beside another villager")
		world._process(0.05)
		check(world.try_talk(other.character.id), "a second conversation opens")
		await frames(3)
		world.ui._touch._process(0.0)
		await frames(1)
		panel.flush()
		await _click(world, panel._make, InputEvent.DEVICE_ID_EMULATION)
		check(panel._offer_box.visible, "a tap on Make an offer opens the terms with touch controls on")
		world.end_conversation()
	GameSettings.set_bool("controls/touch_controls", false)
	world.queue_free()
	await frames(2)


func _all_text(root: Node) -> String:
	var out := ""
	for n in root.find_children("*", "", true, false):
		if n is Label:
			out += (n as Label).text + "\n"
		elif n is Button:
			out += (n as Button).text + "\n"
	return out
