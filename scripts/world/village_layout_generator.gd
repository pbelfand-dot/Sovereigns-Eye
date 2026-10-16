class_name VillageLayoutGenerator
extends RefCounted
## Deterministically lays out a small medieval village from a seed.
##
## Structure: a round town square, four roads leaving it (the north road leads
## up to the manor), farms with lanes and fields on the outskirts, buildings
## facing the roads, and forest growing thicker away from the center.
## The output is a VillageLayout (pure data).

const SQUARE_BUILDINGS := ["tavern", "chapel", "bakery", "smithy"]
const CROPS := ["wheat", "barley", "cabbage", "flax", "turnip"]
## Half-extents (m) kept clear for the big yard props: any haystack model
## turned any way (up to 2.1 m across), and the log pile (2.5 x 1.8 m).
const YARD_HALF := {"haystack": Vector2(1.15, 1.15), "lumber": Vector2(1.3, 1.3), "forge": Vector2(2.4, 1.35),
	"training": Vector2(5.5, 3.25), "training_small": Vector2(3.5, 2.0)}
## How far a training yard keeps from the barracks' wall (m), nearest first.
const TRAINING_SETBACKS := [1.2, 2.5, 4.0]
## The forge yard's centre from the smithy's wall (m): its forge backs onto the wall.
const FORGE_SETBACK := 1.27
## Where the market cross stands (x the square's radius from its centre) and
## how far the trough stands from the well (m).
const CROSS_AT := 0.42
const TROUGH_AT := 2.7

var rng: RandomNumberGenerator
var layout: VillageLayout
var _next_id := 1
## Occupied rectangles: [{ "center": Vector3, "rot": float, "half": Vector2 }]
var _occupied: Array[Dictionary] = []
var _road_ends: Dictionary = {}


func generate(world_seed: int) -> VillageLayout:
	rng = Seeds.rng(world_seed, "layout")
	layout = VillageLayout.new()
	layout.terrain_seed = Seeds.derive(world_seed, "terrain")
	layout.square_radius = rng.randf_range(12.5, 14.5)
	TerrainHeight.configure(layout.terrain_seed, layout.flat_radius)

	_build_main_roads()
	_place_square_props()
	_place_square_buildings()
	_place_manor()
	_place_farms()
	_place_roadside("barracks", ["north"], 14.0, 60.0)
	_place_roadside("mill", ["east", "west"], 58.0, 88.0)
	_place_roadside("workshop", ["east", "west", "south"], 26.0, 70.0)
	_place_roadside("storehouse", ["east", "west", "south"], 30.0, 75.0)
	var plan := GameData.village_plan()
	for i in int(plan.get("cottage", 7)):
		_place_roadside("cottage", ["east", "west", "south", "north"], 20.0, 80.0)
	_place_building_props()
	_place_trees()
	_place_rocks()
	return layout


# --- Roads -------------------------------------------------------------------

func _build_main_roads() -> void:
	var r := layout.square_radius
	var e := layout.extent - 3.0
	var north_end := Vector3(rng.randf_range(-6, 6), 0, -66)
	_add_road("west", Vector3(-r, 0, 0), Vector3(-e, 0, rng.randf_range(-10, 10)), 5.0, 2.2)
	_add_road("east", Vector3(r, 0, 0), Vector3(e, 0, rng.randf_range(-10, 10)), 5.0, 2.2)
	_add_road("north", Vector3(0, 0, -r), north_end, 4.5, 1.6)
	_add_road("south", Vector3(0, 0, r), Vector3(rng.randf_range(-10, 10), 0, e), 4.5, 2.2)


func _add_road(road_name: String, start: Vector3, end: Vector3, width: float, wobble: float, step: float = 14.0) -> int:
	var pts := PackedVector3Array()
	var dist := start.distance_to(end)
	var n := maxi(2, ceili(dist / step))
	var dir := (end - start).normalized()
	var normal := Vector3(-dir.z, 0, dir.x)
	var offset := 0.0
	for i in n + 1:
		var t := float(i) / n
		var p := start.lerp(end, t)
		if i > 0 and i < n:
			offset = clampf(offset + rng.randf_range(-wobble, wobble), -wobble * 2.5, wobble * 2.5)
			var fade := clampf(minf(t, 1.0 - t) * 5.0, 0.0, 1.0)
			p += normal * offset * fade
		pts.append(p)
	layout.roads.append({"points": pts, "width": width, "name": road_name})
	_road_ends[road_name] = end
	return layout.roads.size() - 1


