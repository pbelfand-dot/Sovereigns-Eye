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
## Stores and building sites (Phase 3), set before build(): sites wear the
## ground, felled trees are skipped. Optional (tools build bare layouts).
var territory: TerritoryData
## The home yards drawn by the last dressing pass (for checks and captures):
## [{"set", "building", "center", "rot", "half"}].
var yard_rects: Array[Dictionary] = []
var building_nodes: Dictionary = {}
var site_nodes: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Trodden-ground mask (GroundWear) shared by the meadow shader and scatter.
var _wear: Image
var _wear_origin := Vector2.ZERO
var _wear_size := 1.0
var _terrain: MeshInstance3D
## The castle's levelled ground (CastleSystem.pads) and its site, where
## nothing grows (CastleSystem.yard); set by the world.
var castle_pads: Array = []
var castle_yard: Dictionary = {}
## Scatter group name -> items placed at build time, re-filtered (not
## re-rolled) when the ground changes so the rest of the meadow stays put.
var _scatter_cache: Dictionary = {}


func build(source: VillageLayout) -> void:
	layout = source
	_rng.seed = layout.terrain_seed
	TerrainHeight.configure(layout.terrain_seed, layout.flat_radius)
	TerrainHeight.set_pads(castle_pads)
	_build_terrain()
	_build_roads()
	_build_square()
	_build_fields()
	if NatureKit.available():
		_build_nature()
	else:
		_build_trees()
	_build_props()
	_build_buildings()
	_build_sites()


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
	_wear_origin = Vector2(-e, -e)
	_wear_size = e * 2.0
	_wear = GroundWear.bake(layout, _wear_origin, _wear_size, int(cfg.get("wear", {}).get("mask_size", 512)), cfg.get("wear", {}), _site_buildings())
	mi.material_override = meadow_material(layout, cfg, _wear_origin, _wear_size, _wear)
	add_child(mi)
	_terrain = mi


## The meadow ground shader with its baked wear mask, tuned from art_style.json.
static func meadow_material(source: VillageLayout, cfg: Dictionary, origin: Vector2, size: float, mask: Image = null) -> ShaderMaterial:
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
	if mask == null:
		var wear_cfg: Dictionary = cfg.get("wear", {})
		mask = GroundWear.bake(source, origin, size, int(wear_cfg.get("mask_size", 512)), wear_cfg)
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
	# The rim: the charter's kerb (Market Square models), or a flat stone band.
	var kerb := _square_edge()
	if kerb:
		holder.add_child(kerb)
	else:
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


## The kerb round the square for the current charter, as one MultiMesh
## (data/props.json "square_edge"), or null without the models.
func _square_edge() -> MultiMeshInstance3D:
	var list: Array = PropKit.config().get("square_edge", {}).get("by_charter", [])
	if list.is_empty():
		return null
	var model := str(list[clampi(territory.charter if territory else 0, 0, list.size() - 1)])
	if not ResourceLoader.exists(PropKit.model_path(model)):
		return null
	var parts := PropKit.parts(model)
	if parts.is_empty():
		return null
	var xforms := square_edge_transforms()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = parts[0][0]
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Kerb"
	mmi.multimesh = mm
	return mmi


## Where the kerb pieces lie round the square's rim: each piece's local +X
## runs along the edge and +Z points out of the square, its inner edge on
## the paving's rim. Pieces are stretched to the chord between their ends;
## where a road comes in, the pieces either side are cut short to stop just
## clear of it, so each opening is the road's width.
func square_edge_transforms() -> Array[Transform3D]:
	var cfg: Dictionary = PropKit.config().get("square_edge", {})
	var seg := float(cfg.get("segment", 1.5))
	var gap := float(cfg.get("road_gap", 0.3))
	var c := layout.square_center
	var r := layout.square_radius
	var n := maxi(8, roundi(TAU * r / seg))
	var step := TAU / n
	const SAMPLES := 12
	var out: Array[Transform3D] = []
	for k in n:
		# Walk the piece from its a1 end back to a0, keeping the longest clear run.
		var a1 := (k + 1) * step
		var best := Vector2i(-1, -1)
		var run_start := -1
		for i in SAMPLES + 1:
			var a := a1 - step * i / SAMPLES
			var p := c + Vector3(cos(a), 0, sin(a)) * (r + 0.25)
			var clear := road_clearance(Vector2(p.x, p.z)) >= gap
			if clear and run_start < 0:
				run_start = i
			if run_start >= 0 and (not clear or i == SAMPLES):
				var run_end := i if clear else i - 1
				if run_end - run_start > best.y - best.x:
					best = Vector2i(run_start, run_end)
				run_start = -1
		if best.x < 0 or (best.y - best.x) * step * r / SAMPLES < 0.4:
			continue
		var b1 := a1 - step * best.x / SAMPLES
		var b0 := a1 - step * best.y / SAMPLES
		var mid := (b0 + b1) * 0.5
		var sx := 2.0 * r * sin((b1 - b0) * 0.5) / seg
		var outward := Vector3(cos(mid), 0, sin(mid))
		var along := Vector3(sin(mid), 0, -cos(mid))  # from b1 back to b0, so +Z comes out outward
		var origin := c + Vector3(cos(b1), 0, sin(b1)) * r
		out.append(Transform3D(Basis(along * sx, Vector3.UP, outward), TerrainHeight.on_ground(origin)))
	return out


