extends TestCase
## Lord's Castle (3D/buildings/lords-castle): stone and timber pieces for a
## lord's castle, made ahead of the castle phase. Nothing in the game builds
## a castle yet; the demo castles (tools/castle_demo.gd) show the pieces put
## together, and these tests hold the pieces to the grid they join on.

const DIR := "res://3D/buildings/lords-castle/models/"
const Demo := preload("res://tools/castle_demo.gd")
const BUDGETS := {"SE_Curtain_Wall": 300, "SE_Curtain_Stair": 900, "SE_Curtain_Corner": 300, "SE_Tower_Square": 800,
	"SE_Tower_Corner": 800, "SE_Gatehouse": 2000, "SE_Keep": 4000, "SE_Palisade": 1000, "SE_Palisade_Corner": 1000,
	"SE_Palisade_Gate": 1400, "SE_Timber_Tower": 3200, "SE_Motte": 1000, "SE_Motte_Bridge": 1600}
const SEEDS := ["9", "12345", "1", "7", "42", "2026"]

var _probe = preload("res://tests/mesh_probe.gd").new(DIR)


func _tris(model: String) -> PackedVector3Array:
	return _probe.tris(model)


func _section(model: String, h: float) -> PackedVector3Array:
	return _probe.section(model, h)


## How far a model reaches along `axis` (0 = x, 2 = z) at height h, within
## the band the wall's thickness takes (where pieces meet).
func _extent(model: String, h: float, axis: int, band: float = 1.2) -> Vector2:
	return _probe.extent(model, h, axis, band)


## A model's extent along its wall line (x) at height h, where it meets its neighbours.
func _span(model: String, h: float) -> Vector2:
	return _extent(model, h, 0)


## A placed piece's ground plan (x, z) in the castle's frame: its section
## at height h, or (h = NAN) everything it has.
func _plan(piece: Array, h: float = NAN) -> Rect2:
	return _probe.plan(piece, h)


func test_every_castle_model_loads_within_budget() -> void:
	var seen := 0
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".glb"):
			continue
		seen += 1
		var root := (load(DIR + f) as PackedScene).instantiate()
		var tris := 0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				check(mat != null and mat.resource_name.begins_with("MI_"), "%s: named material" % f)
				if mat:
					check(mat.albedo_texture != null, "%s: %s has its texture" % [f, mat.resource_name])
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := int(BUDGETS.get(f.get_basename(), 0))
		check(budget > 0 and tris <= budget and tris >= 60, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, BUDGETS.size(), "all thirteen castle models are there")


func test_pieces_are_as_long_as_the_grid_says() -> void:
	# Measured between the battered foot and the wall walk, where the
	# pieces meet: only their bodies stand there.
	for model: String in ["SE_Curtain_Wall", "SE_Curtain_Stair", "SE_Tower_Square", "SE_Gatehouse"]:
		var span := _span(model, 3.5)
		var want: float = Demo.LENGTH[model]
		check(absf(span.y - span.x - want) <= 0.02 and absf(span.x + span.y) < 0.02,
			"%s: %.2f m along the wall, centred (the grid says %.1f)" % [model, span.y - span.x, want])
	# A corner tower and a plain corner meet their walls on +X and on +Y in
	# Blender (-Z here), both 3 m from the corner's middle, so they swap.
	for model: String in ["SE_Tower_Corner", "SE_Curtain_Corner"]:
		var east := _extent(model, 3.5, 0)
		var north := _extent(model, 3.5, 2)
		check(absf(east.y - 3.0) < 0.02 and absf(north.x + 3.0) < 0.02, "%s: the faces where walls join are 3 m out (%.2f, %.2f)" % [model, east.y, -north.x])
	var stakes := _span("SE_Palisade", 2.0)
	check(absf(stakes.y - stakes.x - 4.0) <= 0.1, "a palisade length is 4 m of stakes (%.2f)" % (stakes.y - stakes.x))
	var gate := _span("SE_Palisade_Gate", 2.0)
	check(gate.y - gate.x <= 4.0 + 0.4, "the timber gate tower stays within its 4 m (%.2f)" % (gate.y - gate.x))
	# The corner piece's stakes run 2 m along +X and 2 m along +Y (Godot -Z) from its post.
	var arm_x := -INF
	var arm_z := INF
	for v in _section("SE_Palisade_Corner", 2.0):
		if absf(v.z) < 0.3:
			arm_x = maxf(arm_x, v.x)
		if absf(v.x) < 0.3:
			arm_z = minf(arm_z, v.z)
	check(absf(arm_x - 2.0) < 0.1 and absf(arm_z + 2.0) < 0.1, "the palisade corner's arms reach 2 m each way (%.2f, %.2f)" % [arm_x, -arm_z])


func test_the_wall_walk_is_level_from_piece_to_piece() -> void:
	# Each curtain piece's wall walk is at 6 m and clear (nothing stands on
	# it inside the parapet), and every tower and the gatehouse has a
	# doorway at that height on each side a wall joins.
	for model: String in ["SE_Curtain_Wall", "SE_Curtain_Stair", "SE_Curtain_Corner"]:
		var edge := false
		var clear := true
		for v in _tris(model):
			if absf(v.z + 1.2) < 0.01 and absf(v.y - 6.0) < 0.01:
				edge = true
			if v.z > -1.15 and v.z < 0.55 and v.x > -0.55 and v.y > 6.05:
				clear = false
		check(edge, "%s: the walk's inner edge is at 6 m" % model)
		check(clear, "%s: nothing stands on the walk" % model)
	var joins := {"SE_Tower_Square": [Vector3.RIGHT, Vector3.LEFT], "SE_Tower_Corner": [Vector3.RIGHT, Vector3.FORWARD],
		"SE_Gatehouse": [Vector3.RIGHT, Vector3.LEFT]}
	for model: String in joins:
		var half: float = Demo.LENGTH[model] * 0.5
		for dir: Vector3 in joins[model]:
			var found := false
			for v in _tris(model):
				if v.dot(dir) >= half + 0.04 and absf(v.y - 6.04) < 0.05 and absf(v.dot(Vector3(dir.z, 0, -dir.x))) < 1.0:
					found = true
					break
			check(found, "%s: a doorway onto the wall walk toward %s" % [model, dir])


