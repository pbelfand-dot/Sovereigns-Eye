class_name SoundSettings
extends VBoxContainer
## Volume sliders for the four audio buses (see the Audio autoload). Changes
## apply at once and are saved.

const LABELS := {"Music": "Music", "Ambience": "Ambience", "SFX": "Effects", "UI": "Interface"}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(UITheme.label("Sound", 17, UITheme.ACCENT, true))
	for bus: String in LABELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		var name_label := UITheme.label(LABELS[bus], 15)
		name_label.custom_minimum_size.x = 90
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.name = bus
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Audio.level(bus)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.x = 160
		slider.value_changed.connect(func(v: float) -> void: Audio.set_level(bus, v))
		if bus == "UI" or bus == "SFX":
			slider.drag_ended.connect(func(_changed: bool) -> void: Audio.play("ui_click" if bus == "UI" else "coins"))
		row.add_child(slider)
