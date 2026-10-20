extends TestCase
## Villagers' remarks as the heir walks past (Barks, data/barks.json): what
## they say fits them and is true, never names a rank or a number, and the
## village doesn't talk over itself.

const ATTRS := ["leadership", "combat", "intelligence", "politics", "administration", "ambition"]
const PLACEHOLDERS := ["{lord}", "{title}", "{site}", "{charter}"]


## Every line in barks.json (keys starting "_" are notes).
func _lines(v: Variant, out: Array[String]) -> Array[String]:
	if v is String:
		out.append(v)
	elif v is Array:
		for x: Variant in v:
			_lines(x, out)
	elif v is Dictionary:
		for k: String in v:
			if not k.begins_with("_") or k == "_any":
				_lines(v[k], out)
	return out


## The words that would give a gift away: every rank and every reveal tier.
func _giveaway() -> RegEx:
	var words: Array[String] = ["rank", "potential", "talent"]
	for r: Dictionary in GameData.load_file("ranks")["ranks"]:
		words.append(str(r["title"]).to_lower())
	for t: Dictionary in Discovery.eye_config()["tiers"]:
		words.append(str(t.get("name", t["id"])).to_lower())
	return RegEx.create_from_string("(?i)\\b(%s)\\b|[0-9]" % "|".join(words))


func _adult(st: WorldState, skip: Array = []) -> CharacterData:
	for c in st.characters:
		if c.age >= 20 and not st.is_player(c) and not CourtSystem.is_kin(st, c) and not c.retainer and not skip.has(c):
			return c
	return null


func test_no_remark_names_a_rank_or_a_number() -> void:
	var giveaway := _giveaway()
	var cfg := Barks.config()
	var lines: Array[String] = []
	for key: String in ["greet", "work", "leisure", "play", "home", "time", "season", "worry", "happy", "gift", "child_gift", "village", "eyed", "family"]:
		check(cfg.has(key), "barks.json has %s lines" % key)
		_lines(cfg.get(key), lines)
	check(lines.size() > 150, "plenty to say (%d lines)" % lines.size())
	for line in lines:
		var m := giveaway.search(line)
		check(m == null, "\"%s\" gives nothing away%s" % [line, (" (%s)" % m.get_string()) if m else ""])
		var bare := line
		for p: String in PLACEHOLDERS:
			bare = bare.replace(p, "")
		check(not bare.contains("{") and not bare.contains("}"), "\"%s\" only uses known blanks" % line)
	# Every gift has a clue at every strength, and one for children.
	for attr: String in ATTRS:
		check_eq((cfg["gift"][attr] as Array).size(), 3, "%s: mild, keen and striking clues" % attr)
		check(not (cfg["child_gift"][attr] as Array).is_empty(), "%s: a child's clue" % attr)
	for occ: String in GameData.load_file("occupations")["occupations"]:
		if not occ in ["child", "elder", "general", "king", "queen", "raider"]:
			check(cfg["work"].has(occ), "a %s has something to say at work" % occ)
	# And what villagers actually say, filled in.
	var st := WorldGenerator.generate("barks-words")
	var r := Seeds.rng(1, "barks-test")
	var said := 0
	for c in st.characters:
		if st.is_player(c):
			continue
		for i in 4:
			var text := Barks.line_for(st, c, r)
			said += int(not text.is_empty())
			check(giveaway.search(text) == null and not text.contains("{"), "%s says \"%s\"" % [c.first_name, text])
			check(text.substr(0, 1) == text.substr(0, 1).to_upper(), "\"%s\" starts with a capital" % text)
	check(said > st.characters.size() * 3, "everyone has something to say (%d)" % said)


