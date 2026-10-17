class_name RevealCard
extends Control
## The card the Sovereign's Eye reveals. Back: tooled leather, an arched
## window where a silhouette can show, and a wax seal bearing the Eye on two
## ribbons (the same for everyone, so it gives nothing away); the seal
## cracks and light leaks through before the card turns. Front: parchment
## with a frame that grows richer with the person's tier, a crest and pips,
## their portrait in a lit niche, role, greatest gift, three strongest
## abilities, traits and overall promise.
##
## Tier is shown in several ways at once (never by color alone): the tier
## name, the crest shape (none / shield / sun / crown), the number of pips
## and the frame pattern (plain / single / double / filigree).

const SIZE := Vector2(380, 560)
## The back's window (a round-headed arch) and its seal.
const WINDOW := Rect2(100, 64, 180, 238)
const SEAL_AT := Vector2(190, 396)
const SEAL_RADIUS := 50.0
## The front's niche for the portrait (a round-headed arch).
const NICHE := Rect2(90, 82, 200, 214)
const LEATHER := Color("#4a2e1c")
const PARCHMENT := Color("#efe2c4")
const TOOLING := Color("#c9a77a")
const WAX := Color("#8e1b1b")
## Drawing the grain with a material's color times this gives that color on average.
const TINT := Color(1.14, 1.14, 1.14)

var tier: Dictionary = {}
var character: CharacterData
var face := "back":
	set(v):
		face = v
		_back.visible = v == "back"
		_front.visible = v == "front"
		_tier_label.visible = v == "front"
		_niche.visible = v == "front"
		queue_redraw()
var main := Color("#9a9488")
var accent := Color("#5e584e")
var ink := Color("#2b2219")
var glow := Color("#e8e0cc")
## 0..1: cracks spread across the seal, light leaking through them.
var crack := 0.0:
	set(v):
		crack = v
		queue_redraw()

var _back: Control
var _window: Control
var _front: VBoxContainer
var _niche: Control
var silhouette: TextureRect
var portrait: TextureRect
var _tier_label: Label
var _gift_name: Label
var stamp: Label
var _gift_value: Label
var _rows: Array[Dictionary] = []
var _traits: Label
var _overall: Label
var _sheen_layer: Control
var _sheen := 0.0

static var _textures := {}


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
	glow = Color(str(colors.get("glow", "#e8e0cc")))
	# Back: the window clips the silhouette to its arch.
	_back = Control.new()
	_back.size = SIZE
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	_window = Control.new()
	_window.position = WINDOW.position
	_window.size = WINDOW.size
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_window.draw.connect(_draw_window)
	_back.add_child(_window)
	silhouette = TextureRect.new()
	silhouette.texture = portrait_tex
	silhouette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	silhouette.size = Vector2(WINDOW.size.x, WINDOW.size.y - 8)
	silhouette.position = Vector2(0, 14)
	silhouette.modulate = Color(0, 0, 0, 0)
	silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(silhouette)
	# Front: the niche clips the portrait to its arch, lit from behind.
	_niche = Control.new()
	_niche.position = NICHE.position
	_niche.size = NICHE.size
	_niche.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_niche.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_niche.draw.connect(_draw_niche)
	add_child(_niche)
	portrait = TextureRect.new()
	portrait.texture = portrait_tex
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size = NICHE.size + Vector2(0, 6)
	portrait.position = Vector2(0, 4)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_niche.add_child(portrait)
	_tier_label = _label(str(tier.get("name", "")).to_upper(), 15, ink.lightened(0.15), true)
	_tier_label.position = Vector2(0, 56)
	_tier_label.size = Vector2(SIZE.x, 22)
	add_child(_tier_label)
	_front = VBoxContainer.new()
	_front.position = Vector2(26, NICHE.end.y + 6)
	_front.size = Vector2(SIZE.x - 52, SIZE.y - NICHE.end.y - 30)
	_front.add_theme_constant_override("separation", 4)
	_front.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_front)
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
	# The light sweeping across either face, over everything on it.
	_sheen_layer = Control.new()
	_sheen_layer.size = SIZE
	_sheen_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheen_layer.draw.connect(_draw_sheen)
	add_child(_sheen_layer)
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


## The silhouette fades in behind the window's glass, lit from behind.
func set_silhouette(a: float) -> void:
	silhouette.modulate = Color(0, 0, 0, a)
	_window.queue_redraw()


