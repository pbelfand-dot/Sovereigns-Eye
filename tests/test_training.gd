extends TestCase
## The Training Yard (3D/props/training-yard): behind or beside the barracks,
## a village's muster ground grows into a town guard's yard as the charter
## rises; soldiers drill at its pieces and the heir walks round them.

const DIR := "res://3D/props/training-yard/models/"
const BUDGETS := {"SE_Pell": 600, "SE_Dummy_Straw": 1200, "SE_Quintain": 1200, "SE_ArcheryButt": 900,
	"SE_Rack_Staves": 900, "SE_Rack_Weapons": 1300, "SE_Ring_Rope": 1000, "SE_Ring_Rail": 1300}
const SEEDS := ["9", "12345", "1", "7", "42", "2026", "smithy", "harvest", "oakmere", "brackmoor"]


func _yards(l: VillageLayout) -> Array[Dictionary]:
	return l.props_of_type("training") + l.props_of_type("training_small")


func _rect(p: Dictionary) -> Dictionary:
	return {"center": p["pos"], "rot": float(p["rot"]), "half": VillageLayoutGenerator.YARD_HALF[p["type"]]}


func _set_models(set_name: String) -> Array:
	var out := []
	for it: Array in PropKit.set_items(set_name, Transform3D()):
		out.append(str(it[0]))
	return out


func test_every_training_model_loads_within_budget() -> void:
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
		check(budget > 0 and tris <= budget and tris > 100, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, 8, "all eight training yard models are there")


func test_every_barracks_has_its_yard_behind_or_beside_it() -> void:
	var small := 0
	for seed_text: String in SEEDS:
		var w := WorldGenerator.generate(seed_text)
		var yards := _yards(w.layout)
		var barracks: BuildingData = null
		for b in w.layout.buildings:
			if b.type == "barracks":
				barracks = b
		if barracks == null:
			continue
		check_eq(yards.size(), 1, "%s: the barracks has one training yard" % seed_text)
		check(w.layout.props_of_type("dummy").is_empty(), "%s: no kit dummies left before it" % seed_text)
		if yards.size() != 1:
			continue
		var y := yards[0]
		if y["type"] == "training_small":
			small += 1
		var local := barracks.basis().inverse() * ((y["pos"] as Vector3) - barracks.position)
		check(local.z < 0.0 or absf(local.x) > barracks.footprint.x * 0.5, "%s: not on the door side (its road)" % seed_text)
		# Clear of everything but itself.
		var all := w.layout.props
		var others: Array[Dictionary] = []
		for p in all:
			if p != y:
				others.append(p)
		w.layout.props = others
		check(VillageLayoutGenerator._yard_clear(w.layout, barracks, y["pos"], float(y["rot"]), VillageLayoutGenerator.YARD_HALF[y["type"]], false),
			"%s: clear of buildings, the square, roads, fields, props and trees" % seed_text)
		w.layout.props = all
		var out := Basis(Vector3.UP, float(y["rot"])) * Vector3(0, 0, 1)
		check(out.dot((y["pos"] as Vector3) - barracks.position) > 0.0, "%s: it faces away from the wall" % seed_text)
	check(small < SEEDS.size(), "most villages have room for a full yard (%d small)" % small)
	var again := WorldGenerator.generate("9")
	check_eq(_yards(again.layout)[0]["pos"], _yards(WorldGenerator.generate("9").layout)[0]["pos"], "the same village puts it in the same place")