# --- Fields ------------------------------------------------------------------------------

func _build_fields() -> void:
	var holder := Node3D.new()
	holder.name = "Fields"
	add_child(holder)
	for f in layout.fields:
		add_field(f, holder)


## Draws one field (soil, crop rows, fence). Each field rolls its own crop
## jitter from its position, so adding fields later never reshuffles others.
func add_field(f: Dictionary, holder: Node3D = null) -> void:
	if holder == null:
		holder = get_node_or_null("Fields")
		if holder == null:
			return
	var soil := Mats.hex("#6e5134")
	var fence := Mats.hex("#7a5a3a")
	var center: Vector3 = f["center"]
	var size: Vector2 = f["size"]
	var rot: float = f["rot"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(center.x * 10.0), roundi(center.z * 10.0)))
	var field := Node3D.new()
	field.position = TerrainHeight.on_ground(center)
	field.rotation.y = rot
	holder.add_child(field)
	# The Farm & Field models (data/farm.json); the simple shapes below are
	# the fallback when they're missing.
	if FarmKit.available():
		var farm_local: Variant = null
		var farm := layout.get_building(int(f.get("building", -1))) if f.has("building") else null
		if farm:
			farm_local = Basis(Vector3.UP, rot).inverse() * (farm.position - center)
		FarmKit.build_field(field, f, territory.charter if territory else 0, farm_local)
		return
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
			var s := rng.randf_range(0.75, 1.15)
			var y := 0.12 + (0.375 * s if is_stalk else 0.12)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)).rotated(Vector3.UP, rng.randf() * TAU), Vector3(x, y, z)))
			mm.set_instance_color(i, base_color.darkened(rng.randf_range(0.0, 0.2)))
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


# --- Nature (Quaternius Stylized Nature MegaKit) ----------------------------------------

## Kit trees on the layout's tree spots, then grass, flowers, bushes, pebbles
## and mushrooms scattered off trodden ground. See data/nature.json.
func _build_nature() -> void:
	var holder := Node3D.new()
	holder.name = "Nature"
	add_child(holder)
	var cfg := NatureKit.config()
	NatureKit.add_instances(holder, "tree", tree_items(), 0.0, true, "trees")
	var skip: Array = cfg.get("mobile_skip", []) if OS.has_feature("mobile") else []
	for group: Dictionary in cfg.get("scatter", []):
		var group_name := str(group.get("name", ""))
		if skip.has(group_name):
			continue
		if not _scatter_cache.has(group_name):
			_scatter_cache[group_name] = scatter_items(group)
		NatureKit.add_instances(holder, str(group.get("wind", "none")), _kept_scatter(group, _scatter_cache[group_name]),
			float(group.get("visible_to", 0.0)), bool(group.get("shadows", false)), group_name)


## Scatter items still on open ground (new lanes and building sites wear the
## ground after the meadow was scattered).
func _kept_scatter(group: Dictionary, items: Dictionary) -> Dictionary:
	var clear := _clear_yards()
	var out := {}
	for model: String in items:
		var kept := []
		for it: Array in items[model]:
			var o: Vector3 = (it[0] as Transform3D).origin
			if _scatter_ok(group, wear_at(Vector2(o.x, o.z))) and not _in_taken(o, clear):
				kept.append(it)
		if not kept.is_empty():
			out[model] = kept
	return out


