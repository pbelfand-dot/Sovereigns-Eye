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
## Each tier has its own music, in cues that steps start ("cue") and cut
## ("cut"): a rise under the clues, a landing as the card turns, a note for
## each ability as it shows ("rows"). Cues start on their steps, so they
## stay with the picture at any speed; skipping still plays the landing.
## Steps keep to one clock, so the beats never drift. The music and
## ambience are lowered while the Eye is open.
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
var _clock := 0.0          # seconds since the sequence began
var _mark := 0.0           # when the current step's wait ends, on that clock
var _cue_player: AudioStreamPlayer
var _final_cue := ""       # the tier's last cue (its landing), played even when skipped
var _final_played := false
var _fx_done := false
var _closing := false

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
var _vignette: TextureRect
var _fx: RevealFX
var _front_fx: Control


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
	for st: Dictionary in steps_for(tier, compact, reduced, no_flash):
		if st.has("cue"):
			_final_cue = str(st["cue"])
	if not compact:
		Audio.duck(float(_cfg.get("duck_db", -12.0)), 0.4)
	_quiet(true)
	_build()
	_run()


## Their name and ring step aside while the Eye shows them.
func _quiet(on: bool) -> void:
	var npc := world.npc_of(character.id) if world and character else null
	if npc and is_instance_valid(npc):
		npc.quiet = on
		npc.refresh_markers()


## Step lists used for a tier (or the compact reveal), after accessibility
## filtering. Public so tests and tools can inspect timings.
static func steps_for(tier_def: Dictionary, is_compact: bool, reduced_motion: bool, reduce_flash: bool) -> Array:
	var cfg := Discovery.eye_config()
	var src: Array = cfg.get("compact", {}).get("steps", []) if is_compact else tier_def.get("steps", [])
	var out := []
	for s: Dictionary in src:
		var type := str(s.get("type", ""))
		if (reduced_motion and type in ["focus", "shake"]) or (reduce_flash and type == "flash"):
			# No camera move, shaking or flash, but its sounds, music and the
			# seal's cracks still come, at once.
			var still := {"type": "sound", "time": 0.0, "crack": type == "shake"}
			for key: String in ["sound", "caption", "cue", "cut"]:
				if s.has(key):
					still[key] = s[key]
			out.append(still)
			continue
		out.append(s)
	return out


## Seconds a sequence takes (the steps run one after another; focus,
## particles and sounds run alongside).
static func duration(tier_def: Dictionary, is_compact: bool, reduced_motion: bool, reduce_flash: bool) -> float:
	var scale := float(Discovery.eye_config().get("reduced_motion_time", 0.7)) if reduced_motion else 1.0
	var total := 0.0
	for s: Dictionary in steps_for(tier_def, is_compact, reduced_motion, reduce_flash):
		if str(s.get("type", "")) in ["focus", "particles", "sound"]:
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
	# The edges fall darker than the middle, drawing the eye in.
	_vignette = TextureRect.new()
	_vignette.texture = RevealCard.edge_shade()
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(0.02, 0.015, 0.01, 0.0)
	_root.add_child(_vignette)
	var colors: Dictionary = tier.get("colors", {})
	_fx = RevealFX.new()
	_fx.set_colors(colors)
	_fx.reduced = reduced
	_root.add_child(_fx)
	_eye = EyeEmblem.new()
	_eye.set_colors(colors)
	_eye.ornament = int(tier.get("pips", 1)) - 1
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
		_studio.framing = 2.0
		_studio.size = Vector2i(256, 262)
		_studio.rim_color = Color(str(colors.get("glow", "#e8e0cc")))
		add_child(_studio)
		_studio.show_character(character)
		tex = _studio.get_texture()
	_card = RevealCard.new()
	_card.setup(character, tier, tex)
	_card_home = Vector2((view.x - RevealCard.SIZE.x) * 0.5, maxf((view.y - RevealCard.SIZE.y) * 0.5 - 30.0, 8.0))
	_card.position = _card_home
	_card.modulate.a = 0.0
	_root.add_child(_card)
	_fx.center = _card_home + RevealCard.SIZE * 0.5
	_front_fx = Control.new()
	_front_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_front_fx)
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
	var steps := steps_for(tier, compact, reduced, no_flash)
	for step: Dictionary in steps:
		if _skipping:
			break
		await _step(step)
	if not _final_played and not _final_cue.is_empty():
		_play_cue(_final_cue)
	if not _fx_done:
		for step: Dictionary in steps:
			if str(step.get("type", "")) == "particles":
				_particles(step, false)
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


## Waits until `seconds` after the last wait ended, on the sequence's own
## clock: a step that runs a frame long doesn't push the ones after it.
func _wait(seconds: float) -> void:
	_mark += seconds
	while _clock < _mark and not _skipping and is_inside_tree():
		await get_tree().process_frame


