class_name CharacterGenerator
extends RefCounted
## Procedurally generates the village's people from the world seed.
##
## Pipeline (each step uses its own seeded RNG stream, so the same seed always
## gives the same people):
##   1. Households from data/backgrounds.json (heads + spouses + required kids)
##   2. Optional children / elders added at random until the population target
##   3. Jobs for dependents (child, apprentice, farmhand...)
##   4. Homes and workplaces from the village layout
##   5. Personality traits and appearance (children resemble parents)
##   6. Talents: potential + current ability (see TalentRoller)
##   7. Family, friend, rival and romantic relationships
##   8. Life histories, including subtle hints of hidden talent
##   9. Starting mood, building names and positions

const BATTLE_PLACES := ["Greywater Ford", "Kellen's Pass", "the Ashen Moor", "Dunmoor Bridge", "Hollowmere", "the Thornwall", "Redfen Crossing", "Brackenridge"]
const HAMLETS := ["Lowmarsh", "Pellridge", "Coldbrook", "Ashgrove", "Hareby", "Wendlecombe", "Mossfold", "Tillingham"]
const SAINTS := ["Aldhelm", "Brigid", "Cuthbert", "Edith", "Oswin", "Hilda", "Benedict", "Etheldreda", "Swithun", "Werburgh"]

var state: WorldState
var rng_people: RandomNumberGenerator
var rng_looks: RandomNumberGenerator
var rng_talent: RandomNumberGenerator
var rng_social: RandomNumberGenerator
var rng_story: RandomNumberGenerator
## Separate stream so adding portrait-only data never changes other rolls.
var rng_figure: RandomNumberGenerator

var _next_character_id := 1
var _next_family_id := 1
var _used_full_names: Dictionary = {}
var _used_surnames: Dictionary = {}
## [{ family, template, head, spouse, children: Array, elder, child_slots: int, elder_slot: bool }]
var _households: Array[Dictionary] = []


func generate(world: WorldState) -> void:
	state = world
	var s := world.world_seed
	rng_people = Seeds.rng(s, "people")
	rng_looks = Seeds.rng(s, "looks")
	rng_talent = Seeds.rng(s, "talent")
	rng_social = Seeds.rng(s, "social")
	rng_story = Seeds.rng(s, "story")
	rng_figure = Seeds.rng(s, "figure")

	_create_households()
	_fill_population()
	_assign_dependent_jobs()
	_assign_buildings()
	_roll_personalities_and_looks()
	_roll_talents()
	_build_family_relationships()
	_build_social_relationships()
	_write_histories()
	_set_initial_mood()
	_name_buildings()
	_place_everyone_at_home()


# --- 1. Households ---------------------------------------------------------------

func _create_households() -> void:
	for tpl: Dictionary in GameData.households():
		for i in int(tpl.get("count", 1)):
			_create_household(tpl)


func _create_household(tpl: Dictionary) -> Dictionary:
	var bg := str(tpl.get("background", "farming"))
	var fam := FamilyData.new()
	fam.id = _next_family_id
	_next_family_id += 1
	fam.background = bg
	fam.name = _pick_surname(bg)
	fam.is_ruling = bool(tpl.get("ruling", false))
	state.add_family(fam)
	if fam.is_ruling:
		state.ruling_family_id = fam.id

	var head_job := str(tpl.get("head", "farmer"))
	var head_occ := GameData.occupation(head_job)
	var age_range: Array = head_occ.get("age", [20, 60])
	var children_range: Array = tpl.get("children", [0, 0])
	var min_age := int(age_range[0])
	if int(children_range[0]) > 0:
		min_age = maxi(min_age, 26)
	var head := _new_person(fam, head_job, _random_gender(), rng_people.randi_range(min_age, maxi(min_age, int(age_range[1]))))
	fam.head_id = head.id
	var head_status := str(head_occ.get("status", "commoner"))
	fam.social_status = head_status if head_status != "inherit" else "commoner"
	head.social_status = fam.social_status

	var household := {
		"family": fam, "template": tpl, "head": head, "spouse": null,
		"children": [], "elder": null, "child_slots": 0, "elder_slot": false,
	}
	_households.append(household)

	if Seeds.chance(rng_people, float(tpl.get("spouse_chance", 0.0))):
		var spouse_job := str(tpl.get("spouse", ""))
		if spouse_job.is_empty():
			spouse_job = GameData.spouse_job(bg)
		if spouse_job == "same":
			spouse_job = head_job
		var spouse_gender := "female" if head.gender == "male" else "male"
		var spouse_age := clampi(head.age + rng_people.randi_range(-8, 4), 18, 80)
		household["spouse"] = _new_person(fam, spouse_job, spouse_gender, spouse_age)

	for i in int(children_range[0]):
		_add_child(household)
	household["child_slots"] = maxi(0, int(children_range[1]) - int(children_range[0]))
	household["elder_slot"] = Seeds.chance(rng_people, float(tpl.get("elder_chance", 0.0)))
	return household


