extends Node
## A short scripted play-through of the core loop, for review videos:
## walk as the heir, look at someone with the Sovereign's Eye (no talk
## needed), walk up and talk, ask what they want, make an offer, get a
## counteroffer, agree, then the map table and back.
##
## Record it with Movie Maker (needs a display; xvfb works):
##   godot --path . --resolution 1280x720 --write-movie out.avi --fixed-fps 30 \
##     res://tools/gameplay_demo.tscn -- <seed>

var world: VillageWorld
var target: NPC
var _keys: Label
var _note: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if not args.is_empty() else "9"
	GameSettings.memory_only = true
	for t: String in ["ordinary", "skilled", "exceptional", "legendary"]:
		GameSettings.set_bool("eye/seen_" + t, false)
	Game.state = WorldGenerator.generate(seed_text)
	Game.state.minutes += 3.0 * 60.0  # late morning: people about
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_keys = _caption(layer, 100.0, 24)
	_note = _caption(layer, 134.0, 17)
	_run.call_deferred()


## Captions on the right, clear of the game's own notices on the left.
func _caption(layer: CanvasLayer, top: float, size: int) -> Label:
	var l := UITheme.label("", size, UITheme.ACCENT, size > 18)
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.offset_left = -620.0
	l.offset_right = -18.0
	l.offset_top = top
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.95))
	layer.add_child(l)
	return l


func _say(keys: String, note: String = "") -> void:
	_keys.text = keys
	_note.text = note


## DEMO_SHOTS=<dir> saves a still at each beat (for checking without a movie).
func _shot(file_name: String) -> void:
	var dir := OS.get_environment("DEMO_SHOTS")
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(file_name))


func _wait(seconds: float) -> void:
	var frames := maxi(1, roundi(seconds * 30.0))
	for i in frames:
		await get_tree().process_frame


## Someone worth finding: real talent, and an offer story to tell (their
## first answer to a fair wage is a counteroffer that you can agree to).
func _pick_target() -> NPC:
	var st := world.state
	var best: NPC = null
	var best_p := -1
	for npc: NPC in world.npcs.values():
		var c := npc.character
		if npc == world.player_npc() or not Recruitment.eligible(st, c)["ok"] or c.age < 18:
			continue
		var offer := {"wage": Recruitment.wage_need(c), "position": "household"}
		var ev := Recruitment.evaluate(st, c, offer)
		if ev["accept"] or Recruitment.counteroffer(st, c, offer).is_empty():
			continue
		if c.best_potential() > best_p:
			best_p = c.best_potential()
			best = npc
	return best


## Open ground near the square, away from buildings.
func _open_spot(clear: float) -> Vector3:
	var st := world.state
	for r in range(6, 40, 2):
		for k in 16:
			var p := st.layout.square_center + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * r
			if not WorldGeometry.inside_building(st, p, clear) and WorldGeometry.resolve(st, p, 0.8) == p:
				return p
	return st.layout.square_center


