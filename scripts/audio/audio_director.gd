class_name AudioDirector
extends Node
## Autoload "Audio": music, one-shot sounds and the four buses (Music,
## Ambience, SFX, UI), all configured in data/audio.json.
##
## - set_music(context) crossfades to that context's tracks ("menu", "day",
##   "night", "court"...). One track loops; several play in random order with
##   a short silence between them.
## - play(event) plays a one-shot from a numbered family of files, picked at
##   random with slight pitch variation. event_stream() gives the same stream
##   for positional players (see Soundscape).
## - Every button clicks on its own. Set meta "sfx" on a button to play another
##   event instead, or "" for silence. Tab clicks turn a page.
## - Volume sliders are 0..1 per bus, saved in user://settings.cfg.
## - duck(db, time) lowers the music and ambience together (the Eye's
##   reveal hushes the world), duck(0.0, time) brings them back.

const BUSES := ["Music", "Ambience", "SFX", "UI"]
## The buses duck() lowers.
const DUCKED := ["Music", "Ambience"]

var settings_path := "user://settings.cfg"
var music_context := ""
var music_track := ""

var _levels: Dictionary = {}
var _streams: Dictionary = {}        # event -> AudioStreamRandomizer (or null)
var _event_players: Dictionary = {}  # event -> AudioStreamPlayer (or null)
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_tween: Tween
var _gap_left := -1.0
var _rng := RandomNumberGenerator.new()
var _duck_db := 0.0
var _duck_tween: Tween


static func config() -> Dictionary:
	return GameData.load_file("audio")


## Files of a numbered family ("click" -> click_001.ogg ...), sorted.
static func family_files(family: String) -> PackedStringArray:
	var f: Dictionary = config().get("families", {}).get(family, {})
	var dir := str(f.get("dir", ""))
	var prefix := str(f.get("prefix", ""))
	var out := PackedStringArray()
	if dir.is_empty():
		return out
	for file in ResourceLoader.list_directory(dir):
		if file.begins_with(prefix) and file.ends_with(".ogg"):
			out.append(dir + file)
	out.sort()
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	load_settings()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = "Music"
		p.volume_db = -80.0
		p.finished.connect(_on_music_finished.bind(p))
		add_child(p)
		_music.append(p)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	for p in _music:
		p.stop()
	for p: AudioStreamPlayer in _event_players.values():
		if p:
			p.stop()


func _process(delta: float) -> void:
	if _gap_left > 0.0:
		_gap_left -= delta
		if _gap_left <= 0.0:
			_play_next_track()


# --- Volume ------------------------------------------------------------------------

func level(bus: String) -> float:
	return float(_levels.get(bus, config().get("default_levels", {}).get(bus, 0.8)))


func set_level(bus: String, value: float, save := true) -> void:
	value = clampf(value, 0.0, 1.0)
	_levels[bus] = value
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		var base := float(config().get("buses", {}).get(bus, {}).get("volume_db", 0.0))
		AudioServer.set_bus_mute(idx, value <= 0.001)
		AudioServer.set_bus_volume_db(idx, base + linear_to_db(maxf(value, 0.001)) + (_duck_db if bus in DUCKED else 0.0))
	if save:
		save_settings()


## Lowers the music and ambience by `db` (negative) over `time` seconds;
## duck(0.0, time) restores them. The sliders' levels are kept as they are.
func duck(db: float, time: float) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	if time <= 0.0:
		_set_duck(db)
		return
	_duck_tween = create_tween()
	_duck_tween.tween_method(_set_duck, _duck_db, db, time)


func ducked_db() -> float:
	return _duck_db


func _set_duck(db: float) -> void:
	_duck_db = db
	for bus: String in DUCKED:
		set_level(bus, level(bus), false)


func load_settings() -> void:
	var cf := ConfigFile.new()
	var ok := cf.load(settings_path) == OK
	for bus: String in BUSES:
		var value := float(config().get("default_levels", {}).get(bus, 0.8))
		if ok:
			value = float(cf.get_value("audio", bus, value))
		set_level(bus, value, false)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(settings_path)  # keep any other sections
	for bus: String in BUSES:
		cf.set_value("audio", bus, level(bus))
	cf.save(settings_path)