func set_sheen(v: float) -> void:
	_sheen = v
	_sheen_layer.queue_redraw()


# --- Textures (made once, shared) ---------------------------------------------------------

## Soft grain for leather and parchment: a fixed noise, so every card is
## the same. Light (about 0.88) with a little spread, to be tinted by
## drawing it with the material's color (see TINT).
static func grain(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var n := FastNoiseLite.new()
	n.seed = 1187
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.05 if kind == "leather" else 0.035
	n.fractal_octaves = 5 if kind == "leather" else 4
	n.fractal_gain = 0.5 if kind == "leather" else 0.6
	var data := n.get_image(190, 280).get_data()
	var spread := 0.36 if kind == "leather" else 0.11
	for i in data.size():
		data[i] = clampi(roundi(224.0 + (data[i] - 128.0) * spread), 0, 255)
	var tex := ImageTexture.create_from_image(Image.create_from_data(190, 280, false, Image.FORMAT_L8, data))
	_textures[kind] = tex
	return tex


## Edges falling into shadow (transparent in the middle).
static func edge_shade() -> Texture2D:
	if _textures.has("edge"):
		return _textures["edge"]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 1))
	g.set_offset(0, 0.55)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_SQUARE
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_textures["edge"] = tex
	return tex


## A round-headed arch filling `r`.
static func arch(r: Rect2, segments: int = 24) -> PackedVector2Array:
	var rad := r.size.x * 0.5
	var spring := r.position.y + rad
	var pts := PackedVector2Array([Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y)])
	for k in segments + 1:
		var a := lerpf(0.0, -PI, float(k) / segments)
		pts.append(Vector2(r.position.x + rad + cos(a) * rad, spring + sin(a) * rad))
	return pts


# --- Drawing ------------------------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	if face == "back":
		_draw_back(r)
	else:
		_draw_front(r)


func _draw_back(r: Rect2) -> void:
	draw_texture_rect(grain("leather"), r, false, LEATHER * TINT)
	draw_texture_rect(edge_shade(), r, false, Color(0.08, 0.04, 0.02, 0.55))
	# Blind tooling with gold lines and corner stamps, as on a binding.
	draw_rect(r.grow(-12), Color(TOOLING, 0.75), false, 1.5)
	draw_rect(r.grow(-17), Color("#24150c"), false, 2.0)
	draw_rect(r.grow(-21), Color(TOOLING, 0.55), false, 1.0)
	var inner := r.grow(-17)
	for p: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)]), TOOLING)
		draw_circle(p, 2.0, Color("#24150c"))
	var y := 32.0
	draw_string(UITheme.heading_font(), Vector2(0, y + 10), "SOVEREIGN'S EYE", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 14, TOOLING)
	# The window's frame: a dark reveal and a gold line round the arch.
	var frame := arch(WINDOW.grow(5))
	draw_colored_polygon(frame, Color("#24150c"))
	var outline := arch(WINDOW.grow(3))
	outline.append(outline[0])
	draw_polyline(outline, Color(TOOLING, 0.85), 1.5, true)
	_draw_ribbons()
	_draw_seal()


## The silk ribbons the seal hangs on, cut in swallowtails.
func _draw_ribbons() -> void:
	for side: float in [-1.0, 1.0]:
		var top := SEAL_AT + Vector2(side * 12, 10)
		var foot := SEAL_AT + Vector2(side * 46, 128)
		var along := (foot - top).normalized()
		var across := Vector2(-along.y, along.x) * 11.0
		var notch := foot - along * 12.0
		var tail := PackedVector2Array([top - across, top + across, foot + across, notch, foot - across])
		draw_colored_polygon(tail, Color("#5c1018"))
		draw_line(top + along * 4, notch - along * 4, Color("#8a2430"), 3.0, true)
		draw_polyline(tail + PackedVector2Array([tail[0]]), Color("#3a0a10"), 1.2, true)