func _new_person(fam: FamilyData, occupation_id: String, gender: String, age: int) -> CharacterData:
	var c := CharacterData.new()
	c.id = _next_character_id
	_next_character_id += 1
	c.gender = gender
	c.age = age
	c.occupation_id = occupation_id
	c.family_id = fam.id
	c.last_name = fam.name
	c.first_name = _pick_first_name(gender, fam)
	c.social_status = _status_for(occupation_id, fam)
	fam.member_ids.append(c.id)
	state.add_character(c)
	_used_full_names[c.full_name()] = true
	return c


## A person's station is their household's, unless their own job ranks higher.
func _status_for(occupation_id: String, fam: FamilyData) -> String:
	var occ_status := str(GameData.occupation(occupation_id).get("status", "inherit"))
	if occ_status == "inherit" or occupation_id.is_empty():
		return fam.social_status
	var occ_tier := int(GameData.status_def(occ_status).get("tier", 0))
	var fam_tier := int(GameData.status_def(fam.social_status).get("tier", 0))
	return occ_status if occ_tier > fam_tier else fam.social_status


func _random_gender() -> String:
	return "male" if rng_people.randf() < 0.5 else "female"


func _pick_surname(bg: String) -> String:
	var pool_key := str(GameData.background(bg).get("surnames", "common"))
	var pool: Array = GameData.names().get(pool_key, ["Smith"])
	for attempt in 20:
		var n := str(Seeds.pick(rng_people, pool))
		if not _used_surnames.has(n):
			_used_surnames[n] = true
			return n
	return str(Seeds.pick(rng_people, pool))


func _pick_first_name(gender: String, fam: FamilyData) -> String:
	var pool: Array = GameData.names().get(gender, ["Robin"])
	var taken_in_family := {}
	for member_id in fam.member_ids:
		var m := state.get_character(member_id)
		if m:
			taken_in_family[m.first_name] = true
	for attempt in 30:
		var n := str(Seeds.pick(rng_people, pool))
		if not taken_in_family.has(n) and not _used_full_names.has("%s %s" % [n, fam.name]):
			return n
	return str(Seeds.pick(rng_people, pool))


func _parents_of(household: Dictionary) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	if household["head"] != null:
		out.append(household["head"])
	if household["spouse"] != null:
		out.append(household["spouse"])
	return out


func _add_child(household: Dictionary) -> bool:
	var parents := _parents_of(household)
	var youngest := 999
	for p in parents:
		youngest = mini(youngest, p.age)
	var max_age := mini(youngest - 17, 28)
	if max_age < 3:
		return false
	# Infants (under 3) are not simulated yet: they would need to be carried.
	var age := rng_people.randi_range(3, max_age)
	if age > 20:
		age = rng_people.randi_range(3, max_age)  # most grown children have moved out
	var child := _new_person(household["family"], "", _random_gender(), age)
	household["children"].append(child)
	return true


