class_name StatBar
extends Control
## Two-layer bar: solid = current ability, translucent = untapped potential.
## Faint ticks mark the rank thresholds (D, C, B, A, S, S+, SS), so the gap
## between what someone IS and what they COULD BE is visible at a glance.

var current := 0
var potential := 0
var max_value := 160.0
var color := Color.WHITE


func setup(cur: int, pot: int, bar_color: Color, scale_max: float = 160.0) -> void:
	current = cur
	potential = pot
	color = bar_color
	max_value = maxf(scale_max, float(pot))
	queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(120, 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#120d09"))
	if potential >= 0:
		var pw := size.x * clampf(potential / max_value, 0.0, 1.0)
		draw_rect(Rect2(0, 0, pw, size.y), Color(color, 0.28))
		draw_rect(Rect2(pw - 2, 0, 2, size.y), Color(color, 0.9))
	var cw := size.x * clampf(current / max_value, 0.0, 1.0)
	draw_rect(Rect2(0, 2, cw, size.y - 4), color.lightened(0.1))
	for rank: Dictionary in GameData.ranks():
		var v := float(rank["min"])
		if v <= 0.0 or v >= max_value:
			continue
		var x := size.x * v / max_value
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.12), 1.0)
	draw_rect(r, Color("#4a3a2a"), false, 1.0)
