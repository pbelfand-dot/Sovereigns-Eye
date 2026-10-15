class_name CharterSystem
extends RefCounted
## Charters (Phase 3.3): Hamlet -> Village -> Market Town -> Town.
##
## The settlement's charter sets how many people may live here, which
## buildings may be raised (more taverns and chapels, then the Market Hall),
## the dues it brings in, and how many retainers the house can keep. Once a
## charter's requirements are met (data/charters.json) the player petitions
## the Crown and pays the fee; the charter is granted at once.
##
## Static and deterministic. The charter itself is `TerritoryData.charter`.


static func cfg() -> Dictionary:
	return GameData.load_file("charters")


static func tiers() -> Array:
	return cfg().get("tiers", [])


static func tier_def(index: int) -> Dictionary:
	var t := tiers()
	if t.is_empty():
		return {}
	return t[clampi(index, 0, t.size() - 1)]


static func top() -> int:
	return tiers().size() - 1


## The settlement's charter (0 = Hamlet).
static func current(state: WorldState) -> int:
	return state.territory.charter if state.territory else 0


static func title(state: WorldState) -> String:
	return str(tier_def(current(state)).get("name", "Hamlet"))


static func title_of(index: int) -> String:
	return str(tier_def(index).get("name", ""))


## How many people may live here under the current charter.
static func max_population(state: WorldState) -> int:
	return int(tier_def(current(state)).get("max_population", 110))


## Gold a day: the charter's dues plus trade at every Market Hall.
static func dues(state: WorldState) -> int:
	return int(tier_def(current(state)).get("dues", 0)) + market_income(state)


## How far from the square (meters) the settlement may spread.
static func build_radius(state: WorldState) -> float:
	return float(tier_def(current(state)).get("build_radius", 80.0))


static func retainer_bonus(state: WorldState) -> int:
	return int(tier_def(current(state)).get("retainer_cap", 0))


# --- Markets ---------------------------------------------------------------------------------

static func markets(state: WorldState) -> Array[BuildingData]:
	return state.layout.buildings_of_type("market")


## Trade at the Market Halls, gold a day.
static func market_income(state: WorldState) -> int:
	var halls := markets(state)
	if halls.is_empty():
		return 0
	var m: Dictionary = cfg().get("market", {})
	var total := 0.0
	var share := GrowthSystem.population(state) / 10.0 * float(m.get("gold_per_10_people", 1.0)) / halls.size()
	for b in halls:
		var merchants := 0
		for c in state.characters:
			if c.work_building_id == b.id and c.occupation_id == "merchant":
				merchants += 1
		total += minf(merchants * float(m.get("gold_per_merchant", 3)) + share, float(m.get("max", 16)))
	return roundi(total)