func _add_elder(household: Dictionary) -> bool:
	if household["elder"] != null:
		return false
	var head: CharacterData = household["head"]
	var tpl: Dictionary = household["template"]
	var age := clampi(head.age + rng_people.randi_range(20, 30), 58, 90)
	var job := str(tpl.get("elder_job", "elder"))
	household["elder"] = _new_person(household["family"], job, _random_gender(), age)
	return true


# --- 2. Population target -------------------------------------------------------

func _fill_population() -> void:
	var target := GameData.population_target()
	var slots: Array[Dictionary] = []
	for h in _households:
		for i in int(h["child_slots"]):
			slots.append({"household": h, "kind": "child"})
		if h["elder_slot"]:
			slots.append({"household": h, "kind": "elder"})
	Seeds.shuffle(rng_people, slots)
	for slot in slots:
		if state.characters.size() >= target:
			break
		if slot["kind"] == "child":
			_add_child(slot["household"])
		else:
			_add_elder(slot["household"])
	# Still short? Add hired hands who lodge at the farms.
	var farm_tpl := {"background": "farming", "head": "farmhand", "spouse_chance": 0.0, "home": "farmhouse", "children": [0, 0]}
	while state.characters.size() < target:
		_create_household(farm_tpl)


# --- 3. Jobs for dependents -------------------------------------------------------

func _assign_dependent_jobs() -> void:
	for h in _households:
		var fam: FamilyData = h["family"]
		var bg := GameData.background(fam.background)
		for child: CharacterData in h["children"]:
			if child.age < 12:
				child.occupation_id = str(bg.get("young_job", "child"))
			elif child.age < 16:
				child.occupation_id = str(bg.get("teen_job", "child"))
			else:
				child.occupation_id = str(Seeds.pick(rng_people, bg.get("adult_jobs", ["farmhand"])))
			child.social_status = _status_for(child.occupation_id, fam)


# --- 4. Homes & workplaces ----------------------------------------------------------

func _assign_buildings() -> void:
	var layout := state.layout
	var households_in: Dictionary = {}
	for h in _households:
		var fam: FamilyData = h["family"]
		var wanted := str(h["template"].get("home", "cottage"))
		var home := _choose_home(wanted, households_in)
		if home == null:
			continue
		households_in[home.id] = int(households_in.get(home.id, 0)) + 1
		fam.home_building_id = home.id
		for member_id in fam.member_ids:
			state.get_character(member_id).home_building_id = home.id
	for h in _households:
		var head: CharacterData = h["head"]
		for c in _members(h):
			c.work_building_id = _choose_workplace(c, head)


func _choose_home(type: String, households_in: Dictionary) -> BuildingData:
	var private_types := ["cottage", "farmhouse"]
	var candidates := state.layout.buildings_of_type(type)
	if candidates.is_empty():
		candidates = state.layout.buildings_of_type("cottage")
		candidates.append_array(state.layout.buildings_of_type("farmhouse"))
	if candidates.is_empty():
		return null
	if private_types.has(type):
		for b in candidates:
			if int(households_in.get(b.id, 0)) == 0:
				return b
	var best: BuildingData = candidates[0]
	for b in candidates:
		if int(households_in.get(b.id, 0)) < int(households_in.get(best.id, 0)):
			best = b
	return best


func _choose_workplace(c: CharacterData, head: CharacterData) -> int:
	var occ := c.occupation()
	var wp := str(occ.get("workplace", ""))
	if c.occupation_id == "apprentice":
		if head != null and head != c and head.work_building_id >= 0:
			return head.work_building_id
		return _nearest_building_of("workshop", c.home_building_id)
	if wp.is_empty() or wp == "market":
		return -1
	var home := state.get_building(c.home_building_id)
	if wp == "farmhouse" and home != null and home.type == "farmhouse":
		return home.id
	return _nearest_building_of(wp, c.home_building_id)


func _nearest_building_of(type: String, from_building_id: int) -> int:
	var origin := Vector3.ZERO
	var from := state.get_building(from_building_id)
	if from:
		origin = from.position
	var best_id := -1
	var best_d := INF
	for b in state.layout.buildings_of_type(type):
		var d := origin.distance_to(b.position)
		if d < best_d:
			best_d = d
			best_id = b.id
	return best_id