## Yards that grow no scatter (data/nature.json "keep_clear"): their
## footprints, {"center", "rot", "half"}.
func _clear_yards() -> Array:
	var types: Array = NatureKit.config().get("keep_clear", [])
	var out := []
	for p: Dictionary in layout.props:
		if types.has(p["type"]) and VillageLayoutGenerator.YARD_HALF.has(p["type"]):
			out.append({"center": p["pos"], "rot": float(p["rot"]), "half": VillageLayoutGenerator.YARD_HALF[p["type"]]})
	if not castle_yard.is_empty():
		out.append(castle_yard)
	return out


## Whether a scatter group may grow on ground this worn.
static func _scatter_ok(group: Dictionary, wear: float) -> bool:
	var wear_range: Array = group.get("wear", [])
	if wear_range.size() == 2:
		return wear >= float(wear_range[0]) and wear <= float(wear_range[1])
	return wear <= float(group.get("max_wear", 0.05))


func _tree_cleared(index: int) -> bool:
	return territory != null and territory.cleared_trees.has(index)


## Kit tree for every layout tree spot: model -> [[Transform3D, custom], ...].
## Out past accent_min_dist, a few broadleaves become accent trees.
func tree_items() -> Dictionary:
	var cfg := NatureKit.config()
	var rng := Seeds.rng(layout.terrain_seed, "nature_trees")
	var kinds: Dictionary = cfg.get("trees", {})
	var accents: Array = cfg.get("accents", [])
	var accent_dist := float(cfg.get("accent_min_dist", 75.0))
	var items := {}
	for ti in layout.trees.size():
		var t := layout.trees[ti]
		var kind := int(t.w)
		var spec: Dictionary = kinds.get(str(kind), kinds.get("0", {}))
		var roll := rng.randf()
		if kind == 0 and Vector2(t.x, t.y).length() > accent_dist:
			var acc := 0.0
			for a: Dictionary in accents:
				acc += float(a.get("chance", 0.0))
				if roll < acc:
					spec = a
					break
		var model := str(Seeds.pick(rng, spec["models"]))
		var s := t.z * float(spec.get("scale", 0.8))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var pos := TerrainHeight.on_ground(Vector3(t.x, 0, t.y)) - Vector3(0, 0.05, 0)
		var custom := NatureKit.custom(str(Seeds.pick(rng, spec.get("tints", ["#ffffff"]))), rng.randf())
		# Felled trees still roll their dice so the others keep their looks.
		if not _tree_cleared(ti):
			_add_item(items, model, Transform3D(basis, pos), custom)
	return items


## Places one scatter group (grass, flowers...): model -> [[Transform3D, custom], ...].
## Needs the terrain (wear mask) to be built first.
func scatter_items(group: Dictionary) -> Dictionary:
	var rng := Seeds.rng(layout.terrain_seed, "nature_" + str(group.get("name", "")))
	var count := int(float(group.get("count", 0)) * NatureKit.density())
	var models: Array = group.get("models", [])
	var tints: Array = group.get("tints", ["#ffffff"])
	var dist: Array = group.get("dist", [10.0, 120.0])
	var patchiness := float(group.get("patchiness", 0.0))
	var scale: Array = group.get("scale", [1.0, 1.0])
	var near_trees := float(group.get("near_trees", 0.0))
	var limit := _wear_size * 0.5 - 2.0
	var items := {}
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 15 and not models.is_empty():
		attempts += 1
		var p: Vector2
		if near_trees > 0.0:
			if layout.trees.is_empty():
				break
			var t: Vector4 = layout.trees[rng.randi() % layout.trees.size()]
			var a := rng.randf() * TAU
			p = Vector2(t.x, t.y) + Vector2(cos(a), sin(a)) * rng.randf_range(0.7, near_trees)
		else:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(float(dist[0]) * float(dist[0]), float(dist[1]) * float(dist[1])))
			p = Vector2(layout.square_center.x, layout.square_center.z) + Vector2(cos(a), sin(a)) * r
		if absf(p.x) > limit or absf(p.y) > limit:
			continue
		if not _scatter_ok(group, wear_at(p)):
			continue
		if patchiness > 0.0:
			var n := TerrainHeight.grass_variation(p.x * 0.8, p.y * 0.8)
			if rng.randf() > lerpf(1.0, smoothstep(0.35, 0.65, n), patchiness):
				continue
		var s := rng.randf_range(float(scale[0]), float(scale[1]))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var pos := TerrainHeight.on_ground(Vector3(p.x, 0, p.y)) - Vector3(0, 0.02, 0)
		_add_item(items, str(Seeds.pick(rng, models)), Transform3D(basis, pos), NatureKit.custom(str(Seeds.pick(rng, tints)), rng.randf()))
		placed += 1
	return items


