class_name GameUI
extends CanvasLayer
## All in-game interface: top bar (date, speed, buttons), character card,
## village ledger, notifications, controls help and the pause/save/load menu.

var world: VillageWorld

var _root: Control
var _village_label: Label
var _clock_label: Label
var _appraised_label: Label
var _house_label: Label
var _bar_row: HBoxContainer
var _bar_key := ""
var _speed_buttons: Array[Button] = []
var _card: CharacterCard
var _ledger: LedgerPanel
var _court: CourtPanel
var _help: PanelContainer
var _pause_overlay: Control
var _pause_menu: PanelContainer
var _slots: SaveSlotDialog
var _paused_before_menu := false


func setup(owner_world: VillageWorld) -> void:
	world = owner_world
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_build_top_bar()
	_build_card()
	_build_ledger()
	_build_court()
	_build_toasts()
	_build_help()
	_build_pause_menu()
	world.selection_changed.connect(_on_selection_changed)
	world.speed_changed.connect(_on_speed_changed)
	world.day_passed.connect(func(_d: int) -> void: refresh())
	_on_speed_changed(world.time_scale())
	var p := world.state.player()
	if p:
		Game.notify.emit("You are %s, heir of %s. Appraise villagers to find hidden talent (gold crest = you)." % [p.full_name(), CourtSystem.house_name(world.state)], UITheme.TEXT)
	else:
		Game.notify.emit("Welcome to %s. Click any villager to appraise them." % world.state.village_name, UITheme.TEXT)


# --- Top bar -------------------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 50
	var style := UITheme.box(Color("#1c1510ee"), UITheme.GOLD_DIM, 0, 0, 8)
	style.border_width_bottom = 2
	style.border_color = UITheme.GOLD
	bar.add_theme_stylebox_override("panel", style)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_bar_row = row

	_village_label = UITheme.label(world.state.village_name, 18, UITheme.ACCENT, true)
	row.add_child(_village_label)
	_clock_label = UITheme.label("", 16)
	row.add_child(_clock_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var labels := ["Pause", "1x", "2x", "4x", "8x"]
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.tooltip_text = "Space" if i == 0 else "Key %d" % i
		var index := i
		b.pressed.connect(func() -> void: _on_speed_button(index))
		row.add_child(b)
		_speed_buttons.append(b)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)

	_house_label = UITheme.label("", 15, UITheme.ACCENT)
	_house_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_house_label.tooltip_text = "Gold (change per day)  -  Renown  -  Retainers / household size"
	row.add_child(_house_label)
	_appraised_label = UITheme.label("", 15, UITheme.TEXT_DIM)
	row.add_child(_appraised_label)
	var court_button := UITheme.button("Court", toggle_court)
	court_button.tooltip_text = "Your court (K)"
	row.add_child(court_button)
	var ledger_button := UITheme.button("Ledger", toggle_ledger)
	ledger_button.tooltip_text = "Village ledger (L)"
	row.add_child(ledger_button)
	var save_button := UITheme.button("Save", func() -> void: Game.save_game("quicksave"))
	save_button.tooltip_text = "Quicksave (F5)"
	row.add_child(save_button)
	var menu_button := UITheme.button("Menu", open_pause_menu)
	menu_button.tooltip_text = "Menu (Esc)"
	row.add_child(menu_button)


func _on_speed_button(index: int) -> void:
	if index == 0:
		world.toggle_pause()
	else:
		world.set_speed(index - 1)


func _on_speed_changed(_scale: float) -> void:
	for i in _speed_buttons.size():
		var active := world.paused if i == 0 else (not world.paused and world.speed_index == i - 1)
		_speed_buttons[i].set_pressed_no_signal(active)


func _process(_delta: float) -> void:
	if world == null:
		return
	_layout_top_bar()