func _members(h: Dictionary) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	if h["elder"] != null:
		out.append(h["elder"])
	out.append(h["head"])
	if h["spouse"] != null:
		out.append(h["spouse"])
	for child: CharacterData in h["children"]:
		out.append(child)
	return out


# --- 5. Personality & appearance ------------------------------------------------------

func _roll_personalities_and_looks() -> void:
	var ap := GameData.appearance()
	for h in _households:
		var family_skin := str(Seeds.pick(rng_looks, ap["skin_tones"]))
		var family_hair := str(Seeds.pick(rng_looks, ap["hair_colors"]))
		var parents := _parents_of(h)
		for c in _members(h):
			var is_child := (h["children"] as Array).has(c)
			_roll_traits(c, parents if is_child else [])
			var skin := family_skin
			var hair := family_hair
			if c == h["spouse"]:
				skin = str(Seeds.pick(rng_looks, ap["skin_tones"]))
				hair = str(Seeds.pick(rng_looks, ap["hair_colors"]))
			elif is_child and parents.size() > 0:
				var p: CharacterData = parents[rng_looks.randi_range(0, parents.size() - 1)]
				if not p.appearance.is_empty():
					skin = str(p.appearance.get("skin", skin))
					hair = str(p.appearance.get("hair_base", hair))
			c.appearance = _roll_appearance(c, skin, hair)
			c.appearance["face"] = FaceFeatures.roll_child(rng_looks, c, parents) if is_child else FaceFeatures.roll(rng_looks, c)
			c.appearance["figure"] = FaceFeatures.roll_figure(rng_figure, c)


func _roll_traits(c: CharacterData, parents: Array) -> void:
	var all_traits: Array = GameData.traits().keys()
	var count_range: Array = GameData.load_file("traits").get("traits_per_character", [2, 3])
	var count := rng_looks.randi_range(int(count_range[0]), int(count_range[1]))
	# A quarter of children inherit one trait from a parent.
	if parents.size() > 0 and rng_looks.randf() < 0.25:
		var p: CharacterData = parents[rng_looks.randi_range(0, parents.size() - 1)]
		if not p.traits.is_empty():
			c.traits.append(p.traits[rng_looks.randi_range(0, p.traits.size() - 1)])
	var guard := 0
	while c.traits.size() < count and guard < 50:
		guard += 1
		var t := str(Seeds.pick(rng_looks, all_traits))
		var opposite := str(GameData.trait_def(t).get("opposite", ""))
		if c.traits.has(t) or (not opposite.is_empty() and c.traits.has(opposite)):
			continue
		c.traits.append(t)


func _roll_appearance(c: CharacterData, skin: String, hair: String) -> Dictionary:
	var ap := GameData.appearance()
	var outfits: Dictionary = ap["outfits"]
	var palette: Dictionary = outfits.get(c.social_status, outfits["commoner"])
	var hair_color := hair
	if c.age >= 55 and rng_looks.randf() < 0.4 + (c.age - 55) * 0.03:
		hair_color = str(Seeds.pick(rng_looks, ap["elder_hair_colors"]))
	var styles: Array = ap["hair_styles"].duplicate()
	if c.gender == "female" or c.age < 25:
		styles.erase("bald")
	var height := rng_looks.randf_range(0.94, 1.08) if c.gender == "male" else rng_looks.randf_range(0.9, 1.02)
	if c.age < 16:
		height *= clampf(0.42 + c.age * 0.037, 0.42, 1.0)
	return {
		"skin": skin,
		"hair_base": hair,
		"hair": hair_color,
		"hair_style": str(Seeds.pick(rng_looks, styles)),
		"eyes": str(Seeds.pick(rng_looks, ap["eye_colors"])),
		"height": snappedf(height, 0.001),
		"build": snappedf(rng_looks.randf_range(0.85, 1.2), 0.001),
		"beard": c.gender == "male" and c.age >= 20 and rng_looks.randf() < 0.45,
		"primary": str(Seeds.pick(rng_looks, palette["primary"])),
		"secondary": str(Seeds.pick(rng_looks, palette["secondary"])),
	}


