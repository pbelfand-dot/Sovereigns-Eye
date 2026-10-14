class_name StrategyCamera
extends Node3D
## Overhead strategy camera with smooth pan, zoom and rotation.
##
## Mouse:     wheel = zoom (toward cursor) | left-drag or right-drag = pan |
##            middle-drag or Option/Alt + left-drag = rotate
## Trackpad:  pinch = zoom | two-finger scroll = pan (macOS)
## Keyboard:  WASD / arrows = pan | Q/E = rotate | R/F or +/- = zoom |
##            Shift = faster
##
## A plain left click (no drag) emits `clicked` so the world can select NPCs.

signal clicked(screen_position: Vector2)

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

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_distance := 70.0
var _yaw := 0.0
var _distance := 70.0

var _left_down := false
var _left_press_pos := Vector2.ZERO
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


func set_yaw(yaw: float, instant: bool = false) -> void:
	_target_yaw = yaw
	if instant:
		_yaw = yaw


func _pitch_for(distance: float) -> float:
	# Close up the view tilts toward the horizon; far away it looks down.
	var t := inverse_lerp(min_distance, max_distance, distance)
	return deg_to_rad(lerpf(32.0, 64.0, clampf(t, 0.0, 1.0)))


func _forward() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3(0, 0, -1)


func _right() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3(1, 0, 0)


func _process(delta: float) -> void:
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


func _apply_transform() -> void:
	if camera == null:
		return
	var pitch := _pitch_for(_distance)
	var offset := Basis(Vector3.UP, _yaw) * Vector3(0, sin(pitch), cos(pitch)) * _distance
	var ground_y := TerrainHeight.height_at(position.x, position.z)
	var focus := Vector3(position.x, ground_y + 1.0, position.z)
	camera.global_position = focus + offset
	camera.look_at(focus, Vector3.UP)


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


func _zoom_by(factor: float, screen_pos: Variant = null) -> void:
	var old := _target_distance
	_target_distance = clampf(_target_distance * factor, min_distance, max_distance)
	# Zooming in pulls the view toward what is under the cursor.
	if screen_pos != null and _target_distance < old:
		var g: Variant = ground_point(screen_pos)
		if g != null:
			var pull := 1.0 - _target_distance / old
			_target_pos += (Vector3(g.x, 0, g.z) - _target_pos) * pull
			follow_target = null


func _unhandled_input(event: InputEvent) -> void:
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
			MOUSE_BUTTON_MIDDLE:
				_drag_mode = "rotate" if mb.pressed else ""
				_last_mouse = mb.position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_down and _drag_mode.is_empty() and mm.position.distance_to(_left_press_pos) > DRAG_THRESHOLD:
			_drag_mode = "rotate" if mm.alt_pressed else "pan"
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
