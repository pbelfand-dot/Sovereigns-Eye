class_name CourtPanel
extends PanelContainer
## Your house at a glance: treasury, renown, offices, every retainer and what
## they are training, and the house chronicle. Click a name to open their card.

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
	var title := UITheme.label("Your Court", 22, UITheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(UITheme.button("X", close_requested.emit))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	scroll.add_child(_body)


func refresh() -> void:
	if world == null or _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var st := world.state
	var h := st.house
	if h == null:
		return
	var player := st.player()

	_heading(CourtSystem.house_name(st))
	if player:
		_body.add_child(_person_button(player, "Heir: %s (you), %d" % [player.full_name(), player.age]))
	var income := CourtSystem.daily_income(st)
	var wages := CourtSystem.daily_wages(st)
	_body.add_child(UITheme.label("Gold %d   (income %d, wages %d: %+d per day)" % [h.gold, income, wages, income - wages], 15, UITheme.ACCENT))
	if h.in_debt:
		_body.add_child(_wrap("Your coffers are empty and wages go unpaid. Loyalty is falling every day.", 14, UITheme.BAD))
	_body.add_child(UITheme.label("Renown %d   -   Household %d / %d (more renown, more retainers)" % [h.renown, CourtSystem.retainer_count(st), CourtSystem.retainer_cap(st)], 15))

	_heading("Offices")
	for o: Dictionary in CourtSystem.offices():
		var oid := str(o["id"])
		var holder := st.get_character(h.holder_of(oid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := UITheme.label(str(o["name"]), 15, UITheme.ACCENT)
		name_l.custom_minimum_size.x = 120
		name_l.tooltip_text = str(o.get("description", ""))
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_l)
		if holder:
			var a := str(o.get("primary", ""))
			var b := _person_button(holder, "%s  -  %s now %d (%s)" % [holder.display_name(), CourtSystem.attr_name(a), holder.get_current(a), Appraisal.rank_id(holder.get_current(a))])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
		else:
			var v := UITheme.label("Vacant - appoint a retainer from their card", 14, UITheme.TEXT_DIM)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(v)
		_body.add_child(row)
		_body.add_child(_wrap("Effect: " + _office_effect(st, o, holder), 13, UITheme.TEXT_DIM))

	_heading("Household")
	var retainers := st.retainers()
	if retainers.is_empty():
		_body.add_child(_wrap("No one has sworn to you yet. Appraise villagers, find hidden talent, then open their card's Court tab and offer them a place.", 14, UITheme.TEXT_DIM))
	retainers.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.joined_day < b.joined_day)
	for c in retainers:
		var focus := CourtSystem.focus_of(c)
		var cur := c.get_current(focus)
		var pot := c.get_potential(focus)
		var pot_text := "%d (%s potential)" % [pot, Appraisal.rank_id(pot)] if c.appraised else "? (not seen with the Eye)"
		var text := "%s, %d  -  %s  -  %s %d/%s  -  loyalty %d" % [
			c.display_name(), c.age, CourtSystem.role_name(st, c), CourtSystem.attr_name(focus), cur, pot_text, roundi(c.loyalty)]
		var b := _person_button(c, text)
		if c.loyalty < float(CourtSystem.section("loyalty").get("warning_below", 30)):
			b.add_theme_color_override("font_color", UITheme.BAD)
		_body.add_child(b)

	_heading("Chronicle")
	var shown := 0
	for i in range(h.chronicle.size() - 1, -1, -1):
		var e: Dictionary = h.chronicle[i]
		var date := Calendar.format_date(int(e["day"]) * Calendar.MINUTES_PER_DAY)
		_body.add_child(_wrap("%s  -  %s" % [date, e["text"]], 13, _chronicle_color(str(e["kind"]))))
		shown += 1
		if shown >= 12:
			break


func _office_effect(st: WorldState, o: Dictionary, holder: CharacterData) -> String:
	match str(o.get("effect", "")):
		"income":
			if holder:
				return "Income +%d%% from their Administration." % roundi(holder.get_current("administration") / float(o.get("effect_divisor", 200.0)) * 100.0)
			return "Raises income with their Administration."
		"renown":
			if holder:
				return "Renown +%.1f per day from their Politics; helps recruitment." % CourtSystem.daily_renown(st)
			return "Earns renown with their Politics; helps recruitment."
		"mentor":
			var names: Array[String] = []
			for a: String in o.get("mentors", []):
				names.append(CourtSystem.attr_name(a))
			return "Mentors the household in %s (faster training for those behind them)." % ", ".join(names)
		"construction":
			if holder:
				return "Building works go %d%% faster from their Administration." % roundi((TerritorySystem.speed_factor(st) - 1.0) * 100.0)
			return "Speeds every building site with their Administration."
	return str(o.get("description", ""))


func _heading(text: String) -> void:
	_body.add_child(UITheme.label(text, 17, UITheme.ACCENT, true))
	_body.add_child(HSeparator.new())


func _person_button(c: CharacterData, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 14)
	b.text = text
	b.tooltip_text = "Open %s's card" % c.first_name
	b.pressed.connect(func() -> void: character_chosen.emit(c.id))
	return b


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	return l


static func _chronicle_color(kind: String) -> Color:
	match kind:
		"join", "office", "knight":
			return UITheme.GOOD
		"rank":
			return UITheme.ACCENT
		"leave", "bad", "refusal":
			return UITheme.BAD
	return UITheme.TEXT_DIM
