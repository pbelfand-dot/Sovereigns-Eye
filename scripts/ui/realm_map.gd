class_name RealmMap
extends Control
## The realm drawn on parchment (Phase 5.2): the village at the heart, the
## noble houses' seats out along their roads (a ring in the colour of their
## regard), the bandit camps in the woods, the warband on the march. Woods,
## hills and a river are drawn from the seed, the same each time. Click a
## place to choose it.

signal picked(kind: String, id: int)

const PAPER := Color("#dcc89f")
const PAPER_DARK := Color("#b89a68")
const INK := Color("#4a3320")
const ROAD := Color("#7a5532")
const WOODS := Color("#5f6b3a")
const HILLS := Color("#8a6a45")
const RIVER := Color("#5f8296")
const CAMP := Color("#8c3b2e")
const HOUSE_COLORS := [Color("#3f5f8a"), Color("#7a3f6e"), Color("#3f7a55"), Color("#8a6a2a"), Color("#5a4a8a"), Color("#8a4a3a")]

var state: WorldState
## {kind ("village", "house", "camp"), id}
var selected: Dictionary = {"kind": "village", "id": 0}
var _hover: Dictionary = {}
var _art: Dictionary = {}
## Where names and icons already are this drawing (screen rects), and the page.
var _taken: Array[Rect2] = []
var _page := Rect2()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## Map units -> pixels (the map kept whole and centred).
func _scale() -> float:
	var m := Realm.map_cfg()
	return minf(size.x / float(m.get("width", 1000)), size.y / float(m.get("height", 640)))


func _offset() -> Vector2:
	var m := Realm.map_cfg()
	return (size - Vector2(float(m.get("width", 1000)), float(m.get("height", 640))) * _scale()) * 0.5


func to_screen(p: Vector2) -> Vector2:
	return _offset() + p * _scale()


## Everything you can click: [{kind, id, pos (map)}].
func places() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"kind": "village", "id": 0, "pos": Realm.center()}]
	if state == null:
		return out
	for h in state.realm.houses:
		if h.has("pos"):
			out.append({"kind": "house", "id": int(h["id"]), "pos": Realm.pos_of(h)})
	for c in Military.known_camps(state):
		out.append({"kind": "camp", "id": int(c["id"]), "pos": Realm.pos_of(c)})
	return out


func _place_at(screen: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 26.0
	for p in places():
		var d := to_screen(p["pos"]).distance_to(screen)
		if d < best_d:
			best_d = d
			best = p
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p := _place_at(event.position)
		if p.get("kind", "") != _hover.get("kind", "") or p.get("id", -1) != _hover.get("id", -1):
			_hover = p
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not p.is_empty() else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _place_at(event.position)
		if not p.is_empty():
			select(str(p["kind"]), int(p["id"]))
			accept_event()


func select(kind: String, id: int) -> void:
	selected = {"kind": kind, "id": id}
	Audio.play("ui_tick")
	queue_redraw()
	picked.emit(kind, id)


# --- The art (from the seed) ---------------------------------------------------------------------

func _make_art() -> void:
	var rng := Seeds.rng(state.world_seed if state else 0, "realm_map_art")
	var m := Realm.map_cfg()
	var w := float(m.get("width", 1000))
	var h := float(m.get("height", 640))
	var keep: Array[Vector2] = []
	for p in places():
		keep.append(p["pos"])
	var clear_of := func(p: Vector2, r: float) -> bool:
		for k in keep:
			if k.distance_to(p) < r:
				return false
		return true
	var trees: Array = []
	for i in 46:
		var c := Vector2(rng.randf_range(20, w - 20), rng.randf_range(20, h - 20))
		for j in rng.randi_range(4, 11):
			var t := c + Vector2(rng.randf_range(-26, 26), rng.randf_range(-16, 16))
			if clear_of.call(t, 34.0):
				trees.append(t)
	var hills: Array = []
	for i in 22:
		var c := Vector2(rng.randf_range(30, w - 30), rng.randf_range(30, h - 30))
		if clear_of.call(c, 40.0):
			hills.append([c, rng.randf_range(9, 17)])
	# A river from one edge to the other, wandering, passing near the village.
	var river: PackedVector2Array = []
	var y := rng.randf_range(h * 0.2, h * 0.8)
	var x := -10.0
	var heart := Realm.center()
	while x < w + 10.0:
		var pull := (heart.y + 34.0 - y) * 0.05 if absf(x - heart.x) < 220.0 else 0.0
		y = clampf(y + rng.randf_range(-14, 14) + pull, 20.0, h - 20.0)
		river.append(Vector2(x, y))
		x += rng.randf_range(24, 40)
	var bends := {}
	for p in places():
		if p["kind"] == "house":
			bends[p["id"]] = rng.randf_range(-0.25, 0.25)
	_art = {"trees": trees, "hills": hills, "river": river, "bends": bends}


func _road(from: Vector2, to: Vector2, bend: float) -> PackedVector2Array:
	var mid := (from + to) * 0.5
	var normal := (to - from).orthogonal().normalized()
	var ctrl := mid + normal * from.distance_to(to) * bend
	var pts := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		pts.append(from.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t))
	return pts


