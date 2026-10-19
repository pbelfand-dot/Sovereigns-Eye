extends TestCase
## Phase 3 step 1: the village's stores, building orders, construction sites,
## the Master of Works, finishing buildings and backward-compatible saves.

const OLD_SLOT := "test_phase2_migration"


## Runs the clock forward, putting in construction work in 10-minute steps.
## Returns the sites finished along the way (already completed).
func _run_days(state: WorldState, days: float) -> Array[ConstructionSite]:
	var done: Array[ConstructionSite] = []
	var steps := int(days * 24 * 6)
	for i in steps:
		state.minutes += 10.0
		for s in TerritorySystem.advance(state, 10.0):
			done.append(s)
			TerritorySystem.complete(state, s)
	return done


func _place(state: WorldState, type: String) -> ConstructionSite:
	var spot := TerritorySystem.find_spot(state, type)
	check(not spot.is_empty(), "found a free spot for a %s" % type)
	if spot.is_empty():
		return null
	var res := TerritorySystem.place(state, type, spot["pos"], spot["rot"])
	check(res["ok"], "the %s can be ordered (%s)" % [type, res.get("text", "")])
	return res.get("site", null)


func test_new_worlds_start_with_stores() -> void:
	var a := WorldGenerator.generate("territory-a")
	var b := WorldGenerator.generate("territory-a")
	check(a.territory != null, "new games have stores")
	var start := TerritorySystem.section("start")
	for r: String in TerritorySystem.RESOURCES:
		check_eq(a.territory.amount(r), float(start.get(r, 0)), "%s starts at the configured amount" % r)
	var top := 0
	for bld in a.layout.buildings:
		top = maxi(top, bld.id)
	check(a.territory.next_building_id > top, "new building ids never clash with the village's")
	check_eq(a.territory.to_dict(), b.territory.to_dict(), "the same seed gives the same stores")
	check_eq(TerritorySystem.amount(a, "gold"), float(a.house.gold), "gold is the house treasury")


func test_villagers_produce_and_consume() -> void:
	var state := WorldGenerator.generate("territory-economy")
	var prod := TerritorySystem.production(state)
	var cons := TerritorySystem.consumption(state)
	check(float(prod["food"]) > 0.0, "farmers grow food")
	check(float(prod["wood"]) > 0.0, "woodcutters fell timber")
	check_eq(float(prod["stone"]), 0.0, "no stone until a Stonecutter's Yard is built")
	var expected_food := 0.0
	for c in state.characters:
		expected_food += 0.6 if c.age < 14 else 1.0
	check(absf(float(cons["food"]) - expected_food) < 0.01, "everyone eats (children less)")
	var net := TerritorySystem.net_change(state)
	check(float(net["food"]) > 0.0, "a new village feeds itself in spring (net %+.1f)" % float(net["food"]))
	check(float(net["wood"]) > 0.0, "a new village gathers more wood than it burns (net %+.1f)" % float(net["wood"]))
	var before := state.territory.amount("food")
	TerritorySystem.daily_update(state)
	check(absf(state.territory.amount("food") - (before + float(net["food"]))) < 0.01, "a day's food is added to the stores")
	# Winter: fields lie fallow.
	state.minutes += 3 * Calendar.days_per_season() * Calendar.MINUTES_PER_DAY
	check_eq(state.current_season(), "Winter", "three seasons later it is winter")
	check(float(TerritorySystem.production(state)["food"]) < float(prod["food"]), "less food grows in winter")


func test_storage_limits_and_hunger() -> void:
	var state := WorldGenerator.generate("territory-storage")
	var cap := TerritorySystem.capacity(state, "wood")
	var granaries := state.layout.buildings_of_type("storehouse").size()
	check_eq(cap, 400.0 + 300.0 * granaries, "granaries raise the storage limit")
	state.territory.stock["wood"] = cap - 1.0
	check(absf(TerritorySystem.add(state, "wood", 100.0) - 1.0) < 0.001, "stores never overflow")
	check(absf(TerritorySystem.add(state, "food", -10000.0) + 150.0) < 0.001, "stores never go below zero")
	check(TerritorySystem.is_hungry(state), "an empty granary means hunger")
	var c := state.characters[0]
	var hungry := false
	for f in MoodSystem.happiness_factors(c, state):
		if str(f["label"]) == str(TerritorySystem.section("hunger").get("label", "")):
			hungry = true
	check(hungry, "hunger shows up in everyone's happiness factors")


