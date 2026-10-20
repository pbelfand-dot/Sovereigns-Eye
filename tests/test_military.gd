extends TestCase
## Phase 5.1, the military (Military, data/military.json): raids come with a
## warning, can be paid off or fought; the warband (retainers, knights, the
## watch, the levy if called); blows land by Combat, a side breaks when
## enough of it falls (its captain's Leadership holds it), and the fallen may
## die (real risk); what a fight leaves behind; saving it all.


## A village a few weeks on, with a band on its way.
func _raided(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.minutes += 70.0 * Calendar.MINUTES_PER_DAY
	Military.plan_raid(st, Seeds.rng(1, seed_text))
	return st


func test_raids_come_with_a_warning() -> void:
	var st := WorldGenerator.generate("mil-raid")
	var warned := -1
	var struck := -1
	for d in 200:
		st.minutes += Calendar.MINUTES_PER_DAY
		for e: Dictionary in Military.daily_update(st):
			if e.has("raid_warning") and warned < 0:
				warned = st.day()
				check(str(e["text"]).contains("strike in"), "the warning says when: %s" % e["text"])
			if e.has("raid") and struck < 0:
				struck = st.day()
		if struck >= 0:
			break
	check(warned >= int(Military.section("raids").get("first_day", 60)) - int(Military.section("raids").get("warning_days", 2)), "no raid in the first weeks (warned day %d)" % warned)
	check_eq(struck - warned, int(Military.section("raids").get("warning_days", 2)), "they strike when the warning said")
	var m := st.military
	check(m.raiders.size() == int(m.raid["size"]) and m.raiders.size() >= 2, "a band of %d" % m.raiders.size())
	check(m.raiders.all(func(r: CharacterData) -> bool: return r.id < 0 and st.get_character(r.id) == null), "raiders aren't villagers (no village system sees them)")
	check(m.raiders[0].get_current("combat") >= int((Military.section("raids").get("leader_combat") as Array)[0]), "led by a hard fighter")
	check(Military.due(st), "and they're due")
	var again := WorldGenerator.generate("mil-raid")
	again.minutes = st.minutes - 2.0 * Calendar.MINUTES_PER_DAY
	again.military.next_raid_day = m.next_raid_day
	Military.plan_raid(again, Seeds.rng(st.world_seed, "raids_%d" % again.day()))
	check(again.military.raiders.size() > 0, "(plans are made from the seed)")


func test_pay_them_off() -> void:
	var st := _raided("mil-pay")
	var m := st.military
	var cost := int(m.raid["tribute"])
	st.house.gold = cost - 1
	check(not Military.pay_off(st)["ok"], "you can't pay what you haven't got")
	st.house.gold = cost + 10
	var renown := st.house.renown
	var r := Military.pay_off(st)
	check(r["ok"] and st.house.gold == 10, "they take %d gold: %s" % [cost, r["text"]])
	check(m.raid.is_empty() and m.raiders.is_empty() and not Military.due(st), "and go")
	check(st.house.renown <= renown, "a house that pays is thought less of")
	check(m.next_raid_day > st.day(), "another band will come in time")


func test_the_warband() -> void:
	var st := _raided("mil-band")
	var watch: Array = Military.section("warband").get("watch", [])
	var band := Military.warband(st)
	check(not band.is_empty(), "the watch turns out (%d)" % band.size())
	check(band.all(func(c: CharacterData) -> bool: return c.retainer or c.is_knight() or watch.has(c.occupation_id)), "retainers, knights and the watch")
	check(not band.has(st.player()), "you fight only if you choose to")
	var r := st.characters.filter(func(c: CharacterData) -> bool: return c.age >= 20 and not CourtSystem.is_kin(st, c) and Recruitment.eligible(st, c)["ok"])[0] as CharacterData
	Recruitment.accept(st, r, {"wage": 3, "position": "household"})
	check(Military.warband(st).has(r), "a retainer answers the call")
	r.wounded_until = st.day() + 3
	check(not Military.warband(st).has(r), "but not while wounded")
	check(MoodSystem.happiness_factors(r, st).any(func(f: Dictionary) -> bool: return f["label"] == "Wounded"), "(and their wound weighs on them)")
	var levy := Military.levy(st)
	check(levy.size() == int(Military.section("warband").get("levy_max", 3)), "the levy: the strongest few villagers")
	check(not Military.warband(st).has(levy[0]), "only when it's called")
	var happy := levy[0].happiness
	check(Military.call_levy(st)["ok"], "you call the levy")
	check(Military.warband(st).has(levy[0]) and levy[0].happiness < happy, "they take up arms, unwillingly")
	check(Military.fighter(st, levy[0], "house")["combat"] < levy[0].get_current("combat") or levy[0].get_current("combat") <= 1, "with farm tools, not swords")


func test_blows_and_breaking() -> void:
	check(Military.hit_chance(70, 20) > Military.hit_chance(20, 20) and Military.hit_chance(20, 20) > Military.hit_chance(20, 70), "the better fighter lands more blows")
	var st := _raided("mil-math")
	var a := Military.fighter(st, st.military.raiders[1], "raiders")
	var knight := a.duplicate()
	knight["role"] = "knight"
	var levy := a.duplicate()
	levy["role"] = "levy"
	check(Military.damage(a, knight) < Military.damage(a, levy), "armor turns blows")
	var rng := Seeds.rng(1, "blows")
	var hp := float(levy["hp"])
	var landed := false
	for i in 20:
		landed = Military.strike(a, levy, rng)["hit"] or landed
	check(landed and float(levy["hp"]) < hp, "blows wear a fighter down")
	var steady: Array[Dictionary] = [a.duplicate(), a.duplicate()]
	steady[0]["leadership"] = 90
	var shaky: Array[Dictionary] = [a.duplicate(), a.duplicate()]
	shaky[0]["leadership"] = 5
	check(Military.breaking_point(steady) > Military.breaking_point(shaky), "a good captain holds a side together longer")


func test_a_fight_is_decided_by_the_fighters() -> void:
	var st := _raided("mil-resolve")
	var s := Military.sides(st)
	for f: Dictionary in s["ours"]:
		f["combat"] = 85
	for f: Dictionary in s["theirs"]:
		f["combat"] = 10
	check_eq(Military.resolve(s["ours"], s["theirs"], Seeds.rng(1, "r"))["winner"], "house", "skilled defenders beat rabble")
	var t := Military.sides(st)
	for f: Dictionary in t["ours"]:
		f["combat"] = 5
	for f: Dictionary in t["theirs"]:
		f["combat"] = 80
	check_eq(Military.resolve(t["ours"], t["theirs"], Seeds.rng(1, "r"))["winner"], "raiders", "and hard raiders beat a raw watch")
	var x := Military.sides(st)
	var y := Military.sides(st)
	check_eq(Military.resolve(x["ours"], x["theirs"], Seeds.rng(5, "same"))["winner"], Military.resolve(y["ours"], y["theirs"], Seeds.rng(5, "same"))["winner"], "the same fight goes the same way")
	var odds := Military.odds(st)
	check(odds >= 0.0 and odds <= 1.0 and odds == Military.odds(st), "your captains reckon the odds (%.2f, %s)" % [odds, Military.odds_word(odds)])
	Military.call_levy(st)
	check(Military.odds(st) >= odds, "the levy helps (%.2f -> %.2f)" % [odds, Military.odds(st)])


func test_what_a_fight_leaves_behind() -> void:
	var st := _raided("mil-after")
	var s := Military.sides(st)
	for f: Dictionary in s["theirs"]:
		f["down"] = true
	(s["ours"] as Array)[0]["down"] = true
	var hurt: int = (s["ours"] as Array)[0]["id"]
	var standing: int = (s["ours"] as Array)[1]["id"]
	var skill := st.get_character(standing).get_current("combat")
	var renown := st.house.renown
	var gold := st.house.gold
	var events: Array[Dictionary] = []
	var report := Military.finish(st, "house", s["ours"], s["theirs"], events)
	check(report["won"] and st.house.renown > renown and st.house.gold > gold, "a win brings renown and the raiders' purse")
	var fell: Dictionary = (report["ours"] as Array).filter(func(l: Dictionary) -> bool: return int(l["id"]) == hurt)[0]
	check(fell["died"] != fell["wounded"], "the fallen either die or lie wounded")
	if fell["died"]:
		check(st.get_departed(hurt) != null and events.any(func(e: Dictionary) -> bool: return int(e.get("gone", -1)) == hurt), "the dead are mourned")
	else:
		check(st.get_character(hurt).wounded_until > st.day(), "the wounded rest")
	check(st.get_character(standing).get_current("combat") >= skill, "the rest grow in skill (never past their potential)")
	check(st.military.raid.is_empty() and st.military.battles == 1 and st.military.won == 1, "the raid is over")
	check(events.any(func(e: Dictionary) -> bool: return e.has("battle")), "and you hear how it went")
	# A loss: the raiders take their loot and the village is shaken.
	var st2 := _raided("mil-loss")
	var loot := int(st2.military.raid["loot_gold"])
	var gold2 := st2.house.gold
	var someone := st2.characters[5]
	var happy := someone.happiness
	var s2 := Military.sides(st2)
	for f: Dictionary in s2["ours"]:
		f["down"] = true
	var r2 := Military.finish(st2, "raiders", s2["ours"], s2["theirs"], [] as Array[Dictionary])
	check(not r2["won"] and st2.house.gold == gold2 - loot, "they take their loot (%d gold)" % loot)
	check(someone.happiness < happy, "and the village is shaken")
	var dead := (r2["ours"] as Array).filter(func(l: Dictionary) -> bool: return l["died"]).size()
	check(dead > 0 or (r2["ours"] as Array).size() < 3, "real risk: some of the fallen die (%d of %d)" % [dead, (r2["ours"] as Array).size()])


func test_a_raid_left_unfought_is_fought() -> void:
	var st := _raided("mil-late")
	st.minutes += 3.0 * Calendar.MINUTES_PER_DAY
	var events := Military.daily_update(st)
	check(events.any(func(e: Dictionary) -> bool: return e.has("battle")), "a raid whose day has passed is fought out of sight")
	check(st.military.raid.is_empty(), "and over")


func test_the_military_is_saved() -> void:
	var st := _raided("mil-save")
	Military.call_levy(st)
	st.characters[3].wounded_until = st.day() + 4
	var back := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	for k: String in ["name", "day", "size", "tribute", "loot_gold", "levy", "road"]:
		check_eq(back.military.raid[k], st.military.raid[k], "the raid's %s is saved" % k)
	check_eq(back.military.raiders.size(), st.military.raiders.size(), "and the band")
	check_eq(back.military.raiders[0].get_current("combat"), st.military.raiders[0].get_current("combat"), "as they were")
	check_eq(back.characters[3].wounded_until, st.characters[3].wounded_until, "wounds are saved")
	var old: Dictionary = JSON.parse_string(JSON.stringify(WorldGenerator.generate("mil-save").to_dict()))
	old["save_version"] = 15
	old.erase("military")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.military != null and migrated.military.raid.is_empty(), "an older save starts at peace")