func _road_by_name(road_name: String) -> Dictionary:
	for r in layout.roads:
		if r.get("name", "") == road_name:
			return r
	return {}


## Distance from p to the nearest road edge (negative = on a road).
func _road_clearance(p: Vector3) -> float:
	var best := INF
	var p2 := Vector2(p.x, p.z)
	for r in layout.roads:
		var pts: PackedVector3Array = r["points"]
		var half: float = float(r["width"]) * 0.5
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1].x, pts[i - 1].z)
			var b := Vector2(pts[i].x, pts[i].z)
			var c := Geometry2D.get_closest_point_to_segment(p2, a, b)
			best = minf(best, p2.distance_to(c) - half)
	return best


## Closest point on any road (excluding lanes when main_only).
func _closest_road_point(p: Vector3, main_only: bool) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	var p2 := Vector2(p.x, p.z)
	for r in layout.roads:
		if main_only and str(r.get("name", "")).begins_with("lane"):
			continue
		var pts: PackedVector3Array = r["points"]
		for i in range(1, pts.size()):
			var c := Geometry2D.get_closest_point_to_segment(p2, Vector2(pts[i - 1].x, pts[i - 1].z), Vector2(pts[i].x, pts[i].z))
			var d := p2.distance_to(c)
			if d < best_d:
				best_d = d
				best = Vector3(c.x, 0, c.y)
	return best


# --- Occupancy ------------------------------------------------------------------

static func _rect_samples(center: Vector3, rot: float, half: Vector2) -> Array[Vector3]:
	var basis := Basis(Vector3.UP, rot)
	var out: Array[Vector3] = [center]
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [-1.0, 0.0, 1.0]:
			if sx == 0.0 and sz == 0.0:
				continue
			out.append(center + basis * Vector3(half.x * sx, 0, half.y * sz))
	return out


static func _point_in_rect(p: Vector3, rect: Dictionary, margin: float) -> bool:
	var local: Vector3 = Basis(Vector3.UP, float(rect["rot"])).inverse() * (p - rect["center"])
	var half: Vector2 = rect["half"]
	return absf(local.x) < half.x + margin and absf(local.z) < half.y + margin


func _rect_is_free(center: Vector3, rot: float, half: Vector2, margin: float, road_margin: float) -> bool:
	if center.length() + half.length() > layout.flat_radius - 2.0:
		return false
	var mine := {"center": center, "rot": rot, "half": half}
	var samples := _rect_samples(center, rot, half)
	for s in samples:
		if s.distance_to(layout.square_center) < layout.square_radius + 1.5:
			return false
		if _road_clearance(s) < road_margin:
			return false
	for other in _occupied:
		for s in samples:
			if _point_in_rect(s, other, margin):
				return false
		for s in _rect_samples(other["center"], other["rot"], other["half"]):
			if _point_in_rect(s, mine, margin):
				return false
	return true


func _occupy(center: Vector3, rot: float, half: Vector2) -> void:
	_occupied.append({"center": center, "rot": rot, "half": half})


# --- Buildings -------------------------------------------------------------------

func _new_building(type: String, center: Vector3, rot: float) -> BuildingData:
	var def := GameData.building_type(type)
	var fp: Array = def.get("footprint", [6, 5])
	var b := BuildingData.new()
	b.id = _next_id
	_next_id += 1
	b.type = type
	b.name = str(def.get("name", type.capitalize()))
	b.position = center
	b.rotation = rot
	b.footprint = Vector2(float(fp[0]), float(fp[1]))
	b.variant = rng.randi_range(0, 7)
	layout.add_building(b)
	_occupy(center, rot, b.footprint * 0.5)
	return b


func _footprint(type: String) -> Vector2:
	var fp: Array = GameData.building_type(type).get("footprint", [6, 5])
	return Vector2(float(fp[0]), float(fp[1]))


## Rotation that makes a building's front (+Z) face `forward`.
static func _yaw_facing(forward: Vector3) -> float:
	return atan2(forward.x, forward.z)


