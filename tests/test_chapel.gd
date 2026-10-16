extends TestCase
## Chapel & Churchyard (3D/props/chapel-grounds): the chapel's tower shows
## its bells and carries a cross, its east gable another; behind it a
## churchyard grows with the charter, from a hamlet's few graves in a wattle
## fence to a town's walled yard with its lychgate.

const DIR := "res://3D/props/chapel-grounds/models/"
const BUDGETS := {"SE_Belfry": 2600, "SE_Cross_Tower": 400, "SE_Cross_Gable": 400, "SE_Grave_Mound": 400,
	"SE_Grave_Fresh": 500, "SE_Grave_Cross": 300, "SE_Grave_Slab": 300, "SE_Grave_Slab_Knight": 300,
	"SE_Churchyard_Cross": 1500, "SE_Yew": 3200, "SE_Wall_Rubble": 300, "SE_Wall_Coped": 300,
	"SE_Wall_Pier": 300, "SE_Lychgate": 2200}
const SEEDS := ["9", "12345", "1", "7", "42", "2026", "smithy", "harvest", "oakmere", "brackmoor"]
const GRAVES := ["chapel:SE_Grave_Mound", "chapel:SE_Grave_Fresh", "chapel:SE_Grave_Slab", "chapel:SE_Grave_Slab_Knight"]
const BOUNDS := ["chapel:SE_Wall_Rubble", "chapel:SE_Wall_Coped", "chapel:SE_Wall_Pier", "farm:SE_Fence_Wattle", "farm:SE_Fence_Paled",
	"farm:SE_Gate_Wattle", "farm:SE_Gate_Rail"]


func _yards(l: VillageLayout) -> Array[Dictionary]:
	return l.props_of_type("churchyard") + l.props_of_type("churchyard_small")


func _rect(p: Dictionary) -> Dictionary:
	return {"center": p["pos"], "rot": float(p["rot"]), "half": VillageLayoutGenerator.YARD_HALF[p["type"]]}


func _set_models(set_name: String) -> Array:
	var out := []
	for it: Array in PropKit.set_items(set_name, Transform3D()):
		out.append(str(it[0]))
	return out


func _modules(parts: Array) -> Array:
	var out: Array = []
	for p: Array in parts:
		out.append(str(p[0]))
	return out


## A solid piece's circles (data/controls.json "dressing") in the set's frame: [Vector2, radius].
func _circles(model: String, xf: Transform3D) -> Array:
	var shape: Variant = WorldGeometry.cfg().get("dressing", {}).get(model)
	var out := []
	if shape is Array:
		for c: Array in shape:
			var o := xf * Vector3(float(c[0]), 0, float(c[1]))
			out.append([Vector2(o.x, o.z), float(c[2])])
	elif shape != null:
		out.append([Vector2(xf.origin.x, xf.origin.z), float(shape)])
	return out