## How trodden the ground is at a point (0 grass .. 1 road/square/building).
func wear_at(p: Vector2) -> float:
	if _wear == null:
		return 0.0
	return GroundWear.sample(_wear, _wear_origin, _wear_size, p)


static func _add_item(items: Dictionary, model: String, xf: Transform3D, custom: Color) -> void:
	if not items.has(model):
		items[model] = []
	items[model].append([xf, custom])


# --- Trees (primitive fallback when the nature kit is missing) -------------------------

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
	for ti in layout.trees.size():
		var t := layout.trees[ti]
		var base := TerrainHeight.on_ground(Vector3(t.x, 0, t.y))
		var s := t.z
		var yaw := Basis(Vector3.UP, _rng.randf() * TAU)
		if _tree_cleared(ti):
			continue
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
	var use_kit := PropKit.available()
	var replace: Dictionary = PropKit.config().get("replace", {}) if use_kit else {}
	var charter := territory.charter if territory else 0
	var kit_items := []
	for p in layout.props:
		var type := str(p["type"])
		# Kept spots with nothing there yet (the market cross before a market).
		if not PropKit.present(type, charter):
			continue
		# Haystacks and the log pile: the Farm & Field models, one look per spot.
		var variant := PropKit.variant_model(type, p["pos"])
		if not variant.is_empty():
			kit_items.append([variant, Transform3D(Basis(Vector3.UP, float(p["rot"])), TerrainHeight.on_ground(p["pos"]))])
			continue
		# The well, banners, signposts, trough and market cross follow the charter.
		var commons := PropKit.commons_model(type, charter)
		if not commons.is_empty():
			var at_c: Vector3 = p["pos"]
			var basis := Basis(Vector3.UP, float(p["rot"]))
			if type == "banner" and _arm_blocked(at_c, basis):
				basis = basis * Basis.from_scale(Vector3(-1, 1, 1))
			var xf := Transform3D(basis, TerrainHeight.on_ground(at_c))
			# A set of models (the forge yard), merged with the props.
			if commons.begins_with("set:"):
				kit_items.append_array(PropKit.set_items(commons.substr(4), xf))
				continue
			if PropKit.placed_whole(type):
				var centre := PropKit.instance(commons)
				if centre:
					centre.name = type.to_pascal_case()
					centre.transform = xf
					holder.add_child(centre)
					continue
			kit_items.append([commons, xf])
			continue
		if replace.has(type):
			var sets: Array = replace[type]
			var at: Vector3 = p["pos"]
			var set_name := str(sets[absi(hash(Vector2i(roundi(at.x * 10.0), roundi(at.z * 10.0)))) % sets.size()])
			kit_items.append_array(PropKit.set_items(set_name, Transform3D(Basis(Vector3.UP, float(p["rot"])), TerrainHeight.on_ground(at))))
			continue
		var node := Node3D.new()
		node.position = TerrainHeight.on_ground(p["pos"])
		node.rotation.y = float(p["rot"])
		holder.add_child(node)
		# Looks roll from the prop's position, so rebuilding the props (after
		# clearing rocks, raising a building) never changes the others.
		var at_pos: Vector3 = p["pos"]
		var prng := RandomNumberGenerator.new()
		prng.seed = hash(Vector2i(roundi(at_pos.x * 10.0), roundi(at_pos.z * 10.0)))
		match type:
			"well":
				Mats.cylinder(node, 1.1, 1.2, 0.9, Vector3(0, 0.45, 0), stone, 14)
				Mats.cylinder(node, 0.85, 0.85, 0.05, Vector3(0, 0.88, 0), Mats.hex("#2f4a5e"), 14)
				for sx: float in [-1.0, 1.0]:
					Mats.box(node, Vector3(0.15, 2.0, 0.15), Vector3(sx * 0.95, 1.0, 0), dark_wood)
				Mats.add_mesh(node, Mats.prism_mesh(Vector3(1.6, 0.8, 2.6)), Mats.hex("#8f4e31"), Vector3(0, 2.3, 0), Vector3(0, PI * 0.5, 0))
				Mats.cylinder(node, 0.08, 0.08, 1.9, Vector3(0, 1.6, 0), wood, 6, Vector3(0, 0, PI * 0.5))
			"stall":
				var cloth := Mats.hex(STALL_COLORS[prng.randi_range(0, STALL_COLORS.size() - 1)])
				for sx: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						Mats.box(node, Vector3(0.12, 2.3, 0.12), Vector3(sx * 1.3, 1.15, sz * 0.8), dark_wood)
				Mats.box(node, Vector3(2.9, 0.08, 2.0), Vector3(0, 2.32, 0), cloth, Vector3(0.12, 0, 0))
				Mats.box(node, Vector3(2.5, 0.9, 0.7), Vector3(0, 0.45, 0.4), wood)
				for i in 5:
					var good := Mats.hex(["#c94a3a", "#e3b34a", "#7fae4a", "#d8d0b8", "#8a5a9a"][prng.randi_range(0, 4)])
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
				var s := prng.randf_range(0.5, 1.4)
				var rocks: Dictionary = NatureKit.config().get("rocks", {}) if NatureKit.available() else {}
				var models: Array = rocks.get("models", [])
				var kit_mesh: Mesh = null
				if not models.is_empty():
					var pos: Vector3 = p["pos"]
					kit_mesh = NatureKit.mesh(str(models[absi(hash(Vector2i(roundi(pos.x), roundi(pos.z)))) % models.size()]), "none")
				if kit_mesh:
					var k := s * float(rocks.get("scale", 0.55))
					Mats.add_mesh(node, kit_mesh, null, Vector3(0, -0.15 * k, 0), Vector3.ZERO, Vector3(k, k, k))
				else:
					Mats.sphere(node, 0.8, Vector3(0, 0.2 * s, 0), Mats.hex("#8d8a82"), Vector3(s * 1.3, s * 0.6, s))


	if use_kit:
		kit_items.append_array(dressing_items())
	if not kit_items.is_empty():
		PropKit.add_merged(holder, kit_items)


