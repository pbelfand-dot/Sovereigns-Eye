class_name RealmPanel
extends PanelContainer
## The realm map (J, Phase 5.2): the map on the left (RealmMap), what you
## know of the chosen place on the right. A house: its lord or lady, what
## it's known for, its renown, what it thinks of yours, the young you've met
## there and your kin fostered there; ride to visit. A camp: the band, how
## many, its hoard, your captains' odds; send the warband, or lead it.

signal close_requested
signal visit_requested(house_id: int)
signal ride_requested(camp_id: int, lead: bool)

var world: VillageWorld
var _map: RealmMap
var _body: VBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.box(UITheme.BG, UITheme.GOLD, 2, 6, 10))


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := UITheme.label("The Realm", 22, UITheme.ACCENT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UITheme.button("X", func() -> void: close_requested.emit()))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	_map = RealmMap.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.picked.connect(func(_k: String, _id: int) -> void: _refresh_details())
	row.add_child(_map)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 390
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)


func refresh() -> void:
	if world == null:
		return
	_map.state = world.state
	_map._art = {}
	_map.queue_redraw()
	_refresh_details()


## Opens on a place (a house or camp id), else the village.
func show_place(kind: String, id: int) -> void:
	_map.selected = {"kind": kind, "id": id}
	refresh()


func _refresh_details() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var st := world.state
	var sel := _map.selected
	match str(sel.get("kind", "village")):
		"house":
			_house(st, st.realm.get_house(int(sel["id"])))
		"camp":
			_camp(st, st.military.get_camp(int(sel["id"])))
		_:
			_village(st)


func _village(st: WorldState) -> void:
	_heading(st.village_name)
	_line("Your house's seat. Click a noble house's seat or a bandit camp on the map.", 14, UITheme.TEXT_DIM)
	_line("Fit to ride out: %d (retainers, knights and the watch)." % Military.riders(st).size(), 14, UITheme.TEXT)
	var x := st.military.expedition
	if not x.is_empty():
		_line(_expedition_text(st), 14, UITheme.ACCENT)
	var known := Military.known_camps(st)
	if st.military.camps.size() > known.size():
		_line("A band is camped somewhere in the woods; no one knows where yet. Its raid will show the way (or your woodcutters will come on it).", 14, UITheme.BAD)
	elif known.is_empty():
		_line("No bands are camped near the village.", 14, UITheme.TEXT_DIM)
	for c in known:
		_line("%s: some %d men, %s %s." % [Military._cap(str(c["band"])), int(c["men"]), Realm.days_text(int(c["days"])), c["road"]], 14, UITheme.BAD)
	var fostered := st.characters.filter(func(c: CharacterData) -> bool: return c.fostered_at() >= 0)
	for c: CharacterData in fostered:
		var h := st.realm.get_house(c.fostered_at())
		_line("%s is fostered at %s until %d." % [c.full_name(), h.get("seat", "?"), int(Realm.section("fostering").get("return_age", 16))], 14, UITheme.TEXT)