func _world(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.house.gold = 5000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 900.0
	return st


func test_every_chapel_model_loads_within_budget() -> void:
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
		check(budget > 0 and tris <= budget and tris >= 40, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, 14, "all fourteen chapel and churchyard models are there")


func test_the_chapel_shows_its_bells_and_carries_its_crosses() -> void:
	var parts: Array = VillageKit.prefab("chapel", 0, 0)["parts"]
	var mods := _modules(parts)
	check_eq(mods.count("chapel:SE_Belfry"), 1, "one belfry in the tower")
	check_eq(mods.count("chapel:SE_Cross_Tower"), 1, "an iron cross on the spire")
	check_eq(mods.count("chapel:SE_Cross_Gable"), 1, "a stone cross on the east gable")
	var sh := float(VillageKit.config().get("story_height", 3.0))
	var spire := VillageKit.module_mesh("Roof_Tower_RoundTiles")
	var arches := 0
	for p: Array in parts:
		var xf: Transform3D = p[1]
		var m := str(p[0])
		match m:
			"chapel:SE_Belfry":
				check(absf(xf.origin.y - 3.0 * sh) < 0.01, "the belfry hangs in the tower's top story")
				check(xf.origin.z > 2.0, "in the tower, at the front (%s)" % xf.origin)
			"chapel:SE_Cross_Tower":
				check(spire != null and absf(xf.origin.y - (4.0 * sh + spire.get_aabb().end.y)) < 0.1, "on the spire's tip (%.2f)" % xf.origin.y)
			"chapel:SE_Cross_Gable":
				check(xf.origin.z < -5.5, "at the east (back) end of the nave (%.2f)" % xf.origin.z)
				check(xf.origin.y > 10.0, "up on the ridge (%.2f)" % xf.origin.y)
		if xf.origin.y > 3.0 * sh - 0.01 and xf.origin.y < 4.0 * sh - 0.01 and m.begins_with("Wall_"):
			check(m == "Wall_UnevenBrick_Window_Wide_Round", "the top story's walls are open arches (%s)" % m)
			arches += 1
		if xf.origin.y > 3.0 * sh - 0.01 and xf.origin.y < 4.0 * sh - 0.01:
			check(not m.begins_with("Window_") and not m.contains("Shutters"), "no glazing or shutters in the belfry (%s)" % m)
	check_eq(arches, 8, "two arches on each side of the tower")


func test_every_chapel_has_its_churchyard_at_its_east_end() -> void:
	for seed_text: String in SEEDS:
		var w := WorldGenerator.generate(seed_text)
		var chapels := w.layout.buildings_of_type("chapel")
		var yards := _yards(w.layout)
		check_eq(yards.size(), chapels.size(), "%s: every chapel has a churchyard" % seed_text)
		if yards.is_empty() or chapels.is_empty():
			continue
		var b: BuildingData = chapels[0]
		var y := yards[0]
		var local := b.basis().inverse() * ((y["pos"] as Vector3) - b.position)
		check(local.z < -b.footprint.y * 0.5 or absf(local.x) > b.footprint.x * 0.5, "%s: behind the chapel or beside it, not before it" % seed_text)
		check(absf(angle_difference(float(y["rot"]), b.rotation + PI)) < 0.001, "%s: its graves lie east-west, like the chapel" % seed_text)
		# Clear of everything but itself, whole footprints, not just samples.
		var rect := _rect(y)
		for o in w.layout.buildings:
			if o != b:
				check(not VillageLayoutGenerator.rects_overlap(rect, {"center": o.position, "rot": o.rotation, "half": o.footprint * 0.5}, 0.0),
					"%s: clear of %s" % [seed_text, o.name])
		check(not VillageLayoutGenerator.rects_overlap(rect, {"center": b.position, "rot": b.rotation, "half": b.footprint * 0.5}, 0.5),
			"%s: a path round the chapel's east end" % seed_text)
		for f in w.layout.fields:
			check(not VillageLayoutGenerator.rects_overlap(rect, {"center": f["center"], "rot": f["rot"], "half": (f["size"] as Vector2) * 0.5}, 0.0),
				"%s: clear of the fields" % seed_text)
		for p in w.layout.props:
			if p != y and VillageLayoutGenerator.YARD_HALF.has(p["type"]):
				check(not VillageLayoutGenerator.rects_overlap(rect, _rect(p), 0.0), "%s: clear of the %s yard" % [seed_text, p["type"]])
			elif p != y:
				check(not VillageLayoutGenerator._point_in_rect(p["pos"], rect, 0.3), "%s: no %s in it" % [seed_text, p["type"]])
		for t in w.layout.trees:
			check(not VillageLayoutGenerator._point_in_rect(Vector3(t.x, 0, t.y), rect, 0.5), "%s: no tree in it" % seed_text)
	check_eq(_yards(WorldGenerator.generate("9").layout)[0]["pos"], _yards(WorldGenerator.generate("9").layout)[0]["pos"], "the same village puts it in the same place")


func test_the_churchyard_grows_with_the_charter() -> void:
	var want := {
		0: ["farm:SE_Fence_Wattle", "farm:SE_Gate_Wattle", "chapel:SE_Grave_Mound", "chapel:SE_Grave_Fresh", "chapel:SE_Grave_Cross"],
		1: ["farm:SE_Fence_Paled", "chapel:SE_Churchyard_Cross", "chapel:SE_Yew", "chapel:SE_Grave_Mound", "chapel:SE_Grave_Cross"],
		2: ["chapel:SE_Wall_Rubble", "chapel:SE_Wall_Pier", "chapel:SE_Grave_Slab", "chapel:SE_Churchyard_Cross", "chapel:SE_Yew"],
		3: ["chapel:SE_Wall_Coped", "chapel:SE_Wall_Pier", "chapel:SE_Lychgate", "chapel:SE_Grave_Slab_Knight", "chapel:SE_Grave_Slab"],
	}
	var seen := {}
	for charter: int in want:
		for type: String in ["churchyard", "churchyard_small"]:
			var model := PropKit.commons_model(type, charter)
			check(model.begins_with("set:"), "%s at charter %d: a set (%s)" % [type, charter, model])
			check(PropKit.set_ready(model.substr(4)), "%s at charter %d: every model is there" % [type, charter])
		var models := _set_models(PropKit.commons_model("churchyard", charter).substr(4))
		for m: String in want[charter]:
			check(models.has(m), "charter %d: the churchyard has %s" % [charter, m])
		seen[str(models)] = true
	check_eq(seen.size(), 4, "each charter's churchyard looks different")
	var hamlet := _set_models("churchyard_0")
	check(not hamlet.has("chapel:SE_Yew") and not hamlet.has("chapel:SE_Churchyard_Cross"), "a hamlet's has no yew or stone cross yet")
	check(not hamlet.has("chapel:SE_Grave_Slab") and not _set_models("churchyard_1").has("chapel:SE_Grave_Slab"), "stone slabs only from Market Town")
	check(not _set_models("churchyard_2").has("chapel:SE_Lychgate"), "the lychgate only at Town")


func test_the_sets_fit_their_yards_with_graves_east_west() -> void:
	for charter in 4:
		for type: String in ["churchyard", "churchyard_small"]:
			var set_name := PropKit.commons_model(type, charter).substr(4)
			var half: Vector2 = VillageLayoutGenerator.YARD_HALF[type]
			var items := PropKit.set_items(set_name, Transform3D())
			var free := []    # graves, crosses, the yew, the lychgate's posts
			var walls := []   # the bounds: walls, piers, fences, gates
			var crosses := []
			for it: Array in items:
				var m := str(it[0])
				var xf: Transform3D = it[1]
				# Every piece in the yard (the yew's crown may hang over the wall).
				var aabb := AABB()
				var first := true
				for part: Array in PropKit.parts(m):
					var box: AABB = xf * (part[1] as Transform3D) * (part[0] as Mesh).get_aabb()
					aabb = box if first else aabb.merge(box)
					first = false
				var slack := 2.0 if m == "chapel:SE_Yew" else 0.15
				var inside := aabb.position.x >= -half.x - slack and aabb.end.x <= half.x + slack \
					and aabb.position.z >= -half.y - slack and aabb.end.z <= half.y + slack
				check(inside, "%s: %s stays in the yard (%s)" % [set_name, m, aabb])
				if m in GRAVES:
					check(xf.basis.z.is_equal_approx(Vector3(0, 0, 1)), "%s: %s lies east-west" % [set_name, m])
				if m == "chapel:SE_Grave_Cross":
					crosses.append(xf.origin)
				if m in BOUNDS:
					walls.append_array(_circles(m, xf))
				else:
					free.append(_circles(m, xf))
			# Each marked grave has its cross at its head, the west (-Z) end.
			for it: Array in items:
				if str(it[0]) in ["chapel:SE_Grave_Mound", "chapel:SE_Grave_Fresh"]:
					var g: Vector3 = (it[1] as Transform3D).origin
					for c: Vector3 in crosses:
						if absf(c.x - g.x) < 0.2 and absf(c.z - g.z) < 1.5:
							check(c.z < g.z - 0.9, "%s: the cross stands at the grave's head" % set_name)
			# Nothing stands in anything else, nor in the walls.
			for i in free.size():
				for j in range(i + 1, free.size()):
					for a: Array in free[i]:
						for b: Array in free[j]:
							check((a[0] as Vector2).distance_to(b[0]) >= float(a[1]) + float(b[1]) - 0.05, "%s: pieces keep apart" % set_name)
				for a: Array in free[i]:
					for b: Array in walls:
						check((a[0] as Vector2).distance_to(b[0]) >= float(a[1]) + float(b[1]) - 0.05, "%s: nothing stands in the wall" % set_name)
			# The way in, on the west side, is open to someone walking.
			var gate := Vector2(0.15 if charter >= 2 else 1.0, -half.y + 0.45)
			for c: Array in walls + free.reduce(func(acc: Array, x: Array) -> Array: return acc + x, []):
				check((c[0] as Vector2).distance_to(gate) > float(c[1]) + 0.35, "%s: the gateway is open (%s)" % [set_name, c])


func test_the_heir_comes_in_by_the_gateway_not_over_the_wall() -> void:
	var w := WorldGenerator.generate("9")
	TerritorySystem.initialize(w)
	w.territory.charter = 3
	var bl := VillageBuilder.new()
	bl.territory = w.territory
	bl.build(w.layout)
	var y := _yards(w.layout)[0]
	var xf := Transform3D(Basis(Vector3.UP, float(y["rot"])), y["pos"])
	var half: Vector2 = VillageLayoutGenerator.YARD_HALF[y["type"]]
	var wall := xf * Vector3(0, 0, half.y - 0.3)      # the middle of the east wall
	var p := WorldGeometry.resolve(w, wall, 0.35)
	check(Vector2(p.x - wall.x, p.z - wall.z).length() > 0.5, "the heir is kept off the east wall")
	var gate := xf * Vector3(0, 0, -half.y + 0.4)     # the lychgate's mouth
	var q := WorldGeometry.resolve(w, gate, 0.35)
	check(Vector2(q.x - gate.x, q.z - gate.z).length() < 0.05, "and walks in under the lychgate")
	# Walking at a grave from its side, the heir stops at its edge.
	for it: Array in PropKit.set_items(PropKit.commons_model(str(y["type"]), 3).substr(4), xf):
		if not str(it[0]) in GRAVES:
			continue
		var gxf: Transform3D = it[1]
		var across := gxf.basis.x.normalized()
		var at := gxf.origin + across * 0.6   # beside it, between it and the path
		for k in 12:
			at = WorldGeometry.resolve(w, at - across * 0.08, 0.35)
		check(absf(across.dot(at - gxf.origin)) > 0.45, "the heir doesn't walk over the %s" % it[0])
	# Nothing else is set down in it, and nothing grows up through it.
	for it: Array in bl.dressing_items():
		var at: Vector3 = (it[1] as Transform3D).origin
		if not str(it[0]).begins_with("chapel:") and not str(it[0]).begins_with("farm:"):
			check(not VillageLayoutGenerator._point_in_rect(at, _rect(y), 0.0), "no dressing in the churchyard (%s)" % it[0])
	for rr: Dictionary in bl.yard_rects:
		check(not VillageLayoutGenerator.rects_overlap(rr, _rect(y), 0.0), "no home yard overlaps it")
	for group: Dictionary in NatureKit.config().get("scatter", []):
		var kept := bl._kept_scatter(group, bl.scatter_items(group))
		for model: String in kept:
			for it: Array in kept[model]:
				check(not VillageLayoutGenerator._point_in_rect((it[0] as Transform3D).origin, _rect(y), 0.0),
					"no %s grows in the churchyard" % group.get("name", ""))
	bl.free()


func test_a_new_chapel_gets_its_churchyard() -> void:
	var st := _world("chapel-built")
	TerritorySystem.initialize(st)
	st.territory.charter = 1
	var before := _yards(st.layout).size()
	var spot := TerritorySystem.find_spot(st, "chapel")
	check(not spot.is_empty(), "a spot for a second chapel")
	if spot.is_empty():
		return
	var res := TerritorySystem.place(st, "chapel", spot["pos"], spot["rot"])
	check(res["ok"], "a chapel can be ordered (%s)" % res.get("text", ""))
	if not res["ok"]:
		return
	var site: ConstructionSite = res["site"]
	site.work_done = site.work_needed
	TerritorySystem.complete(st, site)
	var b := st.get_building(site.id())
	var yards := _yards(st.layout)
	check_eq(yards.size(), before + 1, "the new chapel has its churchyard")
	if yards.size() == before + 1:
		var y := yards[-1]
		check(absf(angle_difference(float(y["rot"]), b.rotation + PI)) < 0.001, "lying east-west like its chapel")
		check((y["pos"] as Vector3).distance_to(b.position) < 14.0, "beside its own chapel")
		for o in st.layout.buildings:
			if o != b:
				check(not VillageLayoutGenerator.rects_overlap(_rect(y), {"center": o.position, "rot": o.rotation, "half": o.footprint * 0.5}, 0.0),
					"clear of %s" % o.name)
	# The saved game keeps it.
	var again := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary)
	check_eq(_yards(again.layout).size(), _yards(st.layout).size(), "a save keeps both churchyards")


