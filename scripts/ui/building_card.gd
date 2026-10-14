class_name BuildingCard
extends PanelContainer
## What a building is and who it serves: residents and workers (click to
## open their card), jobs and output for workplaces, and for homes their
## level with a checklist of what the next level needs. Building sites show
## their progress and crew.

signal close_requested
signal character_chosen(character_id: int)

const WIDTH := 460.0

var world: VillageWorld
var building_id := -1
var _title: Label
var _subtitle: Label
var _body: VBoxContainer
var _live := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var row := HBoxContainer.new()
	root.add_child(row)
	_title = UITheme.label("", 22, UITheme.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_title)
	var close := UITheme.button("X", close_requested.emit)
	close.tooltip_text = "Close (Esc)"
	row.add_child(close)
	_subtitle = UITheme.label("", 16, UITheme.ACCENT)
	root.add_child(_subtitle)
	root.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	scroll.add_child(_body)


func show_building(id: int) -> void:
	building_id = id
	visible = id >= 0
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_live -= delta
	if _live <= 0.0:
		_live = 1.0
		refresh()


## The building or site this card shows (null when it's gone).
func _subject() -> Dictionary:
	var st := world.state
	var site := st.territory.get_site(building_id) if st.territory else null
	var b := st.get_building(building_id)
	if b == null and site:
		b = site.building
	return {"building": b, "site": site}


func refresh() -> void:
	if world == null or _body == null or building_id < 0:
		return
	var subject := _subject()
	var b: BuildingData = subject["building"]
	var site: ConstructionSite = subject["site"]
	if b == null:
		close_requested.emit()
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var st := world.state
	var in_layout := st.get_building(b.id) != null
	_title.text = b.name
	var kind := "Home" if GrowthSystem.is_home(b) else "Workplace" if not st.workers_of(b.id).is_empty() else "Building"
	_subtitle.text = "%s  -  %s" % [b.type_name(), kind] if in_layout else "%s  -  being built" % TerritorySystem.display_name(b.type)
	if site:
		_site(st, site)
	if not in_layout:
		return
	_people(st, b)
	if GrowthSystem.can_level(b):
		_home(st, b, site)
	_work(st, b)


func _site(st: WorldState, site: ConstructionSite) -> void:
	_heading("Upgrading to %s" % GrowthSystem.tier_def(site.target_tier).get("name", "") if site.is_upgrade() else "Under construction")
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = site.progress()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	_body.add_child(bar)
	var days := TerritorySystem.days_left(st, site)
	var crew: Array[String] = []
	for id in site.builders:
		var c := st.get_character(id)
		if c:
			crew.append(c.first_name)
	if crew.is_empty():
		_body.add_child(_wrap("%d%% done. No one is free to build it." % floori(site.progress() * 100.0), 14, UITheme.BAD))
	else:
		_body.add_child(_wrap("%d%% done, about %s left. Crew: %s." % [floori(site.progress() * 100.0), BuildPanel._duration(days), ", ".join(crew)], 14, UITheme.TEXT))
	var site_id := site.id()
	var cancel := UITheme.button("Call it off", func() -> void: world.cancel_site(site_id))
	cancel.tooltip_text = "Full refund before work starts, half after"
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(cancel)


func _people(st: WorldState, b: BuildingData) -> void:
	var residents := st.residents_of(b.id)
	if not residents.is_empty():
		var fam := st.get_family(residents[0].family_id)
		_heading("Home of the %s" % (fam.display_name() if fam else residents[0].last_name + " family"))
		for c in residents:
			_body.add_child(_person(c))
	elif GrowthSystem.is_home(b):
		_heading("Empty")
		_body.add_child(_wrap("No one lives here yet. The next family of settlers will move in.", 14, UITheme.TEXT_DIM))


