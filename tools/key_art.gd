extends Node
## Renders the title screen's art from the game itself, into assets/ui/menu/
## (see its README): the key art, the village at golden hour seen from the
## hills to its south with the heir standing on a rise looking down over
## it, and the emblem, the Sovereign's Eye as it opens in a reveal.
##
##   godot --path . --resolution 2560x1440 res://tools/key_art.tscn -- [seed] [out_dir] [preview|emblem]
##
## Needs a display (xvfb works). The key art is drawn at the window's size
## (2560 x 1440 for the menu). "preview" instead draws every view in VIEWS
## at the window's size into out_dir, to choose from; "emblem" draws only
## the emblem.
##
## Only the picture is dressed for the occasion, never the game: a sky with
## clouds (tools/key_art_sky.gdshader), haze and light in the air, hills
## running on past the edge of the map, a soft far focus.

const HOUR := 19.15
const SEED := "9"
## Views: the camera's ground position (x, z) and height above the ground,
## where it looks, its field of view, and where the heir stands: so far
## ahead of the camera and so far to its right (m).
const VIEWS := {
	"main": [Vector2(25.0, 113.0), 1.1, Vector3(-6.0, 3.0, -4.0), 38.0, 4.6, 1.5],
	"close": [Vector2(25.0, 113.0), 1.0, Vector3(-6.0, 3.0, -4.0), 34.0, 4.0, 1.3],
	"high": [Vector2(24.0, 115.0), 1.6, Vector3(-6.0, 2.0, -6.0), 40.0, 5.2, 1.8],
}
## Trees standing in the way of a view are left out: within this distance
## of the camera and this angle of where it looks. Grass and flowers right
## under the lens (within CLEAR_NEAR) are left out too.
const CLEAR_DIST := 75.0
const CLEAR_ANGLE := 16.0
const CLEAR_NEAR := 4.5
const KEY_VIEW := "main"
## Villagers walking home along the road into the village: how far along
## the road from the heir's end (m), mid-stride.
const WALKERS := [34.0, 41.0, 58.0]

var seed_text := SEED
var out_dir := "res://assets/ui/menu/"
var preview := false
var emblem_only := false
var world: VillageWorld
var cam: Camera3D
var figure: CharacterModel


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_text = args[0]
	if args.size() > 1:
		out_dir = args[1]
	preview = args.has("preview")
	emblem_only = args.has("emblem")
	GameSettings.memory_only = true
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if emblem_only:
		await _emblem()
		get_tree().quit()
		return
	await _build_world()
	_dress()
	if preview:
		for v: String in VIEWS:
			await _shot_view(v, out_dir.path_join("view_%s.png" % v), false)
	else:
		await _shot_view(KEY_VIEW, out_dir.path_join("key_art.jpg"), true)
		await _emblem()
	get_tree().quit()


## The village a little before sunset, people about their evening.
func _build_world() -> void:
	Game.state = WorldGenerator.generate(seed_text)
	var st := Game.state
	st.minutes += (HOUR - 2.0 - Calendar.hour_f(st.minutes)) * 60.0
	for v: String in (VIEWS.keys() if preview else [KEY_VIEW]):
		_clear_view(st, VIEWS[v])
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await _wait(5)
	world.set_view_mode("overview", true)
	world.set_speed(3)
	while Calendar.hour_f(st.minutes) < HOUR:
		world._process(0.1)
	world.set_speed(0)
	world.paused = true
	world.sky.set_time(st.minutes)
	# Hold the moment: the world stops updating (and resetting the sky).
	world.set_process(false)
	world.ui.visible = false
	var heir := world.player_npc()
	if heir:
		heir.visible = false
	cam = Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	figure = HumanModel.for_character(st.player())
	add_child(figure)
	for f in 20:
		figure.animate("idle", f * 0.1, 0.05)
	_walkers(st)


## The sky, the air and the land beyond the map, for the picture only.
func _dress() -> void:
	var env := world.sky.env
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://tools/key_art_sky.gdshader")
	env.sky.sky_material = sky_mat
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color("#e9b58a")
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.75
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color("#ffe3c0")
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 260.0
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.ssil_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	var sun := world.sky.sun
	sun.light_color = Color("#ffc483")
	sun.light_energy = 1.55
	sun.light_volumetric_fog_energy = 1.6
	sun.directional_shadow_max_distance = 300.0
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 260.0
	attrs.dof_blur_far_transition = 400.0
	attrs.dof_blur_amount = 0.06
	cam.attributes = attrs
	add_child(_far_land())
	get_viewport().msaa_3d = Viewport.MSAA_4X


