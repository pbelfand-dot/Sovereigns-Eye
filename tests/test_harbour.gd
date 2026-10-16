extends TestCase
## Harbour & Ships (3D/props/harbour): quays, a jetty, a slipway and a hoist,
## the craft that use them, and the shore's nets and upturned boats; made
## ahead of the coast phase. The game has no sea yet: the demo harbour
## (tools/harbour_demo.gd) shows them together, and these tests hold the
## waterfront to its grid and its heights, and the craft to the water line.

const DIR := "res://3D/props/harbour/models/"
const Demo := preload("res://tools/harbour_demo.gd")
const BUDGETS := {"SE_Quay_Timber": 1200, "SE_Quay_Stone": 400, "SE_Quay_Steps": 700, "SE_Jetty": 700,
	"SE_Jetty_End": 2200, "SE_Slipway": 1500, "SE_Mooring_Post": 400, "SE_Hoist": 1500, "SE_Boat_Rowing": 1600,
	"SE_Boat_Fishing": 2600, "SE_Ship_Keel": 5500, "SE_Ship_Cog": 6000, "SE_Net_Rack": 1800, "SE_Boat_Ashore": 1400}
## Length and beam of each craft (m), from the family's README.
const CRAFT := {"SE_Boat_Rowing": [4.6, 1.45], "SE_Boat_Fishing": [7.5, 2.2], "SE_Ship_Keel": [16.0, 4.6], "SE_Ship_Cog": [20.0, 6.4]}

var _probe = preload("res://tests/mesh_probe.gd").new(DIR)


func _bounds(model: String) -> AABB:
	var t: PackedVector3Array = _probe.tris(model)
	var box := AABB(t[0], Vector3.ZERO)
	for v in t:
		box = box.expand(v)
	return box


