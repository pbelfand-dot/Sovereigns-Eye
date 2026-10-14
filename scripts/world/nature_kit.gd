class_name NatureKit
extends RefCounted
## Trees, ground cover and rocks from the Quaternius Stylized Nature MegaKit
## (3D/environments/quaternius-stylized-nature-standard), configured in
## data/nature.json.
##
## Every model is drawn through shaders/foliage.gdshader: one shared material
## per source material and wind profile, and chunked MultiMeshes whose custom
## data carries each instance's tint and wind phase. VillageBuilder decides
## where things go; this class only loads, styles and batches them.

static var _available := -1
static var _meshes: Dictionary = {}     # "model|profile" -> Mesh
static var _materials: Dictionary = {}  # "material|profile" -> ShaderMaterial


static func config() -> Dictionary:
	return GameData.load_file("nature")


static func model_path(model: String) -> String:
	return str(config().get("root", "")) + "models/%s.gltf" % model


static func available() -> bool:
	if _available < 0:
		var trees: Dictionary = config().get("trees", {})
		var ok := not trees.is_empty()
		for kind: Dictionary in trees.values():
			for model: String in kind.get("models", []):
				ok = ok and ResourceLoader.exists(model_path(model))
		_available = 1 if ok else 0
	return _available == 1


## Ground cover density for this device (phones draw less).
static func density() -> float:
	return float(config().get("mobile_density", 0.5)) if OS.has_feature("mobile") else 1.0


## A copy of the model's mesh with foliage materials for a wind profile
## ("tree", "plant" or "none"). Null if the model is missing.
static func mesh(model: String, profile: String) -> Mesh:
	var key := model + "|" + profile
	if _meshes.has(key):
		return _meshes[key]
	var out: ArrayMesh = null
	var path := model_path(model)
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			out = ((found[0] as MeshInstance3D).mesh as ArrayMesh).duplicate() as ArrayMesh
			for s in out.get_surface_count():
				var src := out.surface_get_material(s) as BaseMaterial3D
				var mat := _material(src, profile)
				if _is_canopy(src):
					# Canopy lighting needs this model's own canopy center.
					mat = mat.duplicate() as ShaderMaterial
					mat.set_shader_parameter("canopy_normals", float(config().get("canopy_normals", 0.7)))
					mat.set_shader_parameter("canopy_center", _surface_center(out, s))
				out.surface_set_material(s, mat)
		inst.free()
	_meshes[key] = out
	return out


## Adds instances under `parent` as MultiMeshes, one per model and chunk so
## the engine can cull and pick LODs per area. items: model -> [[Transform3D,
## Color custom (linear tint rgb, wind phase a)], ...]. Returns instance count.
static func add_instances(parent: Node3D, profile: String, items: Dictionary, visible_to: float = 0.0, shadows: bool = true, label: String = "") -> int:
	var chunk := float(config().get("chunk", 32.0))
	var total := 0
	var models := items.keys()
	models.sort()
	for model: String in models:
		var m := mesh(model, profile)
		if m == null:
			continue
		var buckets := {}
		for it: Array in items[model]:
			var origin: Vector3 = (it[0] as Transform3D).origin
			var cell := Vector2i(floori(origin.x / chunk), floori(origin.z / chunk))
			if not buckets.has(cell):
				buckets[cell] = []
			buckets[cell].append(it)
		var cells := buckets.keys()
		cells.sort()
		for cell: Vector2i in cells:
			var list: Array = buckets[cell]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = m
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i][0])
				mm.set_instance_custom_data(i, list[i][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s %s %d,%d" % [label, model, cell.x, cell.y]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if visible_to > 0.0:
				mmi.visibility_range_end = visible_to
				mmi.visibility_range_end_margin = 8.0
			parent.add_child(mmi)
			total += list.size()
	return total


static func _is_canopy(src: BaseMaterial3D) -> bool:
	return src != null and (config().get("white_leaves", {}) as Dictionary).has(src.resource_name)


static func _surface_center(m: ArrayMesh, surface: int) -> Vector3:
	var verts: PackedVector3Array = m.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return Vector3.ZERO
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box.get_center()


## Per-instance custom data: tint (sRGB hex from data) in linear, wind phase.
static func custom(tint_hex: String, phase: float) -> Color:
	var c := Color(tint_hex).srgb_to_linear()
	c.a = phase
	return c


static func _material(src: BaseMaterial3D, profile: String) -> Material:
	var name := src.resource_name if src else "none"
	var key := name + "|" + profile
	if _materials.has(key):
		return _materials[key]
	var cfg := config()
	var mat := ShaderMaterial.new()
	mat.resource_name = key
	mat.shader = load("res://shaders/foliage.gdshader")
	var tex: Texture2D = src.albedo_texture if src else null
	var tint := 0.0
	var white: Dictionary = cfg.get("white_leaves", {})
	if white.has(name):
		var path := str(cfg.get("root", "")) + str(white[name])
		if ResourceLoader.exists(path):
			tex = load(path)
			tint = 1.0
	elif (cfg.get("tinted", []) as Array).has(name):
		tint = 1.0
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("tint_amount", tint)
	var masked := src != null and src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.set_shader_parameter("alpha_cutoff", src.alpha_scissor_threshold if masked else 0.0)
	var overrides: Dictionary = cfg.get("material_overrides", {}).get(name, {})
	for param: String in overrides:
		mat.set_shader_parameter(param, float(overrides[param]))
	var wind: Dictionary = cfg.get("wind", {}).get(profile, {})
	mat.set_shader_parameter("wind_strength", float(wind.get("strength", 0.0)))
	mat.set_shader_parameter("wind_height", float(wind.get("height", 1.0)))
	mat.set_shader_parameter("wind_speed", float(wind.get("speed", 0.0)))
	_materials[key] = mat
	return mat
