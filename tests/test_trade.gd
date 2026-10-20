extends TestCase
## Phase 6.2, carts to the noble houses' seats (Trade, data/trade.json; the
## carts in MarketData): what each house wants and pays, sending a cart
## (the goods, the carter and the escort leave), the sale at the seat and
## the way home, bandits on the road, a house in contempt, and saving it.


func _village(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.minutes += 3.0 * Calendar.MINUTES_PER_DAY
	st.house.gold = 1000
	st.military.camps.clear()
	for g: String in ["cloth", "ironware", "ale"]:
		st.territory.stock[g] = 100.0
	for h in st.realm.houses:
		h["standing"] = 0
	return st


func _days(st: WorldState, n: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in n:
		st.minutes += Calendar.MINUTES_PER_DAY
		events.append_array(Trade.daily_update(st))
	return events


## A band camped on the road to this house's seat, `men` strong.
func _camp_on_the_road(st: WorldState, h: Dictionary, men: int, known: bool) -> Dictionary:
	var camp: Dictionary = Military.make_camp(st, Seeds.rng(1, "road"))["camp"]
	var mid := Realm.center().lerp(Realm.pos_of(h), 0.5)
	camp["pos"] = [mid.x, mid.y]
	camp["men"] = men
	camp["known"] = known
	return camp


## The next cart's id for which the road on `leg` goes as wanted.
func _cart_id(st: WorldState, h: Dictionary, leg: String, waylaid: bool) -> int:
	var chance := float(Trade.danger(st, int(h["id"]))["chance"])
	for id in range(1, 500):
		if (Seeds.counted_rng(st.world_seed, "cart_%d_%s" % [id, leg]).randf() < chance) == waylaid:
			return id
	return -1


func test_what_the_houses_want() -> void:
	var st := _village("trade-wants")
	var by: Dictionary = Trade.section("wants")["by_known_for"]
	for h in st.realm.houses:
		var w := Trade.wants(st, int(h["id"]))
		check(w.size() == 2 and w[0] == str(by[h["known_for"]]) and w[0] != w[1], "%s (%s) wants %s" % [h["seat"], h["known_for"], ", ".join(w)])
		var plain := ""
		for g: String in ["food", "stone", "cloth", "ironware", "ale"]:
			if not w.has(g):
				plain = g
				break
		check(Trade.seat_price(st, int(h["id"]), w[0]) > Market.fair_price(st, w[0]) * 1.5, "and pays dearly for it")
		check(is_equal_approx(Trade.seat_price(st, int(h["id"]), plain), Market.fair_price(st, plain)), "and the going price for %s" % plain)
	var again := _village("trade-wants")
	for h in st.realm.houses:
		check_eq(Trade.wants(again, int(h["id"])), Trade.wants(st, int(h["id"])), "the same seed, the same wants")
	var h := st.realm.houses[0]
	var cold := Trade.seat_price(st, int(h["id"]), "cloth")
	h["standing"] = 50
	check(Trade.seat_price(st, int(h["id"]), "cloth") > cold, "a house that likes yours pays more")
	check(Market.price(st, "cloth") > Market.sell_price(st, "cloth") and Trade.seat_price(st, int(h["id"]), "cloth") > Market.sell_price(st, "cloth"), "a seat pays more than the market's merchants")


func test_sending_a_cart() -> void:
	var st := _village("trade-send")
	var h := st.realm.houses[0]
	var id := int(h["id"])
	check(not Trade.can_send(st, id, {"cloth": 70})["ok"], "a cart carries 60 at most: %s" % Trade.can_send(st, id, {"cloth": 70})["reason"])
	check(not Trade.can_send(st, id, {"cloth": 30, "ale": 20, "ironware": 20})["ok"], "(all told)")
	check(not Trade.can_send(st, id, {"cloth": 101})["ok"], "nor more than the stores hold")
	h["standing"] = -60
	check(not Trade.can_send(st, id, {"cloth": 20})["ok"], "a house in contempt won't deal: %s" % Trade.can_send(st, id, {"cloth": 20})["reason"])
	h["standing"] = 0
	var carters := Trade.carters(st)
	check(not carters.is_empty(), "%d could drive a cart" % carters.size())
	var riders := Trade.escorts(st)
	check(riders.all(func(c: CharacterData) -> bool: return c.office.is_empty()), "the house's officers stay at home")
	var r := Trade.send(st, id, {"cloth": 40, "ale": 20}, 2)
	check(r["ok"], r["text"])
	var cart: Dictionary = r["cart"]
	check(is_equal_approx(TerritorySystem.amount(st, "cloth"), 60.0) and is_equal_approx(TerritorySystem.amount(st, "ale"), 80.0), "the goods leave the stores")
	check_eq((r["away"] as Array).size(), 1 + mini(2, riders.size()), "the carter and %d of the warband go with it" % mini(2, riders.size()))
	for pid: int in r["away"]:
		check(st.get_character(pid).away_at == "cart", "%s is on the road" % st.get_character(pid).first_name)
	check_eq(int(cart["arrive"]) - st.day(), ceili(int(h["days"]) * 1.5), "a cart is slower than a rider (%d days)" % (int(cart["arrive"]) - st.day()))
	check(not Trade.can_send(st, id, {"cloth": 10})["ok"], "one cart to a seat at a time")
	var other := st.realm.houses[1]
	check(Trade.send(st, int(other["id"]), {"ironware": 10})["ok"], "a second cart to another seat")
	check(not Trade.can_send(st, int(st.realm.houses[2]["id"]), {"ironware": 10})["ok"], "and no more than two on the road")


func test_the_cart_sells_and_comes_home() -> void:
	var st := _village("trade-sale")
	var h := st.realm.houses[0]
	var id := int(h["id"])
	var want := Trade.wants(st, id)[0]
	var load := {want: 50}
	var est := Trade.estimate(st, id, load)
	var gold := st.house.gold
	var regard := int(h["standing"])
	var r := Trade.send(st, id, load, 0)
	var cart: Dictionary = r["cart"]
	var carter := st.get_character(int(cart["carter"]))
	_days(st, int(cart["arrive"]) - st.day())
	check(str(cart["stage"]) == "home" and int(cart["sold"][want]) == Trade.take(st) and int(cart["unsold"][want]) == 50 - Trade.take(st), "the seat takes %d of the 50 %s" % [Trade.take(st), want])
	check_eq(st.house.gold, gold, "the gold comes home with the cart")
	var events := _days(st, int(cart["back"]) - st.day())
	var home := events.filter(func(e: Dictionary) -> bool: return e.has("cart"))
	check(home.size() == 1 and (home[0]["back"] as Array).has(carter.id), "home: %s" % (home[0]["text"] if not home.is_empty() else "nothing"))
	check_eq(st.house.gold - gold, est, "%d gold, as reckoned" % est)
	check(is_equal_approx(TerritorySystem.amount(st, want), 50.0 + 50 - Trade.take(st)), "what didn't sell is back in the stores")
	check(carter.away_at == "" and not carter.is_away(), "the carter is home")
	check(int(h["standing"]) > regard, "the house thinks better of yours (%+d)" % (int(h["standing"]) - regard))
	check(Trade.on_road(st).is_empty() and int(st.market.last_cart["gold"]) == est, "and the cart is off the road")


func test_bandits_on_the_road() -> void:
	var st := _village("trade-bandits")
	var h := st.realm.houses[0]
	var id := int(h["id"])
	check_eq(float(Trade.danger(st, id)["chance"]), 0.0, "no camps, a safe road")
	var camp := _camp_on_the_road(st, h, 12, false)
	var d := Trade.danger(st, id)
	check(float(d["chance"]) > 0.3 and (d["camps"] as Array).has(camp), "a band of 12 on the road: %.0f%% each way" % (float(d["chance"]) * 100.0))
	check_eq(float(Trade.danger(st, id, true)["chance"]), 0.0, "(as far as you know, the road is safe)")
	var far := st.realm.houses.filter(func(x: Dictionary) -> bool: return Trade.danger(st, int(x["id"]))["camps"].is_empty())
	check(not far.is_empty(), "other roads don't pass it")
	# Unguarded, waylaid on the way there: the goods are lost.
	st.market.next_cart_id = _cart_id(st, h, "out", true)
	var hoard := int(camp["hoard"])
	var stock := TerritorySystem.amount(st, "cloth")
	var r := Trade.send(st, id, {"cloth": 40}, 0)
	var cart: Dictionary = r["cart"]
	var gold := st.house.gold
	var events := _days(st, int(cart["back"]) - st.day())
	var texts := "\n".join(events.map(func(e: Dictionary) -> String: return str(e["text"])))
	check(texts.contains("waylaid") and st.house.gold == gold, "waylaid: %s" % texts)
	check(is_equal_approx(TerritorySystem.amount(st, "cloth"), stock - 40.0), "the cloth is lost")
	check(int(camp["hoard"]) > hoard and bool(camp["known"]), "to the band's hoard (+%d), and now you know where they are" % (int(camp["hoard"]) - hoard))
	check(Trade.on_road(st).is_empty(), "the carter comes home all the same, if alive")


func test_an_escort_on_the_road() -> void:
	var st := _village("trade-escort")
	var h := st.realm.houses[0]
	var id := int(h["id"])
	var camp := _camp_on_the_road(st, h, 3, true)
	var riders := Trade.escorts(st)
	for c in riders.slice(0, 4):
		c.set_attribute("combat", 80, maxi(80, c.get_potential("combat")))
	check(riders.size() >= 2, "%d of the warband could ride with a cart" % riders.size())
	st.market.next_cart_id = _cart_id(st, h, "out", true)
	var r := Trade.send(st, id, {"cloth": 40}, 4)
	var cart: Dictionary = r["cart"]
	var events := _days(st, int(cart["arrive"]) - st.day())
	var texts := "\n".join(events.map(func(e: Dictionary) -> String: return str(e["text"])))
	check(str(cart["waylaid"]).contains("drove them off") and int(cart["sold"].get("cloth", 0)) > 0, "the escort drives them off and the cloth is sold: %s %s" % [cart["waylaid"], texts])
	check(int(camp["men"]) < 3 or not st.military.camps.has(camp), "and the band is the smaller (%d)" % int(camp["men"]))


func test_carts_are_saved() -> void:
	var st := _village("trade-save")
	Trade.send(st, int(st.realm.houses[0]["id"]), {"cloth": 30, "ale": 10}, 1)
	var copy := WorldState.from_dict(st.to_dict())
	check_eq(copy.market.to_dict(), st.market.to_dict(), "the cart on the road is saved")
	check(copy.market.carts[0]["escort"] is Array and int(copy.market.carts[0]["load"]["cloth"]) == 30, "with its load and escort")
	var old := st.to_dict()
	old["save_version"] = 19
	(old["market"] as Dictionary).erase("carts")
	(old["market"] as Dictionary).erase("next_cart_id")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.market.carts.is_empty() and migrated.market.next_cart_id == 1, "an older save has no carts on the road")
	check_eq(int(SaveManager.migrate(old)["save_version"]), WorldState.SAVE_VERSION, "and is brought up to date")


func test_a_cart_from_the_realm_map() -> void:
	Game.state = _village("trade-world")
	var st := Game.state
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var h := st.realm.houses[0]
	world.ui.show_realm("house", int(h["id"]))
	await frames(2)
	var panel: RealmPanel = world.ui._realm
	var want := Trade.wants(st, int(h["id"]))[0]
	panel._change_load(want, 10)
	panel._change_load(want, 10)
	await frames(1)
	var send: Button = null
	for b: Button in panel.find_children("*", "Button", true, false):
		if b.text.begins_with("Send the cart") and not b.disabled:
			send = b
	check(send != null, "the seat's Trade section has a cart to load and send")
	var stock := TerritorySystem.amount(st, want)
	if send:
		send.pressed.emit()
	await frames(1)
	check(Trade.on_road(st).size() == 1 and is_equal_approx(TerritorySystem.amount(st, want), stock - 20.0), "the cart sets out with 20 %s" % want)
	var carter := st.get_character(int(Trade.on_road(st)[0]["carter"]))
	check(world.npc_of(carter.id) == null, "%s has left the village" % carter.first_name)
	var labels := panel.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check(labels.any(func(t: String) -> bool: return t.begins_with("Your cart is on the road to")), "the panel shows it on the road")
	var back := int(Trade.on_road(st)[0]["back"])
	var gold := st.house.gold
	while st.day() < back:
		st.minutes += Calendar.MINUTES_PER_DAY
		world._check_new_day()
	await frames(1)
	check(Trade.on_road(st).is_empty() and st.house.gold > gold, "home with the gold (+%d)" % (st.house.gold - gold))
	check(world.npc_of(carter.id) != null, "and %s is back in the village" % carter.first_name)
	world.queue_free()
	await frames(2)
