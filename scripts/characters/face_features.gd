class_name FaceFeatures
extends RefCounted
## Facial features of a character (face shape, eyes, nose, brows...), stored in
## their appearance data so a portrait never changes between sessions. Children
## inherit some features from a parent, so families look related.

const SHAPES := ["oval", "round", "square", "long", "heart"]
const NOSES := ["straight", "button", "long", "broad", "hooked"]
const EYES := ["almond", "round", "narrow"]
const BEARDS := ["full", "short", "goatee", "mustache", "stubble"]
## Features a child may take from one parent.
const INHERITED := ["shape", "nose", "eye_shape", "ears", "brow"]


static func roll(rng: RandomNumberGenerator, c: CharacterData) -> Dictionary:
	var military := c.occupation_id in ["soldier", "knight", "guard_captain", "general"]
	return {
		"shape": SHAPES[rng.randi_range(0, SHAPES.size() - 1)],
		"width": snappedf(rng.randf_range(0.9, 1.08), 0.001),
		"eye_shape": EYES[rng.randi_range(0, EYES.size() - 1)],
		"eye_spacing": snappedf(rng.randf_range(0.92, 1.08), 0.001),
		"eye_size": snappedf(rng.randf_range(0.9, 1.12), 0.001),
		"brow": snappedf(rng.randf_range(0.7, 1.3), 0.001),
		"nose": NOSES[rng.randi_range(0, NOSES.size() - 1)],
		"mouth": snappedf(rng.randf_range(0.85, 1.15), 0.001),
		"lips": snappedf(rng.randf_range(0.8, 1.25), 0.001),
		"ears": snappedf(rng.randf_range(0.85, 1.15), 0.001),
		"freckles": rng.randf() < 0.18,
		"mole": rng.randf() < 0.12,
		"scar": rng.randf() < (0.35 if military else 0.05),
		"beard_style": BEARDS[rng.randi_range(0, BEARDS.size() - 1)],
	}


## Rolls a child's face, copying some features from a random parent.
static func roll_child(rng: RandomNumberGenerator, c: CharacterData, parents: Array) -> Dictionary:
	var face := roll(rng, c)
	var with_faces: Array = []
	for p: CharacterData in parents:
		if p and p.appearance.has("face"):
			with_faces.append(p)
	if with_faces.is_empty():
		return face
	var parent: CharacterData = with_faces[rng.randi_range(0, with_faces.size() - 1)]
	var parent_face: Dictionary = parent.appearance["face"]
	for key: String in INHERITED:
		if rng.randf() < 0.6 and parent_face.has(key):
			face[key] = parent_face[key]
	return face


## The character's stored face, or a stable one derived from their identity
## (for characters saved before faces existed).
static func for_character(c: CharacterData) -> Dictionary:
	var stored: Variant = c.appearance.get("face", null)
	if stored is Dictionary and not (stored as Dictionary).is_empty():
		return stored
	var rng := RandomNumberGenerator.new()
	rng.seed = ("face:%d:%s" % [c.id, c.full_name()]).hash()
	return roll(rng, c)


## Body shape for portraits ("curvy", "broad"...), weighted by
## data/art_style.json portrait.figure. Rolled for everyone at generation so
## it never changes, but only described for adults (see figure_text()).
static func roll_figure(rng: RandomNumberGenerator, c: CharacterData) -> String:
	var options: Array = _figure_options(c.gender)
	if options.is_empty():
		return "average"
	var total := 0.0
	for o: Dictionary in options:
		total += float(o.get("weight", 1.0))
	var r := rng.randf() * total
	for o: Dictionary in options:
		r -= float(o.get("weight", 1.0))
		if r <= 0.0:
			return str(o["id"])
	return str(options[-1]["id"])


## The stored figure, or a stable one derived from identity (older saves).
static func figure_for(c: CharacterData) -> String:
	var stored := str(c.appearance.get("figure", ""))
	if not stored.is_empty():
		return stored
	var rng := RandomNumberGenerator.new()
	rng.seed = ("figure:%d:%s" % [c.id, c.full_name()]).hash()
	return roll_figure(rng, c)


## Portrait wording for the character's figure. Always empty for anyone
## younger than portrait.figure.min_age (18): children and teenagers are
## never described by body shape.
static func figure_text(c: CharacterData) -> String:
	var cfg: Dictionary = GameData.load_file("art_style").get("portrait", {}).get("figure", {})
	if c.age < int(cfg.get("min_age", 18)):
		return ""
	var id := figure_for(c)
	for o: Dictionary in _figure_options(c.gender):
		if str(o["id"]) == id:
			return str(o.get("text", ""))
	return ""


static func _figure_options(gender: String) -> Array:
	var cfg: Dictionary = GameData.load_file("art_style").get("portrait", {}).get("figure", {})
	return cfg.get("female" if gender == "female" else "male", [])

