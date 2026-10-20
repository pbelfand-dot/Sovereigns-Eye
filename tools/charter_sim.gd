extends SceneTree
## Plays a village for many days with a simple steward bot and reports when
## each charter could be earned. For tuning data/charters.json.
##   godot --headless --path . --script res://tools/charter_sim.gd -- <seed> [days]
## (SIM_HOMES=1 also lists what holds Timber Houses back from becoming Townhouses.)
##
## The bot does what a sensible player would: recruits a chancellor (renown)
## and a steward, keeps food up with farmsteads, builds a stonecutter's yard,
## a bakery and a granary, raises taverns, chapels and a Market Hall once a
## charter allows them, and petitions as soon as it can. It raises the
## house's castle as soon as the charter and the purse allow (Phase 5.3):
## when the works begin and end, and how long they wait for stores. Its
## steward keeps standing orders at the market (Phase 6.1): ten days of food
## and some wood and stone kept, more stone while the castle goes up, the
## rest sold above four fifths of the stores; MARKET=0 turns that off. It
## raises a Weavers' Workshop and a smithy, and sends carts of wares to the
## seats that want them (Phase 6.2), escorted on a road past a camp it
## knows of; CARTS=0 turns that off. Phase 6.3: the mill takes its
## customary toll (TOLL=light or hard for another), the steward buys a fair
## as soon as the town may (keeping 300 gold), and the Crown's levies are
## declared in full (HIDE=1 hides a third each time); MANOR=0 runs without
## the levies and the fair.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if args.size() > 0 else "12345"
	var days := int(args[1]) if args.size() > 1 else 200
	var st := WorldGenerator.generate(seed_text)
	TerritorySystem.initialize(st)
	_court(st)
	var started := Time.get_ticks_msec()
	var stalls := 0
	var trade := OS.get_environment("MARKET") != "0"
	var carting := OS.get_environment("CARTS") != "0"
	var carts := {"sent": 0, "home": 0, "gold": 0, "waylaid": 0}
	var manor_on := OS.get_environment("MANOR") != "0"
	var manor := {"levies": 0, "fair_days": 0, "mill": 0.0, "fair": 0.0}
	if OS.get_environment("TOLL") != "":
		ManorSystem.set_toll(st, OS.get_environment("TOLL"))
	for d in days:
		for k in 48:
			st.minutes += 30.0
			for s in TerritorySystem.advance(st, 30.0):
				TerritorySystem.complete(st, s)
			if CastleSystem.advance(st, 30.0):
				for e: Dictionary in CastleSystem.complete(st):
					print("day %3d  %s" % [d + 1, e["text"]])
		var day := Calendar.day_index(st.whole_minutes())
		var rng := Seeds.rng(st.world_seed, "day_%d" % day)
		for c in st.characters:
			MoodSystem.daily_update(c, st, rng)
		CourtSystem.daily_update(st, Seeds.rng(st.world_seed, "court_day_%d" % day))
		TerritorySystem.daily_update(st)
		if trade:
			_orders(st)
		for e: Dictionary in Market.daily_update(st):
			if e.has("harvest"):
				print("day %3d  %s" % [d + 1, e["text"]])
		for e: Dictionary in Trade.daily_update(st):
			if e.has("cart"):
				carts["home"] += 1
				carts["gold"] += int(e["cart"]["gold"])
				if not str(e["cart"]["waylaid"]).is_empty():
					carts["waylaid"] += 1
			if not str(e["text"]).is_empty() and (e.has("cart") or e.has("waylaid")):
				print("day %3d  %s" % [d + 1, e["text"]])
		manor["mill"] += ManorSystem.mill_income(st)
		manor["fair"] += ManorSystem.fair_income(st)
		if ManorSystem.fair_on(st):
			manor["fair_days"] += 1
		if manor_on:
			if OS.get_environment("HIDE") == "1" and not ManorSystem.next_levy(st).is_empty():
				ManorSystem.set_hiding(st, true)
			for e: Dictionary in ManorSystem.daily_update(st):
				if e.has("levy"):
					manor["levies"] += int(e["levy"]["paid"])
					print("day %3d  %s" % [d + 1, e["text"]])
				elif e.has("fair") and int(st.manor.fair_held_year) == st.current_year() and manor["fair_days"] < 2:
					print("day %3d  %s" % [d + 1, e["text"]])
			if ManorSystem.can_grant_fair(st)["ok"] and st.house.gold >= int(ManorSystem.section("fair")["fee"]) + 300:
				print("day %3d  %s" % [d + 1, ManorSystem.grant_fair(st)["text"]])
		if carting:
			var sent := _carts(st)
			if not sent.is_empty():
				carts["sent"] += 1
				print("day %3d  %s" % [d + 1, sent])
		LifeSystem.daily_update(st)
		MatchSystem.daily_update(st)
		Succession.daily_update(st)
		var war: Array[Dictionary] = Military.daily_update(st)
		if Military.due(st):
			Military.fight(st, war)
		GrowthSystem.daily_update(st)
		_build(st)
		var r := CharterSystem.petition(st)
		if r["ok"]:
			print("day %3d  %s" % [d + 1, r["text"]])
		for e: Dictionary in CastleSystem.daily_update(st):
			stalls += 1
		var keep := CastleSystem.next_kind(st)
		if not keep.is_empty() and CastleSystem.can_order(st, keep)["ok"] and st.house.gold >= int(CastleSystem.kind_def(keep)["gold"]) + 100:
			var o := CastleSystem.order(st, keep)
			print("day %3d  %s (%d builders, ~%.0f days)" % [d + 1, o["text"], st.castle.builders.size(), CastleSystem.days_left(st)])
		if d % 20 == 19:
			_report(st, d + 1)
			if OS.get_environment("SIM_HOMES") == "1":
				var why := {}
				for b in GrowthSystem.homes(st):
					if b.tier == 1:
						for need in GrowthSystem.home_needs(st, b):
							if not need["ok"]:
								why[need["label"]] = int(why.get(need["label"], 0)) + 1
				print("        Timber Houses held back by: %s" % why)
	print("\n%d days in %.1f s" % [days, (Time.get_ticks_msec() - started) / 1000.0])
	print("manor: mill toll %d gold (%s), fair %d days, %d gold in stallage; levies paid %d gold" % [roundi(manor["mill"]), st.manor.toll, manor["fair_days"],
		roundi(manor["fair"]), manor["levies"]])
	print("carts: %d sent, %d home with %d gold, %d waylaid; wares in store: %s" % [carts["sent"], carts["home"], carts["gold"], carts["waylaid"],
		", ".join(TerritorySystem.WARES.map(func(g: String) -> String: return "%d %s" % [roundi(TerritorySystem.amount(st, g)), g]))])
	var sum := Market.steward_summary(st, days)
	print("market: the steward's last %d trades: %s" % [st.market.ledger.size(), sum])
	print("castle: %s%s, %d days the works waited for stores" % [CastleSystem.name_of(st.castle.kind) if not st.castle.kind.is_empty() else "none",
		(", works on the %s %d%%" % [CastleSystem.name_of(st.castle.works), roundi(st.castle.progress() * 100.0)]) if not st.castle.works.is_empty() else "", stalls])
	_report(st, days)
	print("home spot: %s" % GrowthSystem.best_home_spot(st))
	if OS.get_environment("SIM_MOOD") == "1":
		# What moves the village's happiness, on average over everyone.
		var sums := {}
		for c in st.characters:
			for f: Dictionary in MoodSystem.happiness_factors(c, st):
				var key := str(f["label"]).get_slice(" (", 0)
				sums[key] = float(sums.get(key, 0.0)) + float(f["value"]) / st.characters.size()
		var keys := sums.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return absf(sums[a]) > absf(sums[b]))
		print("happiness: %s" % ", ".join(keys.slice(0, 12).map(func(k: String) -> String: return "%s %+.1f" % [k, sums[k]])))
	var reasons := {}
	for road in st.layout.roads:
		var pts: PackedVector3Array = road["points"]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var dir := (b - a).normalized()
			var normal := Vector3(-dir.z, 0, dir.x)
			var n := ceili(a.distance_to(b) / 4.0)
			for k in n:
				var p := a.lerp(b, float(k) / n)
				var d := Vector2(p.x - st.layout.square_center.x, p.z - st.layout.square_center.z).length()
				if d < 14 or d > CharterSystem.build_radius(st):
					continue
				for side: float in [1.0, -1.0]:
					var spot := TerritorySystem.snap(st, "cottage", p + normal * side * 8.0)
					var check := TerritorySystem.check_placement(st, "cottage", spot["pos"], spot["rot"])
					var key := str(check["reason"]).left(40) if not check["ok"] else ("ok, lane %d" % (check["lane"] as PackedVector3Array).size())
					reasons[key] = int(reasons.get(key, 0)) + 1
	print(reasons)
	print("order: %s" % GrowthSystem.order_home(st))
	var next := CharterSystem.current(st) + 1
	if next <= CharterSystem.top():
		print("Next (%s):" % CharterSystem.title_of(next))
		for r in CharterSystem.requirements(st, next):
			print("   %s %s (%s)" % ["[x]" if r["ok"] else "[ ]", r["label"], r["detail"]])
	quit()


