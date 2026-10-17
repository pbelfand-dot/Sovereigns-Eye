class_name RevealFX
extends Control
## Light and particles for the Sovereign's Eye reveal, in a tier's colors.
##
## Drawn behind the card: a halo, rays of light turning slowly (the rarest
## tiers) and a ring that runs out from the card when its seal breaks. The
## particles are made here too: sparks bursting from the card's edges (put
## them in front of it), embers rising around it for as long as it shows,
## and flakes of gold leaf drifting down behind it. Reduce motion stills the rays and
## keeps the particles few and slow.

var center := Vector2.ZERO
var main := Color("#e9bf62")
var glow := Color("#fff1c4")
var reduced := false
## 0..1 strengths, tweened by the reveal.
var halo := 0.0:
	set(v):
		halo = v
		queue_redraw()
var rays := 0.0:
	set(v):
		rays = v
		queue_redraw()
## 0..1 how far the ring has run (0 or 1: not shown).
var ring := 0.0:
	set(v):
		ring = v
		queue_redraw()
var angle := 0.0

static var _textures := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_colors(colors: Dictionary) -> void:
	main = Color(str(colors.get("main", "#e9bf62")))
	glow = Color(str(colors.get("glow", "#fff1c4")))


func _process(delta: float) -> void:
	if rays > 0.0 and not reduced:
		angle += delta * 0.12
		queue_redraw()


func _draw() -> void:
	if halo > 0.01:
		var s := Vector2(980, 980)
		draw_texture_rect(EyeEmblem.halo_texture(), Rect2(center - s * 0.5, s), false, Color(glow, 0.42 * halo))
	if rays > 0.01:
		for k in 18:
			var a := angle + k * TAU / 18.0
			var half := deg_to_rad(3.2 if k % 2 == 0 else 1.8)
			var reach := 760.0 if k % 2 == 0 else 560.0
			var base := Color(glow, (0.16 if k % 2 == 0 else 0.11) * rays)
			draw_polygon(PackedVector2Array([center, center + Vector2.from_angle(a - half) * reach, center + Vector2.from_angle(a + half) * reach]),
				PackedColorArray([base, Color(glow, 0.0), Color(glow, 0.0)]))
	if ring > 0.0 and ring < 1.0:
		var e := 1.0 - pow(1.0 - ring, 3.0)
		var rad := lerpf(120.0, 680.0, e)
		draw_arc(center, rad, 0, TAU, 96, Color(glow, 0.55 * (1.0 - ring)), lerpf(14.0, 2.0, ring), true)
		draw_arc(center, rad * 0.93, 0, TAU, 96, Color(main, 0.35 * (1.0 - ring)), lerpf(5.0, 1.0, ring), true)


# --- Particles -----------------------------------------------------------------------------

## Sparks bursting outward from the edges of a card of `card_size` centred
## at `at`.
func sparks(amount: int, at: Vector2, card_size: Vector2) -> CPUParticles2D:
	var p := _particles(maxi(6, roundi(amount * (0.35 if reduced else 1.0))), "star", true)
	p.position = at
	var pts := PackedVector2Array()
	var normals := PackedVector2Array()
	var half := card_size * 0.5
	for k in 64:
		var t := float(k) / 64.0
		var side := k % 4
		var u := fmod(t * 4.0 + 0.37 * k, 1.0) * 2.0 - 1.0
		match side:
			0:
				pts.append(Vector2(u * half.x, -half.y))
				normals.append(Vector2(u * 0.5, -1).normalized())
			1:
				pts.append(Vector2(half.x, u * half.y))
				normals.append(Vector2(1, u * 0.5).normalized())
			2:
				pts.append(Vector2(u * half.x, half.y))
				normals.append(Vector2(u * 0.5, 1).normalized())
			_:
				pts.append(Vector2(-half.x, u * half.y))
				normals.append(Vector2(-1, u * 0.5).normalized())
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS
	p.emission_points = pts
	p.emission_normals = normals
	p.direction = Vector2.RIGHT
	p.spread = 25.0
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 1.5
	p.initial_velocity_min = 50.0 if reduced else 150.0
	p.initial_velocity_max = 110.0 if reduced else 420.0
	p.damping_min = 90.0
	p.damping_max = 220.0
	p.gravity = Vector2(0, 30 if reduced else 110)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.9
	p.scale_amount_curve = _curve([Vector2(0, 0.2), Vector2(0.12, 1.0), Vector2(1, 0.0)])
	p.color_ramp = _ramp([[0.0, Color(glow, 1.0)], [0.35, Color(main.lightened(0.2), 0.95)], [1.0, Color(main, 0.0)]])
	return p