func _home(st: WorldState, b: BuildingData, site: ConstructionSite) -> void:
	var tier := b.tier
	var def := GrowthSystem.tier_def(tier)
	_heading("Home level: %s (%d of %d)" % [str(def.get("name", "")), tier + 1, GrowthSystem.max_tier() + 1])
	var perks: Array[String] = []
	if int(def.get("rent", 0)) > 0:
		perks.append("pays %d gold rent a day" % int(def.get("rent", 0)))
	if float(def.get("happiness", 0)) > 0.0:
		perks.append("+%d happiness for the family" % int(def.get("happiness", 0)))
	if not perks.is_empty():
		_body.add_child(_wrap("This home " + " and ".join(perks) + ".", 14, UITheme.GOOD))
	if tier >= GrowthSystem.max_tier():
		_body.add_child(_wrap("The finest home a family can have here.", 14, UITheme.TEXT_DIM))
		return
	var next := GrowthSystem.tier_def(tier + 1)
	_body.add_child(UITheme.label("Next: %s  (%s)" % [str(next.get("name", "")), TerritorySystem.cost_text(next.get("cost", {}))], 15, UITheme.ACCENT))
	var all_ok := true
	for need in GrowthSystem.home_needs(st, b):
		var ok: bool = need["ok"]
		all_ok = all_ok and ok
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(NeedMark.new(ok))
		var text := UITheme.label("%s  (%s)" % [need["label"], need["detail"]], 14, UITheme.TEXT if ok else UITheme.TEXT_DIM)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_body.add_child(row)
	var status := ""
	if site and site.is_upgrade():
		status = "Being upgraded now."
	elif st.residents_of(b.id).is_empty():
		status = "Only lived-in homes are upgraded."
	elif not all_ok:
		status = "It will be upgraded once every need is met."
	elif not st.territory.auto_homes:
		status = "Ready, but homes and upgrades are switched off in the Build panel."
	elif not GrowthSystem.affordable_with_reserve(st, next.get("cost", {})):
		status = "Ready: waiting for materials (the stores keep a reserve for your orders)."
	else:
		status = "Ready: the family will start when builders are free."
	_body.add_child(_wrap(status, 14, UITheme.NEUTRAL))


func _work(st: WorldState, b: BuildingData) -> void:
	var workers := st.workers_of(b.id)
	var jobs: Dictionary = TerritorySystem.buildable_def(b.type).get("jobs", {}) if st.territory.built.has(b.id) else {}
	if workers.is_empty() and jobs.is_empty():
		return
	_heading("Workers")
	for occ: String in jobs:
		var have := 0
		for c in workers:
			if c.occupation_id == occ:
				have += 1
		var name := str(GameData.occupation(occ).get("name", occ))
		_body.add_child(UITheme.label("%s: %d of %d jobs filled" % [name, have, int(jobs[occ])], 14, UITheme.TEXT if have >= int(jobs[occ]) else UITheme.BAD))
	var output := {}
	for c in workers:
		var w := TerritorySystem.worker_output(st, c)
		for r: String in w:
			output[r] = float(output.get(r, 0.0)) + float(w[r])
	if not output.is_empty():
		var parts: Array[String] = []
		for r: String in output:
			parts.append("%.1f %s" % [float(output[r]), TerritorySystem.resource_name(r).to_lower()])
		_body.add_child(_wrap("Makes %s a day." % ", ".join(parts), 14, UITheme.GOOD))
	for c in workers:
		_body.add_child(_person(c))


func _person(c: CharacterData) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 14)
	b.text = "%s, %d  -  %s" % [c.display_name(), c.age, CourtSystem.role_name(world.state, c)]
	b.tooltip_text = "Open %s's card" % c.first_name
	var id := c.id
	b.pressed.connect(func() -> void: character_chosen.emit(id))
	return b


func _heading(text: String) -> void:
	_body.add_child(UITheme.label(text, 17, UITheme.ACCENT, true))


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40
	return l


## A drawn tick or cross (the game's fonts have no check-mark glyphs).
class NeedMark extends Control:
	var ok := false

	func _init(met: bool) -> void:
		ok = met
		custom_minimum_size = Vector2(18, 18)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if ok:
			draw_polyline(PackedVector2Array([Vector2(3, 9), Vector2(7, 14), Vector2(15, 4)]), UITheme.GOOD, 2.5, true)
		else:
			draw_line(Vector2(4, 4), Vector2(14, 14), UITheme.BAD, 2.5, true)
			draw_line(Vector2(14, 4), Vector2(4, 14), UITheme.BAD, 2.5, true)
