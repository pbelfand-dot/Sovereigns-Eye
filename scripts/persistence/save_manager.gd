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
		version = 9
	if version == 9:
		# v10 (Smithy) gives each smithy its forge yard against a side wall,
		# where the generator would put it now, moving the smithy's barrels
		# and crates out of the way.
		var l: Dictionary = data.get("layout", {})
		if not l.is_empty():
			var layout := VillageLayout.from_dict(l)
			var props: Array = l.get("props", [])
			if not props.any(func(p: Dictionary) -> bool: return str(p["type"]) == "forge"):
				for b in layout.buildings:
					if b.type != "smithy":
						continue
					var yard := VillageLayoutGenerator.smithy_yard(layout, b, true)
					if yard.is_empty():
						continue
					var rect := {"center": yard["pos"], "rot": yard["rot"], "half": VillageLayoutGenerator.YARD_HALF["forge"]}
					props = props.filter(func(p: Dictionary) -> bool:
						var at := Vector3(float(p["pos"][0]), 0, float(p["pos"][1]))
						return not (str(p["type"]) in ["barrel", "crate"] and VillageLayoutGenerator._point_in_rect(at, rect, 0.5)))
					var pos: Vector3 = yard["pos"]
					props.append({"type": "forge", "pos": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)], "rot": snappedf(float(yard["rot"]), 0.0001)})
			l["props"] = props
		data["save_version"] = 10
		version = 10
	if version == 10:
		# v11 (Training Yard) gives each barracks its training yard behind or
		# beside it, where the generator would put it now, in place of the
		# three kit dummies before it (kept where no yard fits), moving barrels
		# and crates out of the way.
		var l: Dictionary = data.get("layout", {})
		if not l.is_empty():
			var layout := VillageLayout.from_dict(l)
			var props: Array = l.get("props", [])
			if not props.any(func(p: Dictionary) -> bool: return str(p["type"]).begins_with("training")):
				for b in layout.buildings:
					if b.type != "barracks":
						continue
					var yard := VillageLayoutGenerator.training_yard(layout, b, true)
					if yard.is_empty():
						continue
					var rect := {"center": yard["pos"], "rot": yard["rot"], "half": VillageLayoutGenerator.YARD_HALF[yard["type"]]}
					var here := b.position
					props = props.filter(func(p: Dictionary) -> bool:
						var at := Vector3(float(p["pos"][0]), 0, float(p["pos"][1]))
						if str(p["type"]) == "dummy" and at.distance_to(here) < b.footprint.length() * 0.5 + 6.0:
							return false
						return not (str(p["type"]) in ["barrel", "crate"] and VillageLayoutGenerator._point_in_rect(at, rect, 0.5)))
					var pos: Vector3 = yard["pos"]
					props.append({"type": yard["type"], "pos": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)], "rot": snappedf(float(yard["rot"]), 0.0001)})
			l["props"] = props
		data["save_version"] = 11
		version = 11
	if version == 11:
		# v12 (Chapel & Churchyard) gives each chapel its churchyard at its
		# east end (or beside the nave), where the generator would put it
		# now, clear of buildings going up; barrels and crates move out of it.
		var l: Dictionary = data.get("layout", {})
		if not l.is_empty():
			var layout := VillageLayout.from_dict(l)
			var props: Array = l.get("props", [])
			var avoid := []
			for sd: Dictionary in (data.get("territory", {}) as Dictionary).get("sites", []):
				var sb := BuildingData.from_dict(sd.get("building", {}))
				avoid.append({"center": sb.position, "rot": sb.rotation, "half": sb.footprint * 0.5})
			if not props.any(func(p: Dictionary) -> bool: return str(p["type"]).begins_with("churchyard")):
				for b in layout.buildings:
					if b.type != "chapel":
						continue
					var yard := VillageLayoutGenerator.churchyard(layout, b, true, avoid)
					if yard.is_empty():
						continue
					var rect := {"center": yard["pos"], "rot": yard["rot"], "half": VillageLayoutGenerator.YARD_HALF[yard["type"]]}
					props = props.filter(func(p: Dictionary) -> bool:
						var at := Vector3(float(p["pos"][0]), 0, float(p["pos"][1]))
						return not (str(p["type"]) in ["barrel", "crate"] and VillageLayoutGenerator._point_in_rect(at, rect, 0.5)))
					var pos: Vector3 = yard["pos"]
					var entry := {"type": yard["type"], "pos": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)], "rot": snappedf(float(yard["rot"]), 0.0001)}
					props.append(entry)
					layout.props.append({"type": entry["type"], "pos": pos, "rot": float(yard["rot"])})  # a second chapel keeps clear of it
			l["props"] = props
		data["save_version"] = 12
		version = 12
	if version == 12:
		# v13 (Phase 4.1, the years turn) gives everyone a birthday, drawn the
		# way a new village draws them (in order of id), and starts the record
		# of the departed empty. Seasons are 10 days now, so the calendar date
		# of an older save moves on; ages and the clock don't change.
		var rng := Seeds.rng(int(data.get("seed", 0)), "birthdays")
		var people: Array = data.get("characters", [])
		var ordered := people.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("id", 0)) < int(b.get("id", 0)))
		for c: Dictionary in ordered:
			if not c.has("birthday"):
				c["birthday"] = rng.randi_range(0, Calendar.days_per_year() - 1)
		if not data.has("departed"):
			data["departed"] = []
		data["save_version"] = 13
		version = 13
	if version == 13:
		# v14 (Phase 4.2, the house's matches) adds the noble houses around the
		# village, generated from the seed as a new village's are, and who is
		# visiting as a suitor (no one, in an older save).
		if not data.has("realm") or (data["realm"] as Dictionary).is_empty():
			var taken := []
			for f: Dictionary in data.get("families", []):
				taken.append(str(f.get("name", "")))
			data["realm"] = RealmData.generate(int(data.get("seed", 0)), taken).to_dict()
		data["save_version"] = 14
		version = 14
	if version == 14:
		# v15 (Phase 4.3, succession): the house remembers its rulers in turn,
		# starting with today's head; no heir is named and no regent rules.
		var house: Dictionary = data.get("house", {})
		if not house.is_empty() and not house.has("rulers"):
			var head := -1
			for f: Dictionary in data.get("families", []):
				if int(f.get("id", -1)) == int(data.get("ruling_family", -1)):
					head = int(f.get("head", -1))
			house["rulers"] = [{"id": head, "from": 0, "to": -1}] if head >= 0 else []
		data["save_version"] = 15
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
