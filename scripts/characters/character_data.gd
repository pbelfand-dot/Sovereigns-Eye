class_name CharacterData
extends RefCounted
## Pure data for one person in the world. No nodes, no meshes.
##
## A character exists whether or not a 3D body is currently spawned for them,
## which is what lets the game scale to hundreds of notable characters later
## (most of them will live off-screen). The NPC node in the world only reads
## and writes this object.

const ADULT_AGE := 16

var id: int = -1
var first_name: String = ""
var last_name: String = ""
var gender: String = "male"  # "male" / "female"
var age: int = 20
var occupation_id: String = ""
var social_status: String = "commoner"
var family_id: int = -1
var home_building_id: int = -1
var work_building_id: int = -1

## attr_id -> {"current": int, "potential": int}. Use the helpers below to
## change values: they enforce current <= potential.
var attributes: Dictionary = {}
var traits: Array[String] = []

var happiness: float = 60.0
var loyalty: float = 50.0
var stress: float = 20.0

## [{ "target": int, "type": String, "opinion": int }]
## Types: spouse, parent, child, sibling, grandparent, grandchild, friend, rival, lover
var relationships: Array[Dictionary] = []
## [{ "year": int, "season": String, "category": String, "text": String }]
## Categories: life, career, military, appointment, family, achievement
var history: Array[Dictionary] = []
## Visual description (colors, hair style, height...). Models read this; it never
## references a mesh, so any future art pipeline can interpret it.
var appearance: Dictionary = {}

## True once the player has used the Sovereign's Eye on this person.
var appraised: bool = false
## True once the heir has spoken with them (the Eye needs a first meeting).
var met: bool = false
## Pinned by the player after a reveal ("Remember"), for the ledger.
var remembered: bool = false

# --- Court (Phase 2) ---------------------------------------------------------
## Sworn to the player's house.
var retainer: bool = false
## Office held in the house ("steward", "marshal"...), "" for none.
var office: String = ""
## Attribute the player asked them to train ("" = their greatest talent).
var focus: String = ""
## What they think of the player, -100..100.
var player_opinion: float = 0.0
## attr_id -> fractional training progress toward the next point.
var training_progress: Dictionary = {}
## Day index of the last conversation with the player (-1 = never).
var last_talk_day: int = -1
## Status and workplace before joining the house (restored on dismissal).
var former_status: String = ""
var former_work: int = -1
var joined_day: int = -1
## Motives they've told the heir about (Recruitment.SPEAKING_MOTIVES ids).
var known_motives: Array[String] = []
## The terms they joined on: {wage, home, position, focus, office,
## workplace, appeal} (see Recruitment). {} for none.
var terms: Dictionary = {}
## Daily wage agreed when they joined (-1 = the standard wage).
var agreed_wage: int = -1
## A title granted by the house ("squire"), "" for none.
var title: String = ""

# --- Live world state (saved so the village resumes exactly) ---------------
var position: Vector3 = Vector3.ZERO
var facing: float = 0.0
## Building the character is currently inside (-1 = outdoors / visible).
var inside_building_id: int = -1
var activity: String = ""
var activity_text: String = ""


# --- Identity ----------------------------------------------------------------

func full_name() -> String:
	return "%s %s" % [first_name, last_name]


func is_adult() -> bool:
	return age >= ADULT_AGE


func is_knight() -> bool:
	return social_status == "knight"


## Name with a knightly title when they have one ("Sir Aldric Hunt").
func display_name() -> String:
	if is_knight():
		return "%s %s" % ["Dame" if gender == "female" else "Sir", full_name()]
	if title == "squire":
		return "Squire %s" % full_name()
	return full_name()


func occupation() -> Dictionary:
	return GameData.occupation(occupation_id)


func occupation_name() -> String:
	var occ := occupation()
	var gendered_key := "name_female" if gender == "female" else "name_male"
	return str(occ.get(gendered_key, occ.get("name", occupation_id.capitalize())))


## Outfit style from the occupation, adjusted for the wearer: noblemen wear
## a fine doublet, noblewomen a gown, whichever title they hold.
func outfit() -> String:
	var o := str(occupation().get("outfit", "tunic"))
	if o == "gown" and gender == "male":
		return "fine"
	if o == "fine" and gender == "female":
		return "gown"
	return o


