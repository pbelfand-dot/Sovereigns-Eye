class_name MarketData
extends RefCounted
## Phase 6.1: the village's market. How the house's own trade has moved
## each price (pressure), what has changed hands today, the steward's
## standing orders and a ledger of recent trades. Pure data; Market holds
## the rules.

## good -> share the price is up (bought) or down (sold) by your trade.
var pressure: Dictionary = {}
## good -> units bought or sold today (the market's volume is per day).
var traded: Dictionary = {}
var traded_day: int = -1
## good -> {"keep": int, "sell": int}: buy below keep, sell above sell
## (-1 for no mark).
var orders: Dictionary = {}
## Recent trades, newest last: [{day, good, units (+ bought, - sold),
## gold (+ received, - paid), by ("you" or "steward")}].
var ledger: Array = []
## The harvest year last announced (so it's told once).
var harvest_told: int = -999
## Carts on the road to the noble houses' seats (Phase 6.2): [{id, house,
## load: {good: units}, carter, escort: [ids], set_out, set_out_min (the
## minute it left), arrive, back, stage ("out" or "home"), road_home (its
## road home travelled, the day before it's in), gold, unsold: {good:
## units}, sold: {good: units}, waylaid: "" or what happened}].
var carts: Array = []
var next_cart_id: int = 1
## The last cart home's report ({} before any).
var last_cart: Dictionary = {}


func order(good: String) -> Dictionary:
	return orders.get(good, {"keep": -1, "sell": -1})


func traded_today(good: String, day: int) -> int:
	return int(traded.get(good, 0)) if traded_day == day else 0


func to_dict() -> Dictionary:
	return {"pressure": pressure.duplicate(), "traded": traded.duplicate(), "traded_day": traded_day,
		"orders": orders.duplicate(true), "ledger": ledger.duplicate(true), "harvest_told": harvest_told,
		"carts": carts.duplicate(true), "next_cart_id": next_cart_id, "last_cart": last_cart.duplicate(true)}


static func from_dict(d: Dictionary) -> MarketData:
	var m := MarketData.new()
	var p: Dictionary = d.get("pressure", {})
	for g: String in p:
		m.pressure[g] = float(p[g])
	var t: Dictionary = d.get("traded", {})
	for g: String in t:
		m.traded[g] = int(t[g])
	m.traded_day = int(d.get("traded_day", -1))
	var o: Dictionary = d.get("orders", {})
	for g: String in o:
		m.orders[g] = {"keep": int(o[g].get("keep", -1)), "sell": int(o[g].get("sell", -1))}
	for e: Dictionary in d.get("ledger", []):
		m.ledger.append({"day": int(e.get("day", 0)), "good": str(e.get("good", "")), "units": int(e.get("units", 0)),
			"gold": int(e.get("gold", 0)), "by": str(e.get("by", "you"))})
	m.harvest_told = int(d.get("harvest_told", -999))
	for c: Dictionary in d.get("carts", []):
		m.carts.append(_cart_from(c))
	m.next_cart_id = int(d.get("next_cart_id", 1))
	m.last_cart = (d.get("last_cart", {}) as Dictionary).duplicate(true)
	return m


static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = int(d[k])
	return out


static func _cart_from(c: Dictionary) -> Dictionary:
	var escort: Array[int] = []
	for id: Variant in c.get("escort", []):
		escort.append(int(id))
	return {"id": int(c.get("id", 0)), "house": int(c.get("house", -1)), "load": _ints(c.get("load", {})),
		"carter": int(c.get("carter", -1)), "escort": escort, "set_out": int(c.get("set_out", 0)),
		"set_out_min": float(c.get("set_out_min", int(c.get("set_out", 0)) * Calendar.MINUTES_PER_DAY + 8 * Calendar.MINUTES_PER_HOUR)),
		"arrive": int(c.get("arrive", 0)), "back": int(c.get("back", 0)), "stage": str(c.get("stage", "out")),
		"road_home": bool(c.get("road_home", false)),
		"gold": int(c.get("gold", 0)), "unsold": _ints(c.get("unsold", {})), "sold": _ints(c.get("sold", {})),
		"waylaid": str(c.get("waylaid", ""))}
