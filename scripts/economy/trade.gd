class_name Trade
extends RefCounted
## Phase 6.2, carts to the noble houses' seats. A cart carries goods from
## the stores along the realm's roads, driven by a villager and guarded by
## as many of the warband as you spare (all away for the journey). The seat
## buys at the realm's going price, with no spread: dearer for the two goods
## the house wants (one for what it's known for) and from a house that
## likes yours, a share of each good a visit. A bandit camp near the road
## may waylay the cart on either leg; beaten, the escort loses the goods or
## the gold. A sale warms the house (but, being trade, not its rival).
## Carts live in MarketData.
##
## Static and deterministic. Numbers: data/trade.json.


static func cfg() -> Dictionary:
	return GameData.load_file("trade")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


# --- The seats ----------------------------------------------------------------------------------

## The two goods a house wants (the same for the same seed).
static func wants(state: WorldState, house_id: int) -> Array[String]:
	var out: Array[String] = []
	var h := state.realm.get_house(house_id) if state.realm else {}
	if h.is_empty():
		return out
	var w := section("wants")
	var first := str((w.get("by_known_for", {}) as Dictionary).get(str(h.get("known_for", "")), "cloth"))
	out.append(first)
	var rest: Array = (w.get("goods", []) as Array).filter(func(g: String) -> bool: return g != first)
	if not rest.is_empty():
		out.append(str(Seeds.pick(Seeds.rng(state.world_seed, "wants_%d" % house_id), rest)))
	return out


## Gold a house's seat pays for a unit of a good: the going price (Market,
## without your own trade in it), more for what it wants and by its regard.
static func seat_price(state: WorldState, house_id: int, good: String) -> float:
	var w := section("wants")
	var h := state.realm.get_house(house_id)
	var regard := clampi(int(h.get("standing", 0)), 0, int(w.get("max_regard", 100)))
	var f := float(w.get("premium", 1.6)) if wants(state, house_id).has(good) else float(w.get("plain", 1.0))
	return Market.fair_price(state, good) * f * (1.0 + regard * float(w.get("regard_bonus", 0.002)))


## Units of each good a seat takes in a visit.
static func take(_state: WorldState) -> int:
	return int(section("wants").get("take", 40))


## Days a cart takes to a seat, each way.
static func cart_days(state: WorldState, house_id: int) -> int:
	var h := state.realm.get_house(house_id)
	return ceili(int(h.get("days", 2)) * float(section("cart").get("slowness", 1.5)))


## What a load would fetch at the seat now (before the road's dangers).
static func estimate(state: WorldState, house_id: int, load: Dictionary) -> int:
	var total := 0.0
	for g: String in load:
		total += mini(int(load[g]), take(state)) * seat_price(state, house_id, g)
	return roundi(total)


# --- The road -----------------------------------------------------------------------------------

## The camps a cart to this seat passes near, and the chance of being
## waylaid on each leg: {chance, camps: [camp]}. `known_only`: as far as
## you know (the panel); the road itself doesn't care.
static func danger(state: WorldState, house_id: int, known_only: bool = false) -> Dictionary:
	var a := section("ambush")
	var h := state.realm.get_house(house_id)
	var out := {"chance": 0.0, "camps": []}
	if h.is_empty() or not h.has("pos"):
		return out
	var from := Realm.center()
	var to := Realm.pos_of(h)
	var men := 0
	for camp: Dictionary in state.military.camps:
		if known_only and not bool(camp.get("known", true)):
			continue
		var p := Realm.pos_of(camp)
		var near := Geometry2D.get_closest_point_to_segment(p, from, to)
		if Realm.ride_days(p, near) <= float(a.get("reach_days", 1.0)):
			out["camps"].append(camp)
			men += int(camp["men"])
	out["chance"] = minf(float(a.get("max_chance", 0.6)), men * float(a.get("chance_per_man", 0.04)))
	return out


