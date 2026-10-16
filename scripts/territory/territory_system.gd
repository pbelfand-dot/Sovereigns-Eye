class_name TerritorySystem
extends RefCounted
## Phase 3 - Territory, step 1: the village's stores and building works.
##
##   stores      food, wood and stone (gold is the house treasury). Workers
##               produce by occupation every day, everyone eats, every
##               household burns firewood; granaries raise the limits.
##   placing     the player picks a building from the Build menu; it snaps
##               beside the nearest road and faces it. A lane is laid from
##               the door to the road automatically; trees and rocks in the
##               way are cleared (and give wood and stone).
##   building    a crew of villagers (carpenters first) puts in builder-hours
##               during their work shift; the Master of Works (a court office)
##               multiplies the pace with their Administration.
##   finishing   the building joins the village, jobs are filled from
##               farmhands, tavern hands and apprentices, farms get fields.
##
## Everything is static and works on WorldState, so it runs the same in the
## game, in headless tests and on saved games. Numbers: data/territory.json.

const RESOURCES := ["food", "wood", "stone"]


static func config() -> Dictionary:
	return GameData.load_file("territory")


static func section(key: String) -> Dictionary:
	return config().get(key, {})


static func resource_defs() -> Array:
	return config().get("resources", [])


static func resource_def(resource: String) -> Dictionary:
	for r: Dictionary in resource_defs():
		if str(r["id"]) == resource:
			return r
	return {}


static func resource_name(resource: String) -> String:
	return str(resource_def(resource).get("name", resource.capitalize()))


static func buildable() -> Array:
	return config().get("buildable", [])


static func buildable_def(type: String) -> Dictionary:
	for b: Dictionary in buildable():
		if str(b["type"]) == type:
			return b
	return {}


## Menu name of a buildable type ("Stonecutter's Yard"), else the type's name.
static func display_name(type: String) -> String:
	var def := buildable_def(type)
	if def.has("name"):
		return str(def["name"])
	return str(GameData.building_type(type).get("name", type.capitalize()))


static func footprint(type: String) -> Vector2:
	var fp: Array = GameData.building_type(type).get("footprint", [6, 4])
	return Vector2(float(fp[0]), float(fp[1]))


# --- Setup ---------------------------------------------------------------------------

## Creates the village's stores for new games and for saves from before
## Phase 3. Deterministic.
static func initialize(state: WorldState) -> void:
	if state.territory != null:
		return
	var t := TerritoryData.new()
	var start := section("start")
	for r: String in RESOURCES:
		t.stock[r] = float(start.get(r, 0.0))
	var top := 0
	if state.layout:
		for b in state.layout.buildings:
			top = maxi(top, b.id)
	t.next_building_id = top + 1
	t.founded_day = state.day()
	state.territory = t


# --- Stores ----------------------------------------------------------------------------

static func amount(state: WorldState, resource: String) -> float:
	if resource == "gold":
		return float(state.house.gold) if state.house else 0.0
	return state.territory.amount(resource) if state.territory else 0.0


## Most of a resource the village can hold.
static func capacity(state: WorldState, resource: String) -> float:
	if resource == "gold":
		return INF
	var cfg := section("storage")
	var cap := float(cfg.get("base", 400))
	var per: Dictionary = cfg.get("per_building", {})
	for type: String in per:
		cap += float(per[type]) * state.layout.buildings_of_type(type).size()
	return cap


## Adds (or with a negative amount, removes) a resource, clamped to
## 0..capacity. Returns the amount actually added.
static func add(state: WorldState, resource: String, delta: float) -> float:
	if resource == "gold":
		var before := state.house.gold
		state.house.gold = maxi(state.house.gold + roundi(delta), 0)
		return float(state.house.gold - before)
	var t := state.territory
	var before_f := t.amount(resource)
	t.stock[resource] = clampf(before_f + delta, 0.0, maxf(capacity(state, resource), before_f))
	return t.amount(resource) - before_f


static func can_afford(state: WorldState, cost: Dictionary) -> bool:
	for r: String in cost:
		if amount(state, r) + 0.001 < float(cost[r]):
			return false
	return true


