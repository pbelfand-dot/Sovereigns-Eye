class_name RoadGraph
extends RefCounted
## Walkable network for NPCs: road centerlines, a ring around the town
## square and a node at every building door, searched with A*.
##
## Lightweight on purpose: hundreds of NPCs can path on it every frame
## budget-free, and it rebuilds instantly from the layout. A navmesh can
## replace it later without changing the NPC brain (it only calls find_path).

const NODE_SPACING := 5.0
const MERGE_DISTANCE := 2.2

var astar := AStar3D.new()
var door_nodes: Dictionary = {}
var square_nodes: Array[int] = []
var road_nodes: Array[int] = []
var layout: VillageLayout
var _next_id := 0


func build(source: VillageLayout) -> void:
	layout = source
	astar.clear()
	_next_id = 0
	# Roads
	for road in layout.roads:
		var pts: PackedVector3Array = VillageBuilder._resample(road["points"], NODE_SPACING)
		var prev := -1
		for p in pts:
			var id := _add_or_merge(p)
			if not road_nodes.has(id):
				road_nodes.append(id)
			if prev >= 0 and prev != id:
				astar.connect_points(prev, id)
			prev = id
	# Lane ends that touch a road mid-segment: link to the nearest other node.
	for road in layout.roads:
		var pts: PackedVector3Array = road["points"]
		for endpoint in [pts[0], pts[pts.size() - 1]]:
			var id := astar.get_closest_point(endpoint)
			var nearest := _nearest_excluding(endpoint, id, 7.0)
			if nearest >= 0 and not astar.are_points_connected(id, nearest):
				astar.connect_points(id, nearest)
	# Square: a ring of nodes, linked to each other and to road mouths.
	var ring := 12
	var r := layout.square_radius * 0.72
	for i in ring:
		var a := TAU * i / ring
		var id := _add(layout.square_center + Vector3(cos(a), 0, sin(a)) * r)
		square_nodes.append(id)
	for i in ring:
		astar.connect_points(square_nodes[i], square_nodes[(i + 1) % ring])
	for id in road_nodes:
		var p := astar.get_point_position(id)
		if p.distance_to(layout.square_center) <= layout.square_radius + 3.0:
			var best := square_nodes[0]
			for s in square_nodes:
				if astar.get_point_position(s).distance_to(p) < astar.get_point_position(best).distance_to(p):
					best = s
			astar.connect_points(id, best)
	# Doors
	for b in layout.buildings:
		var door := b.door_position()
		var id := _add(door)
		door_nodes[b.id] = id
		var nearest := _nearest_road_or_square(door)
		if nearest >= 0:
			astar.connect_points(id, nearest)


func _add(p: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	astar.add_point(id, Vector3(p.x, 0, p.z))
	return id


func _add_or_merge(p: Vector3) -> int:
	if astar.get_point_count() > 0:
		var closest := astar.get_closest_point(Vector3(p.x, 0, p.z))
		if astar.get_point_position(closest).distance_to(Vector3(p.x, 0, p.z)) < MERGE_DISTANCE:
			return closest
	return _add(p)


func _nearest_excluding(p: Vector3, exclude: int, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for id in road_nodes:
		if id == exclude or astar.are_points_connected(id, exclude):
			continue
		var d := astar.get_point_position(id).distance_to(Vector3(p.x, 0, p.z))
		if d < best_d:
			best_d = d
			best = id
	return best


func _nearest_road_or_square(p: Vector3) -> int:
	var best := -1
	var best_d := INF
	var flat := Vector3(p.x, 0, p.z)
	for id in road_nodes + square_nodes:
		var d := astar.get_point_position(id).distance_to(flat)
		if d < best_d:
			best_d = d
			best = id
	return best


## Path from one world position to another along roads. The first and last
## legs are straight lines to/from the nearest graph nodes.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(from)
	if astar.get_point_count() == 0 or from.distance_to(to) < 6.0:
		out.append(to)
		return out
	var a := astar.get_closest_point(Vector3(from.x, 0, from.z))
	var b := astar.get_closest_point(Vector3(to.x, 0, to.z))
	if a != b:
		for p in astar.get_point_path(a, b):
			out.append(p)
	else:
		out.append(astar.get_point_position(a))
	out.append(to)
	# Drop a first node that sends us backwards past where we already are.
	if out.size() > 3 and out[0].distance_to(out[2]) < out[1].distance_to(out[2]):
		out.remove_at(1)
	for i in out.size():
		out[i] = TerrainHeight.on_ground(out[i])
	return out


func door_of(building_id: int) -> Vector3:
	var b := layout.get_building(building_id)
	return b.door_position() if b else Vector3.ZERO


func random_road_point(rng: RandomNumberGenerator) -> Vector3:
	if road_nodes.is_empty():
		return Vector3.ZERO
	return astar.get_point_position(road_nodes[rng.randi_range(0, road_nodes.size() - 1)])


## Random point on the town square, avoiding the well in the middle.
func random_square_point(rng: RandomNumberGenerator) -> Vector3:
	var a := rng.randf() * TAU
	var d := rng.randf_range(3.0, layout.square_radius - 1.5)
	return layout.square_center + Vector3(cos(a) * d, 0, sin(a) * d)
