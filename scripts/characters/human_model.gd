class_name HumanModel
extends CharacterModel
## A villager built from the Quaternius Universal Base Characters
## (3D/character-tests/quaternius-universal-base-standard) and animated with the
## in-place Universal Animation Libraries (3D/animations).
##
## Everything comes from the character's data: body by gender, height/build,
## skin tone, hair style and color, beard, and clothing. Villagers wear real
## clothes from the Quaternius outfit pack (OutfitKit) over the head of the
## base body; without the pack, clothing is painted on in their outfit colors
## (shaders/human_body.gdshader). Bodies, hair meshes, materials, outfit
## meshes and the animation library are loaded once and shared by everyone.
## Per-villager colors are instance shader parameters, so a crowd costs no
## extra materials.
##
## Use HumanModel.for_character(c): it falls back to the primitive
## CharacterModel when the Quaternius files aren't in the project.

const ROOT := "res://3D/character-tests/quaternius-universal-base-standard/models/"
const BODIES := {"male": "bodies/Superhero_Male_FullBody.glb", "female": "bodies/Superhero_Female_FullBody.glb"}
## Source model heights (m) and the adult heights we scale them to.
const SOURCE_HEIGHT := {"male": 1.81, "female": 1.775}
const TARGET_HEIGHT := {"male": 1.74, "female": 1.70}
## Pelvis height of the animation mannequin; root motion is rescaled per body.
const MANNEQUIN_PELVIS := 0.9167
const HAIR := {
	"male": {"short": "Hair_SimpleParted", "long": "Hair_Long", "bun": "Hair_Buns", "cropped": "Hair_Buzzed", "braid": "Hair_Long"},
	"female": {"short": "Hair_SimpleParted", "long": "Hair_Long", "bun": "Hair_Buns", "cropped": "Hair_BuzzedFemale", "braid": "Hair_Long", "bald": "Hair_BuzzedFemale"},
}
## Which of the two hair texture sheets a hair mesh is UV-mapped to.
const HAIR_SHEET := {"Hair_SimpleParted": 1, "Hair_Buzzed": 1, "Hair_BuzzedFemale": 1, "Hair_Beard": 1, "Hair_Long": 2, "Hair_Buns": 2}
const OUTFITS := ["tunic", "robe", "gown", "armor", "apron", "fine"]
## Bones whose weight keeps a vertex in the head cut from the base body, and
## how much of it a vertex needs (low, so the neck reaches into the collar).
const HEAD_BONES := ["neck_01", "Head"]
const HEAD_CUT_WEIGHT := 0.15
## Skin luminance the base body's texture is tuned to (see human_skin.gdshader).
const BASE_SKIN_LUMINANCE := 0.36

static var _available := -1
static var _bodies: Dictionary = {}          # gender -> shared body data
static var _hair_meshes: Dictionary = {}     # hair name -> {"mesh", "skin"}
static var _hair_materials: Dictionary = {}  # sheet (1/2) -> ShaderMaterial
static var _texture_luminance: Dictionary = {}  # texture path -> average linear luminance

var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _mode := ""
var _clip := ""
var _variety := 0
var _speed := 1.0
var _occupation_id := ""
var _is_child := false
var _is_noble := false
var _head_y := 1.68
var _weapons: Array[Node3D] = []


static func available() -> bool:
	if _available < 0:
		_available = 1 if ResourceLoader.exists(ROOT + BODIES["male"]) and ResourceLoader.exists(ROOT + BODIES["female"]) else 0
	return _available == 1


## The best available body for a character.
static func for_character(c: CharacterData) -> CharacterModel:
	if available():
		var m := HumanModel.new()
		m.name = "Model"
		if m._build_human(c):
			return m
		m.free()
	return CharacterModel.create(c.appearance, c.occupation(), c.gender, c.age)


static func anim_config() -> Dictionary:
	return GameData.load_file("animations")


func head_height() -> float:
	return _head_y * scale.y


