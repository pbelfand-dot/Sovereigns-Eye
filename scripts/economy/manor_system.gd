class_name ManorSystem
extends RefCounted
## Phase 6.3: the manor's dues and the Crown's levies.
##
## The mill: the village's windmill is the lord's; with a miller at work its
## toll on the village's bread comes in each day (CourtSystem.daily_income),
## lighter or harder as the Court sets it, less what's ground at home on
## hand-querns when the village is unhappy, unless the querns are seized.
## The fair: a Market Town may buy one from the Crown; three days a year on
## its saint's feast the market trades more on better terms, wares fetch
## more, the lord takes stallage, and the village is merrier. The Crown:
## levies on the house's movables (its gold and its stores), from the
## Saladin tithe of 1188 on, assessed by sworn neighbours who may tell if
## the house hides some.
##
## Static and deterministic. Numbers: data/manor.json. State: ManorData.


static func cfg() -> Dictionary:
	return GameData.load_file("manor")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {})


static func day_of_year(state: WorldState) -> int:
	return posmod(state.day(), Calendar.days_per_year())


## The absolute day of a day of the year in a year.
static func day_in(year: int, doy: int) -> int:
	return (year - Calendar.start_year()) * Calendar.days_per_year() + doy


static func village_happiness(state: WorldState) -> float:
	return CharterSystem._average_happiness(state)


# --- The mill -------------------------------------------------------------------------------------

static func toll_def(state: WorldState) -> Dictionary:
	var tolls: Dictionary = section("mill").get("tolls", {})
	return tolls.get(state.manor.toll if state.manor else "customary", tolls.get("customary", {}))


static func mill(state: WorldState) -> BuildingData:
	if state.layout == null:
		return null
	var mills := state.layout.buildings_of_type("mill")
	return mills[0] if not mills.is_empty() else null


## The miller at work at the lord's mill, or null.
static func miller(state: WorldState) -> CharacterData:
	var m := mill(state)
	if m == null:
		return null
	for c in state.characters:
		if c.occupation_id == "miller" and c.work_building_id == m.id and not c.is_away() and not c.retainer:
			return c
	return null


## The share of the village's grain ground at home on hand-querns (paying
## nothing): more the unhappier the village, none while they're seized.
static func querns_share(state: WorldState) -> float:
	if state.manor and state.manor.querns_seized_until > state.day():
		return 0.0
	var m := section("mill")
	var under := float(toll_def(state).get("querns_below", 42)) - village_happiness(state)
	return clampf(under * float(m.get("querns_per_point", 0.025)), 0.0, float(m.get("querns_max", 0.6)))


## Gold a day from the mill's toll.
static func mill_income(state: WorldState) -> float:
	if miller(state) == null or state.territory == null:
		return 0.0
	var m := section("mill")
	return GrowthSystem.population(state) * float(m.get("per_head", 0.06)) * float(toll_def(state).get("share", 1.0)) * (1.0 - querns_share(state))


static func set_toll(state: WorldState, toll_id: String) -> Dictionary:
	var tolls: Dictionary = section("mill").get("tolls", {})
	if not tolls.has(toll_id):
		return {"ok": false, "text": ""}
	state.manor.toll = toll_id
	var t: Dictionary = tolls[toll_id]
	state.house.log_event(state.day(), "The mill's toll is set at %s." % t["name"], "office")
	return {"ok": true, "text": "The miller will take %s of the grain he grinds." % t["name"]}


## The lord's men break the hand-querns: the toll is paid in full a season,
## and the village resents it as long.
static func seize_querns(state: WorldState) -> Dictionary:
	if miller(state) == null:
		return {"ok": false, "text": "The mill has no miller: there's no toll to keep."}
	if state.manor.querns_seized_until > state.day():
		return {"ok": false, "text": "The querns were seized lately."}
	var m := section("mill")
	state.manor.querns_seized_until = state.day() + int(m.get("seize_days", 10))
	state.house.log_event(state.day(), "The hand-querns in the village were seized and broken.", "bad")
	return {"ok": true, "text": "Your men go from house to house breaking the querns. The grain comes to the mill, and the village mutters."}


