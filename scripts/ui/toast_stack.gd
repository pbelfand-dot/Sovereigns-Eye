class_name ToastStack
extends VBoxContainer
## Short notifications that fade out ("Game saved", "Exceptional talent
## discovered!"). Listens to Game.notify.

const LIFETIME := 4.5
## Long messages wrap at this width so they never run under the character
## card on the right (GameUI keeps the stack left of it).
const MAX_TEXT_WIDTH := 600.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 6)
	Game.notify.connect(show_toast)


func _exit_tree() -> void:
	if Game.notify.is_connected(show_toast):
		Game.notify.disconnect(show_toast)


func show_toast(text: String, color: Color = UITheme.TEXT) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", UITheme.box(Color("#1c1510ee"), color.darkened(0.2), 2, 6, 10))
	var l := UITheme.label(text, 17, color, true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := UITheme.heading_font()
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > MAX_TEXT_WIDTH:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = MAX_TEXT_WIDTH
	panel.add_child(l)
	add_child(panel)
	while get_child_count() > 4:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var tw := panel.create_tween()
	tw.tween_interval(LIFETIME)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(panel.queue_free)
