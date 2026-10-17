class_name PortraitStudio
extends SubViewport
## Renders a live portrait of a character from their 3D model.
##
## A tiny private 3D world (own_world_3d) holds a camera, lights and a copy
## of the character's model. No image files or external AI are needed; when
## real character models are added, portraits upgrade automatically.
##
## Lit like a painted miniature: a warm key light high on the left, a soft
## cool fill on the right and two rim lights behind that edge the figure
## (in `rim_color`, so the Eye's card can light them in their tier's color).

var _camera: Camera3D
var _holder: Node3D
var _model: CharacterModel
var _phase := 0.0
## The rim lights' color (set before the studio enters the tree).
var rim_color := Color("#9fb6ff")


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
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)
	if transparent_bg:
		env.background_mode = Environment.BG_CLEAR_COLOR
	_light(Vector3(-32, 150, 0), 1.35, Color("#ffe9cc"))   # key: high, front left
	_light(Vector3(-8, -150, 0), 0.32, Color("#c6d2ff"))   # fill: low, front right
	_light(Vector3(-18, -25, 0), 1.1, rim_color)           # rims: behind, either side
	_light(Vector3(-18, 25, 0), 0.8, rim_color)

	_holder = Node3D.new()
	add_child(_holder)
	_camera = Camera3D.new()
	_camera.fov = 28.0
	add_child(_camera)
	_camera.make_current()


func _light(degrees: Vector3, energy: float, color: Color) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = degrees
	l.light_energy = energy
	l.light_color = color
	add_child(l)


## A framing for posters and reveal cards: head and shoulders, wider.
var framing := 2.4


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
	_camera.position = look + Vector3(0.0, 0.08 * h, -framing * h)
	_camera.look_at(look, Vector3.UP)


func _process(delta: float) -> void:
	if _model:
		_phase += delta * 4.0
		_model.animate("idle", _phase, delta)
