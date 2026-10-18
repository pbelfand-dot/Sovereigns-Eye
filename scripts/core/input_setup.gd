class_name InputSetup
extends RefCounted
## Registers the game's input actions at startup.
##
## Defined in code (rather than in project.godot) so the bindings live next to
## each other and are easy to read. The player may change the keyboard keys
## (ControlsSettings): their changes are kept in user://settings.cfg as
## "keys/<action>" and laid over these defaults. Controller buttons are fixed.
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
	"cam_zoom_in": [KEY_R, KEY_EQUAL, KEY_KP_ADD],
	"cam_zoom_out": [KEY_F, KEY_MINUS, KEY_KP_SUBTRACT],
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

## The keys the player may change, by where they work: [id, heading,
## [[action, name], ...]]. A key can do one thing in each place: on foot and
## on the map table the same key may mean different things (Q is the Eye on
## foot and turns the map), but "anywhere" keys work in both.
const GROUPS := [
	["foot", "On foot", [
		["move_forward", "Walk forward"], ["move_back", "Walk back"],
		["move_left", "Walk left"], ["move_right", "Walk right"], ["run", "Run"],
		["interact", "Talk"], ["sovereign_eye", "Sovereign's Eye"],
		["look_left", "Turn the camera left"], ["look_right", "Turn the camera right"],
		["look_up", "Camera closer"], ["look_down", "Camera farther"],
	]],
	["map", "On the map table", [
		["cam_forward", "Pan forward"], ["cam_back", "Pan back"],
		["cam_left", "Pan left"], ["cam_right", "Pan right"], ["cam_fast", "Pan faster"],
		["cam_rotate_left", "Turn the map left"], ["cam_rotate_right", "Turn the map right"],
		["turn_building", "Turn a building"],
	]],
	["any", "Anywhere", [
		["toggle_overview", "Map table / walk"], ["cam_zoom_in", "Zoom in"], ["cam_zoom_out", "Zoom out"],
		["focus_selected", "Follow who's selected"], ["toggle_pause", "Pause"],
		["speed_1", "Speed 1x"], ["speed_2", "Speed 2x"], ["speed_3", "Speed 4x"], ["speed_4", "Speed 8x"],
		["toggle_build", "Build"], ["toggle_court", "Court"], ["toggle_ledger", "Ledger"],
		["toggle_help", "Help"], ["quicksave", "Quicksave"], ["quickload", "Quickload"],
	]],
]
## Keys that can't be given to anything else (Esc closes menus and cancels).
const RESERVED := [KEY_ESCAPE]


static func register() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		InputMap.action_set_deadzone(action, DEADZONE)
		InputMap.action_erase_events(action)
		for keycode: int in keys(action):
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode as Key
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
					JOY_BUTTON_DPAD_DOWN: return "D-pad down"
					JOY_BUTTON_DPAD_LEFT: return "D-pad left"
					JOY_BUTTON_DPAD_RIGHT: return "D-pad right"
		return ""
	var k := keys(action)
	return key_label(k[0]) if not k.is_empty() else ""


# --- The player's keys ---------------------------------------------------------------

## The keys (physical keycodes) bound to `action` now: the player's choice
## if they made one, else the default.
static func keys(action: String) -> Array[int]:
	var out: Array[int] = []
	var chosen: Variant = GameSettings.get_value("keys/" + action)
	for k: Variant in (chosen if chosen is Array else BINDINGS.get(action, [])):
		out.append(int(k))
	return out


## Every key bound to `action`, as words: "Tab or M".
static func keys_text(action: String) -> String:
	var words: Array[String] = []
	for k in keys(action):
		words.append(key_label(k))
	return " or ".join(words)


## The four walking keys together: "WASD" (or "I/J/K/L" when they don't
## spell out so neatly).
static func move_text() -> String:
	var words: Array[String] = []
	var short := true
	for a: String in ["move_forward", "move_left", "move_back", "move_right"]:
		words.append(key_name(a, false))
		short = short and words[-1].length() == 1
	return "".join(words) if short else "/".join(words)


## The four keys that turn the camera on foot: "arrows" while they are.
static func look_text() -> String:
	var words: Array[String] = []
	var arrows := true
	for a: String in ["look_left", "look_right", "look_up", "look_down"]:
		words.append(key_name(a, false))
		arrows = arrows and keys(a) == BINDINGS[a]
	return "arrows" if arrows else "/".join(words)