func _report(st: WorldState, day: int) -> void:
	var tiers := [0, 0, 0]
	for b in GrowthSystem.homes(st):
		if GrowthSystem.can_level(b):
			tiers[mini(b.tier, 2)] += 1
	var h := 0.0
	for c in st.characters:
		h += c.happiness
	print("day %3d  %-11s pop %3d/%3d  homes %s (%d empty)  food %4d wood %4d stone %4d  gold %5d  renown %3d  happy %2d  income %+d  appeal %+d  bar %d%%  sites %d" % [day, CharterSystem.title(st),
		GrowthSystem.population(st), CharterSystem.max_population(st), tiers, GrowthSystem.empty_homes(st).size(), roundi(st.territory.amount("food")),
		roundi(st.territory.amount("wood")), roundi(st.territory.amount("stone")), st.house.gold,
		st.house.renown, roundi(h / st.characters.size()), CourtSystem.daily_income(st) - CourtSystem.daily_wages(st),
		roundi(GrowthSystem.appeal(st)), roundi(st.territory.settler_progress), st.territory.sites.size()])


## The steward's standing orders, set each day from what the village eats
## and what the castle needs.
func _orders(st: WorldState) -> void:
	var cap := roundi(TerritorySystem.capacity(st, "food") * 0.8)
	var eat := float(TerritorySystem.consumption(st)["food"])
	Market.set_order(st, "food", roundi(eat * 10.0), cap)
	# A hamlet saves its gold for the charter; a chartered village buys
	# what its works need.
	var buy := CharterSystem.current(st) >= 1
	Market.set_order(st, "wood", 150 if buy else -1, cap)
	Market.set_order(st, "stone", (400 if st.castle.works == "stone" else 150) if buy else -1, cap)
	# Wares the carts don't take go to market before the stores are full.
	for g: String in TerritorySystem.WARES:
		Market.set_order(st, g, -1, roundi(TerritorySystem.capacity(st, g) * 0.9))