## "Needs 20 more stone" for what's missing, or "".
static func shortfall_text(state: WorldState, cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r: String in cost:
		var missing := ceili(float(cost[r]) - amount(state, r))
		if missing > 0:
			parts.append("%d more %s" % [missing, resource_name(r).to_lower()])
	return "" if parts.is_empty() else "Needs " + ", ".join(parts) + "."


static func pay(state: WorldState, cost: Dictionary) -> void:
	for r: String in cost:
		add(state, r, -float(cost[r]))


static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r: Dictionary in resource_defs():
		var id := str(r["id"])
		if cost.has(id):
			parts.append("%d %s" % [int(cost[id]), str(r["name"]).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "free"


# --- Production --------------------------------------------------------------------------

## Output multiplier from mood and work ethic.
static func productivity(c: CharacterData) -> float:
	var cfg := section("productivity")
	var p := lerpf(float(cfg.get("happiness_min", 0.75)), float(cfg.get("happiness_max", 1.2)), clampf(c.happiness / 100.0, 0.0, 1.0))
	var traits: Dictionary = cfg.get("traits", {})
	for t in c.traits:
		p *= float(traits.get(t, 1.0))
	return p


static func season_factor(state: WorldState, resource: String) -> float:
	var s: Dictionary = section("seasons").get(state.current_season(), {})
	return float(s.get(resource, 1.0))


## What one person adds to the stores in a day: {resource: amount}.
static func worker_output(state: WorldState, c: CharacterData) -> Dictionary:
	var out := {}
	if c.retainer or state.is_player(c) or builder_site(state, c) != null:
		return out
	var prod: Dictionary = section("production").get(c.occupation_id, {})
	if prod.is_empty():
		return out
	var p := productivity(c)
	for r: String in prod:
		out[r] = float(prod[r]) * p * season_factor(state, r)
	return out


static func production(state: WorldState) -> Dictionary:
	var out := {}
	for r: String in RESOURCES:
		out[r] = 0.0
	for c in state.characters:
		var w := worker_output(state, c)
		for r: String in w:
			out[r] = float(out.get(r, 0.0)) + float(w[r])
	return out


static func consumption(state: WorldState) -> Dictionary:
	var cfg := section("consumption")
	var food := 0.0
	for c in state.characters:
		food += float(cfg.get("food_child", 0.6)) if c.age < int(cfg.get("child_below_age", 14)) else float(cfg.get("food_adult", 1.0))
	var households := 0
	for f in state.families:
		if not f.member_ids.is_empty():
			households += 1
	return {"food": food, "wood": households * float(cfg.get("wood_per_household", 0.5)), "stone": 0.0}


## Expected change per day (before storage limits).
static func net_change(state: WorldState) -> Dictionary:
	var prod := production(state)
	var cons := consumption(state)
	var out := {}
	for r: String in RESOURCES:
		out[r] = float(prod.get(r, 0.0)) - float(cons.get(r, 0.0))
	return out


static func is_hungry(state: WorldState) -> bool:
	return state != null and state.territory != null and state.territory.amount("food") <= 0.01


## Runs once per in-game day after the court's update. Returns notification
## events: [{ "text", "kind", "character"?, "building"? }]
static func daily_update(state: WorldState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var t := state.territory
	if t == null:
		return events
	var was_hungry := is_hungry(state)
	var net := net_change(state)
	var wasted: Array[String] = []
	for r: String in RESOURCES:
		var want := float(net[r])
		var got := add(state, r, want)
		t.last_change[r] = got
		if want > 0.0 and got < want - 0.5 and t.amount(r) >= capacity(state, r) - 0.01:
			wasted.append(resource_name(r).to_lower())
	if is_hungry(state) and not was_hungry:
		events.append({"text": "The granary is empty! The village goes hungry. Build farms or ease the workload.", "kind": "bad"})
		state.house.log_event(state.day(), "The granary ran empty.", "bad")
	elif was_hungry and not is_hungry(state):
		events.append({"text": "There is food in the granary again.", "kind": "good"})
	elif not is_hungry(state) and float(net["food"]) < 0.0 and t.amount("food") < -float(net["food"]) * 5.0:
		events.append({"text": "Food is running low: about %d days left." % ceili(t.amount("food") / -float(net["food"])), "kind": "bad"})
	if not wasted.is_empty() and state.day() % 5 == 0:
		events.append({"text": "The stores are full of %s. Build a Granary to keep more." % " and ".join(wasted), "kind": "info"})
	for s in t.sites:
		refresh_crew(state, s)
	for id in t.built:
		var b := state.get_building(id)
		if b:
			events.append_array(staff(state, b, true))
	return events


# --- Building orders ------------------------------------------------------------------------

## How many of a type the player has built or ordered (limits count these only).
static func count_built(state: WorldState, type: String) -> int:
	var n := 0
	for id in state.territory.built:
		var b := state.get_building(id)
		if b and b.type == type:
			n += 1
	for s in state.territory.sites:
		if s.building.type == type:
			n += 1
	return n


## Can the player order this building now (limits, cost)? {ok, reason}
static func can_build(state: WorldState, type: String) -> Dictionary:
	var def := buildable_def(type)
	if def.is_empty():
		return {"ok": false, "reason": "That can't be built."}
	var limit := CharterSystem.limit_for(def, CharterSystem.current(state))
	if limit <= 0:
		return {"ok": false, "reason": "Needs a %s charter." % CharterSystem.title_of(CharterSystem.needed_for(def))}
	if count_built(state, type) >= limit:
		var more := ""
		if CharterSystem.current(state) < CharterSystem.top() and CharterSystem.limit_for(def, CharterSystem.top()) > limit:
			more = " A higher charter allows more."
		return {"ok": false, "reason": "You have built all %d a %s may have.%s" % [limit, CharterSystem.title(state), more]}
	var cost: Dictionary = def.get("cost", {})
	if not can_afford(state, cost):
		return {"ok": false, "reason": shortfall_text(state, cost)}
	return {"ok": true, "reason": ""}


## Where a building lands for a cursor point: beside the nearest road (or the
## square), its front facing it. `turn` rotates it by quarter turns.
## Returns {pos: Vector3, rot: float}.
static func snap(state: WorldState, type: String, cursor: Vector3, turn: int = 0) -> Dictionary:
	var cfg := section("placement")
	var fp := footprint(type)
	var pos := Vector3(cursor.x, 0, cursor.z)
	var hit := nearest_way(state.layout, pos)
	if hit.is_empty():
		return {"pos": pos, "rot": turn * PI * 0.5}
	var away: Vector3 = pos - (hit["point"] as Vector3)
	away.y = 0.0
	var n := away.normalized() if away.length() > 0.01 else Vector3(0, 0, 1)
	var rot := atan2(-n.x, -n.z) + turn * PI * 0.5
	var basis := Basis(Vector3.UP, rot)
	# How far the footprint reaches toward the road.
	var reach := absf(basis.x.dot(n)) * fp.x * 0.5 + absf(basis.z.dot(n)) * fp.y * 0.5
	var standoff := float(hit["half"]) + reach + float(cfg.get("setback", 2.6))
	if float(hit["dist"]) < standoff + float(cfg.get("road_snap", 8.0)):
		pos = (hit["point"] as Vector3) + n * standoff
	return {"pos": pos, "rot": rot}


## Nearest road or square edge to p:
## {point (on the centerline / square rim), half (half width), dist (to point), name}
static func nearest_way(layout: VillageLayout, p: Vector3) -> Dictionary:
	var best := {}
	var best_edge := INF
	var p2 := Vector2(p.x, p.z)
	for road in layout.roads:
		var pts: PackedVector3Array = road["points"]
		var half := float(road["width"]) * 0.5
		for i in range(1, pts.size()):
			var c := Geometry2D.get_closest_point_to_segment(p2, Vector2(pts[i - 1].x, pts[i - 1].z), Vector2(pts[i].x, pts[i].z))
			var d := p2.distance_to(c)
			if d - half < best_edge:
				best_edge = d - half
				best = {"point": Vector3(c.x, 0, c.y), "half": half, "dist": d, "name": str(road.get("name", ""))}
	var sq := Vector2(layout.square_center.x, layout.square_center.z)
	var from_center := p2.distance_to(sq)
	if from_center - layout.square_radius < best_edge and from_center > 0.01:
		var rim := sq + (p2 - sq).normalized() * layout.square_radius
		best = {"point": Vector3(rim.x, 0, rim.y), "half": 0.0, "dist": p2.distance_to(rim), "name": "square"}
	return best


## Distance from a point to the nearest road edge (negative = on a road).
static func road_clearance(layout: VillageLayout, p: Vector3) -> float:
	var best := INF
	var p2 := Vector2(p.x, p.z)
	for road in layout.roads:
		var pts: PackedVector3Array = road["points"]
		var half := float(road["width"]) * 0.5
		for i in range(1, pts.size()):
			var c := Geometry2D.get_closest_point_to_segment(p2, Vector2(pts[i - 1].x, pts[i - 1].z), Vector2(pts[i].x, pts[i].z))
			best = minf(best, p2.distance_to(c) - half)
	return best


## Is a building of `type` allowed at pos/rot? Returns
## {ok, reason, lane: PackedVector3Array (empty = none needed),
##  trees: [tree indices to fell], rocks: [prop indices to clear]}
static func check_placement(state: WorldState, type: String, pos: Vector3, rot: float) -> Dictionary:
	var out := {"ok": false, "reason": "", "lane": PackedVector3Array(), "trees": [], "rocks": []}
	var layout := state.layout
	var cfg := section("placement")
	var half := footprint(type) * 0.5
	var basis := Basis(Vector3.UP, rot)
	pos.y = 0.0
	if Vector2(pos.x, pos.z).length() + half.length() > layout.flat_radius - 2.0:
		out["reason"] = "Too far out: the land is too rough to build on."
		return out
	for s in _rect_grid(pos, rot, half, 5):
		if s.distance_to(layout.square_center) < layout.square_radius + float(cfg.get("square_gap", 2.0)):
			out["reason"] = "Too close to the square."
			return out
		if road_clearance(layout, s) < 0.6:
			out["reason"] = "Can't build on a road."
			return out
	var gap := float(cfg.get("building_gap", 1.5))
	for b in layout.buildings:
		if rects_overlap(pos, rot, half + Vector2(gap, gap), b.position, b.rotation, b.footprint * 0.5):
			out["reason"] = "Too close to %s." % b.name
			return out
	for site in state.territory.sites:
		var sb := site.building
		if rects_overlap(pos, rot, half + Vector2(gap, gap), sb.position, sb.rotation, sb.footprint * 0.5):
			out["reason"] = "Too close to the %s being built." % display_name(sb.type)
			return out
	var fgap := float(cfg.get("field_gap", 1.0))
	for f in layout.fields:
		if rects_overlap(pos, rot, half + Vector2(fgap, fgap), f["center"], float(f["rot"]), (f["size"] as Vector2) * 0.5):
			out["reason"] = "That's farmland."
			return out
	var pgap := float(cfg.get("prop_gap", 1.2))
	var yard_names: Dictionary = cfg.get("yard_names", {})
	for p in layout.props:
		var ptype := str(p["type"])
		if VillageLayoutGenerator.YARD_HALF.has(ptype) and yard_names.has(ptype):
			# A yard is in the way anywhere in its footprint, not just at its middle.
			if rects_overlap(pos, rot, half + Vector2(pgap, pgap), p["pos"], float(p["rot"]), VillageLayoutGenerator.YARD_HALF[ptype]):
				out["reason"] = "The %s is in the way." % str(yard_names[ptype])
				return out
		elif ptype != "rock" and point_in_rect(p["pos"], pos, rot, half, pgap):
			out["reason"] = "The %s is in the way." % ptype
			return out
	var manor_clear := float(cfg.get("manor_clear", 11.0))
	for m in layout.buildings_of_type("manor"):
		var gate := m.door_position()
		for s in _rect_grid(pos, rot, half, 3):
			if Vector2(s.x - gate.x, s.z - gate.z).length() < manor_clear:
				out["reason"] = "Keep the manor's forecourt clear."
				return out
	# The door opens onto open ground, and a lane can reach a road from it.
	var door := pos + basis * Vector3(0, 0, half.y + 1.2)
	for b in layout.buildings:
		if point_in_rect(door, b.position, b.rotation, b.footprint * 0.5, 0.4):
			out["reason"] = "The door would open into %s." % b.name
			return out
	var lane := PackedVector3Array()
	var hit := nearest_way(layout, door)
	if hit.is_empty():
		out["reason"] = "No road nearby."
		return out
	var edge := float(hit["dist"]) - float(hit["half"])
	if edge > float(cfg.get("lane_max", 28.0)):
		out["reason"] = "Too far from a road (%d m)." % roundi(edge)
		return out
	if edge > float(cfg.get("lane_min", 1.5)):
		var start: Vector3 = hit["point"]
		var end := door + basis * Vector3(0, 0, 0.5)
		lane = PackedVector3Array([start, start.lerp(end, 0.5), end])
		var steps := maxi(2, ceili(start.distance_to(end)))
		for k in steps + 1:
			var q := start.lerp(end, float(k) / steps)
			if point_in_rect(q, pos, rot, half, 0.2):
				out["reason"] = "Turn it so the door faces a road (T)."
				return out
			for b in layout.buildings:
				if point_in_rect(q, b.position, b.rotation, b.footprint * 0.5, 0.4):
					out["reason"] = "%s blocks the way to the road." % b.name
					return out
			for site in state.territory.sites:
				if point_in_rect(q, site.building.position, site.building.rotation, site.building.footprint * 0.5, 0.4):
					out["reason"] = "A building site blocks the way to the road."
					return out
			for f in layout.fields:
				if point_in_rect(q, f["center"], float(f["rot"]), (f["size"] as Vector2) * 0.5, 0.3):
					out["reason"] = "Fields block the way to the road."
					return out
			for p in layout.props:
				var ptype := str(p["type"])
				if yard_names.has(ptype) and VillageLayoutGenerator.YARD_HALF.has(ptype) \
						and point_in_rect(q, p["pos"], float(p["rot"]), VillageLayoutGenerator.YARD_HALF[ptype], 0.3):
					out["reason"] = "The %s blocks the way to the road." % str(yard_names[ptype])
					return out
	out["lane"] = lane
	# Clear trees and rocks under the building and along the lane.
	var clear := float(cfg.get("tree_clear", 1.8))
	var lane_half := float(cfg.get("lane_width", 3.0)) * 0.5
	var cleared := state.territory.cleared_trees
	for i in layout.trees.size():
		if cleared.has(i):
			continue
		var tp := Vector3(layout.trees[i].x, 0, layout.trees[i].y)
		if point_in_rect(tp, pos, rot, half, clear) or _near_polyline(tp, lane, lane_half + clear):
			(out["trees"] as Array).append(i)
	for i in layout.props.size():
		var p: Dictionary = layout.props[i]
		if str(p["type"]) == "rock" and (point_in_rect(p["pos"], pos, rot, half, 1.0) or _near_polyline(p["pos"], lane, lane_half + 1.0)):
			(out["rocks"] as Array).append(i)
	out["ok"] = true
	return out


## Orders a building: pays, lays the lane, clears the ground, opens the site
## and gathers a crew. Returns {ok, text, site?}.
static func place(state: WorldState, type: String, pos: Vector3, rot: float) -> Dictionary:
	var allowed := can_build(state, type)
	if not allowed["ok"]:
		return {"ok": false, "text": allowed["reason"]}
	var check := check_placement(state, type, pos, rot)
	if not check["ok"]:
		return {"ok": false, "text": check["reason"]}
	var def := buildable_def(type)
	var opened := open_site(state, type, pos, rot, check, def.get("cost", {}), float(def.get("work", 40)), "build")
	var site: ConstructionSite = opened["site"]
	state.house.log_event(state.day(), "Work began on %s." % site.building.name, "build")
	var text := "Work begins on the %s." % display_name(type)
	if int(opened["trees"]) > 0:
		text += " %d trees felled (+%d wood)." % [int(opened["trees"]), roundi(float(opened["wood"]))]
	if int(opened["rocks"]) > 0:
		text += " Rocks cleared (+%d stone)." % roundi(float(opened["stone"]))
	if site.builders.is_empty():
		text += " No one is free to build it yet."
	return {"ok": true, "text": text, "site": site}


## Pays for and opens a site for a new building at a checked spot: lays its
## lane, fells trees and clears rocks, gathers a crew. Returns
## {site, trees, wood, rocks, stone}.
static func open_site(state: WorldState, type: String, pos: Vector3, rot: float, check: Dictionary, cost: Dictionary, work: float, kind: String) -> Dictionary:
	var t := state.territory
	pay(state, cost)
	var b := BuildingData.new()
	b.id = t.next_building_id
	t.next_building_id += 1
	b.type = type
	b.name = _new_name(state, type) if kind == "build" else "New %s" % str(GameData.building_type(type).get("name", type.capitalize()))
	b.position = Vector3(pos.x, 0, pos.z)
	b.rotation = rot
	b.footprint = footprint(type)
	b.variant = Seeds.rng(state.world_seed, "building_%d" % b.id).randi_range(0, 7)
	var site := ConstructionSite.new()
	site.building = b
	site.kind = kind
	site.work_needed = work
	site.started_day = state.day()
	for r: String in cost:
		site.paid[r] = int(cost[r])
	var lane: PackedVector3Array = check["lane"]
	if not lane.is_empty():
		site.lane = "lane_%d" % b.id
		state.layout.roads.append({"name": site.lane, "points": lane, "width": float(section("placement").get("lane_width", 3.0))})
	var build_cfg := section("construction")
	var felled: Array = check["trees"]
	for i: int in felled:
		t.cleared_trees.append(i)
	var wood := add(state, "wood", felled.size() * float(build_cfg.get("clear_tree_wood", 3)))
	var rocks: Array = check["rocks"]
	rocks.sort()
	for k in range(rocks.size() - 1, -1, -1):
		state.layout.props.remove_at(int(rocks[k]))
	var stone := add(state, "stone", rocks.size() * float(build_cfg.get("clear_rock_stone", 5)))
	t.sites.append(site)
	refresh_crew(state, site)
	return {"site": site, "trees": felled.size(), "wood": wood, "rocks": rocks.size(), "stone": stone}


## Pays for and opens an upgrade of a lived-in home to the next level.
static func open_upgrade(state: WorldState, b: BuildingData, tier: int, cost: Dictionary, work: float) -> ConstructionSite:
	pay(state, cost)
	var site := ConstructionSite.new()
	site.building = b
	site.kind = "upgrade"
	site.target_tier = tier
	site.work_needed = work
	site.started_day = state.day()
	for r: String in cost:
		site.paid[r] = int(cost[r])
	state.territory.sites.append(site)
	refresh_crew(state, site)
	return site


## Cancels an order: refunds part of the cost and lifts the lane.
static func cancel(state: WorldState, site: ConstructionSite) -> Dictionary:
	var cfg := section("construction")
	var share := float(cfg.get("refund_unstarted", 1.0)) if site.work_done <= 0.0 else float(cfg.get("refund_started", 0.5))
	var refunded := {}
	for r: String in site.paid:
		refunded[r] = int(floor(float(site.paid[r]) * share))
		add(state, r, float(refunded[r]))
	if not site.lane.is_empty():
		for i in range(state.layout.roads.size() - 1, -1, -1):
			if str(state.layout.roads[i].get("name", "")) == site.lane:
				state.layout.roads.remove_at(i)
	state.territory.sites.erase(site)
	for s in state.territory.sites:
		refresh_crew(state, s)
	var what := "work on %s" % site.building.name if site.is_upgrade() else "the %s" % display_name(site.building.type)
	return {"ok": true, "text": "You called off %s. Refunded %s." % [what, cost_text(refunded)]}


static func _new_name(state: WorldState, type: String) -> String:
	var base := "%s %s" % [state.village_name, display_name(type)]
	var n := 0
	for b in state.layout.buildings:
		if b.name == base or b.name.begins_with(base + " "):
			n += 1
	for s in state.territory.sites:
		if s.building.name == base or s.building.name.begins_with(base + " "):
			n += 1
	return base if n == 0 else "%s %s" % [base, ["II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][mini(n - 1, 8)]]


# --- Crews & progress ------------------------------------------------------------------------

## The site a villager is building, or null.
static func builder_site(state: WorldState, c: CharacterData) -> ConstructionSite:
	if state.territory == null or c.retainer:
		return null
	for s in state.territory.sites:
		if s.builders.has(c.id):
			return s
	return null


static func can_build_with(state: WorldState, c: CharacterData) -> bool:
	var cfg := section("construction")
	return not c.retainer and not state.is_player(c) \
		and c.age >= int(cfg.get("builder_min_age", 14)) and c.age <= int(cfg.get("builder_max_age", 59)) \
		and (cfg.get("builders", {}) as Dictionary).has(c.occupation_id)


## Drops builders who can no longer work and fills the crew up again,
## carpenters first.
static func refresh_crew(state: WorldState, site: ConstructionSite) -> void:
	var kept: Array[int] = []
	for id in site.builders:
		var c := state.get_character(id)
		if c and can_build_with(state, c):
			kept.append(id)
	site.builders = kept
	var crew := int(section("construction").get("crew", 3))
	if site.builders.size() >= crew:
		return
	var rates: Dictionary = section("construction").get("builders", {})
	var pool: Array[CharacterData] = []
	for c in state.characters:
		if can_build_with(state, c) and builder_site(state, c) == null:
			pool.append(c)
	pool.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		var ra := float(rates.get(a.occupation_id, 0.0))
		var rb := float(rates.get(b.occupation_id, 0.0))
		return ra > rb if ra != rb else a.id < b.id)
	for c in pool:
		if site.builders.size() >= crew:
			break
		site.builders.append(c.id)


static func builder_rate(c: CharacterData) -> float:
	var rates: Dictionary = section("construction").get("builders", {})
	return float(rates.get(c.occupation_id, 0.0)) * productivity(c)


static func overseer(state: WorldState) -> CharacterData:
	if state.house == null:
		return null
	return state.get_character(state.house.holder_of(str(section("construction").get("overseer_office", "master_of_works"))))


## Pace multiplier from the Master of Works (1.0 without one).
static func speed_factor(state: WorldState) -> float:
	var o := overseer(state)
	if o == null:
		return 1.0
	return 1.0 + o.get_current("administration") / float(section("construction").get("overseer_divisor", 100.0))


## Is the person on shift at this hour (their schedule's "work" block)?
static func on_shift(c: CharacterData, hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	for block: Array in GameData.schedule(str(c.occupation().get("schedule", "worker"))):
		if h >= float(block[0]) and h < float(block[1]):
			return str(block[2]) == "work"
	return false


## Builder-hours per hour the site gets at this hour of day.
static func site_rate(state: WorldState, site: ConstructionSite, hour: float) -> float:
	var rate := 0.0
	for id in site.builders:
		var c := state.get_character(id)
		if c and on_shift(c, hour):
			rate += builder_rate(c)
	return rate * speed_factor(state)


## Builder-hours a site gets in a whole day (for estimates in the UI).
static func daily_rate(state: WorldState, site: ConstructionSite) -> float:
	var total := 0.0
	for h in 24:
		total += site_rate(state, site, h + 0.5)
	return total


## Days left at today's pace (INF without a crew).
static func days_left(state: WorldState, site: ConstructionSite) -> float:
	var per_day := daily_rate(state, site)
	return INF if per_day <= 0.0 else (site.work_needed - site.work_done) / per_day


## Puts in the work for `game_minutes` at the current clock. Returns the
## sites that are now finished (call complete() on each).
static func advance(state: WorldState, game_minutes: float) -> Array[ConstructionSite]:
	var done: Array[ConstructionSite] = []
	if state.territory == null or game_minutes <= 0.0:
		return done
	var hour := Calendar.hour_f(state.minutes)
	for s in state.territory.sites:
		s.work_done = minf(s.work_done + site_rate(state, s, hour) * game_minutes / 60.0, s.work_needed)
		if s.is_done():
			done.append(s)
	return done


## A spot beside the site where builder `slot` works, and the point they face.
static func work_spot(site: ConstructionSite, slot: int) -> Vector3:
	var b := site.building
	var h := b.footprint * 0.5
	var spots := [Vector3(-h.x - 1.0, 0, h.y * 0.3), Vector3(h.x + 1.0, 0, -h.y * 0.2), Vector3(h.x * 0.3, 0, h.y + 1.3),
		Vector3(-h.x * 0.4, 0, -h.y - 1.0), Vector3(-h.x * 0.5, 0, h.y + 1.3), Vector3(h.x + 1.0, 0, h.y * 0.6)]
	return b.position + b.basis() * (spots[posmod(slot, spots.size())] as Vector3)


# --- Completion ------------------------------------------------------------------------------

## Turns a finished site into a real building: it joins the layout, farms
## get fields, jobs are filled. Returns notification events.
static func complete(state: WorldState, site: ConstructionSite) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var t := state.territory
	if not t.sites.has(site):
		return events
	t.sites.erase(site)
	if site.is_upgrade():
		var home := state.get_building(site.id())
		if home:
			home.tier = maxi(home.tier, site.target_tier)
			GrowthSystem.rename_home(state, home)
			t.home_since[home.id] = state.day()
			state.house.log_event(state.day(), "%s became a %s." % [home.name, home.type_name()], "build")
			events.append({"text": "%s is now a %s." % [home.name, home.type_name()], "kind": "good", "building": home.id})
		for s in t.sites:
			refresh_crew(state, s)
		return events
	var b := site.building
	state.layout.add_building(b)
	if site.kind == "home":
		b.name = "Empty %s" % b.type_name()
		events.append({"text": "A new %s stands ready for settlers." % b.type_name().to_lower(), "kind": "good", "building": b.id})
		for s in t.sites:
			refresh_crew(state, s)
		return events
	t.built.append(b.id)
	var def := buildable_def(b.type)
	var fields: Array = def.get("fields", [])
	if fields.size() == 2:
		place_fields(state, b, Seeds.rng(state.world_seed, "fields_%d" % b.id).randi_range(int(fields[0]), int(fields[1])))
	if b.type == "chapel":
		add_churchyard(state, b)
	state.house.log_event(state.day(), "%s was finished." % b.name, "build")
	events.append({"text": "The %s is finished!" % display_name(b.type), "kind": "good", "building": b.id})
	events.append_array(staff(state, b, false))
	# The freed crew can help on other sites straight away.
	for s in t.sites:
		refresh_crew(state, s)
	return events


## A new chapel's churchyard at its east end (or beside the nave), clear of
## the buildings still going up and of trees (3D/props/chapel-grounds).
## Returns whether one fitted.
static func add_churchyard(state: WorldState, b: BuildingData) -> bool:
	var avoid := []
	for s in state.territory.sites:
		avoid.append({"center": s.building.position, "rot": s.building.rotation, "half": s.building.footprint * 0.5})
	var cleared := state.territory.cleared_trees
	var layout := state.layout
	# Felled trees don't count: only the ones still standing block it.
	var standing := layout.trees.duplicate()
	for i in range(standing.size() - 1, -1, -1):
		if cleared.has(i):
			standing.remove_at(i)
	var kept := layout.trees
	layout.trees = standing
	var yard := VillageLayoutGenerator.churchyard(layout, b, false, avoid)
	layout.trees = kept
	if yard.is_empty():
		return false
	layout.props.append({"type": yard["type"], "pos": yard["pos"], "rot": yard["rot"]})
	return true


## Fills a building's open jobs from the hiring pool. `quiet` skips the
## "no one is free" notice (daily retries).
static func staff(state: WorldState, b: BuildingData, quiet: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var jobs: Dictionary = buildable_def(b.type).get("jobs", {})
	if jobs.is_empty():
		return events
	var cfg := section("hiring")
	var prefer: Array = cfg.get("from", [])
	for occ: String in jobs:
		var have := 0
		for c in state.workers_of(b.id):
			if c.occupation_id == occ:
				have += 1
		var need := int(jobs[occ]) - have
		if need <= 0:
			continue
		var pool: Array[CharacterData] = []
		for c in state.characters:
			if c.retainer or state.is_player(c) or not prefer.has(c.occupation_id):
				continue
			if c.age < int(cfg.get("min_age", 16)) or c.age > int(cfg.get("max_age", 59)):
				continue
			if c.occupation_id == occ and c.work_building_id == b.id:
				continue
			pool.append(c)
		pool.sort_custom(func(x: CharacterData, y: CharacterData) -> bool:
			var px := prefer.find(x.occupation_id)
			var py := prefer.find(y.occupation_id)
			return px < py if px != py else x.id < y.id)
		for c: CharacterData in pool.slice(0, need):
			var old := c.occupation_name()
			var same := c.occupation_id == occ
			c.occupation_id = occ
			c.work_building_id = b.id
			var text := ""
			if same:
				text = "%s moves to work as a %s at the %s." % [c.full_name(), c.occupation_name().to_lower(), display_name(b.type)]
				c.add_history(state.current_year(), state.current_season(), "career", "Moved to work at %s" % b.name)
			else:
				text = "%s leaves work as a %s to become a %s at the %s." % [c.full_name(), old.to_lower(), c.occupation_name().to_lower(), display_name(b.type)]
				c.add_history(state.current_year(), state.current_season(), "career", "Left work as a %s to become a %s at %s" % [old, c.occupation_name(), b.name])
			events.append({"text": text, "kind": "info", "character": c.id, "hired": c.id})
			need -= 1
		if need > 0 and not quiet:
			events.append({"text": "No one is free to work at the %s yet (%d %s wanted)." % [display_name(b.type), need, GameData.occupation(occ).get("name", occ).to_lower()], "kind": "bad"})
	return events


## Lays out up to `count` fields behind and beside a new farmhouse.
static func place_fields(state: WorldState, farm: BuildingData, count: int) -> int:
	var rng := Seeds.rng(state.world_seed, "fields_layout_%d" % farm.id)
	var layout := state.layout
	var basis := farm.basis()
	var fp := farm.footprint
	var dirs := [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, -2)]
	var placed := 0
	for attempt in 48:
		if placed >= count:
			break
		var dir: Vector3 = dirs[attempt % dirs.size()]
		var size := Vector2(rng.randf_range(10, 16), rng.randf_range(8, 12))
		var reach := Vector3(
			dir.x * (fp.x * 0.5 + size.x * 0.5 + rng.randf_range(2.0, 5.0)),
			0,
			dir.z * (fp.y * 0.5 + size.y * 0.5 + rng.randf_range(2.0, 4.0)) + rng.randf_range(-3.0, 3.0) * (1.0 - absf(dir.z)))
		var center := farm.position + basis * reach
		if _field_fits(state, center, farm.rotation, size * 0.5):
			layout.fields.append({"center": center, "size": size, "rot": farm.rotation, "crop": Seeds.pick(rng, VillageLayoutGenerator.CROPS), "building": farm.id})
			placed += 1
	return placed


static func _field_fits(state: WorldState, center: Vector3, rot: float, half: Vector2) -> bool:
	var layout := state.layout
	if Vector2(center.x, center.z).length() + half.length() > layout.flat_radius - 2.0:
		return false
	for s in _rect_grid(center, rot, half, 4):
		if s.distance_to(layout.square_center) < layout.square_radius + 2.0 or road_clearance(layout, s) < 1.0:
			return false
	for b in layout.buildings:
		if rects_overlap(center, rot, half + Vector2(1.5, 1.5), b.position, b.rotation, b.footprint * 0.5):
			return false
	for s in state.territory.sites:
		if rects_overlap(center, rot, half + Vector2(1.5, 1.5), s.building.position, s.building.rotation, s.building.footprint * 0.5):
			return false
	for f in layout.fields:
		if rects_overlap(center, rot, half + Vector2(0.8, 0.8), f["center"], float(f["rot"]), (f["size"] as Vector2) * 0.5):
			return false
	for p in layout.props:
		if point_in_rect(p["pos"], center, rot, half, 1.0):
			return false
	return true


## A free spot for a building of `type` beside a road (tries roads in order,
## nearest the center first). Used by tests and tools; {} if none.
static func find_spot(state: WorldState, type: String, min_dist: float = 15.0, max_dist: float = -1.0) -> Dictionary:
	if max_dist < 0.0:
		max_dist = CharterSystem.build_radius(state)
	for road in state.layout.roads:
		var pts: PackedVector3Array = road["points"]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var normal := Vector3(-(b - a).normalized().z, 0, (b - a).normalized().x)
			var steps := ceili(a.distance_to(b) / 3.0)
			for s in steps:
				var p := a.lerp(b, float(s) / steps)
				if p.length() < min_dist or p.length() > max_dist:
					continue
				for side: float in [1.0, -1.0]:
					var spot := snap(state, type, p + normal * side * 8.0)
					if check_placement(state, type, spot["pos"], spot["rot"])["ok"]:
						return spot
	return {}


# --- Geometry --------------------------------------------------------------------------------

## Oriented rectangles (center, yaw, half size) overlap? Separating axes.
static func rects_overlap(c1: Vector3, r1: float, h1: Vector2, c2: Vector3, r2: float, h2: Vector2) -> bool:
	var a := Basis(Vector3.UP, r1)
	var b := Basis(Vector3.UP, r2)
	var d := c2 - c1
	d.y = 0.0
	for axis: Vector3 in [a.x, a.z, b.x, b.z]:
		var p1 := absf(a.x.dot(axis)) * h1.x + absf(a.z.dot(axis)) * h1.y
		var p2 := absf(b.x.dot(axis)) * h2.x + absf(b.z.dot(axis)) * h2.y
		if absf(d.dot(axis)) > p1 + p2:
			return false
	return true


static func point_in_rect(p: Vector3, center: Vector3, rot: float, half: Vector2, margin: float) -> bool:
	var local := Basis(Vector3.UP, rot).inverse() * (p - center)
	return absf(local.x) < half.x + margin and absf(local.z) < half.y + margin


static func _rect_grid(center: Vector3, rot: float, half: Vector2, n: int) -> Array[Vector3]:
	var basis := Basis(Vector3.UP, rot)
	var out: Array[Vector3] = []
	for ix in n:
		for iz in n:
			var local := Vector3(lerpf(-half.x, half.x, float(ix) / (n - 1)), 0, lerpf(-half.y, half.y, float(iz) / (n - 1)))
			out.append(center + basis * local)
	return out


static func _near_polyline(p: Vector3, line: PackedVector3Array, radius: float) -> bool:
	var p2 := Vector2(p.x, p.z)
	for i in range(1, line.size()):
		var c := Geometry2D.get_closest_point_to_segment(p2, Vector2(line[i - 1].x, line[i - 1].z), Vector2(line[i].x, line[i].z))
		if p2.distance_to(c) < radius:
			return true
	return false
