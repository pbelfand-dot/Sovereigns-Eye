class_name EyeEmblem
extends Control
## The Sovereign's Eye, drawn in code (no image files) like an illuminated
## roundel: a gold sunburst, a tooled ring, and an eye whose lids part on a
## slit of light to show an ivory eye, a fibred iris and a pupil that
## narrows as it focuses. The ring grows richer with the tier: plain notches,
## a beaded edge, the legend OCVLVS PRINCIPIS OMNIA VIDET ("the ruler's eye
## sees all"), and for the rarest a second ring of jewels turning the other
## way. All animation is driven from outside through the properties below.

const LEGEND := ["OCVLVS", "PRINCIPIS", "OMNIA", "VIDET"]

var main := Color("#e9bf62")
var accent := Color("#2c3e7a")
var glow_color := Color("#fff1c4")
## 0 closed .. 1 wide open
var open := 0.0:
	set(v):
		open = v
		queue_redraw()
## 0..1 strength of the halo and the light in the lids' slit
var glow := 0.0:
	set(v):
		glow = v
		queue_redraw()
## 0..1 strength of the sunburst
var rays := 0.0:
	set(v):
		rays = v
		queue_redraw()
## 0..1: the pupil narrows as the Eye focuses.
var focus := 0.0:
	set(v):
		focus = v
		queue_redraw()
## Radians the ring has turned.
var ring_angle := 0.0:
	set(v):
		ring_angle = v
		queue_redraw()
## How rich the ring is: 0 notches, 1 beaded, 2 the legend, 3 the legend and
## a ring of jewels (one step per tier).
var ornament := 0:
	set(v):
		ornament = v
		queue_redraw()

static var _halo_tex: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_colors(colors: Dictionary) -> void:
	main = Color(str(colors.get("main", "#e9bf62")))
	accent = Color(str(colors.get("accent", "#2c3e7a")))
	glow_color = Color(str(colors.get("glow", "#fff1c4")))
	queue_redraw()


## A soft white disc fading to nothing, shared by every emblem.
static func halo_texture() -> GradientTexture2D:
	if _halo_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_halo_tex = GradientTexture2D.new()
		_halo_tex.gradient = g
		_halo_tex.fill = GradientTexture2D.FILL_RADIAL
		_halo_tex.fill_from = Vector2(0.5, 0.5)
		_halo_tex.fill_to = Vector2(1.0, 0.5)
		_halo_tex.width = 128
		_halo_tex.height = 128
	return _halo_tex


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.45
	if glow > 0.01:
		draw_texture_rect(halo_texture(), Rect2(c - Vector2.ONE * r * 1.45, Vector2.ONE * r * 2.9), false, Color(glow_color, 0.55 * glow))
	if rays > 0.01:
		_draw_sunburst(c, r)
	_draw_ring(c, r)
	_draw_eye(c, r)


## Tapering gold rays, long and short by turns, fading to their tips.
func _draw_sunburst(c: Vector2, r: float) -> void:
	for k in 32:
		var a := k * TAU / 32.0 + ring_angle * 0.25
		var long := k % 2 == 0
		var half := deg_to_rad(2.4 if long else 1.5)
		var reach := r * (1.3 if long else 1.12)
		var base := r * 0.93
		var col := Color(main, 0.6 * rays)
		draw_polygon(PackedVector2Array([c + Vector2.from_angle(a - half) * base, c + Vector2.from_angle(a) * reach, c + Vector2.from_angle(a + half) * base]),
			PackedColorArray([col, Color(main, 0.0), col]))


