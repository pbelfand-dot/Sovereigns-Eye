class_name EyeReveal
extends CanvasLayer
## The Sovereign's Eye reveal: a short, card-pack-style sequence in the
## game's own medieval look. The world dims, the Eye opens, a sealed card
## appears, clues build suspense, the seal breaks, the card turns and the
## person's gifts land, the greatest one last.
##
## Reusable: the sequence is a list of steps in data/eye.json, one list per
## tier (Ordinary, Skilled, Exceptional, Legendary) plus a quick "compact"
## list for people already seen. Respects GameSettings: reduced motion (no
## camera moves, shakes, spins or flips; shorter), reduced flashes, captions
## for important sounds. A tier's full sequence can be skipped once the
## player has seen it.
##
## Ends with choices (talk, appoint, remember, card, close) and emits
## `finished(action)`.

signal finished(action: String)

const LAYER := 30

var world: VillageWorld
var character: CharacterData
var tier: Dictionary = {}
var compact := false
var skippable := false
var reduced := false
var no_flash := false
var done := false

var _cfg: Dictionary = {}
var _time_scale := 1.0
var _skipping := false
var _was_paused := false
var _tweens: Array[Tween] = []
var _spin := false
var _shake := 0.0
var _card_home := Vector2.ZERO

var _root: Control
var _dim: ColorRect
var _flash: ColorRect
var _eye: EyeEmblem
var _card: RevealCard
var _ribbon: Label
var _caption: Label
var _caption_left := 0.0
var _skip_hint: Label
var _actions: HBoxContainer
var _studio: PortraitStudio
var _sting: AudioStreamPlayer
var _sting_fade := 0.0


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts the reveal for a character. `is_compact` plays the quick version.
func play(owner_world: VillageWorld, c: CharacterData, is_compact: bool) -> void:
	world = owner_world
	character = c
	compact = is_compact
	_cfg = Discovery.eye_config()
	tier = Discovery.tier_for(c)
	reduced = GameSettings.reduced_motion()
	no_flash = GameSettings.reduce_flashes()
	skippable = compact or GameSettings.eye_seen(str(tier.get("id", "")))
	_time_scale = float(_cfg.get("reduced_motion_time", 0.7)) if reduced else 1.0
	if world:
		_was_paused = world.paused
		world.paused = true
		world.speed_changed.emit(world.time_scale())
	_build()
	_run()


## Step lists used for a tier (or the compact reveal), after accessibility
## filtering. Public so tests and tools can inspect timings.
static func steps_for(tier_def: Dictionary, is_compact: bool, reduced_motion: bool, reduce_flash: bool) -> Array:
	var cfg := Discovery.eye_config()
	var src: Array = cfg.get("compact", {}).get("steps", []) if is_compact else tier_def.get("steps", [])
	var out := []
	for s: Dictionary in src:
		var type := str(s.get("type", ""))
		if reduced_motion and type in ["focus", "shake"]:
			if s.has("sound"):
				out.append({"type": "sound", "sound": s["sound"], "caption": s.get("caption", ""), "time": 0.0})
			continue
		if reduce_flash and type == "flash":
			continue
		out.append(s)
	return out


## Seconds a sequence takes (the steps run one after another; focus and
## sting run alongside).
static func duration(tier_def: Dictionary, is_compact: bool, reduced_motion: bool, reduce_flash: bool) -> float:
	var scale := float(Discovery.eye_config().get("reduced_motion_time", 0.7)) if reduced_motion else 1.0
	var total := 0.0
	for s: Dictionary in steps_for(tier_def, is_compact, reduced_motion, reduce_flash):
		if str(s.get("type", "")) in ["focus", "sting", "particles", "sound"]:
			continue
		total += float(s.get("time", 0.0)) * scale
	return total


# --- Building the layer -------------------------------------------------------------------

