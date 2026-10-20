extends TestCase
## Phase 5.2, the wider realm (Realm, RealmData, data/realm.json; the camps
## in Military): the houses' seats on a map, their regard (fading, raised by
## visits, gifts, talk, fostering, clearing camps), the heir's visits and
## what's done at a seat (the young seen with the Eye, a hand asked, a child
## fostered), the bands' camps (raids come from them, the warband rides out
## to clear one), gentle fights, and saving it all.


func _at_day(seed_text: String, day: int) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.minutes += float(day) * Calendar.MINUTES_PER_DAY
	return st


func _days(st: WorldState, n: int, also_realm: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in n:
		st.minutes += Calendar.MINUTES_PER_DAY
		events.append_array(Military.daily_update(st))
		if also_realm:
			events.append_array(Realm.daily_update(st))
	return events


## At a seat (arrived) with the house holding yours in `regard`.
func _visiting(st: WorldState, house_id: int, regard: int) -> Dictionary:
	var h := st.realm.get_house(house_id)
	check(Realm.set_out(st, house_id)["ok"], "you ride out")
	st.minutes += float(int(h["days"])) * Calendar.MINUTES_PER_DAY
	Realm.arrive(st)
	h["standing"] = regard
	return h


func test_the_realm_on_a_map() -> void:
	var st := WorldGenerator.generate("realm-map")
	var conf := Realm.map_cfg()
	var days: Array = conf.get("seat_days", [2, 4])
	var seen_kinds := {}
	for h in st.realm.houses:
		check(h.has("pos") and h.has("known_for") and str(h["head"]).ends_with(str(h["name"])), "%s has a seat on the map, a lord or lady (%s) and a name for something" % [h["seat"], h["head"]])
		check(int(h["days"]) >= int(days[0]) and int(h["days"]) <= int(days[1]), "%s is %d days' ride" % [h["seat"], h["days"]])
		check(absf(Realm.ride_days(Realm.center(), Realm.pos_of(h)) - float(h["days"])) < 0.05, "and that far on the map")
		seen_kinds[h["known_for"]] = true
	check_eq(seen_kinds.size(), st.realm.houses.size(), "each house is known for something of its own")
	for a in st.realm.houses:
		for b in st.realm.houses:
			if a != b:
				check(Realm.pos_of(a).distance_to(Realm.pos_of(b)) > 60.0, "%s and %s aren't on top of each other" % [a["seat"], b["seat"]])
	var again := WorldGenerator.generate("realm-map")
	check_eq(again.realm.to_dict()["houses"], st.realm.to_dict()["houses"], "the same seed puts them in the same places")


func test_regard_fades_and_is_won() -> void:
	var st := _at_day("realm-regard", 3)
	var h := st.realm.houses[0]
	h["standing"] = 20
	var other := st.realm.houses[1]
	other["standing"] = -20
	while st.day() % Calendar.days_per_season() != 0:
		st.minutes += Calendar.MINUTES_PER_DAY
	Realm.daily_update(st)
	var drift := int(Realm.section("regard").get("drift", 2))
	check(int(h["standing"]) == 20 - drift and int(other["standing"]) == -20 + drift, "regard fades toward nothing each season (%d, %d)" % [h["standing"], other["standing"]])
	check_eq(Realm.change_regard(st, int(h["id"]), 500), 100 - (20 - drift), "regard is kept to -100..100")
	check_eq(int(h["standing"]), 100, "(at most 100)")
	h["standing"] = 0
	st.house.gold = 500
	var before := int(h["standing"])
	_visiting(st, int(h["id"]), 0)
	check(st.player().is_away() and st.player().away_at == "journey", "you're away on the journey")
	var g := Realm.give_gift(st, 75)
	check(g["ok"] and st.house.gold == 425 and int(h["standing"]) > before, "a gift warms them: %s" % g["text"])
	check(not Realm.give_gift(st, 25)["ok"], "once a visit")
	var t := Realm.speak(st)
	check(t["ok"] and int(t["delta"]) != 0, "a talk with %s moves them: %s" % [h["head"], t["text"]])
	check(not Realm.speak(st)["ok"], "(one talk a visit)")


func test_the_young_of_a_house() -> void:
	var st := _at_day("realm-young", 5)
	var h := st.realm.houses[1]
	check(st.realm.household(int(h["id"])).is_empty(), "you haven't met them before you visit")
	_visiting(st, int(h["id"]), 0)
	var young := st.realm.household(int(h["id"]))
	var conf: Dictionary = Realm.section("houses").get("household", {})
	check(young.size() >= int((conf["young"] as Array)[0]) and young.size() <= int((conf["young"] as Array)[1]), "%d of the house's young" % young.size())
	check(young.all(func(c: CharacterData) -> bool: return c.id <= -2000 and st.get_character(c.id) == null and c.last_name == str(h["name"])), "of their house, never villagers")
	var first := young[0]
	check(not first.appraised, "their gifts are hidden")
	Realm.look(st, first.id)
	check(first.appraised and Appraisal.format_attribute(first, first.best_attribute()) != "", "until you look with the Eye")
	var age := first.age
	var combat := first.get_current("combat")
	st.minutes += 3.0 * Calendar.days_per_year() * Calendar.MINUTES_PER_DAY
	var later := Realm.update_household(st, int(h["id"]))
	if later.has(first):
		check_eq(first.age, age + 3, "three years on, three years older")
		check(first.get_current("combat") >= combat, "and grown in their gifts")
	check(later.size() >= int((conf["young"] as Array)[0]), "a house always has young")
	st.minutes += 30.0 * Calendar.days_per_year() * Calendar.MINUTES_PER_DAY
	later = Realm.update_household(st, int(h["id"]))
	check(not later.has(first) and later.all(func(c: CharacterData) -> bool: return c.age <= int(conf.get("away_at", 25))), "grown, they marry away; children are born")
	var copy := RealmData.from_dict(st.realm.to_dict())
	check_eq(copy.household(int(h["id"])).size(), later.size(), "the young are saved")


## A village (from seeds "<prefix>-1", "-2"...) where `want` holds.
func _seed_where(prefix: String, want: Callable) -> WorldState:
	for i in range(1, 40):
		var st := _at_day("%s-%d" % [prefix, i], 5)
		if want.call(st):
			return st
	return null


func test_a_hand_asked_at_a_seat() -> void:
	var st := _seed_where("realm-hand", func(w: WorldState) -> bool: return Realm.hand_partners(w).has(w.player()) and Realm.can_visit(w, 1)["ok"])
	check(st != null, "a village with an unmarried heir")
	var me := st.player()
	var h := _visiting(st, int(st.realm.houses[0]["id"]), 0)
	var member := Realm._member(st, h, clampi(me.age + 1, 17, 40))
	member.gender = "male" if me.gender == "female" else "female"
	member.traits.clear()
	(st.realm.households[int(h["id"])] as Array).append(member)
	check(Realm.hand_partners(st).has(me), "you're free to marry")
	var no := Realm.ask_hand(st, member.id, me.id)
	check(not no["ok"] and str(no["text"]).contains("think well enough"), "a house that thinks little of yours won't: %s" % no["text"])
	h["standing"] = 60
	st.house.renown = 40
	var r := Realm.ask_hand(st, member.id, me.id)
	check(r["ok"] and r["accept"], "a friendly house gives a son or daughter: %s" % r["text"])
	check(not Realm.ask_hand(st, member.id, me.id)["ok"], "(you ask once a visit)")
	var gold := st.house.gold
	Realm.take_leave(st)
	var events: Array[Dictionary] = []
	Realm.come_home(st, events)
	var wed := st.characters.filter(func(c: CharacterData) -> bool: return c.first_name == member.first_name and c.id >= 0 and LifeSystem.spouse_of(st, c) == me)
	check(wed.size() == 1, "home again, the wedding: %s" % ", ".join(events.map(func(e: Dictionary) -> String: return str(e["text"]))))
	check(st.house.gold > gold, "with their house's dowry")
	check(not me.is_away() and st.realm.trip.is_empty(), "and you're home")
	check(events.any(func(e: Dictionary) -> bool: return e.has("visitor")), "(they come with a body)")
	check(not st.realm.household(int(h["id"])).has(member), "they've left their father's house")


func test_fostering() -> void:
	var st := _seed_where("realm-foster", func(w: WorldState) -> bool: return not Realm.foster_candidates(w).is_empty() and Realm.can_visit(w, 3)["ok"])
	check(st != null, "a village with a kin child to foster")
	var kin := Realm.foster_candidates(st)[0]
	var h := _visiting(st, int(st.realm.houses[2]["id"]), 0)
	check(Realm.foster_candidates(st).has(kin), "a kin child of %d may be fostered" % kin.age)
	check(not Realm.foster(st, kin.id)["ok"], "not by a house that thinks little of yours")
	h["standing"] = 30
	var regard := int(h["standing"])
	var f := Realm.foster(st, kin.id)
	check(f["ok"] and kin.fostered_at() == int(h["id"]), "fostered at %s: %s" % [h["seat"], f["text"]])
	check(int(h["standing"]) > regard, "the house is honoured")
	check(not CourtSystem.is_tutored(st, kin) and not Realm.foster_candidates(st).has(kin), "away, no tutor at home")
	var attr := Realm.known_for_attribute(h)
	kin.set_attribute(attr, 10, 80)
	Realm.take_leave(st)
	var events: Array[Dictionary] = []
	Realm.come_home(st, events)
	while st.day() % Calendar.days_per_season() != 0:
		st.minutes += Calendar.MINUTES_PER_DAY
	Realm.daily_update(st)
	check(kin.get_current(attr) > 10 and kin.is_away(), "a season there: %s grows (%d)" % [attr, kin.get_current(attr)])
	kin.age = int(Realm.section("fostering").get("return_age", 16))
	st.minutes += Calendar.MINUTES_PER_DAY
	var back := Realm.daily_update(st)
	check(not kin.is_away() and back.any(func(e: Dictionary) -> bool: return (e.get("back", []) as Array).has(kin.id)), "grown, %s comes home: %s" % [kin.first_name, back[0]["text"] if not back.is_empty() else ""])


func test_bands_live_in_camps() -> void:
	var st := WorldGenerator.generate("realm-camps")
	var c := Military.section("camps")
	var made := -1
	var raided := -1
	for d in 140:
		st.minutes += Calendar.MINUTES_PER_DAY
		for e: Dictionary in Military.daily_update(st):
			if e.has("camp_made") and made < 0:
				made = st.day()
				check(str(e["text"]).contains("camp"), "news of the camp: %s" % e["text"])
				check(not st.military.camps[0]["known"] and Military.known_camps(st).is_empty(), "but no one knows where")
			if e.has("raid_warning") and raided < 0:
				raided = st.day()
		if raided >= 0:
			break
	check(made >= int(c.get("first_day", 45)) - 1 and made <= int(c.get("first_day", 45)) + 1, "the first band makes camp (day %d)" % made)
	var camp := st.military.camps[0]
	check(Realm.ride_days(Realm.center(), Realm.pos_of(camp)) >= 0.9, "out on the map, %d days' ride" % int(camp["days"]))
	check(camp["known"], "its raid shows where it lies")
	check(raided >= made + int(c.get("first_raid_days", 15)) - int(Military.section("raids").get("warning_days", 2)), "its first raid comes after it's settled (day %d)" % raided)
	check(int(st.military.raid["camp"]) == int(camp["id"]) and str(st.military.raid["name"]) == str(camp["band"]), "the raid comes from the camp")
	check(int(st.military.raid["size"]) == int(camp["men"]) and st.military.raid["road"] == camp["road"], "the whole band, by the camp's road")
	# Beaten, the band loses its fallen; beaten badly, it scatters.
	camp["men"] = 3
	var s := Military.sides(st)
	for f: Dictionary in s["theirs"]:
		f["down"] = true
	var events: Array[Dictionary] = []
	Military.finish(st, "house", s["ours"], s["theirs"], events)
	check(st.military.camps.is_empty() and str(events[0]["text"]).contains("scattered"), "beaten, the band scatters: %s" % events[0]["text"])
	check(st.military.next_camp_day > st.day(), "another will come in time")


func test_riding_against_a_camp() -> void:
	var st := _at_day("realm-ride", 50)
	var made := Military.make_camp(st, Seeds.rng(1, "ride"))
	var camp: Dictionary = made["camp"]
	check(not Military.can_ride(st, int(camp["id"]))["ok"], "no riding against a camp no one has found")
	check(not Military.reveal_camp(st, camp, "Your woodcutters have found where").is_empty() and camp["known"], "found")
	var near := st.realm.houses[0]
	near["pos"] = [Realm.pos_of(camp).x + 20.0, Realm.pos_of(camp).y]
	var near_regard := int(near["standing"])
	var riders := Military.riders(st)
	check(not riders.is_empty(), "%d fit to ride" % riders.size())
	var odds := Military.camp_odds(st, int(camp["id"]))
	check(odds >= 0.0 and odds <= 1.0, "your captains reckon the odds (%.2f)" % odds)
	var r := Military.ride_out(st, int(camp["id"]))
	check(r["ok"] and (r["away"] as Array).size() == riders.size(), "they ride out: %s" % r["text"])
	check(Military.warband(st).is_empty() or Military.warband(st).all(func(c: CharacterData) -> bool: return not riders.has(c)), "the village is barer while they're away")
	check(not Military.ride_out(st, int(camp["id"]))["ok"], "(one ride at a time)")
	var events := _days(st, int(camp["days"]), false)
	var report: Dictionary = {}
	for e in events:
		if e.has("battle"):
			report = e["battle"]
	check(not report.is_empty() and report.get("camp", false), "they fight on arrival: %s" % ("won" if report.get("won", false) else "lost"))
	if report.get("won", false):
		check(st.military.get_camp(int(camp["id"])).is_empty(), "the camp is gone")
		check(int(near["standing"]) > near_regard, "and the house nearby is grateful")
	else:
		check(not st.military.get_camp(int(camp["id"])).is_empty(), "the band holds its camp")
	check(riders.all(func(c: CharacterData) -> bool: return st.get_character(c.id) == null or c.is_away()), "they're still on the road home")
	var back := _days(st, int(camp["days"]), false)
	check(back.any(func(e: Dictionary) -> bool: return e.has("back")) and st.military.expedition.is_empty(), "and home again")
	check(riders.all(func(c: CharacterData) -> bool: return not c.is_away()), "everyone who lived is back")


func test_gentle_fights() -> void:
	var st := WorldGenerator.generate("realm-gentle")
	check(absf(Military.death_chance(st) - float(Military.section("combat")["death_chance"])) < 0.001, "real risk by default")
	st.military.gentle = true
	check(Military.death_chance(st) < 0.2, "gentle fights: far fewer of the fallen die")
	check(MilitaryData.from_dict(st.military.to_dict()).gentle, "(saved with the game)")


func test_the_realm_is_saved() -> void:
	var st := _at_day("realm-save", 50)
	Military.make_camp(st, Seeds.rng(2, "save"))
	var h := _visiting(st, int(st.realm.houses[0]["id"]), 25)
	var copy := WorldState.from_dict(st.to_dict())
	check_eq(copy.realm.to_dict(), st.realm.to_dict(), "the map, regard, the young met and the journey are saved")
	check_eq(copy.military.camps, st.military.camps, "the camps too")
	check(copy.player().away_at == "journey", "and that you're away")
	var old := st.to_dict()
	old["save_version"] = 16
	var houses: Array = (old["realm"] as Dictionary)["houses"]
	for hd: Dictionary in houses:
		for k: String in ["pos", "days", "known_for", "head", "head_gender", "visited"]:
			hd.erase(k)
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.realm.houses.all(func(x: Dictionary) -> bool: return x.has("pos") and x.has("head")), "an older save's houses go on the map")
	check_eq(migrated.realm.houses[0]["pos"], st.realm.houses[0]["pos"], "where the seed puts them")
	check(int(h["visited"]) == st.day(), "(the day of your visit is kept)")


