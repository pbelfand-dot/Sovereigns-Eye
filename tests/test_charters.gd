extends TestCase
## Phase 3.3 charters: Hamlet -> Village -> Market Town -> Town. Each
## charter has a checklist and a fee, raises the population limit, unlocks
## buildings (taverns, chapels, the Market Hall), brings in dues and widens
## the household.

const OLD_SLOT := "test_charter_migration"


func _world(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.house.gold = 5000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 900.0
	return st


## Adds copies of villagers until `n` people live here (a stand-in for
## settlers, so tests don't wait months).
func _grow_to(st: WorldState, n: int) -> void:
	var next_id := 0
	for c in st.characters:
		next_id = maxi(next_id, c.id + 1)
	var i := 0
	while st.characters.size() < n:
		var src := st.characters[i % 40]
		var copy := CharacterData.from_dict(src.to_dict())
		copy.id = next_id
		copy.retainer = false
		copy.office = ""
		next_id += 1
		i += 1
		st.add_character(copy)


## Meets every requirement of charter `index` (except the fee).
func _meet(st: WorldState, index: int) -> void:
	for r: Dictionary in CharterSystem.tier_def(index).get("requires", []):
		match str(r["id"]):
			"population":
				_grow_to(st, int(r["count"]))
			"homes_tier":
				var need := int(r["count"])
				for b in GrowthSystem.homes(st):
					if need <= 0:
						break
					if GrowthSystem.can_level(b):
						b.tier = maxi(b.tier, int(r["tier"]))
						need -= 1
			"renown":
				st.house.renown = maxi(st.house.renown, int(r["value"]))
			"content":
				for c in st.characters:
					c.happiness = maxf(c.happiness, float(r["happiness"]) + 5.0)
			"building":
				var have := st.layout.buildings_of_type(str(r["type"])).size()
				for k in maxi(int(r["count"]) - have, 0):
					_raise(st, str(r["type"]))


## Orders a building and finishes it at once.
func _raise(st: WorldState, type: String) -> BuildingData:
	var spot := TerritorySystem.find_spot(st, type)
	check(not spot.is_empty(), "found a spot for a %s" % type)
	if spot.is_empty():
		return null
	var res := TerritorySystem.place(st, type, spot["pos"], spot["rot"])
	check(res["ok"], "a %s can be ordered (%s)" % [type, res.get("text", "")])
	if not res["ok"]:
		return null
	var site: ConstructionSite = res["site"]
	site.work_done = site.work_needed
	TerritorySystem.complete(st, site)
	return st.get_building(site.id())


func test_a_new_settlement_is_a_hamlet() -> void:
	var st := _world("charter-start")
	check_eq(CharterSystem.current(st), 0, "new games start with no charter")
	check_eq(CharterSystem.title(st), "Hamlet", "a hamlet")
	check_eq(CharterSystem.max_population(st), 70, "with room for 70")
	_grow_to(st, 70)
	check(GrowthSystem.at_capacity(st), "70 people fill a hamlet")
	check_eq(GrowthSystem.progress_per_day(st), 0.0, "and no more settlers come")
	var check_r := CharterSystem.can_petition(st)
	check(not check_r["ok"], "a fresh hamlet can't petition yet")
	check(str(check_r["reason"]).contains("requirement"), "and says how much is missing: %s" % check_r["reason"])


func test_petitioning_for_a_village_charter() -> void:
	var st := _world("charter-village")
	var reqs := CharterSystem.requirements(st, 1)
	check(reqs.size() >= 4, "the Village charter has a checklist")
	_meet(st, 1)
	for r in CharterSystem.requirements(st, 1):
		check(r["ok"], "met: %s (%s)" % [r["label"], r["detail"]])
	st.house.gold = 10
	var poor := CharterSystem.can_petition(st)
	check(not poor["ok"] and str(poor["reason"]).contains("gold"), "the fee must be paid: %s" % poor["reason"])
	st.house.gold = 1000
	var wood := st.territory.amount("wood")
	var renown := st.house.renown
	var props := st.layout.props.size()
	var r := CharterSystem.petition(st)
	check(r["ok"], "the petition is granted: %s" % r["text"])
	check_eq(CharterSystem.current(st), 1, "now a village")
	check_eq(CharterSystem.max_population(st), 110, "with room for 110")
	check_eq(st.house.gold, 1000 - int(CharterSystem.tier_def(1)["cost"]["gold"]), "the gold fee is paid")
	check_eq(st.territory.amount("wood"), wood - 40.0, "and the wood")
	check(st.house.renown > renown, "renown rises")
	check_eq(st.layout.props.size(), props + 2, "two new banners hang around the square")
	check(str(st.house.chronicle.back()["text"]).contains("charter"), "the chronicle records it")
	check(not GrowthSystem.at_capacity(st), "settlers may come again")


func test_charters_unlock_buildings() -> void:
	var st := _world("charter-unlocks")
	var tav := TerritorySystem.can_build(st, "tavern")
	check(not tav["ok"] and str(tav["reason"]).contains("Village"), "a hamlet can't raise a tavern: %s" % tav["reason"])
	check(str(TerritorySystem.can_build(st, "market")["reason"]).contains("Market Town"), "the Market Hall needs a Market Town charter")
	_meet(st, 1)
	CharterSystem.petition(st)
	check(TerritorySystem.can_build(st, "tavern")["ok"], "a village may raise a tavern")
	check(TerritorySystem.can_build(st, "chapel")["ok"], "and a chapel")
	var t := _raise(st, "tavern")
	check(t != null, "a second tavern stands")
	check(not TerritorySystem.can_build(st, "tavern")["ok"], "one new tavern is a village's limit")
	check(not TerritorySystem.can_build(st, "market")["ok"], "still no market")
	check(CharterSystem.unlocked_by(2).has("Market Hall"), "the Market Town charter brings the Market Hall")


func test_market_halls_trade_and_draw_settlers() -> void:
	var st := _world("charter-market")
	for i in 2:
		_meet(st, i + 1)
		var r := CharterSystem.petition(st)
		check(r["ok"], "charter %d granted (%s)" % [i + 1, r["text"]])
	check_eq(CharterSystem.title(st), "Market Town", "a market town")
	var income_before := CourtSystem.daily_income(st)
	var hall := _raise(st, "market")
	check(hall != null, "a Market Hall stands")
	if hall == null:
		return
	var merchants := 0
	for c in st.characters:
		if c.work_building_id == hall.id and c.occupation_id == "merchant":
			merchants += 1
	check_eq(merchants, 2, "two merchants take up trade there")
	check(CharterSystem.market_income(st) >= 6, "trade brings in gold (%d a day)" % CharterSystem.market_income(st))
	check(CourtSystem.daily_income(st) > income_before, "the house's daily income rises")
	var labels: Array[String] = []
	for f in GrowthSystem.appeal_factors(st):
		labels.append(str(f["label"]))
	check(labels.has("Market day"), "market days draw settlers: %s" % ", ".join(labels))
	check(labels.has("A chartered market town"), "and so does the charter")


func test_a_market_hall_serves_townhouses_far_from_the_square() -> void:
	var st := _world("charter-townhouse")
	for i in 2:
		_meet(st, i + 1)
		CharterSystem.petition(st)
	var far: BuildingData = null
	for b in GrowthSystem.homes(st):
		if GrowthSystem.can_level(b) and Vector2(b.position.x - st.layout.square_center.x, b.position.z - st.layout.square_center.z).length() > 60.0:
			far = b
			break
	if far == null:
		# No home out that far in this village: move one there for the test.
		for b in GrowthSystem.homes(st):
			if GrowthSystem.can_level(b):
				far = b
				break
		far.position = st.layout.square_center + Vector3(70, 0, 0)
	var hall := _raise(st, "market")
	if hall == null:
		return
	hall.position = far.position + Vector3(12, 0, 0)
	far.tier = 1
	var market_ok := false
	var needs := GrowthSystem.home_needs(st, far)
	check(not needs.is_empty(), "a timber house has needs for its next level")
	for n in needs:
		if str(n["label"]).to_lower().contains("market"):
			market_ok = bool(n["ok"])
	check(market_ok, "a nearby Market Hall counts as the market")


func test_charters_widen_the_household() -> void:
	var st := _world("charter-household")
	var cap := CourtSystem.retainer_cap(st)
	_meet(st, 1)
	CharterSystem.petition(st)
	var renown_places := floori(st.house.renown / float(CourtSystem.section("house").get("renown_per_extra_retainer", 15)))
	var before_renown := floori((st.house.renown - int(CharterSystem.tier_def(1).get("renown", 0))) / float(CourtSystem.section("house").get("renown_per_extra_retainer", 15)))
	check_eq(CourtSystem.retainer_cap(st) - cap, 1 + renown_places - before_renown, "a village keeps one more retainer (plus any from new renown)")


func test_the_highest_charter_is_the_last() -> void:
	var st := _world("charter-town")
	for i in CharterSystem.top():
		_meet(st, i + 1)
		var r := CharterSystem.petition(st)
		check(r["ok"], "%s granted (%s)" % [CharterSystem.title_of(i + 1), r["text"]])
	check_eq(CharterSystem.title(st), "Town", "a town at last")
	check_eq(CharterSystem.max_population(st), 200, "with room for 200")
	var r2 := CharterSystem.can_petition(st)
	check(not r2["ok"] and int(r2["next"]) == -1, "nothing higher to petition for")
	check(CharterSystem.dues(st) >= 10, "a town's dues")


func test_charters_survive_saving_and_migrate() -> void:
	var st := _world("charter-save")
	_meet(st, 1)
	CharterSystem.petition(st)
	var back := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	check_eq(back.territory.charter, 1, "the charter is saved")
	# A v6 save: no charter field. Small villages become hamlets, larger
	# ones villages, so nobody is over their limit.
	for people: int in [55, 90]:
		var s2 := _world("charter-migrate")
		_grow_to(s2, people)
		var old := JSON.parse_string(JSON.stringify(s2.to_dict())) as Dictionary
		old["save_version"] = 6
		(old["territory"] as Dictionary).erase("charter")
		var migrated := WorldState.from_dict(SaveManager.migrate(old))
		check_eq(migrated.territory.charter, 0 if people <= 70 else 1, "%d people migrate to the right charter" % people)
		check(GrowthSystem.population(migrated) <= CharterSystem.max_population(migrated), "within the limit")


func test_the_market_hall_is_built_from_the_kit() -> void:
	check(VillageKit.has_prefab("market"), "the Market Hall has a kit recipe")
	var p := VillageKit.prefab("market", 0, 0)
	var names := {}
	for part: Array in p.get("parts", []):
		names[str(part[0])] = true
	check(names.has("Wall_Arch"), "with open arches below: %s" % ", ".join(names.keys()).left(200))
	check(float(p.get("height", 0.0)) > 6.0, "and a hall above (%.1f m)" % float(p.get("height", 0.0)))


func test_townhouses_take_lodgers_in_market_towns() -> void:
	var st := _world("charter-lodgers")
	var townhouse: BuildingData = null
	for b in GrowthSystem.homes(st):
		if GrowthSystem.can_level(b) and not st.residents_of(b.id).is_empty():
			townhouse = b
			break
	townhouse.tier = 2
	check_eq(GrowthSystem.family_capacity(st, townhouse), 1, "in a hamlet a townhouse holds one family")
	for i in 2:
		_meet(st, i + 1)
		CharterSystem.petition(st)
	check_eq(GrowthSystem.family_capacity(st, townhouse), 2, "in a market town it takes lodgers")
	check(GrowthSystem.homes_with_room(st).has(townhouse), "so it has room for another family")
	# Fill every empty home so the next settlers must lodge.
	for b in GrowthSystem.empty_homes(st):
		b.type = "storehouse"
	var rent_before := GrowthSystem.rent(st)
	var fam := GrowthSystem.settle(st)
	check(fam != null, "settlers still find a place")
	if fam:
		var lodging := st.get_building(fam.home_building_id)
		check(lodging.tier >= 2, "they lodge in a townhouse")
		check_eq(GrowthSystem.family_counts(st)[lodging.id], 2, "two families live there now")
		check(GrowthSystem.rent(st) > rent_before, "and the lodgers pay rent too")
		check(not GrowthSystem.homes_with_room(st).has(lodging), "then it's full")
	_meet(st, 3)
	CharterSystem.petition(st)
	check_eq(GrowthSystem.family_capacity(st, townhouse), 3, "a town packs in a third family")
