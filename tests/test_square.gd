extends TestCase
## The Market Square family (3D/props/market-square): the square's kerb by
## charter, the market cross a Market Town's charter brings, and the trough
## beside the well.

const BUDGETS := {"SE_Kerb_": 300, "SE_MarketCross_Town": 3000, "SE_MarketCross.": 2200, "SE_Trough_": 800}


func _village(seed_text: String, charter: int) -> Array:
	var w := WorldGenerator.generate(seed_text)
	TerritorySystem.initialize(w)
	w.territory.charter = charter
	var b := VillageBuilder.new()
	b.territory = w.territory
	b.build(w.layout)
	return [w, b]


func _prop(layout: VillageLayout, type: String) -> Dictionary:
	var found := layout.props_of_type(type)
	return found[0] if found.size() == 1 else {}


func test_every_square_model_loads_within_budget() -> void:
	var dir := "res://3D/props/market-square/models/"
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
				if mat is BaseMaterial3D and mat.resource_name != "MI_Square_Water":
					check((mat as BaseMaterial3D).albedo_texture != null, "%s: %s has its texture" % [f, mat.resource_name])
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := 0
		for prefix: String in BUDGETS:
			if (f.get_basename() + ".").begins_with(prefix):
				budget = BUDGETS[prefix]
		check(budget > 0 and tris <= budget and tris > 50, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, 7, "all seven square models are there")


func test_the_kerb_follows_the_charter_and_rings_the_square() -> void:
	var models: Array = PropKit.config()["square_edge"]["by_charter"]
	var seg := float(PropKit.config()["square_edge"]["segment"])
	var gap := float(PropKit.config()["square_edge"]["road_gap"])
	for charter in 4:
		var v := _village("market-square", charter)
		var w: WorldState = v[0]
		var b: VillageBuilder = v[1]
		var kerb := b.get_node("Square").get_node_or_null("Kerb") as MultiMeshInstance3D
		check(kerb != null, "charter %d: the square has a kerb" % charter)
		if kerb:
			check(kerb.multimesh.mesh == PropKit.parts(str(models[charter]))[0][0], "charter %d: the kerb is %s" % [charter, models[charter]])
		var xfs := b.square_edge_transforms()
		var r := w.layout.square_radius
		# All round the rim, open only where the roads come in.
		var laid := 0.0
		for xf in xfs:
			laid += xf.basis.x.length() * seg
		var openings := 0.0
		for road: Dictionary in w.layout.roads:
			if (road["points"] as PackedVector3Array)[0].distance_to(w.layout.square_center) < r + 1.0:
				openings += float(road["width"]) + 2.0 * gap
		var expect := TAU * r - openings
		check(absf(laid - expect) < 2.5, "charter %d: kerb all round but the road mouths (%.1f m laid of %.1f m)" % [charter, laid, expect])
		if kerb:
			check_eq(kerb.multimesh.instance_count, xfs.size(), "one instance per piece")
		var on_rim := true
		var off_roads := true
		for xf in xfs:
			on_rim = on_rim and absf(Vector2(xf.origin.x - w.layout.square_center.x, xf.origin.z - w.layout.square_center.z).length() - r) < 0.05
			var out := (xf.origin + xf.basis.x * 0.5 + xf.basis.z.normalized() * 0.25)
			off_roads = off_roads and b.road_clearance(Vector2(out.x, out.z)) > gap - 0.2
			# +Z points out of the square, +X runs along the rim.
			on_rim = on_rim and xf.basis.z.normalized().dot((xf.origin - w.layout.square_center).normalized()) > 0.95
		check(on_rim, "charter %d: every piece lies on the rim, facing out" % charter)
		check(off_roads, "charter %d: no piece lies across a road" % charter)
		b.free()


func test_the_market_cross_comes_with_the_market() -> void:
	for charter in 4:
		var v := _village("market-square", charter)
		var w: WorldState = v[0]
		var b: VillageBuilder = v[1]
		var cross := b.get_node("Props").get_node_or_null("MarketCross")
		var market := charter >= 2
		check_eq(cross != null, market, "charter %d: the market cross %s" % [charter, "stands" if market else "is not there yet"])
		check_eq(PropKit.present("market_cross", charter), market, "and it counts as there only then")
		# Nothing invisible to walk into before; its steps keep people off after.
		var spot: Vector3 = _prop(w.layout, "market_cross")["pos"]
		var p := WorldGeometry.resolve(w, spot + Vector3(0.3, 0, 0), 0.35)
		if market:
			check(Vector2(p.x - spot.x, p.z - spot.z).length() >= 1.5 + 0.35 - 0.01, "charter %d: the heir is kept off the cross's steps" % charter)
		else:
			check(p.distance_to(spot + Vector3(0.3, 0, 0)) < 0.01, "charter %d: nothing in the way at the empty spot" % charter)
		var trough := b.get_node("Props").find_children("Props *", "MeshInstance3D", false, false)
		var water := 0
		for mi: MeshInstance3D in trough:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m and m.resource_name == "MI_Square_Water":
					water += 1
		check(water > 0, "charter %d: the trough is merged with the props" % charter)
		b.free()


