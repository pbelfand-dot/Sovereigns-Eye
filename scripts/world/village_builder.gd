class_name VillageBuilder
extends Node3D
## Turns a VillageLayout (data) into 3D nodes: terrain, roads, square,
## fields, trees, props and buildings. Rebuilding from the same layout always
## gives the same village.

const CROP_LOOK := {
	"wheat": {"color": "#d9b94c", "shape": "stalk"},
	"barley": {"color": "#cfc477", "shape": "stalk"},
	"flax": {"color": "#7fa58a", "shape": "stalk"},
	"cabbage": {"color": "#5f9a3a", "shape": "head"},
	"turnip": {"color": "#4c8a3c", "shape": "head"},
}
const STALL_COLORS := ["#b23a3a", "#3a6ab2", "#d8a03a", "#3a8a5a", "#8a3ab2"]

var layout: VillageLayout
var building_nodes: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func build(source: VillageLayout) -> void:
	layout = source
	_rng.seed = layout.terrain_seed
	TerrainHeight.configure(layout.terrain_seed, layout.flat_radius)
	_build_terrain()
	_build_roads()
	_build_square()
	_build_fields()
	_build_trees()
	_build_props()
	_build_buildings()


# --- Terrain ------------------------------------------------------------------------

func _build_terrain() -> void:
	var e := layout.extent + 60.0
	var n := 120
	var step := (e * 2.0) / n
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var cfg: Dictionary = GameData.load_file("art_style").get("terrain", {})
	var grass: Array = cfg.get("grass", ["#5d8a37", "#7aa346"])
	var grass_a := Color(str(grass[0]))
	var grass_b := Color(str(grass[1]))
	var forest := Color(str(cfg.get("forest", "#4a7533")))
	var trodden := Color(str(cfg.get("trodden", "#8a9452")))
	for iz in n + 1:
		for ix in n + 1:
			var x := -e + ix * step
			var z := -e + iz * step
			var y := TerrainHeight.height_at(x, z)
			verts.append(Vector3(x, y, z))
			var hx := TerrainHeight.height_at(x + 0.5, z) - TerrainHeight.height_at(x - 0.5, z)
			var hz := TerrainHeight.height_at(x, z + 0.5) - TerrainHeight.height_at(x, z - 0.5)
			normals.append(Vector3(-hx, 1.0, -hz).normalized())
			var d := Vector2(x, z).length()
			var c := grass_a.lerp(grass_b, TerrainHeight.grass_variation(x, z))
			c = c.lerp(forest, smoothstep(60.0, 120.0, d) * 0.6)
			c = c.lerp(trodden, (1.0 - smoothstep(10.0, 40.0, d)) * 0.35)
			c = c.lightened(clampf(y / 30.0, 0.0, 0.15))
			colors.append(c)
	for iz in n:
		for ix in n:
			var i00 := iz * (n + 1) + ix
			var i10 := i00 + 1
			var i01 := i00 + (n + 1)
			var i11 := i01 + 1
			indices.append_array([i00, i10, i01, i10, i11, i01])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = meadow_material(layout, cfg, Vector2(-e, -e), e * 2.0)
	add_child(mi)


