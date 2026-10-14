extends TestCase
## Phase 2 court rules: recruitment, offices, training, money, loyalty and
## backward-compatible saves.

const OLD_SLOT := "test_phase1_migration"


func _adult_outsiders(state: WorldState, count: int = 1) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for c in state.characters:
		if state.is_player(c) or CourtSystem.is_kin(state, c) or c.age < 16:
			continue
		out.append(c)
		if out.size() >= count:
			break
	return out


func test_house_setup_is_deterministic() -> void:
	var a := WorldGenerator.generate("court-setup")
	var b := WorldGenerator.generate("court-setup")
	check(a.house != null, "new games have a player house")
	check(a.player() != null, "new games choose a playable heir")
	check_eq(a.player_id, b.player_id, "the same seed chooses the same heir")
	check_eq(a.house.to_dict(), b.house.to_dict(), "the same seed creates the same house")
	check(a.is_player(a.player()), "the selected heir is recognized as the player")
	check(a.player().appraised, "the player knows their own abilities")


func test_recruitment_and_offices_update_both_sides() -> void:
	var state := WorldGenerator.generate("court-recruit")
	var people := _adult_outsiders(state)
	check(not people.is_empty(), "found an adult outsider")
	if people.is_empty():
		return
	var c := people[0]
	c.player_opinion = 100.0
	c.loyalty = 100.0
	state.house.gold = 1000
	var original_status := c.social_status
	var original_work := c.work_building_id
	var check_result := CourtSystem.recruit_check(state, c)
	check(check_result["ok"], "a willing outsider can be recruited")
	var gold_before := state.house.gold
	var result := CourtSystem.try_recruit(state, c, 0.0)
	check(result["success"], "a roll below the displayed chance succeeds")
	check(c.retainer, "the recruit is marked as a retainer")
	check_eq(state.house.gold, gold_before - int(check_result["cost"]), "the signing cost is paid")

	var appointed := CourtSystem.appoint(state, "steward", c)
	check(appointed["ok"], "an adult retainer can hold office")
	check_eq(c.office, "steward", "the character stores their office")
	check_eq(state.house.holder_of("steward"), c.id, "the house stores the office holder")
	CourtSystem.dismiss(state, c)
	check(not c.retainer, "dismissal removes retainer status")
	check_eq(state.house.holder_of("steward"), -1, "dismissal vacates the office")
	check_eq(c.social_status, original_status, "dismissal restores the former status")
	check_eq(c.work_building_id, original_work, "dismissal restores the former workplace")


func test_training_never_passes_potential() -> void:
	var state := WorldGenerator.generate("court-training")
	var people := _adult_outsiders(state)
	check(not people.is_empty(), "found a trainee")
	if people.is_empty():
		return
	var c := people[0]
	CourtSystem.join(state, c)
	c.set_attribute("combat", 10, 11)
	c.set_attribute("intelligence", 100, maxi(c.get_potential("intelligence"), 100))
	CourtSystem.set_focus(state, c, "combat")
	c.training_progress["combat"] = 0.99
	for i in 60:
		CourtSystem.train_day(state, c)
	check_eq(c.get_current("combat"), 11, "daily training reaches the cap")
	check_eq(c.get_potential("combat"), 11, "training does not change potential")
	check(float(c.training_progress.get("combat", 0.0)) < 1.0, "no unusable progress accumulates at the cap")


func test_retainers_use_household_schedules() -> void:
	var adult := CharacterData.new()
	adult.age = 75
	adult.retainer = true
	check_eq(CourtSystem.schedule_for(adult), "noble", "adult retainers attend household work even if they were elders")
	adult.age = 14
	check_eq(CourtSystem.schedule_for(adult), "scion", "pages keep a lesson-and-training day")


func test_unpaid_wages_and_low_loyalty_can_end_service() -> void:
	var state := WorldGenerator.generate("court-wages")
	var people := _adult_outsiders(state, 4)
	check_eq(people.size(), 4, "found four adult outsiders")
	if people.size() < 4:
		return
	var office_ids := ["steward", "marshal", "chancellor", "scholar"]
	for i in people.size():
		var c := people[i]
		CourtSystem.join(state, c)
		CourtSystem.appoint(state, office_ids[i], c)
		c.loyalty = 0.0
	state.house.gold = 0
	check(CourtSystem.daily_wages(state) > CourtSystem.daily_income(state), "the test household cannot cover wages")

	# Pick a deterministic RNG seed whose first departure roll succeeds.
	var chosen_seed := 0
	for seed in 1000:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed
		if probe.randf() < float(CourtSystem.section("loyalty").get("leave_chance", 0.12)):
			chosen_seed = seed
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = chosen_seed
	var events := CourtSystem.daily_update(state, rng)
	check(state.house.in_debt, "the house records unpaid wages")
	check(state.retainers().size() < people.size(), "a deeply disloyal retainer can leave")
	var saw_departure := false
	for event: Dictionary in events:
		if str(event.get("kind", "")) == "bad" and event.has("character"):
			saw_departure = true
	check(saw_departure, "departure is reported to the UI")


func test_phase1_save_migrates_to_a_playable_house() -> void:
	var original := WorldGenerator.generate("court-migration")
	var old := original.to_dict()
	old["save_version"] = 1
	old.erase("player")
	old.erase("house")
	for c: Dictionary in old["characters"]:
		for key: String in ["retainer", "office", "focus", "player_opinion", "training_progress", "last_talk_day", "recruit_retry_day", "former_status", "former_work", "joined_day"]:
			c.erase(key)
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var file := FileAccess.open(SaveManager.slot_path(OLD_SLOT), FileAccess.WRITE)
	check(file != null, "created a Phase 1-format save")
	if file == null:
		return
	file.store_string(JSON.stringify(old))
	file.close()

	var loaded := SaveManager.load_state(OLD_SLOT)
	check(loaded != null, "Phase 1 save loads")
	if loaded:
		check(loaded.house != null, "migration creates the house")
		check(loaded.player() != null, "migration chooses a playable heir")
		check_eq(loaded.to_dict()["save_version"], WorldState.SAVE_VERSION, "migration writes the current version")
	SaveManager.delete(OLD_SLOT)
