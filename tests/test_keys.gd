extends TestCase
## The player's own keys (InputSetup, ControlsSettings): a new key swaps
## with whatever had it where it works, the choice is kept between sessions
## and can be undone, and every prompt and help line names the keys in use.

const TEST_PATH := "user://test_keys.cfg"


func _fresh() -> void:
	GameSettings.memory_only = true
	GameSettings.reset_cache()
	InputSetup.reset_keys()


func _done() -> void:
	InputSetup.reset_keys()
	GameSettings.reset_cache()


func _fires(action: String, keycode: int) -> bool:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	ev.pressed = true
	return InputMap.event_is_action(ev, action, true)


func test_every_key_has_a_place_and_none_clash() -> void:
	_fresh()
	var listed := {}
	for r: Array in InputSetup.rebindable():
		check(InputSetup.BINDINGS.has(r[1]), "%s is a real action" % r[1])
		check(not listed.has(r[1]), "%s is listed once" % r[1])
		listed[r[1]] = r[0]
	for action: String in InputSetup.BINDINGS:
		if not action in ["menu", "debug_reveal_all"]:
			check(listed.has(action), "%s can be changed" % action)
	check(not listed.has("menu"), "Esc stays Esc")
	# Out of the box, nothing that works in the same place shares a key.
	var actions := listed.keys()
	for i in actions.size():
		for j in range(i + 1, actions.size()):
			var a: String = actions[i]
			var b: String = actions[j]
			if InputSetup._clash(a, b):
				for k in InputSetup.keys(a):
					check(not k in InputSetup.keys(b), "%s and %s don't share %s" % [a, b, InputSetup.key_label(k)])
	_done()


func test_a_new_key_swaps_with_whatever_had_it() -> void:
	_fresh()
	var r := InputSetup.rebind("sovereign_eye", KEY_G)
	check(r["ok"] and str(r["swapped"]).is_empty(), "G was free")
	check_eq(InputSetup.keys("sovereign_eye"), [KEY_G] as Array[int], "the Eye is on G")
	check(_fires("sovereign_eye", KEY_G) and not _fires("sovereign_eye", KEY_Q), "G opens the Eye now, Q doesn't")
	check(_fires("cam_rotate_left", KEY_Q), "Q still turns the map table")
	# Talk takes G: the Eye gets talk's old key.
	r = InputSetup.rebind("interact", KEY_G)
	check_eq(str(r["swapped"]), "sovereign_eye", "the two swap")
	check_eq(InputSetup.keys("interact"), [KEY_G] as Array[int], "talk is on G")
	check_eq(InputSetup.keys("sovereign_eye"), [KEY_E] as Array[int], "and the Eye on E")
	# On foot and on the map table a key may mean different things.
	r = InputSetup.rebind("run", KEY_T)
	check(r["ok"] and str(r["swapped"]).is_empty(), "running on T doesn't disturb turning a building on the map")
	check(_fires("turn_building", KEY_T) and _fires("run", KEY_T), "T does both, each in its place")
	# "Anywhere" keys swap with each other...
	r = InputSetup.rebind("toggle_court", KEY_L)
	check_eq(str(r["swapped"]), "toggle_ledger", "court and ledger swap")
	check_eq(InputSetup.keys("toggle_ledger"), [KEY_K] as Array[int], "the ledger is on K")
	# ...and clash with keys on foot and on the map. Build can't take the
	# map's old E, which is the Eye's on foot: it's left without a key.
	r = InputSetup.rebind("cam_rotate_right", KEY_B)
	check(str(r["swapped"]) == "toggle_build" and r["unbound"], "Build gives up B and has no key")
	check(InputSetup.keys("toggle_build").is_empty(), "rather than share E with the Eye")
	check(_fires("sovereign_eye", KEY_E) and not _fires("toggle_build", KEY_E), "E is only the Eye's on foot")
	InputSetup.rebind("toggle_build", KEY_Z)
	check_eq(InputSetup.keys("toggle_build"), [KEY_Z] as Array[int], "and can be given another")
	# Only the first key changes: the arrows still pan.
	InputSetup.rebind("cam_forward", KEY_I)
	check_eq(InputSetup.keys("cam_forward"), [KEY_I, KEY_UP] as Array[int], "I pans forward, and so does Up")
	r = InputSetup.rebind("cam_rotate_left", KEY_UP)
	check(str(r["swapped"]).is_empty(), "taking a second key from something isn't a swap")
	check_eq(InputSetup.keys("cam_forward"), [KEY_I] as Array[int], "it just lets go of it")
	# Some keys aren't for the taking.
	check(not InputSetup.rebind("run", KEY_ESCAPE)["ok"], "Esc is kept for menus")
	check(not InputSetup.rebind("menu", KEY_G)["ok"], "and the menu stays on Esc")
	check(InputSetup.customized(), "the keys are the player's own now")
	InputSetup.reset_keys()
	check(not InputSetup.customized(), "until they're reset")
	for action: String in InputSetup.BINDINGS:
		var defaults: Array[int] = []
		defaults.assign(InputSetup.BINDINGS[action])
		check_eq(InputSetup.keys(action), defaults, "%s is back as it was" % action)
	check(_fires("sovereign_eye", KEY_Q), "Q opens the Eye again")
	_done()


