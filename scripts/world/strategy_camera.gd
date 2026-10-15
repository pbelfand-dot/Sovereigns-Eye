class_name StrategyCamera
extends Node3D
## The camera, in two modes.
##
## "follow" (walking as the heir): a close, elevated view that follows the
## heir. Drag with any mouse button (or the right stick, or a touch drag)
## to orbit and tilt; wheel / pinch / R,F / up and down arrows zoom; left
## and right arrows orbit.
##
## "strategy" (the map table): overhead view with smooth pan, zoom and
## rotation.
## Mouse:     wheel = zoom (toward cursor) | left-drag or right-drag = pan |
##            middle-drag or Option/Alt + left-drag = rotate
## Trackpad:  pinch = zoom | two-finger scroll = pan (macOS)
## Keyboard:  WASD / arrows / left stick = pan | Q/E / right stick = rotate |
##            R/F or +/- = zoom | Shift = faster
##
## A plain left click (no drag) emits `clicked` so the world can select NPCs;
## a plain right click emits `right_clicked` (click-to-move).

signal clicked(screen_position: Vector2)
signal right_clicked(screen_position: Vector2)

@export var min_distance := 9.0
@export var max_distance := 150.0
@export var bounds_radius := 120.0
@export var keyboard_pan_speed := 0.9  # fraction of view distance per second
@export var rotate_speed := 1.8
@export var smoothing := 10.0
@export var edge_scroll := false

var camera: Camera3D
## Node the camera tracks (e.g. a selected NPC). Panning cancels following.
var follow_target: Node3D

## "follow" (embodied, around the heir) or "strategy" (the map table).
var mode := "strategy"
## (focus, camera) -> fraction of the way at which something blocks the
## view (1.0 = clear). Set by the world; used while following the heir.
var obstruction: Callable
var _lift := 0.0
## Shifts the picture so the people stand higher on screen (above a
## conversation panel); meters, negative = people higher.
var _view_shift := 0.0
var _target_view_shift := 0.0
## Two fingers are pinching (TouchControls): a drag isn't an orbit then.
var pinching := false
var _pitch_bias := 0.0
var _target_pitch_bias := 0.0
var _saved_distance := -1.0

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_distance := 70.0
var _yaw := 0.0
var _distance := 70.0

var _left_down := false
var _left_press_pos := Vector2.ZERO
var _right_press_pos := Vector2.ZERO
var _right_dragged := false
var _drag_mode := ""  # "", "pan", "rotate"
var _last_mouse := Vector2.ZERO
const DRAG_THRESHOLD := 6.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.2
	camera.far = 900.0
	add_child(camera)
	_target_pos = position
	_yaw = _target_yaw
	_distance = _target_distance
	_apply_transform()
	camera.make_current()


func look_at_point(point: Vector3, distance: float = -1.0, instant: bool = false) -> void:
	_target_pos = Vector3(point.x, 0, point.z)
	if distance > 0.0:
		_target_distance = clampf(distance, min_distance, max_distance)
	if instant:
		position = _target_pos
		_distance = _target_distance
		_yaw = _target_yaw
		_apply_transform()


## Current distance from the focus point to the camera (zoom).
func view_distance() -> float:
	return _distance


func set_yaw(yaw: float, instant: bool = false) -> void:
	_target_yaw = yaw
	if instant:
		_yaw = yaw


static func cfg() -> Dictionary:
	return GameData.load_file("controls").get("camera", {})


## Follow `target` closely (walking as the heir), or go back to the map
## table's overhead view.
func set_mode(new_mode: String, target: Node3D = null) -> void:
	var c := cfg()
	mode = new_mode
	if mode == "follow":
		min_distance = float(c.get("follow_min", 5.0))
		max_distance = float(c.get("follow_max", 26.0))
		follow_target = target
		_target_distance = clampf(float(c.get("follow_start", 11.0)), min_distance, max_distance)
		if target:
			_target_pos = Vector3(target.global_position.x, 0, target.global_position.z)
	else:
		min_distance = 9.0
		max_distance = 150.0
		follow_target = null
		_target_pitch_bias = 0.0
		_view_shift = 0.0
		_target_view_shift = 0.0
		if camera:
			camera.v_offset = 0.0
		_target_distance = clampf(float(c.get("overview_distance", 62.0)), min_distance, max_distance)
	_drag_mode = ""
	_left_down = false


## Moves in close for a conversation, with the speakers framed above the
## panel (`shift`, meters); `restore_view` returns to where it was.
func close_in(distance: float, shift: float = 0.0) -> void:
	if _saved_distance < 0.0:
		_saved_distance = _target_distance
	_target_distance = clampf(distance, min_distance, max_distance)
	_target_view_shift = shift


func restore_view() -> void:
	if _saved_distance > 0.0:
		_target_distance = clampf(_saved_distance, min_distance, max_distance)
	_saved_distance = -1.0
	_target_view_shift = 0.0


