extends TestCase
## The Smithy family (3D/props/smithy): the smith's forge yard against the
## smithy's side wall, a village hearth or a town forge by charter.

const BUDGETS := {"SE_Forge_": 2500, "SE_Anvil": 800, "SE_SlackTub": 800, "SE_Coal": 800, "SE_ToolRack": 1000, "SE_Grindstone": 1000}
const SEEDS := ["smithy", "9", "12345", "harvest", "oakmere"]


func _yard_rect(p: Dictionary) -> Dictionary:
	return {"center": p["pos"], "rot": float(p["rot"]), "half": VillageLayoutGenerator.YARD_HALF["forge"]}


func test_every_smithy_model_loads_within_budget() -> void:
	var dir := "res://3D/props/smithy/models/"
	var seen := 0
	var glowing := false
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".glb"):
			continue
		seen += 1
		var root := (load(dir + f) as PackedScene).instantiate()
		var tris := 0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				check(mat != null and not mat.resource_name.is_empty(), "%s: named material" % f)
				if mat and mat.resource_name.begins_with("MI_") and not mat.resource_name.begins_with("MI_Smithy"):
					check(mat.albedo_texture != null, "%s: %s has its texture" % [f, mat.resource_name])
				if mat and mat.resource_name == "MI_Smithy_Embers":
					glowing = glowing or (mat.emission_enabled and mat.emission_energy_multiplier > 1.0)
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := 0
		for prefix: String in BUDGETS:
			if f.begins_with(prefix):
				budget = BUDGETS[prefix]
		check(budget > 0 and tris <= budget and tris > 100, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, 8, "all eight smithy models are there")
	check(glowing, "the forge's embers glow (emissive, brighter than 1)")


func test_every_smithy_has_its_forge_yard_against_a_wall() -> void:
	for seed_text: String in SEEDS:
		var l := VillageLayoutGenerator.new().generate(Seeds.from_text(seed_text))
		var smithies := l.buildings.filter(func(b: BuildingData) -> bool: return b.type == "smithy")
		var yards := l.props_of_type("forge")
		check_eq(yards.size(), smithies.size(), "%s: one forge yard per smithy" % seed_text)
		if yards.is_empty() or smithies.is_empty():
			continue
		var b: BuildingData = smithies[0]
		var y: Dictionary = yards[0]
		var rect := _yard_rect(y)
		var half: Vector2 = rect["half"]
		# Its back (local -Z) is against the smithy's wall, its front faces out.
		var back := (y["pos"] as Vector3) + Basis(Vector3.UP, float(y["rot"])) * Vector3(0, 0, -half.y)
		var local := b.basis().inverse() * (back - b.position)
		var gap := minf(absf(absf(local.x) - b.footprint.x * 0.5), absf(absf(local.z) - b.footprint.y * 0.5))
		check(gap < 0.2, "%s: the yard backs onto the smithy's wall (%.2f m)" % [seed_text, gap])
		var outward := Basis(Vector3.UP, float(y["rot"])) * Vector3(0, 0, 1)
		check(outward.dot(((y["pos"] as Vector3) - b.position).normalized()) > 0.5, "%s: and faces away from it" % seed_text)
		# Clear of every other building, the roads, the fields and the other props.
		for s in VillageLayoutGenerator._rect_samples(rect["center"], rect["rot"], half):
			for other in l.buildings:
				if other != b:
					check(not VillageLayoutGenerator._point_in_rect(s, {"center": other.position, "rot": other.rotation, "half": other.footprint * 0.5}, 0.3), "%s: the yard is clear of the %s" % [seed_text, other.type])
			for f: Dictionary in l.fields:
				check(not VillageLayoutGenerator._point_in_rect(s, {"center": f["center"], "rot": f["rot"], "half": (f["size"] as Vector2) * 0.5}, 0.3), "%s: and of the fields" % seed_text)
		for p: Dictionary in l.props:
			if p != y:
				check(not VillageLayoutGenerator._point_in_rect(p["pos"], rect, 0.3), "%s: no %s in the yard" % [seed_text, p["type"]])
		for t in l.trees:
			check(not VillageLayoutGenerator._point_in_rect(Vector3(t.x, 0, t.y), rect, 0.3), "%s: no tree in the yard" % seed_text)


