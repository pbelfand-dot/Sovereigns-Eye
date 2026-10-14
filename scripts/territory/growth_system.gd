class_name GrowthSystem
extends RefCounted
## Phase 3 - Territory, step 2: the village grows by itself.
##
##   appeal      food in store, happiness, renown and open jobs make the
##               village appealing; appeal fills the settler bar every day.
##   settlers    when the bar is full and a home stands empty, a family
##               arrives (CharacterGenerator.settle_family: names, looks,
##               traits, hidden talents and rumors, like everyone else) and
##               walks in from the edge of the map. Adults without a trade
##               become laborers; open jobs are filled from them first.
##   homes       when every home is lived in, the village builds a cottage
##               on the best free spot beside a main road near the square.
##   upgrades    a home whose needs are met (settled a while, food in store,
##               a content family, a chapel or tavern near...) gains a floor:
##               Cottage -> Timber House -> Townhouse. Better homes pay rent
##               and make their family happier.
## Homes and upgrades are ordinary construction sites, built by the same
## crews, and never spend the stores below a reserve. The player can switch
## them off in the Build panel.
##
## Static and deterministic, like the other systems. Numbers:
## data/territory.json "homes" and "growth".


static func homes_cfg() -> Dictionary:
	return TerritorySystem.section("homes")


static func growth_cfg() -> Dictionary:
	return TerritorySystem.section("growth")


# --- Homes -----------------------------------------------------------------------------

static func is_home(b: BuildingData) -> bool:
	return b != null and (homes_cfg().get("types", []) as Array).has(b.type)


## Homes that can go up levels (cottages; farms stay farms).
static func can_level(b: BuildingData) -> bool:
	return b != null and (homes_cfg().get("upgrade_types", []) as Array).has(b.type)


static func homes(state: WorldState) -> Array[BuildingData]:
	var out: Array[BuildingData] = []
	for b in state.layout.buildings:
		if is_home(b):
			out.append(b)
	return out


## Building id -> number of residents, in one pass over the people.
static func resident_counts(state: WorldState) -> Dictionary:
	var out := {}
	for c in state.characters:
		if c.home_building_id >= 0:
			out[c.home_building_id] = int(out.get(c.home_building_id, 0)) + 1
	return out


## Homes no one lives in (and not being rebuilt), ready for settlers.
static func empty_homes(state: WorldState) -> Array[BuildingData]:
	var counts := resident_counts(state)
	var out: Array[BuildingData] = []
	for b in homes(state):
		if int(counts.get(b.id, 0)) == 0 and state.territory.get_site(b.id) == null:
			out.append(b)
	return out


static func tiers() -> Array:
	return homes_cfg().get("tiers", [])


static func tier_def(tier: int) -> Dictionary:
	var list := tiers()
	return list[clampi(tier, 0, list.size() - 1)] if not list.is_empty() else {}


static func max_tier() -> int:
	return maxi(tiers().size() - 1, 0)


## Gold per day from lived-in homes above the first level.
static func rent(state: WorldState) -> float:
	if state == null or state.layout == null or state.territory == null:
		return 0.0
	var counts := resident_counts(state)
	var total := 0.0
	for b in homes(state):
		if b.tier > 0 and int(counts.get(b.id, 0)) > 0:
			total += float(tier_def(b.tier).get("rent", 0))
	return total


## Happiness from living in a better home (0 for a first-level home).
static func home_happiness(state: WorldState, c: CharacterData) -> float:
	if state == null or state.layout == null:
		return 0.0
	var b := state.get_building(c.home_building_id)
	if not is_home(b) or b.tier <= 0:
		return 0.0
	return float(tier_def(b.tier).get("happiness", 0))


static func settled_days(state: WorldState, b: BuildingData) -> int:
	var t := state.territory
	return state.day() - int(t.home_since.get(b.id, t.founded_day))


## Days of food left at today's consumption.
static func food_days(state: WorldState) -> float:
	var eaten := float(TerritorySystem.consumption(state).get("food", 1.0))
	return state.territory.amount("food") / maxf(eaten, 0.001)


static func _family_happiness(state: WorldState, b: BuildingData) -> float:
	var total := 0.0
	var n := 0
	for c in state.residents_of(b.id):
		total += c.happiness
		n += 1
	return total / n if n > 0 else 0.0


static func _nearest_of(state: WorldState, b: BuildingData, type: String) -> float:
	var best := INF
	for o in state.layout.buildings_of_type(type):
		best = minf(best, Vector2(o.position.x - b.position.x, o.position.z - b.position.z).length())
	return best


