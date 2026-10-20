class_name CharacterCard
extends PanelContainer
## The character card: everything Appraisal reveals about one person.
## Generated entirely from CharacterData; nothing is hand-authored per NPC.

signal close_requested
signal character_link_pressed(character_id: int)
signal follow_pressed(character_id: int)

const WIDTH := 460.0

var world: VillageWorld
var character: CharacterData

var _portrait: PortraitStudio
var _portrait_rect: TextureRect
var _name_label: Label
var _sub_label: Label
var _age_label: Label
var _family_label: Label
var _home_label: Label
var _now_label: Label
var _follow: Button
var _banner: PanelContainer
var _banner_label: Label
var _tabs: TabContainer
var _appraisal_box: VBoxContainer
var _personality_box: VBoxContainer
var _relations_box: VBoxContainer
var _history_box: VBoxContainer
var _court_box: VBoxContainer
var _live_refresh := 0.0
var _dismiss_armed := false
## The match-making list on the Court tab is open, and the last answer.
var _matching := false
var _match_note: Array[Dictionary] = []


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# Header: portrait + identity
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.box(Color("#3b2c1f"), UITheme.GOLD, 2, 4, 2))
	header.add_child(frame)
	_portrait = PortraitStudio.new()
	add_child(_portrait)
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(128, 160)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.texture = _portrait.get_texture()
	frame.add_child(_portrait_rect)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	header.add_child(info)
	var name_row := HBoxContainer.new()
	info.add_child(name_row)
	_name_label = UITheme.label("", 22, UITheme.TEXT, true)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_row.add_child(_name_label)
	var close := UITheme.button("X", close_requested.emit)
	close.tooltip_text = "Close (Esc)"
	name_row.add_child(close)
	_sub_label = UITheme.label("", 16, UITheme.ACCENT)
	info.add_child(_sub_label)
	_age_label = UITheme.label("", 15, UITheme.TEXT_DIM)
	info.add_child(_age_label)
	_family_label = UITheme.label("", 15)
	_family_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_family_label)
	_home_label = UITheme.label("", 14, UITheme.TEXT_DIM)
	_home_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_home_label)
	_now_label = UITheme.label("", 14, UITheme.TEXT_DIM)
	_now_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_now_label)
	_follow = UITheme.button("Follow", _on_follow)
	_follow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(_follow)

	_banner = PanelContainer.new()
	_banner_label = UITheme.label("", 15, UITheme.TEXT, true)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_child(_banner_label)
	root.add_child(_banner)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 15)
	root.add_child(_tabs)
	_appraisal_box = _add_tab("Appraisal")
	_court_box = _add_tab("Court")
	_personality_box = _add_tab("Personality")
	_relations_box = _add_tab("Relationships")
	_history_box = _add_tab("History")


func _on_follow() -> void:
	if character:
		follow_pressed.emit(character.id)


func _add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func show_character(c: CharacterData) -> void:
	if c != character:
		_dismiss_armed = false
		_matching = false
		_match_note.clear()
	character = c
	visible = c != null
	if c == null:
		_portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# An AI portrait (user://portraits/<seed>/<id>.png) wins; otherwise the
	# character's 3D model is rendered live as a placeholder. A baby has no
	# portrait yet (they stay at home, unseen).
	var ai_portrait := PortraitPrompt.image_for(c, world.state.world_seed)
	_portrait_rect.tooltip_text = "Too young to sit for a portrait: at home with their family." if LifeSystem.is_unseen(c) else ""
	if LifeSystem.is_unseen(c):
		_portrait_rect.texture = null
		_portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif ai_portrait:
		_portrait_rect.texture = ai_portrait
		_portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_portrait_rect.texture = _portrait.get_texture()
		_portrait.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_portrait.show_character(c)
	refresh()


func _process(delta: float) -> void:
	if not visible or character == null:
		return
	_live_refresh -= delta
	if _live_refresh <= 0.0:
		_live_refresh = 0.5
		_refresh_live()


## Rebuilds every section from the character's data.
func refresh() -> void:
	if character == null:
		return
	_follow.text = "Follow (%s)" % InputSetup.key_name("focus_selected", false)
	var c := character
	var st := world.state
	_name_label.text = c.display_name()
	_sub_label.text = "%s  -  %s" % [CourtSystem.role_name(st, c) if st.house else c.occupation_name(), c.status_name()]
	_age_label.text = "Age %d  -  %s  -  born %s" % [c.age, c.gender.capitalize(), LifeSystem.born_text(st, c)]
	var fam := world.state.get_family(c.family_id)
	_family_label.text = "%s (%s)" % [fam.display_name(), fam.background_name()] if fam else ""
	var home := world.state.get_building(c.home_building_id)
	_home_label.text = "Lives at %s" % (home.name if home else "no fixed home")
	_refresh_banner()
	_build_appraisal()
	_build_court()
	_build_personality()
	_build_relationships()
	_build_history()
	_refresh_live()


