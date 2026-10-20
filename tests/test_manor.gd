extends TestCase
## Phase 6.3, the manor's dues and the Crown's levies (ManorSystem,
## ManorData, data/manor.json): the mill's toll and the querns, the fair,
## the Crown's levies on movables (declared or hidden), and saving them.


func _village(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.minutes = float(3 * Calendar.MINUTES_PER_DAY + 9 * 60)
	return st


func _set_happiness(st: WorldState, v: float) -> void:
	for c in st.characters:
		c.happiness = v


func test_the_mills_toll() -> void:
	var st := _village("manor-mill")
	_set_happiness(st, 60.0)
	var miller := ManorSystem.miller(st)
	check(miller != null, "the lord's mill has its miller")
	var pop := GrowthSystem.population(st)
	var per_head := float(ManorSystem.section("mill")["per_head"])
	check(is_equal_approx(ManorSystem.mill_income(st), pop * per_head), "the customary toll brings in %.1f gold a day from %d people" % [ManorSystem.mill_income(st), pop])
	var customary := ManorSystem.mill_income(st)
	check(ManorSystem.set_toll(st, "hard")["ok"] and ManorSystem.mill_income(st) > customary, "a harder toll, more (%.1f)" % ManorSystem.mill_income(st))
	var villager: CharacterData = null
	for c in st.characters:
		if not c.retainer and not st.is_player(c) and not CourtSystem.is_kin(st, c):
			villager = c
			break
	var felt := MoodSystem.happiness_factors(villager, st).filter(func(f: Dictionary) -> bool: return str(f["label"]).contains("toll"))
	check(felt.size() == 1 and float(felt[0]["value"]) < 0.0, "and the village resents it: %s" % str(felt))
	ManorSystem.set_toll(st, "light")
	check(ManorSystem.mill_income(st) < customary, "a lighter toll, less, and liked")
	var millers := st.characters.filter(func(x: CharacterData) -> bool: return x.occupation_id == "miller")
	for m: CharacterData in millers:
		m.away_at = "cart"
	check_eq(ManorSystem.mill_income(st), 0.0, "no miller at work, no toll: the village grinds at home")
	for m: CharacterData in millers:
		m.away_at = ""
	var before := CourtSystem.daily_income(st)
	ManorSystem.set_toll(st, "hard")
	check(CourtSystem.daily_income(st) > before, "the toll is in the house's income")


func test_hand_querns() -> void:
	var st := _village("manor-querns")
	_set_happiness(st, 60.0)
	check_eq(ManorSystem.querns_share(st), 0.0, "a contented village grinds at the mill")
	_set_happiness(st, 30.0)
	var share := ManorSystem.querns_share(st)
	check(share > 0.2, "an unhappy one grinds some at home on hand-querns (%.0f%%)" % (share * 100.0))
	var full := GrowthSystem.population(st) * float(ManorSystem.section("mill")["per_head"])
	check(ManorSystem.mill_income(st) < full * (1.0 - share) + 0.01, "and that pays no toll")
	var r := ManorSystem.seize_querns(st)
	check(r["ok"] and ManorSystem.querns_share(st) == 0.0, r["text"])
	check(not ManorSystem.seize_querns(st)["ok"], "(not again so soon)")
	var c: CharacterData = st.characters.filter(func(x: CharacterData) -> bool: return not x.retainer and not st.is_player(x) and not CourtSystem.is_kin(st, x))[0]
	check(MoodSystem.happiness_factors(c, st).any(func(f: Dictionary) -> bool: return float(f["value"]) == float(ManorSystem.section("mill")["seize_happiness"])), "the village resents it")
	st.minutes += float(int(ManorSystem.section("mill")["seize_days"]) + 1) * Calendar.MINUTES_PER_DAY
	check(ManorSystem.querns_share(st) > 0.0, "a season on, the querns are back")


func test_the_fair() -> void:
	var st := _village("manor-fair")
	st.house.gold = 2000
	check(not ManorSystem.can_grant_fair(st)["ok"], "a hamlet may not hold a fair: %s" % ManorSystem.can_grant_fair(st)["reason"])
	st.territory.charter = 2
	check(not ManorSystem.can_grant_fair(st)["ok"], "nor a Market Town without a Market Hall")
	var hall := BuildingData.new()
	hall.id = 9900
	hall.type = "market"
	hall.position = st.layout.square_center + Vector3(40, 0, 40)
	st.layout.buildings.append(hall)
	var r := ManorSystem.grant_fair(st)
	check(r["ok"] and st.house.gold == 2000 - int(ManorSystem.section("fair")["fee"]), r["text"])
	var fe := ManorSystem.feast(st)
	check(not fe.is_empty() and st.manor.fair_granted, "on the feast of %s" % fe.get("name", "?"))
	var start := ManorSystem.next_fair(st)
	var volume := Market.volume(st, "cloth")
	var spread := Market.spread(st)
	var cloth := Market.price(st, "cloth")
	var income := CourtSystem.daily_income(st)
	var renown := st.house.renown
	st.minutes = float(start * Calendar.MINUTES_PER_DAY + 8 * 60)
	var events := ManorSystem.daily_update(st)
	check(ManorSystem.fair_on(st) and events.any(func(e: Dictionary) -> bool: return e.has("fair")), "the fair opens on its feast")
	check(st.house.renown > renown, "and the house's renown grows (+%d)" % (st.house.renown - renown))
	check(Market.volume(st, "cloth") > volume * 3 and Market.spread(st) < spread, "the market trades more (%d cloth a day) on finer terms (%.2f)" % [Market.volume(st, "cloth"), Market.spread(st)])
	check(Market.price(st, "cloth") > cloth * 1.2 or Market.price(st, "cloth") > cloth + 0.5, "wares fetch more (%.2f against %.2f)" % [Market.price(st, "cloth"), cloth])
	check(ManorSystem.fair_income(st) > 30.0 and CourtSystem.daily_income(st) > income, "and the stallage is the lord's (%.0f gold a day)" % ManorSystem.fair_income(st))
	st.minutes += float(int(ManorSystem.section("fair")["days"])) * Calendar.MINUTES_PER_DAY
	check(not ManorSystem.fair_on(st) and ManorSystem.fair_income(st) == 0.0, "three days, and it's over")
	check(ManorSystem.next_fair(st) == start + Calendar.days_per_year(), "until next year")


func test_the_crowns_levies() -> void:
	var st := _village("manor-crown")
	st.minutes = 0.0
	var tithe := ManorSystem.levy_in(st, 1188)
	check(str(tithe.get("name", "")) == "the Saladin tithe" and is_equal_approx(float(tithe["share"]), 0.1), "1188: the Saladin tithe, a tenth")
	check_eq(int(ManorSystem.next_levy(st)["day"]), int(tithe["day"]), "the next levy the house will see")
	check(str(ManorSystem.levy_in(st, 1193).get("name", "")).contains("ransom"), "1193: King Richard's ransom")
	var later := 0
	for y in range(1208, 1240):
		if not ManorSystem.levy_in(st, y).is_empty():
			later += 1
	check(later >= 5 and later <= 11, "after the chronicle, a levy every few years (%d in 32)" % later)
	st.house.gold = 1000
	st.territory.stock["stone"] = 100.0
	var movables := ManorSystem.movables(st)
	check(movables > 1000, "the house's movables: its gold and its stores (%d)" % movables)
	var notice := int(tithe["day"]) - int(ManorSystem.section("crown")["notice_days"])
	st.minutes = float(notice * Calendar.MINUTES_PER_DAY)
	var events := ManorSystem.daily_update(st)
	check(events.any(func(e: Dictionary) -> bool: return e.has("levy_notice")), "announced ahead: %s" % (events[0]["text"] if not events.is_empty() else "nothing"))
	st.minutes = float(int(tithe["day"]) * Calendar.MINUTES_PER_DAY)
	var due := ManorSystem.levy_due(st, tithe)
	var gold := st.house.gold
	events = ManorSystem.daily_update(st)
	check(events.any(func(e: Dictionary) -> bool: return e.has("levy")) and st.house.gold == gold - due, "assessed and paid: %d gold" % due)
	check(st.manor.assessed.has(int(tithe["day"])) and str(ManorSystem.next_levy(st).get("name", "")).contains("ransom"), "and the next is the ransom")


## A world whose neighbours, at this levy, tell (or don't) as wanted.
func _levy_world(told: bool) -> Array:
	for i in 60:
		var st := _village("manor-hide-%d" % i)
		var levy := ManorSystem.levy_in(st, 1188)
		var roll := Seeds.counted_rng(st.world_seed, "levy_told_%d" % int(levy["day"])).randf()
		if told and roll < 0.75:
			_set_happiness(st, 0.0)
			return [st, levy]
		if not told and roll >= 0.25:
			_set_happiness(st, 90.0)
			return [st, levy]
	return []


func test_hiding_from_the_assessors() -> void:
	var quiet := _levy_world(false)
	check(not quiet.is_empty(), "a village that keeps quiet")
	if not quiet.is_empty():
		var st: WorldState = quiet[0]
		var levy: Dictionary = quiet[1]
		st.house.gold = 3000
		var full := ManorSystem.levy_due(st, levy)
		ManorSystem.set_hiding(st, true)
		var gold := st.house.gold
		var e := ManorSystem.assess(st, levy)
		check(gold - st.house.gold < full and not e["levy"]["exposed"], "hidden and not told: %s" % e["text"])
	var tells := _levy_world(true)
	check(not tells.is_empty(), "a village that tells")
	if not tells.is_empty():
		var st: WorldState = tells[0]
		var levy: Dictionary = tells[1]
		st.house.gold = 3000
		var full := ManorSystem.levy_due(st, levy)
		var renown := st.house.renown
		ManorSystem.set_hiding(st, true)
		var gold := st.house.gold
		var e := ManorSystem.assess(st, levy)
		check(gold - st.house.gold > full and e["levy"]["exposed"] and st.house.renown <= renown, "told on: the levy and a fine (%d against %d): %s" % [gold - st.house.gold, full, e["text"]])
		check_eq(st.manor.hide, 0.0, "(the next is declared in full unless chosen again)")


func test_short_of_gold() -> void:
	var st := _village("manor-short")
	var levy := ManorSystem.levy_in(st, 1193)
	st.house.gold = 0
	st.territory.stock["stone"] = 500.0
	var due := ManorSystem.levy_due(st, levy)
	var stone := TerritorySystem.amount(st, "stone")
	var e := ManorSystem.assess(st, levy)
	check(TerritorySystem.amount(st, "stone") < stone or TerritorySystem.amount(st, "food") < 1.0, "the sheriff takes stores for it: %s" % e["text"])
	check(int(e["levy"]["paid"]) > 0 and int(e["levy"]["due"]) == due, "(%d of %d)" % [int(e["levy"]["paid"]), due])


func test_the_manor_is_saved() -> void:
	var st := _village("manor-save")
	ManorSystem.set_toll(st, "light")
	st.manor.fair_granted = true
	st.manor.fair_feast = 2
	ManorSystem.set_hiding(st, true)
	st.manor.assessed.append(8)
	var copy := WorldState.from_dict(st.to_dict())
	check_eq(copy.manor.to_dict(), st.manor.to_dict(), "the toll, the fair and the levies are saved")
	var old := st.to_dict()
	old["save_version"] = 21
	old.erase("manor")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.manor.toll == "customary" and not migrated.manor.fair_granted and migrated.manor.assessed.is_empty(), "an older save takes the customary toll, without a fair")
	check_eq(int(SaveManager.migrate(old)["save_version"]), WorldState.SAVE_VERSION, "and is brought up to date")


