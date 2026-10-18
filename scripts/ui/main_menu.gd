extends Control
## Title screen: Continue, New Game (with optional seed), Load Game, Settings,
## Quit. Laid out like a medieval strategy game's: the key art fills the
## screen, drifting slowly, darkened on the left where a column holds the
## emblem, the title and the menu. The art lives in assets/ui/menu/ (see its
## README); without it the screen falls back to a warm gradient and the
## game's icon. Reduce motion stills the drift and the motes.

const KEY_ART := "res://assets/ui/menu/key_art.jpg"
const EMBLEM := "res://assets/ui/menu/emblem.png"
## How far the key art drifts in (scale) over one slow breath, and how long it takes (s).
const DRIFT_SCALE := 1.06
const DRIFT_TIME := 38.0
## Narrower than this (px), or taller than wide, the column centres over the art.
const NARROW := 900.0
## What stays in view of the key art when the screen is narrower or taller
## than the art (as fractions of it): the chapel and the heir. The slow
## drift draws in toward it too.
const ART_FOCUS := Vector2(0.68, 0.55)

var _menu: VBoxContainer
var _new_game_panel: PanelContainer
var _seed_edit: LineEdit
var _slots: SaveSlotDialog
var _sound_panel: PanelContainer
var _keys_panel: PanelContainer
var _keys: ControlsSettings
var _bg: TextureRect
var _shade: TextureRect
var _column: MarginContainer
var _motes: CPUParticles2D
var _header: Array[Control] = []   # the emblem and the line beneath the title: they step aside for a panel


func _ready() -> void:
	if _autostart_from_command_line():
		return
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Audio.set_music("menu")
	_build_backdrop()
	_build_column()
	var toasts := ToastStack.new()
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.offset_left = -300
	toasts.offset_right = 300
	toasts.offset_top = 20
	add_child(toasts)
	get_viewport().size_changed.connect(_fit)
	_fit()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)
	_focus_first.call_deferred()


## Developer/CI switch: `-- --new-game=<seed>` skips the menu and starts a
## village immediately (used to smoke-test exported builds).
func _autostart_from_command_line() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--new-game="):
			Game.start_new_game.call_deferred(arg.trim_prefix("--new-game="))
			return true
	return false


# --- The backdrop: key art, shade, vignette, motes --------------------------------------

func _build_backdrop() -> void:
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(KEY_ART):
		_bg.texture = load(KEY_ART)
		# Placed by _fit() to cover the screen round ART_FOCUS.
		_bg.stretch_mode = TextureRect.STRETCH_SCALE
		_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	else:
		_bg.texture = _gradient([Color("#3a2a1c"), Color("#0d0a07")], GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.42), Vector2(1.1, 1.1))
		_bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg)
	# The left darkens where the menu stands; the edges fall into shadow.
	_shade = TextureRect.new()
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	var vignette := TextureRect.new()
	vignette.texture = _gradient([Color(0.04, 0.03, 0.02, 0.0), Color(0.04, 0.03, 0.02, 0.62)], GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.5), Vector2(1.15, 1.15), [0.55, 1.0])
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	if GameSettings.reduced_motion():
		return
	_motes = CPUParticles2D.new()
	_motes.amount = 36
	_motes.lifetime = 14.0
	_motes.preprocess = 14.0
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.direction = Vector2(0.3, -1.0)
	_motes.spread = 25.0
	_motes.gravity = Vector2.ZERO
	_motes.initial_velocity_min = 8.0
	_motes.initial_velocity_max = 22.0
	_motes.scale_amount_min = 1.2
	_motes.scale_amount_max = 3.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.85, 0.5, 0.0))
	fade.add_point(0.25, Color(1.0, 0.85, 0.5, 0.55))
	fade.add_point(0.75, Color(1.0, 0.85, 0.5, 0.4))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 0.85, 0.5, 0.0))
	_motes.color_ramp = fade
	_motes.texture = _gradient([Color(1, 1, 1, 1), Color(1, 1, 1, 0)], GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.5), Vector2(1.0, 0.5))
	(_motes.texture as GradientTexture2D).width = 16
	(_motes.texture as GradientTexture2D).height = 16
	_motes.scale_amount_min = 0.15
	_motes.scale_amount_max = 0.38
	add_child(_motes)


## Where the key art goes to cover a screen of size `screen`: scaled to
## cover it without stretching, and shifted, as far as its edges allow, to
## keep `focus` (a fraction of the art) in the middle.
static func cover_rect(screen: Vector2, art: Vector2, focus: Vector2) -> Rect2:
	var k := maxf(screen.x / art.x, screen.y / art.y)
	var size := art * k
	var pos := (screen * 0.5 - size * focus).clamp(screen - size, Vector2.ZERO)
	return Rect2(pos, size)


