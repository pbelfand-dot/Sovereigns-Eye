extends TestCase
## Farm & Field (3D/props/farm-field): crops, fences, gates, haystacks, the
## log pile and scarecrows, drawn by FarmKit from data/farm.json.

const BUDGETS := {"SE_Crop_": 450, "SE_Fence_": 450, "SE_Gate_": 500, "SE_Hay": 700, "SE_Stooks": 2100, "SE_LogPile": 700, "SE_Scarecrow": 700}


func _field(crop: String, size := Vector2(12.0, 9.0)) -> Dictionary:
	return {"center": Vector3(20, 0, 30), "size": size, "rot": 0.0, "crop": crop, "building": -1}


func test_every_farm_model_loads_within_budget() -> void:
	var dir := "res://3D/props/farm-field/models/"
	var seen := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".glb"):
			continue
		seen += 1
		var root := (load(dir + f) as PackedScene).instantiate()
		var tris := 0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				check(mat != null and not mat.resource_name.is_empty(), "%s: named material" % f)
				if mat is BaseMaterial3D:
					check((mat as BaseMaterial3D).albedo_texture != null, "%s: %s has its texture" % [f, mat.resource_name])
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := 0
		for prefix: String in BUDGETS:
			if f.begins_with(prefix):
				budget = BUDGETS[prefix]
		check(budget > 0 and tris <= budget and tris > 50, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, 16, "all sixteen farm models are there")
	check(FarmKit.available(), "FarmKit finds every model it needs")


func test_a_field_is_bed_crops_fence_and_gate() -> void:
	for crop: String in ["wheat", "cabbage"]:
		var f := _field(crop)
		var node := Node3D.new()
		FarmKit.build_field(node, f, 1)
		check(node.get_node_or_null("Bed") is MeshInstance3D, "%s: a soil bed" % crop)
		var crops := node.get_node_or_null("Crops") as MultiMeshInstance3D
		check(crops != null, "%s: crops" % crop)
		if crops:
			var want := FarmKit.crop_transforms(f, FarmKit.cfg()["crops"][crop], f["size"]).size()
			check_eq(crops.multimesh.instance_count, want, "%s: one instance per planned plant or row segment" % crop)
			check(want > 20, "%s: a full field (%d)" % [crop, want])
			check_eq(crops.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "crops cast no shadows")
			check(crops.visibility_range_end > 50.0, "crops fade out far away")
		var fence := node.get_node_or_null("Fence") as MultiMeshInstance3D
		check(fence != null, "a fence")
		var gates := node.find_children("Gate*", "MeshInstance3D", false, false)
		check(gates.size() >= 1, "and a gate")
		# Segments plus the gate go all the way round. (Headless MultiMeshes
		# don't keep their transforms, so check the layout they're built from.)
		var layout := FarmKit.fence_layout(f["size"], null)
		if fence:
			check_eq(fence.multimesh.instance_count, layout["segments"].size(), "%s: one fence instance per segment" % crop)
			var covered := 0.0
			for xf: Transform3D in layout["segments"]:
				covered += xf.basis.x.length() * 2.0
			var gate_len := (layout["gate"] as Transform3D).basis.x.length() * 2.0 if layout["gate"] != null else 0.0
			var size: Vector2 = f["size"]
			var perimeter := 2.0 * (size.x + size.y + 4.0 * float(FarmKit.cfg()["fence"]["offset"]))
			check(absf(covered + gate_len - perimeter) < 0.05, "%s: the fence closes the field (%.2f + %.2f of %.2f m)" % [crop, covered, gate_len, perimeter])
		node.free()


func test_fences_follow_the_charter() -> void:
	var looks := []
	for charter in [0, 1, 3]:
		var node := Node3D.new()
		FarmKit.build_field(node, _field("wheat"), charter)
		looks.append((node.get_node("Fence") as MultiMeshInstance3D).multimesh.mesh)
		node.free()
	check(looks[0] == FarmKit.mesh_of("farm:SE_Fence_Wattle"), "a hamlet's fields have wattle hurdles")
	check(looks[1] == FarmKit.mesh_of("farm:SE_Fence_Rail"), "a village's have split rails")
	check(looks[2] == FarmKit.mesh_of("farm:SE_Fence_Paled"), "a town's are paled")


func test_the_gate_faces_the_farmhouse() -> void:
	var size := Vector2(12, 9)
	check_eq(FarmKit.gate_side(size, Vector3(20, 0, 0)), 1, "farmhouse to the east: gate on the east side")
	check_eq(FarmKit.gate_side(size, Vector3(0, 0, -15)), 0, "to the north: north side")
	check_eq(FarmKit.gate_side(size, Vector3(-9, 0, 2)), 3, "to the west: west side")
	check_eq(FarmKit.gate_side(size, null), 2, "no farmhouse: the front")


func test_fields_are_deterministic() -> void:
	var crop: Dictionary = FarmKit.cfg()["crops"]["turnip"]
	var a := FarmKit.crop_transforms(_field("turnip"), crop, Vector2(10, 8))
	var b := FarmKit.crop_transforms(_field("turnip"), crop, Vector2(10, 8))
	check_eq(str(a), str(b), "the same field plants the same way every time")
	var other := _field("turnip")
	other["center"] = Vector3(-40, 0, 12)
	check(str(FarmKit.crop_transforms(other, crop, Vector2(10, 8))) != str(a), "another field differs")