## Embers rising slowly around the card, for as long as it shows.
func motes(amount: int, at: Vector2, card_size: Vector2) -> CPUParticles2D:
	var p := _particles(maxi(4, roundi(amount * (0.4 if reduced else 1.0))), "dot", true)
	p.position = at + Vector2(0, card_size.y * 0.15)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(card_size.x * 0.85, card_size.y * 0.5)
	p.direction = Vector2.UP
	p.spread = 30.0
	p.lifetime = 4.5
	p.initial_velocity_min = 8.0 if reduced else 14.0
	p.initial_velocity_max = 18.0 if reduced else 40.0
	p.gravity = Vector2(0, -6)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.7
	p.color_ramp = _ramp([[0.0, Color(glow, 0.0)], [0.25, Color(glow, 0.75)], [0.7, Color(main, 0.5)], [1.0, Color(main, 0.0)]])
	return p


## Flakes of gold leaf drifting down past the card from above it.
func flakes(amount: int, at: Vector2, card_size: Vector2) -> CPUParticles2D:
	var p := _particles(amount, "flake", false)
	p.position = at - Vector2(0, card_size.y * 0.5 + 30)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(card_size.x * 0.9, 24)
	p.direction = Vector2.DOWN
	p.spread = 28.0
	p.one_shot = true
	p.explosiveness = 0.2
	p.lifetime = 4.2
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 80.0
	p.gravity = Vector2(0, 45)
	p.damping_min = 10.0
	p.damping_max = 25.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -160.0
	p.angular_velocity_max = 160.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.color_ramp = _ramp([[0.0, Color(main.lightened(0.15), 0.0)], [0.08, Color(main.lightened(0.15), 1.0)], [0.75, Color(main, 0.95)], [1.0, Color(main.darkened(0.2), 0.0)]])
	return p


func _particles(amount: int, tex: String, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = maxi(amount, 1)
	p.texture = texture(tex)
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	return p


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	return c


static func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.set_offset(0, float(stops[0][0]))
	g.set_color(0, stops[0][1])
	g.set_offset(1, float(stops[stops.size() - 1][0]))
	g.set_color(1, stops[stops.size() - 1][1])
	for i in range(1, stops.size() - 1):
		g.add_point(float(stops[i][0]), stops[i][1])
	return g


## Particle images, made once: "star" (a four-pointed twinkle), "dot" (a
## soft round mote) and "flake" (a ragged scrap of gold leaf).
static func texture(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var n := 32 if kind == "star" else 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var h := (n - 1) * 0.5
	for y in n:
		for x in n:
			var dx := (x - h) / h
			var dy := (y - h) / h
			var a := 0.0
			match kind:
				"star":
					var core := exp(-(dx * dx + dy * dy) * 9.0)
					var arms := exp(-absf(dx) * 14.0) * exp(-absf(dy) * 2.2) + exp(-absf(dy) * 14.0) * exp(-absf(dx) * 2.2)
					a = clampf(core + arms * 0.85, 0.0, 1.0)
				"dot":
					a = clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
					a = a * a
				_:
					# A rough quadrilateral, brighter along one edge.
					var ragged := 0.78 + 0.12 * sin(x * 2.3 + y * 1.7)
					var inside := absf(dx + dy * 0.35) < ragged and absf(dy) < 0.62
					a = 1.0 if inside else 0.0
					if inside:
						img.set_pixel(x, y, Color(1, 1, 1, 1).lerp(Color(0.8, 0.8, 0.8, 1), clampf((dy + 0.62) / 1.24, 0.0, 1.0)))
						continue
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_textures[kind] = tex
	return tex
