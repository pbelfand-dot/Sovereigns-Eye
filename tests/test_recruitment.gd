extends TestCase
## Motive-based recruitment: different people are won over by different
## things, offers are concrete and enforced, and answers come in plain words.

const OLD_SLOT := "test_recruitment_migration"


func _world(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.house.gold = 2000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 600.0
	return st


## Children under 16 living with them.
func _kids_at_home(st: WorldState, c: CharacterData) -> int:
	var n := 0
	for r in c.relationships_of_type(["child"]):
		var k := st.get_character(int(r["target"]))
		if k and k.age < 16 and k.home_building_id == c.home_building_id:
			n += 1
	return n


## An adult outsider aged 18-45 with at least `kids` children at home
## (exactly none when kids == 0), who isn't the head of a business.
func _find(st: WorldState, kids: int, taken: Array = []) -> CharacterData:
	for c in st.characters:
		if c.age < 18 or c.age > 45 or taken.has(c) or not Recruitment.eligible(st, c)["ok"]:
			continue
		var n := _kids_at_home(st, c)
		if (kids == 0 and n == 0) or (kids > 0 and n >= kids):
			return c
	return null


## Shapes someone into an archetype: who they are, what they're good at,
## and no friendships (so ties are the same in every world).
func _shape(c: CharacterData, status: String, job: String, traits: Array[String], opinion: float, best: String, current: int, potential: int, ambition: int = 30) -> void:
	c.social_status = status
	c.occupation_id = job
	c.traits = traits
	c.player_opinion = opinion
	c.age = clampi(c.age, 18, 30)
	for a: String in GameData.attribute_ids():
		c.set_attribute(a, 20, 30)
	c.set_attribute(best, current, potential)
	c.set_attribute("ambition", ambition, maxi(ambition, 40))
	for r in c.relationships_of_type(["friend", "rival", "lover"]):
		c.remove_relationship(int(r["target"]))


func _empty_cottage(st: WorldState) -> BuildingData:
	var site := GrowthSystem.order_home(st)
	check(site != null, "the village can order a cottage")
	if site == null:
		return null
	site.work_done = site.work_needed
	TerritorySystem.complete(st, site)
	return st.get_building(site.id())


func _texts(reasons: Array) -> String:
	var out: Array[String] = []
	for r: Dictionary in reasons:
		out.append(str(r["text"]))
	return " | ".join(out)


func _run_court_day(st: WorldState) -> Array[Dictionary]:
	st.minutes += Calendar.MINUTES_PER_DAY
	var day := Calendar.day_index(st.whole_minutes())
	return CourtSystem.daily_update(st, Seeds.rng(st.world_seed, "court_day_%d" % day))


# --- Five ways to win someone over -------------------------------------------------------

## A poor, gifted craftsperson won't give up their trade for pay alone, but
## comes for pay, a workshop and a home for the family.
func test_gifted_craftsperson_joins_for_pay_workshop_and_home() -> void:
	var st := _world("recruit-craft")
	var c := _find(st, 2)
	check(c != null, "found a parent to shape into a craftsperson")
	if c == null:
		return
	_shape(c, "commoner", "carpenter", ["diligent"], 0.0, "administration", 60, 92, 60)
	var need := Recruitment.wage_need(c)
	check_eq(need, 3, "a gifted commoner hand asks a little more than the usual 2 gold")
	var pay_only := Recruitment.evaluate(st, c, {"wage": need})
	check(not pay_only["accept"], "pay alone doesn't buy a craftsperson out of their trade")
	check(_texts(pay_only["reasons"]).contains("give up their trade"), "they say they'd lose their trade: " + _texts(pay_only["reasons"]))
	var shops := Recruitment.open_workplaces(st)
	check(not shops.is_empty(), "the village has a workplace to offer")
	var home := _empty_cottage(st)
	if shops.is_empty() or home == null:
		return
	var offer := {"wage": need, "home": home.id, "position": "workplace", "workplace": shops[0].id}
	var r := Recruitment.propose(st, c, offer)
	check_eq(r["result"], "accept", "pay, a workshop and a home win them over")
	check(c.retainer, "they join the house")
	check_eq(c.work_building_id, shops[0].id, "they work at the workplace they were given")
	check_eq(c.home_building_id, home.id, "they live in the home they were given")
	check_eq(CourtSystem.work_style(c), "", "they keep their trade's working day")
	CourtSystem.set_focus(st, c, "combat")
	check_eq(c.work_building_id, shops[0].id, "later changes keep the agreed workplace")


## A loyal friend comes for a modest wage; a stranger of the same kind
## won't.
func test_loyal_friend_accepts_modest_wages() -> void:
	var st := _world("recruit-friend")
	var friend := _find(st, 0)
	var stranger := _find(st, 0, [friend])
	check(friend != null and stranger != null, "found two people")
	if friend == null or stranger == null:
		return
	for c: CharacterData in [friend, stranger]:
		_shape(c, "peasant", "woodcutter", ["loyal", "kind"], 0.0, "combat", 30, 50)
	friend.player_opinion = 45.0
	friend.add_relationship(st.player_id, "friend", 60)
	var modest := {"wage": 1}
	check(not Recruitment.evaluate(st, stranger, modest)["accept"], "a stranger won't leave their living for 1 gold a day")
	var r := Recruitment.propose(st, friend, modest)
	check_eq(r["result"], "accept", "a loyal friend accepts a modest wage")
	check(_texts(r["reasons"]).contains("fond of you"), "they say why: " + _texts(r["reasons"]))
	check_eq(CourtSystem.wage(friend), 1, "and is paid just that")


## An ambitious fighter wants rank or training, not money.
func test_ambitious_fighter_demands_rank_or_training() -> void:
	var st := _world("recruit-fighter")
	var c := _find(st, 0)
	check(c != null, "found a young fighter")
	if c == null:
		return
	_shape(c, "commoner", "soldier", ["ambitious", "brave"], 0.0, "combat", 45, 85, 70)
	c.age = 22
	var rich := Recruitment.evaluate(st, c, {"wage": 8})
	check(not rich["accept"], "even the highest wage isn't enough")
	check(_texts(rich["reasons"]).contains("get ahead"), "they want to get ahead: " + _texts(rich["reasons"]))
	var r := Recruitment.propose(st, c, {"wage": 2})
	check_eq(r["result"], "counter", "they make a counteroffer")
	check(str(r["counter"].get("position", "")) in ["squire", "training"], "asking for rank or training (got %s)" % r["counter"])
	check(Recruitment.evaluate(st, c, {"wage": 2, "position": "training", "focus": "combat"})["accept"], "training in combat would do")
	var squire := Recruitment.propose(st, c, {"wage": 0, "position": "squire"})
	check_eq(squire["result"], "accept", "a squire's place wins them even without pay")
	check_eq(c.title, "squire", "they become a squire")
	check(c.display_name().begins_with("Squire "), "and are named as one")
	check_eq(CourtSystem.focus_of(c), "combat", "squires train at arms")


## A parent cares most about a proper home for the family.
func test_parent_joins_for_a_family_home() -> void:
	var st := _world("recruit-craft")
	var c := _find(st, 2)
	check(c != null, "found a parent")
	if c == null:
		return
	_shape(c, "commoner", "herbalist", ["kind"], 0.0, "intelligence", 30, 50)
	var family_before: Array[CharacterData] = []
	for p in st.characters:
		if p.family_id == c.family_id and p.home_building_id == c.home_building_id:
			family_before.append(p)
	var m := Recruitment.motives(st, c)
	check(float(m["home"]) >= float(m["money"]) - 0.15, "a home matters to them about as much as money: %s" % m)
	var home := _empty_cottage(st)
	if home == null:
		return
	var wage_only := Recruitment.propose(st, c, {"wage": Recruitment.wage_need(c)})
	check(wage_only["result"] != "accept", "a wage alone isn't enough for a parent")
	if wage_only["result"] == "counter":
		check(int(wage_only["counter"].get("home", -1)) != -1, "their counteroffer asks for a home")
	var r := Recruitment.propose(st, c, {"wage": 1, "home": home.id})
	check_eq(r["result"], "accept", "a home and a modest wage win them over")
	for p in family_before:
		check_eq(p.home_building_id, home.id, "%s moves into the new home too" % p.first_name)
	check(not Recruitment.available_homes(st).has(home), "the home is no longer free")


## A prosperous citizen refuses money but answers to duty and prestige.
func test_prosperous_citizen_answers_duty_not_money() -> void:
	var st := _world("recruit-burgher")
	var c := _find(st, 0)
	check(c != null, "found a citizen")
	if c == null:
		return
	_shape(c, "burgher", "merchant", ["devout"], 0.0, "administration", 55, 80)
	var fam := st.get_family(c.family_id)
	if fam:
		fam.head_id = c.id
	var money := Recruitment.propose(st, c, {"wage": 8})
	check(money["result"] != "accept", "money doesn't move them")
	check(_texts(money["reasons"]).contains("respect, not coin"), "they want respect, not coin: " + _texts(money["reasons"]))
	check(not Recruitment.evaluate(st, c, {"wage": 0, "appeal": true})["accept"], "fine words alone aren't enough")
	var office := Recruitment.vacant_office_for(st, c)
	check_eq(office, "steward", "the office that suits an administrator")
	var r := Recruitment.propose(st, c, {"wage": 0, "appeal": true, "position": "office", "office": office})
	check_eq(r["result"], "accept", "duty and an office win them over")
	check_eq(st.house.holder_of("steward"), c.id, "they take up the office at once")
	check_eq(CourtSystem.wage(c), 0, "and serve without a wage, as agreed")


# --- Offers are real ---------------------------------------------------------------------

func test_wages_are_paid_from_the_treasury_every_day() -> void:
	var st := _world("recruit-wages")
	var c := _find(st, 0)
	if c == null:
		check(false, "found someone")
		return
	var before := CourtSystem.daily_wages(st)
	Recruitment.accept(st, c, {"wage": 5})
	check_eq(CourtSystem.daily_wages(st), before + 5, "the agreed wage joins the daily wage bill")
	st.house.gold = 1000
	var income := CourtSystem.daily_income(st)
	var bill := CourtSystem.daily_wages(st)
	_run_court_day(st)
	check_eq(st.house.gold, 1000 + income - bill, "the treasury pays it")
	var standing := st.house.standing
	st.house.gold = 0
	_run_court_day(st)
	check(st.house.in_debt or CourtSystem.daily_income(st) >= bill, "unpaid wages put the house in debt")
	if st.house.in_debt:
		check(st.house.standing < standing, "and folk trust your word less")


func test_homes_and_workplaces_must_really_exist() -> void:
	var st := _world("recruit-capacity")
	var a := _find(st, 0)
	var b := _find(st, 0, [a])
	if a == null or b == null:
		check(false, "found two people")
		return
	var occupied := st.get_building(a.home_building_id)
	check(Recruitment.offer_problem(st, a, {"home": occupied.id}) != "", "you can't offer a home someone lives in")
	var home := _empty_cottage(st)
	Recruitment.accept(st, a, {"wage": 2, "home": home.id})
	check(Recruitment.offer_problem(st, b, {"home": home.id}) != "", "a home can't be given twice")
	check(Recruitment.offer_problem(st, b, {"position": "workplace", "workplace": -1}).contains("workplace"), "a job needs a workplace")
	check(Recruitment.offer_problem(st, b, {"position": "workplace", "workplace": home.id}) != "", "a cottage isn't a workplace")
	var shop: BuildingData = Recruitment.open_workplaces(st)[0]
	for i in 2:
		var w := _find(st, 0, [a, b])
		Recruitment.accept(st, w, {"wage": 2, "position": "workplace", "workplace": shop.id})
	check(Recruitment.offer_problem(st, b, {"position": "workplace", "workplace": shop.id}) != "", "a workplace holds two of your people")
	check(Recruitment.offer_problem(st, b, {"wage": 9}) != "", "wages are capped")
	check(Recruitment.offer_problem(st, b, {"position": "office", "office": "nonsense"}) != "", "offices must exist")


func test_a_kept_promise_moves_the_family_in() -> void:
	var st := _world("recruit-promise-kept")
	var c := _find(st, 1)
	if c == null:
		check(false, "found a parent")
		return
	Recruitment.accept(st, c, {"wage": 2, "home": Recruitment.PROMISE_HOME})
	check_eq(st.house.promises.size(), 1, "the promise is recorded")
	var standing := st.house.standing
	var home := _empty_cottage(st)
	var events := _run_court_day(st)
	check_eq(c.home_building_id, home.id, "the family moves in as soon as a home is free")
	check(st.house.promises.is_empty(), "the promise is fulfilled")
	check(st.house.standing > standing, "keeping your word raises your standing")
	var told := false
	for e in events:
		told = told or str(e["text"]).contains("kept your word")
	check(told, "you're told the promise was kept")


func test_a_broken_promise_costs_trust_and_can_drive_them_away() -> void:
	var st := _world("recruit-promise-broken")
	var c := _find(st, 0)
	if c == null:
		check(false, "found someone")
		return
	# No empty homes, and none being built.
	for b in Recruitment.available_homes(st):
		b.type = "storehouse"
	st.house.gold = 5000
	Recruitment.accept(st, c, {"wage": 2, "home": Recruitment.PROMISE_HOME})
	var opinion := c.player_opinion
	var loyalty := c.loyalty
	var standing := st.house.standing
	var days := int(Recruitment.cfg()["promises"]["home_days"]) + 1
	for d in days:
		_run_court_day(st)
	check(c.player_opinion < opinion - 10.0, "their opinion of you falls")
	check(c.loyalty < loyalty, "their loyalty falls")
	check(st.house.standing < standing, "your house's word is trusted less")
	check(st.house.promises.is_empty(), "the promise is closed")
	# Someone already wavering leaves over it.
	var d2 := _find(st, 0, [c])
	Recruitment.accept(st, d2, {"wage": 2, "home": Recruitment.PROMISE_HOME})
	d2.loyalty = 30.0
	for d in days:
		_run_court_day(st)
	check(not d2.retainer, "a wavering retainer leaves over a broken promise")
	# And a weaker word makes the next promise worth less.
	var e := _find(st, 0, [c, d2])
	var low := Recruitment.evaluate(st, e, {"wage": 2, "home": Recruitment.PROMISE_HOME})
	st.house.standing = 80.0
	var high := Recruitment.evaluate(st, e, {"wage": 2, "home": Recruitment.PROMISE_HOME})
	check(float(high["satisfaction"]["home"]) > float(low["satisfaction"]["home"]), "promises from a trusted house count for more")


# --- Talking it through ------------------------------------------------------------------

func test_asking_reveals_motives_strongest_first() -> void:
	var st := _world("recruit-ask")
	var c := _find(st, 2)
	if c == null:
		check(false, "found someone")
		return
	var ranked := Recruitment.ranked_motives(st, c)
	check(not ranked.is_empty(), "everyone wants something")
	var first := Recruitment.ask(st, c)
	check_eq(first["motive"], ranked[0], "they speak of what matters most first")
	check(not str(first["line"]).is_empty() and not str(first["line"]).contains("{"), "in their own words")
	for i in ranked.size():
		Recruitment.ask(st, c)
	check_eq(c.known_motives.size(), ranked.size(), "every motive can be learned")
	var done := Recruitment.ask(st, c)
	check_eq(done["motive"], "", "then there's nothing more to tell")


## Someone who values fondness only says they'd follow you if they're fond
## of you; wary, they say trust must be earned.
func test_what_they_say_of_fondness_fits_how_they_feel() -> void:
	var st := _world("recruit-bond-line")
	var c := _find(st, 0)
	if c == null:
		check(false, "found someone")
		return
	var fond: Array = Recruitment.cfg()["ask_lines"]["bond"]
	var wary: Array = Recruitment.cfg()["ask_lines"]["bond_wary"]
	c.traits = ["loyal"] as Array[String]
	for opinion: float in [-30.0, 60.0]:
		c.player_opinion = opinion
		c.known_motives.clear()
		for id: String in Recruitment.ranked_motives(st, c):
			if id != "bond":
				c.known_motives.append(id)
		var r := Recruitment.ask(st, c)
		check_eq(r["motive"], "bond", "they speak of fondness")
		var pool := wary if opinion < 0.0 else fond
		var said := false
		for line: String in pool:
			said = said or Recruitment._fill(line, st) == str(r["line"])
		check(said, "at opinion %d they say a fitting line: %s" % [roundi(opinion), r["line"]])


func test_answers_are_plain_words_and_deterministic() -> void:
	var st := _world("recruit-words")
	var n := 0
	for c in st.characters:
		if not Recruitment.eligible(st, c)["ok"]:
			continue
		var offer := {"wage": 2}
		var a := Recruitment.evaluate(st, c, offer)
		var b := Recruitment.evaluate(st, c, offer)
		check_eq(a["total"], b["total"], "the same offer gets the same answer")
		check(not (a["reasons"] as Array).is_empty(), "%s gives a reason" % c.first_name)
		for r: Dictionary in a["reasons"]:
			check(not str(r["text"]).contains("%") and not str(r["text"]).contains("{"), "reasons are words, not numbers: " + str(r["text"]))
		n += 1
	check(n > 10, "many people were asked")


## Making an offer is what talking is for: a "no" never closes the door.
func test_a_refusal_never_closes_the_door() -> void:
	var st := _world("recruit-craft")
	var c := _find(st, 2)
	if c == null:
		check(false, "found someone")
		return
	_shape(c, "commoner", "carpenter", ["diligent"], 0.0, "administration", 60, 92, 60)
	var r := Recruitment.propose(st, c, {"wage": Recruitment.wage_need(c)})
	check(r["result"] != "accept", "pay alone isn't enough for them")
	check(Recruitment.can_offer(st, c)["ok"], "you can make another offer at once")
	var home := _empty_cottage(st)
	var shop: BuildingData = Recruitment.open_workplaces(st)[0]
	var better := Recruitment.propose(st, c, {"wage": Recruitment.wage_need(c), "home": home.id, "position": "workplace", "workplace": shop.id})
	check_eq(better["result"], "accept", "a better offer right after is accepted (%s)" % better["text"])


func test_a_full_household_costs_upkeep_not_offers() -> void:
	var st := _world("recruit-full")
	var cap := CourtSystem.retainer_cap(st)
	var taken: Array = []
	for i in cap:
		var p := _find(st, 0, taken)
		taken.append(p)
		Recruitment.accept(st, p, {"wage": 1})
	check_eq(CourtSystem.household_upkeep(st), 0, "no upkeep while within what your renown supports")
	var extra := _find(st, 0, taken)
	check(Recruitment.can_offer(st, extra)["ok"], "a full household doesn't stop an offer")
	var bill := CourtSystem.daily_wages(st)
	_shape(extra, "peasant", "woodcutter", ["loyal", "kind"], 45.0, "combat", 30, 50)
	extra.add_relationship(st.player_id, "friend", 60)
	var r := Recruitment.propose(st, extra, {"wage": 1})
	check_eq(r["result"], "accept", "they can join beyond the limit")
	var upkeep := int(CourtSystem.section("house")["over_cap_upkeep"])
	check_eq(CourtSystem.household_upkeep(st), upkeep, "one place beyond the limit costs upkeep")
	check_eq(CourtSystem.daily_wages(st), bill + 1 + upkeep, "paid from the treasury with the wages")


func test_retainers_hear_new_terms() -> void:
	var st := _world("recruit-terms")
	var c := _find(st, 0)
	if c == null:
		check(false, "found someone")
		return
	_shape(c, "commoner", "herbalist", [], 20.0, "administration", 50, 80)
	Recruitment.accept(st, c, {"wage": 2})
	check(Recruitment.can_offer(st, c)["ok"], "you can always offer your own retainer new terms")
	var now := Recruitment.current_terms(st, c)
	check_eq(int(now["wage"]), 2, "their current terms are known")
	var loyalty := c.loyalty
	var raise := now.duplicate()
	raise["wage"] = 5
	var r := Recruitment.propose(st, c, raise)
	check_eq(r["result"], "accept", "a raise is taken")
	check_eq(CourtSystem.wage(c), 5, "and paid")
	check(c.loyalty > loyalty, "it raises their loyalty (%d -> %d)" % [roundi(loyalty), roundi(c.loyalty)])
	var cut := Recruitment.current_terms(st, c)
	cut["wage"] = 0
	loyalty = c.loyalty
	var r2 := Recruitment.propose(st, c, cut)
	check_eq(r2["result"], "refuse", "worse terms are turned down")
	check_eq(CourtSystem.wage(c), 5, "and nothing changes")
	check(c.loyalty < loyalty, "it stings a little")
	var office := Recruitment.current_terms(st, c)
	office["position"] = "office"
	office["office"] = "steward"
	var r3 := Recruitment.propose(st, c, office)
	check_eq(r3["result"], "accept", "an office is welcome")
	check_eq(st.house.holder_of("steward"), c.id, "they take it up")
	check_eq(Recruitment.current_terms(st, c)["position"], "office", "and serve as steward now")
	var same := Recruitment.current_terms(st, c)
	same["wage"] = 6
	check_eq(Recruitment.propose(st, c, same)["result"], "accept", "keeping their office with a raise is fine")
	check_eq(st.house.holder_of("steward"), c.id, "they keep the office")
	# Giving up an office for less is a step down they won't take.
	var school := {"wage": 8, "home": -1, "position": "training", "focus": "administration", "appeal": false}
	check_eq(Recruitment.propose(st, c, school)["result"], "refuse", "a steward won't give up the office for training")
	check_eq(st.house.holder_of("steward"), c.id, "and stays steward")
	# A politician made steward moves gladly to the chancellor's seat,
	# leaving the steward's office free.
	var d := _find(st, 0, [c])
	if d == null:
		check(false, "found a second retainer")
		return
	_shape(d, "commoner", "scribe", [], 20.0, "politics", 50, 80)
	Recruitment.accept(st, d, {"wage": 2})
	CourtSystem.vacate(st, "steward")
	Recruitment.propose(st, d, {"wage": 2, "home": -1, "position": "office", "office": "steward", "appeal": false})
	check_eq(st.house.holder_of("steward"), d.id, "they take the steward's office")
	var seat := {"wage": 2, "home": -1, "position": "office", "office": "chancellor", "appeal": false}
	check_eq(Recruitment.propose(st, d, seat)["result"], "accept", "the office that suits them is welcome")
	check_eq(st.house.holder_of("chancellor"), d.id, "they're chancellor now")
	check_eq(st.house.holder_of("steward"), -1, "and the steward's office is free again")
	check_eq(Recruitment.current_terms(st, d)["office"], "chancellor", "their terms say so")


func test_only_you_your_family_and_small_children_cant_be_asked() -> void:
	var st := _world("recruit-who")
	check(not Recruitment.can_offer(st, st.player())["ok"], "not yourself")
	for c in st.characters:
		if CourtSystem.is_kin(st, c) and not st.is_player(c):
			check(str(Recruitment.can_offer(st, c)["reason"]).contains("family"), "not your own family: %s" % Recruitment.can_offer(st, c)["reason"])
			break
	for c in st.characters:
		if c.age < 10 and not CourtSystem.is_kin(st, c):
			check(not Recruitment.can_offer(st, c)["ok"], "not small children")
			break
	var asked := 0
	for c in st.characters:
		if c.age >= 10 and not CourtSystem.is_kin(st, c) and not st.is_player(c):
			check(Recruitment.can_offer(st, c)["ok"], "%s can always be asked" % c.first_name)
			asked += 1
	check(asked > 20, "everyone else can be asked")


func test_children_join_with_a_parent_deciding() -> void:
	var st := _world("recruit-page")
	var kid: CharacterData = null
	for c in st.characters:
		if c.age >= 10 and c.age <= 15 and Recruitment.eligible(st, c)["ok"] and not c.relationships_of_type(["parent"]).is_empty():
			kid = c
			break
	if kid == null:
		check(false, "found a child of 10-15")
		return
	var parent := Recruitment.decider(st, kid)
	check(parent != kid, "a parent decides for a child")
	var ev := Recruitment.evaluate(st, kid, {"wage": 1})
	check_eq(ev["weights"], Recruitment.motives(st, parent), "weighing the parent's motives")


# --- Saves ---------------------------------------------------------------------------------

func test_terms_and_promises_survive_saving() -> void:
	var st := _world("recruit-save")
	var c := _find(st, 0)
	if c == null:
		check(false, "found someone")
		return
	Recruitment.ask(st, c)
	Recruitment.accept(st, c, {"wage": 4, "home": Recruitment.PROMISE_HOME, "position": "squire"})
	st.house.standing = 61.5
	var back := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	var c2 := back.get_character(c.id)
	check_eq(c2.agreed_wage, 4, "the agreed wage")
	check_eq(c2.title, "squire", "the title")
	check_eq(c2.known_motives, c.known_motives, "the motives they told you")
	check_eq(int(c2.terms["home"]), Recruitment.PROMISE_HOME, "the terms (as whole numbers)")
	check(c2.terms["home"] is int, "terms numbers come back as ints")
	check_eq(back.house.standing, 61.5, "the house's standing")
	check_eq(back.house.promises, st.house.promises, "open promises")


func test_older_saves_migrate() -> void:
	var st := _world("recruit-migrate")
	var old := JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary
	old["save_version"] = 5
	var h: Dictionary = old["house"]
	h.erase("standing")
	h.erase("promises")
	for c: Dictionary in old["characters"]:
		for k: String in ["known_motives", "terms", "agreed_wage", "title"]:
			c.erase(k)
	var migrated := SaveManager.migrate(old)
	check_eq(int(migrated["save_version"]), WorldState.SAVE_VERSION, "migrates to the current version")
	var back := WorldState.from_dict(migrated)
	check_eq(back.house.standing, 50.0, "standing starts fair")
	check(back.house.promises.is_empty(), "no promises")
	for c in back.retainers():
		check_eq(c.agreed_wage, -1, "existing retainers keep the standard wage")


func test_leaving_service_ends_the_terms() -> void:
	var st := _world("recruit-leave")
	var c := _find(st, 0)
	if c == null:
		check(false, "found someone")
		return
	Recruitment.accept(st, c, {"wage": 5, "home": Recruitment.PROMISE_HOME, "position": "squire"})
	check_eq(st.house.promises.size(), 1, "a promise is open")
	CourtSystem.dismiss(st, c)
	check(c.terms.is_empty() and c.agreed_wage == -1 and c.title.is_empty(), "their terms and title end with their service")
	check(st.house.promises.is_empty(), "promises to them lapse")
	check_eq(CourtSystem.wage(c), 0, "and no wage is owed")
	var standing := st.house.standing
	_run_court_day(st)
	check(st.house.standing <= standing, "standing doesn't rise without anyone to pay")