func test_the_demo_castles_close_and_nothing_stands_in_anything() -> void:
	var stone: Array = Demo.stone()
	var models := {}
	for p: Array in stone + Demo.timber():
		models[str(p[0])] = true
	for m: String in models:
		check(ResourceLoader.exists(DIR + m + ".glb"), "%s is in the family" % m)
	# The curtain: four sides, each a corner tower and pieces on the wall
	# line reaching exactly to the next corner tower.
	var half: float = Demo.STONE_HALF
	var sides: Array = []
	for p: Array in stone:
		if p[0] == "SE_Keep":
			continue
		if p[0] in ["SE_Tower_Corner", "SE_Curtain_Corner"]:
			sides.append([p])
			continue
		sides[-1].append(p)
		var at: Vector3 = p[1]
		check(absf(maxf(absf(at.x), absf(at.z)) - half) < 0.01, "%s stands on the wall line" % p[0])
	check_eq(sides.size(), 4, "four sides")
	for i in sides.size():
		var run := 0.0
		for p: Array in sides[i]:
			run += Demo.LENGTH[str(p[0])]
		check(is_equal_approx(run, 2.0 * half), "side %d: %.1f m from corner tower to corner tower" % [i, run])
		# Neighbours meet end to end: above the plinths they touch, and stand in nothing.
		var chain: Array = sides[i] + [sides[(i + 1) % sides.size()][0]]
		for k in range(1, chain.size()):
			var ra := _plan(chain[k - 1], 3.5)
			var rb := _plan(chain[k], 3.5)
			check(not ra.grow(-0.06).intersects(rb.grow(-0.06)), "side %d: %s and %s don't stand in each other" % [i, chain[k - 1][0], chain[k][0]])
			check(ra.grow(0.1).intersects(rb), "side %d: no gap between %s and %s" % [i, chain[k - 1][0], chain[k][0]])
	# The keep stands clear of the walls, towers and stair, with room to walk round it.
	var keep: Rect2 = _plan(stone[-1])
	check_eq(stone[-1][0], "SE_Keep", "the keep is inside")
	for p: Array in stone.slice(0, stone.size() - 1):
		check(not keep.intersects(_plan(p).grow(3.0)), "the keep keeps 3 m off %s" % p[0])


func test_the_motte_carries_its_tower_and_its_bridge() -> void:
	# The motte's top is level where the tower stands.
	for v in _tris("SE_Motte"):
		if Vector2(v.x, v.z).length() < 4.6:
			check(absf(v.y - Demo.MOTTE_TOP) < 0.12, "the motte's top is level under the tower (%.2f)" % v.y)
	# The bridge comes down from the motte's top, by the tower's door, to the ground in the bailey.
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in _tris("SE_Motte_Bridge"):
		lo = lo.min(v)
		hi = hi.max(v)
	check(lo.x > 4.3 and lo.x < 6.0, "the bridge's head is between the tower's hoard and the motte's edge (%.2f)" % lo.x)
	check(hi.y > Demo.MOTTE_TOP and hi.y < Demo.MOTTE_TOP + 1.6, "it reaches the motte's top (%.2f)" % hi.y)
	check(hi.x < Demo.BAILEY_FAR - 6.0 and absf(hi.z) < Demo.BAILEY_HALF - 4.0, "its foot is well inside the bailey")
	var timber: Array = Demo.timber()
	var tower: Array = timber[2]
	check_eq(tower[0], "SE_Timber_Tower", "the tower stands on the motte")
	check(is_equal_approx((tower[1] as Vector3).y, Demo.MOTTE_TOP), "on its top")
	# The door at the tower's foot faces the bridge.
	var door := false
	for v in _tris("SE_Timber_Tower"):
		if v.y > 0.4 and v.y < 2.0 and v.x > 3.0 and absf(v.z) < 0.6:
			door = true
	check(door, "the tower has a door on its bridge side (+X)")


func test_both_castles_find_room_beside_the_village() -> void:
	for seed_text in SEEDS:
		var st := WorldGenerator.generate(seed_text)
		var spots: Dictionary = Demo.find_spots(st.layout)
		check_eq(spots.size(), 2, "seed %s: room for both castles" % seed_text)
		var taken := []
		for kind: String in Demo.KINDS:
			if not spots.has(kind):
				continue
			var xf: Transform3D = spots[kind]
			check(Demo.spot_clear(st.layout, xf, Demo.footprint(kind).grow(3.0), taken),
				"seed %s: the %s castle keeps off buildings, fields, roads and the other castle" % [seed_text, kind])
			taken.append([xf, Demo.footprint(kind).grow(3.0)])
		check_eq(Demo.find_spots(WorldGenerator.generate(seed_text).layout), spots, "seed %s: the same spots each time" % seed_text)
