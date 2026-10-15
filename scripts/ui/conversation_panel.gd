class_name ConversationPanel
extends PanelContainer
## What a villager says when the heir comes to talk. Lines appear one after
## another (click to hurry them). Afterwards the heir may use the Sovereign's
## Eye on them, or take their leave.

signal eye_requested(character_id: int)
signal farewell

const LINE_GAP := 0.7

var character: CharacterData
var _title: Label
var _lines: VBoxContainer
var _note: Label
var _eye_button: Button
var _queue: Array[String] = []
var _next_in := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(620, 0)
	add_theme_stylebox_override("panel", UITheme.box(Color("#1c1510f4"), UITheme.GOLD, 2, 8, 14))


func _ready() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_title = UITheme.label("", 18, UITheme.ACCENT, true)
	col.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	col.add_child(_lines)
	_note = UITheme.label("", 13, UITheme.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	_eye_button = UITheme.button("Use the Sovereign's Eye", func() -> void:
		if character:
			eye_requested.emit(character.id))
	row.add_child(_eye_button)
	row.add_child(UITheme.button("Farewell", farewell.emit))


func open(c: CharacterData, result: Dictionary, appraised: bool) -> void:
	character = c
	_title.text = "%s, %s" % [c.display_name(), c.occupation_name().to_lower()]
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	_queue.clear()
	for l: String in result.get("lines", []):
		_queue.append(l)
	_next_in = 0.0
	var notes: Array[String] = []
	if not str(result.get("opinion", "")).is_empty():
		notes.append(str(result["opinion"]))
	_note.text = "  ".join(notes)
	_eye_button.text = "Look again with the Sovereign's Eye" if appraised else "Use the Sovereign's Eye"
	_eye_button.disabled = true
	visible = true


func _process(delta: float) -> void:
	if not visible or _queue.is_empty():
		return
	_next_in -= delta
	if _next_in <= 0.0:
		_show_next()


func _show_next() -> void:
	var text: String = _queue.pop_front()
	var gesture := text.begins_with("(")
	var l := UITheme.label(text, 16, UITheme.TEXT_DIM if gesture else UITheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 580
	l.modulate.a = 0.0
	_lines.add_child(l)
	create_tween().tween_property(l, "modulate:a", 1.0, 0.25)
	_next_in = LINE_GAP
	if _queue.is_empty():
		_eye_button.disabled = false


func _gui_input(event: InputEvent) -> void:
	# Click to hurry the conversation along.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		while not _queue.is_empty():
			_show_next()