func _refresh_live() -> void:
	var c := character
	var where := "outdoors"
	if c.inside_building_id >= 0:
		var b := world.state.get_building(c.inside_building_id)
		where = "inside %s" % b.name if b else "indoors"
	var text := c.activity_text if not c.activity_text.is_empty() else c.activity.capitalize()
	_now_label.text = "Now: %s (%s)" % [text, where]


func _refresh_banner() -> void:
	var c := character
	# Nothing marks a gifted person until the Sovereign's Eye has seen them.
	_banner.visible = c.appraised
	if not c.appraised:
		return
	var best := c.best_attribute()
	var p := c.get_potential(best)
	var color := Appraisal.rank_color(p)
	var attr_name := str(GameData.attribute_def(best).get("name", best))
	_banner.tooltip_text = "Greatest potential: %s %d (%s, %s)" % [attr_name, p, Appraisal.rank_id(p), Appraisal.rank_title(p)]
	if Appraisal.is_exceptional(c):
		_banner_label.text = "EXCEPTIONAL TALENT  -  %s %s" % [attr_name, Appraisal.rank_id(p)]
	elif Appraisal.is_notable(c):
		_banner_label.text = "Notable talent  -  %s %s" % [attr_name, Appraisal.rank_id(p)]
	else:
		_banner_label.text = "Greatest talent: %s (%s)" % [attr_name, Appraisal.rank_id(p)]
	_banner_label.add_theme_color_override("font_color", color.lightened(0.2))
	_banner.add_theme_stylebox_override("panel", UITheme.box(color.darkened(0.7), color, 1, 4, 6))


static func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _section(box: VBoxContainer, title: String) -> void:
	var l := UITheme.label(title, 17, UITheme.ACCENT, true)
	box.add_child(l)
	box.add_child(HSeparator.new())


# --- Appraisal tab -----------------------------------------------------------------------

func _build_appraisal() -> void:
	_clear(_appraisal_box)
	if not character.appraised:
		_build_unseen()
		return
	var report := Appraisal.appraise(character)
	var hint := UITheme.label("Current ability / maximum potential", 13, UITheme.TEXT_DIM)
	_appraisal_box.add_child(hint)
	for row: Dictionary in report["attributes"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.tooltip_text = "%s\n%s potential: %s" % [row["description"], row["rank"], row["rank_title"]]
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		var name_l := UITheme.label(str(row["name"]), 15)
		name_l.custom_minimum_size.x = 112
		line.add_child(name_l)
		var bar := StatBar.new()
		bar.setup(int(row["current"]), int(row["potential"]), row["color"])
		line.add_child(bar)
		var nums := UITheme.label("%d / %d" % [row["current"], row["potential"]], 15)
		nums.custom_minimum_size.x = 70
		nums.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(nums)
		line.add_child(UITheme.rank_badge(str(row["rank"]), row["color"]))
		_appraisal_box.add_child(line)
	_appraisal_box.add_child(HSeparator.new())
	var untapped := 0
	for row: Dictionary in report["attributes"]:
		untapped += int(row["potential"]) - int(row["current"])
	var summary := UITheme.label("Untapped potential: %d points across all attributes." % untapped, 14, UITheme.TEXT_DIM)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_appraisal_box.add_child(summary)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 4)
	for r: Dictionary in GameData.ranks():
		var badge := UITheme.rank_badge(str(r["id"]), Color(str(r["color"])), 12)
		badge.tooltip_text = "%s: %d+ (%s)" % [r["id"], int(r["min"]), r["title"]]
		legend.add_child(badge)
	_appraisal_box.add_child(legend)


## Before the Eye: only what anyone could see, and the way to learn more.
func _build_unseen() -> void:
	var c := character
	_section(_appraisal_box, "Unseen")
	_appraisal_box.add_child(_wrap_label("What %s could become is hidden. Find them in the village, get close enough to see them clearly, and look with the Sovereign's Eye (%s). If they're worth it, walk up and talk (%s) to learn what they want." % [
		c.first_name, world.key_hint("sovereign_eye"), world.key_hint("interact")], 15, UITheme.TEXT))
	var rumors: Array[String] = []
	for h in c.history:
		if str(h["category"]) == "rumor":
			rumors.append(str(h["text"]))
	if not rumors.is_empty():
		_section(_appraisal_box, "What people say")
		for r in rumors:
			_appraisal_box.add_child(_wrap_label("\"%s\"" % r, 14, UITheme.TEXT_DIM))


