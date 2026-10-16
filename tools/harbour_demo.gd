extends RefCounted
## A demo harbour for the Harbour & Ships family (3D/props/harbour), for the
## capture tool and the family's tests. The family is art made ahead of the
## coast phase: the game has no sea yet, so this harbour brings its own
## shore, sea bed and water (tools/harbour_water.gdshader) and lives with
## the tools, not in data/.
##
## Frame: the waterfront runs along +X at z = 0, the sea toward +Z, the
## water line at y = 0. West to east: a stone quay with water stairs, a
## timber quay, then a beach with a jetty, a slipway, nets drying and a
## boat turned over. A cog lies alongside, a hoist swinging wool aboard; a
## fishing boat at the timber quay, rowing boats at the stairs and the
## jetty; a trading ship comes in under sail.

const ROOT := "res://3D/props/harbour/models/"
## The waterfront's heights (the family's README): the quay top, the
## jetty's deck, the bed at the quays' face.
const QUAY := 1.4
const JETTY := 1.2
const BED := -2.0
## Waterfront pieces' length along the line.
const LENGTH := {"SE_Quay_Stone": 4.0, "SE_Quay_Steps": 4.0, "SE_Quay_Timber": 4.0, "SE_Jetty": 4.0, "SE_Jetty_End": 4.0}
## The quays run from QUAYS_WEST to QUAYS_EAST; beyond them the shore is a
## beach falling at BEACH_SLOPE (the slipway's own slope).
const QUAYS_WEST := -28.0
const QUAYS_EAST := 12.0
const BEACH_SLOPE := 0.23
## Craft lie with their origin on the water line: [model, position, yaw].
const CRAFT := [
	["SE_Ship_Cog", Vector3(-7.0, 0, 3.9), 0.0],
	["SE_Boat_Fishing", Vector3(8.0, 0, 1.75), PI],
	["SE_Boat_Rowing", Vector3(-21.5, 0, 2.0), 0.2],
	["SE_Boat_Rowing", Vector3(22.6, 0, 6.5), -PI * 0.5],
	["SE_Ship_Keel", Vector3(-4.0, 0, 46.0), 0.15],
]


## The quays, the jetty and what stands on the shore: [model, position, yaw].
static func waterfront() -> Array:
	var out := []
	var quays := ["SE_Quay_Stone", "SE_Quay_Steps", "SE_Quay_Stone", "SE_Quay_Stone", "SE_Quay_Stone", "SE_Quay_Stone",
		"SE_Quay_Timber", "SE_Quay_Timber", "SE_Quay_Timber", "SE_Quay_Timber"]
	for i in quays.size():
		out.append([quays[i], Vector3(QUAYS_WEST + 2.0 + 4.0 * i, 0, 0), 0.0])
	# The jetty runs out from the beach (its own +X turned out to sea, +Z),
	# its landward end where the beach is as high as its deck.
	var start := deck_meets_beach()
	for k in 4:
		out.append(["SE_Jetty", Vector3(20.0, 0, start + 2.0 + 4.0 * k), -PI * 0.5])
	out.append(["SE_Jetty_End", Vector3(20.0, 0, start + 18.0), -PI * 0.5])
	out.append(["SE_Slipway", Vector3(30.0, 0, water_line()), 0.0])
	for x: float in [-25.0, -12.4, 5.6]:
		out.append(["SE_Mooring_Post", Vector3(x, QUAY, -0.75), 0.0])
	# The hoist swings a bale of wool down into the cog.
	out.append(["SE_Hoist", Vector3(-3.0, QUAY, -1.5), 0.0])
	out.append(["SE_Net_Rack", Vector3(26.0, QUAY, -9.0), 0.1])
	out.append(["SE_Net_Rack", Vector3(36.5, QUAY, -8.5), -0.15])
	out.append(["SE_Boat_Ashore", Vector3(43.0, QUAY, -10.0), 0.45])
	return out


static func layout() -> Array:
	return waterfront() + CRAFT


## Where the beach's slope crosses the water (z).
static func water_line() -> float:
	return QUAY / BEACH_SLOPE - 6.0


## Where the beach stands as high as the jetty's deck (z).
static func deck_meets_beach() -> float:
	return (QUAY - JETTY) / BEACH_SLOPE - 6.0


