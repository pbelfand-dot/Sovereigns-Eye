class_name Market
extends RefCounted
## Phase 6.1, the market. Food, wood and stone are bought and sold for gold
## at the village's market: the merchant's stall in the square from the
## start, more of it and on better terms with each Market Hall, and better
## again with a merchant gifted at haggling. Prices move with the season,
## with the realm's harvest each year (which also sets how well the
## village's own fields yield that autumn) and with the house's own trade:
## a big sale floods the market and the price falls, recovering day by day.
## The steward keeps standing orders: buy what a store lacks of its mark,
## sell what lies above another, keeping a reserve of gold.
##
## Static and deterministic. Numbers: data/market.json.

const GOODS := ["food", "wood", "stone", "cloth", "ironware", "ale"]


static func cfg() -> Dictionary:
	return GameData.load_file("market")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


# --- The harvest ------------------------------------------------------------------------------

## The harvest year in force: the autumn it came in (0 the first autumn;
## before it, -1, the harvest the village began with).
static func harvest_year(state: WorldState) -> int:
	var autumn := maxi(0, Calendar.seasons().find("Autumn")) * Calendar.days_per_season()
	return floori((state.day() - autumn) / float(Calendar.days_per_year()))


## The realm's harvest of a year (the same for the same seed and year).
static func harvest_of(state: WorldState, year: int) -> Dictionary:
	var kinds: Array = section("harvest").get("kinds", [])
	if kinds.is_empty():
		return {"id": "fair", "name": "a fair harvest", "price": 1.0, "yield": 1.0}
	var weights := {}
	for k: Dictionary in kinds:
		weights[str(k["id"])] = float(k.get("weight", 1))
	var id := Seeds.weighted_key(Seeds.rng(state.world_seed, "harvest_%d" % year), weights)
	for k: Dictionary in kinds:
		if str(k["id"]) == id:
			return k
	return kinds[0]


static func harvest(state: WorldState) -> Dictionary:
	return harvest_of(state, harvest_year(state))


## How well the village's own fields yield today: the harvest's yield in
## autumn, as usual otherwise (TerritorySystem.season_factor).
static func harvest_yield(state: WorldState) -> float:
	return float(harvest(state).get("yield", 1.0)) if state.current_season() == "Autumn" else 1.0


# --- Prices -----------------------------------------------------------------------------------

## The market price of a good today, before the spread: gold per unit.
static func price(state: WorldState, good: String) -> float:
	var g: Dictionary = section("goods").get(good, {})
	var p := float(g.get("price", 1.0)) * float((g.get("season", {}) as Dictionary).get(state.current_season(), 1.0))
	if good == "food":
		p *= float(harvest(state).get("price", 1.0))
	elif g.has("follows"):
		# Ale's price is set from grain's (the Assize of Bread and Ale).
		var f := str(g["follows"])
		p *= fair_price(state, f) / float(section("goods").get(f, {}).get("price", 1.0))
	if state.market:
		p *= 1.0 + float(state.market.pressure.get(good, 0.0))
	return p


## The price the same day without the house's own trade in it.
static func fair_price(state: WorldState, good: String) -> float:
	return price(state, good) / (1.0 + float(state.market.pressure.get(good, 0.0))) if state.market else price(state, good)


## Market Halls standing.
static func halls(state: WorldState) -> int:
	return state.layout.buildings_of_type("market").size() if state.layout else 0


## The village's merchant best at haggling (Politics), or null.
static func best_merchant(state: WorldState) -> CharacterData:
	var best: CharacterData = null
	for c in state.characters:
		if c.occupation_id != "merchant" or c.retainer or c.is_away() or c.is_visitor() or c.age < 16:
			continue
		if best == null or c.get_current("politics") > best.get_current("politics") or (c.get_current("politics") == best.get_current("politics") and c.id < best.id):
			best = c
	return best


## The share added to the price when you buy, and taken off when you sell.
static func spread(state: WorldState) -> float:
	var t := section("trade")
	var s := float(t.get("spread", 0.3)) - halls(state) * float(t.get("spread_per_hall", 0.05))
	var m := best_merchant(state)
	if m:
		s -= m.get_current("politics") / 100.0 * float(t.get("merchant_spread", 0.1))
	return maxf(float(t.get("min_spread", 0.1)), s)


