extends TestCase
## Phase 5.3, the house's castle (CastleSystem, CastleData, data/castle.json):
## ordered when the charter allows, sited on open ground, built by the
## village's builders out of the stores, and what it gives when it stands.


func _village(seed_text: String, charter: int) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.territory.charter = charter
	st.house.gold = 2000
	for r: String in ["wood", "stone"]:
		TerritorySystem.add(st, r, 400.0)
	return st


## Works the castle for `days` whole days (a work hour at a time).
func _work(st: WorldState, days: int) -> bool:
	var done := false
	for i in days * 24:
		st.minutes += 60.0
		if CastleSystem.advance(st, 60.0):
			done = true
			break
	return done


func test_ordering_a_castle() -> void:
	var st := _village("castle-order", 0)
	check(not CastleSystem.can_order(st, "timber")["ok"], "a hamlet can't raise a castle: %s" % CastleSystem.can_order(st, "timber")["reason"])
	st.territory.charter = 1
	check(not CastleSystem.can_order(st, "stone")["ok"], "first a motte and bailey")
	st.house.gold = 10
	check(not CastleSystem.can_order(st, "timber")["ok"], "the hire must be paid")
	st.house.gold = 2000
	var xf := CastleSystem.choose_site(st)
	check(xf != Transform3D.IDENTITY, "there's ground for a castle round the village")
	check(CastleLayout.spot_clear(st.layout, xf, CastleLayout.site_rect(), [], true), "clear of buildings, fields, roads and yards, with room for the stone castle too")
	check_eq(CastleSystem.choose_site(WorldGenerator.generate("castle-order")), xf, "(the same ground for the same village)")
	check(xf.basis.z.dot(-xf.origin.normalized()) > -0.05, "its gate toward the village (or side on, where the ground is tight)")
	var trees := st.territory.cleared_trees.size()
	var wood := TerritorySystem.amount(st, "wood")
	var r := CastleSystem.order(st, "timber")
	check(r["ok"] and st.castle.works == "timber" and st.house.gold == 2000 - int(CastleSystem.kind_def("timber")["gold"]), "ordered: %s" % r["text"])
	check(st.territory.cleared_trees.size() - trees == int(r["felled"]) and (int(r["felled"]) == 0 or TerritorySystem.amount(st, "wood") > wood), "the trees on the ground felled for their wood (%d)" % int(r["felled"]))
	check(not CastleSystem.can_order(st, "timber")["ok"], "(one works at a time)")
	var crew := st.castle.builders
	check(not crew.is_empty() and crew.size() <= int(CastleSystem.kind_def("timber")["crew"]), "a crew of %d builders" % crew.size())
	var mason := st.get_character(crew[0])
	check(TerritorySystem.worker_output(st, mason).is_empty(), "who make nothing else while they build")
	var copy := WorldState.from_dict(st.to_dict())
	check_eq(copy.castle.to_dict(), st.castle.to_dict(), "the works are saved")


func test_the_works_rise_and_wait_for_wood() -> void:
	var st := _village("castle-works", 1)
	CastleSystem.order(st, "timber")
	var per_day := CastleSystem.daily_rate(st)
	check(per_day > 0.0, "the crew puts in %.0f builder-hours a day" % per_day)
	check(CastleSystem.pieces(st).is_empty(), "nothing stands yet")
	_work(st, 3)
	var c := st.castle
	check(c.work_done > 0.0 and float(c.used.get("wood", 0.0)) > 0.0, "the works use wood as they go (%.0f)" % float(c.used.get("wood", 0.0)))
	var standing := CastleSystem.pieces(st).size()
	check(standing > 0 and standing < CastleLayout.layout("timber").size(), "and rise piece by piece (%d of %d)" % [standing, CastleLayout.layout("timber").size()])
	TerritorySystem.add(st, "wood", -TerritorySystem.amount(st, "wood"))
	var before := c.work_done
	_work(st, 1)
	check(c.work_done == before and c.stalled == "wood", "with no wood the works wait")
	check(CastleSystem.daily_update(st).any(func(e: Dictionary) -> bool: return str(e["text"]).contains("wait for wood")), "(and you hear of it)")
	TerritorySystem.add(st, "wood", 400.0)
	var renown := st.house.renown
	var cap := CourtSystem.retainer_cap(st)
	var regard := int(st.realm.houses[0]["standing"])
	check(_work(st, 60), "the motte and bailey is finished in time")
	var events := CastleSystem.complete(st)
	check(st.castle.kind == "timber" and st.castle.works.is_empty(), "it stands: %s" % events[0]["text"])
	check(st.house.renown > renown and CourtSystem.retainer_cap(st) >= cap + int(CastleSystem.kind_def("timber")["retainers"]), "the house is raised by it (household %d -> %d)" % [cap, CourtSystem.retainer_cap(st)])
	check(int(st.realm.houses[0]["standing"]) > regard, "and the houses round about take note")
	check_eq(CastleSystem.pieces(st).size(), CastleLayout.layout("timber").size(), "every piece stands")