## The steward's carts: the seat that would pay most for a cartload of the
## wares in store (at least 10 of a ware, up to what it takes), if worth
## 120 gold and the road isn't known to be dangerous (1 in 3); two of the
## warband ride with it past a camp. The news, or "".
func _carts(st: WorldState) -> String:
	var best := -1
	var best_load := {}
	var best_value := 0
	for h in st.realm.houses:
		var id := int(h["id"])
		if not Trade.can_send(st, id)["ok"] or float(Trade.danger(st, id, true)["chance"]) > 0.33:
			continue
		var load := {}
		var room := int(Trade.section("cart").get("load", 60))
		var order: Array[String] = []
		for g: String in Trade.wants(st, id) + TerritorySystem.WARES:
			if TerritorySystem.WARES.has(g) and not order.has(g):
				order.append(g)
		for g in order:
			var n := mini(mini(Trade.take(st), floori(TerritorySystem.amount(st, g))), room)
			if n >= 10:
				load[g] = n
				room -= n
		var value := Trade.estimate(st, id, load)
		if value > best_value:
			best = id
			best_load = load
			best_value = value
	if best < 0 or best_value < 120:
		return ""
	var escort := 0 if (Trade.danger(st, best, true)["camps"] as Array).is_empty() else 2
	var r := Trade.send(st, best, best_load, escort)
	return str(r["text"]) + " (~%d gold)" % best_value if r["ok"] else ""


## A chancellor (renown) and a steward (income), chosen for their gifts.
func _court(st: WorldState) -> void:
	for office: String in ["chancellor", "steward"]:
		var attr := str(CourtSystem.office_def(office).get("primary", "politics"))
		var best: CharacterData = null
		for c in st.characters:
			if c.age >= 18 and Recruitment.eligible(st, c)["ok"] and (best == null or c.get_current(attr) > best.get_current(attr)):
				best = c
		if best:
			Recruitment.accept(st, best, {"wage": 3, "position": "office", "office": office})


func _try(st: WorldState, type: String) -> bool:
	if not TerritorySystem.can_build(st, type)["ok"]:
		return false
	var spot := TerritorySystem.find_spot(st, type)
	if spot.is_empty():
		return false
	return bool(TerritorySystem.place(st, type, spot["pos"], spot["rot"])["ok"])


## One order a day at most, most pressing first.
func _build(st: WorldState) -> void:
	if st.territory.sites.size() >= 3:
		return
	if GrowthSystem.food_days(st) < 8.0 and _try(st, "farmhouse"):
		return
	if st.territory.amount("stone") < 80.0 and TerritorySystem.count_built(st, "quarry") < 2 and _try(st, "quarry"):
		return
	# The granary is full but holds too few days for the homes: store more.
	if st.territory.amount("food") >= TerritorySystem.capacity(st, "food") * 0.95 and GrowthSystem.food_days(st) < 12.0 and _try(st, "storehouse"):
		return
	for type: String in ["bakery", "storehouse", "tavern", "weavery", "chapel", "smithy", "market"]:
		if TerritorySystem.count_built(st, type) == 0 and _try(st, type):
			return
		if type == "market" and CharterSystem.current(st) >= 2 and TerritorySystem.count_built(st, "market") == 0 and st.minutes / 1440.0 > 120.0 and int(st.minutes / 1440.0) % 50 == 0:
			print("   market blocked: %s  spot %s" % [TerritorySystem.can_build(st, "market"), TerritorySystem.find_spot(st, "market")])
	if CharterSystem.current(st) >= 3 and TerritorySystem.count_built(st, "chapel") < 2 and _try(st, "chapel"):
		return
