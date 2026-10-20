extends SceneTree
## Review shots of the Carts & Transport family in Godot's own renderer,
## with the nodes turned the way the game turns them (CartView): each leg
## segment and the neck about its local +Z (Basis(Vector3.BACK, angle)), the
## tail about +X, the wheels about +Z. Needs a display (xvfb works).
##
##   godot --path . --resolution 1280x800 --script res://3D/props/carts-transport/source/godot_review.gd -- <out_dir>
##
## Files: godot_strategy.png (the rig, laden, and the unhitched cart from a
## strategy camera 30 m off), godot_walk.png (legs at +-35 degrees, side on),
## godot_joints_front.png / godot_joints_rear.png (low, into the joints),
## godot_unhitched.png, godot_laden.png.

const DIR := "res://3D/props/carts-transport/models/"
const J := deg_to_rad(35.0)
## Godot angles about +Z: positive brings a hoof forward (+X).
const WALK := {"Leg_FL": J, "Leg_FL_Lower": -J, "Leg_FR": -J, "Leg_HL": -J, "Leg_HL_Lower": J, "Leg_HR": J, "Neck": -0.1}
const WALK_B := {"Leg_FL": -J, "Leg_FR": J, "Leg_FR_Lower": -J, "Leg_HL": J, "Leg_HR": -J, "Leg_HR_Lower": J, "Neck": 0.1}

var out_dir := "user://carts_review"
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.48, 0.24)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	var track := MeshInstance3D.new()
	var tp := PlaneMesh.new()
	tp.size = Vector2(40, 3.2)
	track.mesh = tp
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.45, 0.37, 0.27)
	tm.roughness = 1.0
	track.material_override = tm
	track.position = Vector3(0, 0.005, 0)
	world.add_child(track)
	cam = Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	# The rig, laden, on the track; the cart unhitched in a yard beside it.
	var rig := (load(DIR + "SE_Cart_Horse.glb") as PackedScene).instantiate() as Node3D
	world.add_child(rig)
	var anchor := rig.find_child("Load_Anchor", true, false) as Node3D
	anchor.add_child((load(DIR + "SE_Cart_Load.glb") as PackedScene).instantiate())
	var cart := (load(DIR + "SE_Cart.glb") as PackedScene).instantiate() as Node3D
	cart.position = Vector3(-3.5, 0, -5.0)
	cart.rotation.y = deg_to_rad(-35.0)
	world.add_child(cart)
	var horse := rig.find_child("Horse", true, false) as Node3D
	var hc := horse.global_position + Vector3(0, 0.8, 0)
	await _shot("godot_strategy.png", Vector3(0.5, 0.6, -2.0), Vector3(-14.0, 22.0, 18.0), 40.0)
	await _shot("godot_laden.png", Vector3(0.3, 0.9, 0.0), Vector3(-3.2, 3.4, -3.6), 40.0)
	_pose(rig, WALK)
	await _shot("godot_walk.png", hc, hc + Vector3(0.0, 0.1, -3.8), 45.0)
	await _shot("godot_joints_front.png", hc + Vector3(0.1, -0.35, 0.0), hc + Vector3(2.0, -0.5, -1.6), 45.0)
	_pose(rig, WALK_B)
	await _shot("godot_walk_b.png", hc, hc + Vector3(0.0, 0.1, -3.8), 45.0)
	await _shot("godot_joints_rear.png", hc + Vector3(-0.2, -0.35, 0.0), hc + Vector3(-2.2, -0.45, 1.5), 45.0)
	_pose(rig, {})
	# From its right, ahead of the wheel (the cart's own frame).
	await _shot("godot_unhitched.png", cart.transform * Vector3(0.9, 0.7, 0.0), cart.transform * Vector3(3.2, 2.4, 4.2), 42.0)
	quit(0)


func _pose(rig: Node3D, pose: Dictionary) -> void:
	for n: String in ["Leg_FL", "Leg_FR", "Leg_HL", "Leg_HR", "Leg_FL_Lower", "Leg_FR_Lower", "Leg_HL_Lower", "Leg_HR_Lower", "Neck"]:
		var node := rig.find_child(n, true, false) as Node3D
		node.basis = Basis(Vector3.BACK, float(pose.get(n, 0.0)))
	var tail := rig.find_child("Tail", true, false) as Node3D
	tail.basis = Basis(Vector3.RIGHT, 0.12 if not pose.is_empty() else 0.0)
	for w: String in ["Wheel_L", "Wheel_R"]:
		(rig.find_child(w, true, false) as Node3D).basis = Basis(Vector3.BACK, -0.4 if not pose.is_empty() else 0.0)


func _shot(file_name: String, target: Vector3, from: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.position = from
	cam.look_at(target)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(file_name))
	print("saved ", out_dir.path_join(file_name))
