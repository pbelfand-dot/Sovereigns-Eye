extends TestCase


func test_rank_boundaries() -> void:
	var cases := {
		0: "F", 19: "F", 20: "D", 49: "D", 50: "C", 64: "C", 65: "B", 79: "B",
		80: "A", 99: "A", 100: "S", 119: "S", 120: "S+", 149: "S+", 150: "SS", 240: "SS",
	}
	for value: int in cases:
		check_eq(Appraisal.rank_id(value), cases[value], "rank for %d" % value)


func test_format_matches_spec() -> void:
	var c := CharacterData.new()
	c.set_attribute("leadership", 12, 126)
	check_eq(Appraisal.format_attribute(c, "leadership"), "Leadership: 12 / 126 (S+)", "spec example")


func test_current_never_exceeds_potential() -> void:
	var c := CharacterData.new()
	c.set_attribute("combat", 300, 60)
	check_eq(c.get_current("combat"), 60, "set clamps current")
	c.set_attribute("combat", 10, 60)
	var gained := c.train("combat", 500)
	check_eq(c.get_current("combat"), 60, "training stops at potential")
	check_eq(gained, 50, "train reports actual gain")
	c.raise_potential("combat", 20)
	check_eq(c.get_potential("combat"), 80, "potential can be raised")
	check_eq(c.get_current("combat"), 60, "raising potential keeps current")


func test_appraisal_levels() -> void:
	var c := CharacterData.new()
	for attr_id in GameData.attribute_ids():
		c.set_attribute(attr_id, 10, 130)
	var full := Appraisal.appraise(c)
	check(full["potential_visible"], "full appraisal sees potential")
	check(full["exceptional"], "130 potential is exceptional")
	check_eq(full["attributes"].size(), 6, "six attributes")
	var weak := Appraisal.appraise(c, 10)
	check(not weak["potential_visible"], "weak appraisal hides potential")
	check_eq(int(weak["attributes"][0]["potential"]), -1, "hidden potential reported as -1")


func test_potential_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts := {}
	var n := 60000
	for i in n:
		var r := Appraisal.rank_id(TalentRoller.roll_potential(rng))
		counts[r] = int(counts.get(r, 0)) + 1
	var most := ""
	for k: String in counts:
		if most.is_empty() or counts[k] > counts[most]:
			most = k
	check_eq(most, "D", "D is the most common rank")
	var elite := float(counts.get("S+", 0) + counts.get("SS", 0)) / n
	check(elite < 0.012, "S+ and SS are rare (%.4f)" % elite)
	check(counts.get("SS", 0) > 0, "SS is possible")
	check(float(counts.get("S", 0)) / n < 0.025, "S is uncommon")


func test_affinity_raises_odds_without_guarantee() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 7
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 7
	var neutral_high := 0
	var boosted_high := 0
	var boosted_low := 0
	for i in 20000:
		if TalentRoller.roll_potential(rng_a, 1.0) >= 80:
			neutral_high += 1
		var v := TalentRoller.roll_potential(rng_b, 1.3)
		if v >= 80:
			boosted_high += 1
		if v < 50:
			boosted_low += 1
	check(boosted_high > neutral_high, "affinity 1.3 increases A+ odds (%d vs %d)" % [boosted_high, neutral_high])
	check(boosted_low > 5000, "favored families still produce many ordinary people")


func test_style_unifier_converts_materials() -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = Mats.hex("#3aa0b0")
	root.add_child(mi)
	StyleUnifier.apply(root)
	check(mi.material_override is ShaderMaterial, "materials become the unified toon shader")
	var palette: Array = GameData.load_file("art_style").get("palette", [])
	check_eq(int((mi.material_override as ShaderMaterial).get_shader_parameter("palette_size")), palette.size(), "shader gets the whole palette")
	root.free()