func _build() -> void:
	var view := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.015, 0.01, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	var colors: Dictionary = tier.get("colors", {})
	_eye = EyeEmblem.new()
	_eye.set_colors(colors)
	_eye.ornate = str(tier.get("id", "")) == "legendary"
	_eye.size = Vector2(320, 320)
	_eye.position = view * 0.5 - _eye.size * 0.5 - Vector2(0, 20)
	_eye.pivot_offset = _eye.size * 0.5
	_eye.modulate.a = 0.0
	_root.add_child(_eye)
	# The portrait comes from a private studio with a clear background, so
	# it can also be shown as a black silhouette.
	var tex: Texture2D = PortraitPrompt.image_for(character, world.state.world_seed) if world else null
	if tex == null:
		_studio = PortraitStudio.new()
		_studio.transparent_bg = true
		_studio.framing = 2.2
		add_child(_studio)
		_studio.show_character(character)
		tex = _studio.get_texture()
	_card = RevealCard.new()
	_card.setup(character, tier, tex)
	_card_home = Vector2((view.x - RevealCard.SIZE.x) * 0.5, maxf((view.y - RevealCard.SIZE.y) * 0.5 - 30.0, 8.0))
	_card.position = _card_home
	_card.modulate.a = 0.0
	_root.add_child(_card)
	_ribbon = UITheme.label("", 20, Color(str(colors.get("glow", "#fff1c4"))), true)
	_ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ribbon.size = Vector2(view.x, 30)
	_ribbon.position = Vector2(0, _card_home.y + RevealCard.SIZE.y + 10)
	_ribbon.modulate.a = 0.0
	_root.add_child(_ribbon)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.97, 0.9, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	_caption = UITheme.label("", 16, UITheme.TEXT, false)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.size = Vector2(view.x, 26)
	_caption.position = Vector2(0, view.y - 34)
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("shadow_offset_x", 1)
	_caption.add_theme_constant_override("shadow_offset_y", 1)
	_root.add_child(_caption)
	_skip_hint = UITheme.label("Click to skip", 14, UITheme.TEXT_DIM, false)
	_skip_hint.position = Vector2(view.x - 130, view.y - 34)
	_skip_hint.visible = skippable and not compact
	_root.add_child(_skip_hint)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.size = Vector2(view.x, 40)
	_actions.position = Vector2(0, _card_home.y + RevealCard.SIZE.y + 12)
	_actions.visible = false
	_root.add_child(_actions)


# --- Running the sequence ---------------------------------------------------------------------

func _run() -> void:
	for step: Dictionary in steps_for(tier, compact, reduced, no_flash):
		if _skipping:
			break
		await _step(step)
	_show_final()
	if not compact:
		GameSettings.mark_eye_seen(str(tier.get("id", "")))
	_show_actions()


func _t(step: Dictionary) -> float:
	return float(step.get("time", 0.0)) * _time_scale


func _tween() -> Tween:
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tweens.append(tw)
	return tw


