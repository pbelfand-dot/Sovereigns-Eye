class_name SkyController
extends Node3D
## Sun, sky, fog and ambient light driven by the in-game clock.
## Nights stay readable on purpose: this is a strategy game, not a horror one.

const SUNRISE := 5.5
const SUNSET := 20.0

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial

var _day_top := Color("#3f78c2")
var _day_horizon := Color("#b9d6ec")
var _dusk_top := Color("#4a4f8a")
var _dusk_horizon := Color("#f0a46a")
var _night_top := Color("#0b1530")
var _night_horizon := Color("#26365a")


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	add_child(sun)


## `minutes` is the world clock (minutes since day 1, 00:00).
func set_time(minutes: float) -> void:
	var hour := Calendar.hour_f(minutes)
	var daylight := 0.0
	if hour > SUNRISE and hour < SUNSET:
		daylight = sin((hour - SUNRISE) / (SUNSET - SUNRISE) * PI)
	var twilight := clampf(1.0 - absf(daylight - 0.15) / 0.25, 0.0, 1.0) * (1.0 if daylight > 0.0 else 0.0)
	var night := 1.0 - smoothstep(0.0, 0.25, daylight)

	# Sun travels east -> west; at night a dim bluish "moon" takes over.
	var t := clampf((hour - SUNRISE) / (SUNSET - SUNRISE), 0.0, 1.0)
	var elevation := deg_to_rad(lerpf(8.0, 62.0, daylight))
	var azimuth := lerpf(deg_to_rad(-100.0), deg_to_rad(100.0), t)
	if daylight <= 0.0:
		elevation = deg_to_rad(45.0)
		azimuth = deg_to_rad(30.0)
	sun.rotation = Vector3(-elevation, azimuth, 0)
	var sun_color := Color("#fff4e0").lerp(Color("#ffb070"), twilight)
	sun.light_color = sun_color.lerp(Color("#9fb4ff"), night)
	sun.light_energy = lerpf(0.4, 1.15, smoothstep(0.0, 0.4, daylight))

	var top := _day_top.lerp(_dusk_top, twilight).lerp(_night_top, night)
	var horizon := _day_horizon.lerp(_dusk_horizon, twilight).lerp(_night_horizon, night)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon.darkened(0.2)
	sky_mat.ground_bottom_color = top.darkened(0.5)
	env.ambient_light_energy = lerpf(0.5, 0.6, 1.0 - night)
	env.fog_light_color = horizon
	Mats.set_night_glow(night)
