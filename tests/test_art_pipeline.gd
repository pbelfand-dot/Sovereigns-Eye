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
