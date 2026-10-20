class_name CastleData
extends RefCounted
## Phase 5.3: the house's castle. What stands ("timber" a motte and bailey,
## "stone" a stone castle, "" nothing yet), the works under way and where
## the castle stands (chosen once, with room for both). Pure data;
## CastleSystem holds the rules, CastleView draws it.

## What stands: "", "timber" or "stone".
var kind: String = ""
## What's being built: "", "timber" or "stone".
var works: String = ""
## Where it stands: [x, z, yaw (rad)], [] until a site is chosen.
var site: Array = []
## Builder-hours needed and done on the works.
var work_needed: float = 0.0
var work_done: float = 0.0
## Wood and stone the works have used so far.
var used: Dictionary = {}
## Character ids of the crew.
var builders: Array[int] = []
var started_day: int = -1
## Why the works wait ("" when they don't): a store run dry.
var stalled: String = ""


func has_site() -> bool:
	return site.size() == 3


func transform() -> Transform3D:
	if not has_site():
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3.UP, float(site[2])), Vector3(float(site[0]), 0.0, float(site[1])))


## 0..1 of the works.
func progress() -> float:
	return clampf(work_done / maxf(work_needed, 0.001), 0.0, 1.0) if not works.is_empty() else 0.0


func to_dict() -> Dictionary:
	return {"kind": kind, "works": works, "site": site.duplicate(), "work_needed": snappedf(work_needed, 0.01),
		"work_done": snappedf(work_done, 0.01), "used": used.duplicate(), "builders": builders.duplicate(),
		"started_day": started_day, "stalled": stalled}


static func from_dict(d: Dictionary) -> CastleData:
	var c := CastleData.new()
	c.kind = str(d.get("kind", ""))
	c.works = str(d.get("works", ""))
	for v: Variant in d.get("site", []):
		c.site.append(float(v))
	c.work_needed = float(d.get("work_needed", 0.0))
	c.work_done = float(d.get("work_done", 0.0))
	var u: Dictionary = d.get("used", {})
	for k: String in u:
		c.used[k] = float(u[k])
	for id: Variant in d.get("builders", []):
		c.builders.append(int(id))
	c.started_day = int(d.get("started_day", -1))
	c.stalled = str(d.get("stalled", ""))
	return c