# --- The fair ------------------------------------------------------------------------------------

static func feast(state: WorldState) -> Dictionary:
	var feasts: Array = section("fair").get("feasts", [])
	if state.manor == null or state.manor.fair_feast < 0 or state.manor.fair_feast >= feasts.size():
		return {}
	return feasts[state.manor.fair_feast]


static func can_grant_fair(state: WorldState) -> Dictionary:
	var f := section("fair")
	if state.manor.fair_granted:
		return {"ok": false, "reason": "Your house holds its fair already."}
	if CharterSystem.current(state) < int(f.get("min_charter", 2)):
		return {"ok": false, "reason": "Only a Market Town may hold a fair."}
	if Market.halls(state) <= 0:
		return {"ok": false, "reason": "A fair needs a Market Hall."}
	if state.house.gold < int(f.get("fee", 400)):
		return {"ok": false, "reason": "The Crown asks %d gold for the grant." % int(f.get("fee", 400))}
	return {"ok": true, "reason": ""}


## Buys a fair from the Crown, on a saint's feast drawn from the seed.
static func grant_fair(state: WorldState) -> Dictionary:
	var can := can_grant_fair(state)
	if not can["ok"]:
		return {"ok": false, "text": can["reason"]}
	var f := section("fair")
	state.house.gold -= int(f.get("fee", 400))
	state.manor.fair_granted = true
	state.manor.fair_feast = Seeds.rng(state.world_seed, "fair_feast").randi_range(0, (f.get("feasts", []) as Array).size() - 1)
	var fe := feast(state)
	state.house.log_event(state.day(), "The Crown granted the house a fair on %s's feast." % fe["name"], "office")
	return {"ok": true, "text": "The Crown grants your house a fair of %d days from the feast of %s, each year (%d gold)." % [
		int(f.get("days", 3)), fe["name"], int(f.get("fee", 400))]}


## Days into the fair (0 its first), or -1 when it isn't on.
static func fair_day(state: WorldState) -> int:
	var fe := feast(state)
	if fe.is_empty():
		return -1
	var d := day_of_year(state) - int(fe["day"])
	return d if d >= 0 and d < int(section("fair").get("days", 3)) else -1


static func fair_on(state: WorldState) -> bool:
	return state.manor != null and fair_day(state) >= 0


## The first day of the next fair (absolute), or -1.
static func next_fair(state: WorldState) -> int:
	var fe := feast(state)
	if fe.is_empty():
		return -1
	var start := day_in(state.current_year(), int(fe["day"]))
	if state.day() >= start + int(section("fair").get("days", 3)):
		start = day_in(state.current_year() + 1, int(fe["day"]))
	return start


## Stallage and tolls a day while the fair is on.
static func fair_income(state: WorldState) -> float:
	if not fair_on(state):
		return 0.0
	var f := section("fair")
	return float(f.get("stallage", 30)) + GrowthSystem.population(state) * float(f.get("per_head", 0.25)) + state.house.renown * float(f.get("per_renown", 0.1))


## What the fair does to the market: {volume, spread, wares_price} (1, 0, 1 when it's off).
static func fair_market(state: WorldState) -> Dictionary:
	if not fair_on(state):
		return {"volume": 1.0, "spread": 0.0, "wares_price": 1.0}
	var f := section("fair")
	return {"volume": float(f.get("volume", 4.0)), "spread": float(f.get("spread", 0.1)), "wares_price": float(f.get("wares_price", 1.25))}


# --- The Crown --------------------------------------------------------------------------------------

