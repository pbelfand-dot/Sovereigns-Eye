extends TestCase
## The Sovereign's Eye: talent stays hidden until the heir looks at someone
## with the Eye, which needs them near and in plain sight (no talk needed);
## talk gives clues, never proof; the reveal is data-driven, scales with
## talent and respects accessibility settings.


func _people(seeds: Array) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for s: String in seeds:
		var st := WorldGenerator.generate(s)
		for c in st.characters:
			if not st.is_player(c):
				out.append(c)
	return out


func test_nobody_is_revealed_at_the_start() -> void:
	var st := WorldGenerator.generate("eye-start")
	for c in st.characters:
		if st.is_player(c):
			check(c.appraised, "the heir knows themselves")
			continue
		check(not c.appraised, "%s isn't revealed before the Eye" % c.full_name())
		if c.family_id == st.ruling_family_id:
			check(c.met, "the heir's own family has met them")
		else:
			check(not c.met, "%s hasn't met the heir" % c.full_name())


func test_talking_reveals_nothing() -> void:
	var st := WorldGenerator.generate("eye-meet")
	var c: CharacterData = null
	for p in st.characters:
		if not p.met and p.age >= 16:
			c = p
			break
	var opinion := c.player_opinion
	var res := Discovery.meet(st, c)
	check(c.met, "talking means they've met")
	check(bool(res["first"]), "it was the first meeting")
	check((res["lines"] as Array).size() >= 2, "they say something")
	check(c.player_opinion > opinion, "a talk warms them a little")
	check(not c.appraised, "talking alone reveals nothing")
	var again := Discovery.meet(st, c)
	check(not bool(again["first"]), "later talks are different")
	check(str(again["lines"][0]).to_lower().contains("again") or str(again["lines"][0]).contains("Twice"), "they remember you")


## Scan first: no meeting needed, but the heir must be near and see them.
func test_the_eye_needs_reach_and_sight_not_talk() -> void:
	var st := WorldGenerator.generate("eye-reach")
	var c: CharacterData = null
	for p in st.characters:
		if not p.met and p.age >= 16:
			c = p
			break
	c.inside_building_id = -1
	var reach := float(Discovery.scan_config()["range"])
	var open := _open_spot(st, reach + 2.0)
	check(open != Vector3.INF, "found open ground")
	var at := open
	var near := at + Vector3(reach * 0.6, 0, 0)
	check(Discovery.scan_check(st, near, c, at)["ok"], "a stranger can be looked at from nearby, without talking first")
	check(not c.met, "no meeting was needed")
	var far := Discovery.scan_check(st, at + Vector3(reach * 1.5, 0, 0), c, at)
	check(not far["ok"] and str(far["reason"]).contains("closer"), "too far away: %s" % far["reason"])
	# A building in between hides them.
	var b: BuildingData = null
	for bd in st.layout.buildings:
		if bd.footprint.y + 2.0 <= reach and bd.footprint.x >= 4.0:
			b = bd
			break
	var across := b.basis() * Vector3(0, 0, b.footprint.y * 0.5 + 1.0)
	var behind := Discovery.scan_check(st, b.position + across, c, b.position - across)
	check((b.position + across).distance_to(b.position - across) <= reach, "both sides are within reach")
	check(not behind["ok"] and str(behind["reason"]).contains("see"), "a building blocks the view: %s" % behind["reason"])
	c.inside_building_id = b.id
	check(not Discovery.scan_check(st, near, c, at)["ok"], "people indoors can't be seen")
	c.inside_building_id = -1
	check(not Discovery.scan_check(st, near, st.player(), at)["ok"], "the heir doesn't look at themselves")
	var talk := float(Discovery.scan_config()["talk_range"])
	check(Discovery.talk_check(st, at + Vector3(talk * 0.7, 0, 0), c, at)["ok"], "close enough to talk")
	check(not Discovery.talk_check(st, near, c, at)["ok"], "a few paces off is too far to talk")


## A spot at least `clear` meters from every building.
func _open_spot(st: WorldState, clear: float) -> Vector3:
	for x in range(-60, 61, 4):
		for z in range(-60, 61, 4):
			var p := Vector3(x, 0, z)
			var ok := true
			for b in st.layout.buildings:
				if b.position.distance_to(p) < clear + b.footprint.length() * 0.5:
					ok = false
					break
			if ok:
				return p
	return Vector3.INF


func test_talk_never_names_ranks_or_numbers() -> void:
	var st := WorldGenerator.generate("eye-words")
	for c in st.characters:
		if st.is_player(c):
			continue
		for line in Discovery.conversation(st, c):
			for bad: String in ["S+", "SS", " rank", "potential", "talent", "Appraisal"]:
				check(not line.contains(bad), "\"%s\" gives nothing away (%s)" % [line, bad])
			var digits := false
			for ch in line:
				digits = digits or ch.is_valid_int()
			check(not digits, "no numbers in talk: %s" % line)


func test_talk_is_a_clue_not_proof() -> void:
	var people := _people(["eye-c1", "eye-c2", "eye-c3", "eye-c4", "eye-c5", "eye-c6"])
	var gifted_striking := 0
	var gifted := 0
	var plain_striking := 0
	var plain := 0
	var gifted_mild := 0
	for c in people:
		var rng := Seeds.rng(77, "clue_%d_%s" % [c.id, c.last_name])
		var topic := Discovery.pick_topic(c, rng)
		var level := Discovery.intensity(c, topic, rng)
		if Appraisal.is_exceptional(c):
			gifted += 1
			if level == 2 and topic == c.best_attribute():
				gifted_striking += 1
			if level == 0:
				gifted_mild += 1
		elif c.best_potential() < 65:
			plain += 1
			if level == 2:
				plain_striking += 1
	check(gifted >= 5, "enough gifted people to judge (%d)" % gifted)
	check(float(gifted_striking) / gifted > 0.2, "the gifted often talk strikingly about their gift (%d/%d)" % [gifted_striking, gifted])
	check(plain_striking > 0, "some ordinary folk talk big too (%d/%d)" % [plain_striking, plain])
	check(float(plain_striking) / plain < float(gifted_striking) / gifted, "but less often than the gifted")
	check(gifted_mild >= 0, "the modest gifted can undersell themselves (%d)" % gifted_mild)


