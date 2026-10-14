extends TestCase
## Sound (data/audio.json): every configured file exists, buses and volume
## settings work, music follows its contexts, ambience zones fade by place,
## zoom and hour, and button clicks are hooked up.


func _audio() -> Node:
	return runner.get_tree().root.get_node("Audio")


func test_configured_sounds_exist() -> void:
	var cfg := GameData.load_file("audio")
	for family: String in cfg.get("families", {}):
		check(not AudioDirector.family_files(family).is_empty(), "family %s has files" % family)
	for event: String in cfg.get("events", {}):
		var family := str(cfg["events"][event].get("family", ""))
		check(cfg["families"].has(family), "event %s uses a known family" % event)
		check(str(cfg["events"][event].get("bus", "")) in AudioDirector.BUSES, "event %s goes to a known bus" % event)
	var music: Dictionary = cfg.get("music", {})
	for context: String in music.get("contexts", {}):
		for track: String in music["contexts"][context]:
			check(ResourceLoader.exists(str(music["root"]) + track + ".ogg"), "music %s exists" % track)
	var amb: Dictionary = cfg.get("ambience", {})
	for zone: String in amb.get("zones", {}):
		for layer: String in amb["zones"][zone].get("layers", {}):
			check(ResourceLoader.exists(str(amb["root"]) + layer + ".ogg"), "ambience %s exists" % layer)
	var occupations: Dictionary = GameData.occupations()
	for job: String in cfg.get("foley", {}).get("work", {}):
		check(occupations.has(job), "foley job %s is a real occupation" % job)
		check(cfg["events"].has(str(cfg["foley"]["work"][job])), "foley job %s plays a known event" % job)


func test_buses_and_volume_settings() -> void:
	var audio := _audio()
	check(audio != null, "Audio autoload is running")
	for bus: String in AudioDirector.BUSES:
		check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	var old_path: String = audio.settings_path
	var old_level: float = audio.level("Music")
	audio.settings_path = "user://test_settings.cfg"
	audio.set_level("Music", 0.35)
	audio.set_level("Music", 0.9, false)
	audio.load_settings()
	check(absf(audio.level("Music") - 0.35) < 0.001, "volume levels are saved and reloaded")
	audio.set_level("UI", 0.0, false)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "a zero slider mutes its bus")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	audio.settings_path = old_path
	audio.load_settings()
	audio.set_level("Music", old_level, false)


func test_music_follows_context() -> void:
	var audio := _audio()
	audio.set_music("menu")
	check_eq(audio.music_track, "old_tower_inn_loop", "the menu plays the inn theme")
	audio.set_music("day")
	check(audio.music_tracks("day").has(audio.music_track), "daytime plays a village track (%s)" % audio.music_track)
	check_eq(Soundscape.music_context(12.0, false), "day", "noon is day music")
	check_eq(Soundscape.music_context(23.0, false), "night", "late evening is night music")
	check_eq(Soundscape.music_context(12.0, true), "court", "the Court panel plays court music")
	audio.set_music("")


func test_ambience_zones_fade_by_place_zoom_and_hour() -> void:
	var market := {"points": [Vector3.ZERO], "radius": 30.0, "hours": [7.0, 19.0]}
	check(Soundscape.zone_weight(market, Vector3(3, 0, 2), 30.0, 12.0) > 0.95, "the market is loud on the square at noon")
	check(Soundscape.zone_weight(market, Vector3(80, 0, 0), 30.0, 12.0) < 0.01, "the market is silent across the village")
	check(Soundscape.zone_weight(market, Vector3.ZERO, 30.0, 23.0) < 0.01, "the market is silent at night")
	check(Soundscape.zone_weight(market, Vector3.ZERO, 200.0, 12.0) < 0.01, "zooming far out silences ambience")
	var village := {"everywhere": true, "day_only": true}
	check(Soundscape.zone_weight(village, Vector3(70, 0, 40), 30.0, 10.0) > 0.95, "the village bed plays anywhere by day")
	check(Soundscape.zone_weight(village, Vector3.ZERO, 30.0, 2.0) < 0.01, "the village bed fades at night")


func test_buttons_click() -> void:
	var b := Button.new()
	runner.add_child(b)
	check(b.has_meta("_audio"), "new buttons are hooked to the click sound")
	b.pressed.emit()
	var tick := Button.new()
	tick.set_meta("sfx", "ui_tick")
	runner.add_child(tick)
	tick.pressed.emit()
	check(_audio().event_stream("ui_click") != null, "click sound loads")
	b.queue_free()
	tick.queue_free()
