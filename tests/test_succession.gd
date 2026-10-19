extends TestCase
## Phase 4.3, succession (Succession, data/succession.json): you live and die
## on the same curve as everyone, your named heir (any child) goes on after
## you, a young ruler has a regent, the line passes to kin when you have no
## child and ends only when no one is left; your health warns you once; the
## house's rulers and family tree; letting the years pass; the live world
## handing your body on.


func _someone(st: WorldState, test: Callable) -> CharacterData:
	for c in st.characters:
		if not st.is_player(c) and test.call(c):
			return c
	return null


## Makes the player the lord (their parent dies), grown and married, with
## children of the given ages (eldest first). Returns [spouse, kids...].
func _lord_with_children(st: WorldState, ages: Array) -> Array[CharacterData]:
	var p := st.player()
	var lord := Succession.ruler(st)
	if lord and lord != p:
		LifeSystem.die(st, lord, "old age", [] as Array[Dictionary])
	p.age = maxi(p.age, 40)
	var spouse := LifeSystem.spouse_of(st, p)
	if spouse == null:
		spouse = _someone(st, func(c: CharacterData) -> bool: return not CourtSystem.is_kin(st, c) and c.gender != p.gender and c.age >= 25 and LifeSystem.spouse_of(st, c) == null and not c.retainer)
		MatchSystem.wed(st, p, spouse)
	var out: Array[CharacterData] = [spouse]
	var mother := p if p.gender == "female" else spouse
	var father := spouse if mother == p else p
	for i in ages.size():
		var kid := CharacterGenerator.newborn(st, mother, father, "test_kid_%d" % i)
		kid.age = int(ages[i])
		out.append(kid)
	return out


func test_you_live_and_die_like_everyone() -> void:
	check(not bool(LifeSystem.section("death").get("spare_player", true)), "the player isn't spared any more")
	var st := WorldGenerator.generate("succ-curve")
	var p := st.player()
	p.age = 100
	var died := false
	for d in 400:
		st.minutes += Calendar.MINUTES_PER_DAY
		for e: Dictionary in LifeSystem.daily_update(st):
			if e.has("succession"):
				died = true
		if died:
			break
	check(died, "a hundred-year-old player dies in time, like anyone")
	check(st.get_departed(p.id) != null and st.player() != null and st.player() != p, "and someone goes on after them")


func test_your_heir_goes_on_after_you() -> void:
	var st := WorldGenerator.generate("succ-heir")
	var family := _lord_with_children(st, [24, 19])
	var p := st.player()
	var elder := family[1]
	var younger := family[2]
	check_eq(Succession.heir(st), elder, "your eldest is your heir by default")
	check(not Succession.is_named(st, elder), "(not named, just the eldest)")
	check_eq(CourtSystem.role_name(st, elder), "Your heir", "known as your heir")
	var before := elder.player_opinion
	var r := Succession.name_heir(st, younger)
	check(r["ok"] and Succession.heir(st) == younger, "you may name a younger child: %s" % r["text"])
	check(elder.player_opinion < before and str(r["text"]).contains(elder.first_name), "the elder, passed over, takes it ill")
	var hurt := elder.player_opinion
	Succession.name_heir(st, elder)
	Succession.name_heir(st, younger)
	check_eq(elder.player_opinion, hurt, "but only once")
	var stranger := _someone(st, func(c: CharacterData) -> bool: return not CourtSystem.is_kin(st, c))
	check(not Succession.name_heir(st, stranger)["ok"], "only your own children can be your heir")
	# You die: the heir is you now, lord of the village.
	var events: Array[Dictionary] = []
	LifeSystem.die(st, p, "old age", events)
	check_eq(st.player(), younger, "you go on as your heir")
	check_eq(Succession.ruler(st), younger, "who rules the house")
	check_eq(younger.occupation_id, "lord", "as its lord or lady")
	check(events.any(func(e: Dictionary) -> bool: return e.has("succession") and int(e["player"]) == younger.id and int(e["gone"]) == p.id and str(e["text"]).contains("You go on as")), "the world is told who you are now")
	check(st.get_departed(p.id) != null, "the old ruler is remembered")
	check_eq(younger.player_opinion, 100.0, "you know your own mind")
	check(younger.appraised, "and your own gifts")
	check_eq(st.house.rulers.size(), 3, "the house's rulers in turn: grandparent, parent, you")
	check(int(st.house.rulers[1]["to"]) >= 0 and int(st.house.rulers[2]["to"]) == -1, "the old reign closed, the new one open")
	check_eq(family[0].occupation_id, "dowager", "the widow is the dowager")
	check(not Succession.minority(st), "a grown heir needs no regent")
	# What people think of the new ruler: some of the old, some of their own tie.
	check(elder.player_opinion != hurt, "the passed-over sibling's view of the new ruler is their own")


