class_name OutfitKit
extends RefCounted
## Real clothes for villagers from the Quaternius Modular Character Outfits
## (3D/characters/quaternius-modular-outfits-fantasy-standard) and the game's
## own Status Wear (3D/characters/status-wear: headwear and aprons),
## configured in data/outfits.json.
##
## look_for() is pure data (character + JSON), so portraits can describe the
## same clothes the 3D model wears. dress() turns a look into one merged,
## skinned mesh per look (one surface per material), cached and shared by
## everyone wearing it, and moves the skeleton to the outfits' proportions.

const SLOTS := ["body", "arms", "legs", "feet"]

static var _available := -1
static var _parts: Dictionary = {}      # part name -> {"surfaces": [...], "skin": Skin}
static var _meshes: Dictionary = {}     # look key -> {"mesh": Mesh, "skin": Skin}
static var _materials: Dictionary = {}  # "set:colorway" / "skin:<material>" -> Material
static var _rests: Dictionary = {}      # gender -> {bone name: Transform3D}


static func config() -> Dictionary:
	return GameData.load_file("outfits")


## A part's file: "family:NAME" is one of the game's own (data/outfits.json
## "roots"), anything else the outfit pack's.
static func part_path(part: String) -> String:
	if part.contains(":"):
		var bits := part.split(":", true, 1)
		return str(config().get("roots", {}).get(bits[0], "")) + "models/%s.glb" % bits[1]
	return str(config().get("root", "")) + "models/parts/%s.gltf" % part


static func available() -> bool:
	if _available < 0:
		var parts: Dictionary = config().get("parts", {})
		var ok := not parts.is_empty()
		for g: String in parts:
			for set_id: String in parts[g]:
				for slot: String in parts[g][set_id]:
					ok = ok and ResourceLoader.exists(part_path(str(parts[g][set_id][slot])))
		_available = 1 if ok else 0
	return _available == 1


## What a character wears: {"gender", "parts": [part names], "colorways":
## {set: index}, "hides_hair": bool, "hair": hairstyle to show, "headwear":
## the headwear shown ("" for none), "apron": its slot ("" for none), "key"}.
static func look_for(c: CharacterData) -> Dictionary:
	var cfg := config()
	var g := "female" if c.gender == "female" else "male"
	var looks: Dictionary = cfg.get("looks", {})
	var look: Dictionary = looks.get(c.outfit(), looks.get("tunic", {}))
	var parts_cfg: Dictionary = cfg.get("parts", {}).get(g, {})
	var parts: Array[String] = []
	var sets: Array[String] = []
	for slot: String in SLOTS:
		var options: Array = look.get(slot, [])
		if options.is_empty():
			continue
		var set_id := str(options[_pick(c.id, slot, options.size())])
		parts.append(str(parts_cfg.get(set_id, {}).get(slot, "")))
		if not sets.has(set_id):
			sets.append(set_id)
	var extras: Array = (look.get("extras", []) as Array).duplicate()
	var apron := ""
	if bool(look.get("apron", false)):
		apron = str(cfg.get("aprons", {}).get(c.occupation_id, cfg.get("apron_default", "")))
		extras.append(apron)
	var hair := str(c.appearance.get("hair_style", "short"))
	var headwear := str(c.occupation().get("headwear", ""))
	headwear = str(cfg.get("instead", {}).get(g, {}).get(headwear, headwear))
	var slot := str(cfg.get("headwear", {}).get(headwear, ""))
	if not slot.is_empty() and (cfg.get("on_hair", []) as Array).has(headwear):
		var long := (cfg.get("long_hair", []) as Array).has(hair)
		slot += "_long" if long else "_short"
		if hair == "bun":
			hair = "long"  # let down under a hat
	if not slot.is_empty():
		extras.append(slot)
	var hides_hair := (cfg.get("hides_hair", []) as Array).has(headwear) and not slot.is_empty()
	for extra: String in extras:
		for set_id: String in parts_cfg:
			if parts_cfg[set_id].has(extra):
				parts.append(str(parts_cfg[set_id][extra]))
				if not sets.has(set_id):
					sets.append(set_id)
				break
	var colorways := {}
	var primary := Color.from_string(str(c.appearance.get("primary", "#7a6248")), Color("#7a6248"))
	for set_id in sets:
		colorways[set_id] = int(look["colorway"]) if look.has("colorway") else _nearest_colorway(set_id, primary)
	var key_parts := parts.duplicate()
	key_parts.sort()
	var cw_keys := colorways.keys()
	cw_keys.sort()
	var key := g + "|" + ",".join(key_parts)
	for k in cw_keys:
		key += "|%s:%d" % [k, colorways[k]]
	return {"gender": g, "parts": parts, "colorways": colorways, "hides_hair": hides_hair, "hair": hair,
		"headwear": headwear if not slot.is_empty() else "", "apron": apron, "key": key}


