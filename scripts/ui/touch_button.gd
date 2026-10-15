class_name TouchButton
extends Control
## A big round on-screen button that any finger can press, even while
## another finger holds the movement stick.

signal pressed

var text := "":
	set(v):
		text = v
		queue_redraw()
var _down := -2


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_down = -2
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _inside(t.position):
			_down = t.index
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _down:
			_down = -2
			queue_redraw()
			if _inside(t.position):
				pressed.emit()
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_down = -1
		elif _down == -1:
			_down = -2
			pressed.emit()
		queue_redraw()
		accept_event()


func _inside(p: Vector2) -> bool:
	var r := get_global_rect()
	return p.distance_to(r.get_center()) <= minf(r.size.x, r.size.y) * 0.5


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var down := _down != -2
	draw_circle(c, r, Color(0.16, 0.11, 0.07, 0.82) if not down else Color(0.42, 0.31, 0.15, 0.9))
	draw_arc(c, r - 2.0, 0.0, TAU, 48, Color(0.91, 0.75, 0.38, 0.95), 3.0, true)
	var font := UITheme.heading_font()
	var fs := int(r * 0.42)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f4e2b8"))
