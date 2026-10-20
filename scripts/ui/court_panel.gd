class_name CourtPanel
extends PanelContainer
## Your house at a glance: treasury, renown, offices, every retainer and what
## they are training, and the house chronicle. Click a name to open their card.

signal character_chosen(character_id: int)
signal close_requested

var world: VillageWorld
var _body: VBoxContainer
var _choosing_regent := false


func _init() -> void:
	custom_minimum_size = Vector2(540, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := UITheme.label("Your Court", 22, UITheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(UITheme.button("X", close_requested.emit))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	scroll.add_child(_body)


func refresh() -> void:
	if world == null or _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var st := world.state
	var h := st.house
	if h == null:
		return
	var player := st.player()

	_heading(CourtSystem.house_name(st))
	if player:
		var role := CourtSystem.role_name(st, player)
		_body.add_child(_person_button(player, "%s: %s (you), %d" % ["Heir" if role.begins_with("Heir") else role, player.full_name(), player.age]))
	_defence(st)
	_castle(st)
	_succession(st)
	_marriages(st)
	var income := CourtSystem.daily_income(st)
	var wages := CourtSystem.daily_wages(st)
	_body.add_child(UITheme.label("Gold %d   (income %d, wages %d: %+d per day)" % [h.gold, income, wages, income - wages], 15, UITheme.ACCENT))
	if h.in_debt:
		_body.add_child(_wrap("Your coffers are empty and wages go unpaid. Loyalty is falling every day.", 14, UITheme.BAD))
	_body.add_child(UITheme.label("Renown %d   -   Household %d / %d (more renown, more retainers)" % [h.renown, CourtSystem.retainer_count(st), CourtSystem.retainer_cap(st)], 15))
	var upkeep := CourtSystem.household_upkeep(st)
	if upkeep > 0:
		_body.add_child(_wrap("Your household is larger than your renown supports: %d gold a day in upkeep (in the wages above)." % upkeep, 14, UITheme.TEXT_DIM))

	_heading("Offices")
	for o: Dictionary in CourtSystem.offices():
		var oid := str(o["id"])
		var holder := st.get_character(h.holder_of(oid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := UITheme.label(str(o["name"]), 15, UITheme.ACCENT)
		name_l.custom_minimum_size.x = 120
		name_l.tooltip_text = str(o.get("description", ""))
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_l)
		if holder:
			var a := str(o.get("primary", ""))
			var b := _person_button(holder, "%s  -  %s now %d (%s)" % [holder.display_name(), CourtSystem.attr_name(a), holder.get_current(a), Appraisal.rank_id(holder.get_current(a))])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
		else:
			var v := UITheme.label("Vacant - appoint a retainer from their card", 14, UITheme.TEXT_DIM)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(v)
		_body.add_child(row)
		_body.add_child(_wrap("Effect: " + _office_effect(st, o, holder), 13, UITheme.TEXT_DIM))

	_heading("Household")
	var retainers := st.retainers()
	if retainers.is_empty():
		_body.add_child(_wrap("No one has sworn to you yet. Appraise villagers, find hidden talent, then open their card's Court tab and offer them a place.", 14, UITheme.TEXT_DIM))
	retainers.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.joined_day < b.joined_day)
	for c in retainers:
		var focus := CourtSystem.focus_of(c)
		var cur := c.get_current(focus)
		var pot := c.get_potential(focus)
		var pot_text := "%d (%s potential)" % [pot, Appraisal.rank_id(pot)] if c.appraised else "? (not seen with the Eye)"
		var text := "%s, %d  -  %s  -  %s %d/%s  -  loyalty %d" % [
			c.display_name(), c.age, CourtSystem.role_name(st, c), CourtSystem.attr_name(focus), cur, pot_text, roundi(c.loyalty)]
		var b := _person_button(c, text)
		if c.loyalty < float(CourtSystem.section("loyalty").get("warning_below", 30)):
			b.add_theme_color_override("font_color", UITheme.BAD)
		_body.add_child(b)

	_heading("Chronicle")
	var shown := 0
	for i in range(h.chronicle.size() - 1, -1, -1):
		var e: Dictionary = h.chronicle[i]
		var date := Calendar.format_date(int(e["day"]) * Calendar.MINUTES_PER_DAY)
		_body.add_child(_wrap("%s  -  %s" % [date, e["text"]], 13, _chronicle_color(str(e["kind"]))))
		shown += 1
		if shown >= 12:
			break


## Raiders on the way (pay them, call the levy), your captains' reckoning,
## and the warband with its wounded (Phase 5.1).
func _defence(st: WorldState) -> void:
	var m := st.military
	if m == null:
		return
	_heading("Defence")
	var raid := m.raid
	if world.battle:
		var s := world.battle.standing()
		var foe := "of the host" if raid.has("host") else "raiders"
		_body.add_child(_wrap("A fight is on! Yours standing %d, %s %d. Walk up to one of them and press %s to strike." % [s["ours"], foe, s["theirs"], world.key_hint("interact")], 15, UITheme.BAD))
	elif not raid.is_empty():
		var when := Calendar.format_date(int(raid["day"]) * Calendar.MINUTES_PER_DAY)
		var host := int(raid.get("host", -1))
		if host >= 0:
			_body.add_child(_wrap("%s, %d strong, comes by the %s road. It strikes on %s at %d o'clock unless you pay %s's demand." % [Military._cap(str(raid["name"])), int(raid["size"]), raid["road"], when, Military.strike_hour(), st.realm.house_title(host)], 15, UITheme.BAD))
		else:
			_body.add_child(_wrap("%s, %d strong, are camped by the %s road. They strike on %s at %d o'clock." % [Military._cap(str(raid["name"])), int(raid["size"]), raid["road"], when, Military.strike_hour()], 15, UITheme.BAD))
		var odds := Military.odds(st)
		_body.add_child(_wrap("Your captains reckon your chances %s.%s" % [Military.odds_word(odds), " (The levy is called.)" if raid.get("levy", false) else ""], 14, UITheme.GOOD if odds >= 0.65 else (UITheme.TEXT if odds >= 0.4 else UITheme.BAD)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var pay := UITheme.button(("Pay their demand (%d gold)" if raid.has("host") else "Pay them off (%d gold)") % int(raid["tribute"]), func() -> void:
			var r := Military.pay_off(st)
			Game.notify.emit(str(r["text"]), Game.COLOR_INFO if r["ok"] else Game.COLOR_BAD)
			Audio.play("coins" if r["ok"] else "ui_error")
			refresh())
		pay.disabled = st.house.gold < int(raid["tribute"])
		pay.tooltip_text = "You haven't the gold." if pay.disabled else ("Their host goes home, and they keep the peace awhile." if raid.has("host") else "They go, and come back another year. A house that pays is thought a little less of.")
		row.add_child(pay)
		if not raid.get("levy", false):
			var lv := UITheme.button("Call the levy (%d)" % Military.levy(st).size(), func() -> void:
				var r := Military.call_levy(st)
				Game.notify.emit(str(r["text"]), Game.COLOR_INFO)
				refresh())
			lv.tooltip_text = "The strongest villagers take up farm tools and fight beside the watch. They won't like it, and they can die."
			row.add_child(lv)
		_body.add_child(row)
		_allies(st)
	else:
		_body.add_child(_wrap("No raiders on the road. Fights won: %d of %d." % [m.won, m.battles], 14, UITheme.TEXT_DIM))
	if not m.expedition.is_empty():
		var x := m.expedition
		var when := "they fight on %s" % Calendar.format_date(int(x["fight"]) * Calendar.MINUTES_PER_DAY) if not bool(x.get("fought", false)) else "home by %s" % Calendar.format_date(int(x["back"]) * Calendar.MINUTES_PER_DAY)
		_body.add_child(_wrap("Your warband is away against %s: %s. The village is the barer for it." % [x["band"], when], 14, UITheme.ACCENT))
	if m.camps.size() > Military.known_camps(st).size():
		_body.add_child(_wrap("A band is camped somewhere in the woods; no one knows where yet.", 13, UITheme.BAD))
	for camp in Military.known_camps(st):
		var b := UITheme.button("%s: some %d men, camped %s %s" % [Military._cap(str(camp["band"])), int(camp["men"]), Realm.days_text(int(camp["days"])), camp["road"]], func() -> void:
			world.ui.show_realm("camp", int(camp["id"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "On the realm map (%s): send the warband to clear the camp." % world.key_hint("toggle_realm")
		_body.add_child(b)
	if m.camps.is_empty():
		_body.add_child(_wrap("No bands are camped near the village.", 13, UITheme.TEXT_DIM))
	var band := Military.warband(st)
	var names: Array[String] = []
	for c in band.slice(0, 10):
		var skill := "%d" % c.get_current("combat")
		if c.appraised:
			skill += "/%d" % c.get_potential("combat")
		names.append("%s (%s)" % [c.first_name, skill])
	_body.add_child(_wrap("Your warband (Combat now%s): %s" % ["/potential" if band.any(func(c: CharacterData) -> bool: return c.appraised) else "", ", ".join(names) + ("..." if band.size() > 10 else "") if not names.is_empty() else "no one"], 13, UITheme.TEXT))
	var hurt := st.characters.filter(func(c: CharacterData) -> bool: return Military.wounded(st, c))
	if not hurt.is_empty():
		_body.add_child(_wrap("Wounded: %s." % ", ".join(hurt.map(func(c: CharacterData) -> String: return "%s (until %s)" % [c.first_name, Calendar.format_date(c.wounded_until * Calendar.MINUTES_PER_DAY)])), 13, UITheme.ACCENT))
	var gentle := CheckBox.new()
	gentle.text = "Gentle fights"
	gentle.button_pressed = m.gentle
	gentle.tooltip_text = "For this game: those who fall in a fight die far less often (one in ten, not one in three)."
	gentle.add_theme_font_size_override("font_size", 14)
	gentle.toggled.connect(func(on: bool) -> void: m.gentle = on)
	_body.add_child(gentle)


## The men-at-arms the noble houses send against the coming raid, and
## asking a friendly house for them (Phase 5.3).
func _allies(st: WorldState) -> void:
	var sent: Array = st.military.raid.get("allies", [])
	for a: Dictionary in sent:
		_body.add_child(_wrap("%s sends %d men-at-arms to stand with you%s." % [st.realm.house_title(int(a["house"])), int(a["men"]), " (you asked)" if a.get("asked", false) else ""], 14, UITheme.GOOD))
	if st.realm == null:
		return
	var aid := Realm.section("aid")
	for h in st.realm.houses:
		var id := int(h["id"])
		if id == int(st.military.raid.get("host", -1)) or sent.any(func(a: Dictionary) -> bool: return int(a["house"]) == id):
			continue
		if int(h.get("days", 99)) > int(aid.get("max_days", 3)):
			continue
		var can := Realm.can_ask(st, id)
		var b := UITheme.button("Ask House %s for men (%d)" % [h["name"], Realm.men_from(h)], func() -> void:
			var r := Realm.ask_aid(st, id)
			Game.notify.emit(str(r["text"]), Game.COLOR_GOOD if r["ok"] else Game.COLOR_BAD)
			refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not can["ok"]
		b.tooltip_text = str(can["reason"]) if b.disabled else "They send men-at-arms to fight beside your warband. It spends some of their regard (%d)." % int(aid.get("ask_cost", 12))
		_body.add_child(b)


## The house's castle: what stands, the works under way, and raising the
## next (Phase 5.3).
func _castle(st: WorldState) -> void:
	var c := st.castle
	if c == null:
		return
	_heading("Castle")
	var stands := CastleSystem.stands(st)
	if not stands.is_empty():
		var d := CastleSystem.kind_def(stands)
		var safe := float(d.get("gold_safe", 0.0))
		_body.add_child(_wrap("Your %s stands. Renown +%d, room for %d more in the household; in a raid your warband holds its gate (+%d Combat, breaks later) and %s of your gold is out of reach." % [
			CastleSystem.name_of(stands), int(d.get("renown", 0)), int(d.get("retainers", 0)), int(d.get("combat", 0)), "all" if safe >= 1.0 else "%d%%" % roundi(safe * 100.0)], 14, UITheme.GOOD))
	if not c.works.is_empty():
		var left := CastleSystem.days_left(st)
		_body.add_child(_wrap("Raising a %s: %d%% done%s." % [CastleSystem.name_of(c.works), roundi(c.progress() * 100.0),
			", some %d days to go" % ceili(left) if left < INF else ""], 15, UITheme.ACCENT))
		var crew := c.builders.map(func(id: int) -> String: return st.get_character(id).first_name if st.get_character(id) else "?")
		_body.add_child(_wrap("The crew: %s." % (", ".join(crew) if not crew.is_empty() else "no one (the village has no builders free)"), 13, UITheme.TEXT if not crew.is_empty() else UITheme.BAD))
		if not c.stalled.is_empty():
			_body.add_child(_wrap("The works wait for %s: the stores are dry." % c.stalled, 14, UITheme.BAD))
		return
	var next := CastleSystem.next_kind(st)
	if next.is_empty():
		return
	var d := CastleSystem.kind_def(next)
	var can := CastleSystem.can_order(st, next)
	var b := UITheme.button("Raise a %s (%d gold)" % [CastleSystem.name_of(next), int(d.get("gold", 0))], func() -> void:
		var r := world.order_castle(next)
		Game.notify.emit(str(r["text"]), Game.COLOR_GOOD if r["ok"] else Game.COLOR_BAD)
		Audio.play("coins" if r["ok"] else "ui_error")
		refresh())
	b.disabled = not can["ok"]
	b.tooltip_text = str(can["reason"]) if b.disabled else "The steward chooses the ground. Your builders raise it from the stores: %s." % CastleSystem.needs_text(next)
	_body.add_child(b)
	_body.add_child(_wrap(("%s " % can["reason"] if b.disabled and not str(can["reason"]).is_empty() else "") + "Uses %s as it goes, %d builder-hours of work." % [CastleSystem.needs_text(next), int(d.get("work", 0))], 13, UITheme.TEXT_DIM))


## Your health and heir, a regency while you're young, the family tree, and
## letting the years pass (Phase 4.3).
func _succession(st: WorldState) -> void:
	var player := st.player()
	if player == null:
		return
	_heading("Succession")
	var failing := Succession.failing(player)
	_body.add_child(_wrap("Your health is failing (you are %d). See to your heir." % player.age if failing else "You are %d and in good health." % player.age,
		14, UITheme.BAD if failing else UITheme.TEXT))
	var heir := Succession.heir(st)
	if heir:
		var how := "named" if Succession.is_named(st, heir) else "your eldest"
		_body.add_child(_person_button(heir, "Your heir: %s, %d (%s)  -  name another child from their card" % [heir.display_name(), heir.age, how]))
	else:
		var next := Succession.successor(st, player)
		_body.add_child(_wrap("You have no child. Were you to die, %s." % ("the house would pass to %s" % next.full_name() if next else "no one would follow you and the house would end"),
			14, UITheme.TEXT_DIM if next else UITheme.BAD))
	if Succession.minority(st):
		_regency(st, player)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UITheme.button("Family tree", func() -> void: world.ui.toggle_tree()))
	var season := UITheme.button("Let a season pass", func() -> void: world.ui.pass_time(Calendar.days_per_season()))
	season.tooltip_text = "Skip %d days and read what happened. It stops early for what needs you: a suitor, a death in the family, your health." % Calendar.days_per_season()
	row.add_child(season)
	var year := UITheme.button("Let a year pass", func() -> void: world.ui.pass_time(Calendar.days_per_year()))
	year.tooltip_text = "Skip %d days (a year) and read what happened. It stops early for what needs you." % Calendar.days_per_year()
	row.add_child(year)
	_body.add_child(row)


## Who rules for you, how well, and who else could.
func _regency(st: WorldState, player: CharacterData) -> void:
	var r := Succession.regent(st)
	var years := Succession.of_age() - player.age
	if r:
		var f := Succession.regent_income_factor(st)
		_body.add_child(_person_button(r, "Regent: %s, %d  -  rules for you for %d more year%s" % [r.display_name(), r.age, years, "" if years == 1 else "s"]))
		_body.add_child(_wrap("Their Administration (%d) moves the house's income %+d%%." % [r.get_current("administration"), roundi(f * 100.0)], 13, UITheme.GOOD if f >= 0.0 else UITheme.BAD))
		var skim := Succession.regent_skim(st, CourtSystem.daily_income(st))
		if skim > 0:
			_body.add_child(_wrap("Their loyalty is thin (%d): they pocket %d gold a day." % [roundi(r.loyalty), skim], 13, UITheme.BAD))
	else:
		_body.add_child(_wrap("No one is fit to rule for you: you rule alone until you are %d." % Succession.of_age(), 14, UITheme.TEXT_DIM))
	var toggle := UITheme.button("Hide" if _choosing_regent else "Choose another regent...", func() -> void:
		_choosing_regent = not _choosing_regent
		refresh())
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(toggle)
	if not _choosing_regent:
		return
	var choices: Array[CharacterData] = []
	for c in st.characters:
		if c != r and Succession.can_be_regent(st, c)["ok"]:
			choices.append(c)
	choices.sort_custom(func(a: CharacterData, b: CharacterData) -> bool: return a.get_current("administration") > b.get_current("administration"))
	if choices.is_empty():
		_body.add_child(_wrap("No one else could: your grown kin and retainers may.", 13, UITheme.TEXT_DIM))
	for c in choices.slice(0, 8):
		var b := Button.new()
		b.theme_type_variation = "RowButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 14)
		var adm := "Administration %d" % c.get_current("administration") if c.appraised else "Administration ? (not seen with the Eye)"
		b.text = "Make regent: %s, %d, %s  -  %s  -  loyalty %d" % [c.display_name(), c.age, CourtSystem.role_name(st, c).to_lower(), adm, roundi(c.loyalty)]
		b.pressed.connect(func() -> void:
			var res := Succession.set_regent(st, c)
			Game.notify.emit(str(res["text"]), Game.COLOR_GOOD if res["ok"] else Game.COLOR_BAD)
			_choosing_regent = false
			refresh())
		_body.add_child(b)


## Who is married, the suitor visiting now, who is still to be matched, and
## the children at their lessons.
func _marriages(st: WorldState) -> void:
	var player := st.player()
	_heading("Marriages")
	var spouse := LifeSystem.spouse_of(st, player) if player else null
	if spouse:
		_body.add_child(_person_button(spouse, "Your %s: %s, %d" % ["wife" if spouse.gender == "female" else "husband", spouse.display_name(), spouse.age]))
	elif player:
		_body.add_child(_wrap("You are unmarried. Ask for someone's hand face to face, or wait for a suitor from a neighbouring house.", 14, UITheme.TEXT_DIM))
	var v := MatchSystem.visitor(st)
	if v:
		var target := st.get_character(v.suitor_for)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var b := _person_button(v, "Suitor: %s, %d, for %s" % [v.full_name(), v.age, "you" if st.is_player(target) else (target.first_name if target else "?")])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		row.add_child(UITheme.button("Accept", func() -> void: _answer_suitor(v, true)))
		row.add_child(UITheme.button("Send home", func() -> void: _answer_suitor(v, false)))
		_body.add_child(row)
		_body.add_child(_wrap("%s. Dowry %d gold. Here until %s." % [st.realm.house_title(v.house_id), MatchSystem.dowry(st, v.house_id), Calendar.format_date(v.visiting_until * Calendar.MINUTES_PER_DAY)], 14, UITheme.TEXT))
		_body.add_child(_wrap("Their letter only praises: walk up to %s and look with the Eye before you answer." % v.first_name, 13, UITheme.TEXT_DIM))
	var fam := st.ruling_family()
	for id in (fam.member_ids if fam else []):
		var k := st.get_character(id)
		if k and not st.is_player(k) and MatchSystem.seeks(st, k):
			var widowed := not k.relationships_of_type(["late_spouse"]).is_empty()
			_body.add_child(_person_button(k, "%s, %d  -  %s (choose a match from their card)" % [k.display_name(), k.age, "widowed" if widowed else "unmarried"]))
	var pupils := CourtSystem.tutored(st)
	if not pupils.is_empty():
		var names: Array[String] = []
		for p in pupils:
			names.append("%s (%s)" % [p.first_name, CourtSystem.attr_name(CourtSystem.focus_of(p))])
		_body.add_child(_wrap("At their lessons: %s  -  tutors %d gold a day." % [", ".join(names), pupils.size() * int(CourtSystem.section("tutors").get("fee", 1))], 14, UITheme.TEXT))


func _answer_suitor(v: CharacterData, yes: bool) -> void:
	var events: Array[Dictionary] = []
	var r := MatchSystem.accept(world.state, v, events) if yes else MatchSystem.decline(world.state, v, events)
	Audio.play("court_good" if yes and r["ok"] else "ui_tick")
	if not (yes and r["ok"]):
		Game.notify.emit(str(r["text"]), Game.COLOR_INFO)
	if not yes and world.talking_to == v.id:
		world.end_conversation()
	world.apply_life_events(events)
	refresh()


func _office_effect(st: WorldState, o: Dictionary, holder: CharacterData) -> String:
	match str(o.get("effect", "")):
		"income":
			if holder:
				return "Income +%d%% from their Administration." % roundi(holder.get_current("administration") / float(o.get("effect_divisor", 200.0)) * 100.0)
			return "Raises income with their Administration."
		"renown":
			if holder:
				return "Renown +%.1f per day from their Politics; helps recruitment." % CourtSystem.daily_renown(st)
			return "Earns renown with their Politics; helps recruitment."
		"mentor":
			var names: Array[String] = []
			for a: String in o.get("mentors", []):
				names.append(CourtSystem.attr_name(a))
			return "Mentors the household in %s (faster training for those behind them)." % ", ".join(names)
		"construction":
			if holder:
				return "Building works go %d%% faster from their Administration." % roundi((TerritorySystem.speed_factor(st) - 1.0) * 100.0)
			return "Speeds every building site with their Administration."
	return str(o.get("description", ""))


func _heading(text: String) -> void:
	_body.add_child(UITheme.label(text, 17, UITheme.ACCENT, true))
	_body.add_child(HSeparator.new())


func _person_button(c: CharacterData, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 14)
	b.text = text
	b.tooltip_text = "Open %s's card" % c.first_name
	b.pressed.connect(func() -> void: character_chosen.emit(c.id))
	return b


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	return l


static func _chronicle_color(kind: String) -> Color:
	match kind:
		"join", "office", "knight", "birth", "marriage":
			return UITheme.GOOD
		"death":
			return UITheme.TEXT
		"rank":
			return UITheme.ACCENT
		"leave", "bad", "refusal":
			return UITheme.BAD
	return UITheme.TEXT_DIM
