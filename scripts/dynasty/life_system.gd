class_name LifeSystem
extends RefCounted
## Phase 4.1, the years turn. Everyone ages on their birthday: children grow
## (taller, and their hidden gifts begin to show in what they can do), take
## up their family's work at 13 and a grown trade at 16; commoners retire to
## an elder's life. Unmarried villagers court and marry and set up home;
## couples have children whose gifts often (never always) follow theirs.
## Adults die in time, of old age or now and then an illness, and their kin
## mourn them. The world is a gentle one: no child dies, and no one dies in
## childbirth. When the lord dies, the heir (the player) inherits.
##
## The departed move to WorldState.departed, so family ties and the
## chronicle keep them. The house's own matches (the heir's marriage, kin and
## retainers) come in Phase 4.2; succession after the heir in 4.3.
##
## Static and deterministic: each day draws from its own stream
## (Seeds.rng(seed, "life_<day>")). Numbers: data/life.json.

const KIN := ["spouse", "parent", "child", "sibling", "grandparent", "grandchild"]


static func cfg() -> Dictionary:
	return GameData.load_file("life")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


## A yearly chance spread over the days of a year.
static func daily(yearly: float) -> float:
	return 1.0 - pow(1.0 - clampf(yearly, 0.0, 0.999999), 1.0 / Calendar.days_per_year())