## Fills the top bar, dropping detail step by step (the "Appraised" count,
## then the long date, then shorter house wording) until everything fits the
## window, so the Court/Ledger/Save/Menu buttons are never pushed off screen.
func _layout_top_bar() -> void:
	var st := world.state
	var minutes := st.whole_minutes()
	var full_clock := Calendar.format_full(minutes)
	var short_clock := "%s %d, %d  %s" % [Calendar.season_name(minutes).left(3), Calendar.day_of_season(minutes), Calendar.year(minutes), Calendar.format_time(minutes)]
	var appraised := "Appraised %d/%d" % [world.appraised_count(), st.characters.size()]
	var house: Array[String] = [""]
	if st.house:
		var net := CourtSystem.daily_income(st) - CourtSystem.daily_wages(st)
		var g := st.house.gold
		var r := st.house.renown
		var n := CourtSystem.retainer_count(st)
		var cap := CourtSystem.retainer_cap(st)
		house = [
			"%d gold (%+d)   Renown %d   Household %d/%d" % [g, net, r, n, cap],
			"%d gold (%+d)  Renown %d  Retainers %d/%d" % [g, net, r, n, cap],
			"%d gold (%+d)  Renown %d  %d/%d" % [g, net, r, n, cap],
			"%dg (%+d)  R%d  %d/%d" % [g, net, r, n, cap],
		]
		_house_label.add_theme_color_override("font_color", UITheme.BAD if st.house.in_debt else UITheme.ACCENT)
	var width := _bar_row.size.x if _bar_row.size.x > 0.0 else get_viewport().get_visible_rect().size.x - 16.0
	var key := "%s|%s|%s|%d" % [full_clock, appraised, house[0], roundi(width)]
	if key == _bar_key:
		return
	_bar_key = key
	# [long date?, show "Appraised"?, house wording index]
	var plans := [[true, true, 0], [true, false, 0], [false, false, 0], [false, false, 1], [false, false, 2], [false, false, 3]]
	for plan: Array in plans:
		_clock_label.text = full_clock if plan[0] else short_clock
		# Fixed widths so the bar doesn't jiggle as the minutes tick.
		_clock_label.custom_minimum_size.x = 250.0 if plan[0] else 150.0
		_appraised_label.text = appraised
		_appraised_label.visible = plan[1]
		_house_label.text = house[mini(int(plan[2]), house.size() - 1)]
		if _bar_min_width() <= width:
			break


func _bar_min_width() -> float:
	var total := 0.0
	var count := 0
	for child in _bar_row.get_children():
		var ctl := child as Control
		if ctl == null or not ctl.visible:
			continue
		total += ctl.get_combined_minimum_size().x
		count += 1
	return total + _bar_row.get_theme_constant("separation") * maxi(count - 1, 0)


# --- Card & ledger ------------------------------------------------------------------------

func _build_card() -> void:
	_card = CharacterCard.new()
	_card.world = world
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.0
	_card.anchor_bottom = 1.0
	_card.offset_left = -CharacterCard.WIDTH - 12
	_card.offset_right = -12
	_card.offset_top = 60
	_card.offset_bottom = -12
	_card.visible = false
	_root.add_child(_card)
	_card.close_requested.connect(world.deselect)
	_card.character_link_pressed.connect(func(id: int) -> void: world.select_character(id, true))
	_card.follow_pressed.connect(world.focus_on)


func _build_ledger() -> void:
	_ledger = LedgerPanel.new()
	_ledger.world = world
	_ledger.anchor_left = 0.0
	_ledger.anchor_right = 0.0
	_ledger.anchor_top = 0.0
	_ledger.anchor_bottom = 1.0
	_ledger.offset_left = 12
	_ledger.offset_right = 12 + 540
	_ledger.offset_top = 60
	_ledger.offset_bottom = -12
	_ledger.visible = false
	_root.add_child(_ledger)
	_ledger.character_chosen.connect(func(id: int) -> void: world.select_character(id, true))
	_ledger.close_requested.connect(toggle_ledger)


func _build_court() -> void:
	_court = CourtPanel.new()
	_court.world = world
	_court.anchor_left = 0.0
	_court.anchor_right = 0.0
	_court.anchor_top = 0.0
	_court.anchor_bottom = 1.0
	_court.offset_left = 12
	_court.offset_right = 12 + 540
	_court.offset_top = 60
	_court.offset_bottom = -12
	_court.visible = false
	_root.add_child(_court)
	_court.character_chosen.connect(func(id: int) -> void: world.select_character(id, true))
	_court.close_requested.connect(toggle_court)


func toggle_ledger() -> void:
	_ledger.visible = not _ledger.visible
	if _ledger.visible:
		_help.visible = false
		_court.visible = false
		_ledger.refresh()


func toggle_court() -> void:
	_court.visible = not _court.visible
	if _court.visible:
		_help.visible = false
		_ledger.visible = false
		_court.refresh()


func _on_selection_changed(c: CharacterData) -> void:
	_card.show_character(c)
	if _ledger.visible:
		_ledger.refresh()
	if _court.visible:
		_court.refresh()