func _house(st: WorldState, h: Dictionary) -> void:
	if h.is_empty():
		_village(st)
		return
	_heading(str(h["seat"]))
	_line("%s, %s." % [st.realm.house_title(int(h["id"])), Realm.known_for_text(h)], 15, UITheme.TEXT)
	_line("%s holds the seat. Renown %d." % [h["head"], int(h["renown"])], 14, UITheme.TEXT)
	var regard := int(h["standing"])
	_line("They are %s toward your house (%+d)." % [MatchSystem.standing_word(regard), regard], 15, UITheme.GOOD if regard >= 10 else (UITheme.BAD if regard <= -10 else UITheme.TEXT))
	# Phase 5.3: their rival, whether they'd help or come against you.
	var rival := Realm.rival_of(st, int(h["id"]))
	if not rival.is_empty():
		_line("At odds with House %s: what warms one toward you cools the other." % rival["name"], 13, UITheme.TEXT_DIM)
	var aid := Realm.section("aid")
	if int(h.get("truce", -1)) > st.day():
		_line("They keep the peace with you until %s." % Calendar.format_date(int(h["truce"]) * Calendar.MINUTES_PER_DAY), 13, UITheme.TEXT)
	elif regard <= int(Realm.section("hosts").get("hostile_at", -40)):
		_line("They hold your house in contempt, and may come against you.", 14, UITheme.BAD)
	if regard >= int(aid.get("min_regard", 40)) and int(h["days"]) <= int(aid.get("max_days", 3)):
		_line("They'd send men-at-arms against a raid on your village.", 13, UITheme.GOOD)
	elif regard >= int(aid.get("ask_regard", 15)) and int(h["days"]) <= int(aid.get("max_days", 3)):
		_line("They'd send men-at-arms against a raid if you asked.", 13, UITheme.TEXT)
	var attr := str(GameData.attribute_def(Realm.known_for_attribute(h)).get("name", ""))
	_line("%s. A child fostered there learns %s." % [Military._cap(Realm.days_text(int(h["days"]))), attr], 14, UITheme.TEXT_DIM)
	if int(h.get("visited", -1)) >= 0:
		_line("Last visited %s." % Calendar.format_date(int(h["visited"]) * Calendar.MINUTES_PER_DAY), 13, UITheme.TEXT_DIM)
	var young := st.realm.household(int(h["id"]))
	if not young.is_empty():
		_sub("Their young (when you were there)")
		for c in young:
			var gift := ""
			if c.appraised:
				var best := c.best_attribute()
				gift = "  -  %s %s" % [GameData.attribute_def(best).get("name", best), Appraisal.rank_id(c.get_potential(best))]
			_line("%s, %d%s" % [c.full_name(), c.age, gift], 14, UITheme.TEXT)
	var mine := st.characters.filter(func(c: CharacterData) -> bool: return c.fostered_at() == int(h["id"]))
	for c: CharacterData in mine:
		_line("%s is fostered here (%s %d)." % [c.full_name(), attr, c.get_current(Realm.known_for_attribute(h))], 14, UITheme.ACCENT)
	var can := Realm.can_visit(st, int(h["id"]))
	var days := int(h["days"])
	var visit := UITheme.button("Ride to %s (%d days there, %d back)" % [h["seat"], days, days + int(Realm.section("visits").get("stay_days", 1))], func() -> void:
		visit_requested.emit(int(h["id"])))
	visit.disabled = not can["ok"]
	visit.tooltip_text = str(can["reason"]) if not can["ok"] else "The days pass at home while you're away: your steward sees to things, your warband to any raid."
	_body.add_child(visit)
	if not can["ok"] and not str(can["reason"]).is_empty():
		_line(str(can["reason"]), 13, UITheme.BAD)
	elif not st.military.raid.is_empty():
		_line("%s is on the road to the village: your warband will meet it without you." % Military._cap(str(st.military.raid["name"])) if st.military.raid.has("host") else "A band is on the road to the village: your warband will meet it without you.", 13, UITheme.BAD)


func _camp(st: WorldState, c: Dictionary) -> void:
	if c.is_empty():
		_village(st)
		return
	_heading(Military._cap(str(c["band"])))
	_line("Camped %s out along the %s road. Some %d men; their hoard, perhaps %d gold." % [Realm.days_text(int(c["days"])), c["road"], int(c["men"]), int(c["hoard"])], 15, UITheme.TEXT)
	_line("They grow while they're left be, and raid the village from here. On their own ground they fight harder.", 13, UITheme.TEXT_DIM)
	var x := st.military.expedition
	if not x.is_empty():
		_line(_expedition_text(st), 14, UITheme.ACCENT)
		return
	var riders := Military.riders(st)
	_line("Fit to ride: %s." % (", ".join(riders.map(func(r: CharacterData) -> String: return "%s (%d)" % [r.first_name, r.get_current("combat")])) if not riders.is_empty() else "no one"), 13, UITheme.TEXT)
	for lead: bool in [false, true]:
		var can := Military.can_ride(st, int(c["id"]), lead)
		if can["ok"] and lead:
			can = Realm.can_travel(st)
		var odds := Military.camp_odds(st, int(c["id"]), lead) if can["ok"] else 0.0
		var text := "Lead them yourself" if lead else "Send the warband"
		var b := UITheme.button("%s (odds %s)" % [text, Military.odds_word(odds)] if can["ok"] else text, func() -> void: ride_requested.emit(int(c["id"]), lead))
		b.disabled = not can["ok"]
		b.tooltip_text = str(can["reason"]) if not can["ok"] else ("You ride with them: the days pass while you're away, and you fight (and may fall)." if lead else "They ride out; the village is the barer until they're home.")
		_body.add_child(b)
		if not can["ok"] and not str(can["reason"]).is_empty():
			_line(str(can["reason"]), 13, UITheme.BAD)
	_line("%s each way; the fight is on arrival. The levy won't leave its fields." % Military._cap(Realm.days_text(int(c["days"]))), 13, UITheme.TEXT_DIM)


func _expedition_text(st: WorldState) -> String:
	var x := st.military.expedition
	if not bool(x.get("fought", false)):
		return "Your warband is riding against %s: they fight on %s." % [x["band"], Calendar.format_date(int(x["fight"]) * Calendar.MINUTES_PER_DAY)]
	return "Your warband is on its way home from %s, by %s." % [x["band"], Calendar.format_date(int(x["back"]) * Calendar.MINUTES_PER_DAY)]


func _heading(text: String) -> void:
	_body.add_child(UITheme.label(text, 20, UITheme.ACCENT, true))


func _sub(text: String) -> void:
	_body.add_child(UITheme.label(text, 15, UITheme.GOLD, true))


func _line(text: String, size_px: int, color: Color) -> void:
	var l := UITheme.label(text, size_px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	_body.add_child(l)
