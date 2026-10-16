class_name PropKit
extends RefCounted
## Props from the Quaternius Fantasy Props MegaKit
## (3D/props/quaternius-fantasy-props-standard), configured in data/props.json.
##
## A "set" is a small arrangement of kit models (a market stall with its
## goods, a smith's anvil with a bucket and chain...). VillageBuilder decides
## where sets go; this class expands them into models and merges everything
## into one mesh per chunk with one surface per shared material, so a whole
## village of props costs a few draw calls.

static var _available := -1
static var _parts: Dictionary = {}  # model -> [[Mesh, Transform3D], ...]
static var _banner_material: ShaderMaterial

static func config() -> Dictionary:
	return GameData.load_file("props")


## A kit model's file. "family:NAME" is one of the game's own families
## (data/props.json "roots": commons, farm...), the rest come from the
## Fantasy Props kit.
static func model_path(model: String) -> String:
	var colon := model.find(":")
	if colon > 0:
		var roots: Dictionary = config().get("roots", {})
		return str(roots.get(model.left(colon), "")) + model.substr(colon + 1) + ".glb"
	return str(config().get("root", "")) + model + ".gltf"


## A layout prop drawn from the game's own models, one look per spot
## (data/props.json "variants": haystacks, the log pile), or "".
static func variant_model(type: String, at: Vector3) -> String:
	var list: Array = config().get("variants", {}).get(type, [])
	if list.is_empty():
		return ""
	var model := str(list[absi(hash(Vector2i(roundi(at.x * 10.0), roundi(at.z * 10.0)))) % list.size()])
	return model if ResourceLoader.exists(model_path(model)) else ""


## A model's meshes with their transforms inside its file (cached).
static func parts(model: String) -> Array:
	return _model_parts(model)


## The model for a layout prop under a charter (data/props.json
## "by_charter": the well, banners, signposts, trough and market cross grow
## finer as the settlement does), or "" if the type has none at this
## charter or its file is missing.
static func commons_model(type: String, charter: int) -> String:
	var by: Dictionary = config().get("by_charter", {})
	var list: Array = by.get(type, [])
	if list.is_empty():
		return ""
	var model := str(list[clampi(charter, 0, list.size() - 1)])
	return model if not model.is_empty() and ResourceLoader.exists(model_path(model)) else ""


## False for a prop whose "by_charter" entry at this charter is empty (the
## market cross before the Crown grants a market): its spot is kept, but
## nothing stands there yet, so it is neither drawn nor in anyone's way.
static func present(type: String, charter: int) -> bool:
	var list: Array = config().get("by_charter", {}).get(type, [])
	return list.is_empty() or not str(list[clampi(charter, 0, list.size() - 1)]).is_empty()


## Centrepieces placed as their own node, keeping their LODs (data/props.json "whole").
static func placed_whole(type: String) -> bool:
	return type in config().get("whole", ["well"])


## A whole model as its own node (keeps the mesh's automatic LODs; used for
## one-off centrepieces like the well). Its collision proxy is kept on the
## buildings' layer and never queried by walking (WorldGeometry does that).
static func instance(model: String) -> Node3D:
	var path := model_path(model)
	if not ResourceLoader.exists(path):
		return null
	var node := (load(path) as PackedScene).instantiate() as Node3D
	for body: CollisionObject3D in node.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 2
		body.collision_mask = 0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		_runtime_materials(mi)
	return node


## The banner cloth sways in the wind (shaders/banner_wind.gdshader).
static func runtime_material(mat: Material) -> Material:
	if mat == null or mat.resource_name != "MI_Commons_Banner" or not mat is BaseMaterial3D:
		return mat
	if _banner_material == null:
		_banner_material = ShaderMaterial.new()
		_banner_material.resource_name = "MI_Commons_Banner_Wind"
		_banner_material.shader = load("res://shaders/banner_wind.gdshader")
		_banner_material.set_shader_parameter("albedo_texture", (mat as BaseMaterial3D).albedo_texture)
	return _banner_material


static func _runtime_materials(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		var rt := runtime_material(mat)
		if rt != mat:
			mi.set_surface_override_material(s, rt)


static func available() -> bool:
	if _available < 0:
		var sets: Dictionary = config().get("sets", {})
		var ok := not sets.is_empty()
		for set_name: String in sets:
			for entry: Array in sets[set_name]:
				ok = ok and ResourceLoader.exists(model_path(str(entry[0])))
		_available = 1 if ok else 0
	return _available == 1


## The models of a set placed at `origin`: [[model, Transform3D], ...].
static func set_items(set_name: String, origin: Transform3D) -> Array:
	var out := []
	for entry: Array in config().get("sets", {}).get(set_name, []):
		var local := Transform3D(Basis(Vector3.UP, deg_to_rad(float(entry[4]))), Vector3(float(entry[1]), float(entry[2]), float(entry[3])))
		out.append([str(entry[0]), origin * local])
	return out


## Merges placed models into MeshInstance3Ds (one per chunk, one surface per
## material) under `parent`. Returns the number of models drawn.
static func add_merged(parent: Node3D, items: Array) -> int:
	var chunk := float(config().get("chunk", 64.0))
	var buckets := {}
	for it: Array in items:
		var o: Vector3 = (it[1] as Transform3D).origin
		var cell := Vector2i(floori(o.x / chunk), floori(o.z / chunk))
		if not buckets.has(cell):
			buckets[cell] = []
		buckets[cell].append(it)
	var drawn := 0
	var cells := buckets.keys()
	cells.sort()
	for cell: Vector2i in cells:
		var tools := {}      # material name -> SurfaceTool
		var materials := {}  # material name -> Material
		for it: Array in buckets[cell]:
			var parts := _model_parts(str(it[0]))
			if parts.is_empty():
				continue
			drawn += 1
			for part: Array in parts:
				var mesh: Mesh = part[0]
				var xf: Transform3D = (it[1] as Transform3D) * (part[1] as Transform3D)
				for s in mesh.get_surface_count():
					var mat := mesh.surface_get_material(s)
					var key := mat.resource_name if mat else "none"
					if not tools.has(key):
						var st := SurfaceTool.new()
						st.begin(Mesh.PRIMITIVE_TRIANGLES)
						tools[key] = st
						materials[key] = mat
					(tools[key] as SurfaceTool).append_from(mesh, s, xf)
		if tools.is_empty():
			continue
		var merged := ArrayMesh.new()
		var keys := tools.keys()
		keys.sort()
		for key: String in keys:
			var st: SurfaceTool = tools[key]
			st.set_material(runtime_material(materials[key]))
			st.commit(merged)
		var mi := MeshInstance3D.new()
		mi.name = "Props %d,%d" % [cell.x, cell.y]
		mi.mesh = merged
		parent.add_child(mi)
	return drawn


## A model's meshes with their transforms inside the model file (cached).
static func _model_parts(model: String) -> Array:
	if _parts.has(model):
		return _parts[model]
	var out := []
	var path := model_path(model)
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			var xf := mi.transform
			var node := mi.get_parent()
			while node != null and node != inst:
				if node is Node3D:
					xf = (node as Node3D).transform * xf
				node = node.get_parent()
			out.append([mi.mesh, xf])
		inst.free()
	_parts[model] = out
	return out
