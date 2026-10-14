class_name SaveSlotDialog
extends PanelContainer
## Lists the save slots for saving or loading. Used by the main menu and the
## in-game menu.

signal slot_chosen(slot: String)
signal cancelled

var mode := "load"  # "load" or "save"
var _title: Label
var _list: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(460, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	_title = UITheme.label("", 22, UITheme.TEXT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	root.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	root.add_child(_list)
	root.add_child(HSeparator.new())
	root.add_child(UITheme.button("Back", cancelled.emit))


func open(dialog_mode: String) -> void:
	mode = dialog_mode
	_title.text = "Save Game" if mode == "save" else "Load Game"
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for slot in SaveManager.SLOTS:
		if mode == "save" and slot == "quicksave":
			continue
		var info := SaveManager.slot_info(slot)
		var b := Button.new()
		b.theme_type_variation = "RowButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 52
		if info.is_empty():
			b.text = "%s  -  empty" % SaveManager.slot_label(slot)
			b.disabled = mode == "load"
		else:
			b.text = "%s  -  %s\n%s   (saved %s)" % [SaveManager.slot_label(slot), info.get("village", "?"), info.get("date", ""), str(info.get("saved_at", "")).replace("T", " ")]
		b.pressed.connect(func() -> void: slot_chosen.emit(slot))
		_list.add_child(b)
	visible = true