# --- 6. Talent ------------------------------------------------------------------------

func _roll_talents() -> void:
	# Adults first so children can inherit odds from their parents.
	for h in _households:
		var fam: FamilyData = h["family"]
		for c in _members(h):
			if not (h["children"] as Array).has(c):
				TalentRoller.roll_attributes(rng_talent, c, fam.background, [])
	for h in _households:
		var fam: FamilyData = h["family"]
		var parents := _parents_of(h)
		for child: CharacterData in h["children"]:
			TalentRoller.roll_attributes(rng_talent, child, fam.background, parents)


# --- 7. Relationships ------------------------------------------------------------------

func _link(a: CharacterData, b: CharacterData, type_a_to_b: String, type_b_to_a: String, opinion_a: int, opinion_b: int) -> void:
	a.add_relationship(b.id, type_a_to_b, opinion_a)
	b.add_relationship(a.id, type_b_to_a, opinion_b)


func _build_family_relationships() -> void:
	for h in _households:
		var head: CharacterData = h["head"]
		var spouse: CharacterData = h["spouse"]
		var children: Array = h["children"]
		var elder: CharacterData = h["elder"]
		if spouse:
			var happy := rng_social.randf() > 0.15
			_link(head, spouse, "spouse", "spouse",
				rng_social.randi_range(30, 95) if happy else rng_social.randi_range(-30, 20),
				rng_social.randi_range(30, 95) if happy else rng_social.randi_range(-30, 20))
		for p in _parents_of(h):
			for child: CharacterData in children:
				_link(p, child, "child", "parent", rng_social.randi_range(40, 95), rng_social.randi_range(20, 95))
		for i in children.size():
			for j in range(i + 1, children.size()):
				var close := rng_social.randf() > 0.12
				var lo := 10 if close else -45
				var hi := 90 if close else 0
				_link(children[i], children[j], "sibling", "sibling", rng_social.randi_range(lo, hi), rng_social.randi_range(lo, hi))
		if elder:
			_link(elder, head, "child", "parent", rng_social.randi_range(30, 90), rng_social.randi_range(20, 90))
			for child: CharacterData in children:
				_link(elder, child, "grandchild", "grandparent", rng_social.randi_range(45, 95), rng_social.randi_range(30, 95))


static func _trait_product(c: CharacterData, key: String) -> float:
	var v := 1.0
	for t in c.traits:
		v *= float(GameData.trait_def(t).get(key, 1.0))
	return v


func _shared_and_clashing(a: CharacterData, b: CharacterData) -> Vector2i:
	var shared := 0
	var clashing := 0
	for t in a.traits:
		if b.traits.has(t):
			shared += 1
		var opposite := str(GameData.trait_def(t).get("opposite", ""))
		if not opposite.is_empty() and b.traits.has(opposite):
			clashing += 1
	return Vector2i(shared, clashing)


func _ages_compatible(a: CharacterData, b: CharacterData) -> bool:
	if a.age < 16 or b.age < 16:
		return a.age < 16 and b.age < 16 and absi(a.age - b.age) <= 4
	return absi(a.age - b.age) <= 16


func _home_distance(a: CharacterData, b: CharacterData) -> float:
	var ha := state.get_building(a.home_building_id)
	var hb := state.get_building(b.home_building_id)
	if ha == null or hb == null:
		return 999.0
	return ha.position.distance_to(hb.position)


