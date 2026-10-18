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
var _crest: Node3D
var _is_player := false
var _crest_on := true
## Moved directly by the player (HeirController) instead of along paths.
var driven := false
var _drive_speed := 0.0
var _last_drive_speed := 0.0
## Animation level of detail: 1 = every frame; far from the camera the
## skeleton is updated every `anim_lod` frames (movement stays smooth).
var anim_lod := 1
var _anim_wait := 0.0
var _anim_count := 0
var _anim_last := ""
var focused := false
## Hides the ring and name over them (while the Eye's reveal shows them).
var quiet := false
## A remark said aloud over their head (Barks), and how long it has left.
var _speech: Label3D
var _speech_left := 0.0


func setup(c: CharacterData) -> void:
	character = c
	name = "NPC_%d" % c.id
	model = HumanModel.for_character(c)
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


## Rebuilds the body after a change of job (new clothes and tools).
func refresh_model() -> void:
	var old := model
	model = HumanModel.for_character(character)
	add_child(model)
	if old:
		remove_child(old)
		old.queue_free()


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
	_label.position.y = model.head_height() + 0.55 * model.body_height + 0.15
	_label.visible = false
	add_child(_label)


## A small gold crest floating over the player's own character.
func set_player_marker(on: bool) -> void:
	_is_player = on
	if on and _crest == null:
		# A gold pointer over your own character. It is billboarded and
		# fixed-size, so it stays the same few pixels at any zoom, and it shows
		# through roofs so you can always find yourself.
		_crest = Node3D.new()
		_crest.name = "PlayerCrest"
		_crest.position.y = model.head_height() + 0.2 * model.body_height
		add_child(_crest)
		_crest.add_child(_marker_triangle(0.046, 0.04, Color("#3a2410"), 0))
		_crest.add_child(_marker_triangle(0.034, 0.029, Color("#f4c84e"), 1))
	if _crest:
		_crest.visible = on and _crest_on and not _label.visible


## The crest helps find yourself from above; on foot the camera already does.
func show_crest(on: bool) -> void:
	_crest_on = on
	refresh_markers()


