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


static func config() -> Dictionary:
	return GameData.load_file("props")


static func model_path(model: String) -> String:
	return str(config().get("root", "")) + model + ".gltf"


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
			st.set_material(materials[key])
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