## Yearly chance of dying at `age` (none below the minimum age).
static func death_yearly(age: int) -> float:
	var d := section("death")
	if age < int(d.get("min_age", 18)):
		return 0.0
	var pts: Array = d.get("yearly", [[18, 0.002]])
	if age <= int(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if age <= int(pts[i][0]):
			var t := inverse_lerp(float(pts[i - 1][0]), float(pts[i][0]), float(age))
			return lerpf(float(pts[i - 1][1]), float(pts[i][1]), t)
	return float(pts[-1][1])


## Babies stay at home, unseen, until they can walk about.
static func is_unseen(c: CharacterData) -> bool:
	return c.age < int(section("ages").get("unseen_below", 3))


## The year they were born (their birthday may still be to come this year).
static func birth_year(state: WorldState, c: CharacterData) -> int:
	return state.current_year() - c.age - (0 if state.day_of_year() >= c.birthday else 1)


## "Spring 1170": the season and year they were born.
static func born_text(state: WorldState, c: CharacterData) -> String:
	var seasons := Calendar.seasons()
	return "%s %d" % [seasons[clampi(c.birthday / Calendar.days_per_season(), 0, seasons.size() - 1)], birth_year(state, c)]


## Their husband or wife, if living.
static func spouse_of(state: WorldState, c: CharacterData) -> CharacterData:
	for r in state.living_ties(c, ["spouse"]):
		return state.get_character(int(r["target"]))
	return null


static func lover_of(state: WorldState, c: CharacterData) -> CharacterData:
	for r in state.living_ties(c, ["lover"]):
		return state.get_character(int(r["target"]))
	return null


## Their children, living and departed.
static func children_count(c: CharacterData) -> int:
	return c.relationships_of_type(["child"]).size()


# --- The day ------------------------------------------------------------------------------

## Runs once per in-game day, after the stores and before settlers arrive.
## Returns events: {text, kind, character?} plus what the world must redraw:
## "aged" (a birthday: new height, maybe new clothes), "job" (new work or
## retired), "moved" (ids with a new home), "born" (a baby, unseen yet),
## "seen" (a child old enough to walk about), "gone" (died or left).
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var day := state.day()
	var rng := Seeds.rng(state.world_seed, "life_%d" % day)
	var doy := state.day_of_year()
	for c in state.characters.duplicate():
		if c.birthday == doy:
			_birthday(state, c, rng, events)
	for c in state.characters.duplicate():
		var p := death_yearly(c.age)
		if c.is_visitor():
			continue  # a guest's fate is their own house's
		if p > 0.0 and not (state.is_player(c) and bool(section("death").get("spare_player", true))) and rng.randf() < daily(p):
			var old_age: bool = c.age >= int(section("death").get("old_age_from", 68))
			die(state, c, "old age" if old_age else str(Seeds.pick(rng, section("death").get("illness", ["an illness"]))), events)
	_courtship(state, rng, events)
	_births(state, rng, events)
	_leaving(state, rng, events)
	return events


# --- Birthdays ------------------------------------------------------------------------------

static func _birthday(state: WorldState, c: CharacterData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	c.age += 1
	var ages := section("ages")
	_grow(c)
	_age_looks(c, rng)
	events.append({"text": "", "aged": c.id})
	if c.age == int(ages.get("unseen_below", 3)):
		events.append({"text": "", "seen": c.id})
	if state.is_player(c):
		events.append({"text": "Your birthday: you are %d today." % c.age, "kind": "good", "character": c.id})
	if c.retainer or state.is_player(c):
		return
	var fam := state.get_family(c.family_id)
	var bg := GameData.background(fam.background if fam else "farming")
	var young := str(bg.get("young_job", "child"))
	var teen := str(bg.get("teen_job", young))
	if c.age == int(ages.get("teen", 13)) and c.occupation_id == young and teen != young:
		_take_up(state, c, teen, events, "Began to learn the work of a %s" % GameData.occupation(teen).get("name", teen).to_lower())
	elif c.age == CharacterData.ADULT_AGE and c.occupation_id in [young, teen]:
		var head := state.get_character(fam.head_id) if fam else null
		var hungry := food_short(state) and not CourtSystem.is_kin(state, c)
		if c.occupation_id == "apprentice" and head and head != c and passes_on(head.occupation_id) and head.work_building_id >= 0 \
				and (not hungry or _makes_food(head.occupation_id)) and rng.randf() < float(section("trades").get("follow_family", 0.6)):
			var trade := str(GameData.occupation(head.occupation_id).get("name", head.occupation_id)).to_lower()
			_take_up(state, c, head.occupation_id, events, "Came of age and joined the family trade as a %s" % trade)
			c.work_building_id = head.work_building_id
		else:
			var adult := str(Seeds.pick(rng, bg.get("adult_jobs", [teen])))
			if hungry and not _makes_food(adult):
				adult = str(section("trades").get("food_job", "farmhand"))
			if adult != c.occupation_id:
				_take_up(state, c, adult, events, "Came of age and took up work as a %s" % GameData.occupation(adult).get("name", adult).to_lower())
		if CourtSystem.is_kin(state, c):
			events.append({"text": "%s has come of age." % c.full_name(), "kind": "good", "character": c.id})
	elif c.age >= int(ages.get("retire", 65)) and _can_retire(state, c):
		var was := c.occupation_name()
		var trade := c.occupation_id
		var work := c.work_building_id
		c.occupation_id = "elder"
		c.social_status = CharacterGenerator.status_for("elder", fam)
		c.work_building_id = -1
		c.add_history(state.current_year(), state.current_season(), "career", "Retired from work as a %s" % was.to_lower())
		events.append({"text": "", "job": c.id})
		pass_on_trade(state, trade, work, c.family_id, events)


## Abilities grow with the years toward what their age, training and station
## would give them (never past their potential), and fade a little in old age.
static func _grow(c: CharacterData) -> void:
	var mult := 1.08 if c.has_trait("diligent") else (0.88 if c.has_trait("lazy") else 1.0)
	for attr_id: String in GameData.attribute_ids():
		var potential := c.get_potential(attr_id)
		var dev := TalentRoller.age_development(c.age, attr_id) * TalentRoller.training_factor(c.social_status, c.occupation_id, attr_id) * mult
		var target := clampi(roundi(potential * clampf(dev, 0.0, 1.0)), 0, potential)
		var now := c.get_current(attr_id)
		if target > now:
			c.set_attribute(attr_id, target, potential)
		elif c.age >= 60 and target < now:
			c.set_attribute(attr_id, now - ceili((now - target) * 0.25), potential)


## Children grow taller; young men may grow a beard; hair greys with age.
static func _age_looks(c: CharacterData, rng: RandomNumberGenerator) -> void:
	var looks := section("looks")
	var ap := c.appearance
	if c.age <= CharacterData.ADULT_AGE:
		if not ap.has("adult_height"):
			ap["adult_height"] = snappedf(float(ap.get("height", 1.0)) / CharacterGenerator.child_height(c.age - 1), 0.001)
		ap["height"] = snappedf(float(ap["adult_height"]) * CharacterGenerator.child_height(c.age), 0.001)
	if c.gender == "male" and c.age == int(looks.get("beard_age", 20)) and rng.randf() < float(looks.get("beard_chance", 0.45)):
		ap["beard"] = true
	if c.age >= int(looks.get("grey_from", 50)) and rng.randf() < float(looks.get("grey_yearly", 0.12)):
		var greys: Array = GameData.appearance().get("elder_hair_colors", [])
		if not greys.is_empty() and not greys.has(ap.get("hair", "")):
			ap["hair"] = str(Seeds.pick(rng, greys))


static func _take_up(state: WorldState, c: CharacterData, occupation_id: String, events: Array[Dictionary], story: String) -> void:
	var fam := state.get_family(c.family_id)
	c.occupation_id = occupation_id
	c.social_status = CharacterGenerator.status_for(occupation_id, fam)
	var gen := CharacterGenerator.new()
	gen.state = state
	c.work_building_id = gen._choose_workplace(c, state.get_character(fam.head_id) if fam else null)
	c.add_history(state.current_year(), state.current_season(), "career", story)
	events.append({"text": "", "job": c.id})


## Commoners leave work for an elder's life; nobles, retainers and the clergy
## keep their place.
static func _can_retire(state: WorldState, c: CharacterData) -> bool:
	if c.occupation_id in ["elder", "dowager", "child"] or CourtSystem.is_kin(state, c) or not c.office.is_empty():
		return false
	return c.status_tier() <= int(GameData.status_def("burgher").get("tier", 2)) and c.social_status != "clergy"


# --- Trades ---------------------------------------------------------------------------------

## Does the village grow less food than it eats (plus a margin)?
static func food_short(state: WorldState) -> bool:
	if state.territory == null:
		return false
	var cons := float(TerritorySystem.consumption(state).get("food", 0.0))
	return float(TerritorySystem.net_change(state).get("food", 0.0)) < cons * float(section("trades").get("food_margin", 0.1))


static func _makes_food(occupation_id: String) -> bool:
	return float(TerritorySystem.section("production").get(occupation_id, {}).get("food", 0.0)) > 0.0

## A trade worth carrying on when its holder goes (not the house's places,
## a child's or an elder's, nor the village's pool of hands).
static func passes_on(occupation_id: String) -> bool:
	if occupation_id.is_empty() or occupation_id in section("trades").get("not_passed_on", []):
		return false
	return not (TerritorySystem.section("hiring").get("from", []) as Array).has(occupation_id)


## Someone left `occupation_id` at `workplace`: a grown son or daughter
## (anyone of the family not yet in a trade) carries it on, else one of the
## village's hands. Returns who took it up, or null.
static func pass_on_trade(state: WorldState, occupation_id: String, workplace: int, family_id: int, events: Array[Dictionary]) -> CharacterData:
	if not passes_on(occupation_id):
		return null
	var hiring := TerritorySystem.section("hiring")
	var pool: Array = hiring.get("from", [])
	# While food is short, the fields keep their hands for food trades.
	var spare_fields := food_short(state) and not _makes_food(occupation_id)
	var best: CharacterData = null
	var best_rank := INF
	for c in state.characters:
		if c.retainer or state.is_player(c) or CourtSystem.is_kin(state, c):
			continue
		if c.age < int(hiring.get("min_age", 16)) or c.age > int(hiring.get("max_age", 59)) or not pool.has(c.occupation_id):
			continue
		if spare_fields and c.family_id != family_id and _makes_food(c.occupation_id):
			continue
		var rank := pool.find(c.occupation_id) + (0 if c.family_id == family_id else 100)
		if rank < best_rank or (rank == best_rank and best and c.id < best.id):
			best_rank = rank
			best = c
	if best == null:
		return null
	var trade := str(GameData.occupation(occupation_id).get("name", occupation_id)).to_lower()
	var story := ("Took over the family trade as a %s" if best.family_id == family_id else "Took up work as the %s at %s") % ([trade] if best.family_id == family_id else [trade, state.get_building(workplace).name if state.get_building(workplace) else state.village_name])
	best.occupation_id = occupation_id
	best.social_status = CharacterGenerator.status_for(occupation_id, state.get_family(best.family_id))
	best.work_building_id = workplace
	best.add_history(state.current_year(), state.current_season(), "career", story)
	events.append({"text": "", "job": best.id})
	return best


# --- Death, leaving and the lord's succession ------------------------------------------------

## They die (`cause`: "old age", "a fever"...). Their kin mourn them
## (MoodSystem) and the living close ranks behind them.
static func die(state: WorldState, c: CharacterData, cause: String, events: Array[Dictionary]) -> void:
	var text := "%s has died of %s, aged %d." % [c.display_name(), cause, c.age]
	c.add_history(state.current_year(), state.current_season(), "life", "Died of %s" % cause)
	var notable := _notable(state, c)
	var lord := state.ruling_family() and state.ruling_family().head_id == c.id
	depart(state, c, "died", cause, events)
	if lord:
		text = _succeed(state, c, cause, events)
	elif not c.office.is_empty() or c.retainer:
		text = "%s, %s, has died of %s." % [c.display_name(), "your " + CourtSystem.office_name(c.office) if not c.office.is_empty() else "one of your retainers", cause]
	if (notable or lord) and state.house:
		state.house.log_event(state.day(), text, "death")
	events.append({"text": text if notable or lord else "", "kind": "bad", "gone": c.id})


## They pack up and go to seek their fortune elsewhere.
static func leave(state: WorldState, c: CharacterData, events: Array[Dictionary]) -> void:
	c.add_history(state.current_year(), state.current_season(), "life", "Left %s to seek their fortune" % state.village_name)
	var notable := _notable(state, c)
	depart(state, c, "left", "seeking their fortune", events)
	var text := "%s has left %s to seek their fortune." % [c.full_name(), state.village_name]
	if notable and state.house:
		state.house.log_event(state.day(), text, "leave")
	events.append({"text": text if notable else "", "kind": "info", "gone": c.id})


## Someone the player knows: kin, a retainer, someone met or looked at.
static func _notable(state: WorldState, c: CharacterData) -> bool:
	return c.met or c.appraised or c.retainer or CourtSystem.is_kin(state, c) or c.remembered


## Moves `c` from the living to the departed ("died" or "left"): their
## office, promises and place on a crew are given up, a sweetheart is free,
## a spouse is widowed, the family has a new head, a trade passes on.
static func depart(state: WorldState, c: CharacterData, how: String, cause: String, events: Array[Dictionary]) -> void:
	c.departed_day = state.day()
	c.departed_how = how
	c.departed_cause = cause
	if not c.office.is_empty():
		var office := c.office
		CourtSystem.vacate(state, office)
		c.office = office  # kept on the record
	if state.house:
		var open_promises: Array[Dictionary] = []
		for p in state.house.promises:
			if int(p.get("character", -1)) != c.id:
				open_promises.append(p)
		state.house.promises = open_promises
	if state.territory:
		for s in state.territory.sites:
			if s.builders.has(c.id):
				s.builders.erase(c.id)
				TerritorySystem.refresh_crew(state, s)
	for r in c.relationships:
		var other := state.get_character(int(r["target"]))
		if other == null:
			continue
		var back := other.get_relationship(c.id)
		if back.is_empty():
			continue
		if back["type"] == "lover":
			other.remove_relationship(c.id)
			other.courting_since = -1
		elif back["type"] == "spouse" and how == "died":
			back["type"] = "late_spouse"
	var fam := state.get_family(c.family_id)
	state.remove_character(c)
	if fam:
		fam.member_ids.erase(c.id)
		if fam.head_id == c.id:
			fam.head_id = _next_head(state, fam)
	if not c.retainer:
		pass_on_trade(state, c.occupation_id, c.work_building_id, c.family_id, events)


## Who leads a family next: the surviving spouse, else the eldest grown
## member, else the eldest.
static func _next_head(state: WorldState, fam: FamilyData) -> int:
	var best: CharacterData = null
	for id in fam.member_ids:
		var m := state.get_character(id)
		if m == null:
			continue
		if best == null or (m.is_adult() and not best.is_adult()) or (m.is_adult() == best.is_adult() and m.age > best.age):
			best = m
	return best.id if best else -1


## The lord is dead; the heir inherits. Returns the news.
static func _succeed(state: WorldState, lord: CharacterData, cause: String, events: Array[Dictionary]) -> String:
	var fam := state.ruling_family()
	var heir := state.player()
	var word := lord.display_name()
	if heir == null:
		return "%s has died of %s." % [word, cause]
	var tie := heir.get_relationship(lord.id)
	match str(tie.get("type", "")):
		"parent":
			word = "Your %s, %s," % ["father" if lord.gender == "male" else "mother", lord.display_name()]
		"grandparent":
			word = "Your %s, %s," % ["grandfather" if lord.gender == "male" else "grandmother", lord.display_name()]
	fam.head_id = heir.id
	for r in lord.relationships_of_type(["spouse"]):
		var widow := state.get_character(int(r["target"]))
		if widow and widow.occupation_id in ["lady", "lord"]:
			widow.occupation_id = "dowager"
			events.append({"text": "", "job": widow.id})
	# The heir's own husband or wife is now the lady (or lord consort).
	var consort := spouse_of(state, heir)
	if consort:
		consort.occupation_id = "lady"
		events.append({"text": "", "job": consort.id})
	heir.occupation_id = "lord"
	heir.social_status = "noble"
	heir.work_building_id = CourtSystem._building_of_type(state, "manor")
	var title := "%s of %s" % [heir.occupation_name(), state.village_name]
	heir.add_history(state.current_year(), state.current_season(), "appointment", "Became %s on the death of %s" % [title, lord.full_name()])
	events.append({"text": "", "job": heir.id})
	return "%s has died of %s. You are now %s." % [word, cause, title]


# --- Courtship and marriage ------------------------------------------------------------------

## Unmarried villagers free to court: grown, not the ruling family or a
## retainer (their matches are the house's, Phase 4.2), and not newly widowed.
static func can_court(state: WorldState, c: CharacterData) -> bool:
	var conf := section("courtship")
	if c.age < int(conf.get("min_age", 18)) or c.age > int(conf.get("max_age", 48)):
		return false
	if state.is_player(c) or CourtSystem.is_kin(state, c) or c.retainer or c.is_visitor() or spouse_of(state, c) != null:
		return false
	for r in c.relationships_of_type(["late_spouse"]):
		var gone := state.get_departed(int(r["target"]))
		if gone and state.day() - gone.departed_day < int(conf.get("remarry_after_days", 80)):
			return false
	return true


static func _courtship(state: WorldState, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	var conf := section("courtship")
	var day := state.day()
	var singles: Array[CharacterData] = []
	for c in state.characters:
		if can_court(state, c):
			singles.append(c)
	var start := daily(float(conf.get("start_yearly", 0.35)))
	var wed := daily(float(conf.get("marry_yearly", 0.8)))
	for c in singles:
		if spouse_of(state, c) != null:
			continue  # married earlier today
		var lover := lover_of(state, c)
		if lover == null:
			var social := 1.0
			for t in c.traits:
				social *= float(GameData.trait_def(t).get("sociability", 1.0))
			if rng.randf() < start * social:
				var match_ := best_match(state, c, singles, rng)
				if match_:
					var r := c.get_relationship(match_.id)
					var fond := 50 + (20 if r.get("type", "") == "friend" else 0)
					c.remove_relationship(match_.id)
					match_.remove_relationship(c.id)
					c.add_relationship(match_.id, "lover", fond + rng.randi_range(0, 30))
					match_.add_relationship(c.id, "lover", fond + rng.randi_range(0, 30))
					c.courting_since = day
					match_.courting_since = day
		elif c.id < lover.id and can_court(state, lover) and day - maxi(c.courting_since, 0) >= int(conf.get("marry_after_days", 20)) and rng.randf() < wed:
			marry(state, c, lover, events)


## The best sweetheart for `c` among the free singles: of an age, not kin,
## liked, alike in temper and station. Null if no one suits.
static func best_match(state: WorldState, c: CharacterData, singles: Array[CharacterData], rng: RandomNumberGenerator) -> CharacterData:
	var gap := int(section("courtship").get("max_gap", 10))
	var best: CharacterData = null
	var best_score := 1.0
	for o in singles:
		if o == c or o.gender == c.gender or absi(o.age - c.age) > gap or lover_of(state, o) != null:
			continue
		if o.family_id == c.family_id or _related(c, o):
			continue
		var r := c.get_relationship(o.id)
		if r.get("type", "") == "rival":
			continue
		var score := rng.randf_range(0.0, 3.0)
		if r.get("type", "") == "friend":
			score += 2.0
		if absi(o.status_tier() - c.status_tier()) <= 1:
			score += 1.0
		if o.work_building_id >= 0 and o.work_building_id == c.work_building_id:
			score += 1.0
		for t in c.traits:
			if o.has_trait(t):
				score += 0.7
		if score > best_score:
			best_score = score
			best = o
	return best


static func _related(a: CharacterData, b: CharacterData) -> bool:
	var r := a.get_relationship(b.id)
	return not r.is_empty() and str(r["type"]) in KIN


## Makes two people husband and wife (from sweethearts, or a match).
static func link_spouses(state: WorldState, a: CharacterData, b: CharacterData) -> void:
	var fond_a := int(a.get_relationship(b.id).get("opinion", 60))
	var fond_b := int(b.get_relationship(a.id).get("opinion", 60))
	a.remove_relationship(b.id)
	b.remove_relationship(a.id)
	a.add_relationship(b.id, "spouse", mini(fond_a + 10, 100))
	b.add_relationship(a.id, "spouse", mini(fond_b + 10, 100))
	for p: CharacterData in [a, b]:
		p.courting_since = -1
		var old := lover_of(state, p)
		if old:
			old.remove_relationship(p.id)
			p.remove_relationship(old.id)
			old.courting_since = -1
	var year := state.current_year()
	var season := state.current_season()
	a.add_history(year, season, "family", "Married %s" % b.full_name())
	b.add_history(year, season, "family", "Married %s" % a.full_name())


## They marry and make one household: a widowed parent's home takes in the
## newcomer; otherwise a young couple takes an empty home if there is one,
## or the younger moves in with the elder's family.
static func marry(state: WorldState, a: CharacterData, b: CharacterData, events: Array[Dictionary]) -> void:
	link_spouses(state, a, b)
	var moved: Array[int] = []
	var fa := state.get_family(a.family_id)
	var fb := state.get_family(b.family_id)
	var a_keeps := fa != null and fa.head_id == a.id and fa.member_ids.size() > 1
	var b_keeps := fb != null and fb.head_id == b.id and fb.member_ids.size() > 1
	if a_keeps and (not b_keeps or fa.member_ids.size() >= fb.member_ids.size()):
		moved = join(state, b, fa)
	elif b_keeps:
		moved = join(state, a, fb)
	else:
		var home := _free_home(state, a)
		if home:
			moved = _found(state, a, b, home)
		else:
			var elder := a if a.age >= b.age else b
			moved = join(state, b if elder == a else a, state.get_family(elder.family_id))
	var text := "%s and %s are married." % [a.full_name(), b.full_name()]
	var notable := _notable(state, a) or _notable(state, b)
	if notable and state.house:
		state.house.log_event(state.day(), text, "marriage")
	events.append({"text": text if notable else "", "kind": "good", "character": a.id, "moved": moved})


## `c` (and their young children) join `fam` in its home. Returns who moved.
static func join(state: WorldState, c: CharacterData, fam: FamilyData) -> Array[int]:
	var moved: Array[int] = []
	if fam == null:
		return moved
	var head := state.get_character(fam.head_id)
	var home := fam.home_building_id if fam.home_building_id >= 0 else (head.home_building_id if head else -1)
	var going: Array[CharacterData] = [c]
	var old := state.get_family(c.family_id)
	if old and old.head_id == c.id:
		for r in state.living_ties(c, ["child"]):
			var kid: CharacterData = state.get_character(int(r["target"]))
			if kid and not kid.is_adult() and kid.family_id == c.family_id:
				going.append(kid)
	for p in going:
		_move_family(state, p, fam)
		if p.home_building_id != home:
			p.home_building_id = home
			moved.append(p.id)
	c.last_name = fam.name
	return moved


## A new household for the couple in `home`, named for the elder.
static func _found(state: WorldState, a: CharacterData, b: CharacterData, home: BuildingData) -> Array[int]:
	var elder := a if a.age >= b.age else b
	var from := state.get_family(elder.family_id)
	var fam := FamilyData.new()
	var next_id := 1
	for f in state.families:
		next_id = maxi(next_id, f.id + 1)
	fam.id = next_id
	fam.name = elder.last_name
	fam.background = from.background if from else "farming"
	fam.social_status = a.social_status if a.status_tier() >= b.status_tier() else b.social_status
	fam.home_building_id = home.id
	fam.head_id = elder.id
	state.add_family(fam)
	for p: CharacterData in [a, b]:
		_move_family(state, p, fam)
		p.home_building_id = home.id
		p.last_name = fam.name
	if state.territory:
		state.territory.home_since[home.id] = state.day()
	GrowthSystem.rename_home(state, home)
	return [a.id, b.id] as Array[int]


static func _move_family(state: WorldState, p: CharacterData, fam: FamilyData) -> void:
	var old := state.get_family(p.family_id)
	if old == fam:
		return
	if old:
		old.member_ids.erase(p.id)
		if old.head_id == p.id:
			old.head_id = _next_head(state, old)
	p.family_id = fam.id
	fam.member_ids.append(p.id)


## An empty home, nearest where `c` lives now.
static func _free_home(state: WorldState, c: CharacterData) -> BuildingData:
	var near := state.get_building(c.home_building_id)
	var origin := near.position if near else state.layout.square_center
	var best: BuildingData = null
	for b in GrowthSystem.empty_homes(state):
		if best == null or b.position.distance_to(origin) < best.position.distance_to(origin):
			best = b
	return best


# --- Births ------------------------------------------------------------------------------------

## Whether `mother` (married, of an age) may have a child today, and how
## likely it is.
static func birth_chance(state: WorldState, mother: CharacterData) -> float:
	var conf := section("births")
	var ages: Array = conf.get("mother_age", [18, 42])
	if mother.gender != "female" or mother.age < int(ages[0]) or mother.age > int(ages[1]):
		return 0.0
	var father := spouse_of(state, mother)
	if father == null:
		return 0.0
	var n := children_count(mother)
	if n >= int(conf.get("max_children", 7)):
		return 0.0
	if mother.last_birth_day >= 0 and state.day() - mother.last_birth_day < int(conf.get("spacing_days", 50)):
		return 0.0
	var yearly := float(conf.get("yearly", 0.38)) * pow(float(conf.get("by", 0.78)), n)
	for f in MoodSystem.happiness_factors(mother, state):
		if str(f["label"]) == "Crowded home":
			yearly *= float(conf.get("crowded", 0.35))
	if GrowthSystem.at_capacity(state):
		yearly *= float(conf.get("village_full", 0.3))
	return daily(yearly)


static func _births(state: WorldState, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	for mother in state.characters.duplicate():
		var p := birth_chance(state, mother)
		if p <= 0.0 or rng.randf() >= p:
			continue
		var father := spouse_of(state, mother)
		var baby := CharacterGenerator.newborn(state, mother, father, "birth_%d_%d" % [state.day(), mother.id])
		mother.last_birth_day = state.day()
		var text := "A %s, %s, was born to %s and %s." % ["son" if baby.gender == "male" else "daughter", baby.first_name, mother.full_name(), father.full_name()]
		var notable := _notable(state, mother) or _notable(state, father)
		if notable and state.house:
			state.house.log_event(state.day(), text, "birth")
		events.append({"text": text if notable else "", "kind": "good", "born": baby.id})


# --- Leaving -----------------------------------------------------------------------------------

## When more live here than the charter allows, young unmarried adults may
## go to seek their fortune, one at a time.
static func _leaving(state: WorldState, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	if state.territory == null or GrowthSystem.population(state) <= CharterSystem.max_population(state):
		return
	var conf := section("leaving")
	var chance := daily(float(conf.get("yearly", 0.5)))
	for c in state.characters.duplicate():
		if c.age < int(conf.get("min_age", 17)) or c.age > int(conf.get("max_age", 32)):
			continue
		if state.is_player(c) or CourtSystem.is_kin(state, c) or c.retainer or c.is_visitor() or spouse_of(state, c) != null or lover_of(state, c) != null:
			continue
		if not state.living_ties(c, ["child"]).is_empty():
			continue
		if rng.randf() < chance:
			leave(state, c, events)
			return