## What the next level of a home needs: [{label, ok, detail}]. [] at the top level.
static func home_needs(state: WorldState, b: BuildingData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not can_level(b) or b.tier >= max_tier():
		return out
	for need: Dictionary in tier_def(b.tier + 1).get("needs", []):
		var ok := false
		var detail := ""
		match str(need.get("id", "")):
			"settled":
				var d := settled_days(state, b)
				ok = d >= int(need.get("days", 0))
				detail = "%d of %d days" % [mini(d, int(need.get("days", 0))), int(need.get("days", 0))]
			"food_days":
				var fd := food_days(state)
				ok = fd >= float(need.get("days", 0))
				detail = "%d days in store" % floori(fd)
			"content":
				var h := _family_happiness(state, b)
				ok = h >= float(need.get("happiness", 50))
				detail = "now %d" % roundi(h)
			"near_any":
				var best := INF
				for type: String in need.get("types", []):
					best = minf(best, _nearest_of(state, b, type))
				ok = best <= float(need.get("radius", 60))
				detail = "nearest %d m" % roundi(best) if best < INF else "none built"
			"near_all":
				ok = true
				var parts: Array[String] = []
				for type: String in need.get("types", []):
					var d := _nearest_of(state, b, type)
					ok = ok and d <= float(need.get("radius", 60))
					parts.append("%s %s" % [str(GameData.building_type(type).get("name", type)).to_lower(), "%d m" % roundi(d) if d < INF else "none"])
				detail = ", ".join(parts)
			"market":
				var d := Vector2(b.position.x - state.layout.square_center.x, b.position.z - state.layout.square_center.z).length()
				ok = d <= float(need.get("radius", 60))
				detail = "%d m" % roundi(d)
		out.append({"label": str(need.get("label", need.get("id", ""))), "ok": ok, "detail": detail})
	return out


static func can_upgrade(state: WorldState, b: BuildingData) -> bool:
	if not can_level(b) or b.tier >= max_tier() or state.territory.get_site(b.id) != null:
		return false
	if state.residents_of(b.id).is_empty():
		return false
	for need in home_needs(state, b):
		if not need["ok"]:
			return false
	return true


## A lived-in home's name: "<family> Cottage", "<family> House", "<family> Farm".
static func rename_home(state: WorldState, b: BuildingData) -> void:
	var residents := state.residents_of(b.id)
	if residents.is_empty():
		return
	var surname := residents[0].last_name
	if b.type == "farmhouse":
		b.name = "%s Farm" % surname
	else:
		b.name = "%s %s" % [surname, "Cottage" if b.tier <= 0 else "House"]


# --- Appeal & settlers -------------------------------------------------------------------

## Why settlers want (or don't want) to come: [{label, value}].
static func appeal_factors(state: WorldState) -> Array[Dictionary]:
	var cfg: Dictionary = growth_cfg().get("appeal", {})
	var out: Array[Dictionary] = [{"label": "Land to settle", "value": float(cfg.get("base", 10))}]
	var total := 0.0
	for c in state.characters:
		total += c.happiness
	var avg := total / maxf(state.characters.size(), 1.0)
	var mood := (avg - 50.0) * float(cfg.get("happiness_weight", 0.6))
	if absf(mood) >= 0.5:
		out.append({"label": "Villagers are %s (happiness %d)" % ["content" if mood > 0.0 else "unhappy", roundi(avg)], "value": mood})
	if TerritorySystem.is_hungry(state):
		out.append({"label": "The granary is empty", "value": float(cfg.get("hungry", -40))})
	else:
		var fd := food_days(state)
		if fd >= float(cfg.get("food_days_good", 10)):
			out.append({"label": "Plenty of food (%d days)" % floori(fd), "value": float(cfg.get("food_good", 10))})
		elif fd < float(cfg.get("food_days_short", 3)):
			out.append({"label": "Food is running short", "value": float(cfg.get("food_short", -15))})
	if state.house:
		var renown := minf(state.house.renown / float(cfg.get("renown_divisor", 10)), float(cfg.get("renown_cap", 15)))
		if renown >= 0.5:
			out.append({"label": "Your house's renown", "value": renown})
		if state.house.in_debt:
			out.append({"label": "Your house can't pay its people", "value": float(cfg.get("in_debt", -10))})
	if open_jobs(state) > 0:
		out.append({"label": "Work to be had (%d open jobs)" % open_jobs(state), "value": float(cfg.get("open_jobs", 6))})
	return out


static func appeal(state: WorldState) -> float:
	var total := 0.0
	for f in appeal_factors(state):
		total += float(f["value"])
	return total


## Jobs at the player's buildings no one fills yet.
static func open_jobs(state: WorldState) -> int:
	var n := 0
	for id in state.territory.built:
		var b := state.get_building(id)
		if b == null:
			continue
		var jobs: Dictionary = TerritorySystem.buildable_def(b.type).get("jobs", {})
		for occ: String in jobs:
			var have := 0
			for c in state.workers_of(b.id):
				if c.occupation_id == occ:
					have += 1
			n += maxi(int(jobs[occ]) - have, 0)
	return n


static func population(state: WorldState) -> int:
	return state.characters.size()


static func at_capacity(state: WorldState) -> bool:
	return population(state) >= int(growth_cfg().get("max_population", 110))


## Settler bar gained per day at the current appeal.
static func progress_per_day(state: WorldState) -> float:
	if at_capacity(state):
		return 0.0
	return maxf(appeal(state), 0.0) * float(growth_cfg().get("progress_per_appeal", 2.0))


## Where newcomers step onto the map: the far end of an entry road.
static func entry_point(state: WorldState, rng: RandomNumberGenerator) -> Vector3:
	var ends: Array[Vector3] = []
	for road in state.layout.roads:
		if (growth_cfg().get("entry_roads", []) as Array).has(str(road.get("name", ""))):
			var pts: PackedVector3Array = road["points"]
			ends.append(pts[pts.size() - 1].lerp(pts[pts.size() - 2], 0.15))
	if ends.is_empty():
		return state.layout.square_center
	return ends[rng.randi_range(0, ends.size() - 1)]


## Brings a family of settlers to an empty home. Returns their FamilyData
## (null if no home is free).
static func settle(state: WorldState) -> FamilyData:
	var free := empty_homes(state)
	if free.is_empty():
		return null
	var t := state.territory
	var stream := "settlers_%d" % t.settler_families
	var rng := Seeds.rng(state.world_seed, stream + "/pick")
	var templates: Array = growth_cfg().get("settlers", [])
	var weights := {}
	for i in templates.size():
		weights[str(i)] = float((templates[i] as Dictionary).get("weight", 1.0))
	var tpl: Dictionary = templates[int(Seeds.weighted_key(rng, weights))] if not templates.is_empty() else {"background": "farming", "head": "laborer"}
	# Nearest empty home to the square first.
	free.sort_custom(func(a: BuildingData, b: BuildingData) -> bool:
		return a.position.distance_to(state.layout.square_center) < b.position.distance_to(state.layout.square_center))
	var home := free[0]
	var fam := CharacterGenerator.settle_family(state, tpl, home, stream)
	var entry := entry_point(state, rng)
	for id in fam.member_ids:
		var c := state.get_character(id)
		c.position = TerrainHeight.on_ground(entry + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)))
		c.inside_building_id = -1
		c.activity = ""
		c.activity_text = "Arriving in %s" % state.village_name
	t.settler_families += 1
	t.home_since[home.id] = state.day()
	rename_home(state, home)
	state.house.log_event(state.day(), "The %s came to settle in %s." % [fam.display_name(), state.village_name], "join")
	return fam


