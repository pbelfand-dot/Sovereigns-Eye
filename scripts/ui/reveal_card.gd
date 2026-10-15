class_name RevealCard
extends Control
## The card the Sovereign's Eye reveals. Back: dark leather and a wax seal
## bearing the Eye (the same for everyone, so it gives nothing away). Front:
## parchment with a frame that grows richer with the person's tier, a crest
## and pips, their portrait, role, greatest gift, three strongest abilities,
## traits and overall promise.
##
## Tier is shown in several ways at once (never by color alone): the tier
## name, the crest shape (none / shield / sun / crown), the number of pips
## and the frame pattern (plain / single / double / filigree).

const SIZE := Vector2(380, 560)

var tier: Dictionary = {}
var character: CharacterData
var face := "back":
	set(v):
		face = v
		_back.visible = v == "back"
		_front.visible = v == "front"
		queue_redraw()
var main := Color("#9a9488")
var accent := Color("#5e584e")
var ink := Color("#2b2219")

var _back: Control
var _front: VBoxContainer
var silhouette: TextureRect
var portrait: TextureRect
var _tier_label: Label
var _gift_name: Label
var stamp: Label
var _gift_value: Label
var _rows: Array[Dictionary] = []
var _traits: Label
var _overall: Label
var _sheen := 0.0


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func setup(c: CharacterData, tier_def: Dictionary, portrait_tex: Texture2D) -> void:
	character = c
	tier = tier_def
	var colors: Dictionary = tier.get("colors", {})
	main = Color(str(colors.get("main", "#9a9488")))
	accent = Color(str(colors.get("accent", "#5e584e")))
	ink = Color(str(colors.get("ink", "#2b2219")))
	# Back
	_back = Control.new()
	_back.size = SIZE
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	silhouette = TextureRect.new()
	silhouette.texture = portrait_tex
	silhouette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	silhouette.size = Vector2(240, 300)
	silhouette.position = Vector2((SIZE.x - 240) * 0.5, 120)
	silhouette.modulate = Color(0, 0, 0, 0)
	_back.add_child(silhouette)
	# Front
	_front = VBoxContainer.new()
	_front.position = Vector2(26, 64)
	_front.size = Vector2(SIZE.x - 52, SIZE.y - 84)
	_front.add_theme_constant_override("separation", 3)
	_front.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_front)
	_tier_label = _label(str(tier.get("name", "")).to_upper(), 15, ink.lightened(0.15), true)
	_front.add_child(_tier_label)
	portrait = TextureRect.new()
	portrait.texture = portrait_tex
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(150, 168)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_front.add_child(portrait)
	_front.add_child(_label(c.display_name(), 22, ink, true))
	_front.add_child(_label("%s, %d" % [c.occupation_name(), c.age], 15, ink.lightened(0.25), false))
	# Greatest gift: the payoff line.
	var gift := HBoxContainer.new()
	gift.alignment = BoxContainer.ALIGNMENT_CENTER
	gift.add_theme_constant_override("separation", 10)
	var top := Discovery.top_abilities(c)
	_gift_name = _label("Greatest gift: %s" % str(top[0]["name"]), 16, ink, false)
	gift.add_child(_gift_name)
	stamp = _label(str(top[0]["rank"]), 30, Color("#7a1414") if int(tier.get("pips", 1)) >= 3 else ink, true)
	stamp.pivot_offset = Vector2(24, 20)
	stamp.custom_minimum_size = Vector2(48, 40)
	stamp.modulate.a = 0.0
	gift.add_child(stamp)
	_gift_value = _label("", 15, ink.lightened(0.2), false)
	gift.add_child(_gift_value)
	_front.add_child(gift)
	# Three strongest abilities, strongest first.
	for i in top.size():
		var r: Dictionary = top[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l := _label(str(r["name"]), 14, ink, false)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.custom_minimum_size.x = 104
		row.add_child(name_l)
		var bar := StatBar.new()
		bar.custom_minimum_size = Vector2(110, 12)
		bar.setup(0, 0, Appraisal.rank_color(int(r["potential"])))
		row.add_child(bar)
		var nums := _label("", 14, ink, false)
		nums.custom_minimum_size.x = 62
		nums.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(nums)
		var rank := _label("", 14, ink, true)
		rank.custom_minimum_size.x = 30
		row.add_child(rank)
		row.modulate.a = 0.0
		_front.add_child(row)
		_rows.append({"node": row, "bar": bar, "nums": nums, "rank": rank, "data": r})
	var trait_names: Array[String] = []
	for t in c.traits:
		trait_names.append(str(GameData.trait_def(t).get("name", t.capitalize())))
	_traits = _label("  ·  ".join(trait_names), 13, ink.lightened(0.25), false)
	_traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_front.add_child(_traits)
	var overall := Discovery.overall_potential(c)
	_overall = _label("Overall promise: %s (%d)" % [Appraisal.rank_id(overall), overall], 15, ink, true)
	_overall.modulate.a = 0.0
	_front.add_child(_overall)
	face = "back"


func _label(text: String, size_px: int, color: Color, heading: bool) -> Label:
	var l := UITheme.label(text, size_px, color, heading)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Shows ability row `i` (0 = strongest) counted up to `p` (0..1).
func set_row(i: int, p: float) -> void:
	if i < 0 or i >= _rows.size():
		return
	var row: Dictionary = _rows[i]
	var d: Dictionary = row["data"]
	(row["node"] as Control).modulate.a = clampf(p * 3.0, 0.0, 1.0)
	var cur := roundi(int(d["current"]) * p)
	var pot := roundi(int(d["potential"]) * p)
	(row["bar"] as StatBar).setup(cur, pot, Appraisal.rank_color(int(d["potential"])))
	(row["nums"] as Label).text = "%d / %d" % [cur, pot]
	(row["rank"] as Label).text = str(d["rank"]) if p >= 0.999 else ""


func row_count() -> int:
	return _rows.size()


## The payoff: the greatest gift's rank lands, with the overall promise.
func show_stamp(on: bool) -> void:
	stamp.modulate.a = 1.0 if on else 0.0
	_overall.modulate.a = 1.0 if on else 0.0
	var top: Dictionary = _rows[0]["data"]
	_gift_value.text = "(%d)" % int(top["potential"]) if on else ""


func set_sheen(v: float) -> void:
	_sheen = v
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	if face == "back":
		_draw_back(r)
	else:
		_draw_front(r)


func _draw_back(r: Rect2) -> void:
	draw_rect(r, Color("#3a2416"))
	draw_rect(r.grow(-10), Color("#4a2e1c"))
	# Stitching
	var inner := r.grow(-18)
	var x := inner.position.x
	while x < inner.end.x:
		draw_line(Vector2(x, inner.position.y), Vector2(x + 6, inner.position.y), Color("#c9a77a"), 1.5)
		draw_line(Vector2(x, inner.end.y), Vector2(x + 6, inner.end.y), Color("#c9a77a"), 1.5)
		x += 12
	var y := inner.position.y
	while y < inner.end.y:
		draw_line(Vector2(inner.position.x, y), Vector2(inner.position.x, y + 6), Color("#c9a77a"), 1.5)
		draw_line(Vector2(inner.end.x, y), Vector2(inner.end.x, y + 6), Color("#c9a77a"), 1.5)
		y += 12
	# Wax seal with the Eye
	var c := r.get_center() + Vector2(0, 10)
	for i in 12:
		var a := i * TAU / 12.0
		draw_circle(c + Vector2(cos(a), sin(a)) * 54, 14, Color("#7a1616"))
	draw_circle(c, 58, Color("#8e1b1b"))
	draw_circle(c, 46, Color("#a32323"))
	var up := PackedVector2Array()
	var low := PackedVector2Array()
	for i in 17:
		var t := lerpf(-1.0, 1.0, i / 16.0)
		var k := pow(maxf(1.0 - t * t, 0.0), 0.85)
		up.append(c + Vector2(t * 34, -16 * k))
		low.append(c + Vector2(t * 34, 13 * k))
	draw_polyline(up, Color("#5a0d0d"), 3.0, true)
	draw_polyline(low, Color("#5a0d0d"), 3.0, true)
	draw_circle(c, 8, Color("#5a0d0d"))
	draw_string(UITheme.heading_font(), Vector2(0, r.end.y - 34), "SOVEREIGN'S EYE", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 15, Color("#c9a77a"))


func _draw_front(r: Rect2) -> void:
	draw_rect(r, Color("#efe2c4"))
	# Parchment edge darkening
	for i in 8:
		draw_rect(r.grow(-i * 2.0), Color(0.45, 0.32, 0.18, 0.05), false, 2.0)
	var frame := str(tier.get("frame", "plain"))
	match frame:
		"plain":
			draw_rect(r.grow(-3), ink.lightened(0.2), false, 4.0)
		"single":
			draw_rect(r.grow(-4), main.darkened(0.15), false, 6.0)
			draw_rect(r.grow(-13), accent, false, 1.5)
			_corners(r.grow(-13), 5.0, accent)
		"double":
			draw_rect(r.grow(-5), main.darkened(0.1), false, 8.0)
			draw_rect(r.grow(-15), accent, false, 2.0)
			draw_rect(r.grow(-20), main.darkened(0.2), false, 1.5)
			_corners(r.grow(-15), 9.0, accent)
		"filigree":
			draw_rect(r.grow(-6), accent, false, 12.0)
			draw_rect(r.grow(-1), main, false, 2.0)
			draw_rect(r.grow(-13), main, false, 2.0)
			draw_rect(r.grow(-20), main.darkened(0.25), false, 1.5)
			_corners(r.grow(-13), 13.0, main)
			# Filigree scrolls along the sides
			for side in 2:
				var x := 9.5 if side == 0 else SIZE.x - 9.5
				for k in 8:
					var yy := 90.0 + k * 52.0
					draw_arc(Vector2(x, yy), 5.0, 0, TAU, 12, main, 1.5)
	_crest(Vector2(SIZE.x * 0.5, 30))
	# Light sheen across the face
	if _sheen > 0.0:
		var sx := lerpf(-120.0, SIZE.x + 120.0, _sheen)
		var poly := PackedVector2Array([Vector2(sx - 40, 0), Vector2(sx + 10, 0), Vector2(sx - 70, SIZE.y), Vector2(sx - 120, SIZE.y)])
		draw_colored_polygon(poly, Color(1, 1, 1, 0.18))


func _corners(r: Rect2, s: float, col: Color) -> void:
	for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), col)