func _place_square_buildings() -> void:
	var types: Array = SQUARE_BUILDINGS.duplicate()
	Seeds.shuffle(rng, types)
	var angles := [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]
	for i in types.size():
		var type: String = types[i]
		var fp := _footprint(type)
		var dir := Vector3(cos(angles[i]), 0, sin(angles[i]))
		var placed := false
		for push in range(0, 14):
			var center := layout.square_center + dir * (layout.square_radius + fp.y * 0.5 + 3.0 + push)
			var rot := _yaw_facing(-dir)
			if _rect_is_free(center, rot, fp * 0.5, 1.0, 0.8):
				_new_building(type, center, rot)
				placed = true
				break
		if not placed:
			_place_roadside(type, ["east", "west", "south"], 16.0, 70.0)


func _place_manor() -> void:
	var fp := _footprint("manor")
	var end: Vector3 = _road_ends["north"]
	var center := end + Vector3(0, 0, -(fp.y * 0.5 + 2.0))
	_new_building("manor", center, 0.0)
	# Gardens / courtyard in front are kept clear.
	_occupy(end + Vector3(0, 0, 4), 0.0, Vector2(9, 3))


func _place_farms() -> void:
	var sites := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	Seeds.shuffle(rng, sites)
	var wanted := int(GameData.village_plan().get("farmhouse", 3))
	var placed := 0
	for site: Vector3 in sites:
		if placed >= wanted:
			break
		if _place_farm(site.normalized()):
			placed += 1
	# Fallback: any free roadside slot.
	while placed < wanted:
		if _place_roadside("farmhouse", ["east", "west", "south"], 30.0, 85.0) == null:
			break
		placed += 1


func _place_farm(dir: Vector3) -> bool:
	var fp := _footprint("farmhouse")
	for attempt in 12:
		var dist := rng.randf_range(52.0, 66.0)
		var ang := atan2(dir.z, dir.x) + rng.randf_range(-0.3, 0.3)
		var center := Vector3(cos(ang), 0, sin(ang)) * dist
		var road_pt := _closest_road_point(center, true)
		var to_road := (road_pt - center)
		to_road.y = 0
		if to_road.length() < 10.0:
			continue
		var rot := _yaw_facing(to_road.normalized()) + rng.randf_range(-0.1, 0.1)
		if not _rect_is_free(center, rot, fp * 0.5, 2.0, 1.5):
			continue
		var farm := _new_building("farmhouse", center, rot)
		# Lane from the main road to the farmhouse door.
		var door := farm.door_position()
		var lane_start := road_pt
		_add_road("lane_%d" % farm.id, lane_start, door + farm.forward() * 0.5, 3.0, 0.8, 8.0)
		_place_fields(farm)
		return true
	return false


func _place_fields(farm: BuildingData) -> void:
	var basis := farm.basis()
	var fp := farm.footprint
	# Fields go behind and beside the farmhouse; several random tries each.
	var directions := [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, -2)]
	var count := 0
	var target := rng.randi_range(2, 4)
	for attempt in 40:
		if count >= target:
			break
		var dir: Vector3 = directions[attempt % directions.size()]
		var size := Vector2(rng.randf_range(11, 18), rng.randf_range(9, 14))
		var reach := Vector3(
			dir.x * (fp.x * 0.5 + size.x * 0.5 + rng.randf_range(2.0, 6.0)),
			0,
			dir.z * (fp.y * 0.5 + size.y * 0.5 + rng.randf_range(2.0, 5.0)) + rng.randf_range(-4.0, 4.0) * (1.0 - absf(dir.z)))
		var center := farm.position + basis * reach
		if not _rect_is_free(center, farm.rotation, size * 0.5, 0.8, 1.0):
			continue
		_occupy(center, farm.rotation, size * 0.5)
		layout.fields.append({"center": center, "size": size, "rot": farm.rotation, "crop": Seeds.pick(rng, CROPS), "building": farm.id})
		count += 1


