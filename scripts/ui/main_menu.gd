extends Control
## Title screen: Continue, New Game (with optional seed), Load Game, Quit.

var _menu: VBoxContainer
var _new_game_panel: PanelContainer
var _seed_edit: LineEdit
var _slots: SaveSlotDialog


func _ready() -> void:
	if _autostart_from_command_line():
		return
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color("#3a2a1c"))
	grad.set_color(1, Color("#0d0a07"))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.1, 1.1)
	tex.width = 512
	tex.height = 512
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var emblem := TextureRect.new()
	emblem.texture = load("res://icon.svg")
	emblem.custom_minimum_size = Vector2(112, 112)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(emblem)
	var title := UITheme.label("SOVEREIGN'S EYE", 56, UITheme.ACCENT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var subtitle := UITheme.label("Every villager hides a ceiling. Only you can see it.", 18, UITheme.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(subtitle)
	col.add_child(Control.new())

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	_menu.custom_minimum_size.x = 300
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_menu)
	var latest := _latest_slot()
	if not latest.is_empty():
		var cont := UITheme.button("Continue", func() -> void: Game.load_game(latest))
		cont.tooltip_text = "%s - %s" % [SaveManager.slot_label(latest), SaveManager.slot_info(latest).get("date", "")]
		_menu.add_child(cont)
	_menu.add_child(UITheme.button("New Game", _show_new_game))
	var load_btn := UITheme.button("Load Game", _show_load)
	load_btn.disabled = not SaveManager.any_save_exists()
	_menu.add_child(load_btn)
	_menu.add_child(UITheme.button("Quit", Game.quit_game))

	_build_new_game_panel(col)
	_slots = SaveSlotDialog.new()
	_slots.visible = false
	_slots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_slots)
	_slots.cancelled.connect(_show_menu)
	_slots.slot_chosen.connect(func(slot: String) -> void: Game.load_game(slot))

	var version := UITheme.label("Phase 1 prototype  -  v%s" % ProjectSettings.get_setting("application/config/version", ""), 13, UITheme.TEXT_DIM)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -300
	version.offset_top = -30
	version.offset_right = -14
	version.offset_bottom = -8
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)

	var toasts := ToastStack.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.offset_left = -300
	toasts.offset_right = 300
	toasts.offset_top = 20
	add_child(toasts)


## Developer/CI switch: `-- --new-game=<seed>` skips the menu and starts a
## village immediately (used to smoke-test exported builds).
func _autostart_from_command_line() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--new-game="):
			Game.start_new_game.call_deferred(arg.trim_prefix("--new-game="))
			return true
	return false


func _build_new_game_panel(parent: Container) -> void:
	_new_game_panel = PanelContainer.new()
	_new_game_panel.visible = false
	_new_game_panel.custom_minimum_size.x = 420
	_new_game_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(_new_game_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_new_game_panel.add_child(col)
	col.add_child(UITheme.label("New Game", 22, UITheme.TEXT, true))
	var hint := UITheme.label("The same seed always creates the same village and people.", 14, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	var row := HBoxContainer.new()
	col.add_child(row)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "World seed (blank = random)"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _begin())
	row.add_child(_seed_edit)
	row.add_child(UITheme.button("Random", func() -> void: _seed_edit.text = Seeds.random_seed_text()))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	buttons.add_child(UITheme.button("Back", _show_menu))
	var begin := UITheme.button("Begin", _begin)
	begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(begin)


func _show_menu() -> void:
	_menu.visible = true
	_new_game_panel.visible = false
	_slots.visible = false


func _show_new_game() -> void:
	_menu.visible = false
	_new_game_panel.visible = true
	_seed_edit.grab_focus()


func _show_load() -> void:
	_menu.visible = false
	_slots.open("load")


func _begin() -> void:
	Game.start_new_game(_seed_edit.text)


func _latest_slot() -> String:
	var best := ""
	var best_time := 0
	for slot in SaveManager.SLOTS:
		if SaveManager.exists(slot):
			var t := FileAccess.get_modified_time(SaveManager.slot_path(slot))
			if t > best_time:
				best_time = t
				best = slot
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu") and not _menu.visible:
		_show_menu()
		get_viewport().set_input_as_handled()
