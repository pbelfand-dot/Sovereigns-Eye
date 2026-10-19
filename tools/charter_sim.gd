extends SceneTree
## Plays a village for many days with a simple steward bot and reports when
## each charter could be earned. For tuning data/charters.json.
##   godot --headless --path . --script res://tools/charter_sim.gd -- <seed> [days]
## (SIM_HOMES=1 also lists what holds Timber Houses back from becoming Townhouses.)
##
## The bot does what a sensible player would: recruits a chancellor (renown)
## and a steward, keeps food up with farmsteads, builds a stonecutter's yard,
## a bakery and a granary, raises taverns, chapels and a Market Hall once a
## charter allows them, and petitions as soon as it can.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if args.size() > 0 else "12345"
	var days := int(args[1]) if args.size() > 1 else 200
	var st := WorldGenerator.generate(seed_text)
	TerritorySystem.initialize(st)
	_court(st)
	var started := Time.get_ticks_msec()
	for d in days:
		for k in 48:
			st.minutes += 30.0
			for s in TerritorySystem.advance(st, 30.0):
				TerritorySystem.complete(st, s)
		var day := Calendar.day_index(st.whole_minutes())
		var rng := Seeds.rng(st.world_seed, "day_%d" % day)
		for c in st.characters:
			MoodSystem.daily_update(c, st, rng)
		CourtSystem.daily_update(st, Seeds.rng(st.world_seed, "court_day_%d" % day))
		TerritorySystem.daily_update(st)
		LifeSystem.daily_update(st)
		MatchSystem.daily_update(st)
		GrowthSystem.daily_update(st)
		_build(st)
		var r := CharterSystem.petition(st)
		if r["ok"]:
			print("day %3d  %s" % [d + 1, r["text"]])
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
	_report(st, days)
	print("home spot: %s" % GrowthSystem.best_home_spot(st))
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
	for type: String in ["bakery", "storehouse", "tavern", "chapel", "market"]:
		if TerritorySystem.count_built(st, type) == 0 and _try(st, type):
			return
		if type == "market" and CharterSystem.current(st) >= 2 and TerritorySystem.count_built(st, "market") == 0 and st.minutes / 1440.0 > 120.0 and int(st.minutes / 1440.0) % 50 == 0:
			print("   market blocked: %s  spot %s" % [TerritorySystem.can_build(st, "market"), TerritorySystem.find_spot(st, "market")])
	if CharterSystem.current(st) >= 3 and TerritorySystem.count_built(st, "chapel") < 2 and _try(st, "chapel"):
		return
