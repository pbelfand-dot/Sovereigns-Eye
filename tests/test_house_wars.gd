extends TestCase
## Phase 5.3, the noble houses in your fights (Realm, Military,
## data/realm.json "rivals", "aid", "hosts"): each house has a rival, and
## what warms one cools the other; houses that hold yours warmly send
## men-at-arms against a raid, friendly ones if you ask; a house that holds
## yours in contempt demands gold, or its host comes against you.


## A village a few weeks on, every house at `regard` and two days' ride away.
func _realm(seed_text: String, regard: int = 0) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.minutes += 70.0 * Calendar.MINUTES_PER_DAY
	for h in st.realm.houses:
		h["standing"] = regard
		h["days"] = 2
	return st


func test_rivals() -> void:
	var st := _realm("wars-rivals")
	var houses := st.realm.houses
	check(houses.size() >= 2, "(the realm has %d houses)" % houses.size())
	for h in houses:
		var rival := Realm.rival_of(st, int(h["id"]))
		check(not rival.is_empty() and rival != h, "%s is at odds with %s" % [h["name"], rival.get("name", "no one")])
	var paired := houses.filter(func(h: Dictionary) -> bool: return int(Realm.rival_of(st, int(Realm.rival_of(st, int(h["id"]))["id"]))["id"]) == int(h["id"]))
	check(paired.size() >= houses.size() - 1, "rivals in pairs (the odd one out aside)")
	check_eq(WorldGenerator.generate("wars-rivals").realm.to_dict()["houses"].map(func(h: Dictionary) -> int: return int(h["rival"])),
		houses.map(func(h: Dictionary) -> int: return int(h["rival"])), "the same rivals for the same seed")
	var a := houses[0]
	var b := Realm.rival_of(st, int(a["id"]))
	check_eq(Realm.change_regard(st, int(a["id"]), 20), 20, "you win 20 with %s" % a["name"])
	check_eq(int(b["standing"]), -10, "and %s thinks the less of you for it" % b["name"])
	Realm.change_regard(st, int(a["id"]), -6)
	check_eq(int(b["standing"]), -10, "(falling out with a house doesn't warm its rival)")
	Realm.change_regard(st, int(a["id"]), 6, false)
	check_eq(int(b["standing"]), -10, "(nor does goodwill to all: a castle raised, a camp cleared)")
	var copy := WorldState.from_dict(st.to_dict())
	check_eq(int(copy.realm.get_house(int(a["id"]))["rival"]), int(b["id"]), "rivals are saved")
	var old := st.to_dict()
	old["save_version"] = 17
	for h: Dictionary in old["realm"]["houses"]:
		h.erase("rival")
		h.erase("truce")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.realm.houses.all(func(h: Dictionary) -> bool: return int(h["rival"]) >= 0 and int(h["truce"]) == -1), "an older save's houses get their rivals")


func test_men_sent_in_aid() -> void:
	var st := _realm("wars-aid")
	var warm := st.realm.houses[0]
	warm["standing"] = 50
	var far := st.realm.houses[1]
	far["standing"] = 60
	far["days"] = int(Realm.section("aid")["max_days"]) + 1
	var warning := Military.plan_raid(st, Seeds.rng(1, "aid"))
	var allies: Array = st.military.raid["allies"]
	check(allies.size() == 1 and int(allies[0]["house"]) == int(warm["id"]), "the house that holds you warmly sends men, not the one too far away")
	check(str(warning["text"]).contains(st.realm.house_title(int(warm["id"]))), "you hear of it with the warning: %s" % warning["text"])
	var men := Realm.men_from(warm)
	check(st.military.allies.size() == men and men >= 1 and men <= int(Realm.section("aid")["men_max"]), "%d men-at-arms" % men)
	var sides := Military.sides(st)
	var ally_f: Array = sides["ours"].filter(func(f: Dictionary) -> bool: return str(f["role"]) == "ally")
	check_eq(ally_f.size(), men, "who stand in your line")
	var ally := st.military.allies[0]
	check(ally.house_id == int(warm["id"]) and ally.id <= Military.ALLY_ID and ally.get_current("combat") >= 30, "men of %s (Combat %d)" % [warm["name"], ally.get_current("combat")])
	check(st.get_character(ally.id) == null, "(not villagers)")
	var ids := st.military.allies.map(func(c: CharacterData) -> String: return "%d:%d" % [c.id, c.get_current("combat")])
	Military.make_allies(st)
	check_eq(st.military.allies.map(func(c: CharacterData) -> String: return "%d:%d" % [c.id, c.get_current("combat")]), ids, "the same men for the same raid")
	var copy := WorldState.from_dict(st.to_dict())
	check_eq(copy.military.allies.size(), men, "they're saved with the raid")
	var events: Array[Dictionary] = []
	var report := Military.fight(st, events)
	var lines: Array = report.get("allies", [])
	check(lines.size() == 1 and int(lines[0]["men"]) == men, "the report says who stood with you: %s" % str(lines))
	check(st.military.allies.is_empty(), "and they go home after")