func _run() -> void:
	await _wait(0.2)
	var st := world.state
	var heir := world.player_npc()
	target = _pick_target()
	if target == null or heir == null:
		push_error("gameplay_demo: no suitable person in this village")
		get_tree().quit(1)
		return
	# Set the scene: they stand at work on open ground; the heir starts
	# a stroll away, facing them.
	var spot := _open_spot(9.0)
	target.brain.set_errand({"type": "hold", "face": spot + Vector3(1, 0, 0)})
	target.brain.update(0.0)
	target.teleport(spot)
	# Start a stroll away, on open ground with room behind for the camera.
	var start := spot + Vector3(-13.0, 0, 9.0)
	var best_room := -1.0
	for i in 24:
		var away := Vector3(cos(i * TAU / 24.0), 0, sin(i * TAU / 24.0))
		var p := spot + away * 16.0
		if WorldGeometry.inside_building(st, p, 1.0) or WorldGeometry.line_blocked(st, p, spot):
			continue
		var room := 0.0
		while room < 14.0 and not WorldGeometry.inside_building(st, p, room + 1.0):
			room += 1.0
		if room > best_room:
			best_room = room
			start = p
	heir.teleport(start)
	var to := spot - start
	heir.rotation.y = atan2(-to.x, -to.z)
	world.camera_rig.set_yaw(heir.rotation.y + 0.35, true)
	world.camera_rig.look_at_point(heir.global_position, 12.0, true)
	var c := target.character
	print("demo: target %s (%s), best potential %d" % [c.full_name(), c.occupation_id, c.best_potential()])

	# 1. Walking as the heir.
	_say("W  -  walk", "You are the heir, on foot. The camera follows you.")
	await _wait(1.0)
	await _shot("01_walk.png")
	world.heir_ctl.scripted_move = Vector2(0.12, 1)
	await _wait(1.6)
	_say("Mouse drag  -  turn the camera")
	for i in 30:
		world.camera_rig.orbit(Vector2(-3.0, 0))
		await _wait(1.0 / 30.0)
	world.heir_ctl.scripted_move = Vector2(0, 1)
	while Vector2(heir.global_position.x - spot.x, heir.global_position.z - spot.z).length() > 8.0:
		var d := spot - heir.global_position
		world.camera_rig.set_yaw(lerp_angle(world.camera_rig._target_yaw, atan2(-d.x, -d.z), 0.04))
		await _wait(1.0 / 30.0)
	world.heir_ctl.scripted_move = null
	_say("", "Look at someone nearby: they come into focus.")
	await _wait(1.6)
	await _shot("02_focus.png")

	# 2. The Sovereign's Eye: from where you stand, no talk needed.
	_say("Q  -  Sovereign's Eye", "Near and in sight is enough. No need to talk first.")
	await _wait(1.2)
	world.use_eye(c.id)
	_say("", "")
	await _wait(2.0)
	await _shot("03_reveal_mid.png")
	while world.is_revealing() and not world._reveal.done:
		await _wait(1.0 / 30.0)
	await _wait(2.4)
	await _shot("04_reveal_card.png")
	_say("", "Worth knowing. Walk up and talk.")
	world._reveal._finish("talk")
	await _wait(1.2)

	# 3. Walk up and talk.
	_say("W  -  walk up")
	world.heir_ctl.scripted_move = Vector2(0, 1)
	while not world.talk_check(c.id)["ok"]:
		var d2 := spot - heir.global_position
		world.camera_rig.set_yaw(lerp_angle(world.camera_rig._target_yaw, atan2(-d2.x, -d2.z), 0.05))
		await _wait(1.0 / 30.0)
	world.heir_ctl.scripted_move = null
	await _wait(0.4)
	_say("E  -  talk")
	await _wait(0.8)
	world.try_talk(c.id)
	var panel := world.ui.conversation_panel()
	await _wait(3.2)
	await _shot("05_talk.png")
	_say("Ask about their life", "Learn what they want: no numbers, their own words.")
	panel._on_ask()
	await _wait(2.6)
	panel._on_ask()
	await _wait(2.6)
	await _shot("06_asked.png")
	_say("Make an offer", "A real wage from the treasury, a real home, a real place.")
	panel._on_make()
	await _wait(1.5)
	panel.offer["wage"] = Recruitment.wage_need(c)
	panel._refresh_offer()
	await _wait(1.5)
	panel._on_propose()
	print("demo: offer %s -> counter %s" % [panel.offer, panel.counter])
	_say("", "Not quite: they say why, and what would win them over.")
	await _wait(4.5)
	await _shot("07_counter.png")
	_say("Agree to their terms")
	await _wait(0.8)
	panel._on_agree()
	print("demo: %s retainer=%s terms=%s" % [c.full_name(), c.retainer, c.terms])
	_say("", "Accepted. Wages, homes and promises are kept by the simulation.")
	await _wait(4.0)
	await _shot("08_accepted.png")
	world.end_conversation()
	_say("", "")
	await _wait(1.0)

	# 4. The map table, and back to the heir.
	_say("Tab  -  the map table", "Plan and build from above.")
	world.toggle_overview()
	await _wait(3.5)
	await _shot("09_map_table.png")
	_say("Tab  -  back on foot")
	world.toggle_overview()
	world.heir_ctl.scripted_move = Vector2(0.3, 1)
	await _wait(2.5)
	world.heir_ctl.scripted_move = null
	_say("", "")
	await _wait(0.5)
	get_tree().quit()