func _build_social_relationships() -> void:
	var people := state.characters
	# Friends
	for c in people:
		if c.age < 5:
			continue
		var desired := clampi(roundi(0.8 + 2.2 * _trait_product(c, "sociability") + rng_social.randf_range(-0.6, 0.8)), 0, 5)
		var have := c.relationships_of_type(["friend"]).size()
		if have >= desired:
			continue
		var scored: Array[Dictionary] = []
		for o in people:
			if o == c or o.age < 5 or not c.get_relationship(o.id).is_empty() or not _ages_compatible(c, o):
				continue
			if o.relationships_of_type(["friend"]).size() >= 6:
				continue
			var tc := _shared_and_clashing(c, o)
			var score := rng_social.randf_range(0.0, 3.0)
			if c.work_building_id >= 0 and c.work_building_id == o.work_building_id:
				score += 3.0
			if _home_distance(c, o) < 30.0:
				score += 2.0
			if absi(c.status_tier() - o.status_tier()) <= 1:
				score += 1.0
			score += tc.x - tc.y * 2.0
			score *= _trait_product(o, "sociability")
			if score > 2.5:
				scored.append({"o": o, "score": score})
		scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["score"] > y["score"])
		for i in mini(desired - have, scored.size()):
			_link(c, scored[i]["o"], "friend", "friend", rng_social.randi_range(25, 80), rng_social.randi_range(25, 80))
	# Rivals
	for c in people:
		if c.age < 14 or rng_social.randf() > 0.22 * _trait_product(c, "rivalry"):
			continue
		var best: CharacterData = null
		var best_score := 2.0
		for o in people:
			if o == c or o.age < 14 or not c.get_relationship(o.id).is_empty() or absi(o.age - c.age) > 25:
				continue
			var score := rng_social.randf_range(0.0, 2.0)
			if o.occupation_id == c.occupation_id:
				score += 3.0
			if c.work_building_id >= 0 and o.work_building_id == c.work_building_id:
				score += 2.0
			score += _shared_and_clashing(c, o).y * 2.0
			if c.has_trait("ambitious") and o.has_trait("ambitious"):
				score += 2.0
			if score > best_score:
				best_score = score
				best = o
		if best:
			_link(c, best, "rival", "rival", rng_social.randi_range(-75, -20), rng_social.randi_range(-75, -15))
	# Romance (adults only)
	for c in people:
		if c.age < 17 or c.age > 50 or not c.relationships_of_type(["spouse", "lover"]).is_empty():
			continue
		if rng_social.randf() > 0.2:
			continue
		var best: CharacterData = null
		var best_score := 1.0
		for o in people:
			if o == c or o.gender == c.gender or o.age < 17 or absi(o.age - c.age) > 8:
				continue
			if not o.relationships_of_type(["spouse", "lover"]).is_empty():
				continue
			var existing := c.get_relationship(o.id)
			if not existing.is_empty() and existing["type"] != "friend":
				continue
			var score := rng_social.randf_range(0.0, 3.0) + (2.0 if existing.get("type", "") == "friend" else 0.0)
			score += _shared_and_clashing(c, o).x
			if score > best_score:
				best_score = score
				best = o
		if best:
			c.remove_relationship(best.id)
			best.remove_relationship(c.id)
			_link(c, best, "lover", "lover", rng_social.randi_range(55, 95), rng_social.randi_range(40, 95))


# --- 8. Histories ------------------------------------------------------------------------

func _event_year(c: CharacterData, at_age: int) -> int:
	return Calendar.start_year() - (c.age - clampi(at_age, 0, c.age))


func _season() -> String:
	return str(Seeds.pick(rng_story, Calendar.seasons()))


func _pronoun(c: CharacterData) -> String:
	return "his" if c.gender == "male" else "her"