## The meadow ground shader with its baked wear mask, tuned from art_style.json.
static func meadow_material(source: VillageLayout, cfg: Dictionary, origin: Vector2, size: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_meadow.gdshader")
	for key: String in ["lush_tint", "dry_tint"]:
		var v: Array = cfg.get(key, [1.0, 1.0, 1.0])
		mat.set_shader_parameter(key, Vector3(float(v[0]), float(v[1]), float(v[2])))
	for key: String in ["patch_scale", "patch_strength", "clump_scale", "clump_strength", "grain_scale",
			"grain_strength", "dirt_threshold", "flower_cell", "flower_density", "flower_radius",
			"flower_patch_scale", "bump_strength"]:
		if cfg.has(key):
			mat.set_shader_parameter(key, float(cfg[key]))
	for key: String in ["dirt_color", "wear_color"]:
		if cfg.has(key):
			mat.set_shader_parameter(key, Color(str(cfg[key])))
	var flowers: Array = cfg.get("flower_colors", [])
	for i in mini(flowers.size(), 3):
		mat.set_shader_parameter("flower_" + "abc"[i], Color(str(flowers[i])))
	var fade: Array = cfg.get("detail_fade", [40.0, 140.0])
	mat.set_shader_parameter("detail_fade", Vector2(float(fade[0]), float(fade[1])))
	var wear_cfg: Dictionary = cfg.get("wear", {})
	var res := int(wear_cfg.get("mask_size", 512))
	var mask := GroundWear.bake(source, origin, size, res, wear_cfg)
	mat.set_shader_parameter("wear_mask", ImageTexture.create_from_image(mask))
	mat.set_shader_parameter("wear_origin", origin)
	mat.set_shader_parameter("wear_size", size)
	mat.set_shader_parameter("use_wear", true)
	return mat


# --- Roads ----------------------------------------------------------------------------

func _build_roads() -> void:
	var holder := Node3D.new()
	holder.name = "Roads"
	add_child(holder)
	var dirt := Color("#a3865f")
	var dirt_edge := Color("#8f7a55")
	for ri in layout.roads.size():
		var road: Dictionary = layout.roads[ri]
		var pts := _resample(road["points"], 1.5)
		var half: float = float(road["width"]) * 0.5
		var lift := 0.05 + ri * 0.004
		var verts := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for i in pts.size():
			var a := pts[maxi(i - 1, 0)]
			var b := pts[mini(i + 1, pts.size() - 1)]
			var t := (b - a).normalized()
			var nrm := Vector3(-t.z, 0, t.x)
			# Three vertices across: edge, center, edge (edges slightly darker).
			for k: float in [-1.0, 0.0, 1.0]:
				var p := pts[i] + nrm * half * k
				p.y = TerrainHeight.height_at(p.x, p.z) + lift
				verts.append(p)
				colors.append(dirt_edge if k != 0.0 else dirt)
			if i > 0:
				var base := (i - 1) * 3
				for k in 2:
					var a0 := base + k
					indices.append_array([a0, a0 + 3, a0 + 1, a0 + 1, a0 + 3, a0 + 4])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: Material = VillageKit.ground_material("road")
		if mat == null:
			var vc := Mats.vertex_colored(1.0).duplicate() as StandardMaterial3D
			vc.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat = vc
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


static func _resample(points: PackedVector3Array, spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if points.size() < 2:
		return points
	out.append(points[0])
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var steps := maxi(1, ceili(a.distance_to(b) / spacing))
		for s in range(1, steps + 1):
			out.append(a.lerp(b, float(s) / steps))
	return out


# --- Square ---------------------------------------------------------------------------------

func _build_square() -> void:
	var holder := Node3D.new()
	holder.name = "Square"
	add_child(holder)
	var c := layout.square_center
	var r := layout.square_radius
	Mats.cylinder(holder, r + 0.5, r + 0.5, 0.14, c + Vector3(0, 0.04, 0), Mats.hex("#7d7262"), 40)
	var paving := VillageKit.ground_material("square")
	if paving:
		# Kit brick paving with a darker cobbled ring.
		Mats.cylinder(holder, r, r, 0.16, c + Vector3(0, 0.06, 0), VillageKit.ground_material("road"), 48)
		Mats.cylinder(holder, r - 1.2, r - 1.2, 0.17, c + Vector3(0, 0.065, 0), paving, 48)
		return
	# Concentric rings of paving read as cobbles from above.
	var bands := ["#a99d86", "#b3a790", "#a59880", "#b6aa93", "#ab9f88"]
	for i in bands.size():
		var radius := r * (1.0 - float(i) / bands.size())
		Mats.cylinder(holder, radius, radius, 0.16 + i * 0.004, c + Vector3(0, 0.06 + i * 0.002, 0), Mats.hex(bands[i]), 40)
	# A few loose flagstones for texture.
	for i in 40:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * (r - 0.8)
		Mats.cylinder(holder, 0.35, 0.35, 0.03, c + Vector3(cos(a) * d, 0.15, sin(a) * d), Mats.hex("#9a8e78"), 6, Vector3(0, _rng.randf() * TAU, 0))


# --- Fields ------------------------------------------------------------------------------

func _build_fields() -> void:
	var holder := Node3D.new()
	holder.name = "Fields"
	add_child(holder)
	var soil := Mats.hex("#6e5134")
	var fence := Mats.hex("#7a5a3a")
	for f in layout.fields:
		var center: Vector3 = f["center"]
		var size: Vector2 = f["size"]
		var rot: float = f["rot"]
		var field := Node3D.new()
		field.position = TerrainHeight.on_ground(center)
		field.rotation.y = rot
		holder.add_child(field)
		Mats.box(field, Vector3(size.x, 0.16, size.y), Vector3(0, 0.04, 0), soil)
		var look: Dictionary = CROP_LOOK.get(f["crop"], CROP_LOOK["wheat"])
		var is_stalk: bool = look["shape"] == "stalk"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Mats.box_mesh(Vector3(0.22, 0.75, 0.22)) if is_stalk else Mats.sphere_mesh(0.3, 8, 4)
		var rows := int((size.y - 1.2) / 1.1)
		var cols := int((size.x - 1.2) / (0.55 if is_stalk else 0.9))
		mm.instance_count = rows * cols
		var base_color := Color(str(look["color"]))
		var i := 0
		for row in rows:
			for col in cols:
				var x := -size.x * 0.5 + 0.6 + col * (size.x - 1.2) / maxf(1.0, cols - 1)
				var z := -size.y * 0.5 + 0.6 + row * (size.y - 1.2) / maxf(1.0, rows - 1)
				var s := _rng.randf_range(0.75, 1.15)
				var y := 0.12 + (0.375 * s if is_stalk else 0.12)
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)).rotated(Vector3.UP, _rng.randf() * TAU), Vector3(x, y, z)))
				mm.set_instance_color(i, base_color.darkened(_rng.randf_range(0.0, 0.2)))
				i += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mats.vertex_colored(0.9)
		field.add_child(mmi)
		_build_fence(field, size, fence)


