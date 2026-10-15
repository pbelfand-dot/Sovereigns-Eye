class_name GameUI
extends CanvasLayer
## All in-game interface: top bar (date, speed, buttons), character card,
## village ledger, notifications, controls help and the pause/save/load menu.

var world: VillageWorld

var _root: Control
var _village_label: Label
var _charter_label: Label
var _clock_label: Label
var _appraised_label: Label
var _house_label: Label
var _bar_row: HBoxContainer
var _bar_key := ""
var _speed_buttons: Array[Button] = []
var _card: CharacterCard
var _ledger: LedgerPanel
var _court: CourtPanel
var _build: BuildPanel
var _building_card: BuildingCard
var _conversation: NegotiationPanel
var _prompt: PanelContainer
var _prompt_name: Label
var _prompt_keys: Label
var _map_banner: PanelContainer
var _map_button: Button
var _touch: TouchControls
## The last input came from a controller (prompts show its buttons).
var _pad := false
var _stores_row: HBoxContainer
var _stores_key := ""
var _place_hint: PanelContainer
var _place_title: Label
var _place_reason: Label
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
	_build_build_panel()
	_build_building_card()
	_build_conversation()
	_build_stores_bar()
	_build_place_hint()
	_build_prompt()
	_build_map_banner()
	_build_toasts()
	_build_help()
	_touch = TouchControls.new()
	_touch.world = world
	_root.add_child(_touch)
	_build_pause_menu()
	world.selection_changed.connect(_on_selection_changed)
	world.speed_changed.connect(_on_speed_changed)
	world.day_passed.connect(func(_d: int) -> void: refresh())
	world.territory_changed.connect(_on_territory_changed)
	world.placing_changed.connect(_on_placing_changed)
	world.building_selected.connect(_on_building_selected)
	world.conversation_started.connect(_on_conversation_started)
	world.conversation_ended.connect(func() -> void: _conversation.visible = false)
	world.mode_changed.connect(_on_mode_changed)
	_on_speed_changed(world.time_scale())
	_on_mode_changed(world.mode)
	var p := world.state.player()
	if p:
		Game.notify.emit("You are %s, heir of %s. Walk among your people (WASD). Look at someone nearby and press Q for the Sovereign's Eye; walk up and press E to talk." % [p.full_name(), CourtSystem.house_name(world.state)], UITheme.TEXT)
	else:
		Game.notify.emit("Welcome to %s." % world.state.village_name, UITheme.TEXT)


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
	_charter_label = UITheme.label("", 15, UITheme.TEXT_DIM)
	_charter_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_charter_label)
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
		b.set_meta("sfx", "ui_tick")
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
	_map_button = UITheme.button("Map", world.toggle_overview)
	_map_button.tooltip_text = "The map table: plan your lands from above (Tab or M). Press again to walk as your heir."
	row.add_child(_map_button)
	var build_button := UITheme.button("Build", toggle_build)
	build_button.tooltip_text = "Order new buildings, see the stores (B)"
	row.add_child(build_button)
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
	_conversation.visible = world.talking_to >= 0 and not world.is_revealing() and _conversation.character != null
	_update_prompt()
	_layout_top_bar()
	_update_stores_bar()
	if _place_hint.visible:
		_update_place_hint()


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
	var charter := CharterSystem.title(st) if st.territory else ""
	_charter_label.tooltip_text = "Charter: %s. Room for %d people. Build panel (B) to petition for the next." % [charter, CharterSystem.max_population(st)] if st.territory else ""
	var key := "%s|%s|%s|%s|%d" % [full_clock, appraised, house[0], charter, roundi(width)]
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
		_charter_label.text = "(%s)" % charter if not charter.is_empty() else ""
		_charter_label.visible = plan[0] and not charter.is_empty()
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
	_card.offset_top = 96
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
	_ledger.offset_top = 96
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
	_court.offset_top = 96
	_court.offset_bottom = -12
	_court.visible = false
	_root.add_child(_court)
	_court.character_chosen.connect(func(id: int) -> void: world.select_character(id, true))
	_court.close_requested.connect(toggle_court)


func toggle_ledger() -> void:
	_ledger.visible = not _ledger.visible
	Audio.play("panel_open" if _ledger.visible else "panel_close")
	if _ledger.visible:
		_help.visible = false
		_court.visible = false
		_build.visible = false
		_ledger.refresh()