## A banner's arm reaches out along its local +X: true if it would hang
## into a building, so the banner is mirrored to reach the other way.
func _arm_blocked(at: Vector3, basis: Basis) -> bool:
	var reach: float = PropKit.config().get("banner_reach", 1.25)
	for t: float in [0.45, 1.0]:
		var tip := at + basis.x * reach * t
		for b in layout.buildings + _site_buildings():
			var local := b.basis().inverse() * (tip - b.position)
			if absf(local.x) < b.footprint.x * 0.5 + 0.3 and absf(local.z) < b.footprint.y * 0.5 + 0.3:
				return true
	return false


## Extra props around buildings by type (data/props.json "dressing"):
## [[model, Transform3D], ...]. Chances are rolled per building so it's
## stable. A home's yard sets follow its level ("@tier") and need their whole
## footprint ("yard_half") clear, of each other too; other spots on roads,
## in fields or inside another building are skipped. Also notes the solid
## pieces for walking (layout.dressing_obstacles).
func dressing_items() -> Array:
	var cfg := PropKit.config()
	var dressing: Dictionary = cfg.get("dressing", {})
	var sets: Dictionary = cfg.get("sets", {})
	var yard_half: Dictionary = cfg.get("yard_half", {})
	var solid: Dictionary = WorldGeometry.cfg().get("dressing", {})
	var clearance := float(cfg.get("road_clearance", 0.8))
	var out := []
	var taken := []
	if territory:
		for site in territory.sites:
			if not site.is_upgrade():  # a new building going up (an upgrade keeps its footprint)
				var sb := site.building
				taken.append({"center": sb.position, "rot": sb.rotation, "half": sb.footprint * 0.5 + Vector2(0.4, 0.4)})
	layout.dressing_obstacles.clear()
	yard_rects.clear()
	# Yards drawn as sets (the training yard): nothing else goes inside them,
	# and their solid pieces block walking.
	var charter := territory.charter if territory else 0
	for p: Dictionary in layout.props:
		var model := PropKit.commons_model(str(p["type"]), charter)
		if not model.begins_with("set:"):
			continue
		if VillageLayoutGenerator.YARD_HALF.has(p["type"]):
			taken.append({"center": p["pos"], "rot": float(p["rot"]), "half": VillageLayoutGenerator.YARD_HALF[p["type"]]})
		for it: Array in PropKit.set_items(model.substr(4), Transform3D(Basis(Vector3.UP, float(p["rot"])), p["pos"])):
			_add_obstacles(solid.get(it[0]), it[1])
	for b in layout.buildings:
		var list: Array = dressing.get(b.type, [])
		var placed := {}  # a set listed again is a second choice of spot
		for i in list.size():
			var e: Array = list[i]
			var roll := float(absi(hash("%d:%d" % [b.id, i])) % 1000) / 1000.0
			if roll >= float(e[6]):
				continue
			var set_name := PropKit.dressing_set(str(e[0]), b.tier)
			if set_name == "" or placed.has(set_name) or (sets.get(set_name, []) as Array).is_empty():
				continue
			var local := Vector3(float(e[1]) * b.footprint.x * 0.5 + float(e[3]), 0, float(e[2]) * b.footprint.y * 0.5 + float(e[4]))
			var pos := b.position + b.basis() * local
			var rot := b.rotation + deg_to_rad(float(e[5]))
			if yard_half.has(set_name):
				var h: Array = yard_half[set_name]
				var half := Vector2(float(h[0]), float(h[1]))
				if not VillageLayoutGenerator.dressing_clear(layout, b, pos, rot, half, taken):
					continue
				taken.append({"center": pos, "rot": rot, "half": half})
				yard_rects.append({"set": set_name, "building": b.id, "center": pos, "rot": rot, "half": half})
			elif road_clearance(Vector2(pos.x, pos.z)) < clearance or _blocked_for_props(pos, b) or _in_taken(pos, taken):
				continue
			var items := PropKit.set_items(set_name, Transform3D(Basis(Vector3.UP, rot), TerrainHeight.on_ground(pos)))
			for it: Array in items:
				_add_obstacles(solid.get(it[0]), it[1])
			out.append_array(items)
			placed[set_name] = true
	return out