## Post-and-rail fence with a gap in the middle of the front side.
func _build_fence(field: Node3D, size: Vector2, mat: Material) -> void:
	var hx := size.x * 0.5 + 0.4
	var hz := size.y * 0.5 + 0.4
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var dir := (b - a).normalized()
		var posts := maxi(2, int(length / 2.5) + 1)
		for p in posts:
			var t := float(p) / (posts - 1)
			var pos := a.lerp(b, t)
			if side == 2 and absf(t - 0.5) < 0.12:
				continue
			Mats.box(field, Vector3(0.14, 0.95, 0.14), pos + Vector3(0, 0.47, 0), mat)
		var yaw := atan2(dir.x, dir.z)
		if side == 2:
			var gap := 1.4
			var seg := (length - gap * 2.0) * 0.5
			for sgn: float in [-1.0, 1.0]:
				var mid := (a + b) * 0.5 + dir * sgn * (gap + seg * 0.5)
				for h: float in [0.4, 0.75]:
					Mats.box(field, Vector3(0.06, 0.08, seg), mid + Vector3(0, h, 0), mat, Vector3(0, yaw, 0))
		else:
			for h: float in [0.4, 0.75]:
				Mats.box(field, Vector3(0.06, 0.08, length), (a + b) * 0.5 + Vector3(0, h, 0), mat, Vector3(0, yaw, 0))


# --- Trees ------------------------------------------------------------------------------------

