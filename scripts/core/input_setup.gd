class_name InputSetup
extends RefCounted
## Registers the game's input actions at startup.
##
## Defined in code (rather than in project.godot) so the bindings live next to
## each other and are easy to read. A rebinding menu can later overwrite them.

const BINDINGS := {
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


static func register() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for keycode: int in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