## Units of a good the market takes or gives in a day (wares in smaller
## lots: their 'volume' share).
static func volume(state: WorldState, good: String = "food") -> int:
	var t := section("trade")
	var share := float(section("goods").get(good, {}).get("volume", 1.0))
	return roundi((int(t.get("volume", 25)) + halls(state) * int(t.get("volume_per_hall", 60))) * share)


## Units of a good left to trade today.
static func room(state: WorldState, good: String) -> int:
	return maxi(0, volume(state, good) - state.market.traded_today(good, state.day()))


## Gold for `units` of a good: paid when buying (units > 0), received when
## selling (units < 0), the price moving with each unit.
static func quote(state: WorldState, good: String, units: int) -> int:
	if units == 0:
		return 0
	var t := section("trade")
	var k := float(t.get("pressure", 0.004))
	var top := float(t.get("max_pressure", 0.6))
	var base := fair_price(state, good)
	var pr := float(state.market.pressure.get(good, 0.0))
	var s := spread(state)
	var total := 0.0
	for i in absi(units):
		total += base * (1.0 + pr)
		pr = clampf(pr + (k if units > 0 else -k), -top, top)
	return ceili(total * (1.0 + s)) if units > 0 else floori(total * (1.0 - s))


static func buy_price(state: WorldState, good: String) -> float:
	return price(state, good) * (1.0 + spread(state))


static func sell_price(state: WorldState, good: String) -> float:
	return price(state, good) * (1.0 - spread(state))


# --- Trading ----------------------------------------------------------------------------------

## How many units of a good could be bought now (by the market's room,
## the stores' room and, if `budget` >= 0, the gold to spend).
static func can_buy_units(state: WorldState, good: String, units: int, budget: int = -1) -> int:
	var n := mini(units, room(state, good))
	n = mini(n, floori(TerritorySystem.capacity(state, good) - TerritorySystem.amount(state, good)))
	if budget >= 0:
		while n > 0 and quote(state, good, n) > budget:
			n -= maxi(1, n / 10)
	return maxi(0, n)


## Buys `units` of a good. {ok, text, units, gold}
static func buy(state: WorldState, good: String, units: int, by: String = "you") -> Dictionary:
	if not GOODS.has(good) or units <= 0:
		return {"ok": false, "text": "", "units": 0, "gold": 0}
	var name := TerritorySystem.resource_name(good).to_lower()
	if room(state, good) <= 0:
		return {"ok": false, "text": "The market has no more %s to sell today." % name, "units": 0, "gold": 0}
	if TerritorySystem.amount(state, good) >= TerritorySystem.capacity(state, good) - 0.5:
		return {"ok": false, "text": "The stores are full of %s." % name, "units": 0, "gold": 0}
	var n := can_buy_units(state, good, units)
	var cost := quote(state, good, n)
	if cost > state.house.gold:
		return {"ok": false, "text": "You haven't the %d gold for %d %s." % [cost, n, name], "units": 0, "gold": 0}
	_trade(state, good, n, -cost, by)
	return {"ok": true, "text": "Bought %d %s for %d gold." % [n, name, cost], "units": n, "gold": -cost}


## Sells `units` of a good. {ok, text, units, gold}
static func sell(state: WorldState, good: String, units: int, by: String = "you") -> Dictionary:
	if not GOODS.has(good) or units <= 0:
		return {"ok": false, "text": "", "units": 0, "gold": 0}
	var name := TerritorySystem.resource_name(good).to_lower()
	if room(state, good) <= 0:
		return {"ok": false, "text": "The market will take no more %s today." % name, "units": 0, "gold": 0}
	var n := mini(mini(units, room(state, good)), floori(TerritorySystem.amount(state, good)))
	if n <= 0:
		return {"ok": false, "text": "There's no %s in the stores to sell." % name, "units": 0, "gold": 0}
	var got := quote(state, good, -n)
	_trade(state, good, -n, got, by)
	return {"ok": true, "text": "Sold %d %s for %d gold." % [n, name, got], "units": -n, "gold": got}