func _write_histories() -> void:
	var village := state.village_name
	var ruling := state.ruling_family()
	var house_name := ruling.display_name() if ruling else "the lord"
	var lord := state.get_character(ruling.head_id) if ruling else null
	for h in _households:
		var head: CharacterData = h["head"]
		var spouse: CharacterData = h["spouse"]
		for c in _members(h):
			# Birth
			if c == spouse and rng_story.randf() < 0.5:
				c.add_history(_event_year(c, 0), _season(), "life", "Born in the hamlet of %s" % Seeds.pick(rng_story, HAMLETS))
			else:
				c.add_history(_event_year(c, 0), _season(), "life", "Born in %s" % village)
			_write_career(c, house_name, lord)
		if spouse:
			var oldest_child := 0
			for child: CharacterData in h["children"]:
				oldest_child = maxi(oldest_child, child.age)
			var max_years := mini(head.age, spouse.age) - 16
			var years := clampi(oldest_child + rng_story.randi_range(1, 3), 1, maxi(1, max_years))
			var year := Calendar.start_year() - years
			head.add_history(year, _season(), "family", "Married %s" % spouse.full_name())
			spouse.add_history(year, _season(), "family", "Married %s" % head.full_name())
		for child: CharacterData in h["children"]:
			for p in _parents_of(h):
				var kind := "son" if child.gender == "male" else "daughter"
				p.add_history(Calendar.start_year() - child.age, _season(), "family", "Welcomed a %s, %s" % [kind, child.first_name])
	for c in state.characters:
		_write_achievements(c)
		_write_hidden_talent_hints(c)
		c.history.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["year"]) < int(b["year"]))


func _write_career(c: CharacterData, house_name: String, lord: CharacterData) -> void:
	var occ := c.occupation()
	var occ_age: Array = occ.get("age", [16, 60])
	if c.age < 12:
		return
	var start_age := clampi(rng_story.randi_range(int(occ_age[0]), int(occ_age[0]) + 6), 12, c.age)
	var y := _event_year(c, start_age)
	var workplace := state.get_building(c.work_building_id)
	var workplace_name := workplace.name if workplace else "the village"
	match c.occupation_id:
		"lord":
			c.add_history(_event_year(c, rng_story.randi_range(20, maxi(20, c.age - 1))), _season(), "appointment", "Inherited the lordship of %s" % state.village_name)
		"lady":
			pass
		"noble_scion":
			if c.age >= 8:
				c.add_history(_event_year(c, 8), _season(), "career", "Began lessons in letters, riding and courtly manners")
		"steward":
			c.add_history(y, _season(), "appointment", "Appointed Steward of %s" % house_name)
		"guard_captain":
			c.add_history(y, _season(), "appointment", "Appointed Captain of the Guard of %s" % state.village_name)
			_write_military(c)
		"knight":
			var by := lord.full_name() if lord and lord != c else "the old lord"
			c.add_history(y, _season(), "appointment", "Knighted by %s" % by)
			_write_military(c)
		"soldier":
			c.add_history(y, _season(), "military", "Took up the spear in the service of %s" % house_name)
			_write_military(c)
		"priest":
			c.add_history(y, _season(), "appointment", "Ordained and given charge of the chapel of %s" % state.village_name)
		"apprentice":
			c.add_history(y, _season(), "career", "Apprenticed at %s" % workplace_name)
		"innkeeper":
			c.add_history(y, _season(), "career", "Took over %s" % workplace_name)
		"blacksmith":
			c.add_history(y, _season(), "career", "Lit the forge of %s for the first time" % workplace_name)
		"farmer":
			c.add_history(y, _season(), "career", "Took on the family fields")
		"merchant":
			c.add_history(y, _season(), "career", "Set up a stall in the market square")
		"dowager", "elder":
			c.add_history(_event_year(c, rng_story.randi_range(55, maxi(55, c.age))), _season(), "life", "Handed %s work to the next generation" % _pronoun(c))
		"child":
			pass
		_:
			c.add_history(y, _season(), "career", "Began work as a %s" % c.occupation_name().to_lower())


func _write_military(c: CharacterData) -> void:
	var templates := [
		"Fought at the Battle of %s",
		"Held the line against raiders at %s",
		"Captured a bandit chief near %s",
		"Wounded in the skirmish at %s",
		"Escorted the tax wagons through %s",
	]
	var count := rng_story.randi_range(1, 3) if c.age >= 22 else 1
	for i in count:
		var at_age := rng_story.randi_range(17, maxi(17, c.age))
		c.add_history(_event_year(c, at_age), _season(), "military", str(Seeds.pick(rng_story, templates)) % Seeds.pick(rng_story, BATTLE_PLACES))


