class_name TalentRoller
extends RefCounted
## Rolls hidden potential and current ability.
##
## POTENTIAL: a weighted pick of a rank from data/ranks.json, then a value
## inside that rank. "Affinity" (from family background, traits and parents)
## multiplies each rank's weight by affinity^affinity_exponent, so a military
## family makes high Combat more likely, but nothing is ever guaranteed.
##
## CURRENT: how much of that potential life has let them develop. It depends
## on age and on opportunity (social status / occupation). That is why a
## peasant child can show "Leadership: 12 / 126 (S+)".


## Rank weights after applying an affinity. Exposed for tests and tooling.
static func rank_weights(affinity: float = 1.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for r: Dictionary in GameData.ranks():
		out.append(float(r["weight"]) * pow(maxf(affinity, 0.01), float(r.get("affinity_exponent", 0.0))))
	return out


static func roll_potential(rng: RandomNumberGenerator, affinity: float = 1.0) -> int:
	var ranks := GameData.ranks()
	var weights := rank_weights(affinity)
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	var chosen := ranks.size() - 1
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			chosen = i
			break
	var rank: Dictionary = ranks[chosen]
	var lo := int(rank["min"])
	var hi := int(rank["max"])
	# Within a rank, values near the floor are more common, more so for high ranks.
	var t := pow(rng.randf(), 1.0 + 0.15 * chosen)
	return lo + roundi(t * (hi - lo))


## Fraction of potential a person of this age has typically developed.
static func age_development(age: int, attr_id: String) -> float:
	var curve: Array = [[0, 0.03], [6, 0.08], [12, 0.2], [16, 0.35], [20, 0.55], [26, 0.7], [35, 0.82], [50, 0.88], [60, 0.88], [75, 0.8], [95, 0.7]]
	if attr_id == "combat":
		curve = [[0, 0.02], [6, 0.06], [12, 0.18], [16, 0.35], [20, 0.6], [26, 0.78], [35, 0.85], [45, 0.82], [60, 0.7], [75, 0.45], [95, 0.3]]
	elif attr_id == "ambition":
		curve = [[0, 0.4], [12, 0.5], [20, 0.75], [35, 0.85], [60, 0.75], [95, 0.6]]
	for i in range(1, curve.size()):
		var a: Array = curve[i - 1]
		var b: Array = curve[i]
		if age <= int(b[0]):
			var t := inverse_lerp(float(a[0]), float(b[0]), float(age))
			return lerpf(float(a[1]), float(b[1]), clampf(t, 0.0, 1.0))
	return float(curve[-1][1])


## How much opportunity this person has had to train an attribute (0..1).
static func training_factor(status_id: String, occupation_id: String, attr_id: String) -> float:
	var occ := GameData.occupation(occupation_id)
	var occ_training: Dictionary = occ.get("training", {})
	if occ_training.has(attr_id):
		return float(occ_training[attr_id])
	var status_training: Dictionary = GameData.status_def(status_id).get("training", {})
	return float(status_training.get(attr_id, 0.3))


static func roll_current(rng: RandomNumberGenerator, potential: int, age: int, attr_id: String,
		training: float, trait_multiplier: float = 1.0) -> int:
	var dev := age_development(age, attr_id) * training * trait_multiplier * rng.randf_range(0.75, 1.15)
	return clampi(roundi(potential * clampf(dev, 0.0, 1.0)), 0, potential)


## Combines every affinity source for one attribute.
static func affinity_for(attr_id: String, background_id: String, trait_ids: Array, parents: Array) -> float:
	var affinity := float(GameData.background(background_id).get("affinities", {}).get(attr_id, 1.0))
	for t: String in trait_ids:
		affinity *= float(GameData.trait_def(t).get("affinities", {}).get(attr_id, 1.0))
	affinity *= inheritance_affinity(attr_id, parents)
	return affinity


## Talented parents raise the odds for their children (never a guarantee).
static func inheritance_affinity(attr_id: String, parents: Array) -> float:
	var best := 1.0
	var tiers: Array = GameData.rank_config().get("inheritance", {}).get("tiers", [])
	for p: CharacterData in parents:
		if p == null:
			continue
		var potential := p.get_potential(attr_id)
		for tier: Dictionary in tiers:
			if potential >= int(tier["min_potential"]):
				best = maxf(best, float(tier["affinity"]))
				break
	return best


## Rolls all attributes for a character in place.
static func roll_attributes(rng: RandomNumberGenerator, c: CharacterData, background_id: String, parents: Array) -> void:
	var trait_mult := 1.0
	if c.has_trait("diligent"):
		trait_mult = 1.08
	elif c.has_trait("lazy"):
		trait_mult = 0.88
	for attr_id: String in GameData.attribute_ids():
		var affinity := affinity_for(attr_id, background_id, Array(c.traits), parents)
		var potential := roll_potential(rng, affinity)
		var training := training_factor(c.social_status, c.occupation_id, attr_id)
		var current := roll_current(rng, potential, c.age, attr_id, training, trait_mult)
		c.set_attribute(attr_id, current, potential)