func test_asking_for_men() -> void:
	var st := _realm("wars-ask")
	var h := st.realm.houses[0]
	h["standing"] = 20
	var cold := st.realm.houses[1]
	cold["standing"] = 5
	check(not Realm.can_ask(st, int(h["id"]))["ok"], "no raid, nothing to ask for")
	Military.plan_raid(st, Seeds.rng(2, "ask"))
	check((st.military.raid["allies"] as Array).is_empty(), "a friendly house doesn't send men unasked")
	check(not Realm.can_ask(st, int(cold["id"]))["ok"], "a cool one won't: %s" % Realm.can_ask(st, int(cold["id"]))["reason"])
	check(Realm.can_ask(st, int(h["id"]))["ok"], "a friendly one will if you ask")
	var rival := Realm.rival_of(st, int(h["id"]))
	var rival_before := int(rival["standing"])
	var r := Realm.ask_aid(st, int(h["id"]))
	check(r["ok"] and st.military.allies.size() == Realm.men_from(h), "asked: %s" % r["text"])
	check_eq(int(h["standing"]), 20 - int(Realm.section("aid")["ask_cost"]), "it spends their regard")
	check_eq(int(rival["standing"]), rival_before, "(their rival doesn't care)")
	check(not Realm.can_ask(st, int(h["id"]))["ok"], "(once)")


## A house in contempt of yours, and its host planned.
func _hosted(seed_text: String) -> WorldState:
	var st := _realm(seed_text)
	st.house.gold = 600
	var h := st.realm.houses[0]
	h["standing"] = -60
	Military.plan_host(st, int(h["id"]), Seeds.rng(3, seed_text))
	return st


func test_a_house_comes_against_you() -> void:
	var st := _realm("wars-host")
	var h := st.realm.houses[0]
	h["standing"] = int(Realm.section("hosts")["hostile_at"]) - 10
	var came := {}
	for season in 40:
		st.minutes = float((st.day() / Calendar.days_per_season() + 1) * Calendar.days_per_season()) * Calendar.MINUTES_PER_DAY
		h["standing"] = -60
		came = Realm._hostility(st)
		if not came.is_empty():
			break
	check(not came.is_empty() and int(came.get("host", -1)) == int(h["id"]), "a house that holds yours in contempt comes against you in time")
	check(Realm._hostility(st).is_empty(), "(one at a time)")
	var raid := st.military.raid
	var k := Realm.section("hosts")
	check(int(raid["host"]) == int(h["id"]) and int(raid["tribute"]) >= int(k["demand_min"]), "it demands %d gold: %s" % [int(raid["tribute"]), came["text"]])
	check_eq(int(raid["day"]), st.day() + int(k["days_to_pay"]), "by a day it names")
	check(st.military.raiders.all(func(c: CharacterData) -> bool: return c.house_id == int(h["id"])), "its own men")
	var roles := {}
	for f: Dictionary in Military.sides(st)["theirs"]:
		roles[f["role"]] = int(roles.get(f["role"], 0)) + 1
	check(roles.has("host_knight") and roles.has("host"), "knights among them: %s" % str(roles))
	check(st.military.raiders.size() <= int(k["host_max"]), "(%d strong)" % st.military.raiders.size())
	var from: Array = raid["from"]
	check(st.layout.roads.any(func(road: Dictionary) -> bool: return (road["points"] as PackedVector3Array)[(road["points"] as PackedVector3Array).size() - 1].distance_to(Vector3(float(from[0]), float(from[1]), float(from[2]))) < 30.0), "by a road into the village")
	var calm := _realm("wars-calm")
	calm.realm.houses[0]["standing"] = -20
	var any := false
	for season in 40:
		calm.minutes = float((calm.day() / Calendar.days_per_season() + 1) * Calendar.days_per_season()) * Calendar.MINUTES_PER_DAY
		any = any or not Realm._hostility(calm).is_empty()
	check(not any, "a house that merely dislikes you leaves you be")