func _draw_seal() -> void:
	var c := SEAL_AT
	# Wax spreads unevenly: a lumpy edge, a raised rim, the pressed face.
	var edge := PackedVector2Array()
	for k in 40:
		var a := k * TAU / 40.0
		edge.append(c + Vector2.from_angle(a) * SEAL_RADIUS * (1.0 + 0.05 * sin(a * 7.0 + 0.6) + 0.03 * sin(a * 13.0)))
	draw_colored_polygon(edge, WAX.darkened(0.25))
	draw_circle(c + Vector2(-1.5, -1.5), SEAL_RADIUS * 0.9, WAX)
	draw_circle(c, SEAL_RADIUS * 0.74, WAX.darkened(0.12))
	draw_arc(c, SEAL_RADIUS * 0.74, PI * 0.9, PI * 1.9, 24, WAX.lightened(0.25), 2.0, true)
	draw_arc(c, SEAL_RADIUS * 0.74, -PI * 0.1, PI * 0.9, 24, WAX.darkened(0.45), 2.0, true)
	# The Eye pressed into it: shadow below, light above, as an impression.
	for pass_i in 2:
		var off := Vector2(1.2, 1.2) if pass_i == 0 else Vector2(-0.8, -0.8)
		var col := WAX.darkened(0.5) if pass_i == 0 else WAX.lightened(0.28)
		var up := PackedVector2Array()
		var low := PackedVector2Array()
		for i in 17:
			var t := lerpf(-1.0, 1.0, i / 16.0)
			var k := pow(maxf(1.0 - t * t, 0.0), 0.85)
			up.append(c + off + Vector2(t * 26, -12 * k))
			low.append(c + off + Vector2(t * 26, 10 * k))
		draw_polyline(up, col, 2.5, true)
		draw_polyline(low, col, 2.5, true)
		draw_arc(c + off, 7.0, 0, TAU, 20, col, 2.0, true)
	draw_circle(c, 3.0, WAX.darkened(0.5))
	if crack > 0.0:
		_draw_cracks(c)


## Cracks run out from near the middle of the seal, wandering and forking;
## light leaks through them. The same cracks every time.
const CRACKS := [
	[0.35, [0.0, 0.14, -0.09, 0.2, 0.06, -0.12], [3, 0.5]],
	[1.45, [0.0, -0.11, 0.17, 0.04, -0.15, 0.09], []],
	[2.3, [0.0, 0.08, 0.21, -0.06, 0.13, -0.04], [2, -0.6]],
	[3.25, [0.0, -0.16, 0.05, -0.2, 0.1, 0.18], []],
	[4.15, [0.0, 0.12, -0.04, 0.16, -0.18, 0.07], [4, 0.45]],
	[5.3, [0.0, -0.07, 0.15, -0.13, 0.02, -0.1], []],
]


func _draw_cracks(c: Vector2) -> void:
	for crack_def: Array in CRACKS:
		var a: float = crack_def[0]
		var bends: Array = crack_def[1]
		var pts := PackedVector2Array()
		for k in bends.size():
			var r := SEAL_RADIUS * (0.1 + 0.155 * k * (1.0 + 0.06 * sin(a * 3.0 + k)))
			pts.append(c + Vector2.from_angle(a + float(bends[k]) * 0.55) * r)
		_draw_crack(_grown(pts, crack), 1.0)
		# A fork off one of its joints, shorter and finer.
		var fork: Array = crack_def[2]
		if not fork.is_empty() and crack > 0.4:
			var from := pts[int(fork[0])]
			var dir := Vector2.from_angle(a + float(fork[1]))
			var branch := PackedVector2Array([from, from + dir * 6.0 + dir.orthogonal() * 1.5, from + dir * 11.0])
			_draw_crack(_grown(branch, (crack - 0.4) / 0.6), 0.7)


## The part of a crack's path grown so far (`t` from 0 to 1).
static func _grown(pts: PackedVector2Array, t: float) -> PackedVector2Array:
	var reach := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var out := PackedVector2Array([pts[0]])
	for k in range(1, pts.size()):
		if reach >= k:
			out.append(pts[k])
		elif reach > k - 1:
			out.append(pts[k - 1].lerp(pts[k], reach - (k - 1)))
	return out


## A fissure: light glowing out of it, its bright core, and the wax's dark
## broken edge just below.
func _draw_crack(pts: PackedVector2Array, weight: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(glow, 0.2 * crack), 3.5 * weight, true)
	var edge := PackedVector2Array()
	for p in pts:
		edge.append(p + Vector2(0.6, 0.8))
	draw_polyline(edge, Color(WAX.darkened(0.6), 0.9), 1.3 * weight, true)
	draw_polyline(pts, Color(glow.lightened(0.5), 0.9 * crack), 1.1 * weight, true)