static func _gradient(colors: Array, fill: int, from: Vector2, to: Vector2, offsets: Array = []) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, colors[0])
	g.set_color(1, colors[1])
	if offsets.size() == 2:
		g.set_offset(0, float(offsets[0]))
		g.set_offset(1, float(offsets[1]))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = fill
	tex.fill_from = from
	tex.fill_to = to
	tex.width = 512
	tex.height = 512
	return tex


## Lays the screen out for its size: the column on the left over a shade
## that fades out across the art, or centred over an even shade when the
## screen is narrow or upright (phones).
func _fit() -> void:
	var s := get_viewport_rect().size
	var narrow := s.x < NARROW or s.y > s.x
	var dark := Color(0.05, 0.035, 0.025)
	if narrow:
		if s.y > s.x:
			# Upright (phones): dark behind the menu at the top, the scene
			# showing below it, a little shade again under the footer.
			var g := _gradient([Color(dark, 0.86), Color(dark, 0.45)], GradientTexture2D.FILL_LINEAR, Vector2(0, 0), Vector2(0, 1))
			g.gradient.set_offset(0, 0.32)
			g.gradient.add_point(0.82, Color(dark, 0.15))
			_shade.texture = g
		else:
			_shade.texture = _gradient([Color(dark, 0.72), Color(dark, 0.72)], GradientTexture2D.FILL_LINEAR, Vector2(0, 0), Vector2(1, 0))
		_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right"]:
			_column.add_theme_constant_override("margin_" + side, int(maxf(16.0, (s.x - 460.0) * 0.5)))
	else:
		_shade.texture = _gradient([Color(dark, 0.9), Color(dark, 0.0)], GradientTexture2D.FILL_LINEAR, Vector2(0, 0), Vector2(0.62, 0), [0.25, 1.0])
		_column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		_column.offset_right = 520.0 + s.x * 0.06
		_column.add_theme_constant_override("margin_left", int(maxf(32.0, s.x * 0.06)))
		_column.add_theme_constant_override("margin_right", 24)
	if _motes:
		_motes.position = Vector2(s.x * 0.5, s.y + 10.0)
		_motes.emission_rect_extents = Vector2(s.x * 0.5, 10.0)
	if _bg.texture and ResourceLoader.exists(KEY_ART):
		var r := cover_rect(s, _bg.texture.get_size(), ART_FOCUS)
		_bg.position = r.position
		_bg.size = r.size
		_bg.pivot_offset = r.size * ART_FOCUS
		if not _bg.has_meta("drifting") and not GameSettings.reduced_motion():
			_bg.set_meta("drifting", true)
			var t := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.tween_property(_bg, "scale", Vector2.ONE * DRIFT_SCALE, DRIFT_TIME)
			t.tween_property(_bg, "scale", Vector2.ONE, DRIFT_TIME)


# --- The column: emblem, title, menu, panels, footer -----------------------------------

func _build_column() -> void:
	_column = MarginContainer.new()
	_column.add_theme_constant_override("margin_top", 48)
	_column.add_theme_constant_override("margin_bottom", 22)
	add_child(_column)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_column.add_child(col)
	col.add_child(_spacer(0.35))

	var emblem := TextureRect.new()
	emblem.texture = load(EMBLEM) if ResourceLoader.exists(EMBLEM) else load("res://icon.svg")
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	emblem.custom_minimum_size = Vector2(112, 112)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(emblem)
	_header.append(emblem)
	var title := UITheme.label("SOVEREIGN'S EYE", 52, UITheme.ACCENT, true)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.85))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	col.add_child(title)
	var subtitle := UITheme.label("Every villager hides a ceiling. Only you can see it.", 19, UITheme.TEXT)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	col.add_child(subtitle)
	_header.append(subtitle)
	col.add_child(Ornament.new())
	col.add_child(_spacer(0.1))

	# The menu and its panels scroll if a small screen can't hold them.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 3.0
	col.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	col = body
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	col.add_child(_menu)
	var latest := _latest_slot()
	if not latest.is_empty():
		var info := SaveManager.slot_info(latest)
		var cont := _item("Continue", func() -> void: Game.load_game(latest),
			"%s  -  %s" % [str(info.get("village", SaveManager.slot_label(latest))), str(info.get("date", ""))])
		_menu.add_child(cont)
	_menu.add_child(_item("New Game", _show_new_game))
	var load_item := _item("Load Game", _show_load)
	load_item.disabled = not SaveManager.any_save_exists()
	_menu.add_child(load_item)
	_menu.add_child(_item("Settings", _show_sound))
	_menu.add_child(_item("Quit", Game.quit_game))

	_build_new_game_panel(col)
	_sound_panel = PanelContainer.new()
	_sound_panel.visible = false
	_sound_panel.custom_minimum_size.x = 420
	_sound_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_sound_panel)
	var sound_col := VBoxContainer.new()
	sound_col.add_theme_constant_override("separation", 10)
	_sound_panel.add_child(sound_col)
	# Back and Keys beside the heading, where they're seen without scrolling.
	var settings_head := HBoxContainer.new()
	settings_head.add_theme_constant_override("separation", 10)
	sound_col.add_child(settings_head)
	var settings_title := UITheme.label("Settings", 22, UITheme.TEXT, true)
	settings_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_head.add_child(settings_title)
	settings_head.add_child(UITheme.button("Keys...", _show_keys))
	settings_head.add_child(UITheme.button("Back", _show_menu))
	sound_col.add_child(SoundSettings.new())
	sound_col.add_child(AccessibilitySettings.new())
	_keys_panel = PanelContainer.new()
	_keys_panel.visible = false
	_keys_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_keys_panel)
	_keys = ControlsSettings.new()
	_keys.list_height = 250.0
	_keys.closed.connect(_show_sound)
	_keys_panel.add_child(_keys)
	_slots = SaveSlotDialog.new()
	_slots.visible = false
	_slots.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_slots)
	_slots.cancelled.connect(_show_menu)
	_slots.slot_chosen.connect(func(slot: String) -> void: Game.load_game(slot))

	var version := UITheme.label("Phase 3 prototype  -  v%s" % ProjectSettings.get_setting("application/config/version", ""), 13, UITheme.TEXT_DIM)
	(scroll.get_parent() as Container).add_child(version)