func test_what_they_say_fits_them() -> void:
	var st := WorldGenerator.generate("barks-fit")
	var cfg := Barks.config()
	var r := Seeds.rng(2, "barks-test")
	var smith := _adult(st)
	smith.occupation_id = "blacksmith"
	smith.activity = "work"
	smith.stress = 10.0
	smith.happiness = 60.0
	smith.player_opinion = 0.0
	smith.appraised = false
	# Nothing to trouble them: a friend, no restless ambition, no crowded home.
	smith.add_relationship(_adult(st, [smith]).id, "friend", 50)
	smith.set_attribute("ambition", 10, 20)
	smith.home_building_id = -1
	TerritorySystem.add(st, "food", 500.0)
	var pools := Barks.pools_for(st, smith, r)
	check_eq(pools.get("work"), cfg["work"]["blacksmith"], "a smith at the forge talks of the forge")
	check_eq(pools.get("greet"), cfg["greet"]["civil"], "a stranger is civil")
	check(not pools.has("worry"), "no worries when there's none to have")
	check(not pools.has("eyed"), "nothing about the Eye before it's been used on them")
	var miller: Array = cfg["work"]["miller"]
	for i in 200:
		var text := Barks.line_for(st, smith, r)
		check(not miller.has(text), "a smith never talks like the miller (%s)" % text)
	smith.activity = "leisure"
	check_eq(Barks.pools_for(st, smith, r).get("work"), cfg["leisure"], "off work, they talk of other things")
	# What they think of the heir.
	smith.player_opinion = 80.0
	check_eq(Barks.pools_for(st, smith, r)["greet"], cfg["greet"]["fond"], "a friend is glad to see you")
	smith.player_opinion = -60.0
	check_eq(Barks.pools_for(st, smith, r)["greet"], cfg["greet"]["sour"], "someone who dislikes you lets it show")
	smith.retainer = true
	check_eq(Barks.pools_for(st, smith, r)["greet"], cfg["greet"]["sworn"], "a retainer speaks as one sworn")
	smith.retainer = false
	smith.appraised = true
	check(Barks.pools_for(st, smith, r).has("eyed"), "once looked at with the Eye, they may say so")
	# Worries are true ones.
	smith.stress = 85.0
	check(Barks.worries_of(st, smith).has("overworked"), "the overworked say so")
	smith.stress = 10.0
	check(not Barks.worries_of(st, smith).has("overworked"), "and the rested don't")
	st.territory.stock["food"] = 0.0
	check_eq(Barks.worries_of(st, smith)[0], "hungry", "when the stores are bare, hunger comes first")
	check_eq(Barks.pools_for(st, smith, r).get("worry"), cfg["worry"]["hungry"], "and that's what they grumble about")
	TerritorySystem.add(st, "food", float(TerritorySystem.consumption(st)["food"]))
	check_eq(Barks.worries_of(st, smith)[0], "lean", "a day's food left: the granary's thin")
	# Children talk like children.
	var child: CharacterData = null
	for c in st.characters:
		if c.age < 10 and not st.is_player(c):
			child = c
			break
	check(child != null, "found a child")
	if child:
		child.activity = "play"
		child.appraised = true
		var kid := Barks.pools_for(st, child, r)
		check_eq(kid["greet"], cfg["greet"]["child"], "children greet like children")
		check_eq(kid.get("work"), cfg["play"], "and talk of their games")
		for key: String in ["worry", "village", "eyed", "happy"]:
			check(not kid.has(key), "a child doesn't talk of %s" % key)
		var clue: Array = kid.get("gift", [])
		var childish := false
		for attr: String in ATTRS:
			childish = childish or clue == cfg["child_gift"][attr]
		check(childish, "a child's gift shows in a child's way")


