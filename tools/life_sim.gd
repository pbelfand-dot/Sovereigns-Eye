extends SceneTree
## Lives a village through the years, data only, and reports how its people
## fare: population, births, deaths, marriages, those who left, the spread
## of ages, and the house. For tuning data/life.json.
##   godot --headless --path . --script res://tools/life_sim.gd -- <seed> [years] [steward] [matches] [heirs]
## With "steward" a simple steward also orders farmsteads and homes and
## petitions for charters (as tools/charter_sim.gd does), so the village can
## grow; without it, only what the village does by itself. With "matches"
## the house accepts the first suitor (for the heir or kin) with a gift of
## B rank or better and sends the rest home. With "heirs" the most gifted
## child is named heir each year. You live and die on the same curve as
## everyone (Phase 4.3), so a long run passes through several rulers. The
## steward also raises a castle when the house can (Phase 5.3), and pays a
## noble house's demand when the captains reckon its host too strong. With
## "favour" the house courts one noble house each year (what a visit with a
## gift and a good talk is worth), so its rival cools.
##   godot --headless --path . --script res://tools/life_sim.gd -- <seed> 40 steward favour


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if args.size() > 0 else "12345"
	var years := int(args[1]) if args.size() > 1 else 40
	var steward := args.has("steward")
	var st := WorldGenerator.generate(seed_text)
	var started := Time.get_ticks_msec()
	var totals := {"born": 0, "died": 0, "left": 0, "married": 0}
	var year_counts := totals.duplicate()
	var generations := 0
	var raids := 0
	var raids_won := 0
	var camps_cleared := 0
	var hosts := 0
	var hosts_won := 0
	var hosts_paid := 0
	print("%s, %d people, the heir %s (%d)" % [st.village_name, st.characters.size(), st.player().full_name(), st.player().age])
	var days := years * Calendar.days_per_year()
	for d in days:
		for k in 24:
			st.minutes += 60.0
			for s in TerritorySystem.advance(st, 60.0):
				TerritorySystem.complete(st, s)
			if CastleSystem.advance(st, 60.0):
				for e: Dictionary in CastleSystem.complete(st):
					print("   day %4d  %s" % [st.day(), e["text"]])
		var day := Calendar.day_index(st.whole_minutes())
		st.last_daily_update = day
		var rng := Seeds.rng(st.world_seed, "day_%d" % day)
		for c in st.characters:
			MoodSystem.daily_update(c, st, rng)
		CourtSystem.daily_update(st, Seeds.rng(st.world_seed, "court_day_%d" % day))
		TerritorySystem.daily_update(st)
		for e: Dictionary in Market.daily_update(st):
			if e.has("harvest") and str(e["harvest"]) in ["dearth", "plenty"]:
				print("   day %4d  %s" % [day, e["text"]])
		Trade.daily_update(st)
		for e: Dictionary in LifeSystem.daily_update(st):
			for key: String in ["born", "gone", "moved"]:
				if not e.has(key):
					continue
				match key:
					"born":
						year_counts["born"] += 1
					"gone":
						var who := st.get_departed(int(e["gone"]))
						year_counts["died" if who.departed_how == "died" else "left"] += 1
						if e.has("succession"):
							generations += 1
						if not str(e.get("text", "")).is_empty() and who.departed_how == "died":
							print("   day %4d  %s" % [day, e["text"]])
							continue
					"moved":
						year_counts["married"] += 1
		for e: Dictionary in MatchSystem.daily_update(st):
			if not str(e.get("text", "")).is_empty():
				print("   day %4d  %s" % [day, e["text"]])
			# With "matches", a player who looks with the Eye: take a suitor
			# with a gift of B rank or better, send the rest home.
			if e.has("visitor") and args.has("matches"):
				var suitor := st.get_character(int(e["visitor"]))
				var r := MatchSystem.accept(st, suitor) if suitor.best_potential() >= 65 else MatchSystem.decline(st, suitor)
				print("   day %4d  (best gift %d) %s" % [day, suitor.best_potential(), r["text"]])
		for e: Dictionary in Succession.daily_update(st):
			print("   day %4d  %s" % [day, e["text"]])
		var war: Array[Dictionary] = Military.daily_update(st)
		# A steward who listens to the captains: call the levy when the odds
		# are poor, pay the band off when even that isn't enough.
		if steward and war.any(func(e: Dictionary) -> bool: return e.has("raid_warning")):
			if Military.odds(st) < 0.5:
				Military.call_levy(st)
			if Military.odds(st) < 0.35:
				var host := st.military.raid.has("host")
				var paid := Military.pay_off(st)
				if paid["ok"]:
					print("   day %4d  %s" % [day, paid["text"]])
					hosts_paid += 1 if host else 0
		if Military.due(st):
			Military.fight(st, war)
		# The steward sends the warband against a camp when the captains
		# reckon the odds good (Phase 5.2), every tenth day at most.
		if steward and day % 10 == 0 and st.military.expedition.is_empty() and st.military.raid.is_empty():
			for camp in st.military.camps:
				if Military.can_ride(st, int(camp["id"]))["ok"] and Military.camp_odds(st, int(camp["id"])) >= 0.65:
					print("   day %4d  %s" % [day, Military.ride_out(st, int(camp["id"]))["text"]])
					break
		for e: Dictionary in war:
			if e.has("battle") or e.has("raid_warning") or e.has("succession") or e.has("camp_made"):
				print("   day %4d  %s" % [day, e["text"]])
				if e.has("battle") and e["battle"].get("camp", false):
					camps_cleared += 1 if e["battle"]["won"] else 0
				elif e.has("battle") and e["battle"].get("host", false):
					hosts += 1
					hosts_won += 1 if e["battle"]["won"] else 0
				elif e.has("battle"):
					raids += 1
					raids_won += 1 if e["battle"]["won"] else 0
			if e.has("gone"):
				year_counts["died"] += 1
		if args.has("favour") and day % Calendar.days_per_year() == 5 and st.realm and not st.realm.houses.is_empty():
			var r := Realm.section("regard")
			var worth := int(r.get("visit", 5)) + roundi(75 * float(r.get("gift_per_gold", 0.12))) + int(r.get("talk_base", 3)) + 4
			Realm.change_regard(st, int(st.realm.houses[0]["id"]), worth)
			if day % (Calendar.days_per_year() * 5) == 5:
				print("   day %4d  regard: %s" % [day, ", ".join(st.realm.houses.map(func(h: Dictionary) -> String: return "%s %+d" % [h["name"], int(h["standing"])]))])
		for e: Dictionary in Realm.daily_update(st):
			print("   day %4d  %s" % [day, e["text"]])
			# A host's demand comes at a season's start: the same steward.
			if steward and e.has("host") and Military.odds(st) < 0.5:
				Military.call_levy(st)
			if steward and e.has("host") and Military.odds(st) < 0.35:
				var paid := Military.pay_off(st)
				if paid["ok"]:
					print("   day %4d  %s" % [day, paid["text"]])
					hosts_paid += 1
		for e: Dictionary in CastleSystem.daily_update(st):
			print("   day %4d  %s" % [day, e["text"]])
		if st.house.ended:
			print("   day %4d  the house is ended" % day)
			break
		# With "heirs", a player who looks with the Eye names the most
		# gifted child heir (once a year).
		if args.has("heirs") and day % Calendar.days_per_year() == 0:
			var best: CharacterData = null
			for k in Succession.children_of(st, st.player()):
				if best == null or k.best_potential() > best.best_potential():
					best = k
			if best and Succession.heir(st) != best:
				print("   day %4d  %s" % [day, Succession.name_heir(st, best)["text"]])
		GrowthSystem.daily_update(st)
		if steward:
			_steward(st)
		if (d + 1) % Calendar.days_per_year() == 0:
			_report(st, (d + 1) / Calendar.days_per_year(), year_counts)
			for k: String in totals:
				totals[k] += year_counts[k]
				year_counts[k] = 0
	print("\n%d years in %.1f s: born %d, died %d, left %d, weddings %d, departed on record %d, you have been %d people, raids %d (won %d), camps cleared %d, hosts %d (won %d, paid %d more), castle %s" % [years, (Time.get_ticks_msec() - started) / 1000.0,
		totals["born"], totals["died"], totals["left"], totals["married"], st.departed.size(), generations + 1, raids, raids_won, camps_cleared, hosts, hosts_won, hosts_paid,
		CastleSystem.name_of(st.castle.kind) if not st.castle.kind.is_empty() else "none"])
	var next := CastleSystem.next_kind(st)
	print("Gold %d, renown %d, charter %d; %s" % [st.house.gold, st.house.renown, CharterSystem.current(st),
		("next castle: " + str(CastleSystem.can_order(st, next)["reason"])) if not next.is_empty() else ("works on the %s, %d%%" % [CastleSystem.name_of(st.castle.works), roundi(st.castle.progress() * 100.0)] if not st.castle.works.is_empty() else "")])
	var p := st.player()
	if p == null:
		print("The house is ended.")
		quit()
		return
	var head := Succession.ruler(st)
	print("You: %s, %d, %s; head of the house: %s; rulers in turn: %s" % [p.full_name(), p.age, CourtSystem.role_name(st, p), head.full_name() if head else "none",
		", ".join(st.house.rulers.map(func(r: Dictionary) -> String: return st.get_person(int(r["id"])).first_name))])
	quit()