func _build_trees() -> void:
	var holder := Node3D.new()
	holder.name = "Trees"
	add_child(holder)
	var trunks: Array[Transform3D] = []
	var trunk_colors: Array[Color] = []
	var round_tops: Array[Transform3D] = []
	var round_colors: Array[Color] = []
	var cone_tops: Array[Transform3D] = []
	var cone_colors: Array[Color] = []
	for t in layout.trees:
		var base := TerrainHeight.on_ground(Vector3(t.x, 0, t.y))
		var s := t.z
		var yaw := Basis(Vector3.UP, _rng.randf() * TAU)
		match int(t.w):
			1:  # conifer
				trunks.append(Transform3D(yaw.scaled(Vector3(s, s, s)), base + Vector3(0, 0.8 * s, 0)))
				trunk_colors.append(Color("#5b4030"))
				var green := Color("#2f6b3c").lerp(Color("#3f7d44"), _rng.randf())
				cone_tops.append(Transform3D(yaw.scaled(Vector3(s, s, s)), base + Vector3(0, 2.6 * s, 0)))
				cone_colors.append(green)
				cone_tops.append(Transform3D(yaw.scaled(Vector3(s * 0.72, s * 0.8, s * 0.72)), base + Vector3(0, 4.2 * s, 0)))
				cone_colors.append(green.lightened(0.06))
			2:  # birch
				trunks.append(Transform3D(yaw.scaled(Vector3(s * 0.8, s * 1.4, s * 0.8)), base + Vector3(0, 1.1 * s, 0)))
				trunk_colors.append(Color("#e8e2d4"))
				round_tops.append(Transform3D(yaw.scaled(Vector3(s * 0.8, s * 1.1, s * 0.8)), base + Vector3(0, 3.2 * s, 0)))
				round_colors.append(Color("#8fb85a").lerp(Color("#a4c867"), _rng.randf()))
			_:  # broadleaf
				trunks.append(Transform3D(yaw.scaled(Vector3(s, s, s)), base + Vector3(0, 0.8 * s, 0)))
				trunk_colors.append(Color("#6b4a32"))
				round_tops.append(Transform3D(yaw.scaled(Vector3(s, s * 0.9, s)), base + Vector3(0, 2.7 * s, 0)))
				round_colors.append(Color("#4f8a3a").lerp(Color("#6fa346"), _rng.randf()))
	_add_multimesh(holder, Mats.cylinder_mesh(0.18, 0.28, 1.6, 7), trunks, trunk_colors)
	_add_multimesh(holder, Mats.sphere_mesh(1.6, 9, 5), round_tops, round_colors)
	_add_multimesh(holder, Mats.cylinder_mesh(0.0, 1.5, 3.0, 8), cone_tops, cone_colors)


func _add_multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Mats.vertex_colored(0.95)
	parent.add_child(mmi)


# --- Props --------------------------------------------------------------------------------------

