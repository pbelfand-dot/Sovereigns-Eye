class_name VisitPanel
extends PanelContainer
## At a noble house's seat (Phase 5.2, Realm): the welcome; gifts and a talk
## with the lord or lady; the house's young, each seen with the Eye if you
## choose (their gifts, current and potential); a hand asked for your heir
## or kin (once a visit; the wedding when you're home); a kin child left to
## be fostered. Then you take your leave (`closed`).

signal closed

var world: VillageWorld
var _title: Label
var _sub: Label
var _welcome: Label
var _regard: Label
var _body: VBoxContainer
var _log: VBoxContainer
var _leave: Button


func _init() -> void:
	custom_minimum_size = Vector2(700, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_title = UITheme.label("", 26, UITheme.ACCENT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)
	_sub = UITheme.label("", 15, UITheme.TEXT_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_sub)
	root.add_child(HSeparator.new())
	_welcome = _wrap("", 15, UITheme.TEXT)
	root.add_child(_welcome)
	_regard = UITheme.label("", 15, UITheme.TEXT)
	root.add_child(_regard)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 400
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	root.add_child(_log)
	_leave = UITheme.button("Take your leave", func() -> void:
		visible = false
		closed.emit())
	_leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_leave)


## At the seat: the welcome (Realm.arrive).
func open(welcome: String) -> void:
	visible = true
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	_welcome.text = welcome
	_refresh()
	_leave.grab_focus.call_deferred()


func _refresh() -> void:
	var st := world.state
	var h := Realm.at_seat(st)
	if h.is_empty():
		return
	_title.text = str(h["seat"])
	_sub.text = "%s  -  %s" % [st.realm.house_title(int(h["id"])), h["head"]]
	var regard := int(h["standing"])
	_regard.text = "They are %s toward your house (%+d).   Your gold: %d" % [MatchSystem.standing_word(regard), regard, st.house.gold]
	_regard.add_theme_color_override("font_color", UITheme.GOOD if regard >= 10 else (UITheme.BAD if regard <= -10 else UITheme.TEXT))
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	# Gifts and a talk.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_body.add_child(row)
	for gold: Variant in Realm.section("regard").get("gifts", [25, 75, 150]):
		var g := int(gold)
		var b := UITheme.button("Gifts: %d gold" % g, func() -> void: _did(Realm.give_gift(st, g), "coins"))
		b.disabled = Realm.did(st, "gift") or st.house.gold < g
		b.tooltip_text = "Once a visit. The more you give, the warmer they are (up to a point)."
		row.add_child(b)
	var talk := UITheme.button("Speak with %s" % str(h["head"]).get_slice(" ", 0) + " " + str(h["head"]).get_slice(" ", 1), func() -> void: _did(Realm.speak(st), "ui_select"))
	talk.disabled = Realm.did(st, "talk")
	talk.tooltip_text = "Your Politics carries a talk; a clumsy word cools them."
	row.add_child(talk)
	# The young of the house.
	var young := st.realm.household(int(h["id"]))
	_body.add_child(UITheme.label("The young of House %s" % h["name"], 17, UITheme.GOLD, true))
	if young.is_empty():
		_body.add_child(_wrap("There are no young at the seat just now.", 14, UITheme.TEXT_DIM))
	var partners := Realm.hand_partners(st)
	for c in young:
		_body.add_child(_member_row(st, h, c, partners))
	# Fostering.
	var kids := Realm.foster_candidates(st)
	if not kids.is_empty() and not Realm.did(st, "foster"):
		var attr := str(GameData.attribute_def(Realm.known_for_attribute(h)).get("name", ""))
		_body.add_child(UITheme.label("Fostering", 17, UITheme.GOLD, true))
		_body.add_child(_wrap("Leave a child of your house here until %d: they learn %s, and the house is honoured." % [int(Realm.section("fostering").get("return_age", 16)), attr], 14, UITheme.TEXT))
		var frow := HBoxContainer.new()
		frow.add_theme_constant_override("separation", 6)
		var pick := OptionButton.new()
		for k in kids:
			pick.add_item("%s (%d, %s %d)" % [k.full_name(), k.age, attr, k.get_current(Realm.known_for_attribute(h))], k.id)
		frow.add_child(pick)
		frow.add_child(UITheme.button("Leave them here", func() -> void:
			var r := Realm.foster(st, pick.get_selected_id())
			if r["ok"]:
				world.apply_life_events([{"text": "", "away": [int(r["away"])]}])
			_did(r, "ui_select")))
		_body.add_child(frow)


