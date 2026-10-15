class_name LedgerPanel
extends PanelContainer
## The village ledger: every resident at a glance. Talent ranks are hidden
## ("?") until you have appraised that person, which keeps discovery the
## core loop. Click a row to fly to them and open their card.

signal character_chosen(character_id: int)
signal close_requested

var world: VillageWorld
var _list: VBoxContainer
var _summary: Label
var _sort: OptionButton
var _only_appraised: CheckBox
var _only_remembered: CheckBox
var _only_talent: CheckBox
var _only_household: CheckBox


func _init() -> void:
	custom_minimum_size = Vector2(540, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := UITheme.label("Village Ledger", 22, UITheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(UITheme.button("X", close_requested.emit))
	_summary = UITheme.label("", 14, UITheme.TEXT_DIM)
	root.add_child(_summary)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	root.add_child(controls)
	controls.add_child(UITheme.label("Sort", 15, UITheme.TEXT_DIM))
	_sort = OptionButton.new()
	for item in ["Greatest talent", "Name", "Age", "Occupation", "Happiness", "Opinion of you"]:
		_sort.add_item(item)
	_sort.item_selected.connect(func(_i: int) -> void: refresh())
	controls.add_child(_sort)
	_only_appraised = CheckBox.new()
	_only_appraised.text = "Appraised only"
	_only_appraised.toggled.connect(func(_on: bool) -> void: refresh())
	controls.add_child(_only_appraised)
	_only_remembered = CheckBox.new()
	_only_remembered.text = "Remembered"
	_only_remembered.tooltip_text = "Only people you chose to remember after the Sovereign's Eye"
	_only_remembered.toggled.connect(func(_on: bool) -> void: refresh())
	controls.add_child(_only_remembered)
	_only_talent = CheckBox.new()
	_only_talent.text = "Talents (A+)"
	_only_talent.toggled.connect(func(_on: bool) -> void: refresh())
	controls.add_child(_only_talent)
	_only_household = CheckBox.new()
	_only_household.text = "Household"
	_only_household.tooltip_text = "Only your retainers"
	_only_household.toggled.connect(func(_on: bool) -> void: refresh())
	controls.add_child(_only_household)

	var header := _row_layout("Name", "Age", "Occupation", "Talent")
	for l in header.get_children():
		(l as Label).add_theme_color_override("font_color", UITheme.ACCENT)
	root.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	var hint := UITheme.label("Click anyone in the village (or here) to appraise them.", 13, UITheme.TEXT_DIM)
	root.add_child(hint)


func _row_layout(n: String, a: String, o: String, t: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var widths := [190, 40, 170, 90]
	var texts := [n, a, o, t]
	for i in 4:
		var l := UITheme.label(texts[i], 15)
		l.custom_minimum_size.x = widths[i]
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	return row


func refresh() -> void:
	if world == null or _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var people: Array[CharacterData] = []
	var exceptional_found := 0
	for c in world.state.characters:
		if c.appraised and Appraisal.is_exceptional(c):
			exceptional_found += 1
		if _only_appraised.button_pressed and not c.appraised:
			continue
		if _only_remembered.button_pressed and not c.remembered:
			continue
		if _only_talent.button_pressed and not (c.appraised and Appraisal.is_notable(c)):
			continue
		if _only_household.button_pressed and not c.retainer:
			continue
		people.append(c)
	_summary.text = "%s  -  %d residents  -  appraised %d  -  exceptional talents found: %d" % [
		world.state.village_name, world.state.characters.size(), world.appraised_count(), exceptional_found]
	match _sort.selected:
		0:
			people.sort_custom(_by_talent)
		1:
			people.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.full_name() < b.full_name())
		2:
			people.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.age > b.age)
		3:
			people.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.occupation_name() < b.occupation_name())
		4:
			people.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.happiness > b.happiness)
		5:
			people.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.player_opinion > b.player_opinion)
	for c in people:
		_list.add_child(_make_row(c))


## Appraised people by best potential first; unappraised ones after, by name.
static func _by_talent(a: CharacterData, b: CharacterData) -> bool:
	var ka := a.best_potential() if a.appraised else -1
	var kb := b.best_potential() if b.appraised else -1
	if ka != kb:
		return ka > kb
	return a.full_name() < b.full_name()


func _make_row(c: CharacterData) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.custom_minimum_size.y = 30
	b.pressed.connect(func() -> void: character_chosen.emit(c.id))
	var role := CourtSystem.role_name(world.state, c) if world.state.house else c.occupation_name()
	var row := _row_layout(("• " if c.remembered else "") + c.display_name(), str(c.age), role, "")
	if c.retainer or world.state.is_player(c) or c.remembered:
		(row.get_child(0) as Label).add_theme_color_override("font_color", UITheme.ACCENT)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	b.add_child(row)
	var talent_cell: Label = row.get_child(3)
	talent_cell.text = ""
	if c.appraised:
		var best := c.best_attribute()
		var p := c.get_potential(best)
		var badge := UITheme.rank_badge(Appraisal.rank_id(p), Appraisal.rank_color(p), 13)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var holder := HBoxContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(badge)
		var attr := UITheme.label(" " + str(GameData.attribute_def(best).get("short", "")), 13, UITheme.TEXT_DIM)
		attr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(attr)
		row.remove_child(talent_cell)
		talent_cell.queue_free()
		row.add_child(holder)
		b.tooltip_text = "%s\nBest: %s" % [c.full_name(), Appraisal.format_attribute(c, best)]
	else:
		talent_cell.text = "  ?"
		talent_cell.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		b.tooltip_text = "Not yet seen with the Sovereign's Eye" + ("" if c.met else " (talk to them first)")
	return b
