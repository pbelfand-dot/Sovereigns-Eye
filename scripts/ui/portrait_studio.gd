class_name PortraitStudio
extends SubViewport
## Renders a live portrait of a character from their 3D model.
##
## A tiny private 3D world (own_world_3d) holds a camera, two lights and a
## copy of the character's model. No image files or external AI are needed;
## when real character models are added, portraits upgrade automatically.

var _camera: Camera3D
var _holder: Node3D
var _model: CharacterModel
var _phase := 0.0


func _init() -> void:
	size = Vector2i(240, 300)
	own_world_3d = true
	transparent_bg = false
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3b2c1f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d9c3a0")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, 155, 0)
	key.light_energy = 1.2
	key.light_color = Color("#fff1dc")
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -30, 0)
	rim.light_energy = 0.6
	rim.light_color = Color("#9fb6ff")
	add_child(rim)

	_holder = Node3D.new()
	add_child(_holder)
	_camera = Camera3D.new()
	_camera.fov = 28.0
	add_child(_camera)
	_camera.make_current()


func show_character(c: CharacterData) -> void:
	if _model:
		_model.queue_free()
		_model = null
	if c == null:
		return
	_model = HumanModel.for_character(c)
	_holder.add_child(_model)
	# Slight three-quarter turn reads better than a flat front view.
	_model.rotation.y = deg_to_rad(-18.0)
	var h := _model.body_height
	var head_y := _model.head_height()
	var look := Vector3(0, head_y - 0.18 * h, 0)
	_camera.position = look + Vector3(0.0, 0.08 * h, -2.4 * h)
	_camera.look_at(look, Vector3.UP)


func _process(delta: float) -> void:
	if _model:
		_phase += delta * 4.0
		_model.animate("idle", _phase, delta)
