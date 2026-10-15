class_name NegotiationPanel
extends PanelContainer
## Face to face with someone the heir walked up to.
##
## What they say comes first (their talk may hint at a gift). Then you can
## ask about their life to learn what they want (Recruitment motives, told
## in words, never numbers), and build an offer from real things: a daily
## wage paid from the treasury, a free home or a promise of one, a place
## (household, training, an office, a workplace with room, a squire's
## place) and an appeal to their duty. They answer yes, with a
## counteroffer, or no, and say why.

signal eye_requested(character_id: int)
signal farewell

const LINE_GAP := 0.6
const WIDTH := 860.0

var world: VillageWorld
var character: CharacterData
var offer: Dictionary = {"wage": 2, "home": -1, "position": "household", "appeal": false}
var counter: Dictionary = {}

var _title: Label
var _opinion: Label
var _log: VBoxContainer
var _scroll: ScrollContainer
var _known: VBoxContainer
var _offer_box: VBoxContainer
var _wage_label: Label
var _home_opt: OptionButton
var _pos_opt: OptionButton
var _appeal: CheckBox
var _treasury: Label
var _propose: Button
var _agree: Button
var _ask: Button
var _make: Button
## Why no offer can be made (only for you, your family, small children).
var _blocked: Label
var _gift: Button
var _eye: Button
var _homes: Array[int] = []
var _positions: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _next_in := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UITheme.box(Color("#1c1510f4"), UITheme.GOLD, 2, 8, 12))


func _ready() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_title = UITheme.label("", 18, UITheme.ACCENT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_opinion = UITheme.label("", 14, UITheme.TEXT_DIM)
	head.add_child(_opinion)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 12)
	col.add_child(mid)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(WIDTH * 0.58, 170)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(_scroll)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 3)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_log)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UITheme.box(Color("#2a2018c0"), UITheme.GOLD_DIM, 1, 6, 8))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(right)
	_known = VBoxContainer.new()
	_known.add_theme_constant_override("separation", 2)
	right.add_child(_known)

	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", 4)
	_offer_box.visible = false
	col.add_child(_offer_box)
	_build_offer_box()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	_ask = UITheme.button("Ask about their life", _on_ask)
	_ask.tooltip_text = "They tell you what matters to them, most important first."
	row.add_child(_ask)
	_make = UITheme.button("Make an offer...", _on_make)
	row.add_child(_make)
	_gift = UITheme.button("Gift", _on_gift)
	row.add_child(_gift)
	_eye = UITheme.button("Sovereign's Eye", func() -> void:
		if character:
			eye_requested.emit(character.id))
	row.add_child(_eye)
	row.add_child(UITheme.button("Farewell", farewell.emit))
	_blocked = UITheme.label("", 14, UITheme.TEXT_DIM)
	_blocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_blocked.visible = false
	col.add_child(_blocked)


func _build_offer_box() -> void:
	_offer_box.add_child(HSeparator.new())
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 8)
	_offer_box.add_child(line1)
	line1.add_child(UITheme.label("Wage", 15))
	line1.add_child(UITheme.button("-", func() -> void: _set_wage(int(offer.get("wage", 0)) - 1)))
	_wage_label = UITheme.label("", 15, UITheme.ACCENT)
	_wage_label.custom_minimum_size.x = 120
	_wage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line1.add_child(_wage_label)
	line1.add_child(UITheme.button("+", func() -> void: _set_wage(int(offer.get("wage", 0)) + 1)))
	var sp := Control.new()
	sp.custom_minimum_size.x = 16
	line1.add_child(sp)
	line1.add_child(UITheme.label("Home", 15))
	_home_opt = OptionButton.new()
	_home_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_opt.item_selected.connect(func(i: int) -> void:
		offer["home"] = _homes[i]
		_offer_changed())
	line1.add_child(_home_opt)

	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 8)
	_offer_box.add_child(line2)
	line2.add_child(UITheme.label("Place", 15))
	_pos_opt = OptionButton.new()
	_pos_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pos_opt.item_selected.connect(func(i: int) -> void:
		for k: String in ["position", "focus", "office", "workplace"]:
			offer.erase(k)
		offer.merge(_positions[i]["fields"], true)
		_offer_changed())
	line2.add_child(_pos_opt)
	_appeal = CheckBox.new()
	_appeal.text = "Appeal to their duty and honour"
	_appeal.add_theme_font_size_override("font_size", 15)
	_appeal.toggled.connect(func(on: bool) -> void:
		offer["appeal"] = on
		_offer_changed())
	line2.add_child(_appeal)

	var line3 := HBoxContainer.new()
	line3.add_theme_constant_override("separation", 8)
	_offer_box.add_child(line3)
	_treasury = UITheme.label("", 13, UITheme.TEXT_DIM)
	_treasury.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_treasury.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line3.add_child(_treasury)
	_agree = UITheme.button("Agree to their terms", _on_agree)
	_agree.visible = false
	line3.add_child(_agree)
	_propose = UITheme.button("Propose", _on_propose)
	line3.add_child(_propose)