## Orbit by a screen-space drag (pixels): sideways turns, up/down tilts.
func orbit(relative: Vector2) -> void:
	var c := cfg()
	_target_yaw -= relative.x * 0.008
	_target_pitch_bias = clampf(_target_pitch_bias + relative.y * 0.12,
		float(c.get("pitch_bias_min", -10.0)), float(c.get("pitch_bias_max", 22.0)))


func _pitch_for(distance: float) -> float:
	# Close up the view tilts toward the horizon; far away it looks down.
	var t := clampf(inverse_lerp(min_distance, max_distance, distance), 0.0, 1.0)
	if mode == "follow":
		var c := cfg()
		return deg_to_rad(lerpf(float(c.get("pitch_near", 24.0)), float(c.get("pitch_far", 52.0)), t) + _pitch_bias)
	return deg_to_rad(lerpf(32.0, 64.0, t))


func _forward() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3(0, 0, -1)


func _right() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3(1, 0, 0)


## The camera's facing on the ground (movement is relative to it).
func forward_flat() -> Vector3:
	return _forward()


func right_flat() -> Vector3:
	return _right()


func _process(delta: float) -> void:
	if mode == "follow":
		_process_follow(delta)
		return
	var move := Vector2(
		Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left"),
		Input.get_action_strength("cam_forward") - Input.get_action_strength("cam_back"))
	if edge_scroll and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		var margin := 8.0
		if m.x < margin: move.x -= 1
		elif m.x > size.x - margin: move.x += 1
		if m.y < margin: move.y += 1
		elif m.y > size.y - margin: move.y -= 1
	if move != Vector2.ZERO:
		follow_target = null
		var speed := keyboard_pan_speed * _distance * (2.5 if Input.is_action_pressed("cam_fast") else 1.0)
		_target_pos += (_right() * move.x + _forward() * move.y) * speed * delta
	var rot := Input.get_action_strength("cam_rotate_right") - Input.get_action_strength("cam_rotate_left")
	# The right stick turns the map table too (read directly: the arrow keys
	# behind the look actions already pan here).
	var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(stick) > 0.2:
		rot += stick
	_target_yaw += rot * rotate_speed * delta
	var zoom := Input.get_action_strength("cam_zoom_out") - Input.get_action_strength("cam_zoom_in")
	if zoom != 0.0:
		_target_distance = clampf(_target_distance * (1.0 + zoom * 1.4 * delta), min_distance, max_distance)

	if is_instance_valid(follow_target):
		var p := follow_target.global_position
		_target_pos = Vector3(p.x, 0, p.z)
	else:
		follow_target = null

	var flat := Vector2(_target_pos.x, _target_pos.z)
	if flat.length() > bounds_radius:
		flat = flat.normalized() * bounds_radius
		_target_pos = Vector3(flat.x, 0, flat.y)

	var k := 1.0 - exp(-smoothing * delta)
	position = position.lerp(_target_pos, k)
	_yaw = lerp_angle(_yaw, _target_yaw, k)
	_distance = lerpf(_distance, _target_distance, k)
	_apply_transform()


func _process_follow(delta: float) -> void:
	var c := cfg()
	var turn := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	_target_yaw -= turn * float(c.get("orbit_speed", 2.2)) * delta
	var zoom := Input.get_action_strength("look_down") - Input.get_action_strength("look_up") \
		+ Input.get_action_strength("cam_zoom_out") - Input.get_action_strength("cam_zoom_in")
	if zoom != 0.0:
		_target_distance = clampf(_target_distance * (1.0 + clampf(zoom, -1.0, 1.0) * 1.4 * delta), min_distance, max_distance)
	if is_instance_valid(follow_target):
		var p := follow_target.global_position
		_target_pos = Vector3(p.x, 0, p.z)
	var k := 1.0 - exp(-smoothing * 1.2 * delta)
	position = position.lerp(_target_pos, k)
	_yaw = lerp_angle(_yaw, _target_yaw, k)
	_distance = lerpf(_distance, _target_distance, k)
	_pitch_bias = lerpf(_pitch_bias, _target_pitch_bias, k)
	_view_shift = lerpf(_view_shift, _target_view_shift, k)
	camera.v_offset = _view_shift
	_apply_transform(delta)


func _apply_transform(delta: float = 0.0) -> void:
	if camera == null:
		return
	var pitch := _pitch_for(_distance)
	var ground_y := TerrainHeight.height_at(position.x, position.z)
	var focus := Vector3(position.x, ground_y + 1.0, position.z)
	if mode == "follow" and obstruction.is_valid():
		# Rise quickly over a roof, settle back slowly once it's behind you.
		var lift := _clear_lift(focus, pitch)
		var rate := 14.0 if lift > _lift else 2.5
		var k := 1.0 if delta <= 0.0 else 1.0 - exp(-rate * delta)
		_lift = lerpf(_lift, lift, k)
		pitch += _lift
	var offset := Basis(Vector3.UP, _yaw) * Vector3(0, sin(pitch), cos(pitch)) * _distance
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)


