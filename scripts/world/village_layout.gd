class_name VillageLayout
extends RefCounted
## The village as data: where every building, road, field, tree and prop is.
##
## Generated once from the world seed (VillageLayoutGenerator), then saved
## with the game, so loading never depends on the generator staying the same.
## VillageBuilder turns this into 3D nodes. A future procedural-terrain or
## multi-settlement system only has to produce another VillageLayout.

## Half-size of the playable map, in meters (map spans -extent..+extent).
var extent: float = 130.0
## Radius around the center that is kept flat for building.
var flat_radius: float = 92.0
var terrain_seed: int = 0

var square_center: Vector3 = Vector3.ZERO
var square_radius: float = 14.0

## [{ "name": String, "points": PackedVector3Array, "width": float }]
var roads: Array[Dictionary] = []
var buildings: Array[BuildingData] = []
## [{ "center": Vector3, "size": Vector2, "rot": float, "crop": String, "building": int }]
var fields: Array[Dictionary] = []
## [Vector4(x, z, scale, variant)]
var trees: Array[Vector4] = []
## [{ "type": String, "pos": Vector3, "rot": float }]
var props: Array[Dictionary] = []
## Runtime only (not saved): the solid pieces of the house dressing drawn
## round the buildings (a hen house, a water butt...), as Vector3(x, z,
## radius). VillageBuilder works them out with the dressing; the heir walks
## round them (WorldGeometry.resolve).
var dressing_obstacles: Array[Vector3] = []

var _by_id: Dictionary = {}


func add_building(b: BuildingData) -> void:
	buildings.append(b)
	_by_id[b.id] = b


func get_building(building_id: int) -> BuildingData:
	return _by_id.get(building_id, null)


func buildings_of_type(type: String) -> Array[BuildingData]:
	var out: Array[BuildingData] = []
	for b in buildings:
		if b.type == type:
			out.append(b)
	return out


func fields_of_building(building_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in fields:
		if int(f["building"]) == building_id:
			out.append(f)
	return out


## Positions of the market stalls (used by merchants).
func market_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in props:
		if p["type"] == "stall":
			var basis := Basis(Vector3.UP, float(p["rot"]))
			out.append(p["pos"] + basis * Vector3(0, 0, 1.6))
	return out


## True if a yard prop (haystack, log pile) with walking radius `radius` at
## `pos` keeps clear of every building's footprint.
func yard_spot_clear(pos: Vector3, radius: float) -> bool:
	for b in buildings:
		var local := b.basis().inverse() * (pos - b.position)
		var out := Vector2(maxf(absf(local.x) - b.footprint.x * 0.5, 0.0), maxf(absf(local.z) - b.footprint.y * 0.5, 0.0))
		if out.length() < radius:
			return false
	return true


func props_of_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in props:
		if p["type"] == type:
			out.append(p)
	return out


# --- Serialization -------------------------------------------------------------

func to_dict() -> Dictionary:
	var road_list: Array = []
	for r in roads:
		var pts: Array = []
		for p: Vector3 in r["points"]:
			pts.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
		road_list.append({"name": r.get("name", ""), "points": pts, "width": r["width"]})
	var building_list: Array = []
	for b in buildings:
		building_list.append(b.to_dict())
	var field_list: Array = []
	for f in fields:
		var c: Vector3 = f["center"]
		var s: Vector2 = f["size"]
		field_list.append({"center": [snappedf(c.x, 0.01), snappedf(c.z, 0.01)], "size": [s.x, s.y], "rot": snappedf(f["rot"], 0.0001), "crop": f["crop"], "building": f["building"]})
	var tree_list: Array = []
	for t in trees:
		tree_list.append([snappedf(t.x, 0.01), snappedf(t.y, 0.01), snappedf(t.z, 0.01), int(t.w)])
	var prop_list: Array = []
	for p in props:
		var pos: Vector3 = p["pos"]
		prop_list.append({"type": p["type"], "pos": [snappedf(pos.x, 0.01), snappedf(pos.z, 0.01)], "rot": snappedf(p["rot"], 0.0001)})
	return {
		"extent": extent,
		"flat_radius": flat_radius,
		"terrain_seed": terrain_seed,
		"square": {"center": [square_center.x, square_center.z], "radius": square_radius},
		"roads": road_list,
		"buildings": building_list,
		"fields": field_list,
		"trees": tree_list,
		"props": prop_list,
	}


static func from_dict(d: Dictionary) -> VillageLayout:
	var l := VillageLayout.new()
	l.extent = float(d.get("extent", 130.0))
	l.flat_radius = float(d.get("flat_radius", 92.0))
	l.terrain_seed = int(d.get("terrain_seed", 0))
	var sq: Dictionary = d.get("square", {})
	var sc: Array = sq.get("center", [0, 0])
	l.square_center = Vector3(float(sc[0]), 0, float(sc[1]))
	l.square_radius = float(sq.get("radius", 14.0))
	for r: Dictionary in d.get("roads", []):
		var pts := PackedVector3Array()
		for p: Array in r["points"]:
			pts.append(Vector3(float(p[0]), 0, float(p[1])))
		l.roads.append({"name": str(r.get("name", "")), "points": pts, "width": float(r["width"])})
	for b: Dictionary in d.get("buildings", []):
		l.add_building(BuildingData.from_dict(b))
	for f: Dictionary in d.get("fields", []):
		var c: Array = f["center"]
		var s: Array = f["size"]
		l.fields.append({"center": Vector3(float(c[0]), 0, float(c[1])), "size": Vector2(float(s[0]), float(s[1])), "rot": float(f["rot"]), "crop": str(f["crop"]), "building": int(f["building"])})
	for t: Array in d.get("trees", []):
		l.trees.append(Vector4(float(t[0]), float(t[1]), float(t[2]), float(t[3])))
	for p: Dictionary in d.get("props", []):
		var pos: Array = p["pos"]
		l.props.append({"type": str(p["type"]), "pos": Vector3(float(pos[0]), 0, float(pos[1])), "rot": float(p["rot"])})
	return l
