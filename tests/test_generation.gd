extends TestCase

const SEEDS := ["12345", "Ashford", "999", "dragon", "7", "441122"]


func test_population_and_identity() -> void:
	for s in SEEDS:
		var w := WorldGenerator.generate(s)
		check_eq(w.characters.size(), GameData.population_target(), "population for seed %s" % s)
		for c in w.characters:
			check(not c.first_name.is_empty() and not c.last_name.is_empty(), "%d has a name" % c.id)
			check(c.gender == "male" or c.gender == "female", "%s has a gender" % c.full_name())
			check(not c.occupation().is_empty(), "%s has a valid occupation (%s)" % [c.full_name(), c.occupation_id])
			check(not GameData.status_def(c.social_status).is_empty(), "%s has a valid status" % c.full_name())
			check(w.get_family(c.family_id) != null, "%s has a family" % c.full_name())
			check(w.get_building(c.home_building_id) != null, "%s has a home" % c.full_name())
			check(c.traits.size() >= 2, "%s has traits" % c.full_name())
			check(not c.history.is_empty(), "%s has a history" % c.full_name())
			check(not c.appearance.is_empty(), "%s has an appearance" % c.full_name())


func test_deterministic_from_seed() -> void:
	var a := JSON.stringify(WorldGenerator.generate("12345").to_dict())
	var b := JSON.stringify(WorldGenerator.generate("12345").to_dict())
	check(a == b, "same seed gives identical worlds")
	var c := JSON.stringify(WorldGenerator.generate("12346").to_dict())
	check(a != c, "different seeds give different worlds")


func test_current_never_exceeds_potential() -> void:
	for s in SEEDS:
		var w := WorldGenerator.generate(s)
		for c in w.characters:
			for attr_id in GameData.attribute_ids():
				check(c.get_current(attr_id) <= c.get_potential(attr_id), "%s %s" % [c.full_name(), attr_id])
				check(c.get_current(attr_id) >= 0, "%s %s non-negative" % [c.full_name(), attr_id])


func test_rank_mix_in_villages() -> void:
	var counts := {}
	var exceptional_people := 0
	var villages := 20
	for i in villages:
		var w := WorldGenerator.generate(str(1000 + i))
		for c in w.characters:
			if Appraisal.is_exceptional(c):
				exceptional_people += 1
			for attr_id in GameData.attribute_ids():
				var r := Appraisal.rank_id(c.get_potential(attr_id))
				counts[r] = int(counts.get(r, 0)) + 1
	var most := ""
	for k: String in counts:
		if most.is_empty() or counts[k] > counts[most]:
			most = k
	check_eq(most, "D", "D is the most common rank in generated villages")
	var per_village := float(exceptional_people) / villages
	check(per_village >= 1.0 and per_village <= 12.0, "a village has a handful of S-rank talents (%.1f)" % per_village)


func test_relationships_are_consistent() -> void:
	var w := WorldGenerator.generate("Ashford")
	var reverse := {
		"spouse": ["spouse"], "parent": ["child"], "child": ["parent"], "sibling": ["sibling"],
		"grandparent": ["grandchild"], "grandchild": ["grandparent"],
		"friend": ["friend"], "rival": ["rival"], "lover": ["lover"],
	}
	for c in w.characters:
		for r in c.relationships:
			var other := w.get_character(int(r["target"]))
			check(other != null, "%s relationship target exists" % c.full_name())
			if other == null:
				continue
			var back := other.get_relationship(c.id)
			check(not back.is_empty(), "%s <-> %s is mutual" % [c.full_name(), other.full_name()])
			if not back.is_empty():
				check(reverse[r["type"]].has(back["type"]), "%s %s / %s match" % [c.full_name(), r["type"], back["type"]])
			if r["type"] in ["lover", "spouse"]:
				check(c.age >= 16 and other.age >= 16, "romance only between adults (%s)" % c.full_name())


func test_village_layout() -> void:
	for s in SEEDS:
		var w := WorldGenerator.generate(s)
		var n := w.layout.buildings.size()
		check(n >= 15 and n <= 20, "15-20 buildings for seed %s (got %d)" % [s, n])
		check(w.layout.buildings_of_type("manor").size() == 1, "one manor")
		check(not w.layout.fields.is_empty(), "farmland exists")
		check(w.layout.trees.size() > 150, "trees exist")
		var ruling := w.ruling_family()
		check(ruling != null, "ruling family exists")
		if ruling:
			check_eq(w.get_building(ruling.home_building_id).type, "manor", "ruling family lives in the manor")


func test_portrait_prompts_match_character_data() -> void:
	var w := WorldGenerator.generate("prompt-seed")
	var seen_seeds := {}
	for c in w.characters:
		var p := PortraitPrompt.build(c, w.world_seed)
		check(p["prompt"].contains(c.occupation_name().to_lower()), "%s prompt names the job" % c.full_name())
		if str(c.appearance.get("hair_style", "")) != "bald":
			check(p["prompt"].contains("hair"), "%s prompt describes hair" % c.full_name())
		check(not seen_seeds.has(p["seed"]), "portrait seeds are unique")
		seen_seeds[p["seed"]] = true
		check_eq(p["seed"], PortraitPrompt.build(c, w.world_seed)["seed"], "portrait seed is stable")
		check(c.appearance.get("face") is Dictionary, "%s has stored facial features" % c.full_name())
	# A finished image placed at the output path is picked up by the card.
	var c0 := w.characters[0]
	var path := PortraitPrompt.file_path(c0, w.world_seed)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(8, 10, false, Image.FORMAT_RGB8)
	img.fill(Color.DARK_RED)
	img.save_png(path)
	check(PortraitPrompt.image_for(c0, w.world_seed) != null, "AI portrait file is loaded")
	DirAccess.remove_absolute(path)
	check(PortraitPrompt.image_for(c0, w.world_seed) == null, "no file -> no AI portrait")


func test_portrait_figures_are_adults_only() -> void:
	var curvy_women := 0
	for s in SEEDS:
		var w := WorldGenerator.generate(s)
		for c in w.characters:
			check(not str(c.appearance.get("figure", "")).is_empty(), "%s has a stored figure" % c.full_name())
			var prompt: String = PortraitPrompt.build(c, w.world_seed)["prompt"]
			if c.age < 18:
				check(FaceFeatures.figure_text(c).is_empty(), "%s (age %d) gets no body description" % [c.full_name(), c.age])
				for word: String in ["bust", "figure", "build", "hourglass", "curvy", "voluptuous"]:
					check(not prompt.contains(word), "%s (age %d) prompt has no '%s'" % [c.full_name(), c.age, word])
			elif c.gender == "female" and FaceFeatures.figure_text(c).contains("bust"):
				curvy_women += 1
				check(prompt.contains("bust"), "%s prompt describes her figure" % c.full_name())
	check(curvy_women > 0, "some adult women have full figures (%d)" % curvy_women)