## Walking as the heir, buildings mustn't hide them: the camera tilts up
## over the roof in the way, up to a limit; whatever still stands between
## is faded by the world (`VillageWorld._update_fades`).
## Returns the extra pitch (radians).
func _clear_lift(focus: Vector3, pitch: float) -> float:
	var top := deg_to_rad(float(cfg().get("lift_max", 66.0)))
	var extra := 0.0
	while pitch + extra <= top:
		var p := pitch + extra
		var cam := focus + Basis(Vector3.UP, _yaw) * Vector3(0, sin(p), cos(p)) * _distance
		if float(obstruction.call(focus, cam)) >= 1.0:
			return extra
		extra += deg_to_rad(6.0)
	return maxf(top - pitch, 0.0)


## The point the camera looks at (just above the ground under the rig).
func focus_point() -> Vector3:
	return Vector3(position.x, TerrainHeight.height_at(position.x, position.z) + 1.0, position.z)


## Where a screen point hits the ground plane (y = 0), or null.
func ground_point(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


## Zoom in (factor < 1) or out (> 1), e.g. from a touch pinch.
func zoom_by(factor: float) -> void:
	_zoom_by(factor)


func _zoom_by(factor: float, screen_pos: Variant = null) -> void:
	var old := _target_distance
	_target_distance = clampf(_target_distance * factor, min_distance, max_distance)
	# Zooming in pulls the view toward what is under the cursor.
	if screen_pos != null and _target_distance < old and mode != "follow":
		var g: Variant = ground_point(screen_pos)
		if g != null:
			var pull := 1.0 - _target_distance / old
			_target_pos += (Vector3(g.x, 0, g.z) - _target_pos) * pull
			follow_target = null


func _unhandled_input(event: InputEvent) -> void:
	if mode == "follow":
		_follow_input(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_by(0.88 if mb.factor <= 0.0 else pow(0.88, mb.factor), mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_by(1.13 if mb.factor <= 0.0 else pow(1.13, mb.factor))
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_down = true
					_left_press_pos = mb.position
					_last_mouse = mb.position
					_drag_mode = ""
				else:
					if _left_down and _drag_mode.is_empty():
						clicked.emit(mb.position)
					_left_down = false
					_drag_mode = ""
			MOUSE_BUTTON_RIGHT:
				_drag_mode = "pan" if mb.pressed else ""
				_last_mouse = mb.position
				if mb.pressed:
					_right_press_pos = mb.position
					_right_dragged = false
				elif not _right_dragged and mb.position.distance_to(_right_press_pos) <= DRAG_THRESHOLD:
					right_clicked.emit(mb.position)
			MOUSE_BUTTON_MIDDLE:
				_drag_mode = "rotate" if mb.pressed else ""
				_last_mouse = mb.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_down and _drag_mode.is_empty() and mm.position.distance_to(_left_press_pos) > DRAG_THRESHOLD:
			_drag_mode = "rotate" if mm.alt_pressed else "pan"
		if _drag_mode == "pan" and mm.position.distance_to(_right_press_pos) > DRAG_THRESHOLD:
			_right_dragged = true
		match _drag_mode:
			"pan":
				_pan_drag(_last_mouse, mm.position)
			"rotate":
				_target_yaw -= mm.relative.x * 0.008
		_last_mouse = mm.position
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_by(1.0 / maxf(mg.factor, 0.01), mg.position)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		follow_target = null
		var pan_scale := _distance * 0.012
		_target_pos += (_right() * pg.delta.x - _forward() * pg.delta.y) * pan_scale


## Walking as the heir: every drag orbits, the wheel zooms, a plain click
## selects and a plain right click is passed on (click-to-move).
func _follow_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_by(0.88 if mb.factor <= 0.0 else pow(0.88, mb.factor))
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_by(1.13 if mb.factor <= 0.0 else pow(1.13, mb.factor))
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_left_down = true
					_left_press_pos = mb.position
					_last_mouse = mb.position
					_drag_mode = ""
				else:
					if _left_down and _drag_mode.is_empty():
						if mb.button_index == MOUSE_BUTTON_LEFT:
							clicked.emit(mb.position)
						elif mb.button_index == MOUSE_BUTTON_RIGHT:
							right_clicked.emit(mb.position)
					_left_down = false
					_drag_mode = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_down and _drag_mode.is_empty() and mm.position.distance_to(_left_press_pos) > DRAG_THRESHOLD:
			_drag_mode = "orbit"
		if _drag_mode == "orbit" and not pinching:
			orbit(mm.position - _last_mouse)
		_last_mouse = mm.position
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_by(1.0 / maxf(mg.factor, 0.01))
	elif event is InputEventPanGesture:
		orbit((event as InputEventPanGesture).delta * 6.0)


func _pan_drag(from_screen: Vector2, to_screen: Vector2) -> void:
	var a: Variant = ground_point(from_screen)
	var b: Variant = ground_point(to_screen)
	if a == null or b == null:
		return
	follow_target = null
	var delta: Vector3 = a - b
	delta.y = 0
	_target_pos += delta
	position += delta
	_apply_transform()
