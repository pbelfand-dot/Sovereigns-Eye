extends TestCase
## Phase 4.2, the house's matches (MatchSystem, data/matches.json): the noble
## houses around the village, suitors who visit and can be looked at with
## the Eye, the heir asking for a hand, matches for kin and retainers that
## both must agree to, and tutors for the house's children.


func _someone(st: WorldState, test: Callable) -> CharacterData:
	for c in st.characters:
		if not st.is_player(c) and test.call(c):
			return c
	return null


## A villager the heir could marry, freed of any sweetheart (the heir grown
## and unmarried).
func _match_for_heir(st: WorldState) -> CharacterData:
	var heir := _single_heir(st)
	var c := _someone(st, func(o: CharacterData) -> bool: return not CourtSystem.is_kin(st, o) and not o.retainer and MatchSystem.can_wed(st, heir, o)["ok"])
	if c:
		_heart_free(st, c)
	return c


## The heir, grown and unmarried (some seeds start with a married heir).
func _single_heir(st: WorldState) -> CharacterData:
	var heir := st.player()
	var spouse := LifeSystem.spouse_of(st, heir)
	if spouse:
		heir.remove_relationship(spouse.id)
		spouse.remove_relationship(heir.id)
	heir.age = clampi(heir.age, 18, 30)
	return heir


func _offer(st: WorldState, target: CharacterData) -> CharacterData:
	if st.is_player(target):
		_single_heir(st)
	target.age = maxi(target.age, 18)
	var events: Array[Dictionary] = []
	return MatchSystem.offer(st, target, Seeds.rng(st.world_seed, "test_offer_%d" % st.day()), events)


## Frees `c` of any sweetheart (so only the match is weighed).
func _heart_free(st: WorldState, c: CharacterData) -> void:
	var sweet := LifeSystem.lover_of(st, c)
	if sweet:
		c.remove_relationship(sweet.id)
		sweet.remove_relationship(c.id)


func test_the_houses_around_the_village() -> void:
	var a := WorldGenerator.generate("match-realm")
	var b := WorldGenerator.generate("match-realm")
	check_eq(a.realm.houses.size(), int(MatchSystem.section("houses").get("count", 4)), "four noble houses round about")
	var names := WorldGenerator.surnames(a)
	for i in a.realm.houses.size():
		var h: Dictionary = a.realm.houses[i]
		check(not names.has(h["name"]), "House %s isn't a village family" % h["name"])
		check_eq(h, b.realm.houses[i], "the same houses for the same seed")
		check(a.realm.house_title(int(h["id"])).begins_with("House %s of " % h["name"]), "named with their seat: %s" % a.realm.house_title(int(h["id"])))
	var back := WorldState.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	check_eq(back.realm.houses, a.realm.houses, "the houses are saved")
	# An older save gets its houses on load.
	var old: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	old["save_version"] = 13
	old.erase("realm")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check_eq(migrated.realm.houses, a.realm.houses, "an older save gets the houses this seed would have")


func test_a_proposal_is_weighed_not_rolled() -> void:
	var st := WorldGenerator.generate("match-propose")
	var heir := st.player()
	var c := _match_for_heir(st)
	check(c != null, "found someone the heir could marry")
	if c == null:
		return
	c.player_opinion = -60.0
	var r1 := MatchSystem.consider(st, c, heir)
	var r2 := MatchSystem.consider(st, c, heir)
	check(not r1["accept"] and r1["score"] == r2["score"], "someone who dislikes the heir says no, and would again")
	check((r1["reasons"] as Array).any(func(r: Dictionary) -> bool: return str(r["text"]) == "They don't care for you." and not r["good"]), "and says why")
	c.player_opinion = 90.0
	var lover := _someone(st, func(o: CharacterData) -> bool: return o.gender != c.gender and o != c and LifeSystem.spouse_of(st, o) == null and not CourtSystem.is_kin(st, o))
	c.add_relationship(lover.id, "lover", 80)
	var torn := MatchSystem.consider(st, c, heir)
	check((torn["reasons"] as Array).any(func(r: Dictionary) -> bool: return str(r["text"]).begins_with("Their heart is set on")), "a sweetheart holds them back")
	c.remove_relationship(lover.id)
	var r := MatchSystem.propose(st, c)
	check(r["ok"] and r["accept"], "someone fond of the heir says yes: %s" % r["text"])
	check(LifeSystem.spouse_of(st, heir) == c, "and they marry")
	var other := _someone(st, func(o: CharacterData) -> bool: return o != c and not CourtSystem.is_kin(st, o) and o.gender == c.gender and o.age >= 18)
	check(not MatchSystem.propose(st, other)["ok"], "the heir can't marry twice")


