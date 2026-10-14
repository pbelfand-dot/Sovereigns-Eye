class_name Appraisal
extends RefCounted
## The Appraisal skill: turns a character's hidden numbers into what the
## player is allowed to see.
##
## Ranks come from data/ranks.json. The appraise() function takes an
## appraiser level so future systems (a weaker appraisal power, fog of war on
## distant lords, magic that hides stats) can reveal less without changing any
## UI code: the UI only ever reads an appraisal report.

## Full insight. Phase 1 always appraises at this level.
const LEVEL_FULL := 100
## Below this level potential is hidden (only current ability is visible).
const LEVEL_SEES_POTENTIAL := 50


# --- Ranks -------------------------------------------------------------------

static func rank_for(value: int) -> Dictionary:
	var result: Dictionary = {}
	for r: Dictionary in GameData.ranks():
		if value >= int(r["min"]):
			result = r
	return result


static func rank_id(value: int) -> String:
	return str(rank_for(value).get("id", "?"))


static func rank_index(value: int) -> int:
	var ranks := GameData.ranks()
	var idx := 0
	for i in ranks.size():
		if value >= int(ranks[i]["min"]):
			idx = i
	return idx


static func rank_color(value: int) -> Color:
	return Color.from_string(str(rank_for(value).get("color", "#ffffff")), Color.WHITE)


static func rank_color_by_id(id: String) -> Color:
	for r: Dictionary in GameData.ranks():
		if r["id"] == id:
			return Color.from_string(str(r["color"]), Color.WHITE)
	return Color.WHITE


static func rank_title(value: int) -> String:
	return str(rank_for(value).get("title", ""))


static func exceptional_threshold() -> int:
	return int(GameData.rank_config().get("exceptional_threshold", 100))


static func notable_threshold() -> int:
	return int(GameData.rank_config().get("notable_threshold", 80))


# --- Formatting -----------------------------------------------------------------

## "Leadership: 12 / 126 (S+)"
static func format_attribute(character: CharacterData, attr_id: String) -> String:
	var def := GameData.attribute_def(attr_id)
	var potential := character.get_potential(attr_id)
	return "%s: %d / %d (%s)" % [
		def.get("name", attr_id.capitalize()),
		character.get_current(attr_id),
		potential,
		rank_id(potential),
	]


## True for anyone with at least one S-rank (or better) potential.
static func is_exceptional(character: CharacterData) -> bool:
	return character.best_potential() >= exceptional_threshold()


static func is_notable(character: CharacterData) -> bool:
	return character.best_potential() >= notable_threshold()


## Sum of potentials, used to sort the ledger by overall promise.
static func talent_score(character: CharacterData) -> int:
	var total := 0
	for attr_id: String in GameData.attribute_ids():
		total += character.get_potential(attr_id)
	return total


# --- The skill itself ------------------------------------------------------------

## Produces what the appraiser can see about a character.
## {
##   "character_id": int,
##   "level": int,
##   "potential_visible": bool,
##   "attributes": [{ id, name, current, potential (-1 if hidden), rank, color, text }],
##   "best_attribute": String, "best_rank": String, "exceptional": bool
## }
static func appraise(character: CharacterData, level: int = LEVEL_FULL) -> Dictionary:
	var sees_potential := level >= LEVEL_SEES_POTENTIAL
	var rows: Array[Dictionary] = []
	for attr_id: String in GameData.attribute_ids():
		var def := GameData.attribute_def(attr_id)
		var potential := character.get_potential(attr_id)
		rows.append({
			"id": attr_id,
			"name": def.get("name", attr_id.capitalize()),
			"description": def.get("description", ""),
			"current": character.get_current(attr_id),
			"potential": potential if sees_potential else -1,
			"rank": rank_id(potential) if sees_potential else "?",
			"rank_title": rank_title(potential) if sees_potential else "",
			"color": rank_color(potential) if sees_potential else Color(0.7, 0.7, 0.7),
			"text": format_attribute(character, attr_id) if sees_potential else "%s: %d / ?" % [def.get("name", attr_id), character.get_current(attr_id)],
		})
	var best := character.best_attribute()
	return {
		"character_id": character.id,
		"level": level,
		"potential_visible": sees_potential,
		"attributes": rows,
		"best_attribute": best if sees_potential else "",
		"best_rank": rank_id(character.get_potential(best)) if sees_potential else "?",
		"exceptional": is_exceptional(character) if sees_potential else false,
	}
