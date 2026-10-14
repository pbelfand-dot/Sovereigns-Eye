class_name UITheme
extends RefCounted
## The medieval look of every menu: dark walnut panels, gold trim and
## parchment text. Built in code so the whole style lives in one place;
## swap fonts/colors here and every screen follows.

const BG := Color("#1c1510f2")
const BG_SOFT := Color("#2a2018")
const BG_ROW := Color("#2f241a")
const BG_ROW_HOVER := Color("#3d2f22")
const GOLD := Color("#c9a14a")
const GOLD_DIM := Color("#7d6533")
const TEXT := Color("#eddcb8")
const TEXT_DIM := Color("#a8957a")
const ACCENT := Color("#e9bf62")
const GOOD := Color("#8fd16a")
const BAD := Color("#e46a5c")
const NEUTRAL := Color("#c9b99a")

const CATEGORY_COLORS := {
	"life": Color("#b9a98c"),
	"career": Color("#7fb2e0"),
	"military": Color("#e07a6a"),
	"appointment": Color("#e9bf62"),
	"family": Color("#e59ac0"),
	"achievement": Color("#8fd16a"),
	"rumor": Color("#b88be6"),
}

static var _theme: Theme
static var _heading_font: Font
static var _body_font: Font


## Bundled fonts (SIL Open Font License, see assets/fonts/) so text looks the
## same on every device; falls back to system serif fonts if missing.
const BODY_FONT_PATH := "res://assets/fonts/EBGaramond.ttf"
const HEADING_FONT_PATH := "res://assets/fonts/Cinzel.ttf"


static func _font(path: String, weight: int) -> Font:
	if ResourceLoader.exists(path):
		var base: FontFile = load(path)
		var v := FontVariation.new()
		v.base_font = base
		v.variation_opentype = {"wght": weight}
		return v
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Palatino", "Palatino Linotype", "Book Antiqua", "Georgia", "Cambria", "Times New Roman", "serif"])
	f.font_weight = weight
	return f


static func body_font() -> Font:
	if _body_font == null:
		_body_font = _font(BODY_FONT_PATH, 500)
	return _body_font


static func heading_font() -> Font:
	if _heading_font == null:
		_heading_font = _font(HEADING_FONT_PATH, 700)
	return _heading_font


static func box(bg: Color, border: Color = GOLD, border_width: int = 2, radius: int = 6, margin: float = 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4 if border_width > 0 else 0
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 16

	t.set_stylebox("panel", "PanelContainer", box(BG))
	t.set_stylebox("panel", "Panel", box(BG))
	for type in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "RichTextLabel", "TabContainer", "LinkButton"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)

	var btn := box(Color("#3a2b1e"), GOLD_DIM, 1, 4, 6)
	btn.content_margin_left = 12
	btn.content_margin_right = 12
	btn.shadow_size = 0
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color("#4d3926")
	btn_hover.border_color = GOLD
	var btn_pressed := btn.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color("#241a12")
	btn_pressed.border_color = ACCENT
	var btn_disabled := btn.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color("#2a221b")
	btn_disabled.border_color = Color("#4a3d2c")
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, btn)
		t.set_stylebox("hover", type, btn_hover)
		t.set_stylebox("pressed", type, btn_pressed)
		t.set_stylebox("hover_pressed", type, btn_pressed)
		t.set_stylebox("disabled", type, btn_disabled)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_hover_color", type, ACCENT)
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_disabled_color", type, Color("#6f6352"))

	# "Flat" row buttons used in lists (ledger, relationships)
	t.add_type("RowButton")
	t.set_type_variation("RowButton", "Button")
	var row := box(BG_ROW, Color(0, 0, 0, 0), 0, 4, 6)
	row.shadow_size = 0
	var row_hover := row.duplicate() as StyleBoxFlat
	row_hover.bg_color = BG_ROW_HOVER
	row_hover.border_color = GOLD_DIM
	row_hover.set_border_width_all(1)
	t.set_stylebox("normal", "RowButton", row)
	t.set_stylebox("hover", "RowButton", row_hover)
	t.set_stylebox("pressed", "RowButton", row_hover)
	t.set_stylebox("hover_pressed", "RowButton", row_hover)
	t.set_stylebox("focus", "RowButton", StyleBoxEmpty.new())

	var edit := box(Color("#120d09"), GOLD_DIM, 1, 4, 8)
	edit.shadow_size = 0
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", box(Color("#120d09"), GOLD, 1, 4, 8))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)

	var tab_sel := box(Color("#3a2b1e"), GOLD, 1, 4, 8)
	tab_sel.border_width_bottom = 0
	tab_sel.shadow_size = 0
	var tab_unsel := box(Color("#211912"), GOLD_DIM, 1, 4, 8)
	tab_unsel.border_width_bottom = 0
	tab_unsel.shadow_size = 0
	var tab_hover := tab_unsel.duplicate() as StyleBoxFlat
	tab_hover.bg_color = Color("#2e2319")
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unsel)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hover)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	var tab_panel := box(Color("#16110c"), GOLD_DIM, 1, 4, 10)
	tab_panel.shadow_size = 0
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	var tip := box(Color("#120d09f5"), GOLD, 1, 4, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)

	var sep := StyleBoxLine.new()
	sep.color = GOLD_DIM
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)

	var bar_bg := box(Color("#120d09"), Color("#3d3024"), 1, 3, 0)
	bar_bg.shadow_size = 0
	var bar_fill := box(GOLD, Color(0, 0, 0, 0), 0, 3, 0)
	bar_fill.shadow_size = 0
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)

	var scroll := box(Color("#2a2018"), Color(0, 0, 0, 0), 0, 3, 3)
	scroll.shadow_size = 0
	var grabber := box(GOLD_DIM, Color(0, 0, 0, 0), 0, 3, 3)
	grabber.shadow_size = 0
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)

	_theme = t
	return t


# --- Widget helpers ---------------------------------------------------------------

static func label(text: String, size: int = 16, color: Color = TEXT, heading: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if heading:
		l.add_theme_font_override("font", heading_font())
	return l


static func button(text: String, callback: Callable, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.x = min_width
	b.pressed.connect(callback)
	return b


## Small colored rank badge, e.g. [S+].
static func rank_badge(rank: String, color: Color, size: int = 15) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = color.darkened(0.55)
	s.border_color = color
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	var l := label(rank, size, color.lightened(0.15), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 26
	p.add_child(l)
	return p


static func value_color(value: float) -> Color:
	if value > 0.0:
		return GOOD
	if value < 0.0:
		return BAD
	return NEUTRAL


static func opinion_color(opinion: int) -> Color:
	if opinion >= 40:
		return GOOD
	if opinion <= -10:
		return BAD
	return NEUTRAL