func test_the_yard_grows_with_the_charter() -> void:
	var want := {
		0: ["training:SE_Pell", "training:SE_Rack_Staves", "training:SE_ArcheryButt"],
		1: ["training:SE_Pell", "training:SE_Dummy_Straw", "training:SE_Rack_Staves", "training:SE_ArcheryButt"],
		2: ["training:SE_Ring_Rope", "training:SE_Dummy_Straw", "training:SE_Rack_Weapons", "training:SE_ArcheryButt"],
		3: ["training:SE_Ring_Rail", "training:SE_Quintain", "training:SE_Dummy_Straw", "training:SE_Rack_Weapons", "training:SE_ArcheryButt"],
	}
	var seen := {}
	for charter: int in want:
		for type: String in ["training", "training_small"]:
			var model := PropKit.commons_model(type, charter)
			check(model.begins_with("set:"), "%s at charter %d: a set (%s)" % [type, charter, model])
			check(PropKit.set_ready(model.substr(4)), "%s at charter %d: every model is there" % [type, charter])
		var models := _set_models(PropKit.commons_model("training", charter).substr(4))
		for m: String in want[charter]:
			check(models.has(m), "charter %d: the yard has %s" % [charter, m])
		seen[str(models)] = true
	check_eq(seen.size(), 4, "each charter's yard looks different")
	check(not _set_models("training_yard_0").has("training:SE_Ring_Rope"), "a hamlet's muster has no ring")
	check(not _set_models("training_small_3").has("training:SE_ArcheryButt"), "a small yard has no room for a butt")