func test_the_village_uses_the_farm_models() -> void:
	var w := WorldGenerator.generate("farm-village")
	TerritorySystem.initialize(w)
	var b := VillageBuilder.new()
	b.territory = w.territory
	b.build(w.layout)
	var fields := b.get_node("Fields").get_children()
	check_eq(fields.size(), w.layout.fields.size(), "every field is drawn")
	var with_crops := 0
	for f in fields:
		if f.get_node_or_null("Crops"):
			with_crops += 1
	check_eq(with_crops, fields.size(), "with its crops")
	for type: String in ["haystack", "lumber"]:
		for p in w.layout.props_of_type(type):
			check(PropKit.variant_model(type, p["pos"]).begins_with("farm:"), "%s uses a farm model" % type)
	var farm_surfaces := 0
	for mi: MeshInstance3D in b.get_node("Props").find_children("Props *", "MeshInstance3D", false, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == "MI_Farm":
				farm_surfaces += 1
	check(farm_surfaces > 0, "haystacks are merged with the props")
	b.free()


func test_collision_covers_haystacks_and_the_log_pile() -> void:
	var radii: Dictionary = WorldGeometry.cfg().get("props", {})
	var body := float(WorldGeometry.cfg().get("walk", {}).get("body_radius", 0.35))
	for type: String in ["haystack", "lumber"]:
		for model: String in PropKit.config()["variants"][type]:
			var root := (load(PropKit.model_path(model)) as PackedScene).instantiate()
			var reach := 0.0
			for cs: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
				for p: Vector3 in (cs.shape as ConvexPolygonShape3D).points:
					reach = maxf(reach, Vector2(p.x, p.z).length())
			check(reach <= float(radii[type]) + body + 0.05, "the heir stays clear of %s (%.2f m vs %.2f + %.2f)" % [model, reach, float(radii[type]), body])
			root.free()


func test_haystacks_and_log_piles_have_room_in_the_yard() -> void:
	# The full-size stacks (up to 2.1 m) and the log pile get their own spot:
	# off the walls, out of the fields and off the road.
	var radii: Dictionary = WorldGeometry.cfg().get("props", {})
	var seen := 0
	for seed_text in ["farm-village", "9", "12345", "harvest", "oakmere"]:
		var layout := VillageLayoutGenerator.new().generate(Seeds.from_text(seed_text))
		var b := VillageBuilder.new()
		b.layout = layout
		for type: String in ["haystack", "lumber"]:
			for p: Dictionary in layout.props_of_type(type):
				seen += 1
				var pos: Vector3 = p["pos"]
				var r := float(radii[type])
				check(layout.yard_spot_clear(pos, r), "%s %s at %s keeps off the walls" % [seed_text, type, pos])
				for f: Dictionary in layout.fields:
					var local := Basis(Vector3.UP, float(f["rot"])).inverse() * (pos - (f["center"] as Vector3))
					var size: Vector2 = f["size"]
					check(absf(local.x) > size.x * 0.5 + r or absf(local.z) > size.y * 0.5 + r, "%s %s at %s stays out of the fields" % [seed_text, type, pos])
				check(b.road_clearance(Vector2(pos.x, pos.z)) > r * 0.5, "%s %s at %s is off the road" % [seed_text, type, pos])
		b.free()
	check(seen > 10, "the villages have haystacks and log piles (%d)" % seen)


func test_older_saves_drop_stacks_against_a_wall() -> void:
	# v7 layouts put stacks where the old, smaller haystack fitted: against
	# (or inside) the farmhouse. Migration drops those and keeps the rest.
	var st := WorldGenerator.generate("farm-migrate")
	var farm: BuildingData = null
	for bd in st.layout.buildings:
		if bd.type == "farmhouse":
			farm = bd
			break
	var against := farm.position + farm.basis() * Vector3(0, 0, -farm.footprint.y * 0.5 - 0.4)
	var inside := farm.position
	st.layout.props.append({"type": "haystack", "pos": against, "rot": 0.0})
	st.layout.props.append({"type": "haystack", "pos": inside, "rot": 0.0})
	var before := st.layout.props.size()
	var old := JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary
	old["save_version"] = 7
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check_eq(migrated.layout.props.size(), before - 2, "the two walled-in stacks are dropped, nothing else")
	for p: Dictionary in migrated.layout.props_of_type("haystack"):
		check((p["pos"] as Vector3).distance_to(against) > 0.1 and (p["pos"] as Vector3).distance_to(inside) > 0.1, "neither is left")
	check_eq(int(SaveManager.migrate(JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary)["save_version"]), WorldState.SAVE_VERSION, "a current save is left alone")


func test_our_own_textures_import_like_the_kits() -> void:
	# VRAM-compressed with mipmaps, as the Quaternius trim sheets are: an
	# uncompressed atlas costs ~4 MB and crops shimmer far away without mips.
	var seen := 0
	var dirs: Array[String] = []
	for category in ["props", "buildings"]:
		for family in DirAccess.get_directories_at("res://3D/%s/" % category):
			dirs.append("res://3D/%s/%s/textures/" % [category, family])
	for dir in dirs:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".png.import"):
				continue
			seen += 1
			var cfg := ConfigFile.new()
			check_eq(cfg.load(dir + f), OK, "%s reads" % f)
			check_eq(int(cfg.get_value("params", "compress/mode", -1)), 2, "%s is VRAM-compressed" % f)
			check(bool(cfg.get_value("params", "mipmaps/generate", false)), "%s has mipmaps" % f)
	check(seen >= 2, "the commons and farm atlases are checked (%d)" % seen)