func test_a_young_ruler_has_a_regent() -> void:
	var st := WorldGenerator.generate("succ-regent")
	var family := _lord_with_children(st, [12])
	var p := st.player()
	var spouse := family[0]
	var kid := family[1]
	var events: Array[Dictionary] = []
	LifeSystem.die(st, p, "a fever", events)
	check_eq(st.player(), kid, "a child of 12 goes on")
	check(Succession.minority(st), "too young to rule alone")
	check_eq(Succession.regent(st), spouse, "their surviving parent rules as regent")
	check_eq(CourtSystem.role_name(st, spouse), "Regent of %s" % st.village_name, "known as the regent")
	check(events.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).contains("rules as regent")), "and the news says so")
	# The regent's Administration moves the income; a disloyal one skims.
	spouse.set_attribute("administration", 90, maxi(spouse.get_potential("administration"), 90))
	var good := Succession.regent_income_factor(st)
	spouse.set_attribute("administration", 10, maxi(spouse.get_potential("administration"), 10))
	var poor := Succession.regent_income_factor(st)
	check(good > 0.0 and poor < 0.0, "a capable regent raises income, a poor one lowers it (%+.2f / %+.2f)" % [good, poor])
	spouse.loyalty = 80.0
	check_eq(Succession.regent_skim(st, 100), 0, "a loyal regent keeps their hands clean")
	spouse.loyalty = 20.0
	check(Succession.regent_skim(st, 100) > 0, "a disloyal one pockets some")
	var gold := st.house.gold
	var income := CourtSystem.daily_income(st)
	CourtSystem.daily_update(st, Seeds.rng(1, "succ-skim"))
	check(st.house.gold - gold <= income - Succession.regent_skim(st, income), "and the skim comes out of the day's gold")
	# You choose another regent: grown kin or a retainer, not just anyone.
	var r := _someone(st, func(c: CharacterData) -> bool: return c.age >= 22 and not CourtSystem.is_kin(st, c) and Recruitment.eligible(st, c)["ok"])
	check(not Succession.set_regent(st, r)["ok"], "a villager can't rule for you")
	Recruitment.accept(st, r, {"wage": 3, "position": "household"})
	check(Succession.set_regent(st, r)["ok"] and Succession.regent(st) == r, "a retainer can")
	check(not Succession.set_regent(st, kid)["ok"], "and you can't be your own regent")
	# The regent leaves: another steps in.
	LifeSystem.depart(st, r, "left", "test", [] as Array[Dictionary])
	var news := Succession.daily_update(st)
	check(Succession.regent(st) != null and Succession.regent(st) != r, "when a regent goes, another steps in")
	check(news.any(func(e: Dictionary) -> bool: return e.has("regent")), "and you hear of it")
	# Of age: the regency ends.
	kid.age = Succession.of_age()
	news = Succession.daily_update(st)
	check(not Succession.minority(st) and st.house.regent_id == -1, "at %d you rule in your own right" % Succession.of_age())
	check(news.any(func(e: Dictionary) -> bool: return e.has("regency_end")), "and you're told")