# --- Homes & upgrades the village orders --------------------------------------------------

static func auto_sites(state: WorldState) -> int:
	var n := 0
	for s in state.territory.sites:
		if s.kind != "build":
			n += 1
	return n


## Can the stores pay `cost` and still keep the reserve?
static func affordable_with_reserve(state: WorldState, cost: Dictionary) -> bool:
	var reserve: Dictionary = growth_cfg().get("auto", {}).get("reserve", {})
	for r: String in cost:
		if TerritorySystem.amount(state, r) - float(cost[r]) < float(reserve.get(r, 0.0)):
			return false
	return true


## Best free spot for a new home: beside a main road, as near the square as
## possible (a small seeded jitter keeps rows from looking machine-made).
static func best_home_spot(state: WorldState) -> Dictionary:
	var cfg: Dictionary = growth_cfg().get("auto", {})
	var type := str(homes_cfg().get("build_type", "cottage"))
	var lo := float(cfg.get("spot_min", 14))
	var hi := float(cfg.get("spot_max", 78))
	var step := float(cfg.get("spot_step", 4))
	var rng := Seeds.rng(state.world_seed, "home_spot_%d" % state.territory.next_building_id)
	var best := {}
	var best_score := INF
	for road in state.layout.roads:
		if str(road.get("name", "")).begins_with("lane"):
			continue
		var pts: PackedVector3Array = road["points"]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var dir := (b - a).normalized()
			var normal := Vector3(-dir.z, 0, dir.x)
			var n := ceili(a.distance_to(b) / step)
			for k in n:
				var p := a.lerp(b, float(k) / n)
				var d := Vector2(p.x - state.layout.square_center.x, p.z - state.layout.square_center.z).length()
				if d < lo or d > hi:
					continue
				for side: float in [1.0, -1.0]:
					var score := d + rng.randf() * 6.0
					if score >= best_score:
						continue
					var spot := TerritorySystem.snap(state, type, p + normal * side * 8.0)
					var check := TerritorySystem.check_placement(state, type, spot["pos"], spot["rot"])
					if check["ok"] and (check["lane"] as PackedVector3Array).is_empty():
						best_score = score
						best = {"pos": spot["pos"], "rot": spot["rot"], "check": check}
	return best


