extends TestCase
## Quaternius art integration: building recipes match the layout's footprints,
## prefabs assemble into shared-material meshes, and villager bodies build
## from character data with the in-place animation clips.


func test_kit_recipes_fit_building_footprints() -> void:
	var prefabs: Dictionary = VillageKit.config().get("prefabs", {})
	check(not prefabs.is_empty(), "building_kit.json has recipes")
	for type: String in prefabs:
		var fp: Array = GameData.building_type(type).get("footprint", [0, 0])
		check(not fp.is_empty(), "%s exists in buildings.json" % type)
		for recipe: Dictionary in VillageKit.variants(type):
			var r := VillageKit.recipe_bounds(recipe)
			check(r.size.x <= float(fp[0]) + 0.01 and r.size.y <= float(fp[1]) + 0.01,
				"%s recipe (%s) fits footprint %s" % [type, r.size, fp])
			check(absf(r.get_center().x) < 0.01 and absf(r.get_center().y) < 0.01, "%s recipe is centered" % type)


func test_kit_prefabs_assemble() -> void:
	if not VillageKit.available():
		check(true, "kit not in project; placeholder buildings are used")
		return
	var materials := {}
	for type: String in VillageKit.config().get("prefabs", {}):
		var p := VillageKit.prefab(type, 0)
		var shell: ArrayMesh = p["shell"]
		check(shell.get_surface_count() > 0, "%s shell has geometry" % type)
		check(shell.get_surface_count() <= 12, "%s shell is merged by material (%d surfaces)" % [type, shell.get_surface_count()])
		check(int(p["pieces"]) > 10, "%s uses kit modules (%d)" % [type, int(p["pieces"])])
		check(not (p["boxes"] as Array).is_empty(), "%s has collision proxies" % type)
		for s in shell.get_surface_count():
			var m := shell.surface_get_material(s)
			if m:
				if materials.has(m.resource_name):
					check(materials[m.resource_name] == m, "%s shares material %s" % [type, m.resource_name])
				materials[m.resource_name] = m
	check(VillageKit.prefab("cottage", 0) == VillageKit.prefab("cottage", 3), "variants wrap and prefabs are cached")


func test_villager_bodies() -> void:
	var w := WorldGenerator.generate("art-seed")
	if not HumanModel.available():
		check(HumanModel.for_character(w.characters[0]) != null, "placeholder body when Quaternius files are missing")
		return
	var lib_checked := false
	for c in w.characters.slice(0, 8):
		var m := HumanModel.for_character(c)
		check(m is HumanModel, "%s gets a Quaternius body" % c.full_name())
		check(m.head_height() > 0.5 and m.head_height() < 1.9, "%s head height is sane (%.2f)" % [c.full_name(), m.head_height()])
		var player := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(player != null, "%s has an animation player" % c.full_name())
		if player and not lib_checked:
			lib_checked = true
			for clip: String in ["Idle", "Walk", "Idle_Talking", "Farm_Harvest", "TreeChopping"]:
				check(player.has_animation(clip), "clip %s is available" % clip)
			# In-place clips: the pelvis must not travel across the ground.
			var walk := player.get_animation("Walk")
			for t in walk.get_track_count():
				if walk.track_get_type(t) == Animation.TYPE_POSITION_3D:
					var first: Vector3 = walk.track_get_key_value(t, 0)
					var last: Vector3 = walk.track_get_key_value(t, walk.track_get_key_count(t) - 1)
					check(Vector2(last.x - first.x, last.y - first.y).length() < 0.2, "walk clip is in place")
		for mode: String in ["walk", "work", "talk", "idle"]:
			m.animate(mode, 0.0, 0.1)
		check(m.find_children("*", "MeshInstance3D", true, false).size() >= 2, "%s has body meshes" % c.full_name())
		m.free()