func test_the_manor_in_the_world() -> void:
	Game.state = _village("manor-world")
	var st := Game.state
	st.house.gold = 3000
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	world.ui.toggle_court()
	await frames(2)
	var court: Control = world.ui._court
	var labels := court.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check(labels.any(func(t: String) -> bool: return t.begins_with("The lord's mill")), "the Court panel shows the mill")
	var hard: Button = null
	for b: Button in court.find_children("*", "Button", true, false):
		if b.text == "A thirteenth":
			hard = b
	check(hard != null and not hard.disabled, "with its tolls to choose")
	if hard:
		hard.pressed.emit()
	check_eq(st.manor.toll, "hard", "a harder toll is set")
	# A levy is coming: hide a third.
	var tithe := ManorSystem.levy_in(st, 1188)
	st.minutes = float((int(tithe["day"]) - 5) * Calendar.MINUTES_PER_DAY + 9 * 60)
	world.ui.toggle_court()
	world.ui.toggle_court()
	await frames(2)
	var hide: Button = null
	for b: Button in court.find_children("*", "Button", true, false):
		if b.text == "Hide a third":
			hide = b
	check(hide != null, "the coming levy offers a choice")
	if hide:
		hide.pressed.emit()
	check(st.manor.hide > 0.3, "to hide a third")
	# The fair: stalls in the square while it's on.
	st.territory.charter = 2
	st.manor.fair_granted = true
	st.manor.fair_feast = 0
	st.minutes = float(ManorSystem.next_fair(st) * Calendar.MINUTES_PER_DAY + 10 * 60)
	await frames(40)
	check(world.fair_view.stall_count() >= 4 and world.fair_view.get_child_count() > 0, "the fair's stalls stand in the square (%d)" % world.fair_view.stall_count())
	st.minutes += 4.0 * Calendar.MINUTES_PER_DAY
	await frames(40)
	check(world.fair_view.get_child_count() == 0, "and are gone when it's over")
	world.queue_free()
	await frames(2)
