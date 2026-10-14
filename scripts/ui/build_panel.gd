class_name BuildPanel
extends PanelContainer
## The village's works: stores with what comes in and goes out each day,
## buildings the player can order (pick one, then place it in the world),
## sites under construction with their crews, and the Master of Works.

signal character_chosen(character_id: int)
signal close_requested

var world: VillageWorld
var _body: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(540, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := UITheme.label("Build", 22, UITheme.TEXT, true)
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
	if st.territory == null:
		return
	_stores(st)
	_growth(st)
	_orders(st)
	_sites(st)
	_overseer(st)


func _stores(st: WorldState) -> void:
	_heading("Stores")
	var prod := TerritorySystem.production(st)
	var cons := TerritorySystem.consumption(st)
	for r: String in TerritorySystem.RESOURCES:
		var def := TerritorySystem.resource_def(r)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := UITheme.label(str(def.get("name", r)), 15, Color(str(def.get("color", "#ffffff"))))
		name_l.custom_minimum_size.x = 70
		name_l.tooltip_text = str(def.get("description", ""))
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_l)
		var cap := TerritorySystem.capacity(st, r)
		var amount := st.territory.amount(r)
		var amount_l := UITheme.label("%d / %d" % [floori(amount), roundi(cap)], 15, UITheme.BAD if amount >= cap - 0.5 else UITheme.TEXT)
		amount_l.custom_minimum_size.x = 100
		row.add_child(amount_l)
		var net := float(prod.get(r, 0.0)) - float(cons.get(r, 0.0))
		var detail := "%+.1f a day  (made %.1f, used %.1f)" % [net, float(prod.get(r, 0.0)), float(cons.get(r, 0.0))]
		row.add_child(UITheme.label(detail, 14, UITheme.value_color(snappedf(net, 0.1))))
		_body.add_child(row)
	if TerritorySystem.is_hungry(st):
		_body.add_child(_wrap("The granary is empty and the village is going hungry. Everyone is unhappier until there is food again.", 14, UITheme.BAD))
	var season := st.current_season()
	var food_f := TerritorySystem.season_factor(st, "food")
	if food_f != 1.0:
		_body.add_child(_wrap("%s: fields yield %d%% of their usual food." % [season, roundi(food_f * 100.0)], 13, UITheme.TEXT_DIM))


func _growth(st: WorldState) -> void:
	_heading("Village growth")
	var t := st.territory
	var homes := GrowthSystem.homes(st)
	var empty := GrowthSystem.empty_homes(st).size()
	var cap := int(GrowthSystem.growth_cfg().get("max_population", 110))
	_body.add_child(UITheme.label("%d people (room for %d)  -  %d homes, %d empty" % [GrowthSystem.population(st), cap, homes.size(), empty], 15))
	var counts := []
	for tier in GrowthSystem.max_tier() + 1:
		counts.append(0)
	var farms := 0
	for b in homes:
		if GrowthSystem.can_level(b):
			counts[b.tier] += 1
		else:
			farms += 1
	var levels: Array[String] = []
	for tier in counts.size():
		levels.append("%d %s" % [counts[tier], str(GrowthSystem.tier_def(tier).get("name", "")).to_lower() + ("s" if counts[tier] != 1 else "")])
	if farms > 0:
		levels.append("%d farm%s" % [farms, "s" if farms != 1 else ""])
	var rent := GrowthSystem.rent(st)
	_body.add_child(_wrap(", ".join(levels) + (".  Rent %+d gold a day." % roundi(rent) if rent > 0.0 else "."), 14, UITheme.TEXT_DIM))
	# Settler bar.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UITheme.label("Settlers", 15, UITheme.ACCENT))
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = t.settler_progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(UITheme.label("%d%%" % floori(t.settler_progress), 14))
	_body.add_child(row)
	var per_day := GrowthSystem.progress_per_day(st)
	var note := ""
	if GrowthSystem.at_capacity(st):
		note = "The village is as large as it can grow for now."
	elif per_day <= 0.0:
		note = "No one wants to settle here: make the village more appealing."
	elif empty == 0 and t.settler_progress >= 100.0:
		note = "A family is waiting for an empty home."
	else:
		note = "Next family in about %s." % BuildPanel._duration((100.0 - t.settler_progress) / per_day) if t.settler_progress < 100.0 else "A family arrives tomorrow."
		if empty == 0:
			note += " They will need an empty home."
	_body.add_child(_wrap(note, 14, UITheme.TEXT))
	var appeal := GrowthSystem.appeal(st)
	_body.add_child(UITheme.label("Appeal %+d" % roundi(appeal), 15, UITheme.value_color(appeal)))
	for f in GrowthSystem.appeal_factors(st):
		_body.add_child(UITheme.label("   %+d  %s" % [roundi(float(f["value"])), str(f["label"])], 13, UITheme.value_color(float(f["value"]))))
	var toggle := CheckButton.new()
	toggle.text = "Villagers build homes and upgrades by themselves"
	toggle.button_pressed = t.auto_homes
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.toggled.connect(func(on: bool) -> void:
		t.auto_homes = on
		refresh())
	_body.add_child(toggle)
	var reserve: Dictionary = GrowthSystem.growth_cfg().get("auto", {}).get("reserve", {})
	_body.add_child(_wrap("They always leave %s in the stores for your own orders." % TerritorySystem.cost_text(reserve), 13, UITheme.TEXT_DIM))