func test_paying_the_demand() -> void:
	var st := _hosted("wars-pay")
	var h := st.realm.houses[0]
	var demand := int(st.military.raid["tribute"])
	var r := Military.pay_off(st)
	check(r["ok"] and st.house.gold == 600 - demand, "you pay %d: %s" % [demand, r["text"]])
	check(st.military.raid.is_empty(), "their host goes home")
	check_eq(int(h["standing"]), -60 + int(Realm.section("hosts")["paid_regard"]), "they're mollified")
	check(int(h["truce"]) > st.day(), "and keep the peace awhile")
	h["standing"] = -60
	st.minutes = float((st.day() / Calendar.days_per_season() + 1) * Calendar.days_per_season()) * Calendar.MINUTES_PER_DAY
	check(Realm._hostility(st).is_empty(), "(no host while the truce holds)")


func test_beating_a_host() -> void:
	var st := _hosted("wars-beat")
	var h := st.realm.houses[0]
	var s := Military.sides(st)
	var knights := 0
	for f: Dictionary in s["theirs"]:
		f["down"] = true
		if str(f["role"]) == "host_knight":
			knights += 1
	var gold := st.house.gold
	var renown := st.house.renown
	var events: Array[Dictionary] = []
	var report := Military.finish(st, "house", s["ours"], s["theirs"], events)
	var k := Realm.section("hosts")
	check(report["won"] and report["host"] and st.house.gold == gold + knights * int(k["ransom_per_knight"]), "beaten, they ransom their %d knights: %s" % [knights, events[0]["text"]])
	check_eq(st.house.renown, renown + int(k["renown_win"]), "renown for it")
	check(int(h["standing"]) >= int(k["after_regard"]) and int(h["truce"]) > st.day(), "and they keep the peace")
	check(st.military.raid.is_empty(), "the host is gone")

	var lost := _hosted("wars-lose")
	var s2 := Military.sides(lost)
	for f: Dictionary in s2["ours"]:
		f["down"] = true
	var take := int(lost.military.raid["loot_gold"])
	var renown2 := lost.house.renown
	events.clear()
	Military.finish(lost, "raiders", s2["ours"], s2["theirs"], events)
	check(take > 0 and lost.house.gold == 600 - mini(take, 600), "winning, they take %d gold" % take)
	check_eq(lost.house.renown, maxi(0, renown2 + int(k["renown_loss"])), "and your house is thought less of")


func test_a_castle_against_a_host() -> void:
	var st := _realm("wars-castle")
	st.house.gold = 600
	st.castle.kind = "stone"
	st.castle.site = [80.0, 0.0, 0.0]
	Military.plan_host(st, int(st.realm.houses[0]["id"]), Seeds.rng(3, "c"))
	check_eq(int(st.military.raid["loot_gold"]), 0, "behind stone walls they can't reach the gold")
	check(int(st.military.raid["tribute"]) > 0, "(though they still demand it)")


func test_allies_in_the_village_fight() -> void:
	Game.state = _realm("wars-live")
	var st := Game.state
	st.realm.houses[0]["standing"] = 60
	Military.plan_raid(st, Seeds.rng(4, "live"))
	var men := st.military.allies.size()
	check(men > 0, "(%d men sent)" % men)
	st.military.raid["day"] = st.day()
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	st.minutes = float(st.day() * Calendar.MINUTES_PER_DAY + Military.strike_hour() * 60 + 1)
	world._process(0.016)
	var b := world.battle
	check(b != null, "the band attacks")
	var allies: Array = b.ours.filter(func(f: Dictionary) -> bool: return str(f["role"]) == "ally")
	check_eq(allies.size(), men, "the men-at-arms stand in your line")
	var bodies: Array = allies.map(func(f: Dictionary) -> NPC: return f["npc"])
	check(bodies.all(func(n: NPC) -> bool: return b._own_npcs.has(n) and not world.npcs.values().has(n) and n.fighting), "with bodies of their own, armed")
	var report: Dictionary = {}
	b.finished.connect(func(r: Dictionary, _e: Array) -> void: report.merge(r))
	b.routed = "raiders"
	b.finish()
	await frames(2)
	check((report.get("allies", []) as Array).size() == 1, "the report names them")
	check(bodies.all(func(n: Variant) -> bool: return not is_instance_valid(n)), "and they go home")
	world.queue_free()
	await frames(2)