func _dashed(pts: PackedVector2Array, color: Color, width: float, on: float, off: float) -> void:
	var carry := 0.0
	var drawing := true
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var pos := 0.0
		while pos < seg:
			var left := (on if drawing else off) - carry
			var step := minf(left, seg - pos)
			if drawing:
				draw_line(a.lerp(b, pos / seg), a.lerp(b, (pos + step) / seg), color, width, true)
			pos += step
			carry += step
			if carry >= (on if drawing else off) - 0.001:
				carry = 0.0
				drawing = not drawing


func _text(text: String, at: Vector2, size_px: int, color: Color, heading: bool = false) -> void:
	var font := UITheme.heading_font() if heading else UITheme.body_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var p := at - Vector2(width * 0.5, 0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(PAPER, 0.85))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


## The sides of a place facing away from the village, nearest first.
func _away(p: Vector2, heart: Vector2) -> Array[Vector2]:
	var out := (p - heart).normalized()
	var sides: Array[Vector2] = [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2.LEFT]
	sides.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.dot(out) > b.dot(out))
	return sides


## A block of lines ([text, size, color, heading]) beside a place (an icon of
## radius r at p): on the first of `sides` where it covers no other name,
## icon or road and stays on the page (else on the first).
func _label(p: Vector2, r: float, lines: Array, sides: Array[Vector2], roads: Array) -> void:
	var size_of := _block_size(lines)
	var best := Rect2()
	for i in sides.size():
		var d := sides[i]
		var c := p + d * (r + 5.0) + Vector2(d.x * size_of.x, d.y * size_of.y) * 0.5
		var rect := Rect2(c - size_of * 0.5, size_of)
		if i == 0 or _free(rect, roads):
			best = rect
		if _free(rect, roads):
			break
	_draw_block(best, lines)


## A road's length beside it, near its middle, where there's room.
func _road_label(pts: PackedVector2Array, text: String, size_px: int, roads: Array) -> void:
	var lines := [[text, size_px, Color(INK, 0.75), false]]
	var size_of := _block_size(lines)
	var first := Rect2()
	for t: float in [0.5, 0.42, 0.58, 0.34, 0.66]:
		var i := roundi(t * (pts.size() - 1))
		var normal := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).orthogonal().normalized()
		for side: float in [-1.0, 1.0]:
			var c := pts[i] + normal * side * (8.0 + size_of.length() * 0.5)
			var rect := Rect2(c - size_of * 0.5, size_of)
			if first.size == Vector2.ZERO:
				first = rect
			if _free(rect, roads):
				_draw_block(rect, lines)
				return
	_draw_block(first, lines)


func _block_size(lines: Array) -> Vector2:
	var out := Vector2.ZERO
	for l: Array in lines:
		var font := UITheme.heading_font() if l[3] else UITheme.body_font()
		out.x = maxf(out.x, font.get_string_size(str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(l[1])).x)
		out.y += font.get_height(int(l[1]))
	return out + Vector2(4.0, 0.0)