## Opens a tab by name ("appraisal", "court", "personality", ...).
func show_tab(tab_name: String) -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i).to_lower() == tab_name.to_lower():
			_tabs.current_tab = i


# --- Court tab (Phase 2) ----------------------------------------------------------------------

func _build_court() -> void:
	_clear(_court_box)
	var c := character
	var st := world.state
	if st.house == null:
		return
	if st.is_player(c):
		_build_court_player()
		return
	# One row: what they think of you, and the two ways to change it.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	var op := roundi(c.player_opinion)
	var op_box := HBoxContainer.new()
	op_box.add_theme_constant_override("separation", 6)
	op_box.tooltip_text = "Their opinion of you (-100 to +100)"
	op_box.mouse_filter = Control.MOUSE_FILTER_PASS
	op_box.add_child(_mini_bar(c.player_opinion, -100.0, 100.0, UITheme.opinion_color(op), 96.0))
	var op_l := UITheme.label("%+d %s" % [op, CourtSystem.opinion_label(c.player_opinion)], 14, UITheme.opinion_color(op))
	op_l.mouse_filter = Control.MOUSE_FILTER_PASS
	op_box.add_child(op_l)
	row.add_child(op_box)
	var near := world.talk_check(c.id)
	var tb := UITheme.button("Talk", _on_talk)
	tb.disabled = not near["ok"]
	tb.tooltip_text = "Speak with them face to face: once a day it raises their opinion of you (your Politics makes you better company)." if near["ok"] else "Walk up to them and press %s to talk." % world.key_hint("interact")
	row.add_child(tb)
	var gift := CourtSystem.can_gift(st, c)
	var gb := UITheme.button("Gift (%d gold)" % CourtSystem.gift_cost(c), _on_gift)
	gb.disabled = not gift["ok"]
	gb.tooltip_text = str(gift["reason"]) if not gift["ok"] else "A gift raises their opinion of you (more for the greedy)."
	row.add_child(gb)
	_court_box.add_child(row)
	if c.is_away():
		var where := "riding with the warband against a camp"
		if c.fostered_at() >= 0:
			where = "fostered at %s until %d" % [st.realm.get_house(c.fostered_at()).get("seat", "?"), int(Realm.section("fostering").get("return_age", 16))]
		elif c.away_at == "journey":
			where = "on a journey"
		_court_box.add_child(_wrap_label("Away: %s." % where, 14, UITheme.ACCENT))
	if c.is_visitor():
		_build_court_visitor()
	elif CourtSystem.is_kin(st, c):
		_build_court_kin()
	elif c.retainer:
		_build_court_retainer()
		_marriage_section(c)
	else:
		_build_court_recruit()


