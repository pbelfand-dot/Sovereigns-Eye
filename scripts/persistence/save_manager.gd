class_name SaveManager
extends RefCounted
## Reads and writes saved games as JSON in user://saves/.
##
## On macOS user:// is ~/Library/Application Support/Godot/app_userdata/Sovereign's Eye/
## JSON keeps saves human-readable, which makes debugging and future save
## migrations easy. Every file carries a save_version for that purpose.

const SAVE_DIR := "user://saves/"
const SLOTS := ["quicksave", "slot_1", "slot_2", "slot_3"]


static func slot_path(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


static func slot_label(slot: String) -> String:
	if slot == "quicksave":
		return "Quicksave"
	return "Slot %s" % slot.trim_prefix("slot_")


static func save(state: WorldState, slot: String) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var payload := state.to_dict()
	payload["meta"] = {
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"village": state.village_name,
		"date": Calendar.format_full(state.whole_minutes()),
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
	}
	# Write to a temp file first so a crash mid-save never corrupts the slot.
	var tmp_path := slot_path(slot) + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "", false))
	file.close()
	var dir := DirAccess.open(SAVE_DIR)
	if dir.file_exists(slot + ".json"):
		dir.remove(slot + ".json")
	return dir.rename(slot + ".json.tmp", slot + ".json")


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


static func read_raw(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Returns null if the slot is empty, unreadable or from an unknown version.
static func load_state(slot: String) -> WorldState:
	var data := read_raw(slot)
	if data.is_empty():
		return null
	data = migrate(data)
	if int(data.get("save_version", 0)) != WorldState.SAVE_VERSION:
		push_error("SaveManager: unsupported save version %s" % data.get("save_version"))
		return null
	var state := WorldState.from_dict(data)
	# Saves from before Phase 2 have no house yet: found it now.
	CourtSystem.initialize(state)
	# Saves from before Phase 3 have no stores yet.
	TerritorySystem.initialize(state)
	CourtSystem.initialize_meetings(state)
	return state


## Upgrades older save files. Add a step here whenever SAVE_VERSION changes.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version == 1:
		# v2 (Phase 2) adds the player's house and court fields on characters.
		# Characters default to "not a retainer"; the house, the player and
		# everyone's opinion of the player are created on load by
		# CourtSystem.initialize().
		data["save_version"] = 2
		version = 2
	if version == 2:
		# v3 (Phase 3) adds the village's stores and building sites. They are
		# created on load by TerritorySystem.initialize() with the starting
		# stock; nothing else changes.
		data["save_version"] = 3
		version = 3
	if version == 3:
		# v4 (Phase 3 step 2) adds home levels and the settler bar. Missing
		# fields default to a first-level home and an empty bar.
		data["save_version"] = 4
		version = 4
	if version == 4:
		# v5 (the Sovereign's Eye) adds "met" and "remembered" on characters.
		# Anyone already appraised counts as met (CharacterData.from_dict);
		# the ruling family knows each other (CourtSystem.initialize_meetings).
		data["save_version"] = 5
	return data


## Small summary for save/load menus: {"village", "date", "saved_at"} or {}.
static func slot_info(slot: String) -> Dictionary:
	var data := read_raw(slot)
	if data.is_empty():
		return {}
	return data.get("meta", {"village": data.get("village_name", "?"), "date": "", "saved_at": ""})


static func any_save_exists() -> bool:
	for s in SLOTS:
		if exists(s):
			return true
	return false


static func delete(slot: String) -> void:
	if exists(slot):
		DirAccess.remove_absolute(slot_path(slot))