func test_a_raid_is_fought_in_the_village() -> void:
	Game.state = _raided("mil-live")
	var st := Game.state
	st.military.raid["day"] = st.day()
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	st.minutes = float(st.day() * Calendar.MINUTES_PER_DAY + Military.strike_hour() * 60 + 1)
	world._process(0.016)
	check(world.battle != null, "at the raid hour the band attacks")
	var b := world.battle
	check(b.theirs.size() == int(st.military.raid["size"]) and b.ours.size() > 0, "%d raiders against %d of yours" % [b.theirs.size(), b.ours.size()])
	check(b.ours.all(func(f: Dictionary) -> bool: return (f["npc"] as NPC).fighting and (f["npc"] as NPC).driven), "the warband is called away from its work")
	var villager: NPC = null
	for npc: NPC in world.npcs.values():
		if not npc.fighting and npc != world.player_npc() and npc.character.home_building_id >= 0:
			villager = npc
			break
	check(villager != null and str(villager.brain.errand.get("type", "")) == "shelter", "villagers run for shelter")
	var skip: Dictionary = await world.pass_time(10)
	check(skip.is_empty() and world.battle != null, "no letting the years pass mid-fight")
	var report: Dictionary = {}
	world.battle.finished.connect(func(r: Dictionary, _e: Array) -> void: report.merge(r))
	check(b.theirs.all(func(f: Dictionary) -> bool: return b._own_npcs.has(f["npc"]) and not world.npcs.values().has(f["npc"])), "the raiders have bodies (their own, not villagers')")
	var first: NPC = b.theirs[0]["npc"]
	check(first.get_node_or_null("HealthBar") != null and (b.ours[0]["npc"] as NPC).get_node_or_null("HealthBar") != null, "everyone in the fight has a bar over their head")
	check(not (first.model is HumanModel) or not (first.model as HumanModel)._weapons.is_empty(), "and a weapon in hand")
	check(not b.heir_strike(), "you can't strike a raider who isn't in reach")
	var me := world.player_npc()
	me.teleport(first.global_position + Vector3(1.0, 0, 0))
	check(b.heir_strike() and int(b.heir_f.get("swings", 0)) == 1 and b.heir_f["joined"], "walk up to one and you strike (and you're in the fight)")
	var blows := 0
	var seconds := 0.0
	for i in 6000:
		world._process(0.05)
		if world.battle:
			world.battle._process(0.05)
		seconds += 0.05
		if world.battle == null:
			break
		blows = b.ours.reduce(func(acc: int, f: Dictionary) -> int: return acc + int(f["hits"]), 0)
	check(world.battle == null and not report.is_empty(), "the fight ends (%s after %.0f s)" % ["won" if report.get("won", false) else "lost", seconds])
	check(blows > 0 or report.get("won", false) == false, "blows were struck")
	check(st.military.raid.is_empty() and st.military.battles == 1, "the raid is over")
	check(world.npcs.values().all(func(n: NPC) -> bool: return not n.fighting), "everyone goes back to their day")
	check(villager == null or not is_instance_valid(villager) or str(villager.brain.errand.get("type", "")) != "shelter", "and out of shelter")
	check(world.ui.is_report_open(), "you read how it went")
	world.queue_free()
	await frames(2)


func test_orders_in_a_fight() -> void:
	Game.state = _raided("mil-orders")
	var st := Game.state
	st.military.raid["day"] = st.day()
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	st.minutes = float(st.day() * Calendar.MINUTES_PER_DAY + Military.strike_hour() * 60 + 1)
	world._process(0.016)
	var b := world.battle
	check(b != null and b.mustering, "the line holds for the band to come up")
	check(b.order_charge() and not b.mustering, "Charge: it goes now")
	check(not b.order_charge(), "(once)")
	for i in 40:
		b._process(0.05)
	var fallen_then := Military.fallen(b.ours)
	check(b.order_fall_back() and b.routed == "house" and b.fell_back, "Fall back: the warband gives way")
	var report: Dictionary = {}
	b.finished.connect(func(r: Dictionary, _e: Array) -> void: report.merge(r))
	for i in 400:
		world._process(0.05)
		if world.battle:
			world.battle._process(0.05)
		if world.battle == null:
			break
	check(not report.is_empty() and not report.get("won", true), "the band has the village's loot")
	check_eq((report["ours"] as Array).filter(func(l: Dictionary) -> bool: return l["fell"]).size(), fallen_then, "and no more of yours fell")
	world.queue_free()
	await frames(2)
