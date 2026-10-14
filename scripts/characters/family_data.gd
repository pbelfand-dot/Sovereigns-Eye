class_name FamilyData
extends RefCounted
## A household / bloodline. Phase 6 (dynasties) will grow this into full
## lineages; for now it groups people who share a surname and a home.

var id: int = -1
var name: String = ""
var background: String = "farming"
var social_status: String = "peasant"
var home_building_id: int = -1
var head_id: int = -1
var member_ids: Array[int] = []
var is_ruling: bool = false


func display_name() -> String:
	if is_ruling or background == "noble":
		return "House %s" % name
	return "%s family" % name


func background_name() -> String:
	return str(GameData.background(background).get("name", background.capitalize()))


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"background": background,
		"status": social_status,
		"home": home_building_id,
		"head": head_id,
		"members": Array(member_ids),
		"ruling": is_ruling,
	}


static func from_dict(d: Dictionary) -> FamilyData:
	var f := FamilyData.new()
	f.id = int(d.get("id", -1))
	f.name = str(d.get("name", ""))
	f.background = str(d.get("background", "farming"))
	f.social_status = str(d.get("status", "peasant"))
	f.home_building_id = int(d.get("home", -1))
	f.head_id = int(d.get("head", -1))
	for m: Variant in d.get("members", []):
		f.member_ids.append(int(m))
	f.is_ruling = bool(d.get("ruling", false))
	return f