func _write_achievements(c: CharacterData) -> void:
	if c.age < 14:
		return
	var options: Array[Dictionary] = []
	if c.get_current("combat") >= 40:
		options.append({"cat": "achievement", "text": "Won the archery contest at the %s fair" % _season()})
	if c.get_current("intelligence") >= 45:
		options.append({"cat": "achievement", "text": "Taught %sself to read and write" % ("him" if c.gender == "male" else "her")})
	if c.get_current("administration") >= 45:
		options.append({"cat": "achievement", "text": "Kept the accounts of a whole season without a single error"})
	if c.get_current("leadership") >= 40:
		options.append({"cat": "achievement", "text": "Led the villagers in rebuilding the bridge after the floods"})
	if c.get_current("politics") >= 40:
		options.append({"cat": "achievement", "text": "Settled a bitter feud between two families"})
	Seeds.shuffle(rng_story, options)
	for i in mini(2, options.size()):
		if rng_story.randf() < 0.6:
			c.add_history(_event_year(c, rng_story.randi_range(mini(16, c.age), c.age)), _season(), options[i]["cat"], options[i]["text"])


## Untapped talent leaks into village gossip. Players who read histories get
## a clue about who might be worth appraising.
func _write_hidden_talent_hints(c: CharacterData) -> void:
	var hints := {
		"leadership": "The other children always seem to follow %s lead",
		"combat": "Bested a seasoned soldier at wrestling, to everyone's surprise",
		"intelligence": "Asks questions even the priest cannot answer",
		"politics": "Talked a merchant into a bargain no one thought possible",
		"administration": "Somehow remembers every debt owed in the village",
		"ambition": "Swears to one day see the royal capital",
	}
	for attr_id: String in GameData.attribute_ids():
		var potential := c.get_potential(attr_id)
		if potential < Appraisal.exceptional_threshold():
			continue
		if c.get_current(attr_id) > potential * 0.45 or rng_story.randf() > 0.55:
			continue
		var text: String = hints[attr_id]
		if text.contains("%s"):
			text = text % _pronoun(c)
		c.add_history(_event_year(c, rng_story.randi_range(mini(6, c.age), c.age)), _season(), "rumor", text)


# --- 9. Mood, names and placement ------------------------------------------------------

func _set_initial_mood() -> void:
	for c in state.characters:
		c.stress = rng_social.randf_range(5.0, 35.0)
		c.happiness = 50.0
		c.happiness = clampf(MoodSystem.happiness_target(c, state) + rng_social.randf_range(-8.0, 8.0), 5.0, 98.0)
		c.loyalty = clampf(MoodSystem.loyalty_target(c, state) + rng_social.randf_range(-6.0, 6.0), 5.0, 98.0)


func _name_buildings() -> void:
	var tavern_names: Array = GameData.names().get("tavern_names", ["The Tavern"])
	for b in state.layout.buildings:
		var residents := state.residents_of(b.id)
		var workers := state.workers_of(b.id)
		var owner := residents[0].last_name if not residents.is_empty() else (workers[0].last_name if not workers.is_empty() else "")
		match b.type:
			"manor":
				var ruling := state.ruling_family()
				b.name = "%s Manor" % (ruling.name if ruling else state.village_name)
			"tavern":
				b.name = str(Seeds.pick(rng_story, tavern_names))
			"chapel":
				b.name = "Chapel of Saint %s" % Seeds.pick(rng_story, SAINTS)
			"barracks":
				b.name = "%s Barracks" % state.village_name
			"storehouse":
				b.name = "%s Granary" % state.village_name
			"mill":
				b.name = "%s Mill" % (owner if owner else state.village_name)
			"cottage":
				b.name = "%s Cottage" % owner if owner else "Empty Cottage"
			"farmhouse":
				b.name = "%s Farm" % owner if owner else "Abandoned Farm"
			_:
				if owner:
					b.name = "%s %s" % [owner, b.type_name()]


func _place_everyone_at_home() -> void:
	for c in state.characters:
		var home := state.get_building(c.home_building_id)
		if home:
			c.position = home.door_position()
			c.inside_building_id = home.id
		c.activity = "sleep"
		c.activity_text = "Asleep"