func test_stone_in_place_of_timber() -> void:
	var st := _village("castle-stone", 1)
	CastleSystem.order(st, "timber")
	_work(st, 60)
	CastleSystem.complete(st)
	check(not CastleSystem.can_order(st, "stone")["ok"], "a stone castle needs a market town: %s" % CastleSystem.can_order(st, "stone")["reason"])
	st.territory.charter = 2
	TerritorySystem.add(st, "stone", 700.0)
	var site := st.castle.site.duplicate()
	check(CastleSystem.order(st, "stone")["ok"], "the stone castle is begun")
	check_eq(st.castle.site, site, "on the same ground")
	var timber := CastleLayout.layout("timber").size()
	st.castle.work_done = st.castle.work_needed * 0.5
	var mid := CastleSystem.pieces(st)
	var old := mid.filter(func(p: Array) -> bool: return CastleLayout.layout("timber").any(func(q: Array) -> bool: return q[0] == p[0] and q[1] == p[1]))
	check(old.size() < timber and old.size() > 0, "half way, the old castle is half down (%d of %d)" % [old.size(), timber])
	check(old.any(func(p: Array) -> bool: return p[0] == "SE_Motte"), "its motte the last to go")
	st.castle.work_done = st.castle.work_needed
	CastleSystem.complete(st)
	check(st.castle.kind == "stone" and CastleSystem.pieces(st).size() == CastleLayout.layout("stone").size(), "the stone castle stands alone")


func test_a_castle_in_a_raid() -> void:
	var st := _village("castle-raid", 1)
	st.minutes += 70.0 * Calendar.MINUTES_PER_DAY
	Military.plan_raid(st, Seeds.rng(1, "open"))
	var open_loot := int(st.military.raid["loot_gold"])
	var open_sides := Military.sides(st)
	var open_hold := Military.breaking_point(open_sides["ours"])
	st.military.raid = {}
	st.castle.kind = "stone"
	st.castle.site = [80.0, 0.0, 0.0]
	Military.plan_raid(st, Seeds.rng(1, "open"))
	check(open_loot > 0 and int(st.military.raid["loot_gold"]) == 0, "behind stone walls the house's gold is out of reach (%d -> %d)" % [open_loot, int(st.military.raid["loot_gold"])])
	var walled := Military.sides(st)
	check(int(walled["ours"][0]["combat"]) == int(open_sides["ours"][0]["combat"]) + int(CastleSystem.kind_def("stone")["combat"]), "the warband fights harder at the gate")
	check(Military.breaking_point(walled["ours"]) > open_hold, "and breaks later")
	check(Military.camp_sides(st, Military.make_camp(st, Seeds.rng(2, "c"))["camp"], false)["ours"].all(func(f: Dictionary) -> bool: return not f.has("steady")), "(not at a camp, far from its walls)")
	var rally := CastleSystem.rally_point(st)
	check(rally.distance_to(st.castle.transform().origin) > CastleLayout.gate_z("stone"), "they form up before its gate")


func test_an_older_save_has_no_castle() -> void:
	var st := _village("castle-old", 1)
	var old := st.to_dict()
	old["save_version"] = 17
	old.erase("castle")
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.castle != null and migrated.castle.kind.is_empty() and migrated.castle.works.is_empty(), "an older save starts without a castle")


func test_the_castle_in_the_world() -> void:
	Game.state = _village("castle-world", 1)
	var st := Game.state
	st.minutes += 70.0 * Calendar.MINUTES_PER_DAY
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var r := world.order_castle("timber")
	check(r["ok"], "ordered in the world: %s" % r["text"])
	var xf := st.castle.transform()
	for p: Vector3 in [Vector3(0, 0, 0), Vector3(0, 0, 30), Vector3(-20, 0, -20)]:
		var w := xf * p
		check(absf(TerrainHeight.height_at(w.x, w.z)) < 0.05, "the ground is level under the castle (%.2f)" % TerrainHeight.height_at(w.x, w.z))
	check(st.layout.roads.any(func(road: Dictionary) -> bool: return road["name"] == "castle_lane"), "a lane runs to its gate")
	check(not world.graph.find_path(st.layout.square_center, CastleSystem.rally_point(st)).is_empty(), "the castle can be walked to")
	check_eq(world.castle_view.piece_count(), 0, "nothing stands at first")
	st.castle.work_done = st.castle.work_needed * 0.5
	world.castle_view.refresh()
	var half := world.castle_view.piece_count()
	check(half > 0 and half < CastleLayout.layout("timber").size(), "half way, %d pieces stand" % half)
	CastleSystem.complete(st)
	world.castle_view.refresh()
	check(st.castle.kind == "timber" and world.castle_view.piece_count() == CastleLayout.layout("timber").size(), "the motte and bailey stands")
	var motte := xf.origin
	check(world.view_blocked_at(xf * Vector3(0, 3, 40), xf * Vector3(0, 3, -40)) < 1.0, "it stands in the way of the view (the follow camera rises over it)")
	check_eq(world.view_blocked_at(xf * Vector3(0, 40, 40), xf * Vector3(0, 40, -40)), 1.0, "(but not of the sky)")
	var pushed := WorldGeometry.resolve(st, motte + Vector3(1, 0, 1), 0.35)
	check(Vector2(pushed.x - motte.x, pushed.z - motte.z).length() >= 13.0, "no one walks through the motte")
	Military.plan_raid(st, Seeds.rng(4, "castle"))
	st.military.raid["day"] = st.day()
	st.minutes = float(st.day() * Calendar.MINUTES_PER_DAY + Military.strike_hour() * 60 + 1)
	world._process(0.016)
	check(world.battle != null and world.battle._rally.distance_to(CastleSystem.rally_point(st)) < 0.5, "a raid is met before the castle's gate")
	check(world.battle._loot_point.distance_to(CastleSystem.rally_point(st)) < 0.5, "(the band comes for the castle, where the gold is)")
	world.queue_free()
	await frames(2)
