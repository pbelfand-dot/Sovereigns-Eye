class_name FarmKit
extends RefCounted
## Draws fields from the Farm & Field models (3D/props/farm-field), as set
## out in data/farm.json: a furrowed soil bed, crops instanced in rows or on
## a grid (MultiMesh, no shadows), a fence of the charter's kind with a gate
## facing the farmhouse, and now and then a scarecrow.
##
## Static and deterministic: every roll comes from the field's position, so
## rebuilding a field (a new charter's fence) changes nothing else.

static var _available := -1


static func cfg() -> Dictionary:
	return GameData.load_file("farm")


## True when every model the fields need is in the project.
static func available() -> bool:
	if _available < 0:
		var c := cfg()
		var models: Array = []
		for crop: Dictionary in c.get("crops", {}).values():
			models.append(str(crop.get("model", "")))
		var fence: Dictionary = c.get("fence", {})
		models.append_array(fence.get("by_charter", []))
		models.append_array(fence.get("gates", []))
		var ok := not models.is_empty()
		for m in models:
			ok = ok and ResourceLoader.exists(PropKit.model_path(str(m)))
		_available = 1 if ok else 0
	return _available == 1


## The first mesh of a model (crop and fence models are one mesh each).
static func mesh_of(model: String) -> Mesh:
	var parts := PropKit.parts(model)
	return (parts[0][0] as Mesh) if not parts.is_empty() else null


static func fence_model(charter: int, gate: bool = false) -> String:
	var list: Array = cfg().get("fence", {}).get("gates" if gate else "by_charter", [])
	return str(list[clampi(charter, 0, list.size() - 1)]) if not list.is_empty() else ""


## Each field plants from its own streams, keyed by where it lies (fields
## never overlap), so redrawing a field never re-rolls it.
static func _rng(f: Dictionary, stream: String) -> RandomNumberGenerator:
	var c: Vector3 = f["center"]
	return Seeds.rng(roundi(c.x * 10.0) * 100003 + roundi(c.z * 10.0), "field:" + stream)


## Builds one field under `field` (a Node3D placed at the field's centre
## and rotation). `farm_local` is the farmhouse in the field's local space
## (for the gate), or null.
static func build_field(field: Node3D, f: Dictionary, charter: int, farm_local: Variant = null) -> void:
	var c := cfg()
	var size: Vector2 = f["size"]
	var crop: Dictionary = c.get("crops", {}).get(str(f["crop"]), c.get("crops", {}).get("wheat", {}))
	var spacing := float(crop.get("row_spacing", crop.get("spacing", 0.8)))
	field.add_child(_bed(size, spacing))
	var crops := _crops(f, crop, size)
	if crops:
		field.add_child(crops)
	_fence(field, f, size, charter, farm_local)
	_scarecrow(field, f, size, spacing)


# --- The bed -----------------------------------------------------------------------------------

