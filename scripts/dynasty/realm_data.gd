class_name RealmData
extends RefCounted
## The noble houses around the village (Phase 4.2): their names and seats,
## how renowned they are, and what they think of the player's house
## (standing, -100..100: their regard). They send suitors for the house's
## unmarried (MatchSystem). Phase 5.2 puts them on a map (Realm): where each
## seat lies and how many days' ride, what the house is known for, its lord
## or lady, the young of the house you've met there (households), and the
## heir's journey under way (trip).

## [{id, name, seat, renown, standing, family, pos [x, y], days, known_for,
## head, head_gender, visited}] ("family": the FamilyData their visitors
## belong to, -1 until one comes; "visited": the last day the heir arrived
## there, -1 if never).
var houses: Array[Dictionary] = []
## The day the next suitor is due (MatchSystem), -1 until it's set.
var next_suitor_day: int = -1
## house id -> the house's young (CharacterData, never in WorldState.characters;
## ids below -2000), made the first time the heir visits.
var households: Dictionary = {}
## house id -> the day its young were last brought up to date (ages).
var household_day: Dictionary = {}
var next_member_id: int = -2000
## The heir's journey, or {}: {kind ("visit"), house, depart, arrive, back,
## stage ("out", "there", "back"), done [deeds at the seat], betrothed
## [{member, to}]}.
var trip: Dictionary = {}


func get_house(house_id: int) -> Dictionary:
	for h in houses:
		if int(h["id"]) == house_id:
			return h
	return {}


## "House Ashcombe of Thornwick".
func house_title(house_id: int) -> String:
	var h := get_house(house_id)
	return "House %s of %s" % [h["name"], h["seat"]] if not h.is_empty() else "a noble house"


## The young of a house the heir has met (empty before a visit).
func household(house_id: int) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for c: CharacterData in households.get(house_id, []):
		out.append(c)
	return out


func get_member(member_id: int) -> CharacterData:
	for list: Array in households.values():
		for c: CharacterData in list:
			if c.id == member_id:
				return c
	return null


func house_of_member(member_id: int) -> int:
	for house_id: int in households:
		for c: CharacterData in households[house_id]:
			if c.id == member_id:
				return house_id
	return -1


## Houses named for the surnames not used in the village, with seats named
## like villages; deterministic for the seed.
static func generate(world_seed: int, taken_names: Array) -> RealmData:
	var r := RealmData.new()
	var rng := Seeds.rng(world_seed, "realm")
	var conf: Dictionary = GameData.load_file("matches").get("houses", {})
	var n := GameData.names()
	var pool: Array = (n.get("noble_houses", []) as Array).filter(func(s: String) -> bool: return not taken_names.has(s))
	Seeds.shuffle(rng, pool)
	var renown: Array = conf.get("renown", [12, 70])
	var seats := {}
	for i in mini(int(conf.get("count", 4)), pool.size()):
		var seat := ""
		for attempt in 10:
			seat = "%s%s" % [Seeds.pick(rng, n.get("village_prefixes", ["Ash"])), Seeds.pick(rng, n.get("village_suffixes", ["ford"]))]
			if not seats.has(seat):
				break
		seats[seat] = true
		r.houses.append({"id": i + 1, "name": str(pool[i]), "seat": seat,
			"renown": rng.randi_range(int(renown[0]), int(renown[1])), "standing": 0, "family": -1})
	r.place(world_seed)
	return r


## Puts the houses on the map (Phase 5.2): their seats round the compass,
## a few days' ride out, what each is known for, and its lord or lady. Only
## fills what's missing (an older save keeps everything else); the same for
## the seed whatever is missing.
func place(world_seed: int) -> void:
	var rng := Seeds.rng(world_seed, "realm_map")
	var conf: Dictionary = GameData.load_file("realm")
	var m: Dictionary = conf.get("map", {})
	var ride := float(m.get("day_ride", 64))
	var days_range: Array = m.get("seat_days", [2, 4])
	var center := Vector2(float(m.get("width", 1000)) * 0.5, float(m.get("height", 640)) * 0.5)
	var kinds: Array = (conf.get("houses", {}).get("known_for", {"arms": {}}) as Dictionary).keys()
	kinds.sort()
	Seeds.shuffle(rng, kinds)
	var names := GameData.names()
	var turn := rng.randf() * TAU
	for i in houses.size():
		var h := houses[i]
		var angle := turn + TAU * i / houses.size() + rng.randf_range(-0.3, 0.3) * TAU / houses.size()
		var days := rng.randi_range(int(days_range[0]), int(days_range[1]))
		var gender := "male" if rng.randf() < 0.7 else "female"
		var first := str(Seeds.pick(rng, names.get(gender, ["Robin"])))
		var pos := center + Vector2(cos(angle), -sin(angle)) * days * ride
		if not h.has("pos"):
			h["pos"] = [float(roundi(pos.x)), float(roundi(pos.y))]
			h["days"] = days
		if not h.has("known_for"):
			h["known_for"] = str(kinds[i % kinds.size()])
		if not h.has("head"):
			h["head"] = "%s %s %s" % ["Lord" if gender == "male" else "Lady", first, h["name"]]
			h["head_gender"] = gender
		if not h.has("visited"):
			h["visited"] = -1


func to_dict() -> Dictionary:
	var young := {}
	for house_id: int in households:
		var list := []
		for c: CharacterData in households[house_id]:
			list.append(c.to_dict())
		young[str(house_id)] = list
	var aged := {}
	for house_id: int in household_day:
		aged[str(house_id)] = household_day[house_id]
	return {"houses": houses.duplicate(true), "next_suitor_day": next_suitor_day, "households": young,
		"household_day": aged, "next_member_id": next_member_id, "trip": trip.duplicate(true)}


static func from_dict(d: Dictionary) -> RealmData:
	var r := RealmData.new()
	for h: Dictionary in d.get("houses", []):
		var house := {"id": int(h.get("id", 0)), "name": str(h.get("name", "")), "seat": str(h.get("seat", "")),
			"renown": int(h.get("renown", 0)), "standing": int(h.get("standing", 0)), "family": int(h.get("family", -1))}
		if h.has("pos"):
			var p: Array = h["pos"]
			house["pos"] = [float(p[0]), float(p[1])]
			house["days"] = int(h.get("days", 2))
		if h.has("known_for"):
			house["known_for"] = str(h["known_for"])
		if h.has("head"):
			house["head"] = str(h["head"])
			house["head_gender"] = str(h.get("head_gender", "male"))
		if h.has("visited"):
			house["visited"] = int(h["visited"])
		r.houses.append(house)
	r.next_suitor_day = int(d.get("next_suitor_day", -1))
	var young: Dictionary = d.get("households", {})
	for key: String in young:
		var list: Array[CharacterData] = []
		for c: Dictionary in young[key]:
			list.append(CharacterData.from_dict(c))
		r.households[int(key)] = list
	var aged: Dictionary = d.get("household_day", {})
	for key: String in aged:
		r.household_day[int(key)] = int(aged[key])
	r.next_member_id = int(d.get("next_member_id", -2000))
	r.trip = (d.get("trip", {}) as Dictionary).duplicate(true)
	for k: String in ["house", "depart", "arrive", "back"]:
		if r.trip.has(k):
			r.trip[k] = int(r.trip[k])
	var betrothed: Array = r.trip.get("betrothed", [])
	for b: Dictionary in betrothed:
		b["member"] = int(b["member"])
		b["to"] = int(b["to"])
	return r
