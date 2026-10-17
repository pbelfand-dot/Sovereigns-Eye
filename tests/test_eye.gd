extends TestCase
## The Sovereign's Eye's polish: each tier's own music (data/eye.json cues,
## audio/stings/), its timing on one clock, the seal that cracks, the card's
## layout, the light and particles, and the world hushing while it shows.

const TIERS := ["ordinary", "skilled", "exceptional", "legendary"]


func _cues(steps: Array) -> Array:
	var out := []
	for s: Dictionary in steps:
		if s.has("cue"):
			out.append(str(s["cue"]))
	return out


## When each step starts, in seconds from the beginning (steps that run
## alongside take no time).
func _starts(steps: Array) -> Array:
	var out := []
	var t := 0.0
	for s: Dictionary in steps:
		out.append(t)
		if not str(s.get("type", "")) in ["focus", "particles", "sound"]:
			t += float(s.get("time", 0.0))
	return out


func test_every_tier_has_its_own_music() -> void:
	var landings := {}
	var audio := AudioDirector.config()
	for id: String in TIERS:
		var tier := Discovery.tier_by_id(id)
		var cues := _cues(tier["steps"])
		check(not cues.is_empty(), "%s has a cue of its own" % id)
		for path: String in cues:
			check(path.begins_with("res://audio/stings/") and ResourceLoader.exists(path), "%s: %s is there" % [id, path])
			var stream := load(path) as AudioStreamOggVorbis
			check(stream != null and not stream.loop, "%s: %s plays once, not in a loop" % [id, path])
		landings[cues[cues.size() - 1]] = true
		for s: Dictionary in tier["steps"]:
			for ev: String in [str(s.get("sound", ""))] + Array(s.get("rows", [])):
				if not ev.is_empty():
					check(audio["events"].has(ev), "%s: the sound %s is configured" % [id, ev])
	check_eq(landings.size(), TIERS.size(), "no two tiers share a landing")


func test_the_rise_peaks_as_the_clues_end_and_then_lands() -> void:
	for id: String in ["exceptional", "legendary"]:
		var steps: Array = Discovery.tier_by_id(id)["steps"]
		var starts := _starts(steps)
		var rise := -1
		var cut := -1
		var land := -1
		for i in steps.size():
			var s: Dictionary = steps[i]
			if str(s.get("cue", "")).ends_with("_rise.ogg"):
				rise = i
			elif s.has("cut") and rise >= 0 and cut < 0:
				cut = i
			elif s.has("cue") and cut >= 0:
				land = i
		check(rise >= 0 and cut > rise and land > cut, "%s: a rise, then a held breath, then the landing" % id)
		if land < 0:
			continue
		# The rise was made to peak exactly when the clues end (make_stings.py).
		var under := float(starts[cut]) - float(starts[rise])
		var made := {"exceptional": 1.95, "legendary": 2.55}
		check(is_equal_approx(snappedf(under, 0.01), float(made[id])), "%s: the clues take %.2f s, as the rise was made for" % [id, under])
		var stream := load(str(steps[rise]["cue"])) as AudioStream
		check(stream.get_length() > under + 0.6, "%s: the rise never runs out before it's cut" % id)
		check(str(steps[land]["type"]) == "flash" and str(steps[land + 1]["type"]) == "flip", "%s: it lands with the flash, as the card turns" % id)
		# One note for each ability as it shows.
		for s: Dictionary in steps:
			if str(s.get("type", "")) == "stats":
				check_eq((s.get("rows", []) as Array).size(), 3, "%s: a note for each of the three abilities" % id)


func test_calm_settings_keep_the_music() -> void:
	for id: String in TIERS:
		var tier := Discovery.tier_by_id(id)
		var full := _cues(EyeReveal.steps_for(tier, false, false, false))
		var calm := _cues(EyeReveal.steps_for(tier, false, true, true))
		check_eq(calm, full, "%s: reduced motion and flashes play the same music" % id)
	var legend := EyeReveal.steps_for(Discovery.tier_by_id("legendary"), false, true, true)
	var cracks := legend.filter(func(s: Dictionary) -> bool: return bool(s.get("crack", false)))
	check_eq(cracks.size(), 1, "without the shaking, the seal still cracks")


