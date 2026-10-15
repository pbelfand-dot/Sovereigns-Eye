extends Node
## Plays the Sovereign's Eye reveals for review, one person per tier, in a
## real village. Record it with Godot's movie maker:
##
##   godot --path . --write-movie out.avi --fixed-fps 30 res://tools/eye_demo.tscn -- <seed>
##
## Shows: talking to someone (the heir walks up, the talk, "Use the
## Sovereign's Eye"), then Ordinary, Skilled, Exceptional and Legendary
## reveals in full, a quick second look, and the Legendary reveal again with
## reduced motion and reduced flashes. Captions are on.

var seed_text := "9"
var _title: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_text = args[0]
	GameSettings.memory_only = true
	GameSettings.set_bool("accessibility/captions", true)
	GameSettings.set_bool("accessibility/reduced_motion", false)
	GameSettings.set_bool("accessibility/reduce_flashes", false)
	for t in ["ordinary", "skilled", "exceptional", "legendary"]:
		GameSettings.set_bool("eye/seen_" + t, false)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _say(text: String) -> void:
	_title.text = text


func _pick(st: WorldState) -> Dictionary:
	var out := {}
	for tier in ["ordinary", "skilled", "exceptional", "legendary"]:
		var best: CharacterData = null
		for c in st.characters:
			if st.is_player(c) or c.family_id == st.ruling_family_id or c.age < 14 or Discovery.tier_id(c) != tier:
				continue
			if best == null or (c.best_potential() > best.best_potential()) == (tier != "ordinary"):
				best = c
		if best:
			out[tier] = best
	return out


func _run() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.5 * 60.0
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_title = UITheme.label("", 20, UITheme.ACCENT, true)
	_title.position = Vector2(18, 58)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_title)
	await _wait(0.3)
	world.ui._help.visible = false
	world.set_speed(1)
	await _wait(2.0)
	world.set_speed(0)
	world.paused = true
	var st := world.state
	var people := _pick(st)
	var heir := world.player_npc()
	var order := ["ordinary", "skilled", "exceptional", "legendary"]
	for i in order.size():
		var tier: String = order[i]
		if not people.has(tier):
			continue
		var c: CharacterData = people[tier]
		var npc := world.npc_of(c.id)
		if npc and not npc.visible:
			npc.brain._leave_building()
		var at := npc.global_position if npc else Vector3.ZERO
		world.camera_rig.set_yaw(0.4 + i * 0.3, true)
		world.camera_rig.look_at_point(at, 20.0, true)
		_say("%d / 4   %s   -   %s, %s" % [i + 1, Discovery.tier_by_id(tier)["name"], c.full_name(), c.occupation_name().to_lower()])
		if i == 0 and heir:
			# The talk-first flow: the heir walks up and they speak.
			heir.teleport(at + Vector3(6, 0, 3))
			heir.set_inside(false)
			heir.character.inside_building_id = -1
			world.paused = false
			world.set_speed(0)
			world.request_talk(c.id)
			for k in 200:
				await _wait(0.05)
				if world.talking_to == c.id:
					break
			world.paused = true
			await _wait(4.0)
		else:
			c.met = true
			await _wait(1.0)
		world.use_eye(c.id)
		while world.is_revealing() and not world._reveal.done:
			await get_tree().process_frame
		await _wait(2.6)
		if world.is_revealing():
			world._reveal._finish("close")
		await _wait(0.8)
	if people.has("legendary"):
		var legend: CharacterData = people["legendary"]
		_say("A second look (quick card)")
		world.use_eye(legend.id)
		await _wait(1.8)
		if world.is_revealing():
			world._reveal._finish("close")
		await _wait(0.6)
		_say("Legendary again with Reduce motion + Reduce flashes")
		GameSettings.set_bool("accessibility/reduced_motion", true)
		GameSettings.set_bool("accessibility/reduce_flashes", true)
		legend.appraised = false
		world.use_eye(legend.id)
		while world.is_revealing() and not world._reveal.done:
			await get_tree().process_frame
		await _wait(2.4)
		if world.is_revealing():
			world._reveal._finish("close")
		await _wait(0.5)
	get_tree().quit()