## The levy in a year, or {}: {year, day (absolute), name, why, share | per_home}.
static func levy_in(state: WorldState, year: int) -> Dictionary:
	var c := section("crown")
	var history: Array = c.get("history", [])
	var last := Calendar.start_year()
	for l: Dictionary in history:
		last = maxi(last, int(l["year"]))
		if int(l["year"]) == year:
			var out := l.duplicate()
			out["day"] = day_in(year, int(l.get("day", 8)))
			return out
	if year <= last:
		return {}
	# After the chronicle: one every few years, from the seed.
	var every: Array = c.get("every", [3, 6])
	var y := last
	while y < year:
		y += Seeds.counted_rng(state.world_seed, "levy_after_%d" % y).randi_range(int(every[0]), int(every[1]))
	if y != year:
		return {}
	var rng := Seeds.counted_rng(state.world_seed, "levy_%d" % year)
	return {"year": year, "day": day_in(year, rng.randi_range(5, Calendar.days_per_year() - 5)), "name": str(c.get("later_name", "the King's levy")),
		"why": str(c.get("later_why", "")), "share": float(Seeds.pick(rng, c.get("shares", [0.1])))}


## The next levy not yet assessed (within twenty years), or {}.
static func next_levy(state: WorldState) -> Dictionary:
	for y in range(state.current_year(), state.current_year() + 20):
		var l := levy_in(state, y)
		if not l.is_empty() and int(l["day"]) >= state.day() and not state.manor.assessed.has(int(l["day"])):
			return l
	return {}


## The house's movable wealth: its gold and its stores at their going price.
static func movables(state: WorldState) -> int:
	var total := float(maxi(0, state.house.gold))
	if state.territory:
		for r: String in TerritorySystem.RESOURCES:
			total += TerritorySystem.amount(state, r) * Market.fair_price(state, r)
	return roundi(total)


## What a levy asks, declaring everything.
static func levy_due(state: WorldState, levy: Dictionary) -> int:
	if levy.has("per_home"):
		return int(levy["per_home"]) * GrowthSystem.homes(state).size()
	return roundi(float(levy.get("share", 0.0)) * movables(state))


## The chance the sworn neighbours tell, if the house hides some.
static func exposed_chance(state: WorldState) -> float:
	var c := section("crown")
	var unhappy := maxf(0.0, 50.0 - village_happiness(state))
	return clampf(float(c.get("exposed_base", 0.2)) + unhappy * float(c.get("exposed_per_unhappy", 0.02)), 0.0, float(c.get("exposed_max", 0.8)))


## Declare everything (0) or hide the data's share (the next assessment).
static func set_hiding(state: WorldState, hiding: bool) -> void:
	state.manor.hide = float(section("crown").get("hide", 0.33)) if hiding else 0.0


## The assessment: the levy is taken (gold, then stores at their price);
## hidden movables may be told of. Event {text, kind, levy}.
static func assess(state: WorldState, levy: Dictionary) -> Dictionary:
	var c := section("crown")
	var m := state.manor
	var full := levy_due(state, levy)
	var hidden := m.hide if levy.has("share") else 0.0
	var due := roundi(full * (1.0 - hidden))
	var exposed := false
	if hidden > 0.0 and Seeds.counted_rng(state.world_seed, "levy_told_%d" % int(levy["day"])).randf() < exposed_chance(state):
		exposed = true
		due = full + roundi(full * hidden * float(c.get("fine", 2.0)))
		state.house.renown = maxi(0, state.house.renown + int(c.get("exposed_renown", -10)))
	var paid := mini(due, maxi(0, state.house.gold))
	state.house.gold -= paid
	# Short of gold: the sheriff takes stores at their price.
	if paid < due and state.territory:
		for r: String in TerritorySystem.RESOURCES:
			if paid >= due:
				break
			var price := maxf(0.01, Market.fair_price(state, r))
			var units := minf(TerritorySystem.amount(state, r), ceilf((due - paid) / price))
			if units > 0.0:
				TerritorySystem.add(state, r, -units)
				paid += roundi(units * price)
	var short := maxi(0, due - paid)
	if short > 0:
		state.house.renown = maxi(0, state.house.renown + int(c.get("unpaid_renown", -15)))
	m.assessed.append(int(levy["day"]))
	m.levies.append({"day": int(levy["day"]), "year": int(levy["year"]), "name": str(levy["name"]), "due": due, "paid": mini(paid, due),
		"hidden": hidden, "exposed": exposed})
	while m.levies.size() > 12:
		m.levies.pop_front()
	m.hide = 0.0
	var text := ""
	if exposed:
		text = "%s: your neighbours, sworn, told the King's men what your house had hidden. You pay it all and a fine besides: %d gold." % [Military._cap(str(levy["name"])), due]
	elif hidden > 0.0:
		text = "%s: your neighbours held their tongues. You paid %d gold on what you declared (%d hidden)." % [Military._cap(str(levy["name"])), due, full - due]
	else:
		text = "%s is assessed and paid: %d gold to the Crown." % [Military._cap(str(levy["name"])), due]
	if short > 0:
		text += " The sheriff took what stores he could; %d gold went unpaid, and the King will remember it." % short
	state.house.log_event(state.day(), text, "bad" if exposed or short > 0 else "office")
	return {"text": text, "kind": "bad" if exposed or short > 0 else "info", "levy": m.levies[-1]}