func test_new_buildings_keep_off_the_yards() -> void:
	var st := _world("9")
	TerritorySystem.initialize(st)
	for type: String in ["churchyard", "training"]:
		var ys := st.layout.props_of_type(type)
		if ys.is_empty():
			continue
		var y: Dictionary = ys[0]
		var half: Vector2 = VillageLayoutGenerator.YARD_HALF[type]
		# A workshop whose middle is outside the yard but whose end is in it.
		var at: Vector3 = (y["pos"] as Vector3) + Basis(Vector3.UP, float(y["rot"])) * Vector3(half.x + 1.5, 0, 0)
		var res := TerritorySystem.check_placement(st, "workshop", at, float(y["rot"]))
		check(not res["ok"], "no building over the %s's edge" % type)
		if not res["ok"] and not str(res["reason"]).begins_with("Too close"):
			check(str(res["reason"]).contains("yard"), "the reason names it (%s)" % res["reason"])


func test_older_saves_get_their_churchyard() -> void:
	var st := WorldGenerator.generate("chapel-migrate")
	var want := _yards(st.layout)
	check_eq(want.size(), 1, "the village has a churchyard to take away")
	var kept: Array[Dictionary] = []
	for p in st.layout.props:
		if not str(p["type"]).begins_with("churchyard"):
			kept.append(p)
	st.layout.props = kept
	var old := JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary
	old["save_version"] = 11
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	var got := _yards(migrated.layout)
	check_eq(got.size(), 1, "the migrated village has its churchyard")
	if got.size() == 1 and want.size() == 1:
		check_eq(got[0]["type"], want[0]["type"], "the same size a new village would have")
		check((got[0]["pos"] as Vector3).distance_to(want[0]["pos"]) < 0.05, "in the same place")
	check_eq(int(SaveManager.migrate(old)["save_version"]), WorldState.SAVE_VERSION, "the save reaches the current version")
	var again := WorldState.from_dict(SaveManager.migrate(JSON.parse_string(JSON.stringify(migrated.to_dict())) as Dictionary))
	check_eq(_yards(again.layout).size(), 1, "a current save is left alone")