func test_meadow_ground_wear() -> void:
	var w := WorldGenerator.generate("meadow-seed")
	var l := w.layout
	var e := l.extent + 60.0
	var origin := Vector2(-e, -e)
	var cfg: Dictionary = GameData.load_file("art_style").get("terrain", {})
	var wear_cfg: Dictionary = cfg.get("wear", {})
	var mask := GroundWear.bake(l, origin, e * 2.0, 256, wear_cfg)
	check(mask.get_width() == 256 and mask.get_format() == Image.FORMAT_R8, "wear mask is a 256px R8 image")
	var sq := Vector2(l.square_center.x, l.square_center.z)
	check(GroundWear.sample(mask, origin, e * 2.0, sq) > 0.95, "the square is fully trodden")
	var road: PackedVector3Array = l.roads[0]["points"]
	var mid := road[road.size() / 2]
	check(GroundWear.sample(mask, origin, e * 2.0, Vector2(mid.x, mid.z)) > 0.9, "roads are trodden")
	check(GroundWear.sample(mask, origin, e * 2.0, Vector2(e - 2.0, e - 2.0)) < 0.05, "the far meadow is untouched")
	var again := GroundWear.bake(l, origin, e * 2.0, 256, wear_cfg)
	check(again.get_data() == mask.get_data(), "same layout bakes the same mask")
	var mat := VillageBuilder.meadow_material(l, cfg, origin, e * 2.0)
	check(mat.shader != null and mat.get_shader_parameter("use_wear") == true, "meadow material uses the wear mask")
	check(mat.get_shader_parameter("wear_mask") is Texture2D, "wear mask is bound to the shader")


func test_outfits_dress_every_villager() -> void:
	if not OutfitKit.available():
		check(true, "outfit pack not in project; painted clothing is used")
		return
	var w := WorldGenerator.generate("outfit-seed")
	var styles := {}
	for c in w.characters:
		var look := OutfitKit.look_for(c)
		check(not (look["parts"] as Array).is_empty(), "%s wears outfit parts" % c.full_name())
		for part: String in look["parts"]:
			check(ResourceLoader.exists(OutfitKit.part_path(part)), "%s: part %s exists" % [c.full_name(), part])
			var cut := part.ends_with("_F" if c.gender == "female" else "_M") if part.contains(":") else part.begins_with("Female_" if c.gender == "female" else "Male_")
			check(cut, "%s wears %s-cut %s" % [c.full_name(), c.gender, part])
		check_eq(look, OutfitKit.look_for(c), "%s's look is stable" % c.full_name())
		check(not OutfitKit.describe(look).is_empty(), "%s's clothes can be described" % c.full_name())
		var headwear := str(c.occupation().get("headwear", ""))
		var hides := headwear in ["hood", "helmet"] or (headwear == "veil" and c.gender == "female")
		check(bool(look["hides_hair"]) == hides, "%s's hair is hidden only under a hood, helmet or veil" % c.full_name())
		if c.outfit() == "armor":
			check(str(look["key"]).contains("Pauldron"), "%s (armor) has shoulder armor" % c.full_name())
		styles[c.outfit()] = true
		if c.outfit() in ["fine", "gown"]:
			check_eq(int(look["colorways"].get("ranger", -1)), 1, "%s (noble) wears the leather colorway" % c.full_name())
	check(styles.size() >= 4, "several outfit styles appear (%s)" % [styles.keys()])
	# Built model: one merged outfit mesh, the base body cut down to the head.
	var c0 := w.characters[0]
	var m := HumanModel.for_character(c0)
	var outfit := m.find_child("Outfit", true, false) as MeshInstance3D
	check(outfit != null and outfit.skin != null, "outfit mesh is skinned to the villager")
	check(outfit.mesh.get_surface_count() <= 4, "outfit parts are merged by material (%d surfaces)" % outfit.mesh.get_surface_count())
	var head := m.find_child("Head", true, false) as MeshInstance3D
	check(head != null and head.mesh.get_aabb().position.y > 1.3, "only the head of the base body remains")
	check(m.find_child("AnimationPlayer", true, false) != null, "dressed villager still animates")
	var again := HumanModel.for_character(c0)
	check((again.find_child("Outfit", true, false) as MeshInstance3D).mesh == outfit.mesh, "same look shares one mesh")
	m.free()
	again.free()


