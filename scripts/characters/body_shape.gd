class_name BodyShape
extends SkeletonModifier3D
## Age and build, laid over whatever the animation is doing: an old villager
## stoops (the upper spine bends forward, the neck lifts the head back to look
## ahead), and a heavier one carries more round the belly (the lower spine
## widens and the bone above is scaled back, so chest, arms and head keep
## their size). Tuned in data/appearance.json "body_shape".

## Forward bend of the upper spine (radians).
var stoop := 0.0
## Width of the belly (1 = as modelled).
var girth := 1.0

var _spine := PackedInt32Array()
var _neck := -1
var _belly := -1
var _chest := -1


## The shape for a villager (null when there is nothing to change).
static func for_character(c: CharacterData) -> BodyShape:
	var cfg: Dictionary = GameData.appearance().get("body_shape", {})
	var from := float(cfg.get("stoop_from_age", 58))
	var full := float(cfg.get("stoop_full_age", 88))
	var stoop_deg := float(cfg.get("stoop_max_deg", 20.0)) * clampf((c.age - from) / maxf(full - from, 1.0), 0.0, 1.0)
	var build := float(c.appearance.get("build", 1.0))
	var g := 1.0 + (build - 1.0) * float(cfg.get("girth_per_build", 0.8))
	if c.age < 16:
		g = 1.0 + (g - 1.0) * 0.4  # children carry less of it
	if stoop_deg < 0.5 and absf(g - 1.0) < 0.01:
		return null
	var shape := BodyShape.new()
	shape.name = "BodyShape"
	shape.stoop = deg_to_rad(stoop_deg)
	shape.girth = g
	return shape


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for bone: String in ["spine_02", "spine_03"]:
		_spine.append(sk.find_bone(bone))
	_neck = sk.find_bone("neck_01")
	_belly = sk.find_bone("spine_01")
	_chest = sk.find_bone("spine_02")


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if stoop > 0.0:
		var share := [0.55, 0.45]
		for k in _spine.size():
			if _spine[k] >= 0:
				sk.set_bone_pose_rotation(_spine[k], sk.get_bone_pose_rotation(_spine[k]) * Quaternion(Vector3.RIGHT, stoop * share[k]))
		if _neck >= 0:
			var lift := float(GameData.appearance().get("body_shape", {}).get("neck_lift", 0.6))
			sk.set_bone_pose_rotation(_neck, sk.get_bone_pose_rotation(_neck) * Quaternion(Vector3.RIGHT, -stoop * lift))
	if girth != 1.0 and _belly >= 0 and _chest >= 0:
		sk.set_bone_pose_scale(_belly, sk.get_bone_pose_scale(_belly) * Vector3(girth, 1.0, girth))
		sk.set_bone_pose_scale(_chest, sk.get_bone_pose_scale(_chest) * Vector3(1.0 / girth, 1.0, 1.0 / girth))