func _draw_ring(c: Vector2, r: float) -> void:
	var bed := accent.darkened(0.55)
	draw_arc(c, r * 0.875, 0, TAU, 96, Color(bed, 0.92), r * 0.15, true)
	draw_arc(c, r * 0.95, 0, TAU, 96, main, 3.0, true)
	draw_arc(c, r * 0.80, 0, TAU, 96, main, 2.0, true)
	draw_arc(c, r * 0.765, 0, TAU, 96, Color(main, 0.45), 1.0, true)
	if ornament >= 1:
		for k in 48:
			draw_circle(c + Vector2.from_angle(k * TAU / 48.0 + ring_angle) * r * 0.99, 2.2, main)
	if ornament >= 2:
		_draw_legend(c, r * 0.875)
	else:
		for k in 24:
			var d := Vector2.from_angle(k * TAU / 24.0 + ring_angle)
			draw_line(c + d * r * 0.83, c + d * r * 0.92, Color(main, 0.85), 2.0, true)
	if ornament >= 3:
		for k in 12:
			var d := Vector2.from_angle(k * TAU / 12.0 - ring_angle * 1.6)
			var p := c + d * r * 1.06
			var t := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([p + d * 7, p + t * 4, p - d * 7, p - t * 4]), main)
			draw_circle(p, 2.2, accent.lightened(0.35))


## The legend around the ring, reading clockwise from the top, its letters
## spaced out evenly around the whole ring like a seal's, its words parted
## by small crosses.
func _draw_legend(c: Vector2, radius: float) -> void:
	var font := UITheme.heading_font()
	var px := 19
	var parting := px * 1.7
	var widths := []
	var text_len := 0.0
	var letters := 0
	for word: String in LEGEND:
		var ws := []
		for ch in word:
			var w := font.get_char_size(ch.unicode_at(0), px).x
			ws.append(w)
			text_len += w
			letters += 1
		widths.append(ws)
	var track := maxf((TAU * radius - text_len - parting * LEGEND.size()) / letters, 0.0)
	# A cross at the top, as a seal's legend begins, then each word.
	var a := -PI * 0.5 + ring_angle - (parting * 0.5) / radius
	var lift := font.get_ascent(px) * 0.36
	for i in LEGEND.size():
		var cm := a + (parting * 0.5) / radius
		draw_set_transform(c + Vector2.from_angle(cm) * radius, cm + PI * 0.5, Vector2.ONE)
		var s := px * 0.28
		draw_line(Vector2(-s, 0), Vector2(s, 0), main, 2.0, true)
		draw_line(Vector2(0, -s), Vector2(0, s), main, 2.0, true)
		a += (parting + track * 0.5) / radius
		var word: String = LEGEND[i]
		for k in word.length():
			var w: float = widths[i][k]
			var mid := a + (w * 0.5) / radius
			draw_set_transform(c + Vector2.from_angle(mid) * radius, mid + PI * 0.5, Vector2.ONE)
			draw_char(font, Vector2(-w * 0.5, lift), word[k], px, main)
			a += (w + (track if k < word.length() - 1 else track * 0.5)) / radius
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_eye(c: Vector2, r: float) -> void:
	var w := r * 0.66
	var up := PackedVector2Array()
	var low := PackedVector2Array()
	var crease := PackedVector2Array()
	for i in 41:
		var t := lerpf(-1.0, 1.0, i / 40.0)
		var k := maxf(1.0 - t * t, 0.0)
		up.append(c + Vector2(t * w, -r * 0.40 * open * pow(k, 0.8)))
		low.append(c + Vector2(t * w, r * 0.30 * open * pow(k, 0.95)))
		crease.append(c + Vector2(t * w * 0.94, -r * (0.08 + 0.40 * open) * pow(k, 0.7) - r * 0.06 * k))
	if open > 0.03:
		var almond := PackedVector2Array(up)
		for i in range(low.size() - 1, -1, -1):
			almond.append(low[i])
		_draw_eyeball(c, r, almond, up, low)
	# The slit of light before the lids part, fading as they open.
	var slit := glow * clampf(1.0 - open * 2.5, 0.0, 1.0)
	if slit > 0.01:
		var line := PackedVector2Array([c + Vector2(-w, 0), c + Vector2(w, 0)])
		draw_polyline(line, Color(glow_color, 0.35 * slit), 10.0, true)
		draw_polyline(line, Color(glow_color, 0.9 * slit), 3.0, true)
	# Lids in gold: the opening's rim, a crease above, lashes.
	draw_polyline(crease, Color(main, 0.55 + 0.25 * open), 1.6, true)
	draw_polyline(up, main, 3.5, true)
	draw_polyline(low, main, 2.5, true)
	for k in 9:
		var i := 6 + k * 3
		var p := up[i]
		var t := lerpf(-1.0, 1.0, i / 40.0)
		var out := (p - c).normalized().rotated(t * 0.45)
		var side := Vector2(-out.y, out.x) * 1.4
		var tip := p + out * (7.0 + 7.0 * open)
		draw_colored_polygon(PackedVector2Array([p - side, tip, p + side]), Color(main, 0.9))