func test_the_forge_follows_the_charter() -> void:
	check_eq(PropKit.commons_model("forge", 0), "set:forge_yard_village", "a hamlet's smith works a village hearth")
	check_eq(PropKit.commons_model("forge", 1), "set:forge_yard_village", "so does a village's")
	check_eq(PropKit.commons_model("forge", 2), "set:forge_yard_town", "a market town's has a town forge")
	check_eq(PropKit.commons_model("forge", 3), "set:forge_yard_town", "and a town's")
	for charter: int in [0, 3]:
		var w := WorldGenerator.generate("smithy")
		TerritorySystem.initialize(w)
		w.territory.charter = charter
		var b := VillageBuilder.new()
		b.territory = w.territory
		b.build(w.layout)
		var mats := {}
		for mi: MeshInstance3D in b.get_node("Props").find_children("Props *", "MeshInstance3D", false, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m:
					mats[m.resource_name] = true
		check(mats.has("MI_Smithy_Embers") and mats.has("MI_Smithy_Coal"), "charter %d: the forge yard is merged with the props" % charter)
		# The yard is one walking obstacle; nothing invisible beyond it.
		var y: Dictionary = w.layout.props_of_type("forge")[0]
		var at: Vector3 = y["pos"]
		var p := WorldGeometry.resolve(w, at + Vector3(0.2, 0, 0.2), 0.35)
		check(Vector2(p.x - at.x, p.z - at.z).length() >= 2.0, "charter %d: the heir is kept out of the yard" % charter)
		b.free()


func test_the_yard_sets_fit_their_footprint() -> void:
	var half: Vector2 = VillageLayoutGenerator.YARD_HALF["forge"]
	for set_name: String in ["forge_yard_village", "forge_yard_town"]:
		check(PropKit.set_ready(set_name), "%s: every model is there" % set_name)
		for it: Array in PropKit.set_items(set_name, Transform3D()):
			var aabb := AABB()
			var first := true
			for part: Array in PropKit.parts(str(it[0])):
				var box: AABB = (it[1] as Transform3D) * (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
				aabb = box if first else aabb.merge(box)
				first = false
			var inside := absf(aabb.position.x) <= half.x + 0.05 and absf(aabb.end.x) <= half.x + 0.05 \
				and absf(aabb.position.z) <= half.y + 0.05 and absf(aabb.end.z) <= half.y + 0.05
			check(inside, "%s: %s stays inside the yard (%s)" % [set_name, it[0], aabb])


func test_older_saves_get_the_forge_yard() -> void:
	var st := WorldGenerator.generate("smithy-migrate")
	var want := st.layout.props_of_type("forge")
	check(not want.is_empty(), "the village has a forge yard to remove")
	var kept: Array[Dictionary] = []
	for p in st.layout.props:
		if p["type"] != "forge":
			kept.append(p)
	st.layout.props = kept
	var old := JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary
	old["save_version"] = 9
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	var got := migrated.layout.props_of_type("forge")
	check_eq(got.size(), 1, "the migrated village has its forge yard")
	if got.size() == 1 and not want.is_empty():
		check((got[0]["pos"] as Vector3).distance_to(want[0]["pos"]) < 0.02, "where a new village would have it")
		for p: Dictionary in migrated.layout.props:
			if p["type"] in ["barrel", "crate"]:
				check(not VillageLayoutGenerator._point_in_rect(p["pos"], _yard_rect(got[0]), 0.3), "no barrel left in the yard")
	var again := WorldState.from_dict(SaveManager.migrate(JSON.parse_string(JSON.stringify(migrated.to_dict())) as Dictionary))
	check_eq(again.layout.props_of_type("forge").size(), 1, "a current save is left alone")


func test_the_kit_anvil_gave_way_to_the_forge_yard() -> void:
	var dressing: Array = PropKit.config()["dressing"]["smithy"]
	for e: Array in dressing:
		check(str(e[0]) != "smith_anvil", "the smithy's dressing has no second anvil")