func test_the_heir_marries_into_the_house() -> void:
	var st := WorldGenerator.generate("match-wed")
	var heir := st.player()
	var c := _match_for_heir(st)
	var fam := st.ruling_family()
	var manor := CourtSystem._building_of_type(st, "manor")
	var renown := st.house.renown
	var villager := _someone(st, func(o: CharacterData) -> bool: return o != c and not CourtSystem.is_kin(st, o))
	var opinion := villager.player_opinion
	var events: Array[Dictionary] = []
	MatchSystem.wed(st, heir, c, events)
	check_eq(c.family_id, fam.id, "the spouse joins the house")
	check_eq(c.last_name, fam.name, "and takes its name")
	check_eq(c.home_building_id, manor, "and lives at the manor")
	check_eq(c.occupation_id, "noble_scion", "a scion while the old lord lives")
	check(CourtSystem.is_kin(st, c), "family now")
	check_eq(st.house.renown, maxi(renown + int(MatchSystem.section("wedding").get("renown_commoner", -2)), 0), "marrying a commoner costs a little renown")
	check(villager.player_opinion > opinion, "the village is pleased the heir married one of their own")
	check(st.house.chronicle.any(func(e: Dictionary) -> bool: return str(e["kind"]) == "marriage"), "the chronicle records the wedding")
	check(events.any(func(e: Dictionary) -> bool: return (e.get("moved", []) as Array).has(c.id)), "the world is told they moved")
	# The heir's marriage can have children.
	var mother := heir if heir.gender == "female" else c
	mother.age = 25
	check(LifeSystem.birth_chance(st, mother) > 0.0, "the heir's marriage may bring children")
	# When the heir inherits, the spouse is the lady (or lord consort).
	var lord := st.get_character(fam.head_id)
	LifeSystem.die(st, lord, "old age", [] as Array[Dictionary])
	check_eq(c.occupation_id, "lady", "the heir's spouse rules beside them: %s" % c.occupation_name())


func test_matches_for_kin_and_retainers() -> void:
	var st := WorldGenerator.generate("match-arrange")
	var fam := st.ruling_family()
	var sibling := _someone(st, func(c: CharacterData) -> bool: return CourtSystem.is_kin(st, c) and c.age >= 16 and LifeSystem.spouse_of(st, c) == null)
	if sibling == null:
		sibling = _someone(st, func(c: CharacterData) -> bool: return CourtSystem.is_kin(st, c) and c.age >= 10 and LifeSystem.spouse_of(st, c) == null)
		if sibling:
			sibling.age = 20
	check(sibling != null, "found unmarried kin")
	if sibling == null:
		return
	var list := MatchSystem.candidates(st, sibling, 6)
	check(not list.is_empty(), "there are matches to choose from")
	for o in list:
		check(MatchSystem.can_wed(st, sibling, o)["ok"] and not st.is_player(o), "%s could marry %s" % [o.first_name, sibling.first_name])
	# Someone who can't stand them refuses, and says so.
	var cold: CharacterData = list[0]
	cold.add_relationship(sibling.id, "rival", -80)
	var no := MatchSystem.arrange(st, sibling, cold)
	check(no["ok"] and not no["accept"], "a rival won't marry them: %s" % no["text"])
	check(str(no["text"]).begins_with(cold.first_name + ":"), "and it's the rival who says no: %s" % no["text"])
	sibling.add_relationship(cold.id, "rival", -80)
	check(str(MatchSystem.arrange(st, sibling, cold)["text"]).begins_with("Neither"), "when both refuse, both are said to")
	cold.remove_relationship(sibling.id)
	sibling.remove_relationship(cold.id)
	# A fond match: both agree; the newcomer joins the house.
	var partner: CharacterData = list[-1]
	_heart_free(st, partner)
	partner.player_opinion = 60.0
	partner.add_relationship(sibling.id, "friend", 70)
	var yes := MatchSystem.arrange(st, sibling, partner)
	check(yes["accept"], "they agree: %s %s" % [yes["text"], yes["reasons"]])
	check(partner.family_id == fam.id and CourtSystem.is_kin(st, partner), "the partner joins the house")
	# A loyal retainer's match: the partner moves into the retainer's home.
	var r := _someone(st, func(c: CharacterData) -> bool: return c.age >= 22 and c.age <= 40 and not CourtSystem.is_kin(st, c) and LifeSystem.spouse_of(st, c) == null and Recruitment.eligible(st, c)["ok"])
	Recruitment.accept(st, r, {"wage": 3, "position": "household"})
	_heart_free(st, r)
	r.loyalty = 95.0
	var mate := MatchSystem.candidates(st, r, 6).filter(func(o: CharacterData) -> bool: return not CourtSystem.is_kin(st, o))
	check(not mate.is_empty(), "a retainer has matches too")
	if not mate.is_empty():
		var m: CharacterData = mate[0]
		_heart_free(st, m)
		m.player_opinion = 50.0
		m.add_relationship(r.id, "friend", 60)
		var done := MatchSystem.arrange(st, r, m)
		check(done["accept"], "the retainer's match is agreed: %s %s" % [done["text"], done["reasons"]])
		check(m.family_id == r.family_id and m.home_building_id == r.home_building_id, "the partner moves into the retainer's home")
		check(not CourtSystem.is_kin(st, m), "and isn't kin of the house")
	check(not MatchSystem.arrange(st, st.player(), list[0])["ok"], "the heir isn't matched by the house: they ask for themselves")