## Places a building of `type` beside one of the named roads, between
## min_dist and max_dist from the village center. Closer slots are preferred.
func _place_roadside(type: String, road_names: Array, min_dist: float, max_dist: float) -> BuildingData:
	var fp := _footprint(type)
	var candidates: Array[Dictionary] = []
	for road_name: String in road_names:
		var road := _road_by_name(road_name)
		if road.is_empty():
			continue
		var pts: PackedVector3Array = road["points"]
		var width: float = road["width"]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var seg_len := a.distance_to(b)
			var dir := (b - a).normalized()
			var normal := Vector3(-dir.z, 0, dir.x)
			var s := 0.0
			while s < seg_len:
				var p := a + dir * s
				var d := p.length()
				if d >= min_dist and d <= max_dist:
					for side: float in [-1.0, 1.0]:
						candidates.append({"p": p, "normal": normal * side, "width": width, "score": d + rng.randf_range(0, 18.0)})
				s += 3.0
	candidates.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["score"] < y["score"])
	for c in candidates:
		var normal: Vector3 = c["normal"]
		var setback: float = float(c["width"]) * 0.5 + fp.y * 0.5 + rng.randf_range(2.2, 3.6)
		var center: Vector3 = c["p"] + normal * setback
		var rot := _yaw_facing(-normal) + rng.randf_range(-0.07, 0.07)
		if _rect_is_free(center, rot, fp * 0.5, 2.0, 1.2):
			return _new_building(type, center, rot)
	push_warning("VillageLayoutGenerator: no room for a %s" % type)
	return null


# --- Props ----------------------------------------------------------------------

func _add_prop(type: String, pos: Vector3, rot: float, half: Vector2 = Vector2.ZERO) -> void:
	layout.props.append({"type": type, "pos": pos, "rot": rot})
	if half != Vector2.ZERO:
		_occupy(pos, rot, half)


func _place_square_props() -> void:
	var r := layout.square_radius
	_add_prop("well", layout.square_center, 0.0)
	# Market stalls around the edge of the square, away from the road mouths.
	var angles := [0.45, 1.1, 2.05, 2.7, 3.6, 4.25, 5.15, 5.8]
	Seeds.shuffle(rng, angles)
	for i in 3:
		var a: float = angles[i]
		var dir := Vector3(cos(a), 0, sin(a))
		var pos := layout.square_center + dir * (r - 2.6)
		_add_prop("stall", pos, _yaw_facing(-dir))
	for i in range(3, 5):
		var a: float = angles[i]
		var dir := Vector3(cos(a), 0, sin(a))
		_add_prop("bench", layout.square_center + dir * (r - 1.6), _yaw_facing(-dir))
	layout.props.append_array(square_furniture(layout))


## Where a smithy's forge yard goes: against its right wall, else its left,
## else its back, on the first side clear of other buildings, the square,
## roads, fields, props and trees. {"pos", "rot"} (the yard's +Z points away
## from the wall), or {} if no side has room. No randomness, so loading an
## older save finds the spot the generator would (SaveManager.migrate);
## `ignore_small` lets barrels and crates be moved out of the way there.
static func smithy_yard(l: VillageLayout, b: BuildingData, ignore_small := false) -> Dictionary:
	var half: Vector2 = YARD_HALF["forge"]
	var basis := b.basis()
	for side: Array in [[Vector3(1, 0, 0), b.footprint.x, PI * 0.5], [Vector3(-1, 0, 0), b.footprint.x, -PI * 0.5], [Vector3(0, 0, -1), b.footprint.y, PI]]:
		var out: Vector3 = side[0]
		var center := b.position + basis * (out * (float(side[1]) * 0.5 + FORGE_SETBACK))
		var rot := b.rotation + float(side[2])
		if _yard_clear(l, b, center, rot, half, ignore_small):
			return {"pos": center, "rot": rot}
	return {}


## The barracks' training yard (3D/props/training-yard): behind it, else
## beside it (never on the door side, which faces its road), a full yard if
## one fits, else a small one, wherever its whole footprint is clear (as a
## forge yard's must be). The yard's +Z points away from the wall.
## {"type": "training" or "training_small", "pos", "rot"}, or {}.
static func training_yard(l: VillageLayout, b: BuildingData, ignore_small := false) -> Dictionary:
	var basis := b.basis()
	for type: String in ["training", "training_small"]:
		var half: Vector2 = YARD_HALF[type]
		for side: Array in [[Vector3(0, 0, -1), b.footprint.y, PI], [Vector3(1, 0, 0), b.footprint.x, PI * 0.5], [Vector3(-1, 0, 0), b.footprint.x, -PI * 0.5]]:
			var out: Vector3 = side[0]
			for setback: float in TRAINING_SETBACKS:
				var center := b.position + basis * (out * (float(side[1]) * 0.5 + setback + half.y))
				var rot := b.rotation + float(side[2])
				if _yard_clear(l, b, center, rot, half, ignore_small):
					return {"type": type, "pos": center, "rot": rot}
	return {}