## The ground (or the bed under the water) at x, z.
static func ground(x: float, z: float) -> float:
	# At the quays: their top behind the face, the bed in front of it.
	var quay := QUAY if z <= -0.3 else lerpf(QUAY, BED, clampf((z + 0.3) / 0.7, 0.0, 1.0))
	# Elsewhere a beach: level ground, then a steady slope into the sea.
	var beach := clampf(QUAY - BEACH_SLOPE * (z + 6.0), BED - 1.2, QUAY)
	var t := smoothstep(QUAYS_EAST + 0.5, QUAYS_EAST + 5.0, x) + (1.0 - smoothstep(QUAYS_WEST - 5.5, QUAYS_WEST - 1.0, x))
	var h := lerpf(quay, beach, clampf(t, 0.0, 1.0))
	if z > 12.0:   # deeper out in the haven
		h = minf(h, BED - 1.2 - (z - 12.0) * 0.05)
	return maxf(h, -5.0)


## The shore and the sea bed as one mesh, coloured by height: grass, the
## quays' trodden earth, sand, wet sand, the bed darkening with depth.
static func shore_mesh() -> ArrayMesh:
	# A metre apart round the harbour, coarser out to the horizon, so the
	# coast runs on out of sight both ways and the land behind does too.
	var xs: Array[float] = []
	for k in 9:
		xs.append(-260.0 + 20.0 * k)
	var x := -79.0
	while x <= 89.0:
		xs.append(x)
		x += 1.0
	for k in 9:
		xs.append(100.0 + 20.0 * k)
	var zs: Array[float] = []
	for k in 14:
		zs.append(-260.0 + 15.0 * k)
	var z := -45.0
	while z <= 90.0:
		if z > -0.5 and z < 0.5:
			zs.append_array([-0.3, 0.4])
		else:
			zs.append(z)
		z += 1.0
	for k in 8:
		zs.append(110.0 + 25.0 * k)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var grass := Color("#5d8a37")
	var grass2 := Color("#7aa346")
	for zz in zs:
		for xx in xs:
			var h := ground(xx, zz)
			verts.append(Vector3(xx, h, zz))
			var c: Color
			var quayside := xx > QUAYS_WEST - 1.0 and xx < QUAYS_EAST + 1.0 and zz > -6.0 and zz < 0.5
			if h < -0.4:
				c = Color("#566048").lerp(Color("#33402f"), clampf((-0.4 - h) / 3.0, 0.0, 1.0))
			elif h < 0.12:
				c = Color("#8e8264")
			elif h < QUAY - 0.12:
				c = Color("#c9b68a")
			elif quayside:
				c = Color("#7c6a52")
			else:
				c = grass.lerp(grass2, 0.5 + 0.5 * sin(xx * 0.31) * cos(zz * 0.27))
			colors.append(c)
	var idx := PackedInt32Array()
	var nx := xs.size()
	for j in zs.size() - 1:
		for i in nx - 1:
			var a := j * nx + i
			# Front faces wind clockwise seen from above.
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		st.set_color(colors[i])
		st.add_vertex(verts[i])
	for i in idx:
		st.add_index(i)
	st.generate_normals()
	return st.commit()


static func water() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tools/harbour_water.gdshader")
	mi.material_override = mat
	mi.position = Vector3(0, 0, 150)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The harbour as nodes: shore, water, every piece; with `town`, storehouses
## and cottages behind the quays (the village kit's own buildings).
static func build(town: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Harbour"
	var shore := MeshInstance3D.new()
	shore.name = "Shore"
	shore.mesh = shore_mesh()
	shore.material_override = Mats.vertex_colored()
	root.add_child(shore)
	root.add_child(water())
	for p: Array in layout():
		var scene := load(ROOT + str(p[0]) + ".glb") as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		node.name = str(p[0])
		node.position = p[1]
		node.rotation.y = float(p[2])
		root.add_child(node, true)
	if town:
		for b: Array in [["storehouse", Vector3(-14.0, QUAY, -12.0)], ["storehouse", Vector3(0.0, QUAY, -12.5)],
				["cottage", Vector3(16.0, QUAY, -12.0)], ["cottage", Vector3(30.0, QUAY, -17.0)], ["cottage", Vector3(-34.0, QUAY, -14.0)]]:
			var bd := BuildingData.new()
			bd.id = root.get_child_count()
			bd.type = str(b[0])
			var fp: Array = GameData.building_type(bd.type).get("footprint", [6, 5])
			bd.footprint = Vector2(float(fp[0]), float(fp[1]))
			bd.position = b[1]
			root.add_child(BuildingFactory.build(bd))
	return root