## Fills "{key:action}" with the action's key, "{keys:action}" with all of
## them ("Tab or M"), "{key:move}" with the walking keys and "{key:look}"
## with the camera's.
static func fill(text: String) -> String:
	var re := RegEx.create_from_string("\\{(key|keys):([a-z_0-9]+)\\}")
	for m in re.search_all(text):
		var action := m.get_string(2)
		var words := ""
		match action:
			"move": words = move_text()
			"look": words = look_text()
			_: words = keys_text(action) if m.get_string(1) == "keys" else key_name(action, false)
		text = text.replace(m.get_string(), words)
	return text


## A key as the player's keyboard shows it (on a French keyboard the key
## where Q sits on an English one reads "A").
static func key_label(keycode: int) -> String:
	var shown := keycode
	if DisplayServer.get_name() != "headless":
		var printed := DisplayServer.keyboard_get_label_from_physical(keycode as Key)
		if printed != KEY_NONE:
			shown = printed
	match shown:
		KEY_EQUAL: return "="
		KEY_MINUS: return "-"
		KEY_KP_ADD: return "Num +"
		KEY_KP_SUBTRACT: return "Num -"
		KEY_ESCAPE: return "Esc"
	return OS.get_keycode_string(shown)


## [group id, action, name] for each key the player may change.
static func rebindable() -> Array:
	var out := []
	for g: Array in GROUPS:
		for a: Array in g[2]:
			out.append([g[0], a[0], a[1]])
	return out


static func group_of(action: String) -> String:
	for g: Array in GROUPS:
		for a: Array in g[2]:
			if a[0] == action:
				return g[0]
	return ""


static func action_name(action: String) -> String:
	for g: Array in GROUPS:
		for a: Array in g[2]:
			if a[0] == action:
				return a[1]
	return action


## Two actions can't share a key if they work in the same place.
static func _clash(a: String, b: String) -> bool:
	var ga := group_of(a)
	var gb := group_of(b)
	return ga == gb or ga == "any" or gb == "any"


## What else, working where `action` does, already has `keycode` ("" if
## nothing; `ignore` doesn't count).
static func taken_by(action: String, keycode: int, ignore: String = "") -> String:
	for other: String in BINDINGS:
		if other != action and other != ignore and not group_of(other).is_empty() \
				and _clash(action, other) and keycode in keys(other):
			return other
	return ""


## Gives `action` the key `keycode` (in place of its first key; any others,
## like the arrows that also pan, stay). If something that works in the same
## place had that key, the two swap; when the old key would clash with
## something else there, the other is left without a key instead. Returns
## {ok, reason, swapped, unbound}: `swapped` is the action that gave the key
## up ("" for none), `unbound` true when it was left with no key at all.
static func rebind(action: String, keycode: int) -> Dictionary:
	if group_of(action).is_empty():
		return {"ok": false, "reason": "That can't be changed.", "swapped": "", "unbound": false}
	if keycode == KEY_NONE or keycode in RESERVED:
		return {"ok": false, "reason": "%s is kept for menus." % key_label(keycode) if keycode != KEY_NONE else "That key can't be used.", "swapped": "", "unbound": false}
	var mine := keys(action)
	var old := mine[0] if not mine.is_empty() else KEY_NONE
	if old == keycode:
		return {"ok": true, "reason": "", "swapped": "", "unbound": false}
	var swapped := ""
	for other: String in BINDINGS:
		if other == action or not keycode in keys(other):
			continue
		var theirs := keys(other)
		if group_of(other).is_empty():
			# A key only the game uses (debug): it simply lets go.
			theirs.erase(keycode)
		elif not _clash(action, other):
			continue
		elif theirs[0] == keycode and old != KEY_NONE and not old in theirs and taken_by(other, old, action).is_empty():
			theirs[0] = old
			swapped = other
		else:
			theirs.erase(keycode)
			if theirs.is_empty():
				swapped = other
		_store(other, theirs)
	mine.erase(keycode)
	if mine.is_empty():
		mine.append(keycode)
	else:
		mine[0] = keycode
	_store(action, mine)
	register()
	return {"ok": true, "reason": "", "swapped": swapped, "unbound": not swapped.is_empty() and keys(swapped).is_empty()}


## Back to the keys the game came with.
static func reset_keys() -> void:
	for action: String in BINDINGS:
		GameSettings.erase("keys/" + action)
	register()


## Has the player changed any keys?
static func customized() -> bool:
	for action: String in BINDINGS:
		if GameSettings.get_value("keys/" + action) != null:
			return true
	return false


static func _store(action: String, k: Array[int]) -> void:
	var defaults: Array[int] = []
	defaults.assign(BINDINGS.get(action, []))
	if k == defaults:
		GameSettings.erase("keys/" + action)
	else:
		GameSettings.set_value("keys/" + action, Array(k))