func test_nature_kit_trees_and_scatter() -> void:
	if not NatureKit.available():
		check(true, "nature kit not in project; primitive trees are used")
		return
	var w := WorldGenerator.generate("nature-seed")
	var b := VillageBuilder.new()
	b.build(w.layout)
	var nature := b.get_node_or_null("Nature")
	check(nature != null, "nature is built from the kit")
	var mmis := nature.find_children("*", "MultiMeshInstance3D", false, false)
	check(not mmis.is_empty(), "nature is drawn as MultiMeshes")
	for mmi: MultiMeshInstance3D in mmis:
		check(mmi.multimesh.use_custom_data, "%s carries tint and wind data" % mmi.name)
		check(mmi.multimesh.mesh != null, "%s has a kit mesh" % mmi.name)
	var trees := 0
	for list: Array in b.tree_items().values():
		trees += list.size()
	check_eq(trees, w.layout.trees.size(), "every layout tree spot gets a kit tree")
	for group: Dictionary in NatureKit.config().get("scatter", []):
		var items := b.scatter_items(group)
		var limit := 0.75 if group.has("wear") else 0.3
		var total := 0
		var on_paths := 0
		for list: Array in items.values():
			for it: Array in list:
				var o: Vector3 = (it[0] as Transform3D).origin
				total += 1
				if b.wear_at(Vector2(o.x, o.z)) > limit:
					on_paths += 1
		check(total > 0, "%s is scattered (%d)" % [group["name"], total])
		check_eq(on_paths, 0, "%s stays off roads, the square and buildings" % group["name"])
	var again := VillageBuilder.new()
	again.build(w.layout)
	check_eq(str(again.tree_items()), str(b.tree_items()), "tree placement is deterministic")
	var grass: Dictionary = NatureKit.config()["scatter"][0]
	check_eq(str(again.scatter_items(grass)), str(b.scatter_items(grass)), "scatter is deterministic")
	b.free()
	again.free()


func test_props_kit_sets_and_dressing() -> void:
	if not PropKit.available():
		check(true, "props kit not in project; simple prop shapes are used")
		return
	var cfg := PropKit.config()
	var sets: Dictionary = cfg.get("sets", {})
	for type: String in cfg.get("replace", {}):
		for set_name: String in cfg["replace"][type]:
			check(sets.has(set_name), "%s props use known set %s" % [type, set_name])
	for type: String in cfg.get("dressing", {}):
		if type.begins_with("_"):
			continue
		check(not GameData.building_type(type).is_empty(), "dressing is for a real building type (%s)" % type)
		for e: Array in cfg["dressing"][type]:
			# "NAME@tier" names a set per home level (NAME_0, NAME_1...): at least one.
			check(sets.has(PropKit.dressing_set(str(e[0]), 9)), "%s dressing uses known set %s" % [type, e[0]])
	var w := WorldGenerator.generate("props-seed")
	var b := VillageBuilder.new()
	b.build(w.layout)
	var merged := b.get_node("Props").find_children("Props *", "MeshInstance3D", false, false)
	check(not merged.is_empty(), "kit props are merged into chunk meshes")
	for mi: MeshInstance3D in merged:
		var names := {}
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			names[m.resource_name if m else "none"] = true
		check_eq(names.size(), mi.mesh.get_surface_count(), "%s has one surface per material" % mi.name)
	var dressing := b.dressing_items()
	check(dressing.size() > 20, "buildings are dressed with props (%d models)" % dressing.size())
	var on_road := 0
	for it: Array in dressing:
		var o: Vector3 = (it[1] as Transform3D).origin
		if b.road_clearance(Vector2(o.x, o.z)) < -0.3:
			on_road += 1
	check_eq(on_road, 0, "dressing stays off the roads")
	var again := VillageBuilder.new()
	again.build(w.layout)
	check_eq(str(again.dressing_items()), str(dressing), "dressing is deterministic")
	b.free()
	again.free()
