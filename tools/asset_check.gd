extends SceneTree
## Checks imported 3D assets the way the game will load them: triangles,
## materials and their textures (every slot must resolve), automatic LODs,
## collision shapes and size. Fails (exit 1) on a missing texture, an
## unnamed material or a model without geometry.
##   godot --headless --path . --script res://tools/asset_check.gd -- <res://dir/> [json_out]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if not args.is_empty() else "res://3D/props/village-commons/models/"
	var out := args[1] if args.size() > 1 else ""
	var report := {"dir": dir, "models": [], "problems": []}
	var files := DirAccess.get_files_at(dir)
	for f in files:
		if not f.ends_with(".glb") and not f.ends_with(".gltf"):
			continue
		var path := dir.path_join(f)
		var scene := load(path) as PackedScene
		if scene == null:
			report["problems"].append("%s: does not load" % f)
			continue
		var root := scene.instantiate() as Node3D
		var info := {"file": f, "tris": 0, "surfaces": 0, "materials": [], "textures": [], "lods": [], "collision": [], "size": ""}
		var aabb := AABB()
		var first := true
		var mats := {}
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := mi.mesh
			if mesh == null:
				continue
			var xf := _global(mi, root)
			var box := xf * mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
			for s in mesh.get_surface_count():
				info["surfaces"] += 1
				var arrays := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				info["tris"] += (idx.size() if idx.size() > 0 else verts.size()) / 3
				var rs := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
				info["lods"].append((rs.get("lods", []) as Array).size())
				var mat := mesh.surface_get_material(s)
				if mat == null or mat.resource_name.is_empty():
					report["problems"].append("%s: surface %d has no named material" % [f, s])
					continue
				mats[mat.resource_name] = true
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					for slot: String in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture"]:
						var tex: Texture2D = bm.get(slot)
						if tex:
							if not tex.resource_path in info["textures"]:
								info["textures"].append(tex.resource_path)
		for body in root.find_children("*", "CollisionShape3D", true, false):
			var cs := body as CollisionShape3D
			info["collision"].append(cs.shape.get_class() if cs.shape else "none")
		info["materials"] = mats.keys()
		info["size"] = "%.2f x %.2f x %.2f m" % [aabb.size.x, aabb.size.y, aabb.size.z]
		if info["tris"] == 0:
			report["problems"].append("%s: no geometry" % f)
		for t: String in info["textures"]:
			if not ResourceLoader.exists(t):
				report["problems"].append("%s: missing texture %s" % [f, t])
		report["models"].append(info)
		print("%-26s %6d tris  %d surf  lods %s  %s  mats %s  col %s" % [f, info["tris"], info["surfaces"], info["lods"], info["size"], info["materials"], info["collision"]])
		root.free()
	print("textures used: ", _shared(report))
	for p in report["problems"]:
		print("PROBLEM: ", p)
	if not out.is_empty():
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string(JSON.stringify(report, "  "))
	quit(1 if not (report["problems"] as Array).is_empty() else 0)


func _global(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _shared(report: Dictionary) -> Array:
	var all := {}
	for m: Dictionary in report["models"]:
		for t: String in m["textures"]:
			all[t] = true
	return all.keys()