# --- The days ---------------------------------------------------------------------------------------

## Once a day (after the Court's income): a levy announced or assessed, the
## fair coming or opening. Events {text, kind}.
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.manor == null or state.house == null:
		return events
	var c := section("crown")
	var levy := next_levy(state)
	if not levy.is_empty():
		var notice := int(levy["day"]) - int(c.get("notice_days", 10))
		if state.day() == notice:
			var what := ("%d gold a home" % int(levy["per_home"])) if levy.has("per_home") else ("%s of your movables, your gold and your stores (about %d gold)" % [_share_text(float(levy["share"])), levy_due(state, levy)])
			var text := "The King's officers are coming: %s, %s. They assess it on %s: %s." % [levy["name"], levy["why"],
				Calendar.format_date(int(levy["day"]) * Calendar.MINUTES_PER_DAY), what]
			state.house.log_event(state.day(), "The Crown announced %s." % levy["name"], "office")
			events.append({"text": text, "kind": "bad", "levy_notice": true})
		elif state.day() == int(levy["day"]):
			events.append(assess(state, levy))
	var fe := feast(state)
	if not fe.is_empty():
		var f := section("fair")
		var start := day_in(state.current_year(), int(fe["day"]))
		if state.day() == start - 3:
			events.append({"text": "In three days the fair of %s opens: merchants are on the roads." % fe["name"], "kind": "info"})
		elif state.day() == start and state.manor.fair_held_year != state.current_year():
			state.manor.fair_held_year = state.current_year()
			state.house.renown += int(f.get("renown", 8))
			state.house.log_event(state.day(), "The fair of %s was held." % fe["name"], "office")
			events.append({"text": "The fair of %s opens! Stalls fill the square for %d days: the market trades more on better terms, wares fetch more, and the stallage is yours." % [
				fe["name"], int(f.get("days", 3))], "kind": "good", "fair": true})
	return events


## What the manor does to one villager's happiness.
static func mood_factors(state: WorldState, c: CharacterData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.manor == null or c.retainer or state.is_player(c) or CourtSystem.is_kin(state, c):
		return out
	var t := toll_def(state)
	if float(t.get("happiness", 0)) != 0.0 and miller(state) != null:
		out.append({"label": str(t.get("label", "The mill's toll")), "value": float(t["happiness"])})
	if state.manor.querns_seized_until > state.day():
		out.append({"label": str(section("mill").get("seize_label", "Querns seized")), "value": float(section("mill").get("seize_happiness", -6))})
	var fe := feast(state)
	if not fe.is_empty():
		var f := section("fair")
		var since := day_of_year(state) - int(fe["day"])
		if since >= 0 and since < int(f.get("days", 3)) + int(f.get("after_days", 4)):
			out.append({"label": str(f.get("label", "The fair")), "value": float(f.get("happiness", 6))})
	return out


static func _share_text(share: float) -> String:
	var n := roundi(1.0 / maxf(share, 0.001))
	return {2: "a half", 3: "a third", 4: "a quarter"}.get(n, "a %s" % _ordinal(n))


static func _ordinal(n: int) -> String:
	var names := {5: "fifth", 7: "seventh", 10: "tenth", 13: "thirteenth", 15: "fifteenth", 20: "twentieth", 30: "thirtieth", 40: "fortieth"}
	return str(names.get(n, "%dth" % n))
