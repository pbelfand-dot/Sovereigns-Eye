class_name RealmData
extends RefCounted
## The noble houses around the village (Phase 4.2): their names and seats,
## how renowned they are, and what they think of the player's house
## (standing, -100..100). They send suitors for the house's unmarried
## (MatchSystem). The wider realm (Phase 5+) grows from here.

## [{id, name, seat, renown, standing, family}] ("family": the FamilyData
## their visitors belong to, -1 until one comes).
var houses: Array[Dictionary] = []
## The day the next suitor is due (MatchSystem), -1 until it's set.
var next_suitor_day: int = -1


func get_house(house_id: int) -> Dictionary:
	for h in houses:
		if int(h["id"]) == house_id:
			return h
	return {}


## "House Ashcombe of Thornwick".
func house_title(house_id: int) -> String:
	var h := get_house(house_id)
	return "House %s of %s" % [h["name"], h["seat"]] if not h.is_empty() else "a noble house"


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
	return r


func to_dict() -> Dictionary:
	return {"houses": houses.duplicate(true), "next_suitor_day": next_suitor_day}


static func from_dict(d: Dictionary) -> RealmData:
	var r := RealmData.new()
	for h: Dictionary in d.get("houses", []):
		r.houses.append({"id": int(h.get("id", 0)), "name": str(h.get("name", "")), "seat": str(h.get("seat", "")),
			"renown": int(h.get("renown", 0)), "standing": int(h.get("standing", 0)), "family": int(h.get("family", -1))})
	r.next_suitor_day = int(d.get("next_suitor_day", -1))
	return r