func _build_human(c: CharacterData) -> bool:
	var g := "female" if c.gender == "female" else "male"
	var body := _body(g)
	if body.is_empty():
		return false
	var ap := c.appearance
	_occupation_id = c.occupation_id
	_is_child = c.age < 14
	_is_noble = anim_config().get("noble_occupations", []).has(c.occupation_id)
	_variety = c.id * 7

	var inst: Node3D = (body["scene"] as PackedScene).instantiate()
	inst.name = "Body"
	inst.rotation.y = PI  # Quaternius models face +Z; ours face -Z.
	add_child(inst)
	_skeleton = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var hair_color := Color.from_string(str(ap.get("hair", "#4a2f1d")), Color("#4a2f1d"))
	var skin := Color.from_string(str(ap.get("skin", "#e0b48c")), Color("#e0b48c"))
	var look := OutfitKit.look_for(c) if body.has("head_mesh") else {}
	var outfit := OUTFITS.find(c.outfit())
	for child in _skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		match str(mi.name):
			"Eyes":
				pass
			"Eyebrows":
				mi.material_override = _hair_material(1 if g == "male" else 2)
				mi.set_instance_shader_parameter("hair_color", hair_color)
			_:
				mi.set_instance_shader_parameter("skin_tint", skin)
				if not look.is_empty():
					mi.name = "Head"
					mi.mesh = body["head_mesh"]
					continue
				mi.mesh = _painted_mesh(g)
				mi.material_override = body["material"]
				mi.set_instance_shader_parameter("cloth_primary", Color.from_string(str(ap.get("primary", "#7a6248")), Color("#7a6248")))
				mi.set_instance_shader_parameter("cloth_secondary", Color.from_string(str(ap.get("secondary", "#4a3a2a")), Color("#4a3a2a")))
				mi.set_instance_shader_parameter("outfit", float(maxi(outfit, 0)))
	if not look.is_empty():
		var clothes := OutfitKit.dress(_skeleton, look)
		if clothes:
			clothes.set_instance_shader_parameter("skin_tint", skin)

	var style := str(look.get("hair", ap.get("hair_style", "short")))
	var hair_name := str(HAIR[g].get(style, ""))
	if not hair_name.is_empty() and not bool(look.get("hides_hair", false)):
		_attach_hair(hair_name, hair_color)
	if g == "male" and bool(ap.get("beard", false)):
		_attach_hair("Hair_Beard", hair_color)
	# Age and build over the animation: an old villager stoops, a heavy one is broad in the belly.
	var shape := BodyShape.for_character(c)
	if shape:
		_skeleton.add_child(shape)

	# Size: appearance height already includes childhood growth.
	var s := float(ap.get("height", 1.0)) * float(TARGET_HEIGHT[g]) / float(SOURCE_HEIGHT[g])
	var widths: Array = GameData.appearance().get("body_shape", {}).get("width_range", [0.96, 1.06])
	var b := lerpf(float(widths[0]), float(widths[1]), inverse_lerp(0.85, 1.2, float(ap.get("build", 1.0))))
	scale = Vector3(s * b, s, s * b)
	body_height = s
	_head_y = float(body["head_y"])
	if _is_child:
		# Children's heads are large for their bodies.
		var head := _skeleton.find_bone("Head")
		var grow := clampf(1.0 + (1.0 - s) * 0.9, 1.0, 1.45)
		_skeleton.set_bone_pose_scale(head, Vector3.ONE * grow)

	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	inst.add_child(_player)
	_player.add_animation_library("", body["library"])
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animate("idle", 0.0, 0.0)
	return true


func _attach_hair(hair_name: String, color: Color) -> void:
	var h := _hair(hair_name)
	if h.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = hair_name
	mi.mesh = h["mesh"]
	mi.skin = h["skin"]
	_skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.material_override = _hair_material(int(HAIR_SHEET.get(hair_name, 1)))
	mi.set_instance_shader_parameter("hair_color", color)


# --- Animation ------------------------------------------------------------------

## mode: "idle", "walk", "work", "talk" (same as CharacterModel).
func animate(mode: String, _phase: float, delta: float) -> void:
	if _player == null:
		return
	if mode != _mode:
		_mode = mode
		_variety += 1
		var modes: Dictionary = anim_config().get("modes", {})
		_speed = float(modes.get(mode, {}).get("speed", 1.0))
		var clip := _clip_for(mode)
		if not clip.is_empty() and clip != _clip:
			var first := _clip.is_empty()
			_clip = clip
			_player.play(clip, 0.0 if first else 0.3)
			if first:
				var length := _player.get_animation(clip).length
				_player.seek(fmod(float(_variety) * 0.37, maxf(length, 0.01)), true)
	var rate := anim_time_scale if mode in ["walk", "run"] else sqrt(maxf(anim_time_scale, 0.0))
	if _is_child and mode == "walk":
		rate *= 1.25
	_player.advance(delta * rate * _speed)


