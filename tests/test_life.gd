extends TestCase
## Phase 4.1, the years turn (LifeSystem, data/life.json): birthdays, growing
## up and growing old, gentle deaths and the lord's succession, courtship,
## marriage and children who inherit their parents' gifts, the record of the
## departed, and the live world following along.


## Runs `body` with data/life.json changed by `patch` ({section: {key: v}}),
## then puts it back.
func _with_life(patch: Dictionary, body: Callable) -> void:
	var life := GameData.load_file("life")
	var saved := life.duplicate(true)
	for s: String in patch:
		for k: String in patch[s]:
			(life[s] as Dictionary)[k] = patch[s][k]
	await body.call()
	for s: String in saved:
		life[s] = saved[s]


## Moves the clock to the start of a day that is `c`'s birthday.
func _to_birthday(st: WorldState, c: CharacterData) -> void:
	var year := Calendar.days_per_year()
	var day := st.day() + posmod(c.birthday - st.day_of_year(), year)
	if day <= st.day():
		day += year
	st.minutes = float(day * Calendar.MINUTES_PER_DAY + 8 * 60)


func _someone(st: WorldState, test: Callable) -> CharacterData:
	for c in st.characters:
		if not st.is_player(c) and test.call(c):
			return c
	return null


func test_the_calendar_and_birthdays() -> void:
	check_eq(Calendar.days_per_season(), 10, "seasons are ten days long")
	check_eq(Calendar.days_per_year(), 40, "a year is forty days")
	var a := WorldGenerator.generate("life-cal")
	var b := WorldGenerator.generate("life-cal")
	var spread := {}
	for i in a.characters.size():
		check_eq(a.characters[i].birthday, b.characters[i].birthday, "birthdays are the same for the same seed")
		check(a.characters[i].birthday >= 0 and a.characters[i].birthday < 40, "a birthday is a day of the year")
		spread[a.characters[i].birthday] = true
	check(spread.size() > 20, "birthdays fall all through the year (%d different days)" % spread.size())
	var c := a.characters[5]
	check(LifeSystem.born_text(a, c).ends_with(str(LifeSystem.birth_year(a, c))), "the card says when they were born: %s" % LifeSystem.born_text(a, c))


func test_birthdays_grow_people_up() -> void:
	await _with_life({"death": {"min_age": 999}, "courtship": {"start_yearly": 0.0}, "births": {"yearly": 0.0}}, func() -> void:
		var st := WorldGenerator.generate("life-grow")
		var kid := _someone(st, func(c: CharacterData) -> bool: return c.age >= 6 and c.age <= 12 and c.occupation_id == "child" and not c.retainer)
		check(kid != null, "found a child")
		if kid == null:
			return
		kid.age = 12
		var height := float(kid.appearance["height"])
		var before := {}
		for attr: String in GameData.attribute_ids():
			before[attr] = kid.get_current(attr)
		_to_birthday(st, kid)
		var others := {}
		for c in st.characters:
			others[c.id] = c.age
		var events := LifeSystem.daily_update(st)
		check_eq(kid.age, 13, "a year older on their birthday")
		for c in st.characters:
			if c != kid and c.birthday != kid.birthday:
				check_eq(c.age, int(others[c.id]), "%s isn't a year older today" % c.first_name)
		check(float(kid.appearance["height"]) > height, "and taller (%.3f -> %.3f)" % [height, float(kid.appearance["height"])])
		var bg := GameData.background(st.get_family(kid.family_id).background)
		check_eq(kid.occupation_id, str(bg.get("teen_job", "child")), "at 13 they start learning the family's work")
		for attr: String in GameData.attribute_ids():
			check(kid.get_current(attr) >= int(before[attr]) and kid.get_current(attr) <= kid.get_potential(attr), "%s grows, never past their potential" % attr)
		check(events.any(func(e: Dictionary) -> bool: return int(e.get("aged", -1)) == kid.id), "the world is told to redraw them")
		# Coming of age: a grown trade, with a workplace when it has one.
		var teen := _someone(st, func(c: CharacterData) -> bool: return c.age == 15 and c.occupation_id in ["apprentice", "farmhand"] and not c.retainer)
		if teen:
			_to_birthday(st, teen)
			LifeSystem.daily_update(st)
			check(teen.age == 16 and not teen.occupation_id in ["apprentice", "child"], "at 16 they take up a grown trade (%s)" % teen.occupation_id)
			check(float(teen.appearance["height"]) == float(teen.appearance["adult_height"]), "and have their full height")
		# Old age: commoners retire, and their trade passes on.
		var old := _someone(st, func(c: CharacterData) -> bool: return c.age >= 40 and LifeSystem.passes_on(c.occupation_id) and c.work_building_id >= 0 \
			and c.status_tier() <= 2 and c.social_status != "clergy" and not c.retainer and not CourtSystem.is_kin(st, c))
		check(old != null, "found someone in a trade")
		if old:
			var trade := old.occupation_id
			var hands := st.characters.filter(func(c: CharacterData) -> bool: return c.occupation_id == trade).size()
			old.age = int(LifeSystem.section("ages").get("retire", 65)) - 1
			_to_birthday(st, old)
			LifeSystem.daily_update(st)
			check(old.occupation_id == "elder" and old.work_building_id == -1, "at %d they retire" % old.age)
			check_eq(st.characters.filter(func(c: CharacterData) -> bool: return c.occupation_id == trade).size(), hands, "and someone takes up their trade (%s)" % trade)
	)


