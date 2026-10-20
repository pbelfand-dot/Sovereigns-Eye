class_name Soundscape
extends Node
## The village's sound, owned by VillageWorld (data/audio.json):
## - Music follows the day: "day", "night", or "court" while the Court panel
##   is open.
## - Ambience beds (market crowd, tavern, smithy, village morning) fade in
##   around their places as the camera's focus nears them and fade out as the
##   camera zooms away or outside working hours.
## - Foley: villagers near the camera's focus make footsteps (grass or stone)
##   and work sounds by job, from a small pool of positional players.

var world: VillageWorld
var _zones: Array[Dictionary] = []          # {layers, points, radius, hours, everywhere, day_only}
var _beds: Dictionary = {}                  # layer -> AudioStreamPlayer
var _bed_level: Dictionary = {}             # layer -> current linear volume
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
var _timers: Dictionary = {}                # npc id -> seconds until next sound
var _music_check := 0.0
var _rng := RandomNumberGenerator.new()


static func config() -> Dictionary:
	return GameData.load_file("audio")


func setup(owner_world: VillageWorld) -> void:
	world = owner_world
	_rng.randomize()
	var amb: Dictionary = config().get("ambience", {})
	var root := str(amb.get("root", ""))
	var layout := world.state.layout
	for zone_id: String in amb.get("zones", {}):
		var z: Dictionary = amb["zones"][zone_id]
		var points: Array[Vector3] = []
		if str(z.get("at", "")) == "square":
			points.append(layout.square_center)
		for type: String in z.get("building_types", []):
			for b in layout.buildings_of_type(type):
				points.append(b.position)
		_zones.append({"layers": z.get("layers", {}), "points": points, "radius": float(z.get("radius", 20.0)),
			"hours": z.get("hours", []), "everywhere": bool(z.get("everywhere", false)), "day_only": bool(z.get("day_only", false))})
		for layer: String in z.get("layers", {}):
			if _beds.has(layer):
				continue
			var path := root + layer + ".ogg"
			if not ResourceLoader.exists(path):
				continue
			var stream := load(path) as AudioStream
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			var p := AudioStreamPlayer.new()
			p.name = "Bed_" + layer
			p.bus = "Ambience"
			p.stream = stream
			p.volume_db = -80.0
			add_child(p)
			_beds[layer] = p
			_bed_level[layer] = 0.0
	var foley: Dictionary = config().get("foley", {})
	for i in int(foley.get("voices", 8)):
		var v := AudioStreamPlayer3D.new()
		v.name = "Voice%d" % i
		v.unit_size = float(foley.get("unit_size", 12.0))
		v.max_distance = 120.0
		add_child(v)
		_voices.append(v)


func _exit_tree() -> void:
	# Stop streams so the audio server lets go of them with the world.
	for p: AudioStreamPlayer in _beds.values():
		p.stop()
	for v in _voices:
		v.stop()


func _process(delta: float) -> void:
	if world == null or world.camera_rig == null:
		return
	var hour := Calendar.hour_f(world.state.minutes)
	var focus := world.camera_rig.position
	var distance := world.camera_rig.view_distance()
	_update_beds(delta, focus, distance, hour)
	_update_foley(delta, focus, distance)
	_music_check -= delta
	if _music_check <= 0.0:
		_music_check = 1.0
		Audio.set_music(world.music_override if not world.music_override.is_empty() else music_context(hour, world.ui != null and world.ui.is_court_open()))


## Which music fits the moment.
static func music_context(hour: float, court_open: bool) -> String:
	if court_open:
		return "court"
	var day: Array = config().get("music", {}).get("day_hours", [6.0, 20.0])
	return "day" if hour >= float(day[0]) and hour < float(day[1]) else "night"