func test_the_yard_sets_fit_their_footprint() -> void:
	var radii: Dictionary = WorldGeometry.cfg().get("dressing", {})
	for charter in 4:
		for type: String in ["training", "training_small"]:
			var set_name := PropKit.commons_model(type, charter).substr(4)
			var half: Vector2 = VillageLayoutGenerator.YARD_HALF[type]
			var solids: Array = []
			for it: Array in PropKit.set_items(set_name, Transform3D()):
				var aabb := AABB()
				var first := true
				for part: Array in PropKit.parts(str(it[0])):
					var box: AABB = (it[1] as Transform3D) * (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
					aabb = box if first else aabb.merge(box)
					first = false
				var inside := aabb.position.x >= -half.x - 0.3 and aabb.end.x <= half.x + 0.3 \
					and aabb.position.z >= -half.y - 0.3 and aabb.end.z <= half.y + 0.3
				check(inside, "%s: %s stays inside the yard (%s)" % [set_name, it[0], aabb])
				if radii.has(it[0]):
					solids.append([(it[1] as Transform3D).origin, float(radii[it[0]])])
			for i in solids.size():
				for j in range(i + 1, solids.size()):
					var a: Array = solids[i]
					var b: Array = solids[j]
					check(Vector2((a[0] as Vector3).x - (b[0] as Vector3).x, (a[0] as Vector3).z - (b[0] as Vector3).z).length() > float(a[1]) + float(b[1]) + 0.3,
						"%s: room to walk between its pieces" % set_name)


func test_soldiers_drill_in_the_yard() -> void:
	var w := WorldGenerator.generate("9")
	TerritorySystem.initialize(w)
	var y := _yards(w.layout)[0]
	var rect := _rect(y)
	var bl := VillageBuilder.new()
	bl.territory = w.territory
	for charter in 4:
		w.territory.charter = charter
		var spots := PropKit.drill_spots(w.layout, charter)
		check(spots.size() >= 2, "charter %d: room for at least two soldiers to drill (%d)" % [charter, spots.size()])
		bl.layout = w.layout
		bl.dressing_items()
		for s: Array in spots:
			check(VillageLayoutGenerator._point_in_rect(s[0], rect, 0.6), "charter %d: they drill inside the yard" % charter)
			check((s[0] as Vector3).distance_to(s[1]) > 0.5, "charter %d: facing what they strike" % charter)
			var free := true
			for o: Vector3 in w.layout.dressing_obstacles:
				if Vector2(o.x - (s[0] as Vector3).x, o.y - (s[0] as Vector3).z).length() < o.z + 0.2:
					free = false
			check(free, "charter %d: nobody drills inside a piece" % charter)
	bl.free()


func test_the_heir_walks_round_the_pieces_and_into_the_ring() -> void:
	var w := WorldGenerator.generate("9")
	TerritorySystem.initialize(w)
	w.territory.charter = 3
	var bl := VillageBuilder.new()
	bl.territory = w.territory
	bl.build(w.layout)
	var y := _yards(w.layout)[0]
	var xf := Transform3D(Basis(Vector3.UP, float(y["rot"])), y["pos"])
	var butt := Vector3.ZERO
	var ring := Vector3.ZERO
	for it: Array in PropKit.set_items(PropKit.commons_model(str(y["type"]), 3).substr(4), xf):
		if str(it[0]).ends_with("ArcheryButt"):
			butt = (it[1] as Transform3D).origin
		if str(it[0]).contains("Ring"):
			ring = (it[1] as Transform3D).origin
	check(butt != Vector3.ZERO, "the town yard has a butt")
	var p := WorldGeometry.resolve(w, butt + Vector3(0.1, 0, 0.1), 0.35)
	check(Vector2(p.x - butt.x, p.z - butt.z).length() >= 1.25, "the heir is kept out of the butt")
	if ring != Vector3.ZERO:
		var q := WorldGeometry.resolve(w, ring, 0.35)
		check(Vector2(q.x - ring.x, q.z - ring.z).length() < 0.05, "and can step into the ring")
	var centre := WorldGeometry.resolve(w, y["pos"], 0.35)
	check(Vector2(centre.x, centre.z).distance_to(Vector2((y["pos"] as Vector3).x, (y["pos"] as Vector3).z)) < 2.0, "the yard itself is open ground")
	# Nothing else is set down in it, and no grass grows there.
	for it: Array in bl.dressing_items():
		check(not VillageLayoutGenerator._point_in_rect((it[1] as Transform3D).origin, _rect(y), 0.0), "no dressing in the yard (%s)" % it[0])
	for r: Dictionary in bl.yard_rects:
		check(not VillageLayoutGenerator.rects_overlap(r, _rect(y), 0.0), "no home yard overlaps it")
	var wear_cfg: Dictionary = GameData.load_file("art_style").get("terrain", {}).get("wear", {})
	var origin := Vector2(-150, -150)
	var mask := GroundWear.bake(w.layout, origin, 300.0, 512, wear_cfg)
	check(GroundWear.sample(mask, origin, 300.0, Vector2((y["pos"] as Vector3).x, (y["pos"] as Vector3).z)) > 0.7, "the yard's ground is trodden bare")
	bl.free()


func test_older_saves_get_the_training_yard() -> void:
	var st := WorldGenerator.generate("training-migrate")
	var want := _yards(st.layout)
	check_eq(want.size(), 1, "the village has a training yard to take away")
	var barracks: BuildingData = null
	for b in st.layout.buildings:
		if b.type == "barracks":
			barracks = b
	# As saved before: the kit's three dummies before the barracks, no yard.
	var kept: Array[Dictionary] = []
	for p in st.layout.props:
		if not str(p["type"]).begins_with("training"):
			kept.append(p)
	for i in 3:
		kept.append({"type": "dummy", "pos": barracks.position + barracks.basis() * Vector3((i - 1) * 3.0, 0, barracks.footprint.y * 0.5 + 5.0), "rot": barracks.rotation})
	st.layout.props = kept
	var old := JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary
	old["save_version"] = 10
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	var got := _yards(migrated.layout)
	check_eq(got.size(), 1, "the migrated village has its training yard")
	check(migrated.layout.props_of_type("dummy").is_empty(), "and the kit dummies are gone")
	if got.size() == 1 and want.size() == 1:
		check_eq(got[0]["type"], want[0]["type"], "the same size of yard a new village would have")
		for p: Dictionary in migrated.layout.props:
			if p["type"] in ["barrel", "crate"]:
				check(not VillageLayoutGenerator._point_in_rect(p["pos"], _rect(got[0]), 0.3), "no barrel left in the yard")
	check_eq(int(SaveManager.migrate(old)["save_version"]), WorldState.SAVE_VERSION, "the save reaches the current version")
	var again := WorldState.from_dict(SaveManager.migrate(JSON.parse_string(JSON.stringify(migrated.to_dict())) as Dictionary))
	check_eq(_yards(again.layout).size(), 1, "a current save is left alone")
