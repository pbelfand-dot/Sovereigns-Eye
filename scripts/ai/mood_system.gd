class_name MoodSystem
extends RefCounted
## Lightweight happiness / loyalty / stress model.
##
## Each day, happiness and loyalty drift toward a TARGET built from readable
## factors ("+6 Gregarious", "-10 Talents go unused"...). The character card
## shows these factors, so the player can see why someone is unhappy, which
## matters later for recruitment and politics. Stress moves hourly with what
## the person is doing.

const STRESS_PER_HOUR := {
	"work": 0.8, "leisure": -1.2, "sleep": -1.0, "home": -0.6, "play": -1.0,
}
const HAPPINESS_PER_HOUR := {
	"work": -0.05, "leisure": 0.15, "play": 0.15,
}


static func _friends(c: CharacterData) -> int:
	return c.relationships_of_type(["friend"]).size()


## [{ "label": String, "value": float }]
static func happiness_factors(c: CharacterData, world: WorldState) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"label": "Baseline", "value": 50.0}]
	var status_bonus := float(GameData.status_def(c.social_status).get("happiness", 0))
	if status_bonus != 0.0:
		out.append({"label": "%s station" % c.status_name(), "value": status_bonus})
	for t in c.traits:
		var v := float(GameData.trait_def(t).get("happiness", 0))
		if v != 0.0:
			out.append({"label": str(GameData.trait_def(t).get("name", t)), "value": v})
	var friends := _friends(c)
	if friends > 0:
		out.append({"label": "Friends in the village (%d)" % friends, "value": minf(friends * 2.0, 8.0)})
	elif c.age >= 8:
		out.append({"label": "Lonely", "value": -4.0})
	if not c.relationships_of_type(["lover"]).is_empty():
		out.append({"label": "In love", "value": 5.0})
	for r in c.relationships_of_type(["spouse"]):
		if int(r["opinion"]) >= 50:
			out.append({"label": "Happy marriage", "value": 4.0})
		elif int(r["opinion"]) < 0:
			out.append({"label": "Unhappy marriage", "value": -6.0})
	var rivals := c.relationships_of_type(["rival"]).size()
	if rivals > 0:
		out.append({"label": "Rivals (%d)" % rivals, "value": -3.0 * rivals})
	var wasted := wasted_talent_penalty(c)
	if wasted < 0.0:
		out.append({"label": "Talents go unused", "value": wasted})
	if c.stress > 60.0:
		out.append({"label": "Overworked", "value": -(c.stress - 60.0) / 3.0})
	if world != null and c.home_building_id >= 0:
		var residents := world.residents_of(c.home_building_id).size()
		if residents > 7:
			out.append({"label": "Crowded home", "value": -3.0})
	return out


## Gifted, driven people stuck in humble work grow restless. This is the hook
## that makes recruiting them (Phase 2) matter.
static func wasted_talent_penalty(c: CharacterData) -> float:
	if c.age < 14 or c.status_tier() > 2:
		return 0.0
	if c.get_potential("ambition") < 50:
		return 0.0
	var best := c.best_potential()
	if best >= Appraisal.exceptional_threshold():
		return -10.0
	if best >= Appraisal.notable_threshold():
		return -6.0
	return 0.0


static func happiness_target(c: CharacterData, world: WorldState) -> float:
	var total := 0.0
	for f in happiness_factors(c, world):
		total += float(f["value"])
	return clampf(total, 0.0, 100.0)


static func loyalty_factors(c: CharacterData, world: WorldState) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"label": "Baseline", "value": 40.0}]
	if world != null and c.family_id == world.ruling_family_id:
		out.append({"label": "Member of the ruling house", "value": 40.0})
	var status_bonus := float(GameData.status_def(c.social_status).get("loyalty", 0))
	if status_bonus != 0.0:
		out.append({"label": "%s station" % c.status_name(), "value": status_bonus})
	for t in c.traits:
		var v := float(GameData.trait_def(t).get("loyalty", 0))
		if v != 0.0:
			out.append({"label": str(GameData.trait_def(t).get("name", t)), "value": v})
	var mood := (c.happiness - 50.0) * 0.4
	if absf(mood) >= 1.0:
		out.append({"label": "Contentment" if mood > 0 else "Discontent", "value": mood})
	if wasted_talent_penalty(c) < 0.0 and c.has_trait("ambitious"):
		out.append({"label": "Feels overlooked", "value": -5.0})
	return out


static func loyalty_target(c: CharacterData, world: WorldState) -> float:
	var total := 0.0
	for f in loyalty_factors(c, world):
		total += float(f["value"])
	return clampf(total, 0.0, 100.0)


## Runs once per in-game day for every character.
static func daily_update(c: CharacterData, world: WorldState, rng: RandomNumberGenerator) -> void:
	c.happiness = clampf(c.happiness + (happiness_target(c, world) - c.happiness) * 0.25 + rng.randf_range(-2.0, 2.0), 0.0, 100.0)
	c.loyalty = clampf(c.loyalty + (loyalty_target(c, world) - c.loyalty) * 0.1 + rng.randf_range(-1.0, 1.0), 0.0, 100.0)


## Applies `hours` of an activity's effect on stress and happiness.
static func activity_update(c: CharacterData, activity: String, hours: float) -> void:
	var stress_rate := float(STRESS_PER_HOUR.get(activity, 0.0))
	if stress_rate > 0.0:
		for t in c.traits:
			stress_rate *= float(GameData.trait_def(t).get("stress", 1.0))
	c.stress = clampf(c.stress + stress_rate * hours, 0.0, 100.0)
	c.happiness = clampf(c.happiness + float(HAPPINESS_PER_HOUR.get(activity, 0.0)) * hours, 0.0, 100.0)


# --- Labels ----------------------------------------------------------------------

static func happiness_label(v: float) -> String:
	if v >= 80: return "Joyful"
	if v >= 62: return "Content"
	if v >= 45: return "Getting by"
	if v >= 28: return "Unhappy"
	return "Miserable"


static func loyalty_label(v: float) -> String:
	if v >= 80: return "Devoted"
	if v >= 60: return "Loyal"
	if v >= 40: return "Dutiful"
	if v >= 25: return "Wavering"
	return "Disloyal"


static func stress_label(v: float) -> String:
	if v >= 75: return "Breaking point"
	if v >= 55: return "Strained"
	if v >= 30: return "Busy"
	return "Relaxed"


static func ambition_label(v: int) -> String:
	if v >= 100: return "Burning ambition"
	if v >= 65: return "Driven"
	if v >= 35: return "Hopeful"
	return "Content with little"