## A suitor from another house: who sent them, for whom, until when; the
## answer is the player's.
func _build_court_visitor() -> void:
	var c := character
	var st := world.state
	var target := st.get_character(c.suitor_for)
	_section(_court_box, "A suitor")
	_court_box.add_child(_wrap_label("%s came from %s to court %s, and stays at the manor until %s. Their house offers a dowry of %d gold." % [
		c.first_name, st.realm.house_title(c.house_id), "you" if st.is_player(target) else (target.full_name() if target else "?"),
		Calendar.format_date(c.visiting_until * Calendar.MINUTES_PER_DAY), MatchSystem.dowry(st, c.house_id)], 14))
	_court_box.add_child(_wrap_label("Their family's letter only praises them. Look with the Eye: their children may inherit their gifts.", 13, UITheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UITheme.button("Accept the match", func() -> void: _answer_suitor(true)))
	row.add_child(UITheme.button("Send them home", func() -> void: _answer_suitor(false)))
	_court_box.add_child(row)


func _answer_suitor(yes: bool) -> void:
	var events: Array[Dictionary] = []
	var r := MatchSystem.accept(world.state, character, events) if yes else MatchSystem.decline(world.state, character, events)
	Audio.play("court_good" if yes and r["ok"] else "ui_tick")
	if not (yes and r["ok"]):
		Game.notify.emit(str(r["text"]), Game.COLOR_INFO)
	world.apply_life_events(events)
	if character and world.state.get_character(character.id):
		_build_court()


## The house's own kin: their lessons and their marriage.
func _build_court_kin() -> void:
	var c := character
	var st := world.state
	_section(_court_box, "Of your house")
	var role := CourtSystem.role_name(st, c)
	if role == "Your heir" or role.begins_with("Regent"):
		_court_box.add_child(_wrap_label("%s is %s, of %s." % [c.first_name, role.substr(0, 1).to_lower() + role.substr(1), CourtSystem.house_name(st)], 14))
	else:
		_court_box.add_child(_wrap_label("%s is %s of %s." % [c.first_name, role.to_lower(), CourtSystem.house_name(st)], 14))
	_heir_section(c)
	if CourtSystem.is_tutored(st, c):
		_section(_court_box, "Lessons")
		var focus_row := HBoxContainer.new()
		focus_row.add_theme_constant_override("separation", 8)
		var fl := UITheme.label("Learn", 15)
		fl.custom_minimum_size.x = 80
		focus_row.add_child(fl)
		focus_row.add_child(_focus_picker(c))
		_court_box.add_child(focus_row)
		_training_lines(c)
		_court_box.add_child(_wrap_label("Tutors at the manor teach them for %d gold a day. Children learn fastest; the Eye shows where their gifts lie." % int(CourtSystem.section("tutors").get("fee", 1)), 13, UITheme.TEXT_DIM))
	_marriage_section(c)


## Your own children: name one your heir (Phase 4.3).
func _heir_section(c: CharacterData) -> void:
	var st := world.state
	if not Succession.children_of(st, st.player()).has(c):
		return
	_section(_court_box, "Succession")
	if Succession.heir(st) == c:
		_court_box.add_child(_wrap_label("%s is your heir%s: they go on after you." % [c.first_name, "" if Succession.is_named(st, c) else " (your eldest)"], 14, UITheme.GOOD))
		if Succession.is_named(st, c):
			return
	var older := Succession.children_of(st, st.player()).filter(func(k: CharacterData) -> bool: return k.age > c.age)
	var b := UITheme.button("Name %s your heir" % c.first_name, func() -> void:
		var r := Succession.name_heir(st, c)
		Audio.play("court_good" if r["ok"] else "ui_error")
		Game.notify.emit(str(r["text"]), Game.COLOR_GOOD if r["ok"] else Game.COLOR_BAD)
		_build_court())
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_court_box.add_child(b)
	if not older.is_empty():
		_court_box.add_child(_wrap_label("Passing over an older child (%s) hurts them, once." % ", ".join(older.map(func(k: CharacterData) -> String: return k.first_name)), 13, UITheme.TEXT_DIM))


## Married, or (for the house's grown kin and retainers) a list of
## matches to propose: both must agree.
func _marriage_section(c: CharacterData) -> void:
	var st := world.state
	var spouse := LifeSystem.spouse_of(st, c)
	if spouse == null and c.age < int(MatchSystem.section("ages").get("min", 16)):
		return
	_section(_court_box, "Marriage")
	if spouse:
		_court_box.add_child(_wrap_label("Married to %s." % spouse.display_name(), 14))
		return
	if st.is_player(c):
		_court_box.add_child(_wrap_label("Ask for someone's hand face to face, or wait for a suitor from a neighbouring house. Children often inherit their parents' gifts.", 14, UITheme.TEXT_DIM))
		return
	_court_box.add_child(_wrap_label("Choose a match for %s. Both must agree. A gifted pair often has gifted children." % c.first_name, 14, UITheme.TEXT_DIM))
	var toggle := UITheme.button("Hide matches" if _matching else "Find a match...", func() -> void:
		_matching = not _matching
		_build_court())
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_court_box.add_child(toggle)
	for n: Dictionary in _match_note:
		_court_box.add_child(_wrap_label(str(n["text"]), 14 if n.get("main", false) else 13, UITheme.GOOD if n["good"] else (UITheme.BAD if not n.get("main", false) else UITheme.TEXT)))
	if _matching:
		var list := MatchSystem.candidates(st, c, 6)
		if list.is_empty():
			_court_box.add_child(_wrap_label("No one suits just now.", 14, UITheme.TEXT_DIM))
		for o in list:
			var b := Button.new()
			b.theme_type_variation = "RowButton"
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.add_theme_font_size_override("font_size", 14)
			var seen := "  -  greatest gift %s" % Appraisal.rank_id(o.best_potential()) if o.appraised else ""
			b.text = "Propose: %s, %d, %s%s" % [o.display_name(), o.age, CourtSystem.role_name(st, o).to_lower(), seen]
			b.tooltip_text = "Ask %s and %s whether they'll marry." % [c.first_name, o.first_name]
			b.pressed.connect(_on_arrange.bind(o.id))
			_court_box.add_child(b)


func _on_arrange(partner_id: int) -> void:
	var st := world.state
	var partner := st.get_character(partner_id)
	if partner == null:
		return
	var events: Array[Dictionary] = []
	var r := MatchSystem.arrange(st, character, partner, events)
	_match_note.clear()
	_match_note.append({"text": str(r["text"]), "good": bool(r["accept"]), "main": true})
	for reason: Dictionary in (r["reasons"] as Array).slice(0, 4):
		_match_note.append({"text": ("+ " if reason["good"] else "– ") + str(reason["text"]), "good": bool(reason["good"])})
	Audio.play("court_good" if r["accept"] else "court_bad")
	if r["accept"]:
		_matching = false
		world.apply_life_events(events)
	_build_court()


func _build_court_recruit() -> void:
	var c := character
	var st := world.state
	_section(_court_box, "What they want")
	var can := Recruitment.eligible(st, c)
	if not can["ok"]:
		_court_box.add_child(_wrap_label(str(can["reason"]), 14, UITheme.BAD))
	var who := Recruitment.decider(st, c)
	if who != c:
		_court_box.add_child(_wrap_label("At %d they would join as a page. %s decides for them." % [c.age, who.full_name()], 14, UITheme.TEXT_DIM))
	if c.known_motives.is_empty():
		_court_box.add_child(_wrap_label("You don't know yet. Talk to them and ask about their life.", 14, UITheme.TEXT_DIM))
	else:
		var weights := Recruitment.motives(st, who)
		for id: String in c.known_motives:
			_court_box.add_child(_motive_row(id, float(weights.get(id, 0.0))))
	_court_box.add_child(_wrap_label("Offers are made face to face: walk up to %s and press %s to talk." % [c.first_name, world.key_hint("interact")], 13, UITheme.TEXT_DIM))
	_court_box.add_child(_wrap_label("Household: %d / %d  -  Gold: %d  -  Your word: %s" % [CourtSystem.retainer_count(st), CourtSystem.retainer_cap(st), st.house.gold, Recruitment.standing_label(st.house.standing)], 13, UITheme.TEXT_DIM))


## One known motive: what it is and how much it matters, in words.
func _motive_row(id: String, weight: float) -> Control:
	var cost := id in ["ties", "risk"]
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var name_l := UITheme.label("•  " + Recruitment.motive_name(id), 15, UITheme.BAD if cost else UITheme.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_l)
	var word := Recruitment.strength_word(weight)
	line.add_child(UITheme.label("holds them back %s" % word if cost else "matters %s" % word, 14, UITheme.TEXT_DIM))
	return line


func _build_court_retainer() -> void:
	var c := character
	var st := world.state
	_section(_court_box, "Service")
	var service := "%s  -  %d gold/day" % [CourtSystem.role_name(st, c), CourtSystem.wage(c)]
	if c.joined_day >= 0:
		var sworn := c.joined_day * Calendar.MINUTES_PER_DAY
		service += "  -  sworn %s %d, %d" % [Calendar.season_name(sworn).left(3), Calendar.day_of_season(sworn), Calendar.year(sworn)]
	var service_l := _wrap_label(service, 14)
	service_l.tooltip_text = "%s of %s" % [CourtSystem.role_name(st, c), CourtSystem.house_name(st)]
	service_l.mouse_filter = Control.MOUSE_FILTER_PASS
	_court_box.add_child(service_l)
	_court_bar(c.loyalty, 0.0, 100.0, "Loyalty %d  %s" % [roundi(c.loyalty), MoodSystem.loyalty_label(c.loyalty)], Color("#6fa8e6"))

	# Consequential actions stay visible before the office and training detail.
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	if not c.is_knight():
		var k := CourtSystem.can_knight(st, c)
		var kb := UITheme.button("Knight (%d gold)" % int(CourtSystem.section("knighthood").get("cost", 60)), _on_knight)
		kb.disabled = not k["ok"]
		kb.tooltip_text = str(k["reason"]) if not k["ok"] else "Raise them to knighthood: a big boost to loyalty, and renown for your house."
		actions.add_child(kb)
	var db := UITheme.button("Click again to dismiss" if _dismiss_armed else "Dismiss", _on_dismiss)
	db.tooltip_text = "Release them from your service. They won't be pleased."
	actions.add_child(db)
	_court_box.add_child(actions)

	# Office
	var office_row := HBoxContainer.new()
	office_row.add_theme_constant_override("separation", 8)
	var ol := UITheme.label("Office", 15)
	ol.custom_minimum_size.x = 80
	office_row.add_child(ol)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item("No office")
	var ids: Array[String] = [""]
	for o: Dictionary in CourtSystem.offices():
		var oid := str(o["id"])
		var holder := st.get_character(st.house.holder_of(oid))
		var text := str(o["name"])
		if holder and holder != c:
			text += " (held by %s)" % holder.first_name
		elif holder == null:
			text += " (vacant)"
		opt.add_item(text)
		opt.set_item_tooltip(opt.item_count - 1, str(o.get("description", "")))
		ids.append(oid)
	opt.selected = maxi(0, ids.find(c.office))
	opt.disabled = c.age < 16
	opt.tooltip_text = "Pages are too young for an office (16+)." if c.age < 16 else "Offices give the house a bonus and train the holder in their duties."
	opt.item_selected.connect(func(i: int) -> void: _on_office_chosen(ids[i]))
	office_row.add_child(opt)
	_court_box.add_child(office_row)

	# Training focus
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 8)
	var fl := UITheme.label("Train", 15)
	fl.custom_minimum_size.x = 80
	focus_row.add_child(fl)
	focus_row.add_child(_focus_picker(c))
	_court_box.add_child(focus_row)
	_training_lines(c)