## Downward-pointing triangle for the player crest (screen-space units).
static func _marker_triangle(width: float, height: float, color: Color, priority: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := 0.006
	st.add_vertex(Vector3(-width * 0.5, lift + height, 0))
	st.add_vertex(Vector3(width * 0.5, lift + height, 0))
	st.add_vertex(Vector3(0, lift, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.fixed_size = true
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.render_priority = priority
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func refresh_markers() -> void:
	_ring.visible = (hovered or selected or focused) and visible and not quiet
	if selected:
		_ring.material_override = Mats.emissive(Color("#f0c24a"), 1.6)
	elif focused:
		_ring.material_override = Mats.emissive(Color("#bcd6f2"), 1.1)
	else:
		_ring.material_override = Mats.emissive(Color("#f4ead2"), 0.8)
	_label.visible = (hovered or selected or focused) and not quiet
	if _speech:
		# Above the name when it shows.
		_speech.offset.y = 44.0 if _label.visible else 0.0
	if _crest:
		# The hover label already says "Heir (You)"; don't stack the crest on it.
		_crest.visible = _is_player and _crest_on and not _label.visible
	if _label.visible:
		var role := character.occupation_name()
		if _is_player:
			role = "Heir (You)"
		elif character.retainer or not character.office.is_empty():
			role = CourtSystem.office_name(character.office) if not character.office.is_empty() else ("Page" if character.age < 16 else "Retainer")
		_label.text = "%s\n%s" % [character.display_name(), role]


func set_hovered(value: bool) -> void:
	hovered = value
	refresh_markers()


func set_selected(value: bool) -> void:
	selected = value
	refresh_markers()


## The person the heir is looking at (who the Eye or a word would go to).
func set_focused(value: bool) -> void:
	if focused == value:
		return
	focused = value
	refresh_markers()


## The player moved this body by `step` this frame (HeirController). Turns
## toward the movement and picks walk or run from the speed.
func drive(step: Vector3, delta: float) -> void:
	driven = true
	var flat := Vector3(step.x, 0, step.z)
	_drive_speed = flat.length() / maxf(delta, 0.0001)
	if _drive_speed > 0.05:
		_turn_toward(flat.normalized(), delta)


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


## What the villager is doing right now: "walk", "work", "talk" or "idle".
func activity() -> String:
	return "walk" if is_moving() or (driven and _last_drive_speed > 0.15) else _anim_mode


## Hide inside a building (or come back out).
func set_inside(inside: bool) -> void:
	visible = not inside
	if inside:
		stop()
		hush()
	refresh_markers()


# --- Remarks ----------------------------------------------------------------------

## Says `text` aloud for `seconds`: the words float over their head, then fade.
func say(text: String, seconds: float) -> void:
	if _speech == null:
		_speech = Label3D.new()
		_speech.name = "Speech"
		_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_speech.no_depth_test = true
		_speech.fixed_size = true
		_speech.pixel_size = 0.0011
		_speech.font = UITheme.body_font()
		_speech.font_size = 25
		_speech.outline_size = 9
		_speech.modulate = Color("#fff7e6")
		_speech.outline_modulate = Color(0.08, 0.05, 0.03, 0.92)
		_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_speech.width = 420.0
		_speech.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_speech.position.y = _label.position.y
		add_child(_speech)
	_speech.text = "\u201c%s\u201d" % text
	_speech_left = seconds
	_speech.modulate.a = 0.0
	refresh_markers()
	_tick_speech(0.0)


func is_speaking() -> bool:
	return _speech_left > 0.0


## What they're saying now ("" when quiet).
func speech() -> String:
	return _speech.text if _speech and is_speaking() else ""


func hush() -> void:
	_speech_left = 0.0
	if _speech:
		_speech.visible = false


## Fades the remark in and out, in real time (it's there to be read, at any
## game speed).
func _tick_speech(delta: float) -> void:
	if _speech == null or (_speech_left <= 0.0 and not _speech.visible):
		return
	_speech_left -= delta
	if _speech_left <= 0.0:
		hush()
		return
	_speech.visible = not quiet
	var a := minf(_speech.modulate.a + delta * 6.0, 1.0)
	_speech.modulate.a = minf(a, _speech_left / 0.4)


func teleport(p: Vector3) -> void:
	global_position = TerrainHeight.on_ground(p)


## Called by the world every frame. `time_scale` is the game speed (0 = paused).
func tick(delta: float, time_scale: float) -> void:
	if not visible:
		return
	_tick_speech(delta)
	if driven:
		_tick_driven(delta, time_scale)
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
	model.anim_time_scale = time_scale * (_speed_factor if moving else 1.0)
	_animate("walk" if moving else _anim_mode, delta)


func _tick_driven(delta: float, time_scale: float) -> void:
	if _face_target != null and _drive_speed <= 0.05:
		var to: Vector3 = _face_target - global_position
		to.y = 0
		if to.length() > 0.05:
			_turn_toward(to.normalized(), delta)
	var walk := BASE_WALK_SPEED * 1.6
	var mode := _anim_mode
	if _drive_speed > walk * 1.35:
		mode = "run"
	elif _drive_speed > 0.15:
		mode = "walk"
	var rate := _drive_speed / walk if mode in ["walk", "run"] else 1.0
	if mode == "run":
		rate = _drive_speed / (walk * 2.0)
	if time_scale > 0.0:
		_anim_phase += delta * 9.0 * maxf(rate, 0.3)
	model.anim_time_scale = maxf(rate, 0.3) if time_scale > 0.0 else 0.0
	_animate(mode, delta)
	_last_drive_speed = _drive_speed
	_drive_speed = 0.0


## Advances the body's animation, skipping frames when far away (a change
## of animation always shows at once).
func _animate(mode: String, delta: float) -> void:
	_anim_wait += delta
	_anim_count += 1
	if anim_lod > 1 and mode == _anim_last and (_anim_count + character.id) % anim_lod != 0:
		return
	_anim_last = mode
	model.animate(mode, _anim_phase, _anim_wait)
	_anim_wait = 0.0


func _turn_toward(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-10.0 * delta))


## Copies live state back into the data object (for saving).
func sync_to_data() -> void:
	character.position = global_position
	character.facing = rotation.y
