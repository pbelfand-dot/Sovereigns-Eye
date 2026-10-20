extends TestCase
## Phase 6.1, the market (Market, MarketData, data/market.json): prices by
## season, harvest and the house's own trade; buying and selling within the
## day's volume and the stores' room; Market Halls and a gifted merchant on
## better terms; the steward's standing orders; saving it all.


## A village some days in (`day`), with gold and stores to trade.
func _village(seed_text: String, day: int = 3) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.minutes += float(day) * Calendar.MINUTES_PER_DAY
	st.house.gold = 1000
	for r: String in Market.GOODS:
		st.territory.stock[r] = 300.0
	return st


func _at_season(st: WorldState, season: String) -> void:
	var i := Calendar.seasons().find(season)
	var day := (st.day() / Calendar.days_per_year()) * Calendar.days_per_year() + i * Calendar.days_per_season() + 1
	st.minutes = float(day) * Calendar.MINUTES_PER_DAY + 8.0 * 60.0


## A Market Hall standing (only its type matters to the market).
func _hall(st: WorldState) -> void:
	var b := BuildingData.new()
	b.id = 9000 + Market.halls(st)
	b.type = "market"
	st.layout.buildings.append(b)


func _next_day(st: WorldState) -> Array[Dictionary]:
	st.minutes += Calendar.MINUTES_PER_DAY
	return Market.daily_update(st)


func test_prices_move_with_the_season_and_the_harvest() -> void:
	var st := _village("market-prices", 45)
	_at_season(st, "Autumn")
	var autumn := Market.price(st, "food")
	st.minutes += 2.0 * Calendar.days_per_season() * Calendar.MINUTES_PER_DAY  # the spring after (the same harvest)
	var spring := Market.price(st, "food")
	var fair := float(Market.section("goods")["food"]["price"])
	check(spring > autumn, "bread is dear before the harvest and cheap after it (%.2f in spring, %.2f in autumn)" % [spring, autumn])
	check(Market.price(st, "stone") > Market.price(st, "food"), "stone costs more than food")
	var kinds := {}
	for y in 60:
		kinds[str(Market.harvest_of(st, y)["id"])] = true
	check(kinds.has("plenty") and kinds.has("poor") and kinds.has("dearth"), "harvests vary year by year: %s" % str(kinds.keys()))
	check_eq(Market.harvest_of(WorldGenerator.generate("market-prices"), 7)["id"], Market.harvest_of(st, 7)["id"], "(the same harvest for the same seed and year)")
	var dearth := -1
	var plenty := -1
	for y in 60:
		var id := str(Market.harvest_of(st, y)["id"])
		if id == "dearth" and dearth < 0:
			dearth = y
		if id == "plenty" and plenty < 0:
			plenty = y
	var dpy := Calendar.days_per_year()
	var autumn_day := Calendar.seasons().find("Autumn") * Calendar.days_per_season()
	st.minutes = float(dearth * dpy + autumn_day + 2) * Calendar.MINUTES_PER_DAY
	var dear := Market.price(st, "food")
	var dearth_yield := Market.harvest_yield(st)
	st.minutes = float(plenty * dpy + autumn_day + 2) * Calendar.MINUTES_PER_DAY
	check(dear > Market.price(st, "food") * 1.8, "food is dearer in a dearth than after a plentiful harvest (%.2f, %.2f)" % [dear, Market.price(st, "food")])
	check(dearth_yield < 1.0 and Market.harvest_yield(st) > 1.0, "and the village's own fields yield less (%.2f) or more (%.2f) that autumn" % [dearth_yield, Market.harvest_yield(st)])
	check(TerritorySystem.season_factor(st, "food") > float(TerritorySystem.section("seasons")["Autumn"]["food"]), "(the harvest counts in the fields' output)")
	_at_season(st, "Winter")
	check_eq(Market.harvest_yield(st), 1.0, "(only the autumn's yield)")
	check(fair > 0.0, "(food has a price: %.2f)" % fair)