func test_placement_rules() -> void:
	var state := WorldGenerator.generate("territory-place")
	var road: Dictionary = state.layout.roads[0]
	var on_road: Vector3 = (road["points"] as PackedVector3Array)[2]
	check(not TerritorySystem.check_placement(state, "quarry", on_road, 0.0)["ok"], "can't build on a road")
	var manor := state.layout.buildings_of_type("manor")[0]
	check(not TerritorySystem.check_placement(state, "quarry", manor.position, manor.rotation)["ok"], "can't build inside the manor")
	check(not TerritorySystem.check_placement(state, "quarry", state.layout.square_center, 0.0)["ok"], "can't build on the square")
	check(not TerritorySystem.check_placement(state, "quarry", Vector3(125, 0, 125), 0.0)["ok"], "can't build on the rough edge of the map")
	var spot := TerritorySystem.find_spot(state, "quarry")
	check(not spot.is_empty(), "there is room beside the roads")
	if spot.is_empty():
		return
	var b := BuildingData.new()
	b.position = spot["pos"]
	b.rotation = spot["rot"]
	b.footprint = TerritorySystem.footprint("quarry")
	var to_road := TerritorySystem.road_clearance(state.layout, b.door_position())
	check(to_road < TerritorySystem.road_clearance(state.layout, b.position - b.forward() * 2.0), "snapped buildings face the road")
	# Snapping is stable: the snapped spot snaps to itself.
	var again := TerritorySystem.snap(state, "quarry", spot["pos"])
	check((again["pos"] as Vector3).distance_to(spot["pos"]) < 0.05, "snapping a snapped spot changes nothing")


func test_ordering_building_and_finishing_a_quarry() -> void:
	var state := WorldGenerator.generate("territory-quarry")
	state.house.gold = 500
	var wood_before := state.territory.amount("wood")
	var gold_before := state.house.gold
	var roads_before := state.layout.roads.size()
	var buildings_before := state.layout.buildings.size()
	var site := _place(state, "quarry")
	if site == null:
		return
	var cost: Dictionary = TerritorySystem.buildable_def("quarry")["cost"]
	check_eq(state.house.gold, gold_before - int(cost["gold"]), "gold is paid up front")
	check(state.territory.amount("wood") <= wood_before - float(cost["wood"]) + 3.0 * state.territory.cleared_trees.size() + 0.01, "wood is paid up front")
	check_eq(state.layout.buildings.size(), buildings_before, "the building isn't in the village until it's finished")
	if not site.lane.is_empty():
		check_eq(state.layout.roads.size(), roads_before + 1, "a lane to the road is laid")
	check_eq(site.builders.size(), int(TerritorySystem.section("construction").get("crew", 3)), "a full crew is gathered")
	var first := state.get_character(site.builders[0])
	check_eq(first.occupation_id, "carpenter", "carpenters are called first")
	check(TerritorySystem.worker_output(state, first).is_empty(), "builders don't do their usual work")
	var days := TerritorySystem.days_left(state, site)
	check(days > 0.3 and days < 3.0, "a yard takes about a day to build (%.1f days)" % days)

	var done := _run_days(state, 4.0)
	check_eq(done.size(), 1, "the site is finished")
	check(state.territory.sites.is_empty(), "the finished site is closed")
	var b := state.get_building(site.id())
	check(b != null, "the finished building joins the village")
	if b == null:
		return
	check_eq(b.type, "quarry", "it is a Stonecutter's Yard")
	check(state.territory.built.has(b.id), "it is recorded as the player's work")
	var cutters := 0
	for c in state.workers_of(b.id):
		if c.occupation_id == "stonecutter":
			cutters += 1
	check_eq(cutters, 2, "two stonecutters are hired")
	check(float(TerritorySystem.production(state)["stone"]) > 0.0, "the village now quarries stone")
	check(TerritorySystem.builder_site(state, first) == null, "the crew goes back to work")
	check(not TerritorySystem.worker_output(state, first).is_empty(), "former builders produce again")