func toggle_court() -> void:
	_court.visible = not _court.visible
	Audio.play("panel_open" if _court.visible else "panel_close")
	if _court.visible:
		_help.visible = false
		_ledger.visible = false
		_build.visible = false
		_court.refresh()


func toggle_build() -> void:
	_build.visible = not _build.visible
	Audio.play("panel_open" if _build.visible else "panel_close")
	if _build.visible:
		world.cancel_placing()
		_help.visible = false
		_ledger.visible = false
		_court.visible = false
		_build.refresh()


func is_build_open() -> bool:
	return _build != null and _build.visible


func is_court_open() -> bool:
	return _court != null and _court.visible


func _on_selection_changed(c: CharacterData) -> void:
	if c:
		_building_card.visible = false
	if c and not _card.visible:
		Audio.play("card_open")
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
	if _build.visible:
		_build.refresh()


# --- Building (Phase 3) -------------------------------------------------------------------

func _build_conversation() -> void:
	_conversation = NegotiationPanel.new()
	_conversation.anchor_left = 0.5
	_conversation.anchor_right = 0.5
	_conversation.anchor_top = 1.0
	_conversation.anchor_bottom = 1.0
	_conversation.offset_bottom = -16
	_conversation.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_conversation.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_conversation.visible = false
	_root.add_child(_conversation)
	_conversation.farewell.connect(world.end_conversation)
	_conversation.eye_requested.connect(world.use_eye)


func _on_conversation_started(character_id: int, result: Dictionary) -> void:
	var c := world.state.get_character(character_id)
	if c:
		_help.visible = false
		_conversation.open(world, c, result)


func conversation_panel() -> NegotiationPanel:
	return _conversation


# --- Walking: who you're looking at, and the map table -----------------------------------------

func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_bottom = -26
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_stylebox_override("panel", UITheme.box(Color("#1c1510d8"), UITheme.GOLD_DIM, 1, 8, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(col)
	_prompt_name = UITheme.label("", 17, UITheme.TEXT, true)
	_prompt_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_prompt_name)
	_prompt_keys = UITheme.label("", 15, UITheme.ACCENT)
	_prompt_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_prompt_keys)
	_prompt.visible = false
	_root.add_child(_prompt)


## "Aldric Hunt, carpenter / [Q] Sovereign's Eye   [E] Talk": public things
## only (name and trade), and what you can do from where you stand.
func _update_prompt() -> void:
	var f := world.focus
	var show := world.mode == "walk" and f != null and world.talking_to < 0 and not world.is_revealing() and not is_menu_open()
	_prompt.visible = show
	if not show:
		return
	var c := f.character
	_prompt_name.text = "%s, %s" % [c.display_name(), c.occupation_name().to_lower()]
	if _touch.visible:
		_prompt_keys.text = ""
		_prompt_keys.visible = false
		return
	_prompt_keys.visible = true
	var eye_key := InputSetup.key_name("sovereign_eye", _pad)
	var talk_key := InputSetup.key_name("interact", _pad)
	var eye := "[%s] %s" % [eye_key, "Look again" if c.appraised else "Sovereign's Eye"]
	var talk := "[%s] Talk" % talk_key if world.talk_check(c.id)["ok"] else "(walk closer to talk)"
	_prompt_keys.text = "%s     %s" % [eye, talk]


func _build_map_banner() -> void:
	_map_banner = PanelContainer.new()
	_map_banner.anchor_left = 0.5
	_map_banner.anchor_right = 0.5
	_map_banner.offset_top = 58
	_map_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_map_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_banner.add_theme_stylebox_override("panel", UITheme.box(Color("#2a1f14e8"), UITheme.GOLD, 1, 6, 8))
	var l := UITheme.label("The Map Table  -  plan from above.  Tab or M to walk as your heir again.", 15, UITheme.ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_banner.add_child(l)
	_map_banner.visible = false
	_root.add_child(_map_banner)


func _on_mode_changed(mode: String) -> void:
	_map_banner.visible = mode == "overview" and world.heir_ctl != null
	_map_button.text = "Walk" if mode == "overview" else "Map"
	_map_button.tooltip_text = "Back to walking as your heir (Tab or M)" if mode == "overview" else "The map table: plan your lands from above (Tab or M)"


## The last input came from a controller (for button names in prompts).
func using_pad() -> bool:
	return _pad


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_pad = true
	elif event is InputEventKey or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION):
		_pad = false


func is_conversation_open() -> bool:
	return _conversation != null and _conversation.visible