func _draw_block(rect: Rect2, lines: Array) -> void:
	_taken.append(rect.grow(2.0))
	var y := rect.position.y
	for l: Array in lines:
		var font := UITheme.heading_font() if l[3] else UITheme.body_font()
		y += font.get_ascent(int(l[1]))
		_text(str(l[0]), Vector2(rect.get_center().x, y), int(l[1]), l[2], l[3])
		y += font.get_descent(int(l[1]))


## Clear of the names and icons already placed and of every road, on the page.
func _free(rect: Rect2, roads: Array) -> bool:
	if not _page.encloses(rect):
		return false
	for t in _taken:
		if t.intersects(rect):
			return false
	for pts: PackedVector2Array in roads:
		for i in range(1, pts.size()):
			for k in 4:
				if rect.has_point(pts[i - 1].lerp(pts[i], k / 4.0)):
					return false
	return true


func _draw() -> void:
	if state == null:
		return
	if _art.is_empty():
		_make_art()
	var s := _scale()
	var m := Realm.map_cfg()
	var page := Rect2(_offset(), Vector2(float(m.get("width", 1000)), float(m.get("height", 640))) * s)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#14100c"))
	draw_rect(page, PAPER)
	for i in 10:
		draw_rect(page.grow(-i * 4.0), Color(PAPER_DARK, 0.12 - i * 0.011), false, 4.0)
	# The land.
	var river: PackedVector2Array = _art["river"]
	var rv := PackedVector2Array()
	for p in river:
		rv.append(to_screen(p))
	draw_polyline(rv, Color(RIVER, 0.8), maxf(2.0, 5.0 * s), true)
	for hdef: Array in _art["hills"]:
		var c := to_screen(hdef[0])
		var r := float(hdef[1]) * s
		draw_arc(c, r, PI, TAU, 10, HILLS, maxf(1.0, 2.0 * s), true)
		draw_arc(c + Vector2(r * 0.9, r * 0.3), r * 0.6, PI, TAU, 8, Color(HILLS, 0.7), maxf(1.0, 1.6 * s), true)
	for t: Vector2 in _art["trees"]:
		var p := to_screen(t)
		var k := 5.0 * s
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -k * 1.6), p + Vector2(-k, k * 0.4), p + Vector2(k, k * 0.4)]), Color(WOODS, 0.85))
		draw_line(p + Vector2(0, k * 0.4), p + Vector2(0, k * 0.9), Color(INK, 0.6), 1.0)
	var heart := to_screen(Realm.center())
	# Roads to the seats, tracks to the camps.
	var roads := {}
	for h in state.realm.houses:
		if not h.has("pos"):
			continue
		var road := _road(Realm.center(), Realm.pos_of(h), float((_art["bends"] as Dictionary).get(int(h["id"]), 0.0)))
		var pts := PackedVector2Array()
		for p in road:
			pts.append(to_screen(p))
		roads[int(h["id"])] = pts
		_dashed(pts, ROAD, maxf(1.5, 3.0 * s), 10.0 * s, 6.0 * s)
	var lines: Array = roads.values()
	for c in Military.known_camps(state):
		var pts := PackedVector2Array([heart, to_screen(Realm.pos_of(c))])
		_dashed(pts, Color(CAMP, 0.55), maxf(1.0, 2.0 * s), 3.0 * s, 5.0 * s)
		lines.append(pts)
	# The places, and room kept round them for the names.
	_page = page.grow(-8.0)
	_taken.clear()
	var village_r := 26.0 * maxf(s, 0.8)
	var seat_r := 22.0 * maxf(s, 0.8)
	var camp_r := 15.0 * maxf(s, 0.8)
	_taken.append(Rect2(heart - Vector2.ONE * village_r, Vector2.ONE * village_r * 2.0))
	_village(heart)
	for h in state.realm.houses:
		if h.has("pos"):
			var p := to_screen(Realm.pos_of(h))
			_taken.append(Rect2(p - Vector2.ONE * seat_r, Vector2.ONE * seat_r * 2.0))
			_seat(p, HOUSE_COLORS[(int(h["id"]) - 1) % HOUSE_COLORS.size()], int(h["standing"]))
	for c in Military.known_camps(state):
		var p := to_screen(Realm.pos_of(c))
		_taken.append(Rect2(p - Vector2.ONE * camp_r, Vector2.ONE * camp_r * 2.0))
		_tent(p, s)
	# The names: each on the side away from the village if it's clear of
	# the others, the icons and the roads; the road's length beside its middle.
	var big := maxi(14, roundi(17 * s))
	var name_px := maxi(13, roundi(16 * s))
	var small := maxi(11, roundi(13 * s))
	_label(heart, village_r, [[state.village_name, big, INK, true]], [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2.LEFT], lines)
	for h in state.realm.houses:
		if h.has("pos"):
			var p := to_screen(Realm.pos_of(h))
			_label(p, seat_r, [[str(h["seat"]), name_px, INK, true], ["House %s" % h["name"], small, Color(INK, 0.8), false]], _away(p, heart), lines)
	for c in Military.known_camps(state):
		var p := to_screen(Realm.pos_of(c))
		_label(p, camp_r, [[Military._cap(str(c["band"])), small, CAMP, false]], [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT], lines)
	for h in state.realm.houses:
		if roads.has(int(h["id"])):
			_road_label(roads[int(h["id"])], Realm.days_text(int(h["days"])).replace("'s ride", "").replace("' ride", ""), small, lines)
	# On the roads: the warband on the march, a noble house's host, your carts.
	var x := state.military.expedition
	if not x.is_empty():
		var camp := state.military.get_camp(int(x["camp"]))
		if not camp.is_empty():
			var day := float(state.day())
			var t := clampf((day - float(x["depart"])) / maxf(1.0, float(x["fight"]) - float(x["depart"])), 0.0, 1.0)
			if day > float(x["fight"]):
				t = clampf(1.0 - (day - float(x["fight"])) / maxf(1.0, float(x["back"]) - float(x["fight"])), 0.0, 1.0)
			_banner(heart.lerp(to_screen(Realm.pos_of(camp)), clampf(t, 0.2, 0.8)), UITheme.GOLD)
	var raid := state.military.raid
	var host := state.realm.get_house(int(raid.get("host", -1))) if not raid.is_empty() else {}
	if not host.is_empty() and roads.has(int(host["id"])):
		var span := float(Realm.section("hosts").get("days_to_pay", 4))
		var t := clampf((float(raid["day"]) - float(state.day())) / maxf(1.0, span), 0.0, 1.0) * 0.6 + 0.2
		var pts: PackedVector2Array = roads[int(host["id"])]
		_banner(pts[roundi(t * (pts.size() - 1))], UITheme.BAD)
	for cart: Dictionary in Trade.on_road(state):
		if not roads.has(int(cart["house"])):
			continue
		var day := float(state.day())
		var t := clampf((day - float(cart["set_out"])) / maxf(1.0, float(cart["arrive"]) - float(cart["set_out"])), 0.0, 1.0)
		if str(cart["stage"]) == "home":
			t = clampf((float(cart["back"]) - day) / maxf(1.0, float(cart["back"]) - float(cart["arrive"])), 0.0, 1.0)
		var pts: PackedVector2Array = roads[int(cart["house"])]
		_cart(pts[roundi(clampf(t, 0.25, 0.75) * (pts.size() - 1))], s)
	_compass(page.position + Vector2(page.size.x - 42, 46), s)
	for sel: Dictionary in [_hover, selected]:
		if sel.is_empty():
			continue
		for p in places():
			if p["kind"] == sel["kind"] and int(p["id"]) == int(sel["id"]):
				draw_arc(to_screen(p["pos"]), 30.0 * maxf(s, 0.8), 0, TAU, 40, UITheme.GOLD if sel == selected else Color(UITheme.GOLD, 0.45), 3.0 if sel == selected else 2.0, true)