## Hills running on past the map's edge into the haze, a little higher
## the further they are. Under the map itself they sit out of sight.
func _far_land() -> MeshInstance3D:
	var noise := FastNoiseLite.new()
	noise.seed = 1187
	noise.frequency = 0.0014
	noise.fractal_octaves = 4
	var edge := world.state.layout.extent + 60.0
	var n := 120
	var size := 4800.0
	var step := size / n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var near := Color("#3e5a2c")
	var far := Color("#56654f")
	var h := func(x: float, z: float) -> float:
		if absf(x) < edge - 1.0 and absf(z) < edge - 1.0:
			return TerrainHeight.height_at(x, z) - 4.0
		var d := Vector2(x, z).length()
		return TerrainHeight.height_at(x, z) + smoothstep(edge + 40.0, 1400.0, d) * (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 140.0
	for iz in n:
		for ix in n:
			var x0 := -size * 0.5 + ix * step
			var z0 := -size * 0.5 + iz * step
			var q := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for k in 4:
				q[k].y = h.call(q[k].x, q[k].z)
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for k: int in tri:
					var v: Vector3 = q[k]
					st.set_color(near.lerp(far, clampf(Vector2(v.x, v.z).length() / 1800.0, 0.0, 1.0)))
					st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "FarLand"
	mi.mesh = st.commit()
	mi.material_override = Mats.vertex_colored()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A few villagers on the road nearest the camera, walking into the village.
func _walkers(st: WorldState) -> void:
	var from: Vector2 = VIEWS[KEY_VIEW][0]
	var best: PackedVector3Array
	var best_d := INF
	for r: Dictionary in st.layout.roads:
		var pts: PackedVector3Array = r["points"]
		for p in pts:
			var d := Vector2(p.x, p.z).distance_to(from)
			if d < best_d:
				best_d = d
				best = pts
	if best.size() < 2:
		return
	# Walk the road from its end nearest the camera toward the village.
	var path := Array(best)
	if Vector2(path[0].x, path[0].z).distance_to(from) > Vector2(path[-1].x, path[-1].z).distance_to(from):
		path.reverse()
	var adults := st.characters.filter(func(c: CharacterData) -> bool: return c.age >= 18 and not st.is_player(c))
	for k in WALKERS.size():
		var along := float(WALKERS[k])
		var at := Vector3.ZERO
		var dir := Vector3.FORWARD
		for i in range(1, path.size()):
			var seg: float = (path[i] - path[i - 1]).length()
			if along <= seg:
				at = path[i - 1].lerp(path[i], along / seg)
				dir = (path[i] - path[i - 1]).normalized()
				break
			along -= seg
		if at == Vector3.ZERO:
			continue
		var side := Vector3(-dir.z, 0, dir.x) * (0.6 if k % 2 == 0 else -0.5)
		var m := HumanModel.for_character(adults[(k * 11 + 3) % adults.size()])
		add_child(m)
		m.global_position = TerrainHeight.on_ground(at + side)
		m.rotation.y = atan2(-dir.x, -dir.z)
		for f in 10 + k * 3:
			m.animate("walk", f * 0.13, 0.05)


## Fells (for the picture) the trees between a view's camera and what it
## looks at, so the village shows.
func _clear_view(st: WorldState, v: Array) -> void:
	var from: Vector2 = v[0]
	var look: Vector3 = v[2]
	var dir := (Vector2(look.x, look.z) - from).normalized()
	for i in st.layout.trees.size():
		var t := st.layout.trees[i]
		var off := Vector2(t.x, t.y) - from
		if off.length() < CLEAR_DIST and absf(rad_to_deg(dir.angle_to(off))) < CLEAR_ANGLE:
			if not st.territory.cleared_trees.has(i):
				st.territory.cleared_trees.append(i)


## Puts the grass, flowers and stones right under the lens out of sight.
func _clear_scatter(at: Vector2) -> void:
	for mmi: MultiMeshInstance3D in world.builder.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := mmi.multimesh
		for i in mm.instance_count:
			var xf := mmi.global_transform * mm.get_instance_transform(i)
			if Vector2(xf.origin.x, xf.origin.z).distance_to(at) < CLEAR_NEAR and xf.origin.y > -50.0:
				xf.origin.y -= 200.0
				mm.set_instance_transform(i, mmi.global_transform.affine_inverse() * xf)


func _ground(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, TerrainHeight.height_at(p.x, p.y) + lift, p.y)


func _shot_view(view: String, path: String, jpg: bool) -> void:
	var v: Array = VIEWS[view]
	var from: Vector2 = v[0]
	var look: Vector3 = v[2]
	var ahead := (Vector2(look.x, look.z) - from).normalized()
	var right := Vector2(-ahead.y, ahead.x)
	figure.global_position = _ground(from + ahead * float(v[4]) + right * float(v[5]), 0.0)
	var to := look - figure.global_position
	figure.rotation.y = atan2(-to.x, -to.z)
	cam.fov = float(v[3])
	cam.global_position = _ground(from, float(v[1]))
	cam.look_at(look)
	cam.make_current()
	_clear_scatter(from)
	await _wait(16)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if jpg:
		img.save_jpg(path, 0.9)
	else:
		img.save_png(path)
	print("saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])


## The Eye at its fullest, gold on royal blue, on a clear background.
func _emblem() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var e := EyeEmblem.new()
	e.set_colors(Discovery.tier_by_id("exceptional").get("colors", {}))
	e.ornament = 3
	e.open = 1.0
	e.glow = 0.55
	e.rays = 1.0
	e.focus = 1.0
	# Drawn at the size the reveal shows it (its lines and letters are sized
	# for that) with room round it for the rays, scaled up to twice the size
	# it is kept at, then halved, for clean edges.
	var room := 400.0
	e.size = Vector2(320, 320)
	e.scale = Vector2.ONE * 1024.0 / room
	e.position = Vector2.ONE * (room - 320.0) * 0.5 * e.scale.x
	vp.add_child(e)
	await _wait(4)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var path := out_dir.path_join("emblem.png")
	img.save_png(path)
	print("saved %s" % path)