## A solid piece's circles for walking (data/controls.json "dressing"): a
## radius at its origin, or circles [x, z, radius] in its own frame.
func _add_obstacles(shape: Variant, xf: Transform3D) -> void:
	if shape is Array:
		for c: Array in shape:
			var o := xf * Vector3(float(c[0]), 0, float(c[1]))
			layout.dressing_obstacles.append(Vector3(o.x, o.z, float(c[2])))
	elif shape != null:
		layout.dressing_obstacles.append(Vector3(xf.origin.x, xf.origin.z, float(shape)))


func _in_taken(pos: Vector3, taken: Array) -> bool:
	for r: Dictionary in taken:
		if VillageLayoutGenerator._point_in_rect(pos, r, 0.3):
			return true
	return false


## Distance from a point to the nearest road edge (negative = on the road).
func road_clearance(p: Vector2) -> float:
	var best := INF
	for road in layout.roads:
		var pts: PackedVector3Array = road["points"]
		var half := float(road["width"]) * 0.5
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1].x, pts[i - 1].z)
			var b := Vector2(pts[i].x, pts[i].z)
			var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, p.distance_to(a.lerp(b, t)) - half)
	return best


## Inside (or right against) another building, in a field, or on a yard prop.
func _blocked_for_props(pos: Vector3, owner: BuildingData) -> bool:
	for b in layout.buildings + _site_buildings():
		if b == owner:
			continue
		var local := b.basis().inverse() * (pos - b.position)
		if absf(local.x) < b.footprint.x * 0.5 + 0.6 and absf(local.z) < b.footprint.y * 0.5 + 0.6:
			return true
	for f in layout.fields:
		var c: Vector3 = f["center"]
		var size: Vector2 = f["size"]
		var local := Basis(Vector3.UP, float(f["rot"])).inverse() * (pos - c)
		if absf(local.x) < size.x * 0.5 + 1.0 and absf(local.z) < size.y * 0.5 + 1.0:
			return true
	var radii: Dictionary = WorldGeometry.cfg().get("props", {})
	for p in layout.props:
		if p["type"] in ["haystack", "lumber", "cart", "forge"] and Vector2(pos.x - p["pos"].x, pos.z - p["pos"].z).length() < float(radii.get(p["type"], 1.0)) + 0.6:
			return true
	return false