func _build_court_player() -> void:
	var c := character
	var st := world.state
	var h := st.house
	_section(_court_box, "You")
	var role := CourtSystem.role_name(st, c)
	_court_box.add_child(_wrap_label("You are %s, %s. Your Appraisal shows you what no one else can see: everyone's hidden potential. Find the gifted, bring them into your household, and raise them into the great servants of your house." % [c.full_name(), ("heir of %s" % CourtSystem.house_name(st)) if role.begins_with("Heir") else role], 15))
	_section(_court_box, "Your house")
	var net := CourtSystem.daily_income(st) - CourtSystem.daily_wages(st)
	_court_box.add_child(UITheme.label("Gold: %d  (%+d per day)" % [h.gold, net], 15, UITheme.ACCENT))
	_court_box.add_child(UITheme.label("Renown: %d  -  Household: %d / %d retainers" % [h.renown, CourtSystem.retainer_count(st), CourtSystem.retainer_cap(st)], 15))
	_marriage_section(c)
	_section(_court_box, "Your studies")
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 8)
	var fl := UITheme.label("Study", 15)
	fl.custom_minimum_size.x = 80
	focus_row.add_child(fl)
	focus_row.add_child(_focus_picker(c))
	_court_box.add_child(focus_row)
	_training_lines(c)
	_court_box.add_child(_wrap_label("Your Politics makes conversations warmer and recruits more willing; your Leadership draws people to your banner.", 13, UITheme.TEXT_DIM))