func _report(st: WorldState, year: int, counts: Dictionary) -> void:
	var bands := [0, 0, 0, 0, 0]  # 0-2, 3-15, 16-39, 40-64, 65+
	var married := 0
	var age_sum := 0
	for c in st.characters:
		age_sum += c.age
		bands[0 if c.age < 3 else (1 if c.age < 16 else (2 if c.age < 40 else (3 if c.age < 65 else 4)))] += 1
		if LifeSystem.spouse_of(st, c):
			married += 1
	var h := 0.0
	for c in st.characters:
		h += c.happiness
	print("year %3d (%d)  pop %3d/%3d  ages 0-2:%2d 3-15:%2d 16-39:%2d 40-64:%2d 65+:%2d  mean %2d  married %3d  happy %2d  born %2d died %2d left %2d weddings %2d  food %4d" % [
		year, st.current_year(), st.characters.size(), CharterSystem.max_population(st), bands[0], bands[1], bands[2], bands[3], bands[4],
		age_sum / maxi(st.characters.size(), 1), married, roundi(h / maxf(st.characters.size(), 1.0)),
		counts["born"], counts["died"], counts["left"], counts["married"], roundi(st.territory.amount("food"))])
	if year % 5 == 0 or OS.get_environment("LIFE_JOBS") == "1":
		var jobs := {}
		for c in st.characters:
			jobs[c.occupation_id] = int(jobs.get(c.occupation_id, 0)) + 1
		var keys := jobs.keys()
		keys.sort()
		var parts: Array[String] = []
		for k: String in keys:
			parts.append("%s %d" % [k, jobs[k]])
		print("          food %+.1f/day (makes %.1f, eats %.1f)  %s" % [float(TerritorySystem.net_change(st)["food"]), float(TerritorySystem.production(st)["food"]),
			float(TerritorySystem.consumption(st)["food"]), ", ".join(parts)])


## A plain steward: keeps food up with farmsteads and petitions when it can;
## raises a castle when the house has its hire and something to spare.
func _steward(st: WorldState) -> void:
	CharterSystem.petition(st)
	var next := CastleSystem.next_kind(st)
	if not next.is_empty() and CastleSystem.can_order(st, next)["ok"] and st.house.gold >= int(CastleSystem.kind_def(next)["gold"]) + 150:
		print("   day %4d  %s" % [st.day(), CastleSystem.order(st, next)["text"]])
	var net := TerritorySystem.net_change(st)
	if float(net["food"]) < 2.0 and TerritorySystem.can_build(st, "farmhouse")["ok"]:
		var spot := TerritorySystem.find_spot(st, "farmhouse", 18.0, CharterSystem.build_radius(st))
		if not spot.is_empty():
			TerritorySystem.place(st, "farmhouse", spot["pos"], spot["rot"])