func test_keys_are_kept_between_sessions() -> void:
	GameSettings.memory_only = false
	GameSettings.path = TEST_PATH
	GameSettings.reset_cache()
	InputSetup.reset_keys()
	InputSetup.rebind("interact", KEY_Q)
	InputSetup.rebind("toggle_pause", KEY_P)
	# A new session reads them back.
	GameSettings.reset_cache()
	InputSetup.register()
	check_eq(InputSetup.keys("interact"), [KEY_Q] as Array[int], "talk is still on Q")
	check_eq(InputSetup.keys("sovereign_eye"), [KEY_E] as Array[int], "the swap was kept too")
	check(_fires("toggle_pause", KEY_P), "P pauses after a restart")
	var cf := ConfigFile.new()
	check(cf.load(TEST_PATH) == OK and cf.has_section_key("keys", "interact"), "written to the settings file")
	check(not cf.has_section_key("keys", "run"), "only the changed keys are written")
	InputSetup.reset_keys()
	cf = ConfigFile.new()
	cf.load(TEST_PATH)
	check(not cf.has_section("keys") or cf.get_section_keys("keys").is_empty(), "a reset clears them from the file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameSettings.path = "user://settings.cfg"
	_fresh()
	_done()


func test_words_for_the_keys() -> void:
	_fresh()
	check_eq(InputSetup.move_text(), "WASD", "walking: WASD")
	check_eq(InputSetup.look_text(), "arrows", "the camera: arrows")
	check_eq(InputSetup.keys_text("toggle_overview"), "Tab or M", "the map table: Tab or M")
	check_eq(InputSetup.fill("Press {key:interact} to talk, {keys:toggle_overview} for the map."), "Press E to talk, Tab or M for the map.", "filled in")
	InputSetup.rebind("move_forward", KEY_I)
	check_eq(InputSetup.move_text(), "IASD", "walking keys follow the player's")
	InputSetup.rebind("move_left", KEY_SHIFT)
	check_eq(InputSetup.move_text(), "I/Shift/S/D", "and stay readable when they're not letters")
	InputSetup.rebind("look_left", KEY_J)
	check(InputSetup.look_text() != "arrows", "not arrows once changed")
	check_eq(InputSetup.key_label(KEY_EQUAL), "=", "short names for symbols")
	check_eq(InputSetup.key_name("toggle_pause", true), "D-pad down", "controller names for the D-pad")
	_done()


func test_the_keys_panel() -> void:
	_fresh()
	var changed := [0]
	var count := func() -> void: changed[0] += 1
	Game.keys_changed.connect(count)
	var panel := ControlsSettings.new()
	runner.add_child(panel)
	await frames(2)
	var row: Button = panel.find_child("sovereign_eye", true, false)
	check(row != null and row.text == "Q", "the Eye's row shows Q")
	var pan: Node = panel.find_child("cam_forward", true, false)
	check(pan != null and (pan.get_parent().get_child(1) as Label).text == "also Up", "keys it also answers to are shown")
	row.pressed.emit()
	check(panel.is_capturing() and row.text.begins_with("Press"), "clicking a key waits for the new one")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	runner.get_viewport().push_input(esc)
	await frames(1)
	check(not panel.is_capturing() and row.text == "Q", "Esc cancels and keeps Q")
	row.pressed.emit()
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	runner.get_viewport().push_input(back)
	await frames(1)
	check(not panel.is_capturing(), "and so does a controller's back button")
	row.pressed.emit()
	var g := InputEventKey.new()
	g.physical_keycode = KEY_E
	g.keycode = KEY_E
	g.pressed = true
	runner.get_viewport().push_input(g)
	await frames(1)
	check_eq(InputSetup.keys("sovereign_eye"), [KEY_E] as Array[int], "pressing E gives the Eye E")
	check_eq(InputSetup.keys("interact"), [KEY_Q] as Array[int], "and talk swaps to Q")
	check(row.text == "E" and (panel.find_child("interact", true, false) as Button).text == "Q", "both rows show it")
	check(panel._note.text.contains("Talk") and panel._note.text.contains("Q"), "and the panel says what moved: %s" % panel._note.text)
	check(changed[0] >= 1, "the game is told the keys changed")
	panel.reset()
	check(row.text == "Q" and InputSetup.keys("interact") == ([KEY_E] as Array[int]), "Reset puts every key back")
	Game.keys_changed.disconnect(count)
	panel.queue_free()
	_done()


func test_the_game_names_the_players_keys() -> void:
	_fresh()
	Game.state = WorldGenerator.generate("keys-live")
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var help: Label = world.ui._help.get_child(0)
	check(help.text.contains("WASD") and help.text.contains("Space - pause") and help.text.contains("Q / (Y)"), "the help names the keys")
	InputSetup.rebind("toggle_pause", KEY_P)
	InputSetup.rebind("sovereign_eye", KEY_G)
	Game.keys_changed.emit()
	check(help.text.contains("P - pause") and help.text.contains("G / (Y)"), "and follows the player's keys: %s" % help.text.get_slice("\n", 1))
	check(not help.text.contains("Space - pause"), "the old key is gone")
	check_eq(world.key_hint("sovereign_eye"), "G", "prompts name the new key")
	world.toggle_overview()
	var c := world.state.characters[3]
	check(str(world.talk_check(c.id)["reason"]).contains("(Tab)"), "the map table's key in the reasons")
	InputSetup.rebind("toggle_overview", KEY_N)
	check(str(world.talk_check(c.id)["reason"]).contains("(N)"), "the new one once it's changed")
	Game.keys_changed.emit()
	check(world.ui._map_button.tooltip_text.contains("N or M"), "and in the map button's tip: %s" % world.ui._map_button.tooltip_text)
	world.queue_free()
	await frames(2)
	_done()