func _wait(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _skipping and is_inside_tree():
		await get_tree().process_frame
		left -= get_process_delta_time()


func _cue(step: Dictionary) -> void:
	var ev := str(step.get("sound", ""))
	if not ev.is_empty():
		Audio.play(ev)
	var cap := str(step.get("caption", ""))
	if not cap.is_empty() and GameSettings.captions():
		_caption.text = cap
		_caption_left = float(_cfg.get("caption_seconds", 1.8))


func _step(step: Dictionary) -> void:
	_cue(step)
	var time := _t(step)
	match str(step.get("type", "")):
		"dim":
			_tween().tween_property(_dim, "color:a", float(step.get("to", 0.5)), time)
			await _wait(time)
		"focus":
			var npc := world.npc_of(character.id) if world else null
			if npc and npc.visible:
				world.camera_rig.follow_target = null
				world.camera_rig.look_at_point(npc.global_position + Vector3(0, 1.0, 0), float(step.get("distance", 16.0)))
		"heartbeat":
			var beats := maxi(int(step.get("beats", 2)), 1)
			_eye.modulate.a = 1.0
			for i in beats:
				var tw := _tween()
				tw.tween_property(_eye, "glow", 0.7, time / beats * 0.3)
				tw.chain().tween_property(_eye, "glow", 0.1, time / beats * 0.7)
				if i > 0:
					_cue(step)
				await _wait(time / beats)
		"eye":
			_eye.modulate.a = 1.0
			_spin = bool(step.get("spin", false)) and not reduced
			var tw := _tween()
			tw.tween_property(_eye, "open", float(step.get("open", 1.0)), time).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_eye, "glow", 1.0, time)
			tw.tween_property(_eye, "rays", float(step.get("rays", 0.0)), time)
			if not reduced:
				_eye.scale = Vector2(0.85, 0.85)
				tw.tween_property(_eye, "scale", Vector2.ONE, time)
			await _wait(time)
		"card_back", "card_front":
			_card.face = "back" if step["type"] == "card_back" else "front"
			var tw := _tween()
			tw.tween_property(_eye, "modulate:a", 0.0, time)
			tw.tween_property(_card, "modulate:a", 1.0, time)
			if not reduced:
				_card.position = _card_home + Vector2(0, 50)
				_card.scale = Vector2(0.94, 0.94)
				tw.tween_property(_card, "position", _card_home, time)
				tw.tween_property(_card, "scale", Vector2.ONE, time)
			await _wait(time)
		"sweep":
			var tw := _tween()
			_card.set_sheen(0.0)
			tw.tween_method(_card.set_sheen, 0.0, 1.0, time).set_trans(Tween.TRANS_SINE)
			await _wait(time)
			_card.set_sheen(0.0)
		"clue":
			await _clue(str(step.get("kind", "role")), time)
		"shake":
			_shake = 0.0 if reduced else float(step.get("strength", 4.0))
			await _wait(time)
			_shake = 0.0
			_card.position = _card_home
		"flash":
			var tw := _tween()
			tw.tween_property(_flash, "color:a", 0.55, time * 0.35)
			tw.chain().tween_property(_flash, "color:a", 0.0, time * 0.65)
			await _wait(time)
		"sting":
			_play_sting(str(step.get("file", "")), float(step.get("fade", 4.0)))
		"flip":
			_ribbon.modulate.a = 0.0
			if reduced:
				var tw := _tween()
				tw.tween_property(_card, "modulate:a", 0.0, time * 0.5)
				await _wait(time * 0.5)
				_card.face = "front"
				_tween().tween_property(_card, "modulate:a", 1.0, time * 0.5)
				await _wait(time * 0.5)
			else:
				var tw := _tween()
				tw.tween_property(_card, "scale:x", 0.02, time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				await _wait(time * 0.5)
				_card.face = "front"
				_tween().tween_property(_card, "scale:x", 1.0, time * 0.5).set_trans(Tween.TRANS_BACK)
				await _wait(time * 0.5)
		"particles":
			_burst(int(step.get("amount", 30)))
		"stats":
			await _stats(str(step.get("mode", "together")), time)
		"stamp":
			_card.show_stamp(true)
			if not reduced:
				_card.stamp.scale = Vector2(2.4, 2.4)
				_card.stamp.rotation = -0.25
				var tw := _tween()
				tw.tween_property(_card.stamp, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BOUNCE)
				tw.tween_property(_card.stamp, "rotation", 0.0, time)
			await _wait(time)
		"wait", "sound":
			await _wait(time)


func _clue(kind: String, time: float) -> void:
	var top := Discovery.top_abilities(character)
	var text := ""
	match kind:
		"role":
			text = "%s of %s" % [character.occupation_name(), world.state.village_name if world else "the village"]
		"gift":
			text = "A gift for %s..." % str(top[0]["name"])
		"motto":
			text = str(_cfg.get("mottos", {}).get(str(top[0]["id"]), "A rare soul."))
		"silhouette":
			_tween().tween_property(_card.silhouette, "modulate:a", 0.92, time)
			await _wait(time)
			return
	_ribbon.text = text
	_ribbon.modulate.a = 0.0
	var tw := _tween()
	tw.tween_property(_ribbon, "modulate:a", 1.0, time * 0.5)
	if not reduced:
		var y := _ribbon.position.y
		_ribbon.position.y = y + 12
		tw.tween_property(_ribbon, "position:y", y, time * 0.5)
	await _wait(time)


func _stats(mode: String, time: float) -> void:
	var n := _card.row_count()
	match mode:
		"instant":
			for i in n:
				_card.set_row(i, 1.0)
		"together":
			var tw := _tween()
			tw.tween_method(func(p: float) -> void:
				for i in n:
					_card.set_row(i, p), 0.0, 1.0, time)
			await _wait(time)
		_:
			# Weakest of the three first; the greatest gift lands last.
			for k in n:
				var i := n - 1 - k
				var tw := _tween()
				tw.tween_method(func(p: float) -> void: _card.set_row(i, p), 0.0, 1.0, time / n)
				await _wait(time / n)
				_card.set_row(i, 1.0)


func _burst(amount: int) -> void:
	var p := CPUParticles2D.new()
	var colors: Dictionary = tier.get("colors", {})
	p.position = _card_home + RevealCard.SIZE * 0.5
	p.amount = maxi(4, roundi(amount * (0.3 if reduced else 1.0)))
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 1.4
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = RevealCard.SIZE * 0.45
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 20.0 if reduced else 90.0
	p.initial_velocity_max = 40.0 if reduced else 260.0
	p.gravity = Vector2(0, 40 if reduced else 160)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(str(colors.get("glow", "#ffffff"))))
	ramp.set_color(1, Color(Color(str(colors.get("main", "#ffffff"))), 0.0))
	p.color_ramp = ramp
	p.texture = _spark_texture()
	_root.add_child(p)
	_root.move_child(p, _card.get_index())
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