func test_master_of_works_speeds_building() -> void:
	var state := WorldGenerator.generate("territory-master")
	state.house.gold = 500
	var site := _place(state, "quarry")
	if site == null:
		return
	var base_rate := TerritorySystem.daily_rate(state, site)
	check(base_rate > 0.0, "the crew works every day")
	var candidate: CharacterData = null
	for c in state.characters:
		if not state.is_player(c) and c.age >= 16 and not c.retainer and c.get_current("administration") >= 20 and TerritorySystem.builder_site(state, c) == null:
			candidate = c
			break
	check(candidate != null, "found someone with a head for administration")
	if candidate == null:
		return
	CourtSystem.join(state, candidate)
	var res := CourtSystem.appoint(state, "master_of_works", candidate)
	check(res["ok"], "a retainer can be made Master of Works")
	var factor := 1.0 + candidate.get_current("administration") / 100.0
	check(absf(TerritorySystem.speed_factor(state) - factor) < 0.001, "Administration sets the pace")
	check(absf(TerritorySystem.daily_rate(state, site) - base_rate * factor) < 0.01, "every site goes faster")
	check_eq(CourtSystem.work_style(candidate), "oversee", "the Master of Works oversees the sites")


func test_cancelling_refunds_and_lifts_the_lane() -> void:
	var state := WorldGenerator.generate("territory-cancel")
	state.house.gold = 500
	var gold_before := state.house.gold
	var roads_before := state.layout.roads.size()
	var site := _place(state, "quarry")
	if site == null:
		return
	var res := TerritorySystem.cancel(state, site)
	check(res["ok"], "an order can be cancelled")
	check_eq(state.house.gold, gold_before, "an unstarted order is refunded in full")
	check_eq(state.layout.roads.size(), roads_before, "its lane is lifted")
	check(state.territory.sites.is_empty(), "the site is gone")


func test_limits_and_costs() -> void:
	var state := WorldGenerator.generate("territory-limits")
	state.house.gold = 0
	check(not TerritorySystem.can_build(state, "quarry")["ok"], "can't build without the gold")
	check(str(TerritorySystem.can_build(state, "quarry")["reason"]).contains("gold"), "the reason names what's missing")
	state.house.gold = 5000
	state.territory.stock["wood"] = 400.0
	state.territory.stock["stone"] = 400.0
	var limit := CharterSystem.limit_for(TerritorySystem.buildable_def("quarry"), CharterSystem.current(state))
	for i in limit:
		_place(state, "quarry")
	check_eq(TerritorySystem.count_built(state, "quarry"), limit, "orders count toward the limit")
	check(not TerritorySystem.can_build(state, "quarry")["ok"], "the limit stops more orders")
	var names := {}
	for s in state.territory.sites:
		names[s.building.name] = true
	check_eq(names.size(), limit, "every new building gets its own name")


func test_farmsteads_get_fields_and_farmers() -> void:
	var state := WorldGenerator.generate("territory-farm")
	state.house.gold = 500
	var site := _place(state, "farmhouse")
	if site == null:
		return
	site.work_done = site.work_needed
	var events := TerritorySystem.complete(state, site)
	check(not events.is_empty(), "finishing is announced")
	var fields := state.layout.fields_of_building(site.id())
	check(fields.size() >= 1, "the new farm gets fields (%d)" % fields.size())
	for f in fields:
		check(TerritorySystem.road_clearance(state.layout, f["center"]) > 1.0, "fields stay off the roads")
	var occupations := []
	for c in state.workers_of(site.id()):
		occupations.append(c.occupation_id)
	check(occupations.has("farmer"), "a farmer is hired")