func status_name() -> String:
	return str(GameData.status_def(social_status).get("name", social_status.capitalize()))


func status_tier() -> int:
	return int(GameData.status_def(social_status).get("tier", 0))


# --- Attributes -------------------------------------------------------------

func get_current(attr_id: String) -> int:
	return int(attributes.get(attr_id, {}).get("current", 0))


func get_potential(attr_id: String) -> int:
	return int(attributes.get(attr_id, {}).get("potential", 0))


## Sets both values at once. Current is clamped so it never exceeds potential.
func set_attribute(attr_id: String, current: int, potential: int) -> void:
	potential = maxi(0, potential)
	attributes[attr_id] = {"current": clampi(current, 0, potential), "potential": potential}


func set_current(attr_id: String, value: int) -> void:
	set_attribute(attr_id, value, get_potential(attr_id))


## Grows current ability toward potential. Returns the amount actually gained.
## (Hook for future training, schooling and battle experience.)
func train(attr_id: String, amount: int) -> int:
	var before := get_current(attr_id)
	set_current(attr_id, before + amount)
	return get_current(attr_id) - before


## Raises the ceiling itself (rare items, blessings, future upgrade systems).
func raise_potential(attr_id: String, amount: int) -> void:
	set_attribute(attr_id, get_current(attr_id), get_potential(attr_id) + amount)


## The attribute with the highest potential.
func best_attribute() -> String:
	var best := ""
	var best_value := -1
	for attr_id: String in GameData.attribute_ids():
		var p := get_potential(attr_id)
		if p > best_value:
			best_value = p
			best = attr_id
	return best


func best_potential() -> int:
	return get_potential(best_attribute())


# --- Relationships ------------------------------------------------------------

func get_relationship(target_id: int) -> Dictionary:
	for r: Dictionary in relationships:
		if int(r["target"]) == target_id:
			return r
	return {}


## Adds a relationship, or upgrades the type if one already exists
## (family ties outrank friendship).
func add_relationship(target_id: int, type: String, opinion: int) -> void:
	if target_id == id:
		return
	var existing := get_relationship(target_id)
	if existing.is_empty():
		relationships.append({"target": target_id, "type": type, "opinion": clampi(opinion, -100, 100)})
		return
	if _relationship_priority(type) > _relationship_priority(str(existing["type"])):
		existing["type"] = type
		existing["opinion"] = clampi(opinion, -100, 100)


func remove_relationship(target_id: int) -> void:
	for i in range(relationships.size() - 1, -1, -1):
		if int(relationships[i]["target"]) == target_id:
			relationships.remove_at(i)


func relationships_of_type(types: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in relationships:
		if types.has(r["type"]):
			out.append(r)
	return out


static func _relationship_priority(type: String) -> int:
	match type:
		"spouse":
			return 9
		"parent", "child":
			return 8
		"sibling":
			return 7
		"grandparent", "grandchild":
			return 6
		"lover":
			return 5
		"rival":
			return 3
		"friend":
			return 2
	return 0


func add_history(year: int, season: String, category: String, text: String) -> void:
	history.append({"year": year, "season": season, "category": category, "text": text})


func has_trait(trait_id: String) -> bool:
	return traits.has(trait_id)


# --- Serialization -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"first_name": first_name,
		"last_name": last_name,
		"gender": gender,
		"age": age,
		"occupation": occupation_id,
		"status": social_status,
		"family": family_id,
		"home": home_building_id,
		"work": work_building_id,
		"attributes": attributes.duplicate(true),
		"traits": Array(traits),
		"happiness": snappedf(happiness, 0.01),
		"loyalty": snappedf(loyalty, 0.01),
		"stress": snappedf(stress, 0.01),
		"relationships": relationships.duplicate(true),
		"history": history.duplicate(true),
		"appearance": appearance.duplicate(true),
		"appraised": appraised,
		"met": met,
		"remembered": remembered,
		"position": [snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01)],
		"facing": snappedf(facing, 0.001),
		"inside": inside_building_id,
		"activity": activity,
		"activity_text": activity_text,
		"retainer": retainer,
		"office": office,
		"focus": focus,
		"player_opinion": snappedf(player_opinion, 0.01),
		"training_progress": _snapped_progress(),
		"last_talk_day": last_talk_day,
		"former_status": former_status,
		"former_work": former_work,
		"joined_day": joined_day,
		"known_motives": Array(known_motives),
		"terms": terms.duplicate(true),
		"agreed_wage": agreed_wage,
		"title": title,
	}