func _clip_for(mode: String) -> String:
	var cfg := anim_config()
	var modes: Dictionary = cfg.get("modes", {})
	var m: Dictionary = modes.get(mode, modes.get("idle", {}))
	var list: Array = m.get("default", ["Idle"])
	var by_job: Dictionary = cfg.get("work_by_occupation", {})
	if mode == "work" and not _is_child and by_job.has(_occupation_id):
		list = by_job[_occupation_id]
	elif _is_child and m.has("child"):
		list = m["child"]
	elif _is_noble and m.has("noble"):
		list = m["noble"]
	for i in list.size():
		var clip := str(list[(_variety + i) % list.size()])
		if _player.has_animation(clip):
			return clip
	return "Idle" if _player.has_animation("Idle") else ""


## Plays the current clip again from the start (a second blow, a second
## stagger).
func replay() -> void:
	if _player and not _clip.is_empty():
		_player.play(_clip, 0.05)
		_player.seek(0.0, true)


# --- Arms (Phase 5.1) ------------------------------------------------------------

## Arms the body for a fight: `kinds` like ["sword", "shield"] (data/animations.json
## "weapons"), held in the hands; [] puts them away.
func set_weapons(kinds: Array) -> void:
	for w in _weapons:
		if is_instance_valid(w):
			w.queue_free()
	_weapons.clear()
	if _skeleton == null or kinds.is_empty():
		return
	var cfg: Dictionary = anim_config().get("weapons", {})
	for kind: String in kinds:
		var off := kind == "shield"
		var bone := "hand_l" if off else "hand_r"
		var path := str(cfg.get("root", "")) + str(cfg.get(kind, ""))
		if _skeleton.find_bone(bone) < 0 or not ResourceLoader.exists(path):
			continue
		var att := BoneAttachment3D.new()
		att.name = "Weapon_%s" % kind
		att.bone_name = bone
		_skeleton.add_child(att)
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		var t: Dictionary = cfg.get("off_hand" if off else "hand", {})
		var p: Array = t.get("position", [0, 0, 0])
		var r: Array = t.get("rotation", [0, 0, 0])
		inst.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		inst.rotation_degrees = Vector3(float(r[0]), float(r[1]), float(r[2]))
		inst.scale = Vector3.ONE * float(t.get("scale", 1.0))
		att.add_child(inst)
		_weapons.append(att)


# --- Shared resources -------------------------------------------------------------

static func _body(gender: String) -> Dictionary:
	if _bodies.has(gender):
		return _bodies[gender]
	var path := ROOT + str(BODIES[gender])
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		_bodies[gender] = {}
		return {}
	var inst := scene.instantiate()
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var body_mi: MeshInstance3D = null
	var brow_mi: MeshInstance3D = null
	for child in skel.get_children():
		if child is MeshInstance3D:
			if child.name == "Eyebrows":
				brow_mi = child
			elif child.name != "Eyes":
				body_mi = child
	var src := body_mi.mesh.surface_get_material(0) as StandardMaterial3D
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/human_body.gdshader")
	if src:
		mat.set_shader_parameter("albedo_tex", src.albedo_texture)
		mat.set_shader_parameter("normal_tex", src.normal_texture)
		mat.set_shader_parameter("rough_tex", src.roughness_texture)
	if brow_mi:
		_register_hair_sheet(1 if gender == "male" else 2, brow_mi.mesh.surface_get_material(0) as StandardMaterial3D)
	var pelvis := skel.get_bone_global_rest(skel.find_bone("pelvis")).origin.y
	var data := {
		"scene": scene,
		"material": mat,
		"library": _library(pelvis / MANNEQUIN_PELVIS),
		"head_y": skel.get_bone_global_rest(skel.find_bone("Head")).origin.y + 0.08,
	}
	if OutfitKit.available():
		var head_mat := OutfitKit.skin_material(src, skin_luminance_of(src))
		data["head_mesh"] = _cut_head(body_mi, skel, head_mat)
	else:
		data["mesh"] = _bake_regions(body_mi, skel, float(SOURCE_HEIGHT[gender]))
	inst.free()
	_bodies[gender] = data
	return data