func _cue(step: Dictionary) -> void:
	if step.has("cut"):
		_cut_cue(float(step["cut"]))
	if step.has("cue"):
		_play_cue(str(step["cue"]))
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
			var tw := _tween()
			tw.tween_property(_dim, "color:a", float(step.get("to", 0.5)), time)
			tw.tween_property(_vignette, "modulate:a", minf(float(step.get("to", 0.5)) + 0.25, 0.95), time)
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
			tw.tween_property(_eye, "focus", 1.0, time * 0.45).set_delay(time * 0.55)
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
			_tween().tween_property(_card, "crack", 1.0, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			await _wait(time)
			_shake = 0.0
			_card.position = _card_home
		"flash":
			var tw := _tween()
			tw.tween_property(_flash, "color:a", 0.55, time * 0.35)
			tw.chain().tween_property(_flash, "color:a", 0.0, time * 0.65)
			await _wait(time)
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
			_particles(step, true)
		"stats":
			await _stats(str(step.get("mode", "together")), time, step.get("rows", []))
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
			if bool(step.get("crack", false)):
				_card.crack = 1.0
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
			_tween().tween_method(_card.set_silhouette, 0.0, 0.92, time)
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


func _stats(mode: String, time: float, notes: Array = []) -> void:
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
				if k < notes.size():
					Audio.play(str(notes[k]))
				var tw := _tween()
				tw.tween_method(func(p: float) -> void: _card.set_row(i, p), 0.0, 1.0, time / n)
				await _wait(time / n)
				_card.set_row(i, 1.0)


## The tier's light and particles: sparks bursting from the card, the
## ring running out, then the halo, rays, embers and gold leaf that stay
## while the card shows. `burst` false gives only what stays (after a skip).
func _particles(step: Dictionary, burst: bool) -> void:
	_fx_done = true
	var at := _card_home + RevealCard.SIZE * 0.5
	if burst:
		var sparks := _fx.sparks(int(step.get("amount", 30)), at, RevealCard.SIZE)
		_front_fx.add_child(sparks)
		sparks.emitting = true
		get_tree().create_timer(2.5).timeout.connect(sparks.queue_free)
		if bool(step.get("ring", false)) and not reduced:
			_fx.ring = 0.001
			_tween().tween_property(_fx, "ring", 1.0, 0.9).set_trans(Tween.TRANS_LINEAR)
		var leaf := int(step.get("flakes", 0))
		if leaf > 0 and not reduced:
			# Behind the card, so no flake ever covers what it says.
			var flakes := _fx.flakes(leaf, at, RevealCard.SIZE)
			_fx.add_child(flakes)
			flakes.emitting = true
			get_tree().create_timer(6.0).timeout.connect(flakes.queue_free)
	var motes := int(step.get("motes", 0))
	if motes > 0:
		var m := _fx.motes(motes, at, RevealCard.SIZE)
		_fx.add_child(m)
		m.emitting = true
	var halo := float(step.get("halo", 0.0))
	var rays := float(step.get("rays", 0.0))
	var tw := create_tween().set_parallel()
	tw.tween_property(_fx, "halo", halo, 0.6 if burst else 0.0)
	tw.tween_property(_fx, "rays", rays, 0.8 if burst else 0.0)


## Starts a cue (a tier's music), cutting short the one before it.
func _play_cue(path: String) -> void:
	_cut_cue(0.08)
	if path == _final_cue:
		_final_played = true
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_cue_player = AudioStreamPlayer.new()
	_cue_player.stream = load(path)
	_cue_player.bus = "SFX"
	_cue_player.volume_db = float(_cfg.get("cue_db", -2.0))
	add_child(_cue_player)
	_cue_player.play()


## Fades the playing cue out over `fade` seconds.
func _cut_cue(fade: float) -> void:
	if _cue_player == null or not is_instance_valid(_cue_player):
		_cue_player = null
		return
	var p := _cue_player
	_cue_player = null
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, maxf(fade, 0.01))
	tw.tween_callback(p.queue_free)


func _process(delta: float) -> void:
	_clock += delta
	if _spin:
		_eye.ring_angle += delta * 0.9
	if _shake > 0.0:
		_card.position = _card_home + Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	if _caption_left > 0.0:
		_caption_left -= delta
		if _caption_left <= 0.0:
			_caption.text = ""


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
	_vignette.modulate.a = minf(dim_to + 0.25, 0.95)
	_flash.color.a = 0.0
	_eye.modulate.a = 0.0
	_ribbon.modulate.a = 0.0
	_card.face = "front"
	_card.position = _card_home
	_card.scale = Vector2.ONE
	_card.modulate.a = 1.0
	_card.set_sheen(0.0)
	_fx.ring = 0.0
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
	if not is_inside_tree() or _closing:
		return
	_closing = true
	_quiet(false)
	if not compact:
		Audio.duck(0.0, 1.2)
	if world:
		world.paused = _was_paused
		world.speed_changed.emit(world.time_scale())
	finished.emit(action)
	# The music's tail fades out rather than stopping dead.
	_root.visible = false
	if _cue_player and is_instance_valid(_cue_player) and _cue_player.playing:
		_cut_cue(0.5)
		await get_tree().create_timer(0.55).timeout
	queue_free()


func _exit_tree() -> void:
	# Torn down some other way (the world closing): bring the music back.
	if not _closing and not compact:
		Audio.duck(0.0, 0.5)
	if not _closing:
		_quiet(false)


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
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
	if not _closing and not done and skippable and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_skipping = true
		get_viewport().set_input_as_handled()