func test_deaths_are_gentle() -> void:
	await _with_life({"death": {"yearly": [[18, 0.95], [100, 0.95]]}, "courtship": {"start_yearly": 0.0}, "births": {"yearly": 0.0}}, func() -> void:
		var st := WorldGenerator.generate("life-death")
		var kids := st.characters.filter(func(c: CharacterData) -> bool: return c.age < 17).map(func(c: CharacterData) -> int: return c.id)
		var player := st.player()
		var start := st.characters.size()
		for d in 40:
			st.minutes += Calendar.MINUTES_PER_DAY
			LifeSystem.daily_update(st)
		check(st.departed.size() > start / 3, "in a deadly year many die (%d)" % st.departed.size())
		for gone in st.departed:
			check(gone.age >= 18, "%s was grown (%d): no child dies" % [gone.full_name(), gone.age])
			check(st.get_character(gone.id) == null, "the departed aren't among the living")
			check(gone.departed_how == "died" and not gone.departed_cause.is_empty(), "and what took them is written down")
		check(st.get_character(player.id) != null, "the heir is spared until succession comes (Phase 4.3)")
		check(kids.all(func(id: int) -> bool: return st.get_character(id) != null), "every child is still here")
		# Nothing points at the dead as if alive.
		for f in st.families:
			for id in f.member_ids:
				check(st.get_character(id) != null, "%s family lists only the living" % f.name)
			check(f.member_ids.is_empty() or st.get_character(f.head_id) != null, "%s family has a living head" % f.name)
		for office: String in st.house.offices:
			check(st.get_character(int(st.house.offices[office])) != null, "the %s is alive" % office)
		for s in st.territory.sites:
			for id in s.builders:
				check(st.get_character(id) != null, "builders are alive")
		for c in st.characters:
			for r in c.relationships_of_type(["spouse", "lover"]):
				check(st.get_character(int(r["target"])) != null, "%s's spouse or sweetheart is alive" % c.first_name)
	)


func test_mourning_and_the_record() -> void:
	var st := WorldGenerator.generate("life-mourn")
	var husband := _someone(st, func(c: CharacterData) -> bool: return c.age >= 30 and LifeSystem.spouse_of(st, c) != null and not CourtSystem.is_kin(st, c))
	var wife := LifeSystem.spouse_of(st, husband)
	var events: Array[Dictionary] = []
	LifeSystem.die(st, husband, "a fever", events)
	check(st.get_departed(husband.id) == husband and st.get_person(husband.id) == husband, "the dead are kept on record")
	check_eq(str(wife.get_relationship(husband.id).get("type", "")), "late_spouse", "the widow's husband is her late husband")
	check(LifeSystem.spouse_of(st, wife) == null, "and she is free to marry again, in time")
	check(not LifeSystem.can_court(st, wife), "but not while newly widowed")
	var grief := MoodSystem.mourning(wife, st)
	check(not grief.is_empty() and float(grief["value"]) < 0.0, "she mourns him: %s" % grief)
	check(Barks.worries_of(st, wife).has("mourning"), "and says so as you pass")
	st.minutes += float(int(LifeSystem.section("mourning").get("days", 40)) + 1) * Calendar.MINUTES_PER_DAY
	check(MoodSystem.mourning(wife, st).is_empty(), "grief passes")
	check(events.any(func(e: Dictionary) -> bool: return int(e.get("gone", -1)) == husband.id), "the world is told he is gone")
	# A retainer with an office and a promise owed dies: the post falls vacant
	# and the promise is void.
	var steward := _someone(st, func(c: CharacterData) -> bool: return c.age >= 25 and not CourtSystem.is_kin(st, c) and Recruitment.eligible(st, c)["ok"])
	Recruitment.accept(st, steward, {"wage": 3, "position": "office", "office": "steward"})
	st.house.promises.append({"character": steward.id, "kind": "home", "due": st.day() + 5, "made": st.day()})
	check(st.house.holder_of("steward") == steward.id, "a steward is appointed")
	var news: Array[Dictionary] = []
	LifeSystem.die(st, steward, "a fever", news)
	check(st.house.holder_of("steward") != steward.id, "their office falls vacant")
	check(not st.house.promises.any(func(p: Dictionary) -> bool: return int(p["character"]) == steward.id), "and what was promised them lapses")
	check(str(news[0]["text"]).contains("your Steward"), "the house hears of it: %s" % news[0]["text"])
	check(st.house.chronicle.any(func(e: Dictionary) -> bool: return str(e["kind"]) == "death"), "and the chronicle records it")


