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

	# Picking: project a visible villager to the screen and click there.
	var target: NPC = null
	for npc: NPC in world.npcs.values():
		if npc.visible and not npc.is_moving():
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
		check(target.character.appraised, "selecting appraises")
		check(world.ui._card.visible, "character card opens")
		check_eq(world.ui._card._name_label.text, target.character.full_name(), "card shows the right person")
		check(world.ui._card._appraisal_box.get_child_count() >= 7, "appraisal rows are built")
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