func _focus_picker(c: CharacterData) -> OptionButton:
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current := CourtSystem.focus_of(c)
	for a: String in CourtSystem.TRAINABLE:
		if c.appraised:
			opt.add_item("%s  %d / %d  (%s)" % [CourtSystem.attr_name(a), c.get_current(a), c.get_potential(a), Appraisal.rank_id(c.get_potential(a))])
		else:
			opt.add_item("%s  %d / ?" % [CourtSystem.attr_name(a), c.get_current(a)])
		if a == current:
			opt.selected = opt.item_count - 1
	opt.tooltip_text = "Which talent to develop each day. Growth slows as they near their potential."
	opt.item_selected.connect(func(i: int) -> void: _on_focus_chosen(CourtSystem.TRAINABLE[i]))
	return opt


func _training_lines(c: CharacterData) -> void:
	var st := world.state
	var rates := CourtSystem.training_rates(st, c)
	if rates.is_empty():
		return
	for a: String in rates:
		var line := HBoxContainer.new()
		var text := "   %s  %d / %s" % [CourtSystem.attr_name(a), c.get_current(a), str(c.get_potential(a)) if c.appraised else "?"]
		var m := CourtSystem.mentor_for(st, c, a)
		if m["mentor"]:
			text += "  (mentored by %s)" % (m["mentor"] as CharacterData).first_name
		var name_l := UITheme.label(text, 14, UITheme.TEXT_DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(name_l)
		var rate := float(rates[a])
		var rate_text := "+%.2f / day" % rate if c.get_current(a) < c.get_potential(a) else "at potential"
		var rate_l := UITheme.label(rate_text, 14, UITheme.GOOD if rate > 0.0 else UITheme.TEXT_DIM)
		rate_l.custom_minimum_size.x = 92
		rate_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(rate_l)
		_court_box.add_child(line)


func _court_bar(value: float, lo: float, hi: float, text: String, color: Color) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var bar := ProgressBar.new()
	bar.min_value = lo
	bar.max_value = hi
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := UITheme.box(color, Color(0, 0, 0, 0), 0, 3, 0)
	fill.shadow_size = 0
	bar.add_theme_stylebox_override("fill", fill)
	line.add_child(bar)
	var l := UITheme.label(text, 14, UITheme.TEXT_DIM)
	l.custom_minimum_size.x = 170
	line.add_child(l)
	_court_box.add_child(line)


func _mini_bar(value: float, lo: float, hi: float, color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = lo
	bar.max_value = hi
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := UITheme.box(color, Color(0, 0, 0, 0), 0, 3, 0)
	fill.shadow_size = 0
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _wrap_label(text: String, size: int, color: Color = UITheme.TEXT) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	return l


func _day_rng(stream: String) -> RandomNumberGenerator:
	var st := world.state
	return Seeds.rng(st.world_seed, "%s_%d_%d" % [stream, character.id, st.day()])


func _after_action(result: Dictionary, good: bool = true) -> void:
	Game.notify.emit(str(result.get("text", "")), Game.COLOR_GOOD if good else Game.COLOR_BAD)
	world.court_changed(character.id)


func _on_talk() -> void:
	world.try_talk(character.id)


func _on_gift() -> void:
	var result := CourtSystem.gift(world.state, character)
	Audio.play("coins" if bool(result.get("ok", true)) else "ui_error")
	_after_action(result)


func _on_office_chosen(office_id: String) -> void:
	var st := world.state
	if office_id.is_empty():
		if not character.office.is_empty():
			var old := CourtSystem.office_name(character.office)
			CourtSystem.vacate(st, character.office)
			_after_action({"text": "%s no longer serves as %s." % [character.first_name, old]})
		return
	var previous := st.house.holder_of(office_id)
	var result := CourtSystem.appoint(st, office_id, character)
	Audio.play("court_good" if bool(result.get("ok", false)) else "ui_error")
	_after_action(result, bool(result.get("ok", false)))
	if previous >= 0 and previous != character.id:
		world.court_changed(previous)


func _on_focus_chosen(attr_id: String) -> void:
	CourtSystem.set_focus(world.state, character, attr_id)
	_after_action({"text": "%s will now train %s." % ["You" if world.state.is_player(character) else character.first_name, CourtSystem.attr_name(attr_id)]})


func _on_knight() -> void:
	var result := CourtSystem.knight(world.state, character)
	Audio.play("knighted" if bool(result.get("ok", false)) else "ui_error")
	_after_action(result, bool(result.get("ok", false)))


func _on_dismiss() -> void:
	if not _dismiss_armed:
		_dismiss_armed = true
		_build_court()
		return
	_dismiss_armed = false
	var name_text := character.full_name()
	CourtSystem.dismiss(world.state, character)
	Audio.play("dismissed")
	_after_action({"text": "You dismissed %s from your service." % name_text}, false)


# --- Personality tab -----------------------------------------------------------------------

func _build_personality() -> void:
	_clear(_personality_box)
	var c := character
	_section(_personality_box, "Traits")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for t in c.traits:
		var def := GameData.trait_def(t)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.box(Color("#2f241a"), UITheme.GOLD_DIM, 1, 10, 4))
		chip.tooltip_text = str(def.get("description", ""))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var l := UITheme.label(str(def.get("name", t)), 15)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(l)
		flow.add_child(chip)
	_personality_box.add_child(flow)

	_section(_personality_box, "Disposition")
	_meter("Happiness", c.happiness, MoodSystem.happiness_label(c.happiness), Color("#8fd16a"))
	_meter("Loyalty", c.loyalty, MoodSystem.loyalty_label(c.loyalty), Color("#6fa8e6"))
	_meter("Stress", c.stress, MoodSystem.stress_label(c.stress), Color("#e07a6a"))
	var amb := c.get_current("ambition")
	_meter("Ambition", minf(amb, 100.0), "%s (ceiling %d)" % [MoodSystem.ambition_label(amb), c.get_potential("ambition")] if c.appraised else MoodSystem.ambition_label(amb), Color("#e9bf62"))

	_section(_personality_box, "Why they feel this way")
	_factor_list("Happiness", MoodSystem.happiness_factors(c, world.state), MoodSystem.happiness_target(c, world.state))
	_factor_list("Loyalty to %s" % (world.state.ruling_family().display_name() if world.state.ruling_family() else "the lord"),
		MoodSystem.loyalty_factors(c, world.state), MoodSystem.loyalty_target(c, world.state))


func _meter(title: String, value: float, text: String, color: Color) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var l := UITheme.label(title, 15)
	l.custom_minimum_size.x = 90
	line.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := UITheme.box(color, Color(0, 0, 0, 0), 0, 3, 0)
	fill.shadow_size = 0
	bar.add_theme_stylebox_override("fill", fill)
	line.add_child(bar)
	var v := UITheme.label("%d  %s" % [roundi(value), text], 14, UITheme.TEXT_DIM)
	v.custom_minimum_size.x = 150
	line.add_child(v)
	_personality_box.add_child(line)


func _factor_list(title: String, factors: Array[Dictionary], target: float) -> void:
	_personality_box.add_child(UITheme.label("%s  (trending toward %d)" % [title, roundi(target)], 15, UITheme.TEXT))
	for f in factors:
		var v := float(f["value"])
		if str(f["label"]) == "Baseline":
			continue
		var row := HBoxContainer.new()
		var name_l := UITheme.label("   " + str(f["label"]), 14, UITheme.TEXT_DIM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		row.add_child(UITheme.label("%+d" % roundi(v), 14, UITheme.value_color(v)))
		_personality_box.add_child(row)


# --- Relationships tab --------------------------------------------------------------------

func _build_relationships() -> void:
	_clear(_relations_box)
	var c := character
	var groups := [
		["Family", ["spouse", "late_spouse", "parent", "child", "sibling", "grandparent", "grandchild"]],
		["Friends", ["friend"]],
		["Rivals", ["rival"]],
	]
	if c.is_adult():
		groups.insert(1, ["Romance", ["lover", "spouse"]])
	var any := false
	for g: Array in groups:
		var rels := c.relationships_of_type(g[1])
		if g[0] == "Romance":
			if rels.is_empty():
				_section(_relations_box, "Romance")
				_relations_box.add_child(UITheme.label("No one has caught their eye.", 14, UITheme.TEXT_DIM))
				continue
		if rels.is_empty():
			continue
		any = true
		_section(_relations_box, str(g[0]))
		for r in rels:
			_relation_row(r)
	if not any:
		_relations_box.add_child(UITheme.label("A stranger to everyone.", 14, UITheme.TEXT_DIM))


func _relation_row(r: Dictionary) -> void:
	var other := world.state.get_character(int(r["target"]))
	if other == null:
		_departed_row(r)
		return
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 15)
	var rel_name := _relation_name(str(r["type"]), other)
	b.text = "%s  -  %s, %d, %s" % [other.full_name(), rel_name, other.age, other.occupation_name()]
	b.tooltip_text = "Open %s's card" % other.first_name
	b.pressed.connect(func() -> void: character_link_pressed.emit(other.id))
	var row := HBoxContainer.new()
	row.add_child(b)
	var op := int(r["opinion"])
	var op_l := UITheme.label("%+d" % op, 15, UITheme.opinion_color(op))
	op_l.custom_minimum_size.x = 42
	op_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	op_l.tooltip_text = "Opinion of %s" % other.first_name
	op_l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(op_l)
	_relations_box.add_child(row)


## Kin who have died or moved away, remembered on the card (not a link).
func _departed_row(r: Dictionary) -> void:
	var gone := world.state.get_departed(int(r["target"]))
	if gone == null or not (str(r["type"]) in LifeSystem.KIN or str(r["type"]) == "late_spouse"):
		return
	var when := Calendar.year(gone.departed_day * Calendar.MINUTES_PER_DAY)
	var how := "died %d, aged %d" % [when, gone.age] if gone.departed_how == "died" else "moved away in %d" % when
	var l := UITheme.label("%s%s  -  %s, %s" % ["\u2020 " if gone.departed_how == "died" else "", gone.full_name(), _relation_name(str(r["type"]), gone), how], 15, UITheme.TEXT_DIM)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = "Died of %s" % gone.departed_cause if gone.departed_how == "died" else "Left %s to seek their fortune" % world.state.village_name
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	_relations_box.add_child(l)


static func _relation_name(type: String, other: CharacterData) -> String:
	var male := other.gender == "male"
	match type:
		"spouse":
			return "Husband" if male else "Wife"
		"late_spouse":
			return "Late husband" if male else "Late wife"
		"parent":
			return "Father" if male else "Mother"
		"child":
			return "Son" if male else "Daughter"
		"sibling":
			return "Brother" if male else "Sister"
		"grandparent":
			return "Grandfather" if male else "Grandmother"
		"grandchild":
			return "Grandson" if male else "Granddaughter"
		"lover":
			return "Sweetheart"
	return type.capitalize()


# --- History tab ----------------------------------------------------------------------------

func _build_history() -> void:
	_clear(_history_box)
	for h: Dictionary in character.history:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var date := UITheme.label("%s %d" % [str(h.get("season", "")).left(3), int(h["year"])], 14, UITheme.TEXT_DIM)
		date.custom_minimum_size.x = 78
		row.add_child(date)
		var cat := str(h["category"])
		var color: Color = UITheme.CATEGORY_COLORS.get(cat, UITheme.TEXT)
		var tag := UITheme.label(cat.capitalize(), 12, color)
		tag.custom_minimum_size.x = 82
		row.add_child(tag)
		var text := str(h["text"])
		if cat == "rumor":
			text = "Rumor has it: " + text.left(1).to_lower() + text.substr(1)
		var t := UITheme.label(text, 15, UITheme.TEXT if cat != "rumor" else color.lightened(0.3))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		_history_box.add_child(row)