func test_a_journey_in_the_world() -> void:
	Game.state = _at_day("realm-world", 20)
	var st := Game.state
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var me := world.player_npc()
	var h := st.realm.houses[0]
	check(Realm.set_out(st, int(h["id"]))["ok"], "you ride for %s" % h["seat"])
	world.apply_life_events([{"text": "", "away": [st.player_id]}])
	check(not me.visible and world.mode == "overview", "you're gone from the village")
	check(not Game.save_game("quicksave"), "no saving while you're away")
	var out: Dictionary = await world.pass_time(int(h["days"]), true)
	check(int(out.get("days", 0)) == int(h["days"]), "the days on the road pass (%d)" % int(out.get("days", 0)))
	Realm.arrive(st)
	var home: Dictionary = await world.pass_time(Realm.take_leave(st), true)
	var events: Array[Dictionary] = []
	Realm.come_home(st, events)
	world.apply_life_events(events)
	check(me.visible and not st.player().is_away() and world.mode == "walk", "home again, on foot (%d days back)" % int(home.get("days", 0)))
	world.queue_free()
	await frames(2)


func test_the_realm_panel_and_a_visit() -> void:
	GameSettings.memory_only = true
	Game.state = _at_day("realm-ui", 20)
	var st := Game.state
	var made := Military.make_camp(st, Seeds.rng(3, "ui"))
	Military.reveal_camp(st, made["camp"], "Found:")
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var ui := world.ui
	ui.toggle_realm()
	await frames(2)
	check(ui.is_realm_open(), "the realm map opens (J)")
	var places := ui._realm._map.places()
	check(places.size() == 1 + st.realm.houses.size() + st.military.camps.size(), "the village, %d seats and %d camp on it" % [st.realm.houses.size(), st.military.camps.size()])
	for p: Dictionary in places:
		ui._realm._map.select(str(p["kind"]), int(p["id"]))
		await frames(1)
		check(ui._realm._body.get_child_count() > 1, "%s %d has its details" % [p["kind"], p["id"]])
	var h := st.realm.houses[0]
	ui.journey(int(h["id"]))
	for i in 200:
		await frames(1)
		if ui.is_visit_open():
			break
	check(ui.is_visit_open() and not ui.is_realm_open(), "after the road, you're at %s" % h["seat"])
	check(ui.is_menu_open(), "(the village waits while you're there)")
	check(ui._visit._title.text == str(h["seat"]) and st.realm.household(int(h["id"])).size() > 0, "welcomed, among the house's young")
	ui._visit.visible = false
	ui._visit.closed.emit()
	for i in 200:
		await frames(1)
		if not world.passing and st.realm.trip.is_empty():
			break
	check(st.realm.trip.is_empty() and not st.player().is_away() and world.player_npc().visible, "home again")
	check(ui.is_years_open() and ui._years._title.text.begins_with("Home from"), "with what happened while you were away")
	world.queue_free()
	await frames(2)
	GameSettings.memory_only = false