func test_a_great_gift_comes_up_most() -> void:
	var st := WorldGenerator.generate("barks-gift")
	var cfg := Barks.config()
	var c := _adult(st)
	c.traits = [] as Array[String]
	for attr: String in ATTRS:
		c.set_attribute(attr, 10, 18)
	c.set_attribute("intelligence", 40, 150)
	var r := Seeds.rng(3, "barks-test")
	var on_it := 0
	var striking := 0
	var n := 300
	for i in n:
		var clue: Array = Barks.pools_for(st, c, r).get("gift", [])
		on_it += int((cfg["gift"]["intelligence"] as Array).has(clue))
		striking += int(clue == cfg["gift"]["intelligence"][2])
	check(on_it > n * 0.85, "their talk keeps turning to their gift (%d of %d)" % [on_it, n])
	check(striking > n * 0.8, "and it sounds striking (%d)" % striking)
	# Someone with no great gift never sounds striking.
	c.set_attribute("intelligence", 10, 18)
	for i in 200:
		var clue: Array = Barks.pools_for(st, c, r).get("gift", [])
		for attr: String in ATTRS:
			check(clue != cfg["gift"][attr][2], "nothing striking from someone ordinary")


func test_villagers_speak_once_as_you_pass() -> void:
	var st := WorldGenerator.generate("barks-pass")
	var a := _adult(st)
	var b := _adult(st, [a])
	var barks := Barks.new(st.world_seed)
	barks.cfg["chance"] = 1.0
	barks.cfg["chance_traits"] = {}
	var range_ := float(barks.cfg["range"])
	var away := float(barks.cfg["leave_range"]) + 1.0
	var gap := float(barks.cfg["gap"])
	var cooldown := float(barks.cfg["cooldown"])
	check(not barks.passing(a, away, 0.0), "too far to be remarked on")
	check(barks.passing(a, range_ - 1.0, 1.0), "coming near, they speak up")
	check(not barks.remark(st, a, 1.0).is_empty(), "and say something")
	check(not barks.passing(a, range_ - 2.0, 2.0), "standing by them, they don't keep talking")
	check(not barks.passing(b, range_ - 1.0, 1.0 + gap * 0.5), "no one talks over someone else")
	check(not barks.passing(b, range_ - 1.0, 2.0 + gap), "and that chance has passed until the heir comes by again")
	barks.passing(b, away, 3.0 + gap)
	check(barks.passing(b, range_ - 1.0, 4.0 + gap), "passing again, they speak")
	barks.remark(st, b, 4.0 + gap)
	barks.passing(a, away, 20.0 + gap)
	check(not barks.passing(a, range_ - 1.0, cooldown * 0.5), "no one speaks twice in a minute")
	barks.passing(a, away, cooldown * 0.75)
	check(barks.passing(a, range_ - 1.0, cooldown + 10.0), "but they will next time")
	# Lines don't repeat back to back.
	var last := ""
	for i in 40:
		var text := barks.remark(st, a, 100.0 + i)
		check(text != last, "a fresh line each time (%s)" % text)
		last = text
	# Some speak up more than others.
	var plain := _adult(st, [a, b])
	plain.traits = [] as Array[String]
	var chatty := CharacterData.from_dict(plain.to_dict())
	chatty.traits = ["gregarious"] as Array[String]
	var shy := CharacterData.from_dict(plain.to_dict())
	shy.traits = ["shy"] as Array[String]
	check(Barks.chance_for(chatty) > Barks.chance_for(plain) and Barks.chance_for(plain) > Barks.chance_for(shy),
		"the gregarious speak up more than most, the shy less")
	check(Barks.duration("A long remark about the weather and the state of the roads.") > Barks.duration("Hmph."), "longer lines stay up longer")
	check(Barks.duration("Hmph.") >= float(Barks.config()["duration"]["min"]), "but every line stays long enough to read")


func _boot(seed_text: String) -> VillageWorld:
	Game.state = WorldGenerator.generate(seed_text)
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	return world


## Somewhere open near the square, with room around it.
func _open_spot(st: WorldState) -> Vector3:
	for r in range(8, 40, 2):
		for k in 12:
			var p := st.layout.square_center + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * r
			if not WorldGeometry.inside_building(st, p, 10.0) and WorldGeometry.resolve(st, p, 0.6) == p:
				return p
	return Vector3.INF


