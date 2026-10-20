class_name BattleReportPanel
extends PanelContainer
## After a raid (Military.finish) or a fight at a bandit camp
## (Military.finish_camp), or against a noble house's host (Phase 5.3): who
## won, what it cost and brought, each of yours (who struck down raiders,
## who fell, who died) and the men other houses sent.

signal closed

var _title: Label
var _body: VBoxContainer
var _ok: Button


func _init() -> void:
	custom_minimum_size = Vector2(560, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	_title = UITheme.label("", 24, UITheme.ACCENT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	root.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 340
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


func show_report(r: Dictionary) -> void:
	visible = true
	_ok.grab_focus.call_deferred()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var won := bool(r.get("won", false))
	var camp := bool(r.get("camp", false))
	var host := bool(r.get("host", false))
	if camp:
		_title.text = "The camp is taken" if won else "Beaten off at the camp"
	elif host:
		_title.text = "The host is beaten back" if won else "The host has its way"
	else:
		_title.text = "Victory" if won else "Defeat"
	_title.add_theme_color_override("font_color", UITheme.GOOD if won else UITheme.BAD)
	var band := str(r.get("band", "the raiders"))
	_body.add_child(_wrap("%s%s: %d of %d %s fell." % ["The camp of " if camp else "", band if camp else Military._cap(band), int(r.get("raiders_fallen", 0)), int(r.get("size", 0)), "of the band" if camp else ("of its men" if host else "raiders")], 16, UITheme.TEXT))
	if won and host:
		_body.add_child(_wrap("Ransom for their fallen knights: %d gold. Renown +%d. They'll keep the peace." % [int(r.get("gold", 0)), int(r.get("renown", 0))], 15, UITheme.GOOD))
	elif host:
		_body.add_child(_wrap("They took %d gold, and the realm thinks less of your house (renown %d)." % [-int(r.get("gold", 0)), int(r.get("renown", 0))], 15, UITheme.BAD))
	elif won and camp:
		_body.add_child(_wrap("Their hoard and purses: %d gold. Renown +%d. The band is no more." % [int(r.get("gold", 0)), int(r.get("renown", 0))], 15, UITheme.GOOD))
		var grateful: Array = r.get("grateful", [])
		if not grateful.is_empty():
			_body.add_child(_wrap("Grateful to you: %s." % ", ".join(grateful), 14, UITheme.GOOD))
	elif won:
		_body.add_child(_wrap("Their purse: %d gold. Renown +%d." % [int(r.get("gold", 0)), int(r.get("renown", 0))], 15, UITheme.GOOD))
	elif camp:
		_body.add_child(_wrap("They hold their camp, and grow bolder.", 15, UITheme.BAD))
	else:
		_body.add_child(_wrap("They took %d gold and %d food, and the village is shaken." % [-int(r.get("gold", 0)), -int(r.get("food", 0))], 15, UITheme.BAD))
	_body.add_child(HSeparator.new())
	var ours: Array = r.get("ours", [])
	if ours.is_empty():
		_body.add_child(_wrap("No one stood against them.", 14, UITheme.TEXT_DIM))
	for l: Dictionary in ours:
		var fate := "stood"
		var color := UITheme.TEXT
		var c := Military.section("combat")
		if l["died"]:
			fate = "died of %s wounds" % ("her" if str(l.get("gender", "")) == "female" else "his")
			color = UITheme.BAD
		elif l["wounded"]:
			fate = "fell wounded (resting %d days)" % int(c.get("wounded_days", 10))
			color = UITheme.ACCENT
		var felled := int(l["felled"])
		var deeds := "" if felled == 0 else "  -  struck down %d" % felled
		_body.add_child(_wrap("%s (%s): %s%s" % [l["name"], l["role"], fate, deeds], 14, color))
	for a: Dictionary in r.get("allies", []):
		var fell := int(a["fell"])
		_body.add_child(_wrap("Men-at-arms of %s: %d fought beside you%s." % [a["house"], int(a["men"]), "" if fell == 0 else ", %d fell" % fell], 14, UITheme.TEXT_DIM))
	_body.add_child(HSeparator.new())
	_body.add_child(_wrap("Those who fought and stood grew in Combat. Look at your fighters with the Eye: the gifted grow fastest.", 13, UITheme.TEXT_DIM))


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	return l