func test_suitors_visit_and_are_answered() -> void:
	var st := WorldGenerator.generate("match-suitor")
	var heir := st.player()
	var gold := st.house.gold
	var suitor := _offer(st, heir)
	check(suitor.is_visitor() and suitor.suitor_for == heir.id, "a suitor comes to court the heir")
	check(suitor.gender != heir.gender and absi(suitor.age - heir.age) <= int(MatchSystem.section("suitors").get("age_spread", 5)) + 1, "of an age with them")
	check_eq(suitor.home_building_id, CourtSystem._building_of_type(st, "manor"), "staying at the manor")
	check_eq(suitor.social_status, "noble", "a noble")
	check(not suitor.appraised and not suitor.met, "a stranger: only the Eye will tell what they are")
	check(st.realm.get_house(suitor.house_id).size() > 0, "from one of the houses")
	check(not Recruitment.eligible(st, suitor)["ok"], "a guest can't be recruited")
	check(not LifeSystem.can_court(st, suitor), "nor courted by the village")
	check(CourtSystem.role_name(st, suitor).begins_with("Suitor from House"), "they're known as a suitor")
	var praise := MatchSystem.letter(st, suitor)
	check(praise.ends_with(".") and not praise.contains("{"), "their letter praises them: %s" % praise)
	check_eq(MatchSystem.letter(st, suitor), praise, "the same letter each time it's read")
	var seat := str(st.realm.get_house(suitor.house_id)["seat"])
	var hello := Discovery.conversation(st, suitor)
	check(hello[0].contains(seat) and not hello[0].contains("{"), "they introduce themselves: %s" % hello[0])
	check(CourtSystem.scion_text(st, suitor).begins_with("A guest"), "a guest at the manor, not at lessons")
	# One visit at a time.
	for d in 3:
		st.minutes += Calendar.MINUTES_PER_DAY
		MatchSystem.daily_update(st)
	check(st.characters.filter(func(c: CharacterData) -> bool: return c.is_visitor()).size() == 1, "one suitor visits at a time")
	# Accepted: they marry the heir and the dowry comes.
	var house_before := st.realm.get_house(suitor.house_id).duplicate()
	var r := MatchSystem.accept(st, suitor)
	check(r["ok"], r["text"])
	check(LifeSystem.spouse_of(st, heir) == suitor and not suitor.is_visitor(), "the heir is married")
	check_eq(st.house.gold, gold + MatchSystem.dowry(st, suitor.house_id), "the dowry is paid")
	check(int(st.realm.get_house(suitor.house_id)["standing"]) > int(house_before["standing"]), "their house thinks well of yours")
	check(CourtSystem.is_kin(st, suitor), "and the suitor is family now")
	check(not MatchSystem.seeks(st, heir), "a married heir gets no more suitors")