func test_the_lord_dies_and_the_heir_inherits() -> void:
	var st := WorldGenerator.generate("life-lord")
	var fam := st.ruling_family()
	var lord := st.get_character(fam.head_id)
	var heir := st.player()
	check(lord != heir, "the heir's parent rules at first")
	check(CourtSystem.role_name(st, heir).begins_with("Heir of"), "the heir is the heir")
	var lady := LifeSystem.spouse_of(st, lord)
	var events: Array[Dictionary] = []
	LifeSystem.die(st, lord, "old age", events)
	check_eq(fam.head_id, heir.id, "the heir heads the house")
	check_eq(heir.occupation_id, "lord", "and holds the lordship")
	var title := CourtSystem.role_name(st, heir)
	check_eq(title, "%s of %s" % ["Lady" if heir.gender == "female" else "Lord", st.village_name], "and the title")
	if lady:
		check_eq(lady.occupation_id, "dowager", "the widow becomes the dowager")
	var news := str(events.filter(func(e: Dictionary) -> bool: return e.has("gone"))[0]["text"])
	check(news.contains("You are now %s" % title), "the news says so: %s" % news)
	check(st.house.chronicle.any(func(e: Dictionary) -> bool: return str(e["text"]) == news), "and the chronicle records it")
	check(events.any(func(e: Dictionary) -> bool: return int(e.get("job", -1)) == heir.id), "the heir's clothes change")


func test_courtship_and_marriage() -> void:
	var st := WorldGenerator.generate("life-wed")
	for c in st.characters:
		check(not (LifeSystem.can_court(st, c) and (CourtSystem.is_kin(st, c) or c.retainer or st.is_player(c))), "the house's own don't court on their own (4.2)")
	var singles: Array[CharacterData] = []
	for c in st.characters:
		if LifeSystem.can_court(st, c) and LifeSystem.lover_of(st, c) == null:
			singles.append(c)
	var a: CharacterData = null
	var b: CharacterData = null
	for x in singles:
		for y in singles:
			if x.gender != y.gender and absi(x.age - y.age) <= 10 and x.family_id != y.family_id and not LifeSystem._related(x, y):
				a = x
				b = y
				break
		if a:
			break
	check(a != null, "found two singles who might wed")
	if a == null:
		return
	# Give them an empty home to move into.
	var empty := GrowthSystem.empty_homes(st)
	if empty.is_empty():
		var vacate := GrowthSystem.homes(st)[0]
		for c in st.residents_of(vacate.id):
			c.home_building_id = -1
		empty = GrowthSystem.empty_homes(st)
	var events: Array[Dictionary] = []
	LifeSystem.marry(st, a, b, events)
	check(LifeSystem.spouse_of(st, a) == b and LifeSystem.spouse_of(st, b) == a, "they are husband and wife")
	check_eq(a.family_id, b.family_id, "one household")
	check_eq(a.home_building_id, b.home_building_id, "one home")
	check(a.history.any(func(h: Dictionary) -> bool: return str(h["text"]).begins_with("Married")), "the day is in their story")
	var moved: Array = events[0].get("moved", [])
	check(moved.has(a.id) or moved.has(b.id), "someone moved house, and the world is told")
	# Over a year, villagers court and wed on their own.
	await _with_life({"courtship": {"start_yearly": 3.0, "marry_yearly": 6.0, "marry_after_days": 5}, "death": {"min_age": 999}}, func() -> void:
		var st2 := WorldGenerator.generate("life-wed2")
		var married := func() -> int:
			return st2.characters.filter(func(c: CharacterData) -> bool: return LifeSystem.spouse_of(st2, c) != null).size()
		var before: int = married.call()
		for d in 40:
			st2.minutes += Calendar.MINUTES_PER_DAY
			LifeSystem.daily_update(st2)
		check(married.call() > before, "weddings happen (%d -> %d married)" % [before, married.call()])
	)