static func _yard_clear(l: VillageLayout, owner: BuildingData, center: Vector3, rot: float, half: Vector2, ignore_small: bool) -> bool:
	if center.length() + half.length() > l.flat_radius - 2.0:
		return false
	var rect := {"center": center, "rot": rot, "half": half}
	var samples := _rect_samples(center, rot, half)
	for s in samples:
		if s.distance_to(l.square_center) < l.square_radius + 1.0:
			return false
		var p2 := Vector2(s.x, s.z)
		for road: Dictionary in l.roads:
			var pts: PackedVector3Array = road["points"]
			for i in range(1, pts.size()):
				var a := Vector2(pts[i - 1].x, pts[i - 1].z)
				var c := Geometry2D.get_closest_point_to_segment(p2, a, Vector2(pts[i].x, pts[i].z))
				if p2.distance_to(c) - float(road["width"]) * 0.5 < 0.4:
					return false
	for other in l.buildings:
		if other == owner:
			continue
		var orect := {"center": other.position, "rot": other.rotation, "half": other.footprint * 0.5}
		for s in samples:
			if _point_in_rect(s, orect, 0.4):
				return false
		for s in _rect_samples(other.position, other.rotation, other.footprint * 0.5):
			if _point_in_rect(s, rect, 0.4):
				return false
	for f: Dictionary in l.fields:
		var frect := {"center": f["center"], "rot": f["rot"], "half": (f["size"] as Vector2) * 0.5}
		for s in samples:
			if _point_in_rect(s, frect, 0.5):
				return false
		for s in _rect_samples(f["center"], float(f["rot"]), (f["size"] as Vector2) * 0.5):
			if _point_in_rect(s, rect, 0.5):
				return false
	for p: Dictionary in l.props:
		if ignore_small and p["type"] in ["barrel", "crate"]:
			continue
		if _point_in_rect(p["pos"], rect, 0.6):
			return false
	for t in l.trees:
		if _point_in_rect(Vector3(t.x, 0, t.y), rect, 0.6):
			return false
	return true


## Is a home yard's footprint (`center`, `rot`, `half`) clear? Clear of other
## buildings, the square, roads, fields and trees (as a forge yard must be),
## of the farm and forge yards (their whole footprints), and of `others`
## (rects already taken: {"center", "rot", "half"}).
static func dressing_clear(l: VillageLayout, owner: BuildingData, center: Vector3, rot: float, half: Vector2, others: Array) -> bool:
	if not _yard_clear(l, owner, center, rot, half, false):
		return false
	var rect := {"center": center, "rot": rot, "half": half}
	for o: Dictionary in others:
		if rects_overlap(rect, o, 0.3):
			return false
	for p: Dictionary in l.props:
		if YARD_HALF.has(p["type"]) and rects_overlap(rect, {"center": p["pos"], "rot": float(p["rot"]), "half": YARD_HALF[p["type"]]}, 0.3):
			return false
	return true


## Do two rectangles on the ground ({"center": Vector3, "rot": yaw, "half":
## Vector2}) come within `margin` of each other? (Separating axes.)
static func rects_overlap(a: Dictionary, b: Dictionary, margin: float) -> bool:
	var d := Vector2((b["center"] as Vector3).x - (a["center"] as Vector3).x, (b["center"] as Vector3).z - (a["center"] as Vector3).z)
	var axes: Array[Vector2] = []
	for r: Dictionary in [a, b]:
		var yaw := float(r["rot"])
		axes.append(Vector2(cos(yaw), -sin(yaw)))
		axes.append(Vector2(sin(yaw), cos(yaw)))
	for n in axes:
		var reach := 0.0
		for r: Dictionary in [a, b]:
			var yaw := float(r["rot"])
			var h: Vector2 = r["half"]
			reach += h.x * absf(Vector2(cos(yaw), -sin(yaw)).dot(n)) + h.y * absf(Vector2(sin(yaw), cos(yaw)).dot(n))
		if absf(d.dot(n)) > reach + margin:
			return false
	return true