## Opens for a conversation: {lines, first, opinion} from Discovery.meet.
func open(owner_world: VillageWorld, c: CharacterData, result: Dictionary) -> void:
	world = owner_world
	character = c
	counter = {}
	if c.retainer:
		offer = Recruitment.current_terms(world.state, c)
	else:
		offer = {"wage": Recruitment.wage_need(Recruitment.decider(world.state, c)), "home": -1, "position": "household", "appeal": false}
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	_queue.clear()
	for l: String in result.get("lines", []):
		_queue.append({"text": l})
	if not str(result.get("opinion", "")).is_empty():
		_queue.append({"text": str(result["opinion"]), "kind": "note"})
	_next_in = 0.0
	_offer_box.visible = false
	_agree.visible = false
	visible = true
	refresh()
	_ask.grab_focus.call_deferred()


## Re-reads everything (after a gift, an answer, a new day...).
func refresh() -> void:
	if character == null or world == null:
		return
	var st := world.state
	var c := character
	_title.text = "%s, %s" % [c.display_name(), c.occupation_name().to_lower()]
	var op := roundi(c.player_opinion)
	_opinion.text = "Opinion of you: %s (%+d)" % [CourtSystem.opinion_label(c.player_opinion), op]
	_opinion.add_theme_color_override("font_color", UITheme.opinion_color(op))
	_eye.text = "Look again (%s)" % world.key_hint("sovereign_eye") if c.appraised else "Sovereign's Eye (%s)" % world.key_hint("sovereign_eye")
	var gift := CourtSystem.can_gift(st, c)
	_gift.text = "Gift (%d gold)" % CourtSystem.gift_cost(c)
	_gift.disabled = not gift["ok"]
	_gift.tooltip_text = str(gift["reason"]) if not gift["ok"] else "A gift raises their opinion of you (more for the greedy)."
	# An offer can always be made, except to yourself, your own family and
	# small children; then the panel says why.
	var can := Recruitment.can_offer(st, c)
	_make.disabled = not can["ok"]
	_make.text = "Offer new terms..." if c.retainer else "Make an offer..."
	_make.tooltip_text = str(can["reason"]) if not can["ok"] else ("Change the terms they serve on: wage, home, place." if c.retainer else "Offer them a place in your house.")
	_blocked.text = str(can["reason"])
	_blocked.visible = not can["ok"]
	if not can["ok"]:
		_offer_box.visible = false
	_refresh_known()
	if _offer_box.visible:
		_refresh_offer()


func _refresh_known() -> void:
	for child in _known.get_children():
		_known.remove_child(child)
		child.queue_free()
	var st := world.state
	var who := Recruitment.decider(st, character)
	_known.add_child(UITheme.label("What you know they want", 15, UITheme.ACCENT, true))
	if who != character:
		_known.add_child(_wrap("%s decides for %s." % [who.full_name(), character.first_name], 13, UITheme.TEXT_DIM))
	if character.known_motives.is_empty():
		_known.add_child(_wrap("Nothing yet. Ask about their life.", 14, UITheme.TEXT_DIM))
	else:
		var weights := Recruitment.motives(st, who)
		for id: String in character.known_motives:
			var cost := id in ["ties", "risk"]
			_known.add_child(UITheme.label("•  " + Recruitment.motive_name(id), 15, UITheme.BAD if cost else UITheme.TEXT))
			var word := Recruitment.strength_word(float(weights.get(id, 0.0)))
			_known.add_child(UITheme.label("     " + ("holds them back %s" % word if cost else "matters %s" % word), 13, UITheme.TEXT_DIM))
	var more := Recruitment.ranked_motives(st, who).size() > character.known_motives.size()
	_ask.disabled = not more
	_ask.tooltip_text = "They tell you what matters to them, most important first." if more else "They've told you all there is."


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH * 0.34
	return l


# --- Talk log ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible or _queue.is_empty():
		return
	_next_in -= delta
	if _next_in <= 0.0:
		_show_next()