func _spacer(weight: float) -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = weight
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A menu entry: large engraved-gold text, a gold bar and a faint wash when
## hovered or focused (mouse, keyboard or pad), an optional line beneath.
func _item(text: String, callback: Callable, detail: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(callback)
	b.add_theme_font_override("font", UITheme.heading_font())
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", UITheme.TEXT)
	b.add_theme_color_override("font_hover_color", UITheme.ACCENT)
	b.add_theme_color_override("font_focus_color", UITheme.ACCENT)
	b.add_theme_color_override("font_pressed_color", UITheme.GOLD)
	b.add_theme_color_override("font_disabled_color", Color(UITheme.TEXT_DIM, 0.45))
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.8))
	b.add_theme_constant_override("outline_size", 4)
	var plain := StyleBoxEmpty.new()
	plain.content_margin_left = 16
	plain.content_margin_top = 6
	plain.content_margin_bottom = 6
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(UITheme.GOLD, 0.12)
	lit.border_color = UITheme.GOLD
	lit.border_width_left = 3
	lit.content_margin_left = 16
	lit.content_margin_top = 6
	lit.content_margin_bottom = 6
	for state in ["normal", "disabled"]:
		b.add_theme_stylebox_override(state, plain)
	for state in ["hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(state, lit)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	if detail != "":
		b.tooltip_text = detail
		b.text = text
		var line := UITheme.label(detail, 14, UITheme.TEXT_DIM)
		line.position = Vector2(18, 40)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(line)
		b.custom_minimum_size.y = 62
		plain.content_margin_bottom = 26
		lit.content_margin_bottom = 26
	return b


func _build_new_game_panel(parent: Container) -> void:
	_new_game_panel = PanelContainer.new()
	_new_game_panel.visible = false
	_new_game_panel.custom_minimum_size.x = 420
	_new_game_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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


func _focus_first() -> void:
	for b in _menu.get_children():
		if b is Button and not (b as Button).disabled:
			(b as Button).grab_focus()
			return


func _show_menu() -> void:
	_menu.visible = true
	_new_game_panel.visible = false
	_sound_panel.visible = false
	_keys_panel.visible = false
	_slots.visible = false
	_set_header(true)
	_focus_first()


func _show_sound() -> void:
	_menu.visible = false
	_keys_panel.visible = false
	_sound_panel.visible = true
	_set_header(false)


func _show_keys() -> void:
	_sound_panel.visible = false
	_keys_panel.visible = true
	_keys.refresh()


func _show_new_game() -> void:
	_menu.visible = false
	_new_game_panel.visible = true
	_set_header(false)
	_seed_edit.grab_focus()


func _show_load() -> void:
	_menu.visible = false
	_set_header(false)
	_slots.open("load")


## With a panel open, the emblem and the line under the title step aside
## to give it room; the title stays as its heading.
func _set_header(shown: bool) -> void:
	for c in _header:
		c.visible = shown


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
		if _keys_panel.visible:
			_show_sound()
		else:
			_show_menu()
		get_viewport().set_input_as_handled()


## A thin gold rule with a diamond in the middle, under the title.
class Ornament extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(360, 18)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		var mid := size.x * 0.5
		var gold := UITheme.GOLD
		draw_line(Vector2(0, y), Vector2(mid - 12, y), Color(gold, 0.85), 1.5, true)
		draw_line(Vector2(mid + 12, y), Vector2(size.x, y), Color(gold, 0.85), 1.5, true)
		draw_colored_polygon(PackedVector2Array([Vector2(mid, y - 6), Vector2(mid + 7, y), Vector2(mid, y + 6), Vector2(mid - 7, y)]), gold)
		draw_circle(Vector2(0, y), 2.0, gold)
		draw_circle(Vector2(size.x, y), 2.0, gold)
