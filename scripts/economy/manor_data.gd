class_name ManorData
extends RefCounted
## Phase 6.3: the manor's dues and the Crown's levies. The mill's toll, when
## the querns were last seized, the house's fair, and the levies assessed.
## Pure data; ManorSystem holds the rules.

## The mill's toll: "light", "customary" or "hard" (data/manor.json mill).
var toll: String = "customary"
## The day until which hand-querns are seized (-1: never).
var querns_seized_until: int = -1
## The fair: bought from the Crown, its saint's feast (an index into the
## fair's feasts), and the last year it was held.
var fair_granted: bool = false
var fair_feast: int = -1
var fair_held_year: int = -999
## The share of its movables the house will hide from the next assessment.
var hide: float = 0.0
## Days (absolute) of the levies already assessed, and what each took:
## [{day, year, name, due, paid, hidden, exposed}], newest last.
var assessed: Array[int] = []
var levies: Array = []


func to_dict() -> Dictionary:
	return {"toll": toll, "querns_seized_until": querns_seized_until, "fair_granted": fair_granted,
		"fair_feast": fair_feast, "fair_held_year": fair_held_year, "hide": hide,
		"assessed": assessed.duplicate(), "levies": levies.duplicate(true)}


static func from_dict(d: Dictionary) -> ManorData:
	var m := ManorData.new()
	m.toll = str(d.get("toll", "customary"))
	m.querns_seized_until = int(d.get("querns_seized_until", -1))
	m.fair_granted = bool(d.get("fair_granted", false))
	m.fair_feast = int(d.get("fair_feast", -1))
	m.fair_held_year = int(d.get("fair_held_year", -999))
	m.hide = float(d.get("hide", 0.0))
	for day: Variant in d.get("assessed", []):
		m.assessed.append(int(day))
	for e: Dictionary in d.get("levies", []):
		m.levies.append({"day": int(e.get("day", 0)), "year": int(e.get("year", 0)), "name": str(e.get("name", "")),
			"due": int(e.get("due", 0)), "paid": int(e.get("paid", 0)), "hidden": float(e.get("hidden", 0.0)),
			"exposed": bool(e.get("exposed", false))})
	return m