func test_without_a_child_the_line_passes_to_kin() -> void:
	var st := WorldGenerator.generate("succ-kin")
	var p := st.player()
	for k in Succession.children_of(st, p):
		LifeSystem.depart(st, k, "left", "test", [] as Array[Dictionary])
	var next := Succession.successor(st, p)
	check(next != null and CourtSystem.is_kin(st, next), "a childless player is followed by kin: %s" % (next.full_name() if next else "no one"))
	var siblings := p.relationships_of_type(["sibling"]).filter(func(r: Dictionary) -> bool: return st.get_character(int(r["target"])) != null)
	if not siblings.is_empty():
		check(next.get_relationship(p.id).get("type", "") == "sibling", "a brother or sister first")
	# Everyone of the house gone: the house ends.
	var fam := st.ruling_family()
	for id in fam.member_ids.duplicate():
		var k := st.get_character(id)
		if k and k != p:
			LifeSystem.depart(st, k, "left", "test", [] as Array[Dictionary])
	check(Succession.successor(st, p) == null, "no one left to follow")
	var events: Array[Dictionary] = []
	LifeSystem.die(st, p, "old age", events)
	check(st.house.ended and st.player() == null, "the house is ended")
	check(events.any(func(e: Dictionary) -> bool: return e.has("ended")), "and the world is told")
	var back := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	CourtSystem.initialize(back)
	check(back.house.ended and back.player() == null, "a saved ended house stays ended (no new house founded on load)")


func test_your_health_warns_you_once() -> void:
	var st := WorldGenerator.generate("succ-health")
	var p := st.player()
	p.age = 40
	check(not Succession.failing(p), "hale at 40")
	check(not Succession.daily_update(st).any(func(e: Dictionary) -> bool: return e.has("health")), "no warning")
	p.age = 63
	check(Succession.failing(p), "failing at 63")
	var first := Succession.daily_update(st)
	check(first.any(func(e: Dictionary) -> bool: return e.has("health")), "you're told your health is failing")
	check(not Succession.daily_update(st).any(func(e: Dictionary) -> bool: return e.has("health")), "once")


func test_the_family_tree() -> void:
	var st := WorldGenerator.generate("succ-tree")
	var family := _lord_with_children(st, [20])
	var p := st.player()
	LifeSystem.die(st, p, "old age", [] as Array[Dictionary])
	var rows := Succession.tree(st)
	check(rows.size() >= 3, "the tree has the generations (%d rows)" % rows.size())
	var ids := rows.map(func(r: Dictionary) -> int: return int(r["id"]))
	check(ids.has(p.id) and ids.has(family[1].id), "the old ruler and you are in it")
	var me: Dictionary = rows[ids.find(family[1].id)]
	var old: Dictionary = rows[ids.find(p.id)]
	check(me["player"] and me["living"] and int(me["depth"]) == int(old["depth"]) + 1, "you, a generation below")
	check(not old["living"] and int(old["died"]) >= int(old["born"]), "the dead with their years")
	check(not (old["ruled"] as Array).is_empty() and not (me["ruled"] as Array).is_empty(), "rulers marked with their reigns")
	check((old["spouses"] as Array).has(family[0].full_name()), "with husband or wife beside them")
	check(not ids.has(family[0].id), "(a spouse appears beside, not again on their own)")
	check(int(rows[0]["depth"]) == 0, "from the eldest forebear down")