## The market cross's spot (it stands once the Crown grants a market) and
## the trough beside the well, as layout props; both are drawn by charter
## (data/props.json "by_charter"). No randomness, so loading an older save
## finds the same spots the generator would (SaveManager.migrate).
static func square_furniture(l: VillageLayout) -> Array[Dictionary]:
	var c := l.square_center
	var cross := square_spot(l, l.square_radius * CROSS_AT)
	var trough := square_spot(l, TROUGH_AT, [cross])
	return [
		{"type": "market_cross", "pos": cross, "rot": _yaw_facing(c - cross)},
		{"type": "trough", "pos": trough, "rot": _yaw_facing(c - trough)},
	]


## The spot `dist` m from the square's centre that keeps furthest from the
## stalls, benches and banners, the walk in from each road mouth, and the
## spots in `taken` (72 angles tried, in order).
static func square_spot(l: VillageLayout, dist: float, taken: Array = []) -> Vector3:
	var c := l.square_center
	var mouths: Array[Vector3] = []
	for road: Dictionary in l.roads:
		var pts: PackedVector3Array = road["points"]
		if not pts.is_empty() and pts[0].distance_to(c) < l.square_radius + 1.0:
			mouths.append(pts[0])
	var best := c + Vector3(dist, 0, 0)
	var best_score := -INF
	for k in 72:
		var a := TAU * k / 72.0
		var p := c + Vector3(cos(a), 0, sin(a)) * dist
		var score := INF
		for prop: Dictionary in l.props:
			if prop["type"] in ["stall", "bench", "banner"]:
				score = minf(score, p.distance_to(prop["pos"]))
		for m: Vector3 in mouths:
			score = minf(score, Geometry3D.get_closest_point_to_segment(p, m, c).distance_to(p) + 1.0)
		for t: Vector3 in taken:
			score = minf(score, p.distance_to(t) - 2.0)  # and well clear of the spots taken
		if score > best_score + 0.001:
			best_score = score
			best = p
	return best


func _place_building_props() -> void:
	for b in layout.buildings:
		var basis := b.basis()
		var fp := b.footprint
		match b.type:
			"tavern", "smithy", "bakery", "storehouse":
				# A smithy's forge yard against a side wall first; barrels and
				# crates keep out of it.
				var yard := smithy_yard(layout, b) if b.type == "smithy" else {}
				if not yard.is_empty():
					_add_prop("forge", yard["pos"], yard["rot"], YARD_HALF["forge"])
				for i in rng.randi_range(2, 4):
					var local := Vector3((fp.x * 0.5 + 0.8) * (1 if i % 2 == 0 else -1), 0, rng.randf_range(-fp.y * 0.4, fp.y * 0.3))
					var kind := "barrel" if rng.randf() < 0.6 else "crate"
					var yaw := rng.randf() * TAU
					if not yard.is_empty() and _point_in_rect(b.position + basis * local, {"center": yard["pos"], "rot": yard["rot"], "half": YARD_HALF["forge"]}, 0.5):
						continue
					_add_prop(kind, b.position + basis * local, yaw)
			"farmhouse":
				# Haystacks in the yard, beside or behind the house (never on
				# the door side, nor across a back door mid-wall), on spots
				# clear of the house, its fields and the road: the stacks are
				# up to 2.1 m across.
				var want := rng.randi_range(1, 3)
				var placed := 0
				for attempt in 12:
					if placed >= want:
						break
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					var local := Vector3(side * rng.randf_range(fp.x * 0.3, fp.x * 0.5 + 2.0), 0, -fp.y * 0.5 - rng.randf_range(1.7, 3.5))
					if attempt % 2 == 1:
						local = Vector3((fp.x * 0.5 + rng.randf_range(1.7, 3.2)) * (1 if rng.randf() < 0.5 else -1), 0, rng.randf_range(-fp.y * 0.5, fp.y * 0.2))
					var pos := b.position + basis * local
					if _rect_is_free(pos, b.rotation, YARD_HALF["haystack"], 0.4, 0.6):
						_add_prop("haystack", pos, rng.randf() * TAU, YARD_HALF["haystack"])
						placed += 1
			"barracks":
				# Its training yard behind it (or beside it); the kit's three
				# dummies before it only where no yard fits.
				var training := training_yard(layout, b)
				if not training.is_empty():
					_add_prop(str(training["type"]), training["pos"], training["rot"], YARD_HALF[training["type"]])
				else:
					for i in 3:
						var local := Vector3((i - 1) * 3.0, 0, fp.y * 0.5 + 5.0)
						_add_prop("dummy", b.position + basis * local, b.rotation)
				# Its banner at a front corner, the one the yard leaves clear.
				var flag := b.position + basis * Vector3(fp.x * 0.5 + 1.2, 0, fp.y * 0.5)
				if not training.is_empty() and _point_in_rect(flag, {"center": training["pos"], "rot": training["rot"], "half": YARD_HALF[training["type"]]}, 0.6):
					flag = b.position + basis * Vector3(-fp.x * 0.5 - 1.2, 0, fp.y * 0.5)
				_add_prop("banner", flag, b.rotation)
			"workshop":
				# The log pile beside the workshop, or behind it if that side is taken.
				for local: Vector3 in [Vector3(fp.x * 0.5 + 2.4, 0, 0.5), Vector3(0, 0, -fp.y * 0.5 - 2.4)]:
					var pos := b.position + basis * local
					if _rect_is_free(pos, b.rotation, YARD_HALF["lumber"], 0.3, 0.5):
						_add_prop("lumber", pos, b.rotation + (PI * 0.5 if local.x > 0.0 else 0.0), YARD_HALF["lumber"])
						break
				_add_prop("cart", b.position + basis * Vector3(-fp.x * 0.5 - 2.0, 0, 1.0), b.rotation + 0.4)
			"manor":
				_add_prop("banner", b.position + basis * Vector3(-fp.x * 0.5 - 1.0, 0, fp.y * 0.5 + 1.0), b.rotation)
				_add_prop("banner", b.position + basis * Vector3(fp.x * 0.5 + 1.0, 0, fp.y * 0.5 + 1.0), b.rotation)
	# Signposts where roads leave the square.
	for road_name: String in ["west", "east", "south"]:
		var road := _road_by_name(road_name)
		var pts: PackedVector3Array = road["points"]
		var dir := (pts[1] - pts[0]).normalized()
		var normal := Vector3(-dir.z, 0, dir.x)
		_add_prop("signpost", pts[0] + dir * 3.0 + normal * 3.4, _yaw_facing(dir))