static func _spark_texture() -> Texture2D:
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	for y in 9:
		for x in 9:
			var d := absf(x - 4) + absf(y - 4)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d / 4.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _play_sting(path: String, fade: float) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_sting = AudioStreamPlayer.new()
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = false
	_sting.stream = stream
	_sting.bus = "SFX"
	_sting.volume_db = -3.0
	add_child(_sting)
	_sting.play()
	_sting_fade = fade


func _process(delta: float) -> void:
	if _spin:
		_eye.ring_angle += delta * 0.9
	if _shake > 0.0:
		_card.position = _card_home + Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	if _caption_left > 0.0:
		_caption_left -= delta
		if _caption_left <= 0.0:
			_caption.text = ""
	if _sting and _sting.playing:
		_sting_fade -= delta
		if _sting_fade < 1.0:
			_sting.volume_db = linear_to_db(maxf(_sting_fade, 0.001)) - 3.0
		if _sting_fade <= 0.0:
			_sting.stop()


# --- End state & choices ---------------------------------------------------------------------

func _show_final() -> void:
	for tw in _tweens:
		if tw.is_valid():
			tw.kill()
	_tweens.clear()
	_spin = false
	_shake = 0.0
	var steps := steps_for(tier, compact, reduced, no_flash)
	var dim_to := 0.6
	for s: Dictionary in steps:
		if str(s.get("type", "")) == "dim":
			dim_to = float(s.get("to", 0.6))
	_dim.color.a = dim_to
	_flash.color.a = 0.0
	_eye.modulate.a = 0.0
	_ribbon.modulate.a = 0.0
	_card.face = "front"
	_card.position = _card_home
	_card.scale = Vector2.ONE
	_card.modulate.a = 1.0
	_card.set_sheen(0.0)
	for i in _card.row_count():
		_card.set_row(i, 1.0)
	_card.show_stamp(true)
	_card.stamp.scale = Vector2.ONE
	_card.stamp.rotation = 0.0
	_skip_hint.visible = false
	done = true


func _show_actions() -> void:
	var st := world.state if world else null
	if st:
		if world.talking_to == character.id:
			_action("Back to the conversation", "talk", "Learn what they want and make them an offer")
		elif not character.retainer and not CourtSystem.is_kin(st, character) and character.age >= int(CourtSystem.section("recruit").get("min_age", 10)):
			_action("Talk to them", "talk", "Walk up and speak with them: learn what they want, then make an offer")
		if character.retainer and character.age >= 16:
			_action("Appoint...", "appoint", "Give them an office or a training focus (Court tab)")
	var remember := _action("Forget" if character.remembered else "Remember", "remember", "Mark them in the ledger so you can find them again")
	remember.pressed.connect(func() -> void:
		character.remembered = not character.remembered
		remember.text = "Forget" if character.remembered else "Remember", CONNECT_DEFERRED)
	_action("Full card", "card", "Open their character card")
	var close := _action("Close", "close", "Back to the village (Esc)")
	_actions.visible = true
	close.grab_focus()


func _action(text: String, action: String, tip: String) -> Button:
	var b := UITheme.button(text, func() -> void:
		if action != "remember":
			_finish(action))
	b.tooltip_text = tip
	_actions.add_child(b)
	return b


func _finish(action: String) -> void:
	if not is_inside_tree():
		return
	if _sting:
		_sting.stop()
	if world:
		world.paused = _was_paused
		world.speed_changed.emit(world.time_scale())
	finished.emit(action)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	var press := (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if not press:
		return
	if not done:
		if skippable:
			_skipping = true
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("menu") or (event is InputEventKey and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
		get_viewport().set_input_as_handled()
		_finish("close")


func _input(event: InputEvent) -> void:
	# Clicks land on the full-screen root first; route them to skipping.
	if not done and skippable and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_skipping = true
		get_viewport().set_input_as_handled()