func test_children_inherit_gifts() -> void:
	var st := WorldGenerator.generate("life-born")
	var mother := _someone(st, func(c: CharacterData) -> bool: return c.gender == "female" and c.age >= 20 and c.age <= 38 and LifeSystem.spouse_of(st, c) != null and not CourtSystem.is_kin(st, c))
	check(mother != null, "found a married mother-to-be")
	if mother == null:
		return
	var father := LifeSystem.spouse_of(st, mother)
	var siblings := st.living_ties(mother, ["child"]).size()
	var baby := CharacterGenerator.newborn(st, mother, father, "test_birth")
	check_eq(baby.age, 0, "a newborn")
	check(LifeSystem.is_unseen(baby), "who stays at home, unseen, for now")
	check_eq(baby.family_id, mother.family_id, "in their parents' family")
	check_eq(baby.home_building_id, mother.home_building_id, "and home")
	check_eq(baby.birthday, st.day_of_year(), "born today")
	check_eq(str(baby.get_relationship(mother.id).get("type", "")), "parent", "their mother")
	check_eq(str(baby.get_relationship(father.id).get("type", "")), "parent", "and father")
	check_eq(baby.relationships_of_type(["sibling"]).size(), siblings, "and their brothers and sisters")
	check(baby.history[0]["text"].begins_with("Born in %s" % st.village_name), "born here: %s" % baby.history[0]["text"])
	check(st.last_character_id() == baby.id and st.get_character(baby.id) == baby, "a new id, among the living")
	# Gifts follow the parents' often, never always.
	# The share of their children with an A-rank gift or better (80+).
	var gifted := func(p: int) -> float:
		mother.set_attribute("combat", 0, p)
		father.set_attribute("combat", 0, p)
		var high := 0
		var n := 160
		for i in n:
			var kid := CharacterGenerator.newborn(st, mother, father, "test_gift_%d_%d" % [p, i])
			high += int(kid.get_potential("combat") >= 80)
			LifeSystem.depart(st, kid, "left", "test", [] as Array[Dictionary])
		return float(high) / n
	var strong: float = gifted.call(150)
	var weak: float = gifted.call(15)
	check(strong > weak * 2.5 and strong > 0.15, "children of two great fighters are often gifted fighters (%d%% vs %d%%)" % [roundi(strong * 100), roundi(weak * 100)])
	check(strong < 0.6, "but never surely (%d%%)" % roundi(strong * 100))
	# Who may have a child.
	check(LifeSystem.birth_chance(st, father) == 0.0, "a father doesn't give birth")
	mother.last_birth_day = st.day()
	check(LifeSystem.birth_chance(st, mother) == 0.0, "nor a mother who just did")
	mother.last_birth_day = -1
	var unwed := _someone(st, func(c: CharacterData) -> bool: return c.gender == "female" and c.age >= 20 and c.age <= 40 and LifeSystem.spouse_of(st, c) == null)
	if unwed:
		check(LifeSystem.birth_chance(st, unwed) == 0.0, "children come to married couples")