## Selects a tab of the character card (after an Eye reveal's choices).
func show_card_tab(tab_name: String) -> void:
	if _card.visible:
		_card.show_tab(tab_name)


func _build_building_card() -> void:
	_building_card = BuildingCard.new()
	_building_card.world = world
	_building_card.anchor_left = 1.0
	_building_card.anchor_right = 1.0
	_building_card.anchor_top = 0.0
	_building_card.anchor_bottom = 1.0
	_building_card.offset_left = -BuildingCard.WIDTH - 12
	_building_card.offset_right = -12
	_building_card.offset_top = 96
	_building_card.offset_bottom = -12
	_building_card.visible = false
	_root.add_child(_building_card)
	_building_card.close_requested.connect(world.deselect)
	_building_card.character_chosen.connect(func(id: int) -> void: world.select_character(id, true))


func _on_building_selected(building_id: int) -> void:
	if building_id >= 0 and not _building_card.visible:
		Audio.play("card_open")
	_building_card.show_building(building_id)


func is_building_card_open() -> bool:
	return _building_card != null and _building_card.visible


func _build_build_panel() -> void:
	_build = BuildPanel.new()
	_build.world = world
	_build.anchor_left = 0.0
	_build.anchor_right = 0.0
	_build.anchor_top = 0.0
	_build.anchor_bottom = 1.0
	_build.offset_left = 12
	_build.offset_right = 12 + 540
	_build.offset_top = 96
	_build.offset_bottom = -12
	_build.visible = false
	_root.add_child(_build)
	_build.character_chosen.connect(func(id: int) -> void: world.select_character(id, true))
	_build.close_requested.connect(toggle_build)


## Food, wood and stone with their daily change, under the top bar.
func _build_stores_bar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.box(Color("#1c1510d8"), UITheme.GOLD_DIM, 1, 6, 6))
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_top = 54
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.tooltip_text = "Village stores (amount, change per day). B opens the Build panel."
	_root.add_child(bar)
	_stores_row = HBoxContainer.new()
	_stores_row.add_theme_constant_override("separation", 18)
	bar.add_child(_stores_row)
	for r: String in TerritorySystem.RESOURCES:
		var l := UITheme.label("", 15, Color(str(TerritorySystem.resource_def(r).get("color", "#ffffff"))))
		l.name = r
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_stores_row.add_child(l)
	var people := UITheme.label("", 15, UITheme.TEXT)
	people.name = "people"
	people.mouse_filter = Control.MOUSE_FILTER_PASS
	_stores_row.add_child(people)
	var sites := UITheme.label("", 15, UITheme.ACCENT)
	sites.name = "sites"
	_stores_row.add_child(sites)


func _update_stores_bar() -> void:
	var st := world.state
	if st.territory == null:
		return
	var net := TerritorySystem.net_change(st) if Engine.get_process_frames() % 30 == 0 or _stores_key.is_empty() else {}
	var key := ""
	for r: String in TerritorySystem.RESOURCES:
		key += "%d|" % floori(st.territory.amount(r))
	key += "%d|%d|%d" % [st.territory.sites.size(), int(TerritorySystem.is_hungry(st)), st.characters.size()]
	if net.is_empty() and key == _stores_key:
		return
	if net.is_empty():
		net = TerritorySystem.net_change(st)
	_stores_key = key
	for r: String in TerritorySystem.RESOURCES:
		var l: Label = _stores_row.get_node(r)
		var cap := TerritorySystem.capacity(st, r)
		var amount := st.territory.amount(r)
		l.text = "%s %d (%+d)" % [TerritorySystem.resource_name(r), floori(amount), roundi(float(net[r]))]
		l.tooltip_text = "%s: %d of %d stored, %+.1f per day" % [TerritorySystem.resource_name(r), floori(amount), roundi(cap), float(net[r])]
		var hungry := r == "food" and TerritorySystem.is_hungry(st)
		l.add_theme_color_override("font_color", UITheme.BAD if hungry else Color(str(TerritorySystem.resource_def(r).get("color", "#ffffff"))))
	var people: Label = _stores_row.get_node("people")
	people.text = "People %d" % st.characters.size()
	people.tooltip_text = "Villagers, homes and the settler bar: open Build (B)"
	var sites: Label = _stores_row.get_node("sites")
	sites.visible = not st.territory.sites.is_empty()
	sites.text = "Building %d" % st.territory.sites.size()