static func order_home(state: WorldState) -> ConstructionSite:
	var cfg := homes_cfg()
	var cost: Dictionary = cfg.get("build_cost", {})
	if not affordable_with_reserve(state, cost):
		return null
	var spot := best_home_spot(state)
	if spot.is_empty():
		return null
	var type := str(cfg.get("build_type", "cottage"))
	var opened := TerritorySystem.open_site(state, type, spot["pos"], spot["rot"], spot["check"], cost, float(cfg.get("build_work", 24)), "home")
	return opened["site"]


static func order_upgrade(state: WorldState, b: BuildingData) -> ConstructionSite:
	var next := tier_def(b.tier + 1)
	var cost: Dictionary = next.get("cost", {})
	if not affordable_with_reserve(state, cost):
		return null
	return TerritorySystem.open_upgrade(state, b, b.tier + 1, cost, float(next.get("work", 20)))


## Runs once per in-game day after the stores' update. Returns events:
## [{text, kind, arrived?: [character ids], site?: building id}]
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var t := state.territory
	if t == null:
		return events
	t.settler_progress = clampf(t.settler_progress + progress_per_day(state), 0.0, 100.0)
	if t.settler_progress >= 100.0 and not at_capacity(state):
		var fam := settle(state)
		if fam:
			t.settler_progress = 0.0
			var who := "The %s (%d) has" % [fam.display_name(), fam.member_ids.size()]
			if fam.member_ids.size() == 1:
				var lone := state.get_character(fam.member_ids[0])
				who = "%s, a %s, has" % [lone.full_name(), lone.occupation_name().to_lower()]
			events.append({"text": "%s come to settle in %s. New faces to appraise!" % [who, state.village_name],
				"kind": "join", "arrived": fam.member_ids.duplicate(), "building": fam.home_building_id})
			for id in t.built:
				var b := state.get_building(id)
				if b:
					events.append_array(TerritorySystem.staff(state, b, true))
	if not t.auto_homes:
		return events
	var max_sites := int(growth_cfg().get("auto", {}).get("max_sites", 2))
	# A new home when every home is taken and settlers would come.
	var building_home := false
	for s in t.sites:
		if s.kind == "home":
			building_home = true
	var needs_home := not building_home and empty_homes(state).is_empty() and not at_capacity(state) and appeal(state) > 0.0
	if needs_home and auto_sites(state) < max_sites:
		var site := order_home(state)
		if site:
			needs_home = false
			events.append({"text": "Villagers have started building a new cottage.", "kind": "info", "site": site.id()})
	# Settlers waiting for a home come first: save the materials for it.
	if needs_home and t.settler_progress >= 50.0:
		return events
	# Upgrades, nearest the square first.
	var ready: Array[BuildingData] = []
	for b in homes(state):
		if can_upgrade(state, b):
			ready.append(b)
	ready.sort_custom(func(a: BuildingData, b: BuildingData) -> bool:
		return a.position.distance_to(state.layout.square_center) < b.position.distance_to(state.layout.square_center))
	for b in ready:
		if auto_sites(state) >= max_sites:
			break
		var site := order_upgrade(state, b)
		if site:
			events.append({"text": "The %s family is adding a floor to their home." % state.residents_of(b.id)[0].last_name, "kind": "info", "site": b.id})
	return events
