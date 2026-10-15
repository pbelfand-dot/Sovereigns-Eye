class_name TouchControls
extends Control
## On-screen controls for touch screens: a movement stick on the left, and
## big contextual buttons on the right (the Sovereign's Eye, Talk, the map
## table). Dragging anywhere else turns the camera; two fingers pinch to
## zoom.
##
## Every finger is tracked by its index, so you can walk and press a button
## at the same time.

var world: VillageWorld

var _stick: TouchStick
var _eye: TouchButton
var _talk: TouchButton
var _map: TouchButton
## Touch index -> position, for fingers on open ground.
var _fingers: Dictionary = {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_stick = TouchStick.new()
	_stick.anchor_top = 1.0
	_stick.anchor_bottom = 1.0
	_stick.offset_left = 28
	_stick.offset_top = -268
	_stick.offset_right = 268
	_stick.offset_bottom = -28
	add_child(_stick)
	_eye = _button("Eye", Vector2(-150, -170), 116.0, func() -> void: _press("sovereign_eye"))
	_talk = _button("Talk", Vector2(-280, -120), 100.0, func() -> void: _press("interact"))
	_map = _button("Map", Vector2(-120, -300), 76.0, func() -> void:
		if world:
			world.toggle_overview())


func _button(text: String, offset: Vector2, diameter: float, action: Callable) -> TouchButton:
	var b := TouchButton.new()
	b.text = text
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = offset.x
	b.offset_top = offset.y
	b.offset_right = offset.x + diameter
	b.offset_bottom = offset.y + diameter
	b.pressed.connect(action)
	add_child(b)
	return b


## Fires an action as if its key were pressed (the world handles the rest).
func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _process(_delta: float) -> void:
	visible = GameSettings.touch_controls() and world != null and not world.is_revealing()
	if world == null:
		return
	if world.heir_ctl:
		world.heir_ctl.touch_move = _stick.value if visible and world.mode == "walk" else Vector2.ZERO
	var walking := world.mode == "walk"
	_stick.visible = walking and world.talking_to < 0
	_eye.visible = walking and (world.focus != null or world.talking_to >= 0)
	_talk.visible = walking and world.talking_to < 0 and world.focus != null and world.talk_check(world.focus.character.id)["ok"]
	_map.text = "Walk" if not walking else "Map"


## Fingers on open ground: one turns the camera (the first finger does so
## through the camera's own touch-as-mouse handling), two pinch to zoom.
func _input(event: InputEvent) -> void:
	if not visible or world == null:
		_fingers.clear()
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _over_controls(t.position):
			_fingers[t.index] = t.position
		elif not t.pressed:
			_fingers.erase(t.index)
		world.camera_rig.pinching = _fingers.size() >= 2
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _fingers.has(d.index):
			return
		if _fingers.size() >= 2:
			var ids := _fingers.keys()
			var other: Vector2 = _fingers[ids[0] if ids[0] != d.index else ids[1]]
			var before := other.distance_to(_fingers[d.index])
			var after := other.distance_to(d.position)
			if before > 1.0 and after > 1.0:
				world.camera_rig.zoom_by(before / after)
		elif d.index != 0 and world.mode == "walk":
			world.camera_rig.orbit(d.relative)
		_fingers[d.index] = d.position


func _over_controls(p: Vector2) -> bool:
	for c: Control in [_stick, _eye, _talk, _map]:
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return false