func _village(p: Vector2) -> void:
	var k := 9.0 * maxf(_scale(), 0.8)
	for off: Vector2 in [Vector2(-k * 1.2, k * 0.3), Vector2(k * 1.1, k * 0.4), Vector2(0, -k * 0.5)]:
		var b := p + off
		draw_rect(Rect2(b + Vector2(-k * 0.7, -k * 0.2), Vector2(k * 1.4, k)), Color("#9c6b43"))
		draw_colored_polygon(PackedVector2Array([b + Vector2(-k * 0.9, -k * 0.2), b + Vector2(0, -k * 1.1), b + Vector2(k * 0.9, -k * 0.2)]), Color("#7a3b2a"))
		draw_rect(Rect2(b + Vector2(-k * 0.7, -k * 0.2), Vector2(k * 1.4, k)), INK, false, 1.0)


func _seat(p: Vector2, color: Color, regard: int) -> void:
	var k := 11.0 * maxf(_scale(), 0.8)
	var ring := UITheme.GOOD if regard >= 10 else (UITheme.BAD if regard <= -10 else UITheme.NEUTRAL)
	draw_circle(p, k * 2.0, Color(PAPER, 0.9))
	draw_arc(p, k * 2.0, 0, TAU, 36, ring, 3.0, true)
	var body := Rect2(p + Vector2(-k, -k * 0.6), Vector2(k * 2.0, k * 1.6))
	draw_rect(body, color)
	for i in 3:
		draw_rect(Rect2(p + Vector2(-k + i * k * 0.8, -k * 1.0), Vector2(k * 0.45, k * 0.45)), color)
	draw_rect(Rect2(p + Vector2(-k * 0.25, k * 0.3), Vector2(k * 0.5, k * 0.7)), INK)
	draw_rect(body, INK, false, 1.2)