func _build_props() -> void:
	var holder := Node3D.new()
	holder.name = "Props"
	add_child(holder)
	var wood := Mats.hex("#7a5636")
	var dark_wood := Mats.hex("#4f3826")
	var stone := Mats.hex("#8e8a80")
	for p in layout.props:
		var node := Node3D.new()
		node.position = TerrainHeight.on_ground(p["pos"])
		node.rotation.y = float(p["rot"])
		holder.add_child(node)
		match str(p["type"]):
			"well":
				Mats.cylinder(node, 1.1, 1.2, 0.9, Vector3(0, 0.45, 0), stone, 14)
				Mats.cylinder(node, 0.85, 0.85, 0.05, Vector3(0, 0.88, 0), Mats.hex("#2f4a5e"), 14)
				for sx: float in [-1.0, 1.0]:
					Mats.box(node, Vector3(0.15, 2.0, 0.15), Vector3(sx * 0.95, 1.0, 0), dark_wood)
				Mats.add_mesh(node, Mats.prism_mesh(Vector3(1.6, 0.8, 2.6)), Mats.hex("#8f4e31"), Vector3(0, 2.3, 0), Vector3(0, PI * 0.5, 0))
				Mats.cylinder(node, 0.08, 0.08, 1.9, Vector3(0, 1.6, 0), wood, 6, Vector3(0, 0, PI * 0.5))
			"stall":
				var cloth := Mats.hex(STALL_COLORS[_rng.randi_range(0, STALL_COLORS.size() - 1)])
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						Mats.box(node, Vector3(0.12, 2.3, 0.12), Vector3(sx * 1.3, 1.15, sz * 0.8), dark_wood)
				Mats.box(node, Vector3(2.9, 0.08, 2.0), Vector3(0, 2.32, 0), cloth, Vector3(0.12, 0, 0))
				Mats.box(node, Vector3(2.5, 0.9, 0.7), Vector3(0, 0.45, 0.4), wood)
				for i in 5:
					var good := Mats.hex(["#c94a3a", "#e3b34a", "#7fae4a", "#d8d0b8", "#8a5a9a"][_rng.randi_range(0, 4)])
					Mats.sphere(node, 0.16, Vector3(-0.9 + i * 0.45, 1.0, 0.45), good)
			"bench":
				Mats.box(node, Vector3(1.8, 0.1, 0.45), Vector3(0, 0.45, 0), wood)
				for sx: float in [-1.0, 1.0]:
					Mats.box(node, Vector3(0.1, 0.45, 0.4), Vector3(sx * 0.75, 0.22, 0), dark_wood)
			"barrel":
				Mats.cylinder(node, 0.38, 0.38, 0.95, Vector3(0, 0.48, 0), wood, 10)
				Mats.cylinder(node, 0.4, 0.4, 0.08, Vector3(0, 0.25, 0), dark_wood, 10)
				Mats.cylinder(node, 0.4, 0.4, 0.08, Vector3(0, 0.72, 0), dark_wood, 10)
			"crate":
				Mats.box(node, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), Mats.hex("#9a7448"))
			"haystack":
				Mats.sphere(node, 1.2, Vector3(0, 0.55, 0), Mats.hex("#d6b85a"), Vector3(1.0, 0.85, 1.0))
			"dummy":
				Mats.box(node, Vector3(0.12, 1.9, 0.12), Vector3(0, 0.95, 0), dark_wood)
				Mats.box(node, Vector3(1.0, 0.1, 0.1), Vector3(0, 1.45, 0), dark_wood)
				Mats.add_mesh(node, Mats.capsule_mesh(0.28, 1.0), Mats.hex("#c9b07a"), Vector3(0, 1.3, 0))
				Mats.sphere(node, 0.2, Vector3(0, 1.95, 0), Mats.hex("#c9b07a"))
			"banner":
				Mats.cylinder(node, 0.06, 0.08, 5.0, Vector3(0, 2.5, 0), dark_wood, 6)
				Mats.box(node, Vector3(0.9, 1.8, 0.05), Vector3(0.5, 3.9, 0), Mats.hex("#8a1f2f"))
				Mats.box(node, Vector3(0.9, 0.18, 0.06), Vector3(0.5, 4.7, 0), Mats.hex("#d9b04a"))
			"lumber":
				for i in 6:
					var row := int(i / 3.0)
					Mats.cylinder(node, 0.22, 0.22, 3.0, Vector3((i % 3) * 0.46 - 0.46 + row * 0.23, 0.22 + row * 0.4, 0), Mats.hex("#8a6440"), 8, Vector3(PI * 0.5, 0, 0))
			"cart":
				Mats.box(node, Vector3(1.4, 0.5, 2.2), Vector3(0, 0.8, 0), wood)
				for sx: float in [-1.0, 1.0]:
					Mats.cylinder(node, 0.5, 0.5, 0.12, Vector3(sx * 0.78, 0.5, 0.2), dark_wood, 12, Vector3(0, 0, PI * 0.5))
				Mats.box(node, Vector3(0.1, 0.1, 1.6), Vector3(0, 0.6, 1.8), dark_wood)
			"signpost":
				Mats.box(node, Vector3(0.14, 2.2, 0.14), Vector3(0, 1.1, 0), dark_wood)
				Mats.box(node, Vector3(1.2, 0.28, 0.06), Vector3(0.45, 1.85, 0), wood, Vector3(0, 0, 0.08))
				Mats.box(node, Vector3(1.0, 0.26, 0.06), Vector3(-0.35, 1.45, 0), wood, Vector3(0, 0.6, -0.06))
			"rock":
				var s := _rng.randf_range(0.5, 1.4)
				Mats.sphere(node, 0.8, Vector3(0, 0.2 * s, 0), Mats.hex("#8d8a82"), Vector3(s * 1.3, s * 0.6, s))


# --- Buildings -----------------------------------------------------------------------------------

func _build_buildings() -> void:
	var holder := Node3D.new()
	holder.name = "Buildings"
	add_child(holder)
	for b in layout.buildings:
		var node := BuildingFactory.build(b)
		holder.add_child(node)
		building_nodes[b.id] = node