func test_the_cross_and_the_trough_have_room_on_the_square() -> void:
	var radii: Dictionary = WorldGeometry.cfg().get("props", {})
	for seed_text in ["market-square", "9", "12345", "harvest"]:
		var layout := VillageLayoutGenerator.new().generate(Seeds.from_text(seed_text))
		var c := layout.square_center
		for type: String in ["market_cross", "trough"]:
			check_eq(layout.props_of_type(type).size(), 1, "%s: one %s" % [seed_text, type])
		var cross: Vector3 = _prop(layout, "market_cross")["pos"]
		var trough: Vector3 = _prop(layout, "trough")["pos"]
		check(cross.distance_to(c) + float(radii["market_cross"]) < layout.square_radius - 1.0, "%s: the cross stands well inside the square" % seed_text)
		check(trough.distance_to(c) >= float(radii["well"]) + float(radii["trough"]) + 0.3, "%s: the trough clears the well" % seed_text)
		check(trough.distance_to(cross) > float(radii["market_cross"]) + float(radii["trough"]) + 1.0, "%s: and the cross" % seed_text)
		for p: Dictionary in layout.props:
			if p["type"] in ["stall", "bench"]:
				for mine: Array in [["market_cross", cross], ["trough", trough]]:
					var room: float = float(radii[mine[0]]) + float(radii[p["type"]]) + 0.3
					check((mine[1] as Vector3).distance_to(p["pos"]) > room, "%s: the %s keeps clear of a %s" % [seed_text, mine[0], p["type"]])
		# Off the walk in from each road.
		for road: Dictionary in layout.roads:
			var mouth: Vector3 = (road["points"] as PackedVector3Array)[0]
			if mouth.distance_to(c) < layout.square_radius + 1.0:
				var off := Geometry3D.get_closest_point_to_segment(cross, mouth, c).distance_to(cross)
				check(off > float(radii["market_cross"]) + 1.0, "%s: the cross leaves the %s road's way into the square open (%.1f m)" % [seed_text, road["name"], off])
	var a := VillageLayoutGenerator.new().generate(Seeds.from_text("market-square"))
	var b := VillageLayoutGenerator.new().generate(Seeds.from_text("market-square"))
	check_eq(str(VillageLayoutGenerator.square_furniture(a)), str(VillageLayoutGenerator.square_furniture(b)), "the spots are the same every time")


func test_older_saves_get_the_trough_and_the_cross_spot() -> void:
	var st := WorldGenerator.generate("square-migrate")
	var want := VillageLayoutGenerator.square_furniture(st.layout)
	var kept: Array[Dictionary] = []
	for p in st.layout.props:
		if not p["type"] in ["market_cross", "trough"]:
			kept.append(p)
	st.layout.props = kept
	var old := JSON.parse_string(JSON.stringify(st.to_dict())) as Dictionary
	old["save_version"] = 8
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	for w: Dictionary in want:
		var got := migrated.layout.props_of_type(w["type"])
		check_eq(got.size(), 1, "the migrated village has a %s" % w["type"])
		if got.size() == 1:
			check((got[0]["pos"] as Vector3).distance_to(w["pos"]) < 0.02, "on the spot a new village would give it")
	# A save that already has them gets no second one.
	var again := WorldState.from_dict(SaveManager.migrate(JSON.parse_string(JSON.stringify(migrated.to_dict())) as Dictionary))
	check_eq(again.layout.props_of_type("trough").size(), 1, "a current save is left alone")


func test_collision_covers_the_cross_and_the_trough() -> void:
	var radii: Dictionary = WorldGeometry.cfg().get("props", {})
	var body := float(WorldGeometry.cfg().get("walk", {}).get("body_radius", 0.35))
	var by: Dictionary = PropKit.config().get("by_charter", {})
	for type: String in ["market_cross", "trough"]:
		for model: String in by[type]:
			if model.is_empty():
				continue
			var root := (load(PropKit.model_path(model)) as PackedScene).instantiate()
			var reach := 0.0
			for cs: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
				for p: Vector3 in (cs.shape as ConvexPolygonShape3D).points:
					reach = maxf(reach, Vector2(p.x, p.z).length())
			check(reach > 0.0, "%s has a footprint" % model)
			check(reach <= float(radii[type]) + body - 0.1, "the heir stays clear of %s (%.2f m vs %.2f + %.2f)" % [model, reach, float(radii[type]), body])
			root.free()
