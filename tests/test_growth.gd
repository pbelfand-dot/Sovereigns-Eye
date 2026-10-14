extends TestCase
## Phase 3 step 2: homes that build and upgrade themselves, settler families,
## appeal, rent, and saves.

const OLD_SLOT := "test_phase3_step1_migration"


func _world(seed_text: String) -> WorldState:
	var st := WorldGenerator.generate(seed_text)
	st.house.gold = 2000
	for r: String in TerritorySystem.RESOURCES:
		st.territory.stock[r] = 600.0
	return st


## A finished, empty cottage beside a road (as if the village had built it).
func _empty_cottage(st: WorldState) -> BuildingData:
	var site := GrowthSystem.order_home(st)
	check(site != null, "the village can order a cottage")
	if site == null:
		return null
	site.work_done = site.work_needed
	TerritorySystem.complete(st, site)
	return st.get_building(site.id())


## Runs days like the game does: construction every half hour, then the
## daily updates. Returns growth events.
func _run_days(st: WorldState, days: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
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
		events.append_array(GrowthSystem.daily_update(st))
	return events


func test_upgrades_keep_the_ground_floor() -> void:
	if not VillageKit.available():
		return
	for type: String in ["cottage", "farmhouse"]:
		for v in VillageKit.variants(type).size():
			var base := VillageKit.prefab(type, v, 0)
			var up := VillageKit.prefab(type, v, 1)
			var top := VillageKit.wall_height(type, v, 0)
			var base_parts := {}
			for p: Array in base["parts"]:
				if (p[1] as Transform3D).origin.y < top - 0.01:
					base_parts["%s@%s" % [p[0], str((p[1] as Transform3D).origin.snappedf(0.01))]] = true
			var up_parts := {}
			for p: Array in up["parts"]:
				if (p[1] as Transform3D).origin.y < top - 0.01:
					up_parts["%s@%s" % [p[0], str((p[1] as Transform3D).origin.snappedf(0.01))]] = true
			check_eq(up_parts, base_parts, "%s %d: an upgrade keeps the walls it already has" % [type, v])
			check(float(up["height"]) > float(base["height"]) or VillageKit.wall_height(type, v, 1) == top, "%s %d: an upgrade is taller" % [type, v])
	var t2 := VillageKit.tier_recipe(VillageKit.variants("cottage")[0], 2)
	check(bool(t2.get("balcony", false)), "a townhouse has a balcony")
	check(VillageKit.wall_height("cottage", 0, 2) <= 9.0, "homes stay at three stories or fewer")


func test_settlers_are_made_like_villagers() -> void:
	var st := _world("growth-settlers")
	var home := _empty_cottage(st)
	if home == null:
		return
	var before := st.characters.size()
	var names := {}
	for c in st.characters:
		names[c.full_name()] = true
	var fam := GrowthSystem.settle(st)
	check(fam != null, "a family settles in the empty cottage")
	if fam == null:
		return
	check(fam.member_ids.size() >= 1 and fam.member_ids.size() <= 6, "a family of 1-6 (%d)" % fam.member_ids.size())
	check_eq(st.characters.size(), before + fam.member_ids.size(), "they join the village")
	check_eq(fam.home_building_id, home.id, "they live in the empty home")
	check(home.name.begins_with(fam.name), "the home takes their name (%s)" % home.name)
	var entry_ok := true
	for id in fam.member_ids:
		var c := st.get_character(id)
		check(not names.has(c.full_name()), "%s is a new name" % c.full_name())
		check_eq(c.home_building_id, home.id, "everyone lives at home")
		check(not c.traits.is_empty(), "they have a personality")
		check(not c.appearance.is_empty(), "they have a look")
		check(not c.occupation_id.is_empty(), "they have a place in life")
		if c.is_adult():
			check(c.occupation().has("workplace"), "adults have a real job (%s)" % c.occupation_id)
		for attr: String in GameData.attribute_ids():
			check(c.get_current(attr) <= c.get_potential(attr), "ability never passes potential")
		var settled := false
		for h in c.history:
			if str(h["text"]).begins_with("Settled in"):
				settled = true
		check(settled, "their story says they came to settle")
		entry_ok = entry_ok and c.inside_building_id == -1 and c.position.distance_to(Vector3.ZERO) > 60.0
	check(entry_ok, "settlers start at the edge of the map and walk in")
	var again := _world("growth-settlers")
	_empty_cottage(again)
	var fam2 := GrowthSystem.settle(again)
	check(fam2 != null and fam2.name == fam.name and fam2.member_ids.size() == fam.member_ids.size(), "the same village draws the same settlers")


func test_the_settler_bar_brings_a_family() -> void:
	var st := _world("growth-bar")
	_empty_cottage(st)
	check(GrowthSystem.appeal(st) > 0.0, "a fed village is appealing (%.0f)" % GrowthSystem.appeal(st))
	check(GrowthSystem.progress_per_day(st) > 0.0, "the settler bar fills")
	st.territory.settler_progress = 99.0
	var before := st.characters.size()
	var events := GrowthSystem.daily_update(st)
	var arrived: Array = []
	for e in events:
		if e.has("arrived"):
			arrived = e["arrived"]
	check(not arrived.is_empty(), "a family arrives when the bar is full")
	check_eq(st.characters.size(), before + arrived.size(), "the arrivals are in the village")
	check(st.territory.settler_progress < 1.0, "the bar starts again")
	check_eq(st.territory.settler_families, 1, "the arrival is counted")


func test_full_homes_mean_a_new_cottage() -> void:
	var st := _world("growth-homes")
	check(GrowthSystem.empty_homes(st).is_empty(), "every home is lived in at the start")
	var events := GrowthSystem.daily_update(st)
	var site: ConstructionSite = null
	for s in st.territory.sites:
		if s.kind == "home":
			site = s
	check(site != null, "the village orders a cottage when every home is full")
	var announced := false
	for e in events:
		announced = announced or e.has("site")
	check(announced, "the new site is announced")
	if site == null:
		return
	check(not site.builders.is_empty(), "a crew builds it")
	check(TerritorySystem.road_clearance(st.layout, site.building.door_position()) < 3.0, "its door faces a road")
	check(site.lane.is_empty(), "homes go right beside a road")
	GrowthSystem.daily_update(st)
	var homes_sites := 0
	for s in st.territory.sites:
		if s.kind == "home":
			homes_sites += 1
	check_eq(homes_sites, 1, "one new home at a time")
	site.work_done = site.work_needed
	TerritorySystem.complete(st, site)
	check_eq(GrowthSystem.empty_homes(st).size(), 1, "the finished cottage stands ready for settlers")


func test_auto_building_keeps_a_reserve_and_can_be_switched_off() -> void:
	var st := _world("growth-reserve")
	var reserve: Dictionary = GrowthSystem.growth_cfg()["auto"]["reserve"]
	st.territory.stock["wood"] = float(reserve["wood"]) + 10.0
	GrowthSystem.daily_update(st)
	check(st.territory.sites.is_empty(), "no home is ordered when it would eat into the reserve")
	check(st.territory.amount("wood") >= float(reserve["wood"]), "the reserve is kept")
	var st2 := _world("growth-toggle")
	st2.territory.auto_homes = false
	GrowthSystem.daily_update(st2)
	check(st2.territory.sites.is_empty(), "switched off, the village builds nothing by itself")


func test_homes_upgrade_when_their_needs_are_met() -> void:
	var st := _world("growth-upgrade")
	var chapel := st.layout.buildings_of_type("chapel")[0]
	var home: BuildingData = null
	for b in GrowthSystem.homes(st):
		if b.type == "cottage" and not st.residents_of(b.id).is_empty() and b.position.distance_to(chapel.position) < 55.0:
			home = b
			break
	check(home != null, "found a lived-in cottage near the chapel")
	if home == null:
		return
	check(not GrowthSystem.can_upgrade(st, home), "a home isn't upgraded on day one")
	st.territory.home_since[home.id] = st.day() - 10
	for c in st.residents_of(home.id):
		c.happiness = 80.0
	var needs := GrowthSystem.home_needs(st, home)
	check(needs.size() >= 3, "the next level lists its needs")
	for n in needs:
		check(n["ok"], "need met: %s (%s)" % [n["label"], n["detail"]])
	check(GrowthSystem.can_upgrade(st, home), "a settled, happy, fed home near a chapel can upgrade")
	var rent_before := GrowthSystem.rent(st)
	var income_before := CourtSystem.daily_income(st)
	var site := GrowthSystem.order_upgrade(st, home)
	check(site != null and site.is_upgrade(), "an upgrade site opens")
	if site == null:
		return
	check(st.get_building(home.id) == home, "the home stays in the village while it's rebuilt")
	check(GrowthSystem.empty_homes(st).find(home) < 0, "a home being rebuilt isn't offered to settlers")
	site.work_done = site.work_needed
	TerritorySystem.complete(st, site)
	check_eq(home.tier, 1, "the home went up a level")
	check(home.name.ends_with("House"), "it's a house now (%s)" % home.name)
	check(GrowthSystem.rent(st) > rent_before, "better homes pay rent")
	check(CourtSystem.daily_income(st) > income_before, "rent reaches the treasury")
	var fine := false
	for f in MoodSystem.happiness_factors(st.residents_of(home.id)[0], st):
		fine = fine or str(f["label"]).begins_with("Fine home")
	check(fine, "the family enjoys their finer home")
	check(not GrowthSystem.can_upgrade(st, home), "the next level needs time again")


func test_hunger_blocks_upgrades_and_settlers() -> void:
	var st := _world("growth-hunger")
	st.territory.stock["food"] = 0.0
	check(GrowthSystem.appeal(st) < 0.0, "no one settles in a hungry village")
	check_eq(GrowthSystem.progress_per_day(st), 0.0, "the settler bar stops")
	for b in GrowthSystem.homes(st):
		st.territory.home_since[b.id] = st.day() - 30
		check(not GrowthSystem.can_upgrade(st, b), "no upgrades while the granary is empty")


func test_growth_survives_save_and_load() -> void:
	var st := _world("growth-save")
	var home: BuildingData = null
	for b in GrowthSystem.homes(st):
		if not st.residents_of(b.id).is_empty():
			home = b
			break
	st.territory.settler_progress = 42.5
	st.territory.auto_homes = false
	home.tier = 1
	var site := TerritorySystem.open_upgrade(st, home, 2, {}, 30.0)
	site.work_done = 7.0
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	check_eq(loaded.territory.settler_progress, 42.5, "the settler bar is saved")
	check_eq(loaded.territory.auto_homes, false, "the auto switch is saved")
	var lhome := loaded.get_building(home.id)
	check_eq(lhome.tier, 1, "home levels are saved")
	var lsite := loaded.territory.get_site(home.id)
	check(lsite != null and lsite.is_upgrade() and lsite.target_tier == 2, "an upgrade in progress is saved")
	if lsite:
		check(lsite.building == lhome, "after loading, the upgrade works on the home itself")
	check_eq(loaded.territory.home_since, st.territory.home_since, "when families settled is saved")
	# Saves from step 1 load as first-level homes with an empty bar.
	var old := WorldGenerator.generate("growth-migration").to_dict()
	old["save_version"] = 3
	for k: String in ["founded_day", "home_since", "settler_progress", "settler_families", "auto_homes"]:
		(old["territory"] as Dictionary).erase(k)
	for b: Dictionary in old["layout"]["buildings"]:
		b.erase("tier")
	DirAccess.make_dir_recursive_absolute(SaveManager.SAVE_DIR)
	var file := FileAccess.open(SaveManager.slot_path(OLD_SLOT), FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var migrated := SaveManager.load_state(OLD_SLOT)
	check(migrated != null, "a step 1 save loads")
	if migrated:
		check_eq(migrated.to_dict()["save_version"], WorldState.SAVE_VERSION, "and is upgraded to the current version")
		check(migrated.territory.auto_homes, "with homes building themselves")
		for b in migrated.layout.buildings:
			check_eq(b.tier, 0, "and first-level homes")
	SaveManager.delete(OLD_SLOT)


func test_a_village_grows_cleanly_over_two_months() -> void:
	var st := WorldGenerator.generate("growth-two-months")
	st.house.gold = 400
	var quarry := TerritorySystem.find_spot(st, "quarry")
	check(TerritorySystem.place(st, "quarry", quarry["pos"], quarry["rot"])["ok"], "a yard for stone")
	var start := st.characters.size()
	_run_days(st, 60)
	check(st.characters.size() >= start + 8, "the village grew (%d -> %d)" % [start, st.characters.size()])
	check(st.territory.settler_families >= 2, "several families settled (%d)" % st.territory.settler_families)
	var upgraded := 0
	for b in GrowthSystem.homes(st):
		if b.tier > 0:
			upgraded += 1
	check(upgraded >= 1, "some homes went up a level (%d)" % upgraded)
	# Nothing overlaps, nothing sits on a road, everyone has a real home.
	var list := st.layout.buildings
	for i in list.size():
		for j in range(i + 1, list.size()):
			check(not TerritorySystem.rects_overlap(list[i].position, list[i].rotation, list[i].footprint * 0.5, list[j].position, list[j].rotation, list[j].footprint * 0.5),
				"%s and %s don't overlap" % [list[i].name, list[j].name])
	for id in st.territory.built:
		var b := st.get_building(id)
		check(TerritorySystem.road_clearance(st.layout, b.position) > 0.0, "%s isn't on a road" % b.name)
	var homes_seen := {}
	for c in st.characters:
		check(st.get_building(c.home_building_id) != null, "%s has a home" % c.full_name())
		var fam := st.get_family(c.family_id)
		if fam and GrowthSystem.is_home(st.get_building(c.home_building_id)):
			var key := c.home_building_id
			if homes_seen.has(key) and int(homes_seen[key]) != fam.id and st.territory.home_since.has(key) and st.get_building(key).name.begins_with(fam.name):
				check(false, "settler families don't share a home")
			homes_seen[key] = fam.id
	var ids := {}
	for c in st.characters:
		check(not ids.has(c.id), "character ids are unique")
		ids[c.id] = true
	var bids := {}
	for b in st.layout.buildings:
		check(not bids.has(b.id), "building ids are unique")
		bids[b.id] = true
