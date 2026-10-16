extends TestCase
## Status Wear (3D/characters/status-wear): headwear and aprons that show what
## a villager does and where they stand, skinned to the outfit rig.

const BUDGETS := {"SE_Circlet": 400, "SE_Crown": 600, "SE_Helmet": 900, "SE_StrawHat": 900, "SE_Cap": 800, "SE_BakerHat": 800,
	"SE_Veil": 900, "SE_Apron": 700}


## A copy of a generated villager with the given job, gender and hairstyle.
func _villager(occupation: String, gender: String, hair: String, id: int) -> CharacterData:
	var w := WorldGenerator.generate("wear-seed")
	var c := CharacterData.from_dict(w.characters[0].to_dict())
	c.id = id
	c.occupation_id = occupation
	c.gender = gender
	c.appearance["hair_style"] = hair
	return c


func test_every_wear_model_loads_within_budget() -> void:
	var dir := "res://3D/characters/status-wear/models/"
	var seen := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".glb"):
			continue
		seen += 1
		var root := (load(dir + f) as PackedScene).instantiate()
		var tris := 0
		var skinned := false
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			skinned = skinned or mi.skin != null
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				check(mat != null and mat.resource_name in ["MI_Wear", "MI_Wear_Metal"], "%s: a Status Wear material" % f)
				if mat:
					check(mat.albedo_texture != null, "%s: %s has its atlas" % [f, mat.resource_name])
				tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var budget := 0
		for prefix: String in BUDGETS:
			if f.begins_with(prefix):
				budget = BUDGETS[prefix]
		check(budget > 0 and tris <= budget and tris > 100, "%s: %d tris within its budget (%d)" % [f, tris, budget])
		check(skinned, "%s is skinned" % f)
		root.free()
	check_eq(seen, 27, "all 27 pieces are there")


func test_each_piece_shares_the_outfit_rig() -> void:
	# OutfitKit merges every part on the first part's skin: the binds must name
	# the same bones in the same order (it remaps by name if not, but they do).
	var body := load(OutfitKit.part_path("Male_Peasant_Body")) as PackedScene
	var ref: Skin = null
	var inst := body.instantiate()
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.skin:
			ref = mi.skin
	inst.free()
	check(ref != null, "the pack's body has a skin")
	for gender: String in ["male", "female"]:
		var wear: Dictionary = OutfitKit.config()["parts"][gender]["wear"]
		for slot: String in wear:
			var w := (load(OutfitKit.part_path(str(wear[slot]))) as PackedScene).instantiate()
			var skin: Skin = null
			for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
				skin = mi.skin
			check(skin != null and skin.get_bind_count() == ref.get_bind_count(), "%s: 65 binds" % wear[slot])
			if skin and ref:
				var same := true
				for i in skin.get_bind_count():
					same = same and skin.get_bind_name(i) == ref.get_bind_name(i)
				check(same, "%s binds the rig's bones in its order" % wear[slot])
			w.free()


func test_headwear_follows_the_job_and_the_hair() -> void:
	var cases := [
		# job, gender, hair, part expected, hair hidden, hair shown
		["farmer", "male", "short", "wear:SE_StrawHat_Short_M", false, "short"],
		["farmer", "female", "long", "wear:SE_StrawHat_Long_F", false, "long"],
		["miller", "male", "braid", "wear:SE_Cap_Long_M", false, "braid"],
		["baker", "female", "bun", "wear:SE_BakerHat_Long_F", false, "long"],
		["lord", "male", "cropped", "wear:SE_Circlet_Short_M", false, "cropped"],
		["queen", "female", "long", "wear:SE_Crown_Long_F", false, "long"],
		["soldier", "male", "long", "wear:SE_Helmet_M", true, "long"],
		["dowager", "female", "bun", "wear:SE_Veil_F", true, "bun"],
		["dowager", "male", "short", "wear:SE_Cap_Short_M", false, "short"],
		["woodcutter", "female", "long", "Female_Ranger_Head_Hood", true, "long"],
	]
	for i in cases.size():
		var e: Array = cases[i]
		var c := _villager(str(e[0]), str(e[1]), str(e[2]), 7000 + i)
		var look := OutfitKit.look_for(c)
		check((look["parts"] as Array).has(e[3]), "%s (%s, %s hair) wears %s (%s)" % [e[0], e[1], e[2], e[3], look["parts"]])
		check_eq(bool(look["hides_hair"]), bool(e[4]), "%s (%s): hair hidden %s" % [e[0], e[1], e[4]])
		check_eq(str(look["hair"]), str(e[5]), "%s (%s, %s): shows %s hair" % [e[0], e[1], e[2], e[5]])
	var bare := OutfitKit.look_for(_villager("farmhand", "male", "short", 7100))
	for part: String in bare["parts"]:
		check(not part.begins_with("wear:SE_") or part.contains("Apron"), "a farmhand goes bareheaded (%s)" % part)