func _place_trees() -> void:
	var cell := 2.8
	var grid := {}
	var target := 520
	var attempts := 0
	var e := layout.extent - 2.0
	while layout.trees.size() < target and attempts < 9000:
		attempts += 1
		var x := rng.randf_range(-e, e)
		var z := rng.randf_range(-e, e)
		var p := Vector3(x, 0, z)
		var d := p.length()
		var density := smoothstep(48.0, 105.0, d) * (0.35 + 0.65 * TerrainHeight.grass_variation(x * 1.7, z * 1.7))
		if d < 48.0:
			density = 0.03
		if rng.randf() > density:
			continue
		if d < layout.square_radius + 4.0 or _road_clearance(p) < 2.2:
			continue
		var blocked := false
		for rect in _occupied:
			if _point_in_rect(p, rect, 2.2):
				blocked = true
				break
		if blocked:
			continue
		var key := Vector2i(floori(x / cell), floori(z / cell))
		var crowded := false
		for gx in range(key.x - 1, key.x + 2):
			for gz in range(key.y - 1, key.y + 2):
				var other: Variant = grid.get(Vector2i(gx, gz))
				if other != null and Vector2(other.x, other.y).distance_to(Vector2(x, z)) < cell:
					crowded = true
		if crowded:
			continue
		grid[key] = Vector2(x, z)
		var variant := 1 if rng.randf() < 0.35 + 0.3 * smoothstep(70.0, 120.0, d) else (0 if rng.randf() < 0.8 else 2)
		layout.trees.append(Vector4(x, z, rng.randf_range(0.8, 1.35), variant))


func _place_rocks() -> void:
	for i in 40:
		var a := rng.randf() * TAU
		var d := rng.randf_range(40.0, layout.extent - 5.0)
		var p := Vector3(cos(a), 0, sin(a)) * d
		if _road_clearance(p) < 1.5:
			continue
		var blocked := false
		for rect in _occupied:
			if _point_in_rect(p, rect, 1.0):
				blocked = true
				break
		if not blocked:
			_add_prop("rock", p, rng.randf() * TAU)