func test_the_years_are_saved() -> void:
	var st := WorldGenerator.generate("life-save")
	var gone := _someone(st, func(c: CharacterData) -> bool: return c.age > 40 and not CourtSystem.is_kin(st, c))
	LifeSystem.die(st, gone, "old age", [] as Array[Dictionary])
	var mother := _someone(st, func(c: CharacterData) -> bool: return c.gender == "female" and LifeSystem.spouse_of(st, c) != null and c.age < 40)
	var baby := CharacterGenerator.newborn(st, mother, LifeSystem.spouse_of(st, mother), "save_birth")
	var data: Dictionary = JSON.parse_string(JSON.stringify(st.to_dict()))
	var back := WorldState.from_dict(SaveManager.migrate(data))
	check(back.get_departed(gone.id) != null and back.get_departed(gone.id).departed_cause == "old age", "the departed are saved")
	check_eq(back.get_character(baby.id).birthday, baby.birthday, "birthdays are saved")
	for c in st.characters:
		check_eq(back.get_character(c.id).birthday, c.birthday, "%s's birthday" % c.first_name)
	# An older save gets birthdays, the same way every time.
	var old: Dictionary = JSON.parse_string(JSON.stringify(WorldGenerator.generate("life-old").to_dict()))
	old["save_version"] = 12
	old.erase("departed")
	for c: Dictionary in old["characters"]:
		c.erase("birthday")
	var again: Dictionary = old.duplicate(true)
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	var migrated2 := WorldState.from_dict(SaveManager.migrate(again))
	check(migrated.departed.is_empty(), "no one departed yet")
	var days := {}
	for i in migrated.characters.size():
		check_eq(migrated.characters[i].birthday, migrated2.characters[i].birthday, "an old save's birthdays are stable")
		days[migrated.characters[i].birthday] = true
	check(days.size() > 10, "and spread through the year")


func test_the_village_lives_on() -> void:
	var run := func(years: int) -> Dictionary:
		var st := WorldGenerator.generate("life-long")
		var out := {"born": 0, "died": 0, "children_died": 0, "min": 9999, "max": 0}
		for d in years * Calendar.days_per_year():
			st.minutes += Calendar.MINUTES_PER_DAY
			var rng := Seeds.rng(st.world_seed, "day_%d" % st.day())
			for c in st.characters:
				MoodSystem.daily_update(c, st, rng)
			TerritorySystem.daily_update(st)
			for e: Dictionary in LifeSystem.daily_update(st):
				if e.has("born"):
					out["born"] += 1
				if e.has("gone") and st.get_departed(int(e["gone"])).departed_how == "died":
					out["died"] += 1
					if st.get_departed(int(e["gone"])).age < 18:
						out["children_died"] += 1
			GrowthSystem.daily_update(st)
			out["min"] = mini(out["min"], st.characters.size())
			out["max"] = maxi(out["max"], st.characters.size())
		out["pop"] = st.characters.size()
		out["heir"] = st.player().age
		return out
	var a: Dictionary = run.call(12)
	check(a["born"] > 5 and a["died"] > 0, "in twelve years children are born and the old die (%d born, %d died)" % [a["born"], a["died"]])
	check_eq(int(a["children_died"]), 0, "no child dies")
	check(int(a["min"]) >= 40 and int(a["max"]) <= CharterSystem.max_population(WorldGenerator.generate("life-long")) + 10, "the village neither empties nor overflows (%d..%d)" % [a["min"], a["max"]])
	var b: Dictionary = run.call(12)
	check(a == b, "the same seed lives the same years")


func test_the_live_world_follows() -> void:
	Game.state = WorldGenerator.generate("life-live")
	var st := Game.state
	var mother := _someone(st, func(c: CharacterData) -> bool: return c.gender == "female" and LifeSystem.spouse_of(st, c) != null and c.age < 40)
	var baby := CharacterGenerator.newborn(st, mother, LifeSystem.spouse_of(st, mother), "live_birth")
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	check(world.npc_of(baby.id) == null, "a baby has no body in the world")
	check_eq(world.npcs.size(), st.characters.size() - 1, "everyone else does")
	baby.age = 3
	world._on_life_event({"text": "", "seen": baby.id})
	check(world.npc_of(baby.id) != null, "at three they're about the village")
	# Someone dies while the heir looks at them.
	var target: NPC = null
	for npc: NPC in world.npcs.values():
		if npc != world.player_npc() and npc.character.age >= 30 and not CourtSystem.is_kin(st, npc.character):
			target = npc
			break
	var dead := target.character
	world._set_focus(target)
	world.select_character(dead.id)
	var events: Array[Dictionary] = []
	LifeSystem.die(st, dead, "old age", events)
	for e in events:
		world._on_life_event(e)
	await frames(1)
	check(world.npc_of(dead.id) == null, "the departed leave the world")
	check(world.focus == null and world.selected == null, "and nothing is left pointing at them")
	world.queue_free()
	await frames(2)