func test_every_harbour_model_loads_within_budget() -> void:
	var seen := 0
	var cut := 0
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
					if mat.resource_name == "MI_Harbour_Cut":
						cut += 1
						check(mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "%s: nets and weed are cut out of the atlas" % f)
						check(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "%s: a net is seen from both sides" % f)
					if mat.resource_name == "MI_Harbour_Sail":
						check(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "%s: a sail is seen from both sides" % f)
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := int(BUDGETS.get(f.get_basename(), 0))
		check(budget > 0 and tris <= budget and tris >= 100, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		root.free()
	check_eq(seen, BUDGETS.size(), "all fourteen harbour models are there")
	check(cut >= 5, "the nets and the weed at the tide line use the cut-out material (%d)" % cut)


func test_the_waterfront_is_on_its_grid_and_its_heights() -> void:
	for model: String in ["SE_Quay_Timber", "SE_Quay_Stone", "SE_Quay_Steps"]:
		# Along the face, above the water: 4 m, centred.
		var span: Vector2 = _probe.extent(model, 0.8, 0, 0.6, 0.0)
		check(absf(span.y - span.x - 4.0) <= 0.02 and absf(span.x + span.y) < 0.02,
			"%s: %.2f m along the waterfront, centred" % [model, span.y - span.x])
		# Its top: the trodden ground at the quay's height, 4 m long, behind the face.
		var lo := INF
		var hi := -INF
		for v in _probe.tris(model):
			if absf(v.y - Demo.QUAY) < 0.005 and v.z < -1.0:
				lo = minf(lo, v.x)
				hi = maxf(hi, v.x)
		check(absf(lo + 2.0) < 0.01 and absf(hi - 2.0) < 0.01, "%s: its top is level at %.1f m the whole way" % [model, Demo.QUAY])
		var box := _bounds(model)
		check(box.end.y <= Demo.QUAY + 0.1, "%s: nothing of it stands above its top (%.2f)" % [model, box.end.y])
		check(box.position.y <= Demo.BED, "%s: its face goes down to the bed" % model)
	for model: String in ["SE_Jetty", "SE_Jetty_End"]:
		# Measured clear of the head's ladder, which hangs off its end.
		var along: Vector2 = _probe.extent(model, Demo.JETTY - 0.04, 0, 0.4, 0.0 if model == "SE_Jetty" else 1.4)
		check(absf(along.y - along.x - 4.0) <= 0.02, "%s: %.2f m of deck along the jetty" % [model, along.y - along.x])
		var across: Vector2 = _probe.extent(model, Demo.JETTY - 0.04, 2, 0.5, 0.0)
		var want := 2.4 if model == "SE_Jetty" else 4.4
		check(absf(across.y - across.x - want) <= 0.02, "%s: its deck is %.1f m across (%.2f)" % [model, want, across.y - across.x])
	check(_bounds("SE_Jetty").end.y <= Demo.JETTY + 0.001, "the jetty's deck is its top, at %.1f m" % Demo.JETTY)


func test_the_craft_float_on_the_water_line() -> void:
	for model: String in CRAFT:
		var dims: Array = CRAFT[model]
		var box := _bounds(model)
		check(box.position.y < -0.15 and box.end.y > 0.5, "%s: draws water and stands out of it" % model)
		# Cut at the water line: the hull's length and beam there.
		var along: Vector2 = _probe.extent(model, 0.02, 0, 1.0, 0.0)
		var across: Vector2 = _probe.extent(model, 0.02, 2, 1.0, 0.0)
		var length := along.y - along.x
		var beam := across.y - across.x
		check(length > 0.7 * float(dims[0]) and length < float(dims[0]) + 0.3, "%s: %.1f m long at the water line" % [model, length])
		check(beam > 0.6 * float(dims[1]) and beam < float(dims[1]) * 1.06, "%s: %.2f m broad at the water line" % [model, beam])
		check(absf(across.x + across.y) < 0.08, "%s: lies upright" % model)
	# The cog is steered from its sternpost, the keel by a side rudder on its
	# starboard quarter. Each hull is the same fore and aft, port and
	# starboard, so under the water the rudder is what reaches further.
	var lo := INF
	var hi := -INF
	for p in _probe.section("SE_Ship_Cog", -0.6):
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	check(-lo - hi > 0.4, "the cog's rudder hangs in the water behind its sternpost (%.2f m)" % (-lo - hi))
	var port := 0.0
	var starboard := 0.0
	for p in _probe.section("SE_Ship_Keel", -0.6):
		if p.x < -4.0:
			port = maxf(port, -p.z)
			starboard = maxf(starboard, p.z)
	check(starboard - port > 0.3, "the keel's side rudder is in the water on its starboard quarter (%.2f m)" % (starboard - port))


func test_the_demo_harbour_holds_together() -> void:
	var front := Demo.waterfront()
	var quays := front.filter(func(p: Array) -> bool: return str(p[0]).begins_with("SE_Quay"))
	quays.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector3).x < (b[1] as Vector3).x)
	for i in quays.size():
		var at: Vector3 = quays[i][1]
		check(is_equal_approx(at.x, Demo.QUAYS_WEST + 2.0 + 4.0 * i) and at.z == 0.0 and at.y == 0.0, "quay %d on the line" % i)
	check(is_equal_approx(Demo.QUAYS_WEST + 4.0 * quays.size(), Demo.QUAYS_EAST), "the quays run unbroken from end to end")
	var jetty := front.filter(func(p: Array) -> bool: return str(p[0]).begins_with("SE_Jetty"))
	var start := Demo.deck_meets_beach()
	for k in jetty.size():
		check(is_equal_approx((jetty[k][1] as Vector3).z, start + 2.0 + 4.0 * k), "jetty length %d follows the last" % k)
	check(absf(Demo.ground(20.0, start) - Demo.JETTY) < 0.02, "the jetty starts where the beach is as high as its deck")
	check(absf(Demo.ground(30.0, Demo.water_line())) < 0.02, "the slipway's foot is at the water line")
	# The slipway lies on the beach: its slope is the beach's.
	var slip := _bounds("SE_Slipway")
	var slope := (slip.size.y - 0.3) / slip.size.z
	check(absf(slope - Demo.BEACH_SLOPE) < 0.03, "the slipway falls as the beach does (%.3f)" % slope)
	# What stands on the shore stands on the ground.
	for p: Array in front:
		if str(p[0]) in ["SE_Mooring_Post", "SE_Hoist", "SE_Net_Rack", "SE_Boat_Ashore"]:
			var at: Vector3 = p[1]
			check(absf(at.y - Demo.ground(at.x, at.z)) < 0.05, "%s at %s stands on the ground" % [p[0], at])
	# Craft and waterfront don't run into each other at the water.
	var wet: Array = quays + jetty + Demo.CRAFT
	for i in wet.size():
		for j in range(i + 1, wet.size()):
			var a: Rect2 = _probe.plan(wet[i], 0.05).grow(-0.05)
			var b: Rect2 = _probe.plan(wet[j], 0.05).grow(-0.05)
			var both_craft := Demo.CRAFT.has(wet[i]) and Demo.CRAFT.has(wet[j])
			var any_craft := Demo.CRAFT.has(wet[i]) or Demo.CRAFT.has(wet[j])
			if any_craft:
				check(not a.intersects(b), "%s and %s keep apart at the water%s" % [wet[i][0], wet[j][0], " (both afloat)" if both_craft else ""])


func test_the_demo_harbour_builds() -> void:
	var root: Node3D = Demo.build(false)
	var pieces := 0
	for c in root.get_children():
		if str(c.name).begins_with("SE_"):
			pieces += 1
	check_eq(pieces, Demo.layout().size(), "every piece of the layout is placed")
	check(root.get_node_or_null("Shore") != null and root.get_node_or_null("Water") != null, "the harbour has its shore and its water")
	root.free()