func _member_row(st: WorldState, h: Dictionary, c: CharacterData, partners: Array[CharacterData]) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG_ROW, UITheme.GOLD_DIM, 1, 4, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	box.add_child(v)
	var kin := "daughter" if c.gender == "female" else "son"
	var traits := ", ".join(c.traits.map(func(t: String) -> String: return str(GameData.trait_def(t).get("name", t)).to_lower()))
	v.add_child(UITheme.label("%s, %d  -  a %s of the house%s" % [c.full_name(), c.age, kin, ("  (%s)" % traits) if not traits.is_empty() else ""], 15, UITheme.TEXT))
	if c.appraised:
		var attrs: Array = Array(GameData.attribute_ids())
		attrs.sort_custom(func(a: String, b: String) -> bool: return c.get_potential(a) > c.get_potential(b))
		for a: String in attrs.slice(0, 3):
			var l := UITheme.label("  " + Appraisal.format_attribute(c, a), 14, Appraisal.rank_color(c.get_potential(a)))
			v.add_child(l)
	else:
		var eye := UITheme.button("Look with the Eye", func() -> void:
			Realm.look(st, c.id)
			Audio.play("eye_bell_great" if Appraisal.is_exceptional(c) else "eye_bell_small")
			if Appraisal.is_exceptional(c):
				var best := c.best_attribute()
				Game.notify.emit("Exceptional talent! %s - %s %s" % [c.full_name(), GameData.attribute_def(best).get("name", best), Appraisal.rank_id(c.get_potential(best))], Game.COLOR_TALENT)
			_refresh())
		eye.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		eye.tooltip_text = "See what no one else can: what they are, and what they could become."
		v.add_child(eye)
	var fits := partners.filter(func(p: CharacterData) -> bool: return MatchSystem.can_wed(st, p, c)["ok"])
	if not fits.is_empty() and not Realm.did(st, "hand"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var pick := OptionButton.new()
		for p: CharacterData in fits:
			pick.add_item("for you" if st.is_player(p) else "for %s (%d)" % [p.full_name(), p.age], p.id)
		row.add_child(pick)
		row.add_child(UITheme.button("Ask for %s hand" % ("her" if c.gender == "female" else "his"), func() -> void:
			var r := Realm.ask_hand(st, c.id, pick.get_selected_id())
			_did(r, "ui_select")
			for reason: Dictionary in (r.get("reasons", []) as Array).slice(0, 4):
				_note(("+ " if reason["good"] else "- ") + str(reason["text"]), UITheme.GOOD if reason["good"] else UITheme.BAD)))
		v.add_child(row)
	return box


func _did(r: Dictionary, sound: String) -> void:
	if not str(r.get("text", "")).is_empty():
		_note(str(r["text"]), UITheme.TEXT if r.get("ok", false) else UITheme.BAD)
	Audio.play(sound if r.get("ok", false) else "ui_error")
	_refresh()


func _note(text: String, color: Color) -> void:
	_log.add_child(_wrap(text, 14, color))
	while _log.get_child_count() > 6:
		var old := _log.get_child(0)
		_log.remove_child(old)
		old.queue_free()


func _wrap(text: String, size_px: int, color: Color) -> Label:
	var l := UITheme.label(text, size_px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 660
	return l
