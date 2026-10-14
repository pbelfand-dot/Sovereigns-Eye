class_name ConstructionSite
extends RefCounted
## A building going up: where it stands, how much work it still needs and
## who is building it. Pure data; TerritorySystem holds the rules and
## ConstructionView draws it.
##
## `building` is the finished BuildingData, already given its id, so the
## site can use door_position()/basis() and the id stays stable across saves.
## It joins the VillageLayout only when the work is done.

var building: BuildingData
## Builder-hours needed and done so far.
var work_needed: float = 1.0
var work_done: float = 0.0
## Character ids of the crew.
var builders: Array[int] = []
var started_day: int = 0
## Name of the lane laid from the door to the road ("" = none needed).
var lane: String = ""
## What was paid, for refunds if the order is cancelled.
var paid: Dictionary = {}


func id() -> int:
	return building.id if building else -1


## 0..1
func progress() -> float:
	return clampf(work_done / maxf(work_needed, 0.001), 0.0, 1.0)


func is_done() -> bool:
	return work_done >= work_needed


func to_dict() -> Dictionary:
	return {
		"building": building.to_dict(),
		"work_needed": snappedf(work_needed, 0.01),
		"work_done": snappedf(work_done, 0.01),
		"builders": builders.duplicate(),
		"started_day": started_day,
		"lane": lane,
		"paid": paid.duplicate(),
	}


static func from_dict(d: Dictionary) -> ConstructionSite:
	var s := ConstructionSite.new()
	s.building = BuildingData.from_dict(d.get("building", {}))
	s.work_needed = float(d.get("work_needed", 1.0))
	s.work_done = float(d.get("work_done", 0.0))
	for id: Variant in d.get("builders", []):
		s.builders.append(int(id))
	s.started_day = int(d.get("started_day", 0))
	s.lane = str(d.get("lane", ""))
	var paid: Dictionary = d.get("paid", {})
	for k: String in paid:
		s.paid[k] = int(paid[k])
	return s