func test_remarks_in_the_live_world() -> void:
	GameSettings.memory_only = true
	GameSettings.set_bool("gameplay/remarks", true)
	var world: VillageWorld = await _boot("barks-live")
	var st := world.state
	var heir := world.player_npc()
	var spot := _open_spot(st)
	var target: NPC = null
	for npc: NPC in world.npcs.values():
		var c := npc.character
		if npc != heir and c.age >= 18 and not CourtSystem.is_kin(st, c) and not c.retainer:
			target = npc
			break
	check(heir != null and target != null and spot != Vector3.INF, "found the heir, a villager and somewhere open")
	if heir == null or target == null or spot == Vector3.INF:
		world.queue_free()
		return
	target.brain.set_errand({"type": "hold", "face": spot + Vector3(0, 0, 1)})
	target.brain.update(0.0)
	target.teleport(spot)
	target.set_inside(false)
	# Only the people in the test speak up (a trait no one else has).
	var other: NPC = null
	for npc: NPC in world.npcs.values():
		if npc != heir and npc != target and npc.visible and npc.character.age >= 18:
			other = npc
			break
	target.character.traits = ["barks_test"] as Array[String]
	if other:
		other.character.traits = ["barks_test"] as Array[String]
	world.hush_remarks()
	world.set_speed(0)
	world._process(0.05)
	world.barks = Barks.new(st.world_seed)
	world.barks.cfg["chance"] = 1.0e-12
	world.barks.cfg["chance_traits"] = {"barks_test": 1.0e12}
	world.barks.cfg["gap"] = 0.0
	world.barks.cfg["cooldown"] = 0.0
	var walk_by := func() -> void:
		heir.teleport(spot + Vector3(14, 0, 0))
		for i in 4:
			world._process(0.1)
		heir.teleport(spot + Vector3(2.5, 0, 0))
		for i in 8:
			world._process(0.1)
	walk_by.call()
	check(target.is_speaking(), "walking past, they say something")
	check(not target.speech().is_empty() and target.speech().begins_with("“"), "in quotes over their head: %s" % target.speech())
	check(target._speech.visible, "where it can be seen")
	world._process(0.5)
	check(target._speech.modulate.a > 0.9, "it fades in")
	# One voice at a time: someone else close by waits their turn.
	check(other != null, "someone else to stand by")
	if other:
		other.brain.set_errand({"type": "hold", "face": spot})
		other.brain.update(0.0)
		other.teleport(spot + Vector3(2.5, 0, 1.5))
		for i in 6:
			world._process(0.1)
		check(not other.is_speaking(), "no one talks over someone still speaking")
		other.teleport(spot + Vector3(30, 0, 30))
		world._process(0.1)
	world.try_talk(target.character.id)
	check(not target.is_speaking(), "talking to them, the remark gives way to the conversation")
	world.end_conversation()
	target.brain.set_errand({"type": "hold", "face": spot + Vector3(0, 0, 1)})
	target.brain.update(0.0)
	target.teleport(spot)
	# Paused, nobody speaks.
	world.paused = true
	walk_by.call()
	check(not target.is_speaking(), "with time stopped, the village is silent")
	world.paused = false
	# Switched off in the settings.
	GameSettings.set_bool("gameplay/remarks", false)
	walk_by.call()
	check(not target.is_speaking(), "with remarks switched off, they say nothing")
	GameSettings.set_bool("gameplay/remarks", true)
	walk_by.call()
	check(target.is_speaking(), "and switched back on, they speak again")
	# A remark lasts its time, then goes.
	for i in 70:
		world._process(0.1)
	check(not target.is_speaking() and not target._speech.visible, "after a few seconds it's gone")
	if other:
		other.teleport(spot + Vector3(2.5, 0, 1.5))
		for i in 6:
			world._process(0.1)
		check(other.is_speaking(), "and then the next may have their say")
	world.queue_free()
	await frames(2)