## Who may drive a cart: village folk of the carting trades, of age, at
## home; those whose work is missed least first.
static func carters(state: WorldState) -> Array[CharacterData]:
	var c := section("cart")
	var trades: Array = c.get("carters", ["laborer"])
	var ages: Array = c.get("carter_age", [16, 55])
	var out: Array[CharacterData] = []
	for p in state.characters:
		if not trades.has(p.occupation_id) or p.retainer or p.is_away() or p.is_visitor() or state.is_player(p):
			continue
		if p.age < int(ages[0]) or p.age > int(ages[1]) or Military.wounded(state, p):
			continue
		if TerritorySystem.builder_site(state, p) != null or CastleSystem.is_builder(state, p):
			continue
		out.append(p)
	out.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		var ia := trades.find(a.occupation_id)
		var ib := trades.find(b.occupation_id)
		return ia < ib if ia != ib else a.id < b.id)
	return out


## The warband who can ride with a cart, best fighters first: the fighting
## men, not the house's officers (a steward guarding a cart of ale isn't
## seeing to the house).
static func escorts(state: WorldState) -> Array[CharacterData]:
	var out: Array[CharacterData] = Military.riders(state).filter(func(c: CharacterData) -> bool: return c.office.is_empty())
	out.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.get_current("combat") > b.get_current("combat") if a.get_current("combat") != b.get_current("combat") else a.id < b.id)
	return out


static func on_road(state: WorldState) -> Array:
	return state.market.carts if state.market else []


## Could a cart go to this seat now? {ok, reason}
static func can_send(state: WorldState, house_id: int, load: Dictionary = {}) -> Dictionary:
	var h := state.realm.get_house(house_id) if state.realm else {}
	var c := section("cart")
	if h.is_empty():
		return {"ok": false, "reason": ""}
	if int(h["standing"]) < int(section("wants").get("min_regard", -39)):
		return {"ok": false, "reason": "House %s holds yours in contempt: they won't deal with you." % h["name"]}
	if on_road(state).any(func(x: Dictionary) -> bool: return int(x["house"]) == house_id):
		return {"ok": false, "reason": "A cart of yours is already on the road to %s." % h["seat"]}
	if on_road(state).size() >= int(c.get("max", 2)):
		return {"ok": false, "reason": "Your carts are all on the road."}
	if carters(state).is_empty():
		return {"ok": false, "reason": "No one is free to drive a cart (a labourer, farmhand, woodcutter or farmer)."}
	var units := 0
	for g: String in load:
		units += int(load[g])
		if int(load[g]) > floori(TerritorySystem.amount(state, g)):
			return {"ok": false, "reason": "You haven't %d %s in the stores." % [int(load[g]), TerritorySystem.resource_name(g).to_lower()]}
	if not load.is_empty() and units <= 0:
		return {"ok": false, "reason": "The cart is empty."}
	if units > int(c.get("load", 60)):
		return {"ok": false, "reason": "A cart carries %d at most." % int(c.get("load", 60))}
	return {"ok": true, "reason": ""}


## Sends a cart: the goods leave the stores, the carter and `escort_count`
## of the warband leave the village. {ok, text, away: [ids], cart}
static func send(state: WorldState, house_id: int, load: Dictionary, escort_count: int = 0) -> Dictionary:
	var clean := {}
	for g: String in load:
		if int(load[g]) > 0:
			clean[g] = int(load[g])
	var can := can_send(state, house_id, clean)
	if not can["ok"] or clean.is_empty():
		return {"ok": false, "text": can["reason"] if not can["ok"] else "The cart is empty.", "away": []}
	var h := state.realm.get_house(house_id)
	var m := state.market
	var days := cart_days(state, house_id)
	var carter: CharacterData = carters(state)[0]
	var escort: Array[int] = []
	for e in escorts(state).slice(0, clampi(escort_count, 0, int(section("cart").get("escort_max", 4)))):
		escort.append(e.id)
	for g: String in clean:
		TerritorySystem.add(state, g, -float(clean[g]))
	var cart := {"id": m.next_cart_id, "house": house_id, "load": clean, "carter": carter.id, "escort": escort,
		"set_out": state.day(), "arrive": state.day() + days, "back": state.day() + days * 2, "stage": "out",
		"gold": 0, "unsold": {}, "sold": {}, "waylaid": ""}
	m.next_cart_id += 1
	m.carts.append(cart)
	var away: Array[int] = [carter.id]
	away.append_array(escort)
	for id in away:
		var p := state.get_character(id)
		p.away_at = "cart"
		p.away_until = int(cart["back"])
	var what := _goods_text(clean)
	state.house.log_event(state.day(), "A cart set out for %s with %s." % [h["seat"], what], "office")
	return {"ok": true, "away": away, "cart": cart,
		"text": "%s drives a cart of %s to %s%s: %d days there, %d back." % [carter.first_name, what, h["seat"],
			(", %d of your warband riding with it" % escort.size()) if not escort.is_empty() else "", days, days]}