## Crest shape by tier plus pips (one per tier step).
func _crest(c: Vector2) -> void:
	var pips := int(tier.get("pips", 1))
	match str(tier.get("crest", "none")):
		"shield":
			var pts := PackedVector2Array([c + Vector2(-14, -14), c + Vector2(14, -14), c + Vector2(14, 2), c + Vector2(0, 16), c + Vector2(-14, 2)])
			draw_colored_polygon(pts, accent)
			pts.append(pts[0])
			draw_polyline(pts, main.darkened(0.2), 2.0, true)
		"sun":
			for k in 12:
				var a := k * TAU / 12.0
				draw_line(c + Vector2(cos(a), sin(a)) * 12, c + Vector2(cos(a), sin(a)) * 21, main.darkened(0.15), 3.0, true)
			draw_circle(c, 11, accent)
			draw_circle(c, 7, main)
		"crown":
			var base := c + Vector2(0, 6)
			var pts := PackedVector2Array([base + Vector2(-22, 8), base + Vector2(-22, -10), base + Vector2(-11, 0), base + Vector2(0, -18),
				base + Vector2(11, 0), base + Vector2(22, -10), base + Vector2(22, 8)])
			draw_colored_polygon(pts, main)
			draw_polyline(pts + PackedVector2Array([pts[0]]), accent, 2.0, true)
			for p: Vector2 in [base + Vector2(-22, -12), base + Vector2(0, -20), base + Vector2(22, -12)]:
				draw_circle(p, 3.5, accent)
		_:
			pass
	# Pips: one to four diamonds under the crest.
	var y := c.y + 22
	var start := c.x - (pips - 1) * 9.0
	for i in pips:
		var p := Vector2(start + i * 18.0, y)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), ink.lightened(0.15) if pips == 1 else main.darkened(0.25))