func _ensure_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


# --- Music -----------------------------------------------------------------------

func music_tracks(context: String) -> Array:
	return config().get("music", {}).get("contexts", {}).get(context, [])


func set_music(context: String) -> void:
	if context == music_context:
		return
	music_context = context
	if music_tracks(context).has(music_track) and _music[_music_active].playing:
		return  # the current track already fits
	_play_next_track()


func _play_next_track() -> void:
	_gap_left = -1.0
	var cfg: Dictionary = config().get("music", {})
	var tracks := music_tracks(music_context)
	var fade := float(cfg.get("fade", 2.5))
	if tracks.is_empty():
		music_track = ""
		_crossfade(null, fade)
		return
	var choices := tracks.filter(func(t: Variant) -> bool: return str(t) != music_track) if tracks.size() > 1 else tracks
	var track := str(choices[_rng.randi() % choices.size()])
	var path := str(cfg.get("root", "")) + track + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("Audio: missing music %s" % path)
		return
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = tracks.size() == 1
	music_track = track
	_crossfade(stream, fade)


func _crossfade(stream: AudioStream, fade: float) -> void:
	if _music_tween:
		_music_tween.kill()
	var old := _music[_music_active]
	_music_tween = create_tween().set_parallel()
	if stream:
		_music_active = 1 - _music_active
		var p := _music[_music_active]
		p.stream = stream
		p.volume_db = -40.0
		p.play()
		_music_tween.tween_property(p, "volume_db", 0.0, fade)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -60.0, fade)
		_music_tween.chain().tween_callback(func() -> void:
			if old != _music[_music_active] or stream == null:
				old.stop())


func _on_music_finished(p: AudioStreamPlayer) -> void:
	if p != _music[_music_active]:
		return
	var gap: Array = config().get("music", {}).get("gap", [6.0, 16.0])
	_gap_left = _rng.randf_range(float(gap[0]), float(gap[1]))


# --- One-shots ---------------------------------------------------------------------

func event_config(event: String) -> Dictionary:
	return config().get("events", {}).get(event, {})


## Random-variation stream for an event (null if its files are missing).
func event_stream(event: String) -> AudioStream:
	if _streams.has(event):
		return _streams[event]
	var ev := event_config(event)
	var files := family_files(str(ev.get("family", "")))
	var out: AudioStreamRandomizer = null
	if not files.is_empty():
		out = AudioStreamRandomizer.new()
		out.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS if files.size() > 2 else AudioStreamRandomizer.PLAYBACK_RANDOM
		out.random_pitch = float(ev.get("pitch", 1.0))
		for i in files.size():
			out.add_stream(i, load(files[i]))
	_streams[event] = out
	return out


func play(event: String) -> void:
	if event.is_empty():
		return
	if not _event_players.has(event):
		var stream := event_stream(event)
		var p: AudioStreamPlayer = null
		if stream:
			var ev := event_config(event)
			p = AudioStreamPlayer.new()
			p.name = "Sfx_" + event
			p.stream = stream
			p.bus = str(ev.get("bus", "SFX"))
			p.volume_db = float(ev.get("volume_db", 0.0))
			p.max_polyphony = 4
			add_child(p)
		_event_players[event] = p
	var player: AudioStreamPlayer = _event_players[event]
	if player:
		player.play()


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("_audio"):
		node.set_meta("_audio", true)
		(node as BaseButton).pressed.connect(_on_button_pressed.bind(node))
		if node is OptionButton:
			(node as OptionButton).item_selected.connect(func(_i: int) -> void: play("ui_select"))
	elif node is TabBar and not node.has_meta("_audio"):
		node.set_meta("_audio", true)
		(node as TabBar).tab_clicked.connect(func(_t: int) -> void: play("tab"))


func _on_button_pressed(b: BaseButton) -> void:
	if not is_instance_valid(b):
		return
	if b.has_meta("sfx"):
		play(str(b.get_meta("sfx")))
	elif b.toggle_mode:
		play("ui_toggle")
	else:
		play("ui_click")