## Raised soil with sloped edges and furrows between the rows (along X).
static func _bed(size: Vector2, spacing: float) -> MeshInstance3D:
	var b: Dictionary = cfg().get("bed", {})
	var h := float(b.get("height", 0.1))
	var furrow := float(b.get("furrow", 0.045))
	var edge := float(b.get("edge", 0.4))
	var sink := float(b.get("sink", 0.03))
	var soil := Color(str(b.get("soil", "#6f5134")))
	var dark := Color(str(b.get("soil_dark", "#4a3523")))
	var light := Color(str(b.get("soil_light", "#8a6a46")))
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var margin := float(cfg().get("margin", 0.45))
	var z0 := -hz + margin
	# Grid: coarse along X (furrows run along it), fine across Z.
	var xs: Array[float] = [-hx, -hx + edge * 0.5, -hx + edge]
	var nx := maxi(2, int((size.x - 2.0 * edge) / 1.5))
	for i in range(1, nx):
		xs.append(-hx + edge + (size.x - 2.0 * edge) * i / nx)
	xs.append_array([hx - edge, hx - edge * 0.5, hx])
	var zs: Array[float] = [-hz, -hz + edge * 0.5, -hz + edge]
	var nz := maxi(4, int((size.y - 2.0 * edge) / (spacing / 4.0)))
	for i in range(1, nz):
		zs.append(-hz + edge + (size.y - 2.0 * edge) * i / nz)
	zs.append_array([hz - edge, hz - edge * 0.5, hz])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := func(x: float, z: float) -> Array:
		var dx := minf(x + hx, hx - x)
		var dz := minf(z + hz, hz - z)
		var e := smoothstep(0.0, edge, minf(dx, dz))
		var ph := cos((z - z0) / spacing * TAU)
		var y := -sink + e * (h + furrow * ph * smoothstep(edge * 0.5, edge * 1.5, minf(dx, dz)))
		var col := dark.lerp(light, clampf(0.5 + 0.5 * ph, 0.0, 1.0)).lerp(soil, 0.35)
		if e < 0.99:
			col = col.lerp(soil.darkened(0.15), 1.0 - e)
		return [Vector3(x, y, z), col]
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var quad := [height.call(xs[i], zs[j]), height.call(xs[i + 1], zs[j]), height.call(xs[i + 1], zs[j + 1]), height.call(xs[i], zs[j + 1])]
			# Clockwise from above (Godot front faces).
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(quad[k][1])
				st.add_vertex(quad[k][0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Bed"
	mi.mesh = st.commit()
	mi.material_override = Mats.vertex_colored(0.95)
	return mi


# --- Crops ------------------------------------------------------------------------------------

static var _crop_mats: Dictionary = {}


## The crop's material, taking per-instance tint (MultiMesh colours).
static func _tinted(mesh: Mesh) -> Material:
	var src := mesh.surface_get_material(0)
	var key := src.resource_name if src else "none"
	if not _crop_mats.has(key):
		var m: BaseMaterial3D = (src.duplicate() if src is BaseMaterial3D else StandardMaterial3D.new()) as BaseMaterial3D
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		_crop_mats[key] = m
	return _crop_mats[key]


static func crop_transforms(f: Dictionary, crop: Dictionary, size: Vector2) -> Array:
	var c := cfg()
	var b: Dictionary = c.get("bed", {})
	var margin := float(c.get("margin", 0.45))
	var y := float(b.get("height", 0.1)) - float(b.get("sink", 0.03)) + float(b.get("furrow", 0.045)) * 0.6
	var rng := _rng(f, "crops")
	var out := []  # [Transform3D, shade]
	var usable_x := size.x - margin * 2.0
	var usable_z := size.y - margin * 2.0
	if usable_x < 0.5 or usable_z < 0.5:
		return out
	var shade := float(crop.get("shade", 0.1))
	if str(crop.get("layout", "rows")) == "rows":
		var spacing := float(crop.get("row_spacing", 0.6))
		var seg := float(crop.get("segment", 2.0))
		var n := maxi(1, roundi(usable_x / seg))
		var sx := usable_x / (n * seg)
		var hr: Array = crop.get("height", [0.95, 1.05])
		var rows := int(usable_z / spacing) + 1
		var z0 := -size.y * 0.5 + margin
		for r in rows:
			var z := z0 + r * spacing
			if z > size.y * 0.5 - margin * 0.5:
				break
			for i in n:
				var x := -usable_x * 0.5 + seg * sx * (i + 0.5)
				var flip := PI if rng.randf() < 0.5 else 0.0
				var basis := Basis(Vector3.UP, flip) * Basis.from_scale(Vector3(sx, rng.randf_range(float(hr[0]), float(hr[1])), 1.0))
				out.append([Transform3D(basis, Vector3(x, y, z)), rng.randf() * shade])
	else:
		var sp := float(crop.get("spacing", 0.8))
		var jit := float(crop.get("jitter", 0.1))
		var sr: Array = crop.get("scale", [0.9, 1.1])
		var cols := int(usable_x / sp) + 1
		var rows := int(usable_z / sp) + 1
		var x0 := -usable_x * 0.5 + (usable_x - (cols - 1) * sp) * 0.5
		var z0 := -size.y * 0.5 + margin
		for r in rows:
			for i in cols:
				var s := rng.randf_range(float(sr[0]), float(sr[1]))
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
				var p := Vector3(x0 + i * sp + rng.randf_range(-jit, jit), y, z0 + r * sp + rng.randf_range(-jit, jit))
				out.append([Transform3D(basis, p), rng.randf() * shade])
	return out


static func _crops(f: Dictionary, crop: Dictionary, size: Vector2) -> MultiMeshInstance3D:
	var mesh := mesh_of(str(crop.get("model", "")))
	if mesh == null:
		return null
	var items := crop_transforms(f, crop, size)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, Color.WHITE.darkened(float(items[i][1])))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crops"
	mmi.multimesh = mm
	mmi.material_override = _tinted(mesh)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = float(cfg().get("crop_visibility_range", 170.0))
	mmi.visibility_range_end_margin = 12.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mmi


# --- Fence, gate, scarecrow ---------------------------------------------------------------------

## The fence runs: [[side, start, dir, length, n, stretch]] around the field.
static func fence_sides(size: Vector2) -> Array:
	var fc: Dictionary = cfg().get("fence", {})
	var off := float(fc.get("offset", 0.45))
	var seg := float(fc.get("segment", 2.0))
	var hx := size.x * 0.5 + off
	var hz := size.y * 0.5 + off
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var out := []
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var n := maxi(1, roundi(length / seg))
		out.append([side, a, (b - a).normalized(), length, n, length / (n * seg)])
	return out


## Which side gets the gate: the one facing the farmhouse (default: +Z).
static func gate_side(size: Vector2, farm_local: Variant) -> int:
	if farm_local == null:
		return 2
	var p: Vector3 = farm_local
	var outward := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	var best := 2
	var best_d := -INF
	for side in 4:
		var d: float = (outward[side] as Vector3).dot(Vector3(p.x / maxf(size.x, 0.1), 0, p.z / maxf(size.y, 0.1)))
		if d > best_d:
			best_d = d
			best = side
	return best


## Where the fence pieces stand: {"segments": [Transform3D], "gate": Transform3D
## or null}. Each piece is turned to face out (pales, gate leaves and the good
## side of a hurdle toward the road), so it runs back from its far end.
static func fence_layout(size: Vector2, farm_local: Variant) -> Dictionary:
	var seg := float(cfg().get("fence", {}).get("segment", 2.0))
	var gate_at := gate_side(size, farm_local)
	var segments: Array[Transform3D] = []
	var gate: Variant = null
	for s: Array in fence_sides(size):
		var side: int = s[0]
		var a: Vector3 = s[1]
		var dir: Vector3 = s[2]
		var n: int = s[4]
		var sx: float = s[5]
		var yaw := atan2(-dir.z, dir.x) + PI
		var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sx, 1, 1))
		for k in n:
			var xf := Transform3D(basis, a + dir * ((k + 1) * seg * sx))
			if side == gate_at and k == n / 2 and gate == null:
				gate = xf
			else:
				segments.append(xf)
	return {"segments": segments, "gate": gate}