func test_buying_and_selling() -> void:
	var st := _village("market-trade")
	var gold := st.house.gold
	var price := Market.sell_price(st, "food")
	var r := Market.sell(st, "food", 20)
	check(r["ok"] and int(r["units"]) == -20 and st.house.gold == gold + int(r["gold"]) and int(r["gold"]) > 0, "you sell 20 food: %s" % r["text"])
	check_eq(TerritorySystem.amount(st, "food"), 280.0, "it leaves the stores")
	check(Market.sell_price(st, "food") < price, "and the price falls with it (%.3f -> %.3f)" % [price, Market.sell_price(st, "food")])
	var cost := Market.quote(st, "wood", 10)
	var got := -Market.quote(st, "wood", -10)
	check(cost > absi(got), "buying costs more than selling brings (%d against %d)" % [cost, absi(got)])
	var w := Market.buy(st, "wood", 10)
	check(w["ok"] and TerritorySystem.amount(st, "wood") == 310.0 and int(w["gold"]) == -cost, "you buy 10 wood: %s" % w["text"])
	var room := Market.room(st, "stone")
	var big := Market.sell(st, "stone", 1000)
	check(int(big["units"]) == -room, "the market takes only so much in a day (%d)" % room)
	check(not Market.sell(st, "stone", 10)["ok"], "and no more: %s" % Market.sell(st, "stone", 10)["text"])
	st.house.gold = 3
	check(not Market.buy(st, "food", 10)["ok"], "you can't buy without the gold: %s" % Market.buy(st, "food", 10)["text"])
	st.house.gold = 5000
	st.territory.stock["food"] = TerritorySystem.capacity(st, "food") - 4.0
	var full := Market.buy(st, "food", 10)
	check(full["ok"] and int(full["units"]) == 4, "you buy only what the granary holds (%d)" % int(full["units"]))
	st.territory.stock["wood"] = 0.0
	check(not Market.sell(st, "wood", 10)["ok"], "there's nothing to sell from empty stores")


func test_the_market_recovers() -> void:
	var st := _village("market-recover")
	var fair := Market.price(st, "food")
	Market.sell(st, "food", 25)
	var low := Market.price(st, "food")
	check(low < fair, "a sale floods the market (%.3f -> %.3f)" % [fair, low])
	_next_day(st)
	check(Market.price(st, "food") > low and Market.room(st, "food") == Market.volume(st), "next day it has recovered some (%.3f) and trades afresh" % Market.price(st, "food"))
	for i in 15:
		_next_day(st)
	check(absf(Market.price(st, "food") - Market.fair_price(st, "food")) < 0.001, "in time it forgets")


func test_halls_and_a_gifted_merchant() -> void:
	var st := _village("market-halls")
	var vol := Market.volume(st)
	var spread := Market.spread(st)
	_hall(st)
	check(Market.volume(st) > vol and Market.spread(st) < spread, "a Market Hall trades more (%d -> %d) on better terms (%.2f -> %.2f)" % [vol, Market.volume(st), spread, Market.spread(st)])
	var m := Market.best_merchant(st)
	check(m != null, "the village has a merchant")
	var before := Market.spread(st)
	m.set_attribute("politics", 95, maxi(95, m.get_potential("politics")))
	check(Market.spread(st) < before, "one gifted at haggling gets better terms still (%.3f -> %.3f)" % [before, Market.spread(st)])
	for i in 5:
		_hall(st)
	check(Market.spread(st) >= float(Market.section("trade")["min_spread"]), "(never better than the floor)")


