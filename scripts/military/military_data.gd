class_name MilitaryData
extends RefCounted
## Phase 5.1: the raid to come (or being fought) and the house's record in
## arms; Phase 5.2: the bands' camps and the warband away against one. Pure
## data; Military holds the rules. The raiders are their own people, never
## villagers: they are not in WorldState.characters (ids below zero), so no
## village system sees them.

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
## Phase 5.2: where the bands live, on the realm map: [{id, band, pos [x, y],
## days, from [x, y, z] (the road they come in by), road, men, hoard,
## founded, known (where it lies), found (the day it's come on)}].
var camps: Array[Dictionary] = []
## The day the next camp is made (-1 until it's set).
var next_camp_day: int = -1
var next_camp_id: int = 1
## The warband riding against a camp, or {}: {camp, band, party [ids], heir,
## depart, fight, back, fought}.
var expedition: Dictionary = {}
## Gentle fights (chosen for this game): the fallen die far less often
## (combat death_chance_gentle).
var gentle: bool = false


func get_camp(camp_id: int) -> Dictionary:
	for c in camps:
		if int(c["id"]) == camp_id:
			return c
	return {}


func to_dict() -> Dictionary:
	var list := []
	for r in raiders:
		list.append(r.to_dict())
	return {"next_raid_day": next_raid_day, "raid": raid.duplicate(true), "raiders": list,
		"battles": battles, "won": won, "last_report": last_report.duplicate(true),
		"camps": camps.duplicate(true), "next_camp_day": next_camp_day, "next_camp_id": next_camp_id,
		"expedition": expedition.duplicate(true), "gentle": gentle}


static func from_dict(d: Dictionary) -> MilitaryData:
	var m := MilitaryData.new()
	m.next_raid_day = int(d.get("next_raid_day", -1))
	var r: Dictionary = d.get("raid", {})
	m.raid = r.duplicate(true)
	for k: String in ["day", "size", "tribute", "loot_gold", "loot_food", "camp"]:
		if m.raid.has(k):
			m.raid[k] = int(m.raid[k])
	for rd: Dictionary in d.get("raiders", []):
		m.raiders.append(CharacterData.from_dict(rd))
	m.battles = int(d.get("battles", 0))
	m.won = int(d.get("won", 0))
	m.last_report = (d.get("last_report", {}) as Dictionary).duplicate(true)
	for c: Dictionary in d.get("camps", []):
		var camp := c.duplicate(true)
		for k: String in ["id", "days", "men", "hoard", "founded", "found"]:
			camp[k] = int(camp.get(k, 0))
		camp["known"] = bool(camp.get("known", true))
		m.camps.append(camp)
	m.next_camp_day = int(d.get("next_camp_day", -1))
	m.next_camp_id = int(d.get("next_camp_id", 1))
	m.gentle = bool(d.get("gentle", false))
	m.expedition = (d.get("expedition", {}) as Dictionary).duplicate(true)
	for k: String in ["camp", "depart", "fight", "back"]:
		if m.expedition.has(k):
			m.expedition[k] = int(m.expedition[k])
	if m.expedition.has("party"):
		var ids: Array[int] = []
		for id: Variant in m.expedition["party"]:
			ids.append(int(id))
		m.expedition["party"] = ids
	return m
