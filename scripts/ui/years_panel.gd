class_name YearsPanel
extends PanelContainer
## Letting the years pass (VillageWorld.pass_time): the days turning while it
## runs, then what happened (Succession.summary): the dates, why it stopped
## early if it did, the village's numbers before and after, and the news.

signal closed

var _title: Label
var _progress: Label
var _body: VBoxContainer
var _ok: Button


func _init() -> void:
	custom_minimum_size = Vector2(560, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_title = UITheme.label("The years pass", 24, UITheme.ACCENT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	root.add_child(HSeparator.new())
	_progress = UITheme.label("", 16, UITheme.TEXT)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_progress)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 320
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)
	_ok = UITheme.button("Continue", func() -> void:
		visible = false
		closed.emit())
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_ok)


## While the days turn: `done` of `total`, and today's date.
func show_progress(done: int, total: int, minutes: int) -> void:
	visible = true
	_ok.visible = false
	_title.text = "The years pass"
	_progress.text = "%s   (%d of %d days)" % [Calendar.format_date(minutes), done, total]
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


## What happened (Succession.summary).
func show_summary(s: Dictionary) -> void:
	visible = true
	_ok.visible = true
	_ok.grab_focus.call_deferred()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var from := Calendar.format_date(int(s["from_day"]) * Calendar.MINUTES_PER_DAY)
	var to := Calendar.format_date(int(s["to_day"]) * Calendar.MINUTES_PER_DAY)
	var days := int(s["days"])
	if days == Calendar.days_per_year():
		_title.text = "A year passes"
	elif days == Calendar.days_per_season():
		_title.text = "A season passes"
	else:
		_title.text = "%d days pass" % days if days != 1 else "A day passes"
	_progress.text = "%s  to  %s" % [from, to]
	if not str(s["stop_text"]).is_empty():
		_body.add_child(_wrap("Stopped early: %s" % s["stop_text"], 15, UITheme.BAD if str(s["stop"]) in ["kin_death", "succession", "health", "ended"] else UITheme.ACCENT))
	var c: Dictionary = s["counts"]
	_body.add_child(_wrap("People %d -> %d   Gold %d -> %d   Renown %d -> %d" % [s["people"][0], s["people"][1], s["gold"][0], s["gold"][1], s["renown"][0], s["renown"][1]], 15, UITheme.ACCENT))
	_body.add_child(_wrap("Born %d, died %d, left %d, weddings %d, settlers %d" % [c.get("born", 0), c.get("died", 0), c.get("left", 0), c.get("wed", 0), c.get("arrived", 0)], 14, UITheme.TEXT))
	_body.add_child(HSeparator.new())
	var lines: Array = s["lines"]
	if lines.is_empty():
		_body.add_child(_wrap("The days pass quietly.", 14, UITheme.TEXT_DIM))
	for i in mini(lines.size(), 24):
		_body.add_child(_wrap(str(lines[i]), 14, UITheme.TEXT))
	if lines.size() > 24:
		_body.add_child(_wrap("... and %d more (the Court panel's chronicle keeps the rest)." % (lines.size() - 24), 13, UITheme.TEXT_DIM))


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	return l
