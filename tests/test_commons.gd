extends TestCase
## The Village Commons (3D/props/village-commons): the well, charter banners
## and signposts are real models that grow finer with the charter.

const TIERS := ["well", "banner", "signpost"]


func test_every_tier_has_a_model_with_its_textures() -> void:
	var by: Dictionary = PropKit.config().get("by_charter", {})
	for type: String in TIERS:
		var list: Array = by.get(type, [])
		check_eq(list.size(), CharterSystem.tiers().size(), "%s has a model for every charter" % type)
		for model: String in list:
			var path := PropKit.model_path(model)
			check(ResourceLoader.exists(path), "%s exists" % path)
			var scene := load(path) as PackedScene
			check(scene != null, "%s loads" % path)
			if scene == null:
				continue
			var root := scene.instantiate()
			var tris := 0
			for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				for s in mi.mesh.get_surface_count():
					var mat := mi.mesh.surface_get_material(s)
					check(mat != null and not mat.resource_name.is_empty(), "%s: every surface has a named material" % model)
					if mat is BaseMaterial3D and mat.resource_name != "MI_Commons_Water":
						check((mat as BaseMaterial3D).albedo_texture != null, "%s: %s has its texture" % [model, mat.resource_name])
					var idx: PackedInt32Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
					tris += idx.size() / 3
			check(tris > 200 and tris < 8000, "%s is a real model within budget (%d tris)" % [model, tris])
			check(not root.find_children("*", "CollisionShape3D", true, false).is_empty(), "%s has a simple collision proxy" % model)
			root.free()


func test_the_well_follows_the_charter() -> void:
	var w := WorldGenerator.generate("commons-well")
	TerritorySystem.initialize(w)
	var looks := []
	for charter in [0, 1, 3]:
		w.territory.charter = charter
		var b := VillageBuilder.new()
		b.territory = w.territory
		b.build(w.layout)
		var well := b.get_node("Props").get_node_or_null("Well") as Node3D
		check(well != null, "the well is its own node (charter %d)" % charter)
		if well:
			check(well.position.distance_to(w.layout.square_center) < 0.5, "at the heart of the square")
			var meshes := well.find_children("*", "MeshInstance3D", true, false)
			check(not meshes.is_empty(), "with its mesh")
			looks.append((meshes[0] as MeshInstance3D).mesh.resource_path if not meshes.is_empty() else "")
		b.free()
	check(looks.size() == 3 and looks[0] != looks[1] and looks[1] != looks[2], "a hamlet, a village and a town each have their own well")


func test_banners_reach_away_from_walls_and_sway() -> void:
	var w := WorldGenerator.generate("commons-banner")
	TerritorySystem.initialize(w)
	w.territory.charter = 2
	var b := VillageBuilder.new()
	b.territory = w.territory
	b.build(w.layout)
	var house := w.layout.buildings[0]
	var basis := house.basis()
	var left := house.position + basis * Vector3(-house.footprint.x * 0.5 - 1.0, 0, house.footprint.y * 0.5 - 0.5)
	var right := house.position + basis * Vector3(house.footprint.x * 0.5 + 1.0, 0, house.footprint.y * 0.5 - 0.5)
	check(b._arm_blocked(left, basis), "a banner left of a house would reach into its wall")
	check(not b._arm_blocked(right, basis), "one on the right reaches clear")
	var wind := false
	for mi: MeshInstance3D in b.get_node("Props").find_children("Props *", "MeshInstance3D", false, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("banner_wind.gdshader"):
				wind = true
	check(wind, "banner cloth is drawn with the wind shader")
	b.free()


func test_collision_covers_each_footing() -> void:
	## WorldGeometry keeps the heir (body_radius) this far from a prop's
	## center; the model's own collision proxy must fit inside that.
	var radii: Dictionary = WorldGeometry.cfg().get("props", {})
	var body := float(WorldGeometry.cfg().get("walk", {}).get("body_radius", 0.35))
	var by: Dictionary = PropKit.config().get("by_charter", {})
	for type: String in TIERS:
		for model: String in by.get(type, []):
			var root := (load(PropKit.model_path(model)) as PackedScene).instantiate()
			var reach := 0.0
			for cs: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
				if cs.shape is ConvexPolygonShape3D:
					for p: Vector3 in (cs.shape as ConvexPolygonShape3D).points:
						reach = maxf(reach, Vector2(p.x, p.z).length())
			check(reach > 0.0, "%s has a footprint" % model)
			check(reach <= float(radii.get(type, 0.0)) + body - 0.1, "the heir stays clear of %s's footing (%.2f m vs %.2f + %.2f)" % [model, reach, float(radii.get(type, 0.0)), body])
			root.free()