## Plain-language description for portrait prompts ("" if no outfit pack data).
static func describe(look: Dictionary) -> String:
	var sets: Dictionary = config().get("sets", {})
	var bits: Array[String] = []
	for set_id: String in look.get("colorways", {}):
		var variants: Array = sets.get(set_id, {}).get("variants", [])
		var i := int(look["colorways"][set_id])
		if i < variants.size():
			var d := str(variants[i].get("describe", ""))
			if not d.is_empty() and not bits.has(d):
				bits.append(d)
	var apron := str(look.get("apron", ""))
	if not apron.is_empty():
		bits.append(str(config().get("apron_describe", {}).get(apron, "an apron")))
	return " and ".join(bits)


## Puts the look on a Quaternius base skeleton: rests switch to the outfits'
## proportions and a merged outfit mesh is added. Returns the MeshInstance3D.
static func dress(skeleton: Skeleton3D, look: Dictionary) -> MeshInstance3D:
	var built := _mesh_for(look)
	if built.is_empty():
		return null
	var rests := _rests_for(str(look["gender"]))
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		if rests.has(bone):
			skeleton.set_bone_rest(i, rests[bone])
			skeleton.set_bone_pose(i, rests[bone])
	var mi := MeshInstance3D.new()
	mi.name = "Outfit"
	mi.mesh = built["mesh"]
	mi.skin = built["skin"]
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	return mi


## Skin material for the hands that come with the outfits and for the head
## cut from the base body (shaders/human_skin.gdshader).
static func skin_material(src: StandardMaterial3D, luminance: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/human_skin.gdshader")
	if src:
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("rough_tex", src.roughness_texture)
	mat.set_shader_parameter("skin_luminance", luminance)
	return mat


# --- Internals --------------------------------------------------------------------

static func _pick(id: int, slot: String, count: int) -> int:
	return absi(hash("%d:%s" % [id, slot])) % maxi(count, 1)


static func _nearest_colorway(set_id: String, primary: Color) -> int:
	var variants: Array = config().get("sets", {}).get(set_id, {}).get("variants", [])
	var best := 0
	var best_d := INF
	for i in variants.size():
		var s := Color(str(variants[i].get("swatch", "#808080")))
		var d := Vector3(s.r - primary.r, s.g - primary.g, s.b - primary.b).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


static func _part(part: String) -> Dictionary:
	if _parts.has(part):
		return _parts[part]
	var out := {}
	var path := part_path(part)
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		var surfaces: Array[Dictionary] = []
		var skin: Skin = null
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			if skin == null:
				skin = mi.skin
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				surfaces.append({"arrays": mi.mesh.surface_get_arrays(s), "material": m})
		if not surfaces.is_empty():
			out = {"surfaces": surfaces, "skin": skin}
		inst.free()
	_parts[part] = out
	return out


## Bone rests of the outfit rig (Regular proportions) for a gender.
static func _rests_for(gender: String) -> Dictionary:
	if _rests.has(gender):
		return _rests[gender]
	var out := {}
	var parts: Dictionary = config().get("parts", {}).get(gender, {})
	if not parts.is_empty():
		var first: Dictionary = parts.values()[0]
		var path := part_path(str(first.get("body", "")))
		if ResourceLoader.exists(path):
			var inst := (load(path) as PackedScene).instantiate()
			var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
			if sk:
				for i in sk.get_bone_count():
					out[sk.get_bone_name(i)] = sk.get_bone_rest(i)
			inst.free()
	_rests[gender] = out
	return out


## Material key for a source surface material: "set:colorway" for cloth,
## "skin:<name>" for the outfit's bare hands.
static func _material_key(src: Material, colorways: Dictionary) -> String:
	var name := src.resource_name if src else ""
	var cfg := config()
	if (cfg.get("skin_materials", []) as Array).has(name):
		return "skin:" + name
	var sets: Dictionary = cfg.get("sets", {})
	for set_id: String in sets:
		if str(sets[set_id].get("material", "")) == name:
			return "%s:%d" % [set_id, int(colorways.get(set_id, 0))]
	return "src:" + name


static func _material(key: String, src: Material) -> Material:
	if _materials.has(key):
		return _materials[key]
	var out: Material = src
	var bits := key.split(":")
	if bits[0] == "skin":
		out = skin_material(src as StandardMaterial3D, HumanModel.skin_luminance_of(src as StandardMaterial3D))
	elif bits[0] != "src" and src is StandardMaterial3D:
		var variants: Array = config().get("sets", {}).get(bits[0], {}).get("variants", [])
		var i := int(bits[1])
		var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
		if i < variants.size():
			var root := str(config().get("sets", {}).get(bits[0], {}).get("root", config().get("root", "")))
			var tex_path := root + str(variants[i].get("texture", ""))
			if ResourceLoader.exists(tex_path):
				m.albedo_texture = load(tex_path)
		m.resource_name = key
		out = m
	_materials[key] = out
	return out


## One mesh per look: every part's surfaces grouped by material and merged
## (all pieces share the rig's bind order), with LODs.
static func _mesh_for(look: Dictionary) -> Dictionary:
	var key := str(look["key"])
	if _meshes.has(key):
		return _meshes[key]
	var groups := {}  # material key -> {"src": Material, "chunks": [arrays]}
	var skin: Skin = null
	for part: String in look["parts"]:
		var p := _part(part)
		if p.is_empty():
			continue
		if skin == null:
			skin = p["skin"]
		var remap := _bind_remap(p["skin"], skin)
		for s: Dictionary in p["surfaces"]:
			var mk := _material_key(s["material"], look["colorways"])
			if not groups.has(mk):
				groups[mk] = {"src": s["material"], "chunks": []}
			groups[mk]["chunks"].append(_remapped(s["arrays"], remap))
	if groups.is_empty():
		_meshes[key] = {}
		return {}
	var importer := ImporterMesh.new()
	var keys := groups.keys()
	keys.sort()
	for mk: String in keys:
		var merged := _merge(groups[mk]["chunks"])
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if int(merged["per"]) == 8 else 0
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, merged["arrays"], [], {}, _material(mk, groups[mk]["src"]), mk, flags)
	importer.generate_lods(25.0, 60.0, [])
	var out := {"mesh": importer.get_mesh(), "skin": skin}
	_meshes[key] = out
	return out


