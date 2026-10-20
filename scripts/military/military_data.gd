class_name MilitaryData
extends RefCounted
## Phase 5.1: the raid to come (or being fought) and the house's record in
## arms. Pure data; Military holds the rules. The raiders are their own
## people, never villagers: they are not in WorldState.characters (ids below
## zero), so no village system sees them.

## The day the next band is due (-1 until it's set).
var next_raid_day: int = -1
## The band on its way, or {}: {name, day, size, from [x, y, z], road,
## tribute, loot_gold, loot_food, levy (called), fought}.
var raid: Dictionary = {}
var raiders: Array[CharacterData] = []
## Fights fought and won.
var battles: int = 0
var won: int = 0
## The last fight's report (Military.finish), for the battle report.
var last_report: Dictionary = {}


func to_dict() -> Dictionary:
	var list := []
	for r in raiders:
		list.append(r.to_dict())
	return {"next_raid_day": next_raid_day, "raid": raid.duplicate(true), "raiders": list,
		"battles": battles, "won": won, "last_report": last_report.duplicate(true)}


static func from_dict(d: Dictionary) -> MilitaryData:
	var m := MilitaryData.new()
	m.next_raid_day = int(d.get("next_raid_day", -1))
	var r: Dictionary = d.get("raid", {})
	m.raid = r.duplicate(true)
	for k: String in ["day", "size", "tribute", "loot_gold", "loot_food"]:
		if m.raid.has(k):
			m.raid[k] = int(m.raid[k])
	for rd: Dictionary in d.get("raiders", []):
		m.raiders.append(CharacterData.from_dict(rd))
	m.battles = int(d.get("battles", 0))
	m.won = int(d.get("won", 0))
	m.last_report = (d.get("last_report", {}) as Dictionary).duplicate(true)
	return m
