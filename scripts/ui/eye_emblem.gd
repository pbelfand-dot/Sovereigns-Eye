class_name EyeEmblem
extends Control
## The Sovereign's Eye, drawn (no image files): a ring of notches, rays, and
## an almond eye whose lids open to show a slit-pupilled iris. Tier colors and
## a spinning rune ring for the rarest reveals. All animation is driven from
## outside through the properties below.

var main := Color("#e9bf62")
var accent := Color("#2c3e7a")
var glow_color := Color("#fff1c4")
## 0 closed .. 1 wide open
var open := 0.0:
	set(v):
		open = v
		queue_redraw()
## 0..1 strength of the halo and rays
var glow := 0.0:
	set(v):
		glow = v
		queue_redraw()
var rays := 0.0:
	set(v):
		rays = v
		queue_redraw()
## Radians the rune ring has turned.
var ring_angle := 0.0:
	set(v):
		ring_angle = v
		queue_redraw()
## Legendary: diamond runes on the ring and a second, counter-turning ring.
var ornate := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_colors(colors: Dictionary) -> void:
	main = Color(str(colors.get("main", "#e9bf62")))
	accent = Color(str(colors.get("accent", "#2c3e7a")))
	glow_color = Color(str(colors.get("glow", "#fff1c4")))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.45
	# Halo
	for i in 7:
		draw_circle(c, r * (0.55 + i * 0.11), Color(glow_color, 0.035 * glow))
	# Rays
	if rays > 0.01:
		for k in 24:
			var a := k * TAU / 24.0 + ring_angle * 0.25
			var d := Vector2(cos(a), sin(a))
			var long := 1.18 if k % 2 == 0 else 1.05
			draw_line(c + d * r * 0.78, c + d * r * long, Color(main, 0.45 * rays), 2.5 if k % 2 == 0 else 1.5, true)
	# Rune ring
	draw_arc(c, r * 0.92, 0, TAU, 72, Color(main, 0.9), 3.0, true)
	draw_arc(c, r * 0.8, 0, TAU, 72, Color(main, 0.5), 1.5, true)
	for k in 24:
		var a := k * TAU / 24.0 + ring_angle
		var d := Vector2(cos(a), sin(a))
		if ornate and k % 3 == 0:
			var p := c + d * r * 0.86
			var t := Vector2(-d.y, d.x)
			draw_colored_polygon(PackedVector2Array([p + d * 7, p + t * 4, p - d * 7, p - t * 4]), main)
		else:
			draw_line(c + d * r * 0.83, c + d * r * 0.9, Color(main, 0.8), 2.0, true)
	if ornate:
		for k in 12:
			var a := k * TAU / 12.0 - ring_angle * 1.6
			var d := Vector2(cos(a), sin(a))
			draw_circle(c + d * r * 0.98, 3.0, accent.lightened(0.3))
	# The eye: almond lids
	var w := r * 0.72
	var up := PackedVector2Array()
	var low := PackedVector2Array()
	for i in 33:
		var t := lerpf(-1.0, 1.0, i / 32.0)
		var curve := pow(maxf(1.0 - t * t, 0.0), 0.85)
		up.append(c + Vector2(t * w, -r * 0.42 * open * curve))
		low.append(c + Vector2(t * w, r * 0.34 * open * curve))
	var shape := PackedVector2Array(up)
	for i in range(low.size() - 1, -1, -1):
		shape.append(low[i])
	if open > 0.02:
		draw_colored_polygon(shape, Color("#120d09"))
		# Iris, squashed by the lids, with a slit pupil.
		var squash := clampf(open * 1.25, 0.0, 1.0)
		var ir := r * 0.26
		for ring in 4:
			var rr := ir * (1.0 - ring * 0.2)
			var col := accent.lerp(main, ring / 3.0)
			draw_set_transform(c, 0.0, Vector2(1.0, squash))
			draw_circle(Vector2.ZERO, rr, col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_set_transform(c, 0.0, Vector2(0.28, squash))
		draw_circle(Vector2.ZERO, ir * 0.72, Color("#08060a"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if open > 0.5:
			draw_circle(c + Vector2(-ir * 0.35, -ir * 0.35 * squash), ir * 0.12, Color(1, 1, 1, 0.8 * (open - 0.5) * 2.0))
	draw_polyline(up, main, 3.0, true)
	draw_polyline(low, main, 3.0, true)
	# Lashes / lid marks on the upper lid.
	for k in 7:
		var i := 6 + k * 3
		var p := up[i]
		var n := (p - c).normalized()
		draw_line(p, p + n * (6.0 + 6.0 * open), Color(main, 0.8), 2.0, true)