## The eye inside the lids: ivory, the iris with its fibres and rings, the
## pupil, the shadow of the upper lid and two catchlights, all clipped to
## the opening.
func _draw_eyeball(c: Vector2, r: float, almond: PackedVector2Array, up: PackedVector2Array, low: PackedVector2Array) -> void:
	# Ivory, lit from within while the lids are still parting.
	draw_colored_polygon(almond, Color("#eadfc6").lerp(glow_color.lightened(0.4), glow * clampf(1.0 - open * 1.4, 0.0, 0.8)))
	var ir := r * 0.25
	var iris_c := c + Vector2(0, -r * 0.01)
	_fill_clipped(_circle(iris_c, ir, 40), almond, accent.lerp(main, 0.3))
	_fill_clipped(_circle(iris_c, ir * 0.78, 40), almond, accent.lerp(main, 0.55))
	var pr := ir * lerpf(0.6, 0.34, clampf(focus, 0.0, 1.0))
	for k in 64:
		var a := k * TAU / 64.0
		var light := k % 2 == 0
		var from := iris_c + Vector2.from_angle(a + 0.03) * pr * 1.05
		var to := iris_c + Vector2.from_angle(a - 0.02) * ir * (0.93 if light else 0.85)
		var col := Color(main.lightened(0.3), 0.6) if light else Color(accent.darkened(0.35), 0.55)
		for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([from, to]), almond):
			draw_polyline(seg, col, 1.3, true)
	# The collarette: a wavy ring of light around the pupil.
	var wave := PackedVector2Array()
	for k in 49:
		var a := k * TAU / 48.0
		wave.append(iris_c + Vector2.from_angle(a) * pr * (1.55 + 0.12 * sin(a * 12.0)))
	for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(wave, almond):
		draw_polyline(seg, Color(glow_color, 0.55), 1.4, true)
	# The dark limbal ring at the iris' edge.
	var rim := _circle(iris_c, ir, 48)
	rim.append(rim[0])
	for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(rim, almond):
		draw_polyline(seg, accent.darkened(0.6), 2.6, true)
	_fill_clipped(_circle(iris_c, pr, 32), almond, Color("#070508"))
	# The upper lid's shadow across the top of the eye.
	var shade := PackedVector2Array()
	var cols := PackedColorArray()
	for i in up.size():
		shade.append(up[i])
		cols.append(Color(0.1, 0.06, 0.03, 0.55))
	for i in range(up.size() - 1, -1, -1):
		shade.append(up[i].lerp(low[i], 0.32))
		cols.append(Color(0.1, 0.06, 0.03, 0.0))
	draw_polygon(shade, cols)
	if open > 0.35:
		var a := clampf((open - 0.35) * 2.5, 0.0, 1.0)
		var spot := iris_c + Vector2(-ir * 0.36, -ir * 0.30)
		if Geometry2D.is_point_in_polygon(spot, almond):
			draw_circle(spot, ir * 0.15, Color(1, 1, 1, 0.85 * a))
		var dot := iris_c + Vector2(ir * 0.3, ir * 0.26)
		if Geometry2D.is_point_in_polygon(dot, almond):
			draw_circle(dot, ir * 0.06, Color(1, 1, 1, 0.6 * a))


func _fill_clipped(shape: PackedVector2Array, clip: PackedVector2Array, col: Color) -> void:
	for poly: PackedVector2Array in Geometry2D.intersect_polygons(shape, clip):
		if poly.size() >= 3:
			draw_colored_polygon(poly, col)


static func _circle(at: Vector2, radius: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		out.append(at + Vector2.from_angle(k * TAU / n) * radius)
	return out
