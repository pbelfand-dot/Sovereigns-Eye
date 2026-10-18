extends TestCase
## The title screen (scripts/ui/main_menu.gd): its menu, its panels, and
## the key art and emblem from assets/ui/menu/ when they are there.

const MENU := preload("res://scripts/ui/main_menu.gd")


func _menu() -> Control:
	var m: Control = load("res://scenes/main/main.tscn").instantiate()
	runner.add_child(m)
	return m


func _items(m: Control) -> Dictionary:
	var out := {}
	for b in (m.get("_menu") as VBoxContainer).get_children():
		if b is Button:
			out[(b as Button).text] = b
	return out


func test_the_menu_offers_every_choice() -> void:
	var m := _menu()
	var items := _items(m)
	for want: String in ["New Game", "Load Game", "Settings", "Quit"]:
		check(items.has(want), "the menu has %s" % want)
	check_eq((items["Load Game"] as Button).disabled, not SaveManager.any_save_exists(), "Load Game only when there is a save")
	check_eq(items.has("Continue"), SaveManager.any_save_exists(), "Continue only when there is a save")
	check(str(m.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)).contains("Phase 3 prototype"),
		"the footer names the current phase")
	m.free()


func test_panels_take_the_menus_place() -> void:
	var m := _menu()
	var header: Array = m.get("_header")
	check_eq(header.size(), 2, "the emblem and the line under the title can step aside")
	m.call("_show_sound")
	check(not (m.get("_menu") as Control).visible and (m.get("_sound_panel") as Control).visible, "Settings replaces the menu")
	check(header.all(func(c: Control) -> bool: return not c.visible), "the header steps aside for a panel")
	m.call("_show_menu")
	check((m.get("_menu") as Control).visible and not (m.get("_sound_panel") as Control).visible, "Back brings the menu back")
	check(header.all(func(c: Control) -> bool: return c.visible), "and the header with it")
	m.call("_show_new_game")
	check((m.get("_new_game_panel") as Control).visible, "New Game opens its panel")
	m.free()


func test_key_art_and_emblem_when_present() -> void:
	var m := _menu()
	var bg: TextureRect = m.get("_bg")
	if ResourceLoader.exists(MENU.KEY_ART):
		check(not (bg.texture is GradientTexture2D), "the key art fills the screen")
		check_eq(bg.texture.get_size(), Vector2(2560, 1440), "the key art is 2560 x 1440")
		var emblem := load(MENU.EMBLEM) as Texture2D
		check(emblem != null and emblem.get_size() == Vector2(512, 512) and emblem.get_image().detect_alpha() != Image.ALPHA_NONE,
			"the emblem is 512 px square on a clear background")
	else:
		check(bg.texture is GradientTexture2D, "without key art, a warm gradient")
	m.free()


func test_the_key_art_covers_any_screen_round_its_focus() -> void:
	var art := Vector2(2560, 1440)
	for screen: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1080), Vector2(1024, 768), Vector2(720, 1280), Vector2(1080, 2400)]:
		var r: Rect2 = MENU.cover_rect(screen, art, MENU.ART_FOCUS)
		check(r.encloses(Rect2(Vector2.ZERO, screen)), "%s: covered edge to edge (%s)" % [screen, r])
		check(is_equal_approx(r.size.x / r.size.y, art.x / art.y), "%s: never stretched" % screen)
		# What the menu shows of the art: its focus (the chapel and the heir)
		# whenever the art is wider than the screen can show.
		var focus := r.position + r.size * MENU.ART_FOCUS
		check(Rect2(Vector2.ZERO, screen).grow(1.0).has_point(focus), "%s: the chapel and the heir in view" % screen)
	var wide: Rect2 = MENU.cover_rect(Vector2(1920, 1080), art, MENU.ART_FOCUS)
	check(wide.position.is_zero_approx(), "a 16:9 screen shows the whole picture")
