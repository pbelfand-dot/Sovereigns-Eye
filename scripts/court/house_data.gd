class_name HouseData
extends RefCounted
## The player's noble house: treasury, renown, offices and its chronicle.
## Pure data; CourtSystem holds the rules. Retainer membership itself lives
## on each CharacterData (retainer, office, focus...).

var gold: int = 0
var renown: int = 0
## office id -> character id (missing = vacant)
var offices: Dictionary = {}
## True after a day the house couldn't pay wages.
var in_debt: bool = false
## [{ "day": int, "text": String, "kind": String }], newest last.
var chronicle: Array[Dictionary] = []
## Fractional renown earned so far (Chancellor), paid out in whole points.
var renown_progress: float = 0.0
## How common folk regard the house's word, 0..100 (Recruitment): kept
## promises and paid wages raise it, broken ones and hunger lower it.
var standing: float = 50.0
## Open promises: [{character, kind ("home"), due (day), made (day)}].
var promises: Array[Dictionary] = []

# --- Succession (Phase 4.3) ---------------------------------------------------
## The child the player named heir (-1: the eldest, by default).
var heir_id: int = -1
## Who rules for a ruler not yet of age (-1: no regency).
var regent_id: int = -1
## The house's heads in turn: [{id, from (day), to (day, -1 while ruling)}].
var rulers: Array[Dictionary] = []
## The player last told their health is failing (told once each).
var warned_id: int = -1
## Older children already passed over for heir (they take it ill once).
var passed_over: Array[int] = []
## No one of the house is left: the game is over.
var ended: bool = false

const CHRONICLE_LIMIT := 60


func holder_of(office_id: String) -> int:
	return int(offices.get(office_id, -1))


func log_event(day: int, text: String, kind: String = "court") -> void:
	chronicle.append({"day": day, "text": text, "kind": kind})
	while chronicle.size() > CHRONICLE_LIMIT:
		chronicle.pop_front()


func to_dict() -> Dictionary:
	return {
		"gold": gold,
		"renown": renown,
		"offices": offices.duplicate(),
		"in_debt": in_debt,
		"chronicle": chronicle.duplicate(true),
		"renown_progress": snappedf(renown_progress, 0.001),
		"standing": snappedf(standing, 0.01),
		"promises": promises.duplicate(true),
		"heir_id": heir_id,
		"regent_id": regent_id,
		"rulers": rulers.duplicate(true),
		"warned_id": warned_id,
		"passed_over": passed_over.duplicate(),
		"ended": ended,
	}


static func from_dict(d: Dictionary) -> HouseData:
	var h := HouseData.new()
	h.gold = int(d.get("gold", 0))
	h.renown = int(d.get("renown", 0))
	var offices: Dictionary = d.get("offices", {})
	for k: String in offices:
		h.offices[k] = int(offices[k])
	h.in_debt = bool(d.get("in_debt", false))
	for e: Dictionary in d.get("chronicle", []):
		h.chronicle.append({"day": int(e.get("day", 0)), "text": str(e.get("text", "")), "kind": str(e.get("kind", "court"))})
	h.renown_progress = float(d.get("renown_progress", 0.0))
	h.standing = float(d.get("standing", 50.0))
	for p: Dictionary in d.get("promises", []):
		h.promises.append({"character": int(p.get("character", -1)), "kind": str(p.get("kind", "home")),
			"due": int(p.get("due", 0)), "made": int(p.get("made", 0))})
	h.heir_id = int(d.get("heir_id", -1))
	h.regent_id = int(d.get("regent_id", -1))
	for r: Dictionary in d.get("rulers", []):
		h.rulers.append({"id": int(r.get("id", -1)), "from": int(r.get("from", 0)), "to": int(r.get("to", -1))})
	h.warned_id = int(d.get("warned_id", -1))
	for id in d.get("passed_over", []):
		h.passed_over.append(int(id))
	h.ended = bool(d.get("ended", false))
	return h