func test_a_suitor_declined_or_kept_waiting_goes_home() -> void:
	var st := WorldGenerator.generate("match-home")
	var heir := st.player()
	var a := _offer(st, heir)
	var standing := int(st.realm.get_house(a.house_id)["standing"])
	var events: Array[Dictionary] = []
	MatchSystem.decline(st, a, events)
	check(st.get_character(a.id) == null and st.get_departed(a.id) != null, "declined, they go home")
	check(int(st.realm.get_house(a.house_id)["standing"]) < standing, "and their house is cooler toward yours")
	check(events.any(func(e: Dictionary) -> bool: return int(e.get("gone", -1)) == a.id), "the world is told they've gone")
	var b := _offer(st, heir)
	var h := st.realm.get_house(b.house_id)
	var before := int(h["standing"])
	st.minutes += float(int(MatchSystem.section("suitors").get("visit_days", 10)) + 1) * Calendar.MINUTES_PER_DAY
	var news := MatchSystem.daily_update(st)
	check(st.get_character(b.id) == null, "a suitor left waiting goes home when the visit is over")
	check(int(h["standing"]) < before, "their house is offended")
	check(news.any(func(e: Dictionary) -> bool: return int(e.get("gone", -1)) == b.id and not str(e["text"]).is_empty()), "and you hear of it")


func test_suitors_come_in_time() -> void:
	var st := WorldGenerator.generate("match-time")
	_single_heir(st)
	var came := 0
	for d in 80:
		st.minutes += Calendar.MINUTES_PER_DAY
		for e: Dictionary in MatchSystem.daily_update(st):
			if e.has("visitor"):
				came += 1
	check(came >= 1 and came <= 6, "over two years a few suitors come for an unmarried heir (%d)" % came)


func test_the_house_s_children_have_tutors() -> void:
	var st := WorldGenerator.generate("match-tutor")
	var kid := _someone(st, func(c: CharacterData) -> bool: return CourtSystem.is_kin(st, c) and c.age >= 6 and c.age <= 17)
	if kid == null:
		kid = _someone(st, func(c: CharacterData) -> bool: return CourtSystem.is_kin(st, c))
		kid.age = 10
	check(CourtSystem.is_tutored(st, kid), "%s (%d) is at lessons" % [kid.first_name, kid.age])
	check(not CourtSystem.is_tutored(st, st.player()), "the heir studies on their own")
	check(CourtSystem.scion_text(st, kid).begins_with("Studying"), "about the manor they're at lessons: %s" % CourtSystem.scion_text(st, kid))
	var grown := kid.age
	kid.age = 20
	check(CourtSystem.scion_text(st, kid) == "Helping to run the estate", "grown, they help run the estate")
	kid.age = grown
	var wages := CourtSystem.daily_wages(st)
	check(wages >= CourtSystem.tutored(st).size() * int(CourtSystem.section("tutors").get("fee", 1)), "the tutors are paid")
	var attr := "intelligence"
	kid.set_attribute(attr, 5, 120)
	CourtSystem.set_focus(st, kid, attr)
	for d in 20:
		CourtSystem.train_day(st, kid)
	check(kid.get_current(attr) > 5 and kid.get_current(attr) <= 120, "they learn in their focus (5 -> %d)" % kid.get_current(attr))


func test_the_live_world_receives_a_suitor() -> void:
	Game.state = WorldGenerator.generate("match-live")
	var st := Game.state
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var heir := _single_heir(st)
	var events: Array[Dictionary] = []
	var s := MatchSystem.offer(st, heir, Seeds.rng(1, "live"), events)
	world.apply_life_events(events)
	check(world.npc_of(s.id) != null, "the suitor arrives in the village")
	var panel := world.ui.conversation_panel()
	panel.open(world, s, {"lines": []})
	await frames(1)
	check(panel._accept_match.visible and panel._decline_match.visible, "talking to them, you can accept or send them home")
	check(not panel._hand.visible, "(not ask for their hand: they came to ask for yours)")
	world.ui._court.refresh()
	check(world.ui._court._body.find_children("*", "Button", true, false).any(func(b: Button) -> bool: return b.text == "Accept"), "the court panel shows the offer")
	panel._on_decline_match()
	await frames(1)
	check(world.npc_of(s.id) == null and st.get_character(s.id) == null, "sent home, they leave")
	var c := _match_for_heir(st)
	panel.open(world, c, {"lines": []})
	await frames(1)
	check(panel._hand.visible and not panel._hand.disabled, "the heir can ask a villager for their hand")
	c.player_opinion = 95.0
	panel._on_hand()
	await frames(1)
	check(LifeSystem.spouse_of(st, heir) == c, "who says yes")
	check_eq(world.npc_of(c.id).character.home_building_id, CourtSystem._building_of_type(st, "manor"), "and moves to the manor")
	panel.visible = false
	world.queue_free()
	await frames(2)