# --- The days -----------------------------------------------------------------------------------

## Once a day: carts reach their seats and sell, or come home. Events:
## {text, kind, back?: [ids], cart?}.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.market == null or state.realm == null:
		return events
	for cart: Dictionary in state.market.carts.duplicate():
		if str(cart["stage"]) == "out" and state.day() >= int(cart["arrive"]):
			_arrive(state, cart, events)
		if str(cart["stage"]) == "home" and state.day() >= int(cart["back"]):
			_home(state, cart, events)
	return events


## At the seat (if the road let it pass): what the house takes is sold.
static func _arrive(state: WorldState, cart: Dictionary, events: Array[Dictionary]) -> void:
	cart["stage"] = "home"
	var beaten := _waylay(state, cart, "out", events)
	if not str(cart["waylaid"]).is_empty():
		events.append({"text": "Word from the road to %s: %s" % [state.realm.get_house(int(cart["house"])).get("seat", "the seat"), cart["waylaid"]], "kind": "bad" if beaten else "good", "waylaid": int(cart["id"])})
	if beaten:
		cart["unsold"] = {}
		return
	var gold := 0.0
	var load: Dictionary = cart["load"]
	for g: String in load:
		var n := mini(int(load[g]), take(state))
		gold += n * seat_price(state, int(cart["house"]), g)
		cart["sold"][g] = n
		if int(load[g]) > n:
			cart["unsold"][g] = int(load[g]) - n
	cart["gold"] = roundi(gold)


## Home: the gold to the treasury, what didn't sell back to the stores,
## the carter and escort back in the village, and the house thinks better of yours.
static func _home(state: WorldState, cart: Dictionary, events: Array[Dictionary]) -> void:
	var h := state.realm.get_house(int(cart["house"]))
	var seat := str(h.get("seat", "the seat"))
	# An empty cart (robbed on the way there) isn't worth waylaying.
	var worth := int(cart["gold"]) > 0 or not (cart["unsold"] as Dictionary).is_empty()
	if worth and _waylay(state, cart, "back", events):
		cart["gold"] = 0
		cart["unsold"] = {}
	state.house.gold += int(cart["gold"])
	var unsold: Dictionary = cart["unsold"]
	for g: String in unsold:
		TerritorySystem.add(state, g, float(unsold[g]))
	var back: Array[int] = []
	for id: int in [int(cart["carter"])] + Array(cart["escort"]):
		var p := state.get_character(id)
		if p and p.away_at == "cart":
			p.away_at = ""
			p.away_until = -1
			back.append(p.id)
	var sold: Dictionary = cart["sold"]
	var text := ""
	if not sold.is_empty() and int(cart["gold"]) > 0:
		var want := wants(state, int(cart["house"]))
		var parts: Array[String] = []
		for g: String in sold:
			parts.append("%d %s%s" % [int(sold[g]), TerritorySystem.resource_name(g).to_lower(), " (they wanted it)" if want.has(g) else ""])
		# Trade, not a favour: the house's rival doesn't take it amiss.
		Realm.change_regard(state, int(cart["house"]), int(section("cart").get("regard", 3)), false)
		text = "Your cart is home from %s: %s sold for %d gold.%s%s" % [seat, ", ".join(parts), int(cart["gold"]),
			(" %s came back unsold." % _goods_text(unsold)) if not unsold.is_empty() else "", " " + str(cart["waylaid"]) if not str(cart["waylaid"]).is_empty() else ""]
	else:
		text = "Your cart is home from %s with nothing to show for it. %s" % [seat, cart["waylaid"]]
	state.house.log_event(state.day(), text, "office" if int(cart["gold"]) > 0 else "bad")
	var report := {"house": int(cart["house"]), "seat": seat, "gold": int(cart["gold"]), "sold": sold.duplicate(),
		"unsold": unsold.duplicate(), "waylaid": str(cart["waylaid"]), "day": state.day()}
	state.market.last_cart = report
	state.market.carts.erase(cart)
	events.append({"text": text, "kind": "good" if int(cart["gold"]) > 0 else "bad", "back": back, "cart": report})


