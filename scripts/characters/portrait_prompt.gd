class_name PortraitPrompt
extends RefCounted
## Describes a villager for an AI image generator, so every AI portrait matches
## the character's data (hair color, skin, eyes, age, clothes, job, mood).
##
## The style text and negative prompt live in data/art_style.json so every
## portrait shares one look. Each character also gets a fixed seed, so the same
## person comes out the same every time on any generator that supports seeds
## (FLUX.2 [klein] via stable-diffusion.cpp, Draw Things, ComfyUI, Higgsfield).
##
## Finished images go in user://portraits/<world seed>/<character id>.png and
## the character card shows them automatically (see image_for()).

const PORTRAIT_DIR := "user://portraits/"


static func style() -> Dictionary:
	return GameData.load_file("art_style").get("portrait", {})


static func seed_for(c: CharacterData, world_seed: int) -> int:
	return Seeds.derive(world_seed, "portrait_%d" % c.id)


static func file_path(c: CharacterData, world_seed: int) -> String:
	return "%s%d/%d.png" % [PORTRAIT_DIR, world_seed, c.id]


## The AI portrait for this character if one has been generated, else null.
static func image_for(c: CharacterData, world_seed: int) -> Texture2D:
	var path := file_path(c, world_seed)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img else null


static func _color_name(hex: String, palette: Dictionary) -> String:
	## Nearest named color, so prompts say "auburn" instead of "#7a2e1c".
	var target := Color(hex)
	var best := ""
	var best_d := INF
	for name: String in palette:
		var c := Color(str(palette[name]))
		var d := Vector3(target.r - c.r, target.g - c.g, target.b - c.b).length()
		if d < best_d:
			best_d = d
			best = name
	return best


static func _age_words(c: CharacterData) -> String:
	if c.age < 6: return "a small %s of about %d" % ["boy" if c.gender == "male" else "girl", c.age]
	if c.age < 13: return "a %d-year-old %s" % [c.age, "boy" if c.gender == "male" else "girl"]
	if c.age < 18: return "a %d-year-old teenage %s" % [c.age, "boy" if c.gender == "male" else "girl"]
	var pron := "his" if c.gender == "male" else "her"
	if c.age < 30: return "a young %s in %s twenties" % ["man" if c.gender == "male" else "woman", pron]
	if c.age < 40: return "a %s in %s thirties" % ["man" if c.gender == "male" else "woman", pron]
	if c.age < 50: return "a %s in %s forties" % ["man" if c.gender == "male" else "woman", pron]
	if c.age < 60: return "a middle-aged %s" % ("man" if c.gender == "male" else "woman")
	return "an elderly %s of about %d" % ["man" if c.gender == "male" else "woman", c.age]


## Full prompt package for one character.
static func build(c: CharacterData, world_seed: int) -> Dictionary:
	var s := style()
	var ap := c.appearance
	var face := FaceFeatures.for_character(c)
	var hair_names: Dictionary = s.get("hair_names", {})
	var skin_names: Dictionary = s.get("skin_names", {})
	var eye_names: Dictionary = s.get("eye_names", {})
	var cloth_names: Dictionary = s.get("cloth_names", {})
	var parts: Array[String] = []
	var job := c.occupation_name().to_lower()
	parts.append("Portrait of %s, %s %s in a medieval village" % [_age_words(c), "an" if "aeiou".contains(job.left(1)) else "a", job])
	parts.append("%s skin" % _color_name(str(ap.get("skin", "#e0b48c")), skin_names))
	var hair_style := str(ap.get("hair_style", "short"))
	if hair_style == "bald":
		parts.append("bald head")
	else:
		var hair_color := _color_name(str(ap.get("hair", "#4a2f1d")), hair_names)
		parts.append(str({"short": "short %s hair", "long": "long flowing %s hair", "bun": "%s hair tied in a bun", "cropped": "close-cropped %s hair", "braid": "%s hair in a long braid"}.get(hair_style, "%s hair")) % hair_color)
	parts.append("%s eyes" % _color_name(str(ap.get("eyes", "#3b2a1a")), eye_names))
	if bool(ap.get("beard", false)):
		parts.append({"full": "a full beard", "short": "a short trimmed beard", "goatee": "a goatee", "mustache": "a mustache", "stubble": "stubble"}.get(str(face.get("beard_style", "full")), "a beard"))
	parts.append("%s face, %s nose" % [str(face.get("shape", "oval")), str(face.get("nose", "straight"))])
	if bool(face.get("freckles", false)):
		parts.append("freckles")
	if bool(face.get("scar", false)):
		parts.append("an old scar across one eyebrow")
	var occ := c.occupation()
	var primary := _color_name(str(ap.get("primary", "#7a6248")), cloth_names)
	var secondary := _color_name(str(ap.get("secondary", "#4a3a2a")), cloth_names)
	parts.append("wearing %s %s with %s trim" % [primary, {"tunic": "linen tunic", "robe": "wool robe", "gown": "fine gown", "armor": "chainmail and a tabard", "apron": "work clothes and a leather apron", "fine": "embroidered doublet"}.get(c.outfit(), "clothes"), secondary])
	var headwear := str(occ.get("headwear", ""))
	if not headwear.is_empty():
		parts.append({"circlet": "a thin gold circlet", "crown": "a gold crown", "helmet": "a steel nasal helmet", "straw_hat": "a straw hat", "hood": "a hood", "cap": "a cloth cap", "baker_hat": "a baker's cap", "veil": "a linen veil"}.get(headwear, headwear))
	var mood := "calm expression"
	if c.happiness >= 70: mood = "warm, content smile"
	elif c.happiness < 35: mood = "weary, unhappy expression"
	if c.has_trait("wrathful") or c.has_trait("cruel"): mood += ", stern brow"
	parts.append(mood)
	return {
		"character_id": c.id,
		"name": c.full_name(),
		"seed": seed_for(c, world_seed),
		"prompt": "%s. %s" % [", ".join(parts), str(s.get("style", ""))],
		"negative_prompt": str(s.get("negative", "")),
		"width": int(s.get("width", 768)),
		"height": int(s.get("height", 960)),
		"output": file_path(c, world_seed),
	}


## Writes every villager's prompt to user://portraits/<world seed>/prompts.json
## so the local generator (ai-art/generate_portraits.py) can paint the whole
## village without opening Godot. Returns the file's absolute path.
static func write_prompt_file(state: WorldState) -> String:
	var dir := "%s%d/" % [PORTRAIT_DIR, state.world_seed]
	DirAccess.make_dir_recursive_absolute(dir)
	var list: Array = []
	for c in state.characters:
		var p := build(c, state.world_seed)
		p["output_file"] = ProjectSettings.globalize_path(str(p["output"]))
		list.append(p)
	var path := dir + "prompts.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({
		"game": "Sovereign's Eye",
		"seed_text": state.seed_text,
		"world_seed": state.world_seed,
		"village": state.village_name,
		"portraits": list,
	}, "  "))
	f.close()
	return ProjectSettings.globalize_path(path)

