class_name TouchStick
extends Control
## The on-screen movement stick. Follows one finger (any finger) from its
## first touch inside the pad; `value` is x = right, y = forward, 0..1.

var value := Vector2.ZERO
var _finger := -2  # -2 none, -1 the mouse (desktop testing), else a touch index
var _center := Vector2.ZERO


func _init() -> void:
	# Stop touch-as-mouse events here so they don't also turn the camera.
	mouse_filter = Control.MOUSE_FILTER_STOP


func radius() -> float:
	return minf(size.x, size.y) * 0.5


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_release()
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _finger == -2 and get_global_rect().has_point(t.position):
			_finger = t.index
			_center = get_global_rect().get_center()
			_move_to(t.position)
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _finger:
			_release()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _finger:
			_move_to(d.position)
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# A real mouse (not a finger pretending to be one) works too.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed and _finger == -2:
			_finger = -1
			_center = get_global_rect().get_center()
			_move_to(mb.global_position)
		elif not mb.pressed and _finger == -1:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _finger == -1:
		_move_to((event as InputEventMouseMotion).global_position)
		accept_event()


func _move_to(p: Vector2) -> void:
	var d := (p - _center) / maxf(radius(), 1.0)
	d = d.limit_length(1.0)
	value = Vector2(d.x, -d.y)
	queue_redraw()


func _release() -> void:
	if _finger == -2 and value == Vector2.ZERO:
		return
	_finger = -2
	value = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := radius()
	draw_circle(c, r, Color(0.11, 0.08, 0.06, 0.45))
	draw_arc(c, r - 2.0, 0.0, TAU, 48, Color(0.79, 0.63, 0.29, 0.8), 3.0, true)
	var knob := c + Vector2(value.x, -value.y) * r * 0.62
	draw_circle(knob, r * 0.34, Color(0.91, 0.75, 0.38, 0.85))
	draw_arc(knob, r * 0.34, 0.0, TAU, 32, Color(0.24, 0.16, 0.09, 0.9), 2.0, true)
