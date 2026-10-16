extends TestCase
## The Home Yard family (3D/props/home-yard): what stands round a home, by
## the home's level (Cottage, Timber House, Townhouse), and round a farmhouse.

const BUDGETS := {"SE_Bench": 800, "SE_Garden": 1500, "SE_ChoppingBlock": 800, "SE_WaterButt": 1000, "SE_LaundryLine": 1200,
	"SE_ChickenCoop": 2000, "SE_FlowerPots": 1500}
const SEEDS := ["9", "smithy", "12345", "harvest", "oakmere"]


## A village with every cottage at `tier`, built (its yards drawn).
func _built(seed_text: String, tier: int) -> Array:
	var w := WorldGenerator.generate(seed_text)
	TerritorySystem.initialize(w)
	for b in w.layout.buildings:
		if b.type == "cottage":
			b.tier = tier
	var bl := VillageBuilder.new()
	bl.territory = w.territory
	bl.build(w.layout)
	return [w, bl]


func _models(items: Array) -> Dictionary:
	var out := {}
	for it: Array in items:
		out[str(it[0])] = int(out.get(str(it[0]), 0)) + 1
	return out


func test_every_home_model_loads_within_budget() -> void:
	var dir := "res://3D/props/home-yard/models/"
	var seen := 0
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
				if mat and mat.resource_name.begins_with("MI_") and mat.resource_name != "MI_Home_Water":
					check(mat.albedo_texture != null, "%s: %s has its texture" % [f, mat.resource_name])
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := 0
		for prefix: String in BUDGETS:
			if f.begins_with(prefix):
				budget = BUDGETS[prefix]
		check(budget > 0 and tris <= budget and tris > 100, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, 10, "all ten home yard models are there")


func test_a_homes_yard_follows_its_level() -> void:
	check_eq(PropKit.dressing_set("home_door@tier", 0), "home_door_0", "a cottage has a log bench")
	check_eq(PropKit.dressing_set("home_door@tier", 1), "home_door_1", "a timber house a plank bench")
	check_eq(PropKit.dressing_set("home_door@tier", 2), "home_door_2", "a townhouse a painted one")
	check_eq(PropKit.dressing_set("home_garden@tier", 2), "home_garden_1", "a level without its own set keeps the one below")
	check_eq(PropKit.dressing_set("home_pots@tier", 1), "", "no flower pots below a townhouse")
	check_eq(PropKit.dressing_set("home_coop@tier", 0), "", "no hens at a poor cottage")
	check((PropKit.config()["sets"]["home_coop_2"] as Array).is_empty(), "nor at a townhouse")
	check_eq(PropKit.dressing_set("farm_crates", 2), "farm_crates", "a plain set name is itself")
	var want := {
		0: ["home:SE_Bench_Log", "home:SE_Garden_Poor", "home:SE_ChoppingBlock", "home:SE_LaundryLine"],
		1: ["home:SE_Bench", "home:SE_Garden", "home:SE_WaterButt", "home:SE_ChickenCoop"],
		2: ["home:SE_Bench_Painted", "home:SE_FlowerPots", "home:SE_Garden", "home:SE_WaterButt"],
	}
	var never := {0: ["home:SE_Bench_Painted", "home:SE_FlowerPots"], 1: ["home:SE_Bench_Painted", "home:SE_FlowerPots", "home:SE_Bench_Log"],
		2: ["home:SE_Bench_Log", "home:SE_Garden_Poor"]}
	for tier: int in want:
		var built := _built("9", tier)
		var bl: VillageBuilder = built[1]
		var have := _models(bl.dressing_items())
		for m: String in want[tier]:
			check(int(have.get(m, 0)) > 0, "level %d: the homes have %s" % [tier, m])
		for m: String in never[tier]:
			check(int(have.get(m, 0)) == 0, "level %d: and no %s" % [tier, m])
		var cottages := 0
		for b in (built[0] as WorldState).layout.buildings:
			cottages += 1 if b.type == "cottage" else 0
		var doors := bl.yard_rects.filter(func(r: Dictionary) -> bool: return str(r["set"]).begins_with("home_door"))
		check(doors.size() >= cottages, "level %d: every cottage has its bench (%d of %d, and farmhouses)" % [tier, doors.size(), cottages])
		if tier == 2:
			var coops := bl.yard_rects.filter(func(r: Dictionary) -> bool: return str(r["set"]) == "home_coop_1")
			for r: Dictionary in coops:
				check_eq((built[0] as WorldState).layout.get_building(int(r["building"])).type, "farmhouse", "a townhouse keeps no hens; a farm does")
		bl.free()


