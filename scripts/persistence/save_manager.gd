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
		version = 5
	if version == 5:
		# v6 (motive-based recruitment) adds the terms people joined on, the
		# motives they've told you, titles, and the house's standing and open
		# promises. Retainers who joined before keep the standard wage
		# (agreed_wage -1) and empty terms; standing starts at fair (50).
		data["save_version"] = 6
		version = 6
	if version == 6:
		# v7 (Phase 3.3) adds the settlement's charter. Villages that already
		# grew past a Hamlet's limit start as a Village, so nobody is over
		# their charter's limit.
		var t: Dictionary = data.get("territory", {})
		if not t.is_empty() and not t.has("charter"):
			var people := (data.get("characters", []) as Array).size()
			t["charter"] = 1 if people > 70 else 0
		data["save_version"] = 7
		version = 7
	if version == 7:
		# v8 (Farm & Field) draws haystacks and the log pile as full-size
		# models, and new layouts give them room in the yard. Older layouts
		# put some against (or inside) a wall, where they'd clip and block
		# the path: those are dropped. Nothing else changes.
		var l: Dictionary = data.get("layout", {})
		if not l.is_empty():
			var layout := VillageLayout.from_dict(l)
			var radii: Dictionary = WorldGeometry.cfg().get("props", {})
			var kept := []
			for p: Dictionary in l.get("props", []):
				var type := str(p["type"])
				var pos: Array = p["pos"]
				if type in ["haystack", "lumber"] and not layout.yard_spot_clear(Vector3(float(pos[0]), 0, float(pos[1])), float(radii.get(type, 1.0))):
					continue
				kept.append(p)
			l["props"] = kept
		data["save_version"] = 8
		version = 8
	if version == 8:
		# v9 (Market Square) adds the trough beside the well and the market
		# cross's spot to the square (the cross stands from Market Town on),
		# found the way the generator finds them for a new village.
		var l: Dictionary = data.get("layout", {})
		if not l.is_empty():
			var props: Array = l.get("props", [])
			var have := {}
			for p: Dictionary in props:
				have[str(p["type"])] = true
			for p: Dictionary in VillageLayoutGenerator.square_furniture(VillageLayout.from_dict(l)):
				if not have.has(p["type"]):
					var pos: Vector3 = p["pos"]
					props.append({"type": p["type"], "pos": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)], "rot": snappedf(float(p["rot"]), 0.0001)})
			l["props"] = props
		data["save_version"] = 9
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