func test_sites_survive_save_and_load() -> void:
	var state := WorldGenerator.generate("territory-save")
	state.house.gold = 500
	var site := _place(state, "quarry")
	if site == null:
		return
	_run_days(state, 0.25)
	var text := JSON.stringify(state.to_dict())
	var loaded := WorldState.from_dict(JSON.parse_string(text))
	check(loaded.territory != null, "stores are saved")
	check_eq(loaded.territory.to_dict(), state.territory.to_dict(), "stores and sites round-trip")
	var s2 := loaded.territory.get_site(site.id())
	check(s2 != null, "the site is restored")
	if s2:
		check(absf(s2.work_done - site.work_done) < 0.02, "its progress is kept")
		check_eq(s2.builders, site.builders, "its crew is kept")
		check_eq(s2.building.name, site.building.name, "its name is kept")
	if not site.lane.is_empty():
		var found := false
		for r in loaded.layout.roads:
			if str(r["name"]) == site.lane:
				found = true
		check(found, "its lane is saved with the roads")


func test_phase2_save_migrates_with_starting_stores() -> void:
	var original := WorldGenerator.generate("territory-migration")
	var old := original.to_dict()
	old["save_version"] = 2
	old.erase("territory")
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var file := FileAccess.open(SaveManager.slot_path(OLD_SLOT), FileAccess.WRITE)
	check(file != null, "created a Phase 2-format save")
	if file == null:
		return
	file.store_string(JSON.stringify(old))
	file.close()
	var loaded := SaveManager.load_state(OLD_SLOT)
	check(loaded != null, "Phase 2 save loads")
	if loaded:
		check(loaded.territory != null, "migration creates the stores")
		check_eq(loaded.territory.amount("food"), float(TerritorySystem.section("start")["food"]), "with the starting food")
		check_eq(loaded.to_dict()["save_version"], WorldState.SAVE_VERSION, "migration writes the current version")
	SaveManager.delete(OLD_SLOT)


func test_construction_rises_bottom_up() -> void:
	check_eq(ConstructionView.pieces_shown(0.05, 100), 0, "staked-out ground shows no walls")
	check_eq(ConstructionView.pieces_shown(1.0, 100), 100, "a finished site shows everything")
	var last := 0
	for i in 21:
		var n := ConstructionView.pieces_shown(i / 20.0, 100)
		check(n >= last, "walls never vanish as work goes on")
		last = n
	if not VillageKit.has_prefab("quarry"):
		return
	var p := VillageKit.prefab("quarry", 0)
	var parts: Array = (p["parts"] as Array).duplicate()
	check(parts.size() > 10, "the kit yard is made of pieces (%d)" % parts.size())
	parts.sort_custom(func(x: Array, y: Array) -> bool: return ConstructionView.piece_order(x) < ConstructionView.piece_order(y))
	var first_y := (parts[0][1] as Transform3D).origin.y
	var last_y := (parts[parts.size() - 1][1] as Transform3D).origin.y
	check(first_y <= last_y, "the floor goes in before the roof")
	var bounds := VillageKit.recipe_bounds(VillageKit.variants("quarry")[0])
	check_eq(bounds.size, TerritorySystem.footprint("quarry"), "the kit yard matches its footprint")