## Re-reads data into open panels (after a new day, debug reveal...).
func refresh() -> void:
	if _card.visible:
		_card.refresh()
	if _ledger.visible:
		_ledger.refresh()
	if _court.visible:
		_court.refresh()


# --- Toasts & help ------------------------------------------------------------------------

func _build_toasts() -> void:
	var toasts := ToastStack.new()
	# Shifted left of center so toasts never cover the character card.
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.offset_left = -520
	toasts.offset_right = 140
	toasts.offset_top = 62
	toasts.offset_bottom = 300
	_root.add_child(toasts)


func _build_help() -> void:
	_help = PanelContainer.new()
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_left = 12
	_help.offset_top = -12
	_help.offset_bottom = -12
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.add_theme_stylebox_override("panel", UITheme.box(Color("#1c1510d0"), UITheme.GOLD_DIM, 1, 6, 10))
	var text := UITheme.label(
		"Click a villager - appraise & open their card\n" +
		"Card > Court tab - talk, give gifts, recruit, appoint, train\n" +
		"Drag (left/right mouse) or WASD - move camera\n" +
		"Wheel / pinch / R,F - zoom    Q,E or middle-drag - rotate\n" +
		"Space - pause    1-4 - game speed    C - follow selected\n" +
		"K - your court    L - village ledger    F5 / F9 - quicksave / quickload\n" +
		"Esc - close / menu    H - hide this help", 14, UITheme.TEXT_DIM)
	_help.add_child(text)
	_root.add_child(_help)
	# Fade the help away after a while; H brings it back.
	get_tree().create_timer(45.0).timeout.connect(_auto_hide_help)


func _auto_hide_help() -> void:
	if is_instance_valid(_help):
		_help.visible = false


# --- Pause / save / load -------------------------------------------------------------------

func _build_pause_menu() -> void:
	_pause_overlay = ColorRect.new()
	(_pause_overlay as ColorRect).color = Color(0, 0, 0, 0.55)
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	_root.add_child(_pause_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)

	_pause_menu = PanelContainer.new()
	_pause_menu.custom_minimum_size = Vector2(320, 0)
	stack.add_child(_pause_menu)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_pause_menu.add_child(col)
	var title := UITheme.label("Paused", 26, UITheme.ACCENT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(HSeparator.new())
	col.add_child(UITheme.button("Resume", close_pause_menu))
	col.add_child(UITheme.button("Save Game", func() -> void: _open_slots("save")))
	col.add_child(UITheme.button("Load Game", func() -> void: _open_slots("load")))
	col.add_child(UITheme.button("Main Menu", Game.quit_to_menu))
	col.add_child(UITheme.button("Quit to Desktop", Game.quit_game))

	_slots = SaveSlotDialog.new()
	_slots.visible = false
	stack.add_child(_slots)
	_slots.cancelled.connect(_on_slots_cancelled)
	_slots.slot_chosen.connect(_on_slot_chosen)


func _on_slots_cancelled() -> void:
	_slots.visible = false
	_pause_menu.visible = true


func is_menu_open() -> bool:
	return _pause_overlay.visible


func open_pause_menu() -> void:
	if _pause_overlay.visible:
		return
	_paused_before_menu = world.paused
	world.paused = true
	world.speed_changed.emit(world.time_scale())
	_pause_overlay.visible = true
	_pause_menu.visible = true
	_slots.visible = false


func close_pause_menu() -> void:
	_pause_overlay.visible = false
	world.paused = _paused_before_menu
	world.speed_changed.emit(world.time_scale())


func _open_slots(mode: String) -> void:
	_pause_menu.visible = false
	_slots.open(mode)


func _on_slot_chosen(slot: String) -> void:
	if _slots.mode == "save":
		if Game.save_game(slot):
			_slots.open("save")
	else:
		Game.load_game(slot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if _pause_overlay.visible:
			if _slots.visible:
				_on_slots_cancelled()
			else:
				close_pause_menu()
		elif _card.visible:
			world.deselect()
		elif _ledger.visible:
			toggle_ledger()
		elif _court.visible:
			toggle_court()
		else:
			open_pause_menu()
	elif event.is_action_pressed("toggle_ledger"):
		toggle_ledger()
	elif event.is_action_pressed("toggle_court"):
		toggle_court()
	elif event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	else:
		return
	get_viewport().set_input_as_handled()
