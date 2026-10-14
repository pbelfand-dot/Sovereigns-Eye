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
var _banner: PanelContainer
var _banner_label: Label
var _tabs: TabContainer
var _appraisal_box: VBoxContainer
var _personality_box: VBoxContainer
var _relations_box: VBoxContainer
var _history_box: VBoxContainer
var _live_refresh := 0.0


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
	var follow := UITheme.button("Follow (C)", _on_follow)
	follow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(follow)

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
	character = c
	visible = c != null
	if c == null:
		_portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# An AI portrait (user://portraits/<seed>/<id>.png) wins; otherwise the
	# character's 3D model is rendered live as a placeholder.
	var ai_portrait := PortraitPrompt.image_for(c, world.state.world_seed)
	if ai_portrait:
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
	var c := character
	_name_label.text = c.full_name()
	_sub_label.text = "%s  -  %s" % [c.occupation_name(), c.status_name()]
	_age_label.text = "Age %d  -  %s" % [c.age, c.gender.capitalize()]
	var fam := world.state.get_family(c.family_id)
	_family_label.text = "%s (%s)" % [fam.display_name(), fam.background_name()] if fam else ""
	var home := world.state.get_building(c.home_building_id)
	_home_label.text = "Lives at %s" % (home.name if home else "no fixed home")
	_refresh_banner()
	_build_appraisal()
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
	var best := c.best_attribute()
	var p := c.get_potential(best)
	var color := Appraisal.rank_color(p)
	var attr_name := str(GameData.attribute_def(best).get("name", best))
	if Appraisal.is_exceptional(c):
		_banner_label.text = "EXCEPTIONAL TALENT  -  %s %s (%s)" % [attr_name, Appraisal.rank_id(p), Appraisal.rank_title(p)]
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
	_meter("Ambition", minf(amb, 100.0), "%s (ceiling %d)" % [MoodSystem.ambition_label(amb), c.get_potential("ambition")], Color("#e9bf62"))

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
		["Family", ["spouse", "parent", "child", "sibling", "grandparent", "grandchild"]],
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


static func _relation_name(type: String, other: CharacterData) -> String:
	var male := other.gender == "male"
	match type:
		"spouse":
			return "Husband" if male else "Wife"
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