func test_home_yards_keep_clear() -> void:
	for seed_text: String in SEEDS:
		var built := _built(seed_text, 1)
		var w: WorldState = built[0]
		var bl: VillageBuilder = built[1]
		bl.dressing_items()
		var l := w.layout
		var rects := bl.yard_rects
		check(rects.size() >= 30, "%s: the homes have their yards (%d)" % [seed_text, rects.size()])
		for i in rects.size():
			var r: Dictionary = rects[i]
			var owner := l.get_building(int(r["building"]))
			# Clear of every building, its own included: the yard is outside the walls.
			for b in l.buildings:
				check(not VillageLayoutGenerator.rects_overlap(r, {"center": b.position, "rot": b.rotation, "half": b.footprint * 0.5}, 0.05),
					"%s: %s of #%d keeps out of the %s" % [seed_text, r["set"], owner.id, b.type])
			for j in range(i + 1, rects.size()):
				check(not VillageLayoutGenerator.rects_overlap(r, rects[j], 0.0), "%s: %s and %s don't overlap" % [seed_text, r["set"], rects[j]["set"]])
			for f: Dictionary in l.fields:
				check(not VillageLayoutGenerator.rects_overlap(r, {"center": f["center"], "rot": f["rot"], "half": (f["size"] as Vector2) * 0.5}, 0.0),
					"%s: %s keeps out of the fields" % [seed_text, r["set"]])
			for p: Dictionary in l.props:
				if VillageLayoutGenerator.YARD_HALF.has(p["type"]):
					check(not VillageLayoutGenerator.rects_overlap(r, {"center": p["pos"], "rot": float(p["rot"]), "half": VillageLayoutGenerator.YARD_HALF[p["type"]]}, 0.0),
						"%s: %s keeps out of the %s's yard" % [seed_text, r["set"], p["type"]])
			for s in VillageLayoutGenerator._rect_samples(r["center"], float(r["rot"]), r["half"]):
				check(bl.road_clearance(Vector2(s.x, s.z)) > 0.0, "%s: %s keeps off the road" % [seed_text, r["set"]])
			for t in l.trees:
				check(not VillageLayoutGenerator._point_in_rect(Vector3(t.x, 0, t.y), r, 0.3), "%s: no tree in %s" % [seed_text, r["set"]])
			# Its back to its own house: the side nearest the house is the set's -Z.
			var back := (r["center"] as Vector3) + Basis(Vector3.UP, float(r["rot"])) * Vector3(0, 0, -(r["half"] as Vector2).y)
			var front := (r["center"] as Vector3) + Basis(Vector3.UP, float(r["rot"])) * Vector3(0, 0, (r["half"] as Vector2).y)
			check(back.distance_to(owner.position) < front.distance_to(owner.position), "%s: %s faces away from its house" % [seed_text, r["set"]])
		bl.free()


func test_the_yard_sets_fit_their_footprint() -> void:
	var halves: Dictionary = PropKit.config()["yard_half"]
	for set_name: String in halves:
		check(PropKit.set_ready(set_name), "%s: every model is there" % set_name)
		var half := Vector2(float(halves[set_name][0]), float(halves[set_name][1]))
		for it: Array in PropKit.set_items(set_name, Transform3D()):
			var aabb := AABB()
			var first := true
			for part: Array in PropKit.parts(str(it[0])):
				var box: AABB = (it[1] as Transform3D) * (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
				aabb = box if first else aabb.merge(box)
				first = false
			var inside := absf(aabb.position.x) <= half.x + 0.05 and absf(aabb.end.x) <= half.x + 0.05 \
				and absf(aabb.position.z) <= half.y + 0.05 and absf(aabb.end.z) <= half.y + 0.05
			check(inside, "%s: %s stays inside its footprint (%s)" % [set_name, it[0], aabb])
	for set_name: String in PropKit.config()["sets"]:
		if set_name.begins_with("home_") and not (PropKit.config()["sets"][set_name] as Array).is_empty():
			check(halves.has(set_name), "%s has a footprint" % set_name)


func test_a_home_upgrade_grows_its_yard() -> void:
	var built := _built("9", 0)
	var w: WorldState = built[0]
	var bl: VillageBuilder = built[1]
	var r: Dictionary = bl.yard_rects.filter(func(x: Dictionary) -> bool: return x["set"] == "home_door_0")[0]
	var home := w.layout.get_building(int(r["building"]))
	home.tier = 2
	bl.refresh_props()
	var now: Array = bl.yard_rects.filter(func(x: Dictionary) -> bool: return int(x["building"]) == home.id and str(x["set"]).begins_with("home_door"))
	check_eq(now.size(), 1, "the upgraded home still has its bench")
	if now.size() == 1:
		check_eq(now[0]["set"], "home_door_2", "now a townhouse's painted bench")
		check((now[0]["center"] as Vector3).distance_to(r["center"]) < 0.01, "in the same spot")
	check(bl.yard_rects.any(func(x: Dictionary) -> bool: return int(x["building"]) == home.id and x["set"] == "home_pots_2"), "with flower pots by the door")
	bl.free()


func test_the_heir_walks_round_the_hen_house() -> void:
	var built := _built("9", 1)
	var w: WorldState = built[0]
	var bl: VillageBuilder = built[1]
	var radius := float(WorldGeometry.cfg()["dressing"]["home:SE_ChickenCoop"])
	var coop := Vector3.INF
	for o in w.layout.dressing_obstacles:
		if is_equal_approx(o.z, radius):
			coop = o
			break
	check(coop != Vector3.INF, "the hen houses are walking obstacles")
	if coop != Vector3.INF:
		var p := WorldGeometry.resolve(w, Vector3(coop.x + 0.1, 0, coop.y + 0.1), 0.35)
		check(Vector2(p.x - coop.x, p.z - coop.y).length() >= radius + 0.3, "the heir is kept out of the hen house")
	check(not w.to_dict().has("dressing_obstacles") and not (w.to_dict()["layout"] as Dictionary).has("dressing_obstacles"), "they're worked out, not saved")
	bl.free()


func test_the_kit_cottage_bits_gave_way_to_the_home_yard() -> void:
	for e: Array in PropKit.config()["dressing"]["cottage"]:
		check(str(e[0]).begins_with("home_"), "a cottage is dressed from the home yard (%s)" % e[0])
	check(not PropKit.config()["sets"].has("cottage_bits"), "the kit bucket and stool are gone")