## What the charter and the markets add to the settler bar.
static func appeal_factors(state: WorldState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a := float(tier_def(current(state)).get("appeal", 0))
	if a > 0.0:
		out.append({"label": "A chartered %s" % title(state).to_lower(), "value": a})
	var halls := mini(markets(state).size(), 2)
	if halls > 0:
		out.append({"label": "Market day%s" % ("s" if halls > 1 else ""), "value": halls * float(cfg().get("market", {}).get("appeal", 6))})
	return out


## What the charter and a nearby market do for one person's happiness.
static func mood_factors(state: WorldState, c: CharacterData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m: Dictionary = cfg().get("mood", {})
	var prides: Array = m.get("pride", [])
	var pride := float(prides[mini(current(state), prides.size() - 1)]) if not prides.is_empty() else 0.0
	if pride != 0.0:
		out.append({"label": "Proud of their %s" % title(state).to_lower(), "value": pride})
	var home := state.get_building(c.home_building_id)
	if home:
		var reach := float(m.get("market_radius", 80.0))
		for b in markets(state):
			if Vector2(b.position.x - home.position.x, b.position.z - home.position.z).length() <= reach:
				out.append({"label": "A market close to home", "value": float(m.get("market", 3.0))})
				break
	return out


# --- Requirements and petitions ---------------------------------------------------------------

static func _average_happiness(state: WorldState) -> float:
	var total := 0.0
	for c in state.characters:
		total += c.happiness
	return total / maxf(state.characters.size(), 1.0)


static func _homes_at(state: WorldState, tier: int) -> int:
	var n := 0
	for b in GrowthSystem.homes(state):
		if b.tier >= tier:
			n += 1
	return n


## The checklist for a charter: [{label, ok, detail}].
static func requirements(state: WorldState, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in tier_def(index).get("requires", []):
		var ok := false
		var detail := ""
		match str(r.get("id", "")):
			"population":
				var p := GrowthSystem.population(state)
				ok = p >= int(r.get("count", 0))
				detail = "%d now" % p
			"homes_tier":
				var n := _homes_at(state, int(r.get("tier", 1)))
				ok = n >= int(r.get("count", 1))
				detail = "%d now" % n
			"building":
				var n := state.layout.buildings_of_type(str(r.get("type", ""))).size()
				ok = n >= int(r.get("count", 1))
				detail = "%d now" % n
			"renown":
				var v := state.house.renown if state.house else 0
				ok = v >= int(r.get("value", 0))
				detail = "%d now" % v
			"food_days":
				var fd := GrowthSystem.food_days(state)
				ok = fd >= float(r.get("days", 0))
				detail = "%d days now" % floori(fd)
			"content":
				var h := _average_happiness(state)
				ok = h >= float(r.get("happiness", 50))
				detail = "%d now" % roundi(h)
		out.append({"label": str(r.get("label", r.get("id", ""))), "ok": ok, "detail": detail})
	return out


## Can the settlement petition for its next charter now? {ok, reason, next}
static func can_petition(state: WorldState) -> Dictionary:
	var next := current(state) + 1
	if next > top():
		return {"ok": false, "reason": "%s holds the highest charter there is." % state.village_name, "next": -1}
	var missing := 0
	for r in requirements(state, next):
		if not r["ok"]:
			missing += 1
	if missing > 0:
		return {"ok": false, "reason": "%d requirement%s still to meet." % [missing, "s" if missing != 1 else ""], "next": next}
	var cost: Dictionary = tier_def(next).get("cost", {})
	if not TerritorySystem.can_afford(state, cost):
		return {"ok": false, "reason": TerritorySystem.shortfall_text(state, cost), "next": next}
	return {"ok": true, "reason": "", "next": next}


## Petitions the Crown: pays the fee and raises the charter.
## Returns {ok, text, charter}.
static func petition(state: WorldState) -> Dictionary:
	var check := can_petition(state)
	if not check["ok"]:
		return {"ok": false, "text": str(check["reason"]), "charter": current(state)}
	var next := int(check["next"])
	var def := tier_def(next)
	TerritorySystem.pay(state, def.get("cost", {}))
	state.territory.charter = next
	if state.house:
		state.house.renown += int(def.get("renown", 0))
		state.house.standing = clampf(state.house.standing + float(cfg().get("ceremony", {}).get("standing", 5)), 0.0, 100.0)
		state.house.log_event(state.day(), "The Crown granted %s a charter as a %s." % [state.village_name, str(def.get("name", ""))], "charter")
	raise_banners(state, int(def.get("banners", 0)) - int(tier_def(next - 1).get("banners", 0)))
	var unlocked := unlocked_by(next)
	var text := "By royal charter, %s is now a %s! Room for %d people%s." % [state.village_name, str(def.get("name", "")),
		int(def.get("max_population", 0)), (", and you may now build: " + ", ".join(unlocked)) if not unlocked.is_empty() else ""]
	return {"ok": true, "text": text, "charter": next}


## Hangs `count` new banners around the square, on its edge between the
## roads, where nothing else stands. Returns how many were hung.
static func raise_banners(state: WorldState, count: int) -> int:
	var l := state.layout
	var hung := 0
	var r := l.square_radius - 0.7
	for k in 16:
		if hung >= count:
			break
		# Between the four roads: 22.5, 67.5, ... degrees, alternating sides.
		var a := deg_to_rad(22.5 + 45.0 * ((k * 3) % 8)) + (0.0 if k < 8 else deg_to_rad(11.0))
		var p := l.square_center + Vector3(cos(a), 0, sin(a)) * r
		var free := true
		for prop: Dictionary in l.props:
			if (prop["pos"] as Vector3).distance_to(p) < 1.6:
				free = false
				break
		if free and not WorldGeometry.inside_building(state, p, 1.0):
			var to := l.square_center - p
			l.props.append({"type": "banner", "pos": p, "rot": atan2(to.x, to.z)})
			hung += 1
	return hung


## Names of buildings a charter newly allows.
static func unlocked_by(index: int) -> Array[String]:
	var out: Array[String] = []
	for def: Dictionary in TerritorySystem.buildable():
		if limit_for(def, index) > 0 and limit_for(def, index - 1) <= 0:
			out.append(str(def.get("name", def.get("type", ""))))
	return out


## Names of buildings a charter allows more of.
static func raised_by(index: int) -> Array[String]:
	var out: Array[String] = []
	for def: Dictionary in TerritorySystem.buildable():
		if limit_for(def, index - 1) > 0 and limit_for(def, index) > limit_for(def, index - 1):
			out.append(str(def.get("name", def.get("type", ""))).to_lower())
	return out


## What a charter grants, in words (for the petition button's tooltip).
static func grants_text(index: int) -> String:
	var def := tier_def(index)
	var parts: Array[String] = ["room for %d people" % int(def.get("max_population", 0))]
	var unlocked := unlocked_by(index)
	if not unlocked.is_empty():
		parts.append("new buildings: " + ", ".join(unlocked))
	var raised := raised_by(index)
	if not raised.is_empty():
		parts.append("more of: " + ", ".join(raised))
	if int(def.get("dues", 0)) > 0:
		parts.append("%d gold a day in dues" % int(def.get("dues", 0)))
	if int(def.get("retainer_cap", 0)) > 0:
		parts.append("a household of %d more" % int(def.get("retainer_cap", 0)))
	if int(def.get("renown", 0)) > 0:
		parts.append("+%d renown" % int(def.get("renown", 0)))
	return ", ".join(parts)


# --- Building limits --------------------------------------------------------------------------

## How many of a buildable the player may raise under a charter. A
## "limits" list gives one number per charter; otherwise "limit" holds.
static func limit_for(def: Dictionary, index: int) -> int:
	if index < 0:
		return 0
	var limits: Array = def.get("limits", [])
	if limits.is_empty():
		return int(def.get("limit", 99))
	return int(limits[clampi(index, 0, limits.size() - 1)])


## The first charter that allows a buildable (0 if always allowed).
static func needed_for(def: Dictionary) -> int:
	for i in tiers().size():
		if limit_for(def, i) > 0:
			return i
	return top() + 1