static func _fence(field: Node3D, f: Dictionary, size: Vector2, charter: int, farm_local: Variant) -> void:
	var seg_mesh := mesh_of(fence_model(charter))
	if seg_mesh == null:
		return
	var layout := fence_layout(size, farm_local)
	var xforms: Array[Transform3D] = layout["segments"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = seg_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Fence"
	mmi.multimesh = mm
	field.add_child(mmi)
	if layout["gate"] != null:
		var gate_xf: Transform3D = layout["gate"]
		for part: Array in PropKit.parts(fence_model(charter, true)):
			var gi := MeshInstance3D.new()
			gi.name = "Gate"
			gi.mesh = part[0]
			gi.transform = gate_xf * (part[1] as Transform3D)
			field.add_child(gi)


static func _scarecrow(field: Node3D, f: Dictionary, size: Vector2, spacing: float) -> void:
	var sc: Dictionary = cfg().get("scarecrow", {})
	var rng := _rng(f, "scarecrow")
	if rng.randf() >= float(sc.get("chance", 0.4)) or size.x < 4.0 or size.y < 4.0:
		return
	var node := PropKit.instance(str(sc.get("model", "")))
	if node == null:
		return
	var b: Dictionary = cfg().get("bed", {})
	var margin := float(cfg().get("margin", 0.45))
	var row := roundi(rng.randf_range(0.25, 0.75) * (size.y - 2.0 * margin) / spacing)
	var z := -size.y * 0.5 + margin + row * spacing
	node.name = "Scarecrow"
	node.position = Vector3(rng.randf_range(-0.3, 0.3) * size.x, float(b.get("height", 0.1)) - float(b.get("sink", 0.03)), z)
	node.rotation.y = rng.randf_range(-0.5, 0.5)
	field.add_child(node)
