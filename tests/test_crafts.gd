extends TestCase
## Phase 6.2, the crafts (TerritorySystem.craft, data/territory.json
## "crafts"): the smith makes ironware from wood, the tavern brews ale from
## grain, weavers weave cloth; never from the village's own bread and
## firewood; wares in their own room; at the market.


func _village(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.minutes += 3.0 * Calendar.MINUTES_PER_DAY
	st.house.gold = 3000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 600.0
	return st


func _raise(st: WorldState, type: String) -> BuildingData:
	var spot := TerritorySystem.find_spot(st, type)
	if spot.is_empty():
		return null
	var res := TerritorySystem.place(st, type, spot["pos"], spot["rot"])
	if not res["ok"]:
		return null
	var site: ConstructionSite = res["site"]
	site.work_done = site.work_needed
	TerritorySystem.complete(st, site)
	return st.get_building(site.id())


func test_the_craftsmen_make_wares() -> void:
	var st := _village("crafts-start")
	var plans := TerritorySystem.craft_plans(st)
	var makes := {}
	for p: Dictionary in plans:
		makes[p["makes"]] = true
	check(makes.has("ironware") and makes.has("ale"), "the village's smith and tavern folk are craftsmen: %s" % str(makes.keys()))
	var wood := TerritorySystem.amount(st, "wood")
	var r := TerritorySystem.craft(st)
	check(float(r["made"].get("ironware", 0.0)) > 0.0 and TerritorySystem.amount(st, "ironware") > 0.0, "the smith makes ironware (%.1f)" % float(r["made"].get("ironware", 0.0)))
	check(float(r["made"].get("ale", 0.0)) > 0.0 and float(r["used"].get("food", 0.0)) > 0.0, "the tavern brews ale (%.1f) from grain (%.1f)" % [float(r["made"].get("ale", 0.0)), float(r["used"].get("food", 0.0))])
	check(TerritorySystem.amount(st, "wood") < wood, "the forge burns wood")
	var before := TerritorySystem.amount(st, "ale")
	st.minutes += Calendar.MINUTES_PER_DAY
	TerritorySystem.daily_update(st)
	check(TerritorySystem.amount(st, "ale") > before and float(st.territory.last_change.get("ale", 0.0)) > 0.0, "each day (%+.1f ale)" % float(st.territory.last_change.get("ale", 0.0)))


func test_crafts_spare_the_villages_bread() -> void:
	var st := _village("crafts-bread")
	var reserve := TerritorySystem.craft_floor(st, "food")
	check(reserve >= float(TerritorySystem.consumption(st)["food"]) * 10.0 and reserve >= TerritorySystem.capacity(st, "food") * 0.5, "the village keeps ten days' bread and half its granary (%d)" % roundi(reserve))
	st.territory.stock["food"] = reserve - 1.0
	var r := TerritorySystem.craft(st)
	check_eq(float(r["made"].get("ale", 0.0)), 0.0, "with less than %d food in store, no grain goes to ale" % roundi(reserve))
	st.territory.stock["food"] = reserve + 1.0
	r = TerritorySystem.craft(st)
	check(float(r["used"].get("food", 0.0)) <= 1.0 + 0.001 and float(r["made"].get("ale", 0.0)) > 0.0, "with a little more, only the spare (%.2f)" % float(r["used"].get("food", 0.0)))
	st.territory.stock["wood"] = TerritorySystem.capacity(st, "wood") * 0.5
	r = TerritorySystem.craft(st)
	check_eq(float(r["made"].get("ironware", 0.0)), 0.0, "the smith leaves a half-empty woodpile for building")


func test_wares_have_their_own_room() -> void:
	var st := _village("crafts-room")
	var cap := TerritorySystem.capacity(st, "ale")
	check(cap < TerritorySystem.capacity(st, "food"), "wares are kept in less room (%d) than grain (%d)" % [roundi(cap), roundi(TerritorySystem.capacity(st, "food"))])
	st.territory.stock["ale"] = cap
	var food := TerritorySystem.amount(st, "food")
	var r := TerritorySystem.craft(st)
	check(float(r["made"].get("ale", 0.0)) == 0.0 and TerritorySystem.amount(st, "food") == food, "a full cellar brews no more, and uses no grain")
	_raise(st, "storehouse")
	check(TerritorySystem.capacity(st, "ale") > cap, "a granary makes room for wares too")


func test_the_weavers_workshop() -> void:
	var st := _village("crafts-weavers")
	check(TerritorySystem.can_build(st, "weavery")["ok"], "a hamlet may build a Weavers' Workshop: %s" % TerritorySystem.can_build(st, "weavery")["reason"])
	check(not TerritorySystem.can_build(st, "smithy")["ok"], "a smithy waits for a village's charter")
	var b := _raise(st, "weavery")
	check(b != null, "the workshop is raised")
	var weavers := st.characters.filter(func(c: CharacterData) -> bool: return c.occupation_id == "weaver")
	check(weavers.size() == 2, "two weavers take up the looms (%d)" % weavers.size())
	var cloth := TerritorySystem.amount(st, "cloth")
	TerritorySystem.craft(st)
	check(TerritorySystem.amount(st, "cloth") > cloth, "and weave cloth (%.1f)" % TerritorySystem.amount(st, "cloth"))
	st.territory.charter = 1
	check(TerritorySystem.can_build(st, "smithy")["ok"], "a chartered village may raise a smithy")


func test_wares_at_the_market() -> void:
	var st := _village("crafts-market")
	st.territory.stock["cloth"] = 50.0
	check(Market.volume(st, "cloth") < Market.volume(st, "food"), "wares sell in smaller lots (%d cloth, %d food a day)" % [Market.volume(st, "cloth"), Market.volume(st, "food")])
	var r := Market.sell(st, "cloth", 10)
	check(r["ok"] and int(r["gold"]) > Market.quote(st, "food", -10) * 4, "cloth fetches far more than grain: %s" % r["text"])
	var dpy := Calendar.days_per_year()
	var autumn := Calendar.seasons().find("Autumn") * Calendar.days_per_season()
	var dearth := -1
	var plenty := -1
	for y in 60:
		var id := str(Market.harvest_of(st, y)["id"])
		if id == "dearth" and dearth < 0:
			dearth = y
		if id == "plenty" and plenty < 0:
			plenty = y
	st.minutes = float(dearth * dpy + autumn + 2) * Calendar.MINUTES_PER_DAY
	var dear := Market.price(st, "ale")
	st.minutes = float(plenty * dpy + autumn + 2) * Calendar.MINUTES_PER_DAY
	check(dear > Market.price(st, "ale") * 1.8, "ale's price follows grain's (%.2f in a dearth, %.2f in plenty)" % [dear, Market.price(st, "ale")])