func test_the_sequence_keeps_to_one_clock() -> void:
	var reveal := EyeReveal.new()
	runner.add_child(reveal)
	reveal.set_process(false)
	# Exceptional's first beats, on long, uneven frames: each step ends
	# within a frame of its time, and the frames it ran over don't add up.
	var steps := [0.3, 0.75, 0.3, 0.6, 0.6, 0.45, 0.15, 0.15]
	var ends := []
	var run := func() -> void:
		for w: float in steps:
			await reveal._wait(w)
			ends.append(reveal._clock)
	run.call()
	var dt := 0.07
	while ends.size() < steps.size() and reveal._clock < 10.0:
		await frames(1)
		reveal._clock += dt
	check_eq(ends.size(), steps.size(), "every step ends")
	var nominal := 0.0
	for i in ends.size():
		nominal += float(steps[i])
		check(float(ends[i]) >= nominal - 1e-6 and float(ends[i]) - nominal < dt + 1e-6,
			"step %d ends at %.2f s, within a frame of %.2f s" % [i, ends[i], nominal])
	reveal.queue_free()


func test_the_card_lays_out_on_both_faces() -> void:
	# The back: the window above the seal, the ribbons on the card.
	check(RevealCard.WINDOW.end.y + 6.0 < RevealCard.SEAL_AT.y - RevealCard.SEAL_RADIUS, "the silhouette's window is clear of the seal")
	check(RevealCard.SEAL_AT.y + 128.0 < RevealCard.SIZE.y - 18.0, "the ribbons end inside the tooled border")
	var arch := RevealCard.arch(RevealCard.NICHE)
	var r := Rect2(arch[0], Vector2.ZERO)
	for p in arch:
		r = r.expand(p)
	check(r.is_equal_approx(RevealCard.NICHE), "the niche's arch fills its rectangle")
	# The front, with a long name and many traits: nothing runs off the card.
	var st := WorldGenerator.generate("eye-card")
	var c := st.characters[3]
	c.first_name = "Wynflæd Æthelgifu"
	c.traits = ["ambitious", "honest", "brave", "generous", "patient"] as Array[String]
	for id: String in TIERS:
		var card := RevealCard.new()
		card.setup(c, Discovery.tier_by_id(id), null)
		runner.add_child(card)
		card.face = "front"
		card.show_stamp(true)
		for i in card.row_count():
			card.set_row(i, 1.0)
		await frames(2)
		var bottom := card._overall.get_global_rect().end.y - card.get_global_rect().position.y
		check(bottom <= RevealCard.SIZE.y - 18.0, "%s: the card's last line is inside its frame (%.0f)" % [id, bottom])
		check(card._niche.clip_children != CanvasItem.CLIP_CHILDREN_DISABLED, "%s: the portrait is held inside its niche" % id)
		card.crack = 1.0
		card.face = "back"
		check(not card._front.visible and card._back.visible, "%s: one face at a time" % id)
		card.queue_free()


func test_light_and_particles_scale_with_the_tier() -> void:
	var last := -1
	for id: String in TIERS:
		var amount := 0
		var extras := 0
		for s: Dictionary in Discovery.tier_by_id(id)["steps"]:
			if str(s.get("type", "")) == "particles":
				amount = int(s.get("amount", 0))
				extras = int(s.get("motes", 0) > 0) + int(float(s.get("halo", 0.0)) > 0.0) + int(bool(s.get("ring", false))) \
					+ int(float(s.get("rays", 0.0)) > 0.0) + int(int(s.get("flakes", 0)) > 0)
		if id == "ordinary":
			check_eq(amount, 0, "an ordinary reveal stays quiet")
			continue
		check(amount > last and extras > 0, "%s: more sparks and light than the tier below (%d)" % [id, amount])
		last = amount
	var fx := RevealFX.new()
	runner.add_child(fx)
	var sparks := fx.sparks(100, Vector2(400, 300), RevealCard.SIZE)
	check(sparks.emission_shape == CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS and sparks.emission_points.size() > 0, "sparks fly from the card's edges")
	fx.reduced = true
	var calm := fx.sparks(100, Vector2.ZERO, RevealCard.SIZE)
	check(calm.amount < sparks.amount, "fewer sparks with reduced motion")
	calm.free()
	for kind: String in ["star", "dot", "flake"]:
		check(RevealFX.texture(kind) != null, "the %s particle has its image" % kind)
	sparks.free()
	fx.queue_free()


func test_the_world_hushes_while_the_eye_is_open() -> void:
	var audio: AudioDirector = runner.get_tree().root.get_node("Audio")
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	var before := AudioServer.get_bus_volume_db(music)
	var sfx_before := AudioServer.get_bus_volume_db(sfx)
	audio.duck(-12.0, 0.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(music), before - 12.0), "the music is lowered")
	check(is_equal_approx(AudioServer.get_bus_volume_db(sfx), sfx_before), "the Eye's own sounds are not")
	audio.duck(0.0, 0.0)
	check(is_equal_approx(AudioServer.get_bus_volume_db(music), before), "and comes back after")