# --- Buildings -----------------------------------------------------------------------------------

func _build_buildings() -> void:
	var holder := Node3D.new()
	holder.name = "Buildings"
	add_child(holder)
	for b in layout.buildings:
		var node := BuildingFactory.build(b)
		holder.add_child(node)
		building_nodes[b.id] = node


func add_building_node(b: BuildingData) -> Node3D:
	var holder := get_node_or_null("Buildings")
	var node := BuildingFactory.build(b)
	holder.add_child(node)
	building_nodes[b.id] = node
	return node


## Rebuilds a building's look (e.g. after a home gains a floor).
func replace_building_node(b: BuildingData) -> Node3D:
	var old: Node = building_nodes.get(b.id, null)
	if old:
		old.get_parent().remove_child(old)
		old.queue_free()
	return add_building_node(b)


## Shows or hides a building (a home is hidden while its site rebuilds it).
func set_building_visible(building_id: int, on: bool) -> void:
	var node: Node3D = building_nodes.get(building_id, null)
	if node:
		node.visible = on


# --- Building sites & refreshing (Phase 3) ------------------------------------------------

func _site_buildings() -> Array[BuildingData]:
	var out: Array[BuildingData] = []
	if territory:
		for s in territory.sites:
			out.append(s.building)
	return out


func _build_sites() -> void:
	var holder := Node3D.new()
	holder.name = "Sites"
	add_child(holder)
	if territory:
		for s in territory.sites:
			add_site(s)


func add_site(site: ConstructionSite) -> ConstructionView:
	var view := ConstructionView.new()
	get_node("Sites").add_child(view)
	view.setup(site)
	site_nodes[site.id()] = view
	if site.is_upgrade():
		set_building_visible(site.id(), false)
	return view


func remove_site(building_id: int) -> void:
	var view: Node = site_nodes.get(building_id, null)
	if view:
		view.queue_free()
	site_nodes.erase(building_id)


## Moves every site's look to its current progress.
func update_sites() -> void:
	if territory == null:
		return
	for s in territory.sites:
		var view: ConstructionView = site_nodes.get(s.id(), null)
		if view:
			view.set_progress(s.progress())


## Re-reads the ground after the layout changed (new lane, site, building):
## worn earth, roads, trees and grass. Untouched parts of the meadow keep
## exactly the same plants.
func refresh_ground() -> void:
	var cfg: Dictionary = GameData.load_file("art_style").get("terrain", {})
	var wear_cfg: Dictionary = cfg.get("wear", {})
	_wear = GroundWear.bake(layout, _wear_origin, _wear_size, int(wear_cfg.get("mask_size", 512)), wear_cfg, _site_buildings())
	if _terrain and _terrain.material_override is ShaderMaterial:
		(_terrain.material_override as ShaderMaterial).set_shader_parameter("wear_mask", ImageTexture.create_from_image(_wear))
	_replace_holder("Roads", _build_roads)
	if NatureKit.available():
		_replace_holder("Nature", _build_nature)
	else:
		_rng.seed = layout.terrain_seed
		_replace_holder("Trees", _build_trees)


## Rebuilds the ground mesh (a castle's site levelled, Phase 5.3), then the
## roads, trees and scatter that stand on it.
func refresh_terrain() -> void:
	TerrainHeight.set_pads(castle_pads)
	if _terrain:
		remove_child(_terrain)
		_terrain.queue_free()
		_terrain = null
	_build_terrain()
	refresh_ground()
	refresh_props()
	refresh_fields()


## Rebuilds the merged props (rocks cleared, new buildings dressed).
func refresh_props() -> void:
	_replace_holder("Props", _build_props)


## Redraws the fields (a new charter brings a new kind of fence).
func refresh_fields() -> void:
	_replace_holder("Fields", _build_fields)


## Redraws the square (a new charter brings a finer kerb).
func refresh_square() -> void:
	_replace_holder("Square", _build_square)


func _replace_holder(holder_name: String, build_fn: Callable) -> void:
	var old := get_node_or_null(holder_name)
	if old:
		remove_child(old)
		old.queue_free()
	build_fn.call()