func _build_place_hint() -> void:
	_place_hint = PanelContainer.new()
	_place_hint.add_theme_stylebox_override("panel", UITheme.box(Color("#1c1510ee"), UITheme.GOLD, 2, 8, 10))
	_place_hint.anchor_left = 0.5
	_place_hint.anchor_right = 0.5
	_place_hint.anchor_top = 1.0
	_place_hint.anchor_bottom = 1.0
	_place_hint.offset_bottom = -16
	_place_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_place_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place_hint.visible = false
	_root.add_child(_place_hint)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_place_hint.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	_place_title = UITheme.label("", 17, UITheme.ACCENT, true)
	top.add_child(_place_title)
	top.add_child(UITheme.button("Turn (T)", func() -> void: world.turn_ghost()))
	top.add_child(UITheme.button("Cancel (Esc)", func() -> void: world.cancel_placing()))
	_place_reason = UITheme.label("", 15)
	col.add_child(_place_reason)
	col.add_child(UITheme.label("Click beside a road to place  -  Shift+click to place another", 13, UITheme.TEXT_DIM))


func _on_placing_changed(type: String) -> void:
	_place_hint.visible = not type.is_empty()
	if type.is_empty():
		return
	_build.visible = false
	var cost: Dictionary = TerritorySystem.buildable_def(type).get("cost", {})
	_place_title.text = "Placing: %s  (%s)" % [TerritorySystem.display_name(type), TerritorySystem.cost_text(cost)]


func _update_place_hint() -> void:
	var reason := world.placement_reason()
	if reason.is_empty():
		var trees := world.placement_trees()
		_place_reason.text = "Good spot." + (" %d trees will be felled for wood." % trees if trees > 0 else "")
		_place_reason.add_theme_color_override("font_color", UITheme.GOOD)
	else:
		_place_reason.text = reason
		_place_reason.add_theme_color_override("font_color", UITheme.BAD)


func _on_territory_changed() -> void:
	_stores_key = ""
	if _build.visible:
		_build.refresh()
	if _card.visible:
		_card.refresh()
	if _building_card.visible:
		_building_card.refresh()


# --- Toasts & help ------------------------------------------------------------------------

func _build_toasts() -> void:
	var toasts := ToastStack.new()
	# Shifted left of center so toasts never cover the character card.
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.offset_left = -520
	toasts.offset_right = 140
	toasts.offset_top = 96
	toasts.offset_bottom = 340
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
	var touch_help := "Stick - walk    Drag - turn the camera    Pinch - zoom\n" + \
		"Eye - the Sovereign's Eye on the person you face (be near, in sight)\n" + \
		"Talk - speak with them when you're beside them\n" + \
		"Map - the map table (build, plan)    Tap a villager - their card"
	var text := UITheme.label(touch_help if GameSettings.touch_controls() else
		"WASD / left stick - walk    Shift - run    Drag / right stick / arrows - turn the camera\n" +
		"Q / (Y) - Sovereign's Eye on the person you look at (be near, in sight)\n" +
		"E / (A) - talk: ask what they want, make an offer\n" +
		"Tab or M - the map table (build, plan)    Click a villager - their card\n" +
		"Wheel / pinch / R,F - zoom    Space - pause    1-4 - game speed\n" +
		"B - build    K - your court    L - village ledger    F5 / F9 - quicksave / quickload\n" +
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
	col.add_child(HSeparator.new())
	col.add_child(SoundSettings.new())
	col.add_child(AccessibilitySettings.new())

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
	if world.is_placing() and not _pause_overlay.visible:
		if event.is_action_pressed("menu"):
			world.cancel_placing()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("turn_building"):
			world.turn_ghost()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("menu"):
		if _pause_overlay.visible:
			if _slots.visible:
				_on_slots_cancelled()
			else:
				close_pause_menu()
		elif _conversation.visible:
			world.end_conversation()
		elif _card.visible or _building_card.visible:
			world.deselect()
		elif _ledger.visible:
			toggle_ledger()
		elif _court.visible:
			toggle_court()
		elif _build.visible:
			toggle_build()
		else:
			open_pause_menu()
	elif event.is_action_pressed("toggle_build"):
		toggle_build()
	elif event.is_action_pressed("toggle_ledger"):
		toggle_ledger()
	elif event.is_action_pressed("toggle_court"):
		toggle_court()
	elif event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	else:
		return
	get_viewport().set_input_as_handled()
