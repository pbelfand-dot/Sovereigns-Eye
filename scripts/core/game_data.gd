class_name GameData
extends RefCounted
## Read-only access to the design data in res://data/*.json.
##
## Everything tunable (ranks, occupations, traits, names, buildings...) lives in
## JSON so designers can rebalance without touching code. Files are parsed once
## and cached. All accessors are static, so any script (including headless
## tests) can use them without an autoload.

const DATA_DIR := "res://data/"

static var _cache: Dictionary = {}


static func load_file(file_id: String) -> Dictionary:
	if _cache.has(file_id):
		return _cache[file_id]
	var path := DATA_DIR + file_id + ".json"
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("GameData: could not read %s" % path)
		_cache[file_id] = {}
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: %s is not a JSON object" % path)
		parsed = {}
	_cache[file_id] = parsed
	return parsed


## Drops the cache so edited JSON is re-read (handy while tuning).
static func reload() -> void:
	_cache.clear()


# --- Ranks & attributes ------------------------------------------------------

static func ranks() -> Array:
	return load_file("ranks").get("ranks", [])


static func rank_config() -> Dictionary:
	return load_file("ranks")


static func attributes() -> Array:
	return load_file("attributes").get("attributes", [])


static func attribute_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for a: Dictionary in attributes():
		ids.append(a["id"])
	return ids


static func attribute_def(attr_id: String) -> Dictionary:
	for a: Dictionary in attributes():
		if a["id"] == attr_id:
			return a
	return {}


# --- Society ----------------------------------------------------------------

static func statuses() -> Array:
	return load_file("society").get("statuses", [])


static func status_def(status_id: String) -> Dictionary:
	for s: Dictionary in statuses():
		if s["id"] == status_id:
			return s
	return {}


static func calendar() -> Dictionary:
	return load_file("society").get("calendar", {})


static func occupations() -> Dictionary:
	return load_file("occupations").get("occupations", {})


static func occupation(occ_id: String) -> Dictionary:
	return occupations().get(occ_id, {})


static func backgrounds() -> Dictionary:
	return load_file("backgrounds").get("backgrounds", {})


static func background(bg_id: String) -> Dictionary:
	return backgrounds().get(bg_id, {})


static func households() -> Array:
	return load_file("backgrounds").get("households", [])


static func spouse_job(bg_id: String) -> String:
	return str(load_file("backgrounds").get("spouse_jobs", {}).get(bg_id, "farmer"))


static func population_target() -> int:
	return int(load_file("backgrounds").get("population_target", 50))


static func traits() -> Dictionary:
	return load_file("traits").get("traits", {})


static func trait_def(trait_id: String) -> Dictionary:
	return traits().get(trait_id, {})


static func schedule(schedule_id: String) -> Array:
	return load_file("schedules").get("schedules", {}).get(schedule_id, [])


# --- Names, appearance, buildings --------------------------------------------

static func names() -> Dictionary:
	return load_file("names")


static func appearance() -> Dictionary:
	return load_file("appearance")


static func building_types() -> Dictionary:
	return load_file("buildings").get("types", {})


static func building_type(type_id: String) -> Dictionary:
	return building_types().get(type_id, {})


static func village_plan() -> Dictionary:
	var plan: Dictionary = load_file("buildings").get("village_plan", {}).duplicate()
	plan.erase("_comment")
	return plan