static func _trade(state: WorldState, good: String, units: int, gold: int, by: String) -> void:
	var m := state.market
	var t := section("trade")
	var day := state.day()
	if m.traded_day != day:
		m.traded = {}
		m.traded_day = day
	TerritorySystem.add(state, good, float(units))
	state.house.gold = maxi(0, state.house.gold + gold)
	var top := float(t.get("max_pressure", 0.6))
	m.pressure[good] = clampf(float(m.pressure.get(good, 0.0)) + float(t.get("pressure", 0.004)) * units, -top, top)
	m.traded[good] = int(m.traded.get(good, 0)) + absi(units)
	m.ledger.append({"day": day, "good": good, "units": units, "gold": gold, "by": by})
	var keep := int(section("orders").get("ledger", 30))
	if m.ledger.size() > keep:
		m.ledger = m.ledger.slice(m.ledger.size() - keep)


# --- The steward's standing orders ------------------------------------------------------------

## Sets a good's marks (-1 for none). The sell mark is kept above the keep mark.
static func set_order(state: WorldState, good: String, keep: int, sell_above: int) -> void:
	keep = maxi(-1, keep)
	sell_above = maxi(-1, sell_above)
	if keep >= 0 and sell_above >= 0 and sell_above <= keep:
		sell_above = keep + int(section("orders").get("step", 50))
	state.market.orders[good] = {"keep": keep, "sell": sell_above}


static func has_steward(state: WorldState) -> bool:
	return state.house != null and state.get_character(state.house.holder_of("steward")) != null


## Gold the steward won't spend below.
static func reserve(state: WorldState) -> int:
	var o := section("orders")
	return maxi(int(o.get("reserve_min", 50)), int(o.get("reserve_days", 10)) * CourtSystem.daily_wages(state))


## Carries out the standing orders (each morning). The trades made.
static func run_orders(state: WorldState) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	if not has_steward(state):
		return done
	for good: String in GOODS:
		var o := state.market.order(good)
		var have := floori(TerritorySystem.amount(state, good))
		if int(o["keep"]) >= 0 and have < int(o["keep"]):
			var n := can_buy_units(state, good, int(o["keep"]) - have, state.house.gold - reserve(state))
			if n > 0:
				var r := buy(state, good, n, "steward")
				if r["ok"]:
					done.append(r)
		elif int(o["sell"]) >= 0 and have > int(o["sell"]):
			var r := sell(state, good, have - int(o["sell"]), "steward")
			if r["ok"]:
				done.append(r)
	return done


# --- The days ---------------------------------------------------------------------------------

## Once a day (after the stores are counted): yesterday's trade fades from
## the prices, the harvest is told when it comes in, and the steward trades.
## Events: {text, kind, harvest?}.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var m := state.market
	if m == null or state.house == null or state.house.ended:
		return events
	var recover := float(section("trade").get("recover", 0.3))
	for g: String in m.pressure.keys():
		var p := float(m.pressure[g]) * (1.0 - recover)
		if absf(p) < 0.005:
			m.pressure.erase(g)
		else:
			m.pressure[g] = p
	var y := harvest_year(state)
	if m.harvest_told != y and (y < 0 or state.current_season() != "Autumn"):
		m.harvest_told = y  # a harvest that came in before this market opened isn't news
	elif m.harvest_told != y:
		m.harvest_told = y
		var h := harvest(state)
		var dear := float(h.get("price", 1.0))
		var text := "The harvest is in: %s across the realm. Food goes for %.2f gold until the next harvest%s." % [h["name"], fair_price(state, "food"),
			", and your fields yield less" if float(h.get("yield", 1.0)) < 1.0 else (", and your fields yield more" if float(h.get("yield", 1.0)) > 1.0 else "")]
		events.append({"text": text, "kind": "bad" if dear > 1.05 else ("good" if dear < 0.95 else "info"), "harvest": str(h["id"])})
		state.house.log_event(state.day(), "The harvest: %s." % h["name"], "bad" if dear > 1.05 else "office")
	run_orders(state)
	return events


## What the steward did in the last `days` days: {bought: {good: units},
## sold: {good: units}, paid, got}.
static func steward_summary(state: WorldState, days: int) -> Dictionary:
	var out := {"bought": {}, "sold": {}, "paid": 0, "got": 0}
	for e: Dictionary in state.market.ledger:
		if str(e["by"]) != "steward" or int(e["day"]) < state.day() - days:
			continue
		var g := str(e["good"])
		if int(e["units"]) > 0:
			out["bought"][g] = int(out["bought"].get(g, 0)) + int(e["units"])
			out["paid"] += -int(e["gold"])
		else:
			out["sold"][g] = int(out["sold"].get(g, 0)) - int(e["units"])
			out["got"] += int(e["gold"])
	return out