func _say(text: String, kind: String = "") -> void:
	_queue.append({"text": text, "kind": kind})
	if _queue.size() == 1:
		_next_in = 0.0


func _show_next() -> void:
	var item: Dictionary = _queue.pop_front()
	var text := str(item["text"])
	var kind := str(item.get("kind", ""))
	var color := UITheme.TEXT
	var size := 16
	match kind:
		"note":
			color = UITheme.TEXT_DIM
			size = 14
		"good":
			color = UITheme.GOOD
			size = 15
		"bad":
			color = UITheme.BAD
			size = 15
		"you":
			color = UITheme.ACCENT
			size = 15
		_:
			if text.begins_with("("):
				color = UITheme.TEXT_DIM
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH * 0.56
	l.modulate.a = 0.0
	_log.add_child(l)
	create_tween().tween_property(l, "modulate:a", 1.0, 0.2)
	_next_in = LINE_GAP if not kind in ["good", "bad"] else 0.15
	_scroll_down.call_deferred()


func _scroll_down() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Shows everything still waiting (clicking hurries the talk along).
func flush() -> void:
	while not _queue.is_empty():
		_show_next()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not _queue.is_empty():
		flush()


# --- Actions ---------------------------------------------------------------------------------

func _on_ask() -> void:
	var r := Recruitment.ask(world.state, character)
	_say("You ask about their life.", "you")
	_say(str(r["line"]))
	if not str(r["motive"]).is_empty():
		var who := Recruitment.decider(world.state, character)
		var w := float(Recruitment.motives(world.state, who).get(str(r["motive"]), 0.0))
		_say("(%s: %s)" % [Recruitment.motive_name(str(r["motive"])), "holds them back " + Recruitment.strength_word(w) if str(r["motive"]) in ["ties", "risk"] else "matters " + Recruitment.strength_word(w)], "note")
	Audio.play("ui_tick")
	refresh()


func _on_make() -> void:
	_offer_box.visible = not _offer_box.visible
	if _offer_box.visible:
		_refresh_offer()
		_propose.grab_focus.call_deferred()


func _on_gift() -> void:
	var result := CourtSystem.gift(world.state, character)
	Audio.play("coins" if bool(result.get("ok", true)) else "ui_error")
	_say(str(result.get("text", "")), "note")
	world.court_changed(character.id)
	refresh()


func _set_wage(w: int) -> void:
	offer["wage"] = clampi(w, 0, int(Recruitment.cfg().get("max_wage", 8)))
	_offer_changed()


func _offer_changed() -> void:
	counter = {}
	_agree.visible = false
	_refresh_offer()