## Inside the window: a dark ground tooled with a gold lattice, as behind
## the figures in a manuscript, lit from behind once a silhouette shows.
func _draw_window() -> void:
	var r := Rect2(Vector2.ZERO, WINDOW.size)
	var shape := arch(r)
	var cols := PackedColorArray()
	for p in shape:
		cols.append(Color("#120a06").lerp(Color("#2a1a10"), clampf(p.y / r.size.y, 0.0, 1.0)))
	_window.draw_polygon(shape, cols)
	# Lines x - y = a * step and x + y = b * step; a dot in each diamond.
	var step := 22.0
	var line := Color(TOOLING, 0.2)
	var h := r.size.y
	for a in range(-ceili(h / step), ceili(r.size.x / step) + 1):
		var x0 := a * step
		for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + h, h)]), shape):
			_window.draw_polyline(seg, line, 1.0, true)
	for b in range(0, ceili((r.size.x + h) / step) + 1):
		var x0 := b * step
		for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 - h, h)]), shape):
			_window.draw_polyline(seg, line, 1.0, true)
	for j in ceili(2.0 * h / step) + 1:
		for i in ceili(2.0 * r.size.x / step) + 1:
			var p := Vector2(i, j) * step * 0.5
			if (i + j) % 2 == 1 and Geometry2D.is_point_in_polygon(p, shape):
				_window.draw_circle(p, 1.4, Color(TOOLING, 0.32))
	var lit := silhouette.modulate.a if silhouette else 0.0
	if lit > 0.0:
		var halo := EyeEmblem.halo_texture()
		_window.draw_texture_rect(halo, Rect2(r.get_center() - Vector2(150, 120), Vector2(300, 300)), false, Color(glow, 0.75 * lit))


func _draw_front(r: Rect2) -> void:
	draw_texture_rect(grain("parchment"), r, false, PARCHMENT * TINT)
	draw_texture_rect(edge_shade(), r, false, Color(0.45, 0.3, 0.14, 0.32))
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
	_crest(Vector2(SIZE.x * 0.5, 26))
	# The niche's frame, drawn round the arch the portrait sits in.
	var rim := arch(NICHE.grow(4))
	draw_colored_polygon(rim, main.darkened(0.15) if frame != "plain" else ink.lightened(0.35))
	var line := arch(NICHE.grow(1.5))
	line.append(line[0])
	draw_polyline(line, ink.lightened(0.1), 1.0, true)


## Inside the niche: a backdrop in the tier's colors, brightest behind the
## head, so the portrait reads as a lit miniature.
func _draw_niche() -> void:
	var r := Rect2(Vector2.ZERO, NICHE.size)
	var shape := arch(r)
	var cols := PackedColorArray()
	var top := glow.lerp(PARCHMENT, 0.25)
	var foot := accent.darkened(0.35)
	for p in shape:
		cols.append(top.lerp(foot, clampf(p.y / r.size.y, 0.0, 1.0) * 0.95))
	_niche.draw_polygon(shape, cols)
	_niche.draw_texture_rect(EyeEmblem.halo_texture(), Rect2(Vector2(r.size.x * 0.5 - 110, -40), Vector2(220, 220)), false, Color(glow.lightened(0.3), 0.8))


func _draw_sheen() -> void:
	if _sheen <= 0.0 or _sheen >= 1.0:
		return
	var sx := lerpf(-120.0, SIZE.x + 120.0, _sheen)
	var poly := PackedVector2Array([Vector2(sx - 40, 0), Vector2(sx + 10, 0), Vector2(sx - 70, SIZE.y), Vector2(sx - 120, SIZE.y)])
	_sheen_layer.draw_colored_polygon(poly, Color(1, 1, 1, 0.16))
	var core := PackedVector2Array([Vector2(sx - 18, 0), Vector2(sx - 6, 0), Vector2(sx - 86, SIZE.y), Vector2(sx - 98, SIZE.y)])
	_sheen_layer.draw_colored_polygon(core, Color(1, 1, 1, 0.22))


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
	var y := c.y + 20
	var start := c.x - (pips - 1) * 9.0
	for i in pips:
		var p := Vector2(start + i * 18.0, y)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), ink.lightened(0.15) if pips == 1 else main.darkened(0.25))