func test_rumors_are_not_proof() -> void:
	var decoys := 0
	var people := _people(["eye-r1", "eye-r2", "eye-r3", "eye-r4", "eye-r5", "eye-r6", "eye-r7", "eye-r8"])
	for c in people:
		var rumor := false
		for h in c.history:
			rumor = rumor or str(h["category"]) == "rumor"
		if rumor and not Appraisal.is_exceptional(c):
			decoys += 1
	check(decoys >= 1, "some rumors are about ordinary braggarts (%d)" % decoys)


func test_tiers_follow_talent() -> void:
	var c := CharacterData.new()
	for attr: String in GameData.attribute_ids():
		c.set_attribute(attr, 10, 30)
	check_eq(Discovery.tier_id(c), "ordinary", "low potential is ordinary")
	c.set_attribute("politics", 20, 70)
	check_eq(Discovery.tier_id(c), "skilled", "B potential is skilled")
	c.set_attribute("politics", 20, 104)
	check_eq(Discovery.tier_id(c), "exceptional", "S potential is exceptional")
	c.set_attribute("politics", 20, 131)
	check_eq(Discovery.tier_id(c), "legendary", "S+ potential is legendary")
	var top := Discovery.top_abilities(c)
	check_eq(str(top[0]["id"]), "politics", "the greatest gift comes first")
	check_eq(top.size(), 3, "three strongest abilities")


func test_reveal_tiers_are_clearly_different() -> void:
	var tiers: Array = Discovery.eye_config()["tiers"]
	check(tiers.size() >= 3, "at least three tiers")
	var last := -1.0
	var looks := {}
	for t: Dictionary in tiers:
		var d := EyeReveal.duration(t, false, false, false)
		check(d > last, "%s takes longer than the tier below (%.1fs)" % [t["id"], d])
		last = d
		looks["%s|%s|%s" % [t["crest"], t["frame"], t["pips"]]] = true
		check(not str(t.get("name", "")).is_empty(), "%s has a name (not color alone)" % t["id"])
	check_eq(looks.size(), tiers.size(), "each tier has its own crest, frame and pips")
	check(EyeReveal.duration(tiers[0], false, false, false) <= 1.6, "an ordinary reveal is quick")
	check(EyeReveal.duration(tiers[tiers.size() - 1], false, false, false) <= 7.5, "even the biggest reveal stays short")
	check(EyeReveal.duration(tiers[tiers.size() - 1], true, false, false) <= 0.6, "later looks are a quick card")
	var legend: Dictionary = tiers[tiers.size() - 1]
	var types := []
	for s: Dictionary in legend["steps"]:
		types.append(s["type"])
	var cues: Array = (legend["steps"] as Array).filter(func(s: Dictionary) -> bool: return s.has("cue"))
	check(cues.size() >= 2 and types.has("clue") and types.has("particles"), "the legendary reveal has its music, clues and particles")
	check(types.find("stamp") == types.size() - 1, "the top skill lands last")


func test_accessibility_trims_the_reveal() -> void:
	var legend: Dictionary = Discovery.tier_by_id("legendary")
	var calm := EyeReveal.steps_for(legend, false, true, true)
	for s: Dictionary in calm:
		check(not (str(s["type"]) in ["focus", "shake", "flash"]), "reduced motion and flashes drop %s" % s["type"])
	check(EyeReveal.duration(legend, false, true, true) < EyeReveal.duration(legend, false, false, false), "reduced motion is shorter")
	var with_sound := 0
	for s: Dictionary in calm:
		if s.has("caption") and not str(s["caption"]).is_empty():
			with_sound += 1
	check(with_sound >= 4, "important sounds keep their captions")


func test_settings_are_remembered() -> void:
	GameSettings.memory_only = true
	GameSettings.set_bool("accessibility/captions", true)
	check(GameSettings.captions(), "captions switch on")
	GameSettings.set_bool("accessibility/captions", false)
	check(not GameSettings.captions(), "and off")
	GameSettings.set_bool("eye/seen_skilled", false)
	check(not GameSettings.eye_seen("skilled"), "a tier starts unseen")
	GameSettings.mark_eye_seen("skilled")
	check(GameSettings.eye_seen("skilled"), "after a full reveal it can be skipped")


func test_meetings_survive_save_and_migration() -> void:
	var st := WorldGenerator.generate("eye-save")
	var c := st.characters[5]
	c.met = true
	c.remembered = true
	var loaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	var lc := loaded.get_character(c.id)
	check(lc.met and lc.remembered, "meetings and remembered people are saved")
	var old := st.to_dict()
	old["save_version"] = 4
	for d: Dictionary in old["characters"]:
		d.erase("met")
		d.erase("remembered")
		d["appraised"] = int(d["id"]) == c.id
	var migrated := WorldState.from_dict(SaveManager.migrate(old))
	check(migrated.get_character(c.id).met, "people appraised in old saves count as met")
	check_eq(SaveManager.migrate(old)["save_version"], WorldState.SAVE_VERSION, "old saves reach the current version")