func _tent(p: Vector2, s: float) -> void:
	var k := 10.0 * maxf(s, 0.8)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-k, k * 0.7), p + Vector2(0, -k), p + Vector2(k, k * 0.7)]), CAMP)
	draw_polyline(PackedVector2Array([p + Vector2(-k, k * 0.7), p + Vector2(0, -k), p + Vector2(k, k * 0.7), p + Vector2(-k, k * 0.7)]), INK, 1.2, true)
	draw_line(p + Vector2(0, -k), p + Vector2(0, k * 0.7), INK, 1.0)
	draw_circle(p + Vector2(k * 1.5, k * 0.5), k * 0.3, Color("#e08a2a"))


func _banner(p: Vector2, color: Color) -> void:
	draw_line(p + Vector2(0, 10), p + Vector2(0, -16), INK, 2.0)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -16), p + Vector2(16, -12), p + Vector2(0, -6)]), color)


## A cart: its bed, the load under a cloth, two wheels and the shafts.
func _cart(p: Vector2, s: float) -> void:
	var k := 9.0 * maxf(s, 0.8)
	draw_rect(Rect2(p + Vector2(-k * 0.8, -k * 1.5), Vector2(k * 1.6, k * 0.7)), Color("#e6d8bd"))
	var bed := Rect2(p + Vector2(-k, -k * 0.9), Vector2(k * 2.0, k * 0.8))
	draw_rect(bed, Color("#9c6b43"))
	draw_rect(bed, INK, false, 1.2)
	draw_line(p + Vector2(k, -k * 0.5), p + Vector2(k * 1.8, -k * 0.2), INK, 1.5)
	for wx: float in [-k * 0.55, k * 0.55]:
		draw_circle(p + Vector2(wx, 0), k * 0.4, INK)
		draw_circle(p + Vector2(wx, 0), k * 0.18, PAPER)


func _compass(p: Vector2, s: float) -> void:
	var k := 16.0
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -k), p + Vector2(k * 0.3, 0), p + Vector2(0, k * 0.4), p + Vector2(-k * 0.3, 0)]), INK)
	draw_circle(p, 3.0, PAPER)
	_text("N", p + Vector2(0, -k - 4), 15, INK, true)