## A camp near the road may waylay the cart on this leg ("out" or "back"):
## the escort and the carter fight a share of the band on its own ground.
## True when the cart was beaten (its goods or gold lost).
static func _waylay(state: WorldState, cart: Dictionary, leg: String, events: Array[Dictionary]) -> bool:
	var d := danger(state, int(cart["house"]))
	if (d["camps"] as Array).is_empty():
		return false
	var rng := Seeds.counted_rng(state.world_seed, "cart_%d_%s" % [int(cart["id"]), leg])
	if rng.randf() >= float(d["chance"]):
		return false
	var camp: Dictionary = (d["camps"] as Array)[rng.randi_range(0, (d["camps"] as Array).size() - 1)]
	var band := str(camp["band"])
	var ours: Array[Dictionary] = []
	for id: int in Array(cart["escort"]) + [int(cart["carter"])]:
		var p := state.get_character(id)
		if p and not Military.wounded(state, p):
			ours.append(Military.fighter(state, p, "house"))
	if ours.is_empty():
		return _beaten(cart, leg, str(camp["band"]))
	var all := Military.camp_band(state, camp)
	var theirs: Array[Dictionary] = []
	for f in all.slice(0, maxi(2, ceili(all.size() * float(section("ambush").get("share", 0.5))))):
		theirs.append(f)
	var r := Military.resolve(ours, theirs, rng)
	var won := str(r["winner"]) == "house"
	var report := {"ours": []}
	var dead := Military._toll(state, ours, report, rng)
	var reveal := Military.reveal_camp(state, camp, "Your carters were waylaid by")
	var scattered := ""
	camp["men"] = maxi(0, int(camp["men"]) - Military.fallen(theirs))
	if int(camp["men"]) < int(Military.section("camps").get("min_men", 2)):
		scattered = " What was left of the band scattered: their camp is empty."
		Military._remove_camp(state, camp)
	var what := ("the goods" if leg == "out" else "the gold")
	var lost := 0
	if not won:
		lost = int(cart["gold"]) if leg == "back" else roundi(estimate(state, int(cart["house"]), cart["load"]) * 0.5)
		camp["hoard"] = int(camp["hoard"]) + lost
	var deaths: Array[String] = []
	for c in dead:
		deaths.append(c.first_name)
	cart["waylaid"] = _also(cart, "%s waylaid the cart on the road %s%s%s%s" % [Military._cap(band), "there" if leg == "out" else "home",
		(": the escort drove them off" if not (cart["escort"] as Array).is_empty() else ": the carter got away with the load") if won else (": %s %s lost" % [what, "were" if leg == "out" else "was"]),
		(". %s %s killed." % [" and ".join(deaths), "were" if deaths.size() > 1 else "was"]) if not deaths.is_empty() else ".", scattered])
	for c in dead:
		LifeSystem.die(state, c, "wounds taken defending a cart from %s" % band, events)
	if not reveal.is_empty():
		events.append(reveal)
	return not won


## No one fit to fight: the band takes what it likes.
static func _beaten(cart: Dictionary, leg: String, band: String) -> bool:
	cart["waylaid"] = _also(cart, "%s waylaid the cart on the road %s: with no one fit to fight, %s %s lost." % [Military._cap(band),
		"there" if leg == "out" else "home", "the goods" if leg == "out" else "the gold", "were" if leg == "out" else "was"])
	return true


## What befell the cart on the road, after what befell it before.
static func _also(cart: Dictionary, text: String) -> String:
	return (str(cart["waylaid"]) + " " + text).strip_edges()


static func _goods_text(goods: Dictionary) -> String:
	var parts: Array[String] = []
	for g: String in goods:
		parts.append("%d %s" % [int(goods[g]), TerritorySystem.resource_name(g).to_lower()])
	return ", ".join(parts)