func test_succession_is_saved() -> void:
	var st := WorldGenerator.generate("succ-save")
	var family := _lord_with_children(st, [10, 8])
	Succession.name_heir(st, family[2])
	LifeSystem.die(st, st.player(), "old age", [] as Array[Dictionary])
	st.house.warned_id = 3
	var back := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	for k: String in ["regent_id", "warned_id", "ended"]:
		check_eq(back.house.get(k), st.house.get(k), "%s is saved" % k)
	check_eq(back.house.rulers, st.house.rulers, "the rulers are saved")
	check_eq(back.player_id, st.player_id, "who you are now is saved")
	# An older save starts its list of rulers with today's head.
	var old: Dictionary = JSON.parse_string(JSON.stringify(WorldGenerator.generate("succ-save").to_dict()))
	old["save_version"] = 14
	(old["house"] as Dictionary).erase("rulers")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check_eq(migrated.house.rulers.size(), 1, "an older save gets its ruler")
	check_eq(int(migrated.house.rulers[0]["id"]), migrated.ruling_family().head_id, "today's head")


func test_letting_the_years_pass() -> void:
	Game.state = WorldGenerator.generate("succ-pass")
	var st := Game.state
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var start := st.day()
	# A quiet season: no suitor due.
	st.realm.next_suitor_day = start + 999
	var s: Dictionary = await world.ui.pass_time(Calendar.days_per_season())
	check(not s.is_empty(), "the years pass")
	if str(s["stop"]).is_empty():
		check_eq(st.day(), start + Calendar.days_per_season(), "a whole season")
	check(int(s["days"]) >= 1 and (s["lines"] as Array) is Array and (s["people"] as Array).size() == 2, "and you read what happened (%d days, stop '%s')" % [s["days"], s["stop"]])
	check(world.ui.is_years_open(), "in a summary")
	check(not world.passing, "then the world runs on")
	world.ui._years.closed.emit()
	world.ui._years_overlay.visible = false
	# A suitor due in three days stops a year early.
	var heir := st.player()
	var spouse := LifeSystem.spouse_of(st, heir)
	if spouse:
		heir.remove_relationship(spouse.id)
		spouse.remove_relationship(heir.id)
	heir.age = clampi(heir.age, 18, 30)
	st.realm.next_suitor_day = st.day() + 3
	var day0 := st.day()
	s = await world.ui.pass_time(Calendar.days_per_year())
	check_eq(str(s["stop"]), "visitor", "a suitor's arrival stops the year: %s" % s["stop_text"])
	check(st.day() < day0 + Calendar.days_per_year(), "early (%d days)" % (st.day() - day0))
	check(MatchSystem.visitor(st) != null and world.npc_of(MatchSystem.visitor(st).id) != null, "and they're there to meet")
	world.ui._years_overlay.visible = false
	world.queue_free()
	await frames(2)


func test_the_live_world_hands_you_on() -> void:
	Game.state = WorldGenerator.generate("succ-live")
	var st := Game.state
	var family := _lord_with_children(st, [9])
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var old := world.player_npc()
	check(old != null and world.heir_ctl != null and world.heir_ctl.npc == old, "you walk as yourself")
	var kid := family[1]
	var events: Array[Dictionary] = []
	LifeSystem.die(st, st.player(), "old age", events)
	world.apply_life_events(events)
	await frames(3)
	var now := world.player_npc()
	check(now != null and now.character == kid, "you walk as your heir now")
	check(world.heir_ctl != null and world.heir_ctl.npc == now and now.driven, "under your control")
	check(world.npc_of(family[0].id) != null, "your regent is about")
	check(not is_instance_valid(old) or old.is_queued_for_deletion(), "the old body is gone")
	world.set_speed(3)
	for i in 10:
		world._process(0.1)
	check(world.state.player() == kid, "and the world runs on without a hitch")
	world.ui.toggle_court()
	world.ui._court.refresh()
	var texts := world.ui._court._body.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	texts.append_array(world.ui._court._body.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text))
	check(texts.any(func(t: String) -> bool: return t.begins_with("Regent: ")), "the Court panel shows your regent")
	check(texts.any(func(t: String) -> bool: return t == "Let a year pass"), "and lets the years pass")
	world.ui.toggle_tree()
	check(world.ui.is_tree_open() and world.ui._tree._body.get_child_count() > 3, "the family tree opens")
	world.queue_free()
	await frames(2)