func _orders(st: WorldState) -> void:
	_heading("Order a building")
	_body.add_child(_wrap("Pick one, then click beside a road to place it. It turns to face the road and a lane is laid to its door. T turns it, Shift+click places another, Esc cancels.", 13, UITheme.TEXT_DIM))
	for def: Dictionary in TerritorySystem.buildable():
		var type := str(def["type"])
		var allowed := TerritorySystem.can_build(st, type)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var b := Button.new()
		b.text = str(def.get("name", type))
		b.custom_minimum_size.x = 190
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not allowed["ok"]
		b.tooltip_text = str(def.get("description", ""))
		b.pressed.connect(func() -> void: world.start_placing(type))
		row.add_child(b)
		var cost: Dictionary = def.get("cost", {})
		var cost_l := UITheme.label(TerritorySystem.cost_text(cost), 14, UITheme.ACCENT if TerritorySystem.can_afford(st, cost) else UITheme.BAD)
		cost_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cost_l)
		row.add_child(UITheme.label("%d/%d" % [TerritorySystem.count_built(st, type), int(def.get("limit", 99))], 13, UITheme.TEXT_DIM))
		box.add_child(row)
		var info := str(def.get("description", ""))
		var jobs: Dictionary = def.get("jobs", {})
		if not jobs.is_empty():
			var parts: Array[String] = []
			for occ: String in jobs:
				parts.append("%d %s" % [int(jobs[occ]), str(GameData.occupation(occ).get("name", occ)).to_lower()])
			info += " Jobs: " + ", ".join(parts) + "."
		if not allowed["ok"]:
			info += "  " + str(allowed["reason"])
		box.add_child(_wrap(info, 13, UITheme.TEXT_DIM if allowed["ok"] else UITheme.NEUTRAL))
		_body.add_child(box)


func _sites(st: WorldState) -> void:
	var sites := st.territory.sites
	if sites.is_empty():
		return
	_heading("Under construction")
	for s in sites:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var title := s.building.name
		if s.is_upgrade():
			title = "%s: adding a floor (%s)" % [s.building.name, str(GrowthSystem.tier_def(s.target_tier).get("name", ""))]
		elif s.kind == "home":
			title = "New cottage for settlers"
		var name_l := UITheme.label(title, 15, UITheme.ACCENT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		row.add_child(name_l)
		row.add_child(UITheme.label("%d%%" % floori(s.progress() * 100.0), 15))
		var site_id := s.id()
		var show := UITheme.button("Show", func() -> void: world.focus_site(site_id))
		show.tooltip_text = "Move the camera to the site"
		row.add_child(show)
		var cancel := UITheme.button("Cancel", func() -> void: world.cancel_site(site_id))
		cancel.tooltip_text = "Abandon it (full refund before work starts, half after)"
		row.add_child(cancel)
		box.add_child(row)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = s.progress()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		box.add_child(bar)
		var days := TerritorySystem.days_left(st, s)
		if s.builders.is_empty() or days == INF:
			box.add_child(_wrap("No one is free to build it.", 13, UITheme.BAD))
		else:
			var crew: Array[String] = []
			for id in s.builders:
				var c := st.get_character(id)
				if c:
					crew.append("%s (%s)" % [c.first_name, c.occupation_name().to_lower()])
			box.add_child(_wrap("Crew: %s  -  about %s left" % [", ".join(crew), _duration(days)], 13, UITheme.TEXT_DIM))
		_body.add_child(box)


func _overseer(st: WorldState) -> void:
	_heading("Master of Works")
	var o := TerritorySystem.overseer(st)
	if o:
		var b := Button.new()
		b.theme_type_variation = "RowButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s  -  Administration %d: building %d%% faster" % [o.display_name(), o.get_current("administration"), roundi((TerritorySystem.speed_factor(st) - 1.0) * 100.0)]
		b.pressed.connect(func() -> void: character_chosen.emit(o.id))
		_body.add_child(b)
	else:
		_body.add_child(_wrap("No one oversees the works. Appoint a retainer with a head for Administration as Master of Works (their card's Court tab) and every site goes faster. Appraise villagers to find hidden talent.", 13, UITheme.TEXT_DIM))


static func _duration(days: float) -> String:
	if days < 1.0:
		return "%d hours" % maxi(1, ceili(days * 24.0))
	return "%.1f days" % days


func _heading(text: String) -> void:
	_body.add_child(UITheme.label(text, 17, UITheme.ACCENT, true))
	_body.add_child(HSeparator.new())


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	return l