func test_the_stewards_standing_orders() -> void:
	var st := _village("market-orders")
	Market.set_order(st, "stone", 400, -1)
	Market.set_order(st, "food", -1, 200)
	_next_day(st)
	check_eq(TerritorySystem.amount(st, "stone"), 300.0, "without a steward, no one carries out the orders")
	var steward: CharacterData = null
	for c in st.characters:
		if c.age >= 20 and not st.is_player(c):
			steward = c
			break
	st.house.offices["steward"] = steward.id
	var gold := st.house.gold
	_next_day(st)
	check(TerritorySystem.amount(st, "stone") > 300.0 and st.house.gold < gold, "the steward buys stone toward the mark (%d)" % TerritorySystem.amount(st, "stone"))
	check(TerritorySystem.amount(st, "food") < 300.0 and TerritorySystem.amount(st, "food") >= 200.0, "and sells food above its mark (%d left)" % TerritorySystem.amount(st, "food"))
	check(st.market.ledger.any(func(e: Dictionary) -> bool: return e["by"] == "steward"), "(the ledger shows it)")
	st.house.gold = Market.reserve(st) + 2
	var stone := TerritorySystem.amount(st, "stone")
	_next_day(st)
	check(TerritorySystem.amount(st, "stone") - stone < 10.0, "he keeps a reserve of gold (%d) for the wages" % Market.reserve(st))
	var sum := Market.steward_summary(st, 10)
	check(int(sum["bought"].get("stone", 0)) > 0 and int(sum["sold"].get("food", 0)) > 0, "what he did, in sum: %s" % str(sum))
	Market.set_order(st, "wood", 300, 250)
	check(int(st.market.order("wood")["sell"]) > int(st.market.order("wood")["keep"]), "(a sell mark is kept above the keep mark)")


func test_the_harvest_is_told() -> void:
	var st := _village("market-news", 0)
	var told: Array[Dictionary] = []
	for d in Calendar.days_per_year() + 1:
		told.append_array(_next_day(st).filter(func(e: Dictionary) -> bool: return e.has("harvest")))
	check_eq(told.size(), 1, "once a year, when the harvest comes in: %s" % (told[0]["text"] if not told.is_empty() else ""))
	check(st.current_season() == "Autumn" or Market.harvest_year(st) >= 0, "(in autumn)")


func test_the_market_is_saved() -> void:
	var st := _village("market-save")
	Market.sell(st, "food", 10)
	Market.set_order(st, "stone", 100, 500)
	var copy := WorldState.from_dict(st.to_dict())
	check_eq(copy.market.to_dict(), st.market.to_dict(), "prices, orders and the ledger are saved")
	var old := st.to_dict()
	old["save_version"] = 18
	old.erase("market")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.market != null and migrated.market.orders.is_empty() and migrated.market.ledger.is_empty(), "an older save starts with an untouched market")


func test_the_market_in_the_world() -> void:
	Game.state = _village("market-world")
	var st := Game.state
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	world.ui.toggle_build()
	await frames(2)
	var buttons := world.ui._build.find_children("*", "Button", true, false)
	var sell: Button = null
	for b: Button in buttons:
		if b.text == "Sell 10" and not b.disabled:
			sell = b
			break
	check(sell != null, "the Build panel has the market, with something to sell")
	var gold := st.house.gold
	if sell:
		sell.pressed.emit()
	check(st.house.gold > gold, "a sale from the panel brings in gold (%d -> %d)" % [gold, st.house.gold])
	await frames(1)
	var labels := world.ui._build.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check(labels.any(func(t: String) -> bool: return t.contains("You sold")), "and shows in the latest trades")
	world.ui.toggle_court()
	await frames(2)
	var court := world.ui._court.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check(court.any(func(t: String) -> bool: return t.begins_with("In: ")), "the Court panel shows the treasury, part by part")
	st.minutes = float((Calendar.seasons().find("Autumn") * Calendar.days_per_season() + 1) * Calendar.MINUTES_PER_DAY) + 7.0 * 60.0
	world._check_new_day()
	check(st.market.harvest_told == 0, "the harvest is told in the world")
	world.queue_free()
	await frames(2)