## 0..1 loudness of one ambience zone for a camera focus point, camera
## distance and time of day.
static func zone_weight(zone: Dictionary, focus: Vector3, camera_distance: float, hour: float) -> float:
	var amb: Dictionary = config().get("ambience", {})
	var zoom := 1.0 - smoothstep(float(amb.get("zoom_full", 40.0)), float(amb.get("zoom_silent", 170.0)), camera_distance)
	var w := 0.0
	if bool(zone.get("everywhere", false)):
		w = 1.0
	else:
		var r := float(zone.get("radius", 20.0))
		for p: Vector3 in zone.get("points", []):
			var d := Vector2(p.x - focus.x, p.z - focus.z).length()
			w = maxf(w, 1.0 - smoothstep(r * 0.5, r * 1.5, d))
	var hours: Array = zone.get("hours", [])
	if hours.size() == 2:
		w *= smoothstep(float(hours[0]) - 0.5, float(hours[0]) + 0.5, hour) * (1.0 - smoothstep(float(hours[1]) - 0.5, float(hours[1]) + 0.5, hour))
	if bool(zone.get("day_only", false)):
		var day: Array = config().get("music", {}).get("day_hours", [6.0, 20.0])
		w *= smoothstep(float(day[0]) - 1.0, float(day[0]) + 1.0, hour) * (1.0 - smoothstep(float(day[1]) - 1.0, float(day[1]) + 1.0, hour))
	return w * zoom


func _update_beds(delta: float, focus: Vector3, distance: float, hour: float) -> void:
	var target := {}
	for zone in _zones:
		var w := zone_weight(zone, focus, distance, hour)
		var layers: Dictionary = zone["layers"]
		for layer: String in layers:
			target[layer] = maxf(float(target.get(layer, 0.0)), w * float(layers[layer]))
	var speed := float(config().get("ambience", {}).get("fade_speed", 1.2))
	for layer: String in _beds:
		var p: AudioStreamPlayer = _beds[layer]
		var level := move_toward(float(_bed_level[layer]), float(target.get(layer, 0.0)), speed * delta)
		_bed_level[layer] = level
		if level <= 0.001:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play(_rng.randf() * maxf(p.stream.get_length() - 1.0, 0.0))
		p.volume_db = linear_to_db(level)


func _update_foley(delta: float, focus: Vector3, distance: float) -> void:
	var foley: Dictionary = config().get("foley", {})
	var speed := world.time_scale()
	if distance > float(foley.get("camera_max_distance", 55.0)) or speed <= 0.0:
		return
	var radius := float(foley.get("hear_radius", 22.0))
	var work: Dictionary = foley.get("work", {})
	var tempo := sqrt(speed)
	for npc: NPC in world.npcs.values():
		if not npc.visible:
			continue
		var p := npc.global_position
		if Vector2(p.x - focus.x, p.z - focus.z).length() > radius:
			continue
		var activity := npc.activity()
		var event := ""
		var interval := 0.0
		if activity == "walk" and speed <= 2.0:
			var stone := world.builder.wear_at(Vector2(p.x, p.z)) > float(foley.get("stone_wear", 0.5))
			event = "step_stone" if stone else "step_grass"
			interval = float(foley.get("step_interval", 0.42))
		elif activity == "work" and TerritorySystem.builder_site(world.state, npc.character) != null:
			event = str(foley.get("build", "work_wood"))
			var span: Array = foley.get("work_interval", [1.1, 2.0])
			interval = _rng.randf_range(float(span[0]), float(span[1]))
		elif activity == "work" and work.has(npc.character.occupation_id):
			event = str(work[npc.character.occupation_id])
			var span: Array = foley.get("work_interval", [1.1, 2.0])
			interval = _rng.randf_range(float(span[0]), float(span[1]))
		if event.is_empty():
			_timers.erase(npc.character.id)
			continue
		var left := float(_timers.get(npc.character.id, _rng.randf() * interval)) - delta * tempo
		if left <= 0.0:
			_play_at(event, p)
			left += interval
		_timers[npc.character.id] = left


## Plays `event` at a place in the village (a blow in a fight).
func play_at(event: String, at: Vector3) -> void:
	_play_at(event, at)


func _play_at(event: String, at: Vector3) -> void:
	var stream := Audio.event_stream(event)
	if stream == null or _voices.is_empty():
		return
	var ev := Audio.event_config(event)
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = stream
	v.bus = str(ev.get("bus", "SFX"))
	v.volume_db = float(ev.get("volume_db", 0.0))
	v.global_position = at
	v.play()