func test_aprons_for_the_trades() -> void:
	var leather := OutfitKit.look_for(_villager("blacksmith", "male", "short", 7200))
	check((leather["parts"] as Array).has("wear:SE_ApronLeather_M"), "the smith wears leather")
	var linen := OutfitKit.look_for(_villager("baker", "female", "long", 7201))
	check((linen["parts"] as Array).has("wear:SE_ApronLinen_F"), "the baker wears linen")
	var none := OutfitKit.look_for(_villager("farmer", "male", "short", 7202))
	for part: String in none["parts"]:
		check(not part.contains("Apron"), "a farmer wears no apron")
	# Every apron job in the game gets one.
	for occ: String in GameData.load_file("occupations").get("occupations", {}):
		var c := _villager(occ, "female", "short", 7300)
		if c.outfit() == "apron":
			check(str(OutfitKit.look_for(c)["key"]).contains("Apron"), "%s wears an apron" % occ)


func test_a_dressed_villager_wears_it() -> void:
	var baker := HumanModel.for_character(_villager("baker", "male", "short", 7400))
	var outfit := baker.find_child("Outfit", true, false) as MeshInstance3D
	var mats := {}
	for s in outfit.mesh.get_surface_count():
		mats[str(outfit.mesh.surface_get_material(s).resource_name)] = true
	check(mats.keys().any(func(k: String) -> bool: return k.begins_with("wear:")), "the baker's cap and apron are merged into the outfit (%s)" % [mats.keys()])
	check(baker.find_child("Hair_SimpleParted", true, false) != null, "and his hair shows under the cap")
	baker.free()
	var soldier := HumanModel.for_character(_villager("soldier", "male", "short", 7401))
	check(soldier.find_child("Hair_SimpleParted", true, false) == null, "a helmet hides the hair")
	var smats := {}
	var so := soldier.find_child("Outfit", true, false) as MeshInstance3D
	for s in so.mesh.get_surface_count():
		smats[str(so.mesh.surface_get_material(s).resource_name)] = true
	check(smats.has("MI_Wear_Metal"), "the helmet is steel")
	soldier.free()


func test_a_caps_colour_follows_the_clothes() -> void:
	var variants: Array = OutfitKit.config()["sets"]["wear"]["variants"]
	for i in variants.size():
		var c := _villager("miller", "male", "short", 7500 + i)
		c.appearance["primary"] = str(variants[i]["swatch"])
		check_eq(int(OutfitKit.look_for(c)["colorways"]["wear"]), i, "a %s coat gets the matching cap" % variants[i]["swatch"])
		check(ResourceLoader.exists("res://3D/characters/status-wear/" + str(variants[i]["texture"])), "colorway %d's atlas is there" % i)


func test_portraits_describe_what_the_model_wears() -> void:
	var baker := PortraitPrompt.build(_villager("baker", "female", "long", 7600), 1)["prompt"] as String
	check(baker.contains("linen apron") and baker.contains("baker's cap"), "a baker's portrait has her linen apron and cap")
	var smith := PortraitPrompt.build(_villager("blacksmith", "male", "short", 7601), 1)["prompt"] as String
	check(smith.contains("leather apron"), "the smith's portrait has his leather apron")
	var elder := PortraitPrompt.build(_villager("dowager", "male", "short", 7602), 1)["prompt"] as String
	check(elder.contains("cloth cap") and not elder.contains("veil"), "an elder lord is painted in the cap he wears, not a veil")
