class_name NPC
extends Node3D
## The in-world body of one character: moves along paths, animates, shows
## hover / selection markers. All identity and stats live in `character`
## (CharacterData); this node never owns game data.

const BASE_WALK_SPEED := 1.35  # meters per real second at 1x game speed

var character: CharacterData
var model: CharacterModel
var brain: NPCBrain

var _ring: MeshInstance3D
var _label: Label3D
var _path := PackedVector3Array()
var _path_index := 0
var _anim_mode := "idle"
var _anim_phase := 0.0
var _lane := 0.0
var _speed_factor := 1.0
var _face_target: Variant = null
var hovered := false
var selected := false


func setup(c: CharacterData) -> void:
	character = c
	name = "NPC_%d" % c.id
	model = CharacterModel.create(c.appearance, c.occupation(), c.gender, c.age)
	add_child(model)
	# Lane offset so people sharing a road don't walk inside each other.
	_lane = (float(c.id % 7) - 3.0) * 0.22
	_speed_factor = 1.0
	if c.age < 12:
		_speed_factor = 1.15
	elif c.age >= 65:
		_speed_factor = 0.75
	_build_markers()
	global_position = c.position
	rotation.y = c.facing
	set_inside(c.inside_building_id >= 0)


func _build_markers() -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.55
	torus.rings = 24
	_ring.mesh = torus
	_ring.position.y = 0.06
	_ring.scale = Vector3(1, 0.2, 1)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 26
	_label.outline_size = 8
	_label.modulate = Color("#fff3d6")
	_label.outline_modulate = Color(0.1, 0.07, 0.05, 0.9)
	_label.position.y = 2.25 * model.body_height + 0.15
	_label.visible = false
	add_child(_label)


func refresh_markers() -> void:
	_ring.visible = (hovered or selected) and visible
	if selected:
		_ring.material_override = Mats.emissive(Color("#f0c24a"), 1.6)
	else:
		_ring.material_override = Mats.emissive(Color("#f4ead2"), 0.8)
	_label.visible = hovered or selected
	if _label.visible:
		_label.text = "%s\n%s" % [character.full_name(), character.occupation_name()]


func set_hovered(value: bool) -> void:
	hovered = value
	refresh_markers()


func set_selected(value: bool) -> void:
	selected = value
	refresh_markers()


# --- Movement ---------------------------------------------------------------------

func walk_path(points: PackedVector3Array) -> void:
	_path = PackedVector3Array()
	for i in points.size():
		var p := points[i]
		# Offset intermediate road points sideways into this NPC's lane.
		if i > 0 and i < points.size() - 1:
			var dir := (points[i + 1] - points[i - 1])
			dir.y = 0
			if dir.length() > 0.01:
				var side := Vector3(-dir.z, 0, dir.x).normalized()
				p += side * _lane
				p.y = TerrainHeight.height_at(p.x, p.z)
		_path.append(p)
	_path_index = 1 if _path.size() > 1 else 0
	_face_target = null


func stop() -> void:
	_path = PackedVector3Array()
	_path_index = 0


func is_moving() -> bool:
	return _path_index > 0 and _path_index < _path.size()


func face_point(p: Variant) -> void:
	_face_target = p


func set_anim(mode: String) -> void:
	_anim_mode = mode


## Hide inside a building (or come back out).
func set_inside(inside: bool) -> void:
	visible = not inside
	if inside:
		stop()
	refresh_markers()


func teleport(p: Vector3) -> void:
	global_position = TerrainHeight.on_ground(p)


## Called by the world every frame. `time_scale` is the game speed (0 = paused).
func tick(delta: float, time_scale: float) -> void:
	if not visible:
		return
	var moving := false
	if time_scale > 0.0 and is_moving():
		var step := BASE_WALK_SPEED * _speed_factor * time_scale * delta
		while step > 0.0 and _path_index < _path.size():
			var target := _path[_path_index]
			var to := target - global_position
			to.y = 0
			var dist := to.length()
			if dist <= step:
				global_position = Vector3(target.x, TerrainHeight.height_at(target.x, target.z), target.z)
				step -= dist
				_path_index += 1
			else:
				var dir := to / dist
				var p := global_position + dir * step
				global_position = Vector3(p.x, TerrainHeight.height_at(p.x, p.z), p.z)
				_turn_toward(dir, delta * maxf(time_scale, 1.0))
				step = 0.0
		moving = true
	elif _face_target != null:
		var to: Vector3 = _face_target - global_position
		to.y = 0
		if to.length() > 0.05:
			_turn_toward(to.normalized(), delta)
	if time_scale > 0.0:
		_anim_phase += delta * time_scale * (9.0 if moving else 4.0) / maxf(1.0, sqrt(time_scale))
	model.animate("walk" if moving else _anim_mode, _anim_phase, delta)


func _turn_toward(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-10.0 * delta))


## Copies live state back into the data object (for saving).
func sync_to_data() -> void:
	character.position = global_position
	character.facing = rotation.y