## Bind index in `from` -> bind index in `to`, matched by bone name ({} when
## they already agree, as every part on this rig does).
static func _bind_remap(from: Skin, to: Skin) -> Dictionary:
	if from == null or to == null or from == to:
		return {}
	var index := {}
	for i in to.get_bind_count():
		index[to.get_bind_name(i)] = i
	var out := {}
	var same := from.get_bind_count() == to.get_bind_count()
	for i in from.get_bind_count():
		var j := int(index.get(from.get_bind_name(i), i))
		out[i] = j
		same = same and j == i
	return {} if same else out


static func _remapped(arrays: Array, remap: Dictionary) -> Array:
	if remap.is_empty():
		return arrays
	var out := arrays.duplicate()
	var bones: PackedInt32Array = (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).duplicate()
	for i in bones.size():
		bones[i] = int(remap.get(bones[i], bones[i]))
	out[Mesh.ARRAY_BONES] = bones
	return out


## Concatenates surface arrays (position, normal, tangent, UV, bones, weights,
## indices). Bone influences are padded to the largest count in the group.
static func _merge(chunks: Array) -> Dictionary:
	var per := 4
	for a: Array in chunks:
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		per = maxi(per, (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / maxi(v.size(), 1))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var all_tangents := true
	for a: Array in chunks:
		all_tangents = all_tangents and a[Mesh.ARRAY_TANGENT] != null
	for a: Array in chunks:
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(v)
		normals.append_array(a[Mesh.ARRAY_NORMAL])
		if all_tangents:
			tangents.append_array(a[Mesh.ARRAY_TANGENT])
		var uv: Variant = a[Mesh.ARRAY_TEX_UV]
		if uv == null:
			var blank := PackedVector2Array()
			blank.resize(v.size())
			uvs.append_array(blank)
		else:
			uvs.append_array(uv)
		var b: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var src_per := b.size() / maxi(v.size(), 1)
		if src_per == per:
			bones.append_array(b)
			weights.append_array(w)
		else:
			for i in v.size():
				for k in per:
					bones.append(b[i * src_per + k] if k < src_per else 0)
					weights.append(w[i * src_per + k] if k < src_per else 0.0)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in idx.size():
			indices.append(idx[i] + base)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	if all_tangents:
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"arrays": arrays, "per": per}