func test_rectangle_overlap() -> void:
	check(TerritorySystem.rects_overlap(Vector3.ZERO, 0.0, Vector2(2, 1), Vector3(3.5, 0, 0), 0.0, Vector2(2, 1)), "side by side with overlap")
	check(not TerritorySystem.rects_overlap(Vector3.ZERO, 0.0, Vector2(2, 1), Vector3(4.5, 0, 0), 0.0, Vector2(2, 1)), "side by side with a gap")
	check(TerritorySystem.rects_overlap(Vector3.ZERO, 0.0, Vector2(3, 0.5), Vector3(0, 0, 0), PI * 0.5, Vector2(3, 0.5)), "a cross overlaps")
	check(not TerritorySystem.rects_overlap(Vector3.ZERO, PI * 0.25, Vector2(1, 1), Vector3(3.0, 0, 0), PI * 0.25, Vector2(1, 1)), "turned squares with a gap")
	check(TerritorySystem.rects_overlap(Vector3.ZERO, PI * 0.25, Vector2(1, 1), Vector3(2.5, 0, 0), PI * 0.25, Vector2(1, 1)), "turned squares corner to corner")
	check(TerritorySystem.point_in_rect(Vector3(1.9, 0, 0), Vector3.ZERO, 0.0, Vector2(2, 1), 0.0), "point inside")
	check(not TerritorySystem.point_in_rect(Vector3(0, 0, 1.6), Vector3.ZERO, 0.0, Vector2(2, 1), 0.5), "point outside the margin")


func test_buildings_away_from_roads_get_a_lane() -> void:
	var state := WorldGenerator.generate("territory-lane")
	state.house.gold = 500
	# Walk out from a road until a spot needs a lane but is still allowed.
	var placed: Dictionary = {}
	for road in state.layout.roads:
		var pts: PackedVector3Array = road["points"]
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			if a.length() < 25.0 or a.length() > 70.0:
				continue
			var normal := Vector3(-(b - a).normalized().z, 0, (b - a).normalized().x)
			for side: float in [1.0, -1.0]:
				var pos := a + normal * side * 20.0
				var rot := atan2(-normal.x * side, -normal.z * side)
				var chk := TerritorySystem.check_placement(state, "quarry", pos, rot)
				if chk["ok"] and not (chk["lane"] as PackedVector3Array).is_empty():
					placed = {"pos": pos, "rot": rot}
					break
			if not placed.is_empty():
				break
		if not placed.is_empty():
			break
	check(not placed.is_empty(), "found a spot back from the road")
	if placed.is_empty():
		return
	var res := TerritorySystem.place(state, "quarry", placed["pos"], placed["rot"])
	check(res["ok"], "it can be ordered")
	var site: ConstructionSite = res["site"]
	check(not site.lane.is_empty(), "a lane is laid to the door")
	var graph := RoadGraph.new()
	graph.build(state.layout)
	var path := graph.find_path(site.building.door_position(), state.layout.square_center)
	var longest := 0.0
	for i in range(1, path.size()):
		longest = maxf(longest, path[i - 1].distance_to(path[i]))
	check(longest < 12.0, "villagers can walk from the door to the square along the lane (longest leg %.1f m)" % longest)
	for i in state.layout.trees.size():
		var t := state.layout.trees[i]
		if TerritorySystem.point_in_rect(Vector3(t.x, 0, t.y), site.building.position, site.building.rotation, site.building.footprint * 0.5, 0.5):
			check(state.territory.cleared_trees.has(i), "trees under the building are felled")


func test_freed_builders_join_other_sites() -> void:
	var state := WorldGenerator.generate("territory-crews")
	state.house.gold = 5000
	for r: String in TerritorySystem.RESOURCES:
		state.territory.stock[r] = 600.0
	var sites: Array[ConstructionSite] = []
	for type: String in ["quarry", "storehouse", "workshop", "bakery", "quarry"]:
		var s := _place(state, type)
		if s:
			sites.append(s)
	var short: ConstructionSite = null
	for s in sites:
		if short == null and s.builders.size() < int(TerritorySystem.section("construction").get("crew", 3)):
			short = s
	check(short != null, "with many sites the builders run out")
	if short == null:
		return
	var before := short.builders.size()
	var first := sites[0]
	first.work_done = first.work_needed
	TerritorySystem.complete(state, first)
	check(short.builders.size() > before, "a finished crew moves on to a short-handed site")
	var c := state.get_character(short.builders[0])
	CourtSystem.join(state, c)
	check(TerritorySystem.builder_site(state, c) == null, "a new retainer leaves the building crew at once")