## Fills the offer controls from the world as it is now: free homes, open
## offices and workplaces, and what the wage does to the treasury.
func _refresh_offer() -> void:
	var st := world.state
	var c := character
	var wage := int(offer.get("wage", 0))
	_wage_label.text = "%d gold a day" % wage if wage > 0 else "no wage"
	_home_opt.clear()
	_homes.clear()
	_add_home("No home", -1, false, "")
	_add_home("Rooms at the manor", Recruitment.MANOR_ROOMS, not Recruitment.manor_rooms_free(st), "There's no room left at the manor.")
	for b in Recruitment.available_homes(st):
		_add_home("%s (empty)" % b.name, b.id, false, "")
	var days := int(Recruitment.cfg().get("promises", {}).get("home_days", 6))
	_add_home("Promise a home within %d days" % days, Recruitment.PROMISE_HOME, false,
		"If no home is free by then, you break your word: they lose trust in you and others hear of it.")
	var hi := _homes.find(int(offer.get("home", -1)))
	if hi < 0 or _home_opt.is_item_disabled(hi):
		hi = 0
		offer["home"] = -1
	_home_opt.select(hi)

	_pos_opt.clear()
	_positions.clear()
	_add_pos("A place in your household", {"position": "household"}, "")
	for a: String in CourtSystem.TRAINABLE:
		_add_pos("Training in %s" % CourtSystem.attr_name(a), {"position": "training", "focus": a}, "")
	for o: Dictionary in CourtSystem.offices():
		var oid := str(o["id"])
		var holder := st.get_character(st.house.holder_of(oid))
		var why := ""
		if holder and holder != c:
			why = "Held by %s." % holder.first_name
		elif c.age < 16:
			why = "Too young to hold an office (16+)."
		_add_pos("Office: %s" % str(o["name"]), {"position": "office", "office": oid}, why)
	var shops := Recruitment.open_workplaces(st)
	var own := st.get_building(int(c.terms.get("workplace", -1))) if c.retainer else null
	if own and not shops.has(own):
		shops.insert(0, own)
	for b in shops:
		_add_pos("Workplace: %s" % b.name, {"position": "workplace", "workplace": b.id}, "")
	if shops.is_empty():
		_add_pos("Workplace: none with room (build a workshop)", {"position": "workplace", "workplace": -1}, "Every workplace already has two of your people. Build a workshop, smithy, quarry, bakery or mill.")
	var squire_why := ""
	if c.age < 14 or c.age > 30:
		squire_why = "Squires are 14 to 30 years old."
	elif c.is_knight():
		squire_why = "Already a knight."
	_add_pos("A squire's place", {"position": "squire"}, squire_why)
	var pi := 0
	for i in _positions.size():
		var f: Dictionary = _positions[i]["fields"]
		var same := true
		for k: String in f:
			same = same and offer.get(k, null) == f[k]
		if same and not _pos_opt.is_item_disabled(i):
			pi = i
			break
	_pos_opt.select(pi)
	for k: String in ["position", "focus", "office", "workplace"]:
		offer.erase(k)
	offer.merge(_positions[pi]["fields"], true)
	_appeal.set_pressed_no_signal(bool(offer.get("appeal", false)))

	var net := CourtSystem.daily_income(st) - CourtSystem.daily_wages(st)
	var now_paid := CourtSystem.wage(c) if c.retainer else 0
	var upkeep := 0 if c.retainer else CourtSystem.household_upkeep(st, 1) - CourtSystem.household_upkeep(st)
	var after := net - (wage - now_paid) - upkeep
	var text := "Treasury %d gold, %+d a day now; %+d a day with these terms." % [st.house.gold, net, after]
	if upkeep > 0:
		text += " Your household is beyond what your renown supports (%d): another place adds %d gold a day in upkeep." % [CourtSystem.retainer_cap(st), upkeep]
	_treasury.text = text + " Your word: %s." % Recruitment.standing_label(st.house.standing)
	var problem := Recruitment.offer_problem(st, c, offer)
	_propose.disabled = not problem.is_empty()
	_propose.tooltip_text = problem if not problem.is_empty() else ("Offer these terms. Better terms raise their loyalty; worse ones they'll turn down." if c.retainer else "Make this offer. They'll answer yes, with their own terms, or no: you can always improve it and ask again.")


func _add_home(text: String, id: int, disabled: bool, tip: String) -> void:
	_home_opt.add_item(text)
	var i := _home_opt.item_count - 1
	_home_opt.set_item_disabled(i, disabled)
	if not tip.is_empty():
		_home_opt.set_item_tooltip(i, tip)
	_homes.append(id)


func _add_pos(text: String, fields: Dictionary, why: String) -> void:
	_pos_opt.add_item(text)
	var i := _pos_opt.item_count - 1
	if not why.is_empty():
		_pos_opt.set_item_disabled(i, true)
		_pos_opt.set_item_tooltip(i, why)
	_positions.append({"fields": fields})


func _on_propose() -> void:
	var was_retainer := character.retainer
	_answer(Recruitment.propose(world.state, character, offer), was_retainer)


func _on_agree() -> void:
	if counter.is_empty():
		return
	offer = counter.duplicate()
	var was_retainer := character.retainer
	_answer(Recruitment.propose(world.state, character, offer), was_retainer)


func _answer(r: Dictionary, was_retainer: bool) -> void:
	flush()
	_say("You offer %s." % Recruitment.describe(world.state, offer), "you")
	_say(str(r["text"]), "note" if r["result"] == "invalid" else "")
	for reason: Dictionary in (r["reasons"] as Array).slice(0, 4):
		var good := bool(reason["good"])
		_say(("+ " if good else "– ") + str(reason["text"]), "good" if good else "bad")
	counter = r.get("counter", {})
	_agree.visible = not counter.is_empty()
	match str(r["result"]):
		"accept":
			Audio.play("court_good")
			_offer_box.visible = false
			if was_retainer:
				Game.notify.emit("%s now serves on new terms." % character.full_name(), Game.COLOR_GOOD)
			else:
				Game.notify.emit("%s swears service to %s." % [character.full_name(), CourtSystem.house_name(world.state)], Game.COLOR_GOOD)
			world.recruited(character.id)
		"counter":
			Audio.play("ui_tick")
			_agree.grab_focus.call_deferred()
		"refuse":
			# The door stays open: change the offer and propose again.
			Audio.play("court_bad")
			_say("(Change your offer and propose again.)", "note")
			world.court_changed(character.id)
		_:
			Audio.play("ui_error")
	refresh()
