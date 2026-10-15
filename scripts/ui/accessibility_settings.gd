class_name AccessibilitySettings
extends VBoxContainer
## Switches for motion, flashes and captions (saved in user://settings.cfg).

const OPTIONS := [
	["accessibility/reduced_motion", "Reduce motion", "No camera moves, shakes, spins or card flips; shorter reveals."],
	["accessibility/reduce_flashes", "Reduce flashes", "No bright flashes or strong light sweeps."],
	["accessibility/captions", "Captions for sound cues", "Short text for important sounds, like the Eye's bells."],
]


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	add_child(UITheme.label("Accessibility", 17, UITheme.ACCENT, true))
	for o: Array in OPTIONS:
		var cb := CheckBox.new()
		cb.text = str(o[1])
		cb.tooltip_text = str(o[2])
		cb.button_pressed = GameSettings.get_bool(str(o[0]))
		cb.add_theme_font_size_override("font_size", 15)
		var key := str(o[0])
		cb.toggled.connect(func(on: bool) -> void: GameSettings.set_bool(key, on))
		add_child(cb)
