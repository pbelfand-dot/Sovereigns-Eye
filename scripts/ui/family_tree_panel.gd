class_name FamilyTreePanel
extends PanelContainer
## The house's family tree (Succession.tree): from its eldest known forebear
## down, each generation indented under its parents, husbands and wives
## beside them. Rulers are marked with their years; the departed are
## dimmed. Click someone living to open their card.

signal character_chosen(character_id: int)
signal close_requested

var world: VillageWorld
var _body: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(540, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := UITheme.label("Family Tree", 22, UITheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(UITheme.button("X", close_requested.emit))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 3)
	scroll.add_child(_body)


func refresh() -> void:
	if world == null or _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var st := world.state
	_body.add_child(UITheme.label(CourtSystem.house_name(st), 17, UITheme.ACCENT, true))
	_body.add_child(HSeparator.new())
	var rows := Succession.tree(st)
	if rows.is_empty():
		_body.add_child(UITheme.label("No one of the house is left.", 14, UITheme.TEXT_DIM))
		return
	for r: Dictionary in rows:
		_body.add_child(_row(r))
	_body.add_child(HSeparator.new())
	_body.add_child(_wrap("Rulers are marked with the years they ruled. The dimmed have died or left. A child often inherits a parent's gifts: look at the young of the house with the Eye.", 13, UITheme.TEXT_DIM))


func _row(r: Dictionary) -> Control:
	var box := HBoxContainer.new()
	var indent := Control.new()
	indent.custom_minimum_size.x = 22.0 * int(r["depth"])
	box.add_child(indent)
	var years := "%d-%s" % [int(r["born"]), str(r["died"]) if int(r["died"]) >= 0 else ""]
	if not bool(r["living"]) and int(r["died"]) < 0:
		years = "b. %d, left" % int(r["born"])
	elif bool(r["living"]):
		years = "b. %d" % int(r["born"])
	var text := "%s (%s)" % [r["name"], years]
	var ruled: Array = r["ruled"]
	if not ruled.is_empty():
		text += "  -  ruled %d-%s" % [int(ruled[0]), str(ruled[1]) if int(ruled[1]) >= 0 else "now"]
	var tags: Array[String] = []
	if r["player"]:
		tags.append("you")
	if r["heir"]:
		tags.append("your heir")
	if r["regent"]:
		tags.append("regent")
	if not tags.is_empty():
		text += "  [%s]" % ", ".join(tags)
	var spouses: Array = r["spouses"]
	if not spouses.is_empty():
		text += "  -  m. %s" % ", ".join(spouses)
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	b.text = text
	b.tooltip_text = text
	var id := int(r["id"])
	if bool(r["living"]):
		b.pressed.connect(func() -> void: character_chosen.emit(id))
		b.add_theme_color_override("font_color", UITheme.ACCENT if not ruled.is_empty() or r["player"] else UITheme.TEXT)
	else:
		b.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		b.add_theme_color_override("font_disabled_color", UITheme.TEXT_DIM)
		b.disabled = true
	box.add_child(b)
	return box


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	return l