func _snapped_progress() -> Dictionary:
	var out := {}
	for k: String in training_progress:
		out[k] = snappedf(float(training_progress[k]), 0.0001)
	return out


## Builds a character from saved data. JSON turns every number into a float,
## so ints are cast back explicitly.
static func from_dict(d: Dictionary) -> CharacterData:
	var c := CharacterData.new()
	c.id = int(d.get("id", -1))
	c.first_name = str(d.get("first_name", ""))
	c.last_name = str(d.get("last_name", ""))
	c.gender = str(d.get("gender", "male"))
	c.age = int(d.get("age", 20))
	c.occupation_id = str(d.get("occupation", ""))
	c.social_status = str(d.get("status", "commoner"))
	c.family_id = int(d.get("family", -1))
	c.home_building_id = int(d.get("home", -1))
	c.work_building_id = int(d.get("work", -1))
	var attrs: Dictionary = d.get("attributes", {})
	for attr_id: String in attrs:
		var a: Dictionary = attrs[attr_id]
		c.set_attribute(attr_id, int(a.get("current", 0)), int(a.get("potential", 0)))
	for t: Variant in d.get("traits", []):
		c.traits.append(str(t))
	c.happiness = float(d.get("happiness", 60.0))
	c.loyalty = float(d.get("loyalty", 50.0))
	c.stress = float(d.get("stress", 20.0))
	for r: Dictionary in d.get("relationships", []):
		c.relationships.append({"target": int(r["target"]), "type": str(r["type"]), "opinion": int(r["opinion"])})
	for h: Dictionary in d.get("history", []):
		c.history.append({"year": int(h["year"]), "season": str(h.get("season", "")), "category": str(h["category"]), "text": str(h["text"])})
	c.appearance = _clean_appearance(d.get("appearance", {}))
	c.appraised = bool(d.get("appraised", false))
	c.met = bool(d.get("met", c.appraised))
	c.remembered = bool(d.get("remembered", false))
	var p: Array = d.get("position", [0, 0, 0])
	c.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	c.facing = float(d.get("facing", 0.0))
	c.inside_building_id = int(d.get("inside", -1))
	c.activity = str(d.get("activity", ""))
	c.activity_text = str(d.get("activity_text", ""))
	c.retainer = bool(d.get("retainer", false))
	c.office = str(d.get("office", ""))
	c.focus = str(d.get("focus", ""))
	c.player_opinion = float(d.get("player_opinion", 0.0))
	var progress: Dictionary = d.get("training_progress", {})
	for k: String in progress:
		c.training_progress[k] = float(progress[k])
	c.last_talk_day = int(d.get("last_talk_day", -1))
	c.former_status = str(d.get("former_status", ""))
	c.former_work = int(d.get("former_work", -1))
	c.joined_day = int(d.get("joined_day", -1))
	for m: Variant in d.get("known_motives", []):
		c.known_motives.append(str(m))
	c.terms = _clean_terms(d.get("terms", {}))
	c.agreed_wage = int(d.get("agreed_wage", -1))
	c.title = str(d.get("title", ""))
	return c


## Terms come back from JSON with float numbers.
static func _clean_terms(src: Dictionary) -> Dictionary:
	var out := {}
	for k: String in src:
		var v: Variant = src[k]
		out[k] = int(v) if v is float else v
	return out


static func _clean_appearance(src: Dictionary) -> Dictionary:
	var out := src.duplicate(true)
	for key: String in ["height", "build"]:
		if out.has(key):
			out[key] = float(out[key])
	if out.get("face") is Dictionary:
		var face: Dictionary = out["face"]
		for key: String in face:
			if typeof(face[key]) == TYPE_FLOAT or typeof(face[key]) == TYPE_INT:
				face[key] = float(face[key])
	return out