## The painted full body (only built when a villager has no outfit).
static func _painted_mesh(gender: String) -> Mesh:
	var data := _body(gender)
	if not data.has("mesh"):
		var inst := (data["scene"] as PackedScene).instantiate()
		var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
		for child in skel.get_children():
			if child is MeshInstance3D and child.name != "Eyes" and child.name != "Eyebrows":
				data["mesh"] = _bake_regions(child, skel, float(SOURCE_HEIGHT[gender]))
		inst.free()
	return data["mesh"]


## Skin shader luminance for a skin texture: scaled so every texture's average
## skin maps to the same brightness the base body is tuned to.
static func skin_luminance_of(src: StandardMaterial3D) -> float:
	var reference := _average_luminance(load(ROOT + "bodies/Superhero_Male_FullBody_T_Superhero_Male_Dark.png") as Texture2D)
	var own := _average_luminance(src.albedo_texture if src else null)
	if reference <= 0.0 or own <= 0.0:
		return BASE_SKIN_LUMINANCE
	return BASE_SKIN_LUMINANCE * own / reference


static func _average_luminance(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	var key := tex.resource_path
	if _texture_luminance.has(key):
		return _texture_luminance[key]
	var lum := 0.0
	var img := tex.get_image()
	if img and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
		for y in 8:
			for x in 8:
				var px := img.get_pixel(x, y).srgb_to_linear()
				lum += (px.r * 0.2126 + px.g * 0.7152 + px.b * 0.0722) / 64.0
	_texture_luminance[key] = lum
	return lum


## The head and neck of the base body, for villagers wearing outfits (the
## outfit pieces bring their own torso, arms, hands, legs and feet).
static func _cut_head(mi: MeshInstance3D, skel: Skeleton3D, material: Material) -> Mesh:
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(verts.size(), 1)
	var head_bind := PackedByteArray()
	var bind_count := mi.skin.get_bind_count() if mi.skin else skel.get_bone_count()
	head_bind.resize(bind_count)
	for i in bind_count:
		var bone_name := str(mi.skin.get_bind_name(i)) if mi.skin else skel.get_bone_name(i)
		head_bind[i] = 1 if HEAD_BONES.has(bone_name) else 0
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var kept := PackedInt32Array()
	for v in verts.size():
		var w := 0.0
		for k in per:
			var b := bones[v * per + k]
			if b < head_bind.size() and head_bind[b] == 1:
				w += weights[v * per + k]
		if w >= HEAD_CUT_WEIGHT:
			remap[v] = kept.size()
			kept.append(v)
	var src_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var idx := PackedInt32Array()
	for t in range(0, src_idx.size(), 3):
		var a := remap[src_idx[t]]
		var b := remap[src_idx[t + 1]]
		var c := remap[src_idx[t + 2]]
		if a >= 0 and b >= 0 and c >= 0:
			idx.append_array([a, b, c])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_INDEX] = idx
	var per_vertex := {Mesh.ARRAY_VERTEX: 1, Mesh.ARRAY_NORMAL: 1, Mesh.ARRAY_TANGENT: 4, Mesh.ARRAY_TEX_UV: 1, Mesh.ARRAY_BONES: per, Mesh.ARRAY_WEIGHTS: per}
	for ch: int in per_vertex:
		var src: Variant = arrays[ch]
		if src == null:
			continue
		var n: int = per_vertex[ch]
		var dst: Variant = src.duplicate()
		dst.resize(kept.size() * n)
		for i in kept.size():
			for k in n:
				dst[i * n + k] = src[kept[i] * n + k]
		out[ch] = dst
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, material, "Head", flags)
	importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


## One shared clip library per body: both in-place Universal Animation
## Libraries, with the pelvis motion rescaled to this body's leg length.
static func _library(pelvis_ratio: float) -> AnimationLibrary:
	var one_shot: Array = anim_config().get("one_shot", [])
	var lib := AnimationLibrary.new()
	for path: String in anim_config().get("libraries", []):
		if not ResourceLoader.exists(path):
			push_warning("HumanModel: animation library missing: %s" % path)
			continue
		var inst := (load(path) as PackedScene).instantiate()
		var src := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if src:
			for clip_name: StringName in src.get_animation_list():
				if lib.has_animation(clip_name) or clip_name == &"A_TPose" or clip_name == &"RESET":
					continue
				var a := src.get_animation(clip_name).duplicate(true) as Animation
				a.loop_mode = Animation.LOOP_NONE if one_shot.has(str(clip_name)) else Animation.LOOP_LINEAR
				for t in a.get_track_count():
					if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
						for k in a.track_get_key_count(t):
							a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * pelvis_ratio)
				lib.add_animation(clip_name, a)
		inst.free()
	return lib


