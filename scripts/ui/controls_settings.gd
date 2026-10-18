class_name ControlsSettings
extends VBoxContainer
## The keyboard keys, grouped by where they work (InputSetup.GROUPS): click
## one and press the new key, Esc cancels. A key already used for something
## in the same place swaps over. Saved in user://settings.cfg; controller
## buttons stay as they are.

signal closed

## Height of the scrolling list of keys.
var list_height := 380.0
var _rows: Dictionary = {}
var _capturing := ""
var _note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	var title := UITheme.label("Keys", 22, UITheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.button("Reset keys", reset))
	head.add_child(UITheme.button("Back", close))
	var hint := UITheme.label("Click a key, then press the new one (Esc cancels). If it's already used where it works, the two swap. Controller buttons don't change.", 13, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 380
	add_child(hint)
	_note = UITheme.label("", 14, UITheme.ACCENT)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 380
	add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(420, list_height)
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for g: Array in InputSetup.GROUPS:
		var heading := UITheme.label(str(g[1]), 17, UITheme.ACCENT, true)
		if list.get_child_count() > 0:
			heading.custom_minimum_size.y = 34
			heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		list.add_child(heading)
		for a: Array in g[2]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			list.add_child(row)
			var name_label := UITheme.label(str(a[1]), 15)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			var also := UITheme.label("", 13, UITheme.TEXT_DIM)
			row.add_child(also)
			var b := Button.new()
			b.name = str(a[0])
			b.custom_minimum_size.x = 112
			b.pressed.connect(_capture.bind(str(a[0])))
			row.add_child(b)
			_rows[a[0]] = [b, also]
	refresh()


## Shows each action's key (and any others it also answers to).
func refresh() -> void:
	for action: String in _rows:
		var k := InputSetup.keys(action)
		var b: Button = _rows[action][0]
		b.text = "Press a key..." if action == _capturing else (InputSetup.key_label(k[0]) if not k.is_empty() else "-")
		var others: Array[String] = []
		for i in range(1, k.size()):
			others.append(InputSetup.key_label(k[i]))
		(_rows[action][1] as Label).text = "also %s" % ", ".join(others) if not others.is_empty() else ""


## Waiting for the new key for `action`.
func is_capturing() -> bool:
	return not _capturing.is_empty()


func _capture(action: String) -> void:
	_capturing = action
	_note.text = "Press the new key for %s (Esc cancels)." % InputSetup.action_name(action)
	refresh()


func cancel() -> void:
	_capturing = ""
	_note.text = ""
	refresh()


func close() -> void:
	cancel()
	closed.emit()


func reset() -> void:
	cancel()
	InputSetup.reset_keys()
	_note.text = "Every key is back as it was."
	refresh()
	Game.keys_changed.emit()


## Gives `action` the key `keycode` and says what happened.
func assign(action: String, keycode: int) -> Dictionary:
	_capturing = ""
	var result := InputSetup.rebind(action, keycode)
	var what := InputSetup.action_name(action)
	if not result["ok"]:
		_note.text = str(result["reason"])
		Audio.play("ui_error")
	elif bool(result["unbound"]):
		var other := str(result["swapped"])
		_note.text = "%s is now %s. %s has no key now: give it one." % [what, InputSetup.key_label(keycode), InputSetup.action_name(other)]
		Audio.play("ui_select")
	elif not str(result["swapped"]).is_empty():
		var other := str(result["swapped"])
		_note.text = "%s is now %s, and %s takes %s." % [what, InputSetup.key_label(keycode), InputSetup.action_name(other), InputSetup.key_name(other, false)]
		Audio.play("ui_select")
	else:
		_note.text = "%s is now %s." % [what, InputSetup.key_label(keycode)]
		Audio.play("ui_select")
	refresh()
	Game.keys_changed.emit()
	return result


func _input(event: InputEvent) -> void:
	if _capturing.is_empty() or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null:
		# A controller's back button lets go too (its buttons can't be bound here).
		if event.is_action_pressed("menu"):
			get_viewport().set_input_as_handled()
			cancel()
		return
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_ESCAPE:
		cancel()
		return
	assign(_capturing, code)
