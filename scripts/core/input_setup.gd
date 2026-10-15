class_name InputSetup
extends RefCounted
## Registers the game's input actions at startup.
##
## Defined in code (rather than in project.godot) so the bindings live next to
## each other and are easy to read. A rebinding menu can later overwrite them.
##
## Walking as the heir: WASD / left stick move, Shift / left-stick click run,
## Q / Y the Sovereign's Eye, E / A talk, arrows / right stick camera,
## Tab or M / View the map table. On the map table WASD, arrows and the
## left stick pan the view.

const BINDINGS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"run": [KEY_SHIFT],
	"interact": [KEY_E],
	"sovereign_eye": [KEY_Q],
	"toggle_overview": [KEY_TAB, KEY_M],
	"look_left": [KEY_LEFT],
	"look_right": [KEY_RIGHT],
	"look_up": [KEY_UP],
	"look_down": [KEY_DOWN],
	"cam_forward": [KEY_W, KEY_UP],
	"cam_back": [KEY_S, KEY_DOWN],
	"cam_left": [KEY_A, KEY_LEFT],
	"cam_right": [KEY_D, KEY_RIGHT],
	"cam_rotate_left": [KEY_Q],
	"cam_rotate_right": [KEY_E],
	"cam_zoom_in": [KEY_EQUAL, KEY_KP_ADD, KEY_R],
	"cam_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT, KEY_F],
	"cam_fast": [KEY_SHIFT],
	"focus_selected": [KEY_C],
	"toggle_ledger": [KEY_L],
	"toggle_court": [KEY_K],
	"toggle_build": [KEY_B],
	"turn_building": [KEY_T],
	"toggle_help": [KEY_H],
	"toggle_pause": [KEY_SPACE],
	"speed_1": [KEY_1],
	"speed_2": [KEY_2],
	"speed_3": [KEY_3],
	"speed_4": [KEY_4],
	"quicksave": [KEY_F5],
	"quickload": [KEY_F9],
	"menu": [KEY_ESCAPE],
	"debug_reveal_all": [KEY_F2],
}

## Controller: ["axis", axis, direction] or ["button", button].
const PAD := {
	"move_forward": [["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [["axis", JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [["axis", JOY_AXIS_LEFT_X, 1.0]],
	"run": [["button", JOY_BUTTON_LEFT_STICK], ["axis", JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"interact": [["button", JOY_BUTTON_A]],
	"sovereign_eye": [["button", JOY_BUTTON_Y]],
	"toggle_overview": [["button", JOY_BUTTON_BACK]],
	"look_left": [["axis", JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [["axis", JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [["axis", JOY_AXIS_RIGHT_Y, 1.0]],
	"cam_forward": [["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"cam_back": [["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"cam_left": [["axis", JOY_AXIS_LEFT_X, -1.0]],
	"cam_right": [["axis", JOY_AXIS_LEFT_X, 1.0]],
	"cam_zoom_in": [["button", JOY_BUTTON_RIGHT_SHOULDER]],
	"cam_zoom_out": [["button", JOY_BUTTON_LEFT_SHOULDER]],
	"toggle_build": [["button", JOY_BUTTON_X]],
	"toggle_pause": [["button", JOY_BUTTON_DPAD_DOWN]],
	"toggle_court": [["button", JOY_BUTTON_DPAD_LEFT]],
	"toggle_ledger": [["button", JOY_BUTTON_DPAD_RIGHT]],
	"menu": [["button", JOY_BUTTON_START], ["button", JOY_BUTTON_B]],
}

const DEADZONE := 0.22


static func register() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		InputMap.action_set_deadzone(action, DEADZONE)
		InputMap.action_erase_events(action)
		for keycode: int in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
		for b: Array in PAD.get(action, []):
			if str(b[0]) == "axis":
				var m := InputEventJoypadMotion.new()
				m.axis = int(b[1])
				m.axis_value = float(b[2])
				InputMap.action_add_event(action, m)
			else:
				var j := InputEventJoypadButton.new()
				j.button_index = int(b[1])
				InputMap.action_add_event(action, j)


## Words for an action's key on the device in use: "Q", "Y", "E", "A"...
static func key_name(action: String, pad: bool) -> String:
	if pad:
		for b: Array in PAD.get(action, []):
			if str(b[0]) == "button":
				match int(b[1]):
					JOY_BUTTON_A: return "A"
					JOY_BUTTON_B: return "B"
					JOY_BUTTON_X: return "X"
					JOY_BUTTON_Y: return "Y"
					JOY_BUTTON_BACK: return "View"
					JOY_BUTTON_START: return "Menu"
		return ""
	var keys: Array = BINDINGS.get(action, [])
	return OS.get_keycode_string(int(keys[0])) if not keys.is_empty() else ""