static func _register_hair_sheet(sheet: int, src: StandardMaterial3D) -> void:
	if _hair_materials.has(sheet) or src == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/human_hair.gdshader")
	mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	mat.set_shader_parameter("normal_tex", src.normal_texture)
	_hair_materials[sheet] = mat


static func _hair_material(sheet: int) -> Material:
	if not _hair_materials.has(sheet):
		_body("male" if sheet == 1 else "female")
	return _hair_materials.get(sheet, null)


static func _hair(hair_name: String) -> Dictionary:
	if _hair_meshes.has(hair_name):
		return _hair_meshes[hair_name]
	var path := ROOT + "hair/%s.glb" % hair_name
	var out := {}
	if ResourceLoader.exists(path):
		var inst := (load(path) as PackedScene).instantiate()
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var mi := found[0] as MeshInstance3D
			out = {"mesh": mi.mesh, "skin": mi.skin}
		inst.free()
	_hair_meshes[hair_name] = out
	return out


## Copies the body mesh and stores smooth body coordinates per vertex for the
## clothing shader (see shaders/human_body.gdshader):
##   r = position along the arm (0 shoulder, 0.5 elbow, 0.85 wrist, 1 fingertip;
##       0 for anything that isn't arm), g = rest height / body height,
##   b = distance from the center line, a = front (1) or back (0).
## The source rig rests in a T-pose, so arm position is measured along X.
static func _bake_regions(mi: MeshInstance3D, skel: Skeleton3D, height: float) -> Mesh:
	var src := mi.mesh
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones.is_empty():
		return src
	var per := bones.size() / verts.size()
	# Which skin binds belong to the arms.
	var arm_bind := PackedByteArray()
	var skin := mi.skin
	var bind_count := skin.get_bind_count() if skin else skel.get_bone_count()
	arm_bind.resize(bind_count)
	for i in bind_count:
		var bone_name := ""
		if skin:
			bone_name = str(skin.get_bind_name(i))
			if bone_name.is_empty():
				bone_name = skel.get_bone_name(skin.get_bind_bone(i))
		else:
			bone_name = skel.get_bone_name(i)
		var is_arm := false
		for prefix: String in ["upperarm", "lowerarm", "hand", "index", "middle", "ring", "pinky", "thumb"]:
			if bone_name.begins_with(prefix):
				is_arm = true
		arm_bind[i] = 1 if is_arm else 0
	var shoulder := absf(skel.get_bone_global_rest(skel.find_bone("upperarm_l")).origin.x)
	var elbow := absf(skel.get_bone_global_rest(skel.find_bone("lowerarm_l")).origin.x)
	var wrist := absf(skel.get_bone_global_rest(skel.find_bone("hand_l")).origin.x)
	var tip := src.get_aabb().end.x
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for v in verts.size():
		var arm_w := 0.0
		for k in per:
			var b := bones[v * per + k]
			if b < arm_bind.size() and arm_bind[b] == 1:
				arm_w += weights[v * per + k]
		var p := verts[v]
		var ax := absf(p.x)
		var arm_t := 0.0
		if arm_w > 0.5:
			if ax < elbow:
				arm_t = 0.5 * inverse_lerp(shoulder, elbow, ax)
			elif ax < wrist:
				arm_t = lerpf(0.5, 0.85, inverse_lerp(elbow, wrist, ax))
			else:
				arm_t = lerpf(0.85, 1.0, inverse_lerp(wrist, tip, ax))
			arm_t = clampf(arm_t, 0.0, 1.0)
		colors[v] = Color(arm_t, clampf(p.y / height, 0.0, 1.0), clampf(ax / 0.5, 0.0, 1.0), 1.0 if p.z > 0.0 else 0.0)
	arrays[Mesh.ARRAY_COLOR] = colors
	# Extra custom channels from the source file aren't used and would need
	# their own format flags.
	for ch in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[ch] = null
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", flags)
	importer.generate_lods(25.0, 60.0, [])
	var out := importer.get_mesh()
	if out == null or out.get_surface_count() == 0:
		var plain := ArrayMesh.new()
		plain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		return plain
	return out
