class_name BuildPanel
extends PanelContainer
## The village's works: its charter and the next one to petition for,
## stores with what comes in and goes out each day, the market (Phase 6.1:
## prices, buying and selling, the steward's standing orders), buildings the
## player can order (pick one, then place it in the world), sites under
## construction with their crews, and the Master of Works.

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
	_charter(st)
	_stores(st)
	_market(st)
	_growth(st)
	_orders(st)
	_sites(st)
	_overseer(st)


## The charter: what the settlement is now, and what the next charter asks
## for, as a checklist, with the petition to the Crown.
func _charter(st: WorldState) -> void:
	_heading("Charter: %s of %s" % [CharterSystem.title(st), st.village_name])
	var now := CharterSystem.current(st)
	_body.add_child(_wrap("%s  Room for %d people (%d live here); %d gold a day in dues and trade." % [
		str(CharterSystem.tier_def(now).get("description", "")), CharterSystem.max_population(st), GrowthSystem.population(st), CharterSystem.dues(st)], 14, UITheme.TEXT))
	var check := CharterSystem.can_petition(st)
	var next := int(check["next"])
	if next < 0:
		return
	_body.add_child(UITheme.label("Next: a %s charter" % CharterSystem.title_of(next), 15, UITheme.ACCENT))
	for r in CharterSystem.requirements(st, next):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(BuildingCard.NeedMark.new(bool(r["ok"])))
		var l := UITheme.label("%s  (%s)" % [r["label"], r["detail"]], 14, UITheme.TEXT if r["ok"] else UITheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_body.add_child(row)
	var cost: Dictionary = CharterSystem.tier_def(next).get("cost", {})
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	var b := UITheme.button("Petition the Crown", func() -> void: world.petition_charter())
	b.disabled = not check["ok"]
	b.tooltip_text = "Grants " + CharterSystem.grants_text(next) + "." if check["ok"] else str(check["reason"])
	row2.add_child(b)
	row2.add_child(UITheme.label("Fee: " + TerritorySystem.cost_text(cost), 14, UITheme.ACCENT if TerritorySystem.can_afford(st, cost) else UITheme.BAD))
	_body.add_child(row2)
	_body.add_child(_wrap("Grants " + CharterSystem.grants_text(next) + ".", 13, UITheme.TEXT_DIM))


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


## The market: today's prices, buying and selling in lots, the steward's
## standing orders and the latest trades (Phase 6.1).
func _market(st: WorldState) -> void:
	if st.market == null:
		return
	_heading("Market")
	var halls := Market.halls(st)
	var where := "The merchant's stall in the square" if halls == 0 else ("%d Market Hall%s" % [halls, "s" if halls != 1 else ""])
	var m := Market.best_merchant(st)
	_body.add_child(_wrap("%s: up to %d of each good a day. You pay %d%% over the price and get %d%% under it%s." % [where, Market.volume(st),
		roundi(Market.spread(st) * 100.0), roundi(Market.spread(st) * 100.0), (", %s haggling for you (Politics %d)" % [m.first_name, m.get_current("politics")]) if m else ""], 14, UITheme.TEXT))
	var h := Market.harvest(st)
	_body.add_child(_wrap("This year: %s. Food is %s until the next harvest; bread is dearest in spring and cheapest after the harvest." % [h["name"],
		"dear" if float(h.get("price", 1.0)) > 1.05 else ("cheap" if float(h.get("price", 1.0)) < 0.95 else "at its usual price")], 13, UITheme.TEXT_DIM))
	var lots: Array = Market.section("trade").get("lots", [10, 50])
	for good: String in Market.GOODS:
		var def := TerritorySystem.resource_def(good)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var name_l := UITheme.label(str(def.get("name", good)), 15, Color(str(def.get("color", "#ffffff"))))
		name_l.custom_minimum_size.x = 56
		row.add_child(name_l)
		var p := Market.price(st, good)
		var fair := Market.fair_price(st, good)
		var price_l := UITheme.label("%.2f" % p, 15, UITheme.TEXT if absf(p - fair) < 0.005 else UITheme.ACCENT)
		price_l.custom_minimum_size.x = 40
		price_l.tooltip_text = "Gold a unit at the market today (buy at %.2f, sell at %.2f).%s" % [Market.buy_price(st, good), Market.sell_price(st, good),
			"" if absf(p - fair) < 0.005 else " Your own trade has moved it from %.2f; it recovers day by day." % fair]
		price_l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(price_l)
		var room := Market.room(st, good)
		for n: int in lots:
			var units := n
			var have := floori(TerritorySystem.amount(st, good))
			var sell_n := mini(units, mini(room, have))
			var b := UITheme.button("Sell %d" % units, func() -> void: _trade(Market.sell(st, good, units)))
			b.disabled = sell_n <= 0
			b.tooltip_text = "Sell %d for %d gold." % [sell_n, -Market.quote(st, good, -sell_n)] if sell_n > 0 else ("The market will take no more today." if room <= 0 else "Nothing to sell.")
			row.add_child(b)
		for n: int in lots:
			var units := n
			var buy_n := Market.can_buy_units(st, good, units)
			var cost := Market.quote(st, good, buy_n)
			var b := UITheme.button("Buy %d" % units, func() -> void: _trade(Market.buy(st, good, units)))
			b.disabled = buy_n <= 0 or cost > st.house.gold
			b.tooltip_text = ("Buy %d for %d gold." % [buy_n, cost]) if buy_n > 0 else ("The market has no more today." if room <= 0 else "The stores are full.")
			row.add_child(b)
		_body.add_child(row)
	if room_note(st) != "":
		_body.add_child(_wrap(room_note(st), 13, UITheme.TEXT_DIM))
	# The steward's standing orders.
	_body.add_child(UITheme.label("Your steward's standing orders", 15, UITheme.ACCENT))
	if not Market.has_steward(st):
		_body.add_child(_wrap("Appoint a steward (Court panel, a retainer's card) to keep them: each morning, buy what a store lacks of its mark and sell what it holds above another.", 13, UITheme.TEXT_DIM))
	else:
		_body.add_child(_wrap("Each morning: buy up to the keep mark, sell above the sell mark, never spending below %d gold (the wages' reserve)." % Market.reserve(st), 13, UITheme.TEXT_DIM))
	var step := int(Market.section("orders").get("step", 50))
	for good: String in Market.GOODS:
		var o := st.market.order(good)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var name_l := UITheme.label(TerritorySystem.resource_name(good), 14, UITheme.TEXT)
		name_l.custom_minimum_size.x = 56
		row.add_child(name_l)
		for which: String in ["keep", "sell"]:
			var key := which
			var v := int(o[key])
			row.add_child(UITheme.label("Keep" if key == "keep" else "Sell above", 14, UITheme.TEXT_DIM))
			row.add_child(UITheme.button("-", func() -> void: _set_mark(st, good, key, v - step if v - step > 0 else -1)))
			var v_l := UITheme.label("none" if v < 0 else str(v), 14, UITheme.TEXT)
			v_l.custom_minimum_size.x = 40
			v_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(v_l)
			row.add_child(UITheme.button("+", func() -> void: _set_mark(st, good, key, step if v < 0 else mini(v + step, roundi(TerritorySystem.capacity(st, good))))))
		_body.add_child(row)
	# The latest trades.
	var recent := st.market.ledger.slice(maxi(0, st.market.ledger.size() - 4))
	recent.reverse()
	for e: Dictionary in recent:
		var units := int(e["units"])
		_body.add_child(_wrap("%s: %s %s %d %s for %d gold." % [Calendar.format_date(int(e["day"]) * Calendar.MINUTES_PER_DAY), "You" if e["by"] == "you" else "Your steward",
			"bought" if units > 0 else "sold", absi(units), TerritorySystem.resource_name(str(e["good"])).to_lower(), absi(int(e["gold"]))], 13, UITheme.TEXT_DIM))


## What's left to trade today, when some of it has gone.
func room_note(st: WorldState) -> String:
	var parts: Array[String] = []
	for good: String in Market.GOODS:
		var left := Market.room(st, good)
		if left < Market.volume(st):
			parts.append("%d %s" % [left, TerritorySystem.resource_name(good).to_lower()])
	return ("Left to trade today: " + ", ".join(parts) + ".") if not parts.is_empty() else ""


func _trade(r: Dictionary) -> void:
	Game.notify.emit(str(r["text"]), Game.COLOR_INFO if r["ok"] else Game.COLOR_BAD)
	Audio.play("coins" if r["ok"] else "ui_error")
	if world:
		world.territory_changed.emit()
	refresh()


func _set_mark(st: WorldState, good: String, which: String, value: int) -> void:
	var o := st.market.order(good)
	if which == "keep":
		Market.set_order(st, good, value, int(o["sell"]))
	else:
		Market.set_order(st, good, int(o["keep"]), value)
	Audio.play("ui_click")
	refresh()


func _growth(st: WorldState) -> void:
	_heading("Village growth")
	var t := st.territory
	var homes := GrowthSystem.homes(st)
	var empty := GrowthSystem.empty_homes(st).size()
	var lodging := GrowthSystem.homes_with_room(st).size() - empty
	var cap := CharterSystem.max_population(st)
	_body.add_child(UITheme.label("%d people (room for %d)  -  %d homes, %d empty" % [GrowthSystem.population(st), cap, homes.size(), empty], 15))
	if lodging > 0:
		_body.add_child(_wrap("%d Townhouse%s can take in a second family." % [lodging, "s" if lodging != 1 else ""], 13, UITheme.TEXT_DIM))
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
		note = "Full: a %s may hold %d people." % [CharterSystem.title(st), cap]
		if CharterSystem.current(st) < CharterSystem.top():
			note += " A %s charter makes room for more." % CharterSystem.title_of(CharterSystem.current(st) + 1)
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
	_body.add_child(_wrap(InputSetup.fill("Pick one, then click beside a road to place it. It turns to face the road and a lane is laid to its door. {key:turn_building} turns it, Shift+click places another, Esc cancels."), 13, UITheme.TEXT_DIM))
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
		var limit := CharterSystem.limit_for(def, CharterSystem.current(st))
		row.add_child(UITheme.label("%d/%d" % [TerritorySystem.count_built(st, type), limit] if limit > 0 else CharterSystem.title_of(CharterSystem.needed_for(def)), 13, UITheme.TEXT_DIM))
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
