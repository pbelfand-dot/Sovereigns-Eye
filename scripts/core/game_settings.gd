class_name GameSettings
extends RefCounted
## Player preferences kept in user://settings.cfg (shared with the audio
## volumes): accessibility switches and which Eye reveals have been seen.
## Values are cached; every change is written straight away.

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"accessibility/reduced_motion": false,
	"accessibility/reduce_flashes": false,
	"accessibility/captions": false,
}

static var _cache: Dictionary = {}
static var _loaded := false
## Keep changes in memory only (tests must never touch the player's file).
static var memory_only := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for section in cf.get_sections():
		if section == "audio":
			continue
		for key in cf.get_section_keys(section):
			_cache["%s/%s" % [section, key]] = cf.get_value(section, key)


static func get_bool(key: String) -> bool:
	_load()
	return bool(_cache.get(key, DEFAULTS.get(key, false)))


static func set_bool(key: String, value: bool) -> void:
	_load()
	_cache[key] = value
	if memory_only:
		return
	var cf := ConfigFile.new()
	cf.load(PATH)  # keep the other sections (audio volumes)
	var parts := key.split("/")
	cf.set_value(parts[0], parts[1], value)
	cf.save(PATH)


static func reduced_motion() -> bool:
	return get_bool("accessibility/reduced_motion")


static func reduce_flashes() -> bool:
	return get_bool("accessibility/reduce_flashes")


static func captions() -> bool:
	return get_bool("accessibility/captions")


## Has the player watched this tier's full reveal before? (Then it may be skipped.)
static func eye_seen(tier_id: String) -> bool:
	return get_bool("eye/seen_" + tier_id)


static func mark_eye_seen(tier_id: String) -> void:
	if not eye_seen(tier_id):
		set_bool("eye/seen_" + tier_id, true)


## Forget everything cached (tests).
static func reset_cache() -> void:
	_cache.clear()
	_loaded = false
