extends Node3D
## Side-by-side comparison: models from different sources as they come (left)
## and after StyleUnifier (right). Needs the 3D/ library importable.
##
##   godot --path . res://tools/style_demo.tscn -- <output.png>

const KENNEY_TOWN := "res://3D/environments/fantasy-town-kit/"
const KAYKIT := "res://3D/alternatives/option-01-kaykit-adventurers/models/"
const MINI := "res://3D/alternatives/option-05-kenney-mini-characters/models/"
const BLOCKY := "res://3D/characters/blocky/"


func _ready() -> void:
	var sky := SkyController.new()
	add_child(sky)
	sky.set_time(11.0 * 60.0)
	TerrainHeight.configure(1, 999.0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 30)
	ground.mesh = plane
	ground.material_override = Mats.hex("#6f9b47")
	add_child(ground)
	var raw := _group(Vector3(-9.5, 0, 0), "As imported")
	var unified := _group(Vector3(9.5, 0, 0), "Unified palette + toon")
	StyleUnifier.apply(unified)
	var cam := Camera3D.new()
	cam.fov = 46
	add_child(cam)
	cam.position = Vector3(0, 10, 23)
	cam.look_at(Vector3(0, 1.2, -0.5))
	for player: AnimationPlayer in find_children("*", "AnimationPlayer", true, false):
		for anim_name in player.get_animation_list():
			if anim_name.to_lower().contains("idle"):
				player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
				player.play(anim_name)
				break
	_capture.call_deferred()


func _load(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("missing " + path)
		return Node3D.new()
	return (load(path) as PackedScene).instantiate()


func _place(parent: Node3D, node: Node3D, pos: Vector3, s: float, yaw: float = 0.0) -> void:
	node.position = pos
	node.scale = Vector3.ONE * s
	node.rotation.y = yaw
	parent.add_child(node)


func _group(origin: Vector3, title: String) -> Node3D:
	var g := Node3D.new()
	g.position = origin
	add_child(g)
	var label := Label3D.new()
	label.text = title
	label.font_size = 96
	label.pixel_size = 0.01
	label.position = Vector3(0, 6.2, -3)
	label.outline_size = 16
	g.add_child(label)
	# A tiny house from Kenney town-kit pieces (2x2 cells, 2.4 m per cell)
	var house := Node3D.new()
	_place(g, house, Vector3(-4.5, 0, -3.0), 2.4)
	for cell in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var faces := []
		if cell.x > 0: faces.append(0.0)
		if cell.x < 0: faces.append(PI)
		if cell.y > 0: faces.append(-PI * 0.5)
		if cell.y < 0: faces.append(PI * 0.5)
		for yaw in faces:
			var piece := "wall-door" if (yaw == -PI * 0.5 and cell.x < 0) else ("wall-window-shutters" if cell.y > 0 else "wall")
			var w := _load(KENNEY_TOWN + "architecture/" + piece + ".glb")
			w.position = Vector3(cell.x, 0, cell.y)
			w.rotation.y = yaw
			house.add_child(w)
	for z in [-0.5, 0.5]:
		var r := _load(KENNEY_TOWN + "architecture/roof-gable.glb")
		r.position = Vector3(0, 1.0, z)
		r.scale = Vector3(2.0, 1.6, 1.0)
		house.add_child(r)
	_place(g, _load(KENNEY_TOWN + "decor/stall-red.glb"), Vector3(-0.6, 0, -2.4), 2.2)
	_place(g, _load(KENNEY_TOWN + "terrain/tree-high-round.glb"), Vector3(6.4, 0, -4.2), 1.8)
	# Characters from four different sources
	_place(g, _load(KAYKIT + "Knight.glb"), Vector3(-5.0, 0, 2.4), 0.62)
	_place(g, _load(MINI + "character-female-a.glb"), Vector3(-2.4, 0, 2.6), 1.25)
	_place(g, _load(BLOCKY + "character-k.glb"), Vector3(0.2, 0, 2.6), 0.62)
	var appearance := {"skin": "#e0b48c", "hair": "#6b4426", "hair_style": "short", "primary": "#2f5f8f", "secondary": "#e0d0b0", "height": 1.0, "build": 1.0, "beard": true}
	var prim := CharacterModel.create(appearance, GameData.occupation("merchant"), "male", 40)
	_place(g, prim, Vector3(2.8, 0, 2.6), 1.0, PI)
	var b := BuildingData.new()
	b.type = "bakery"
	b.footprint = Vector2(4.5, 4.0)
	b.position = Vector3(0, 0, 0)
	var bakery := BuildingFactory.build(b)
	bakery.scale = Vector3.ONE * 0.7
	bakery.position = Vector3(4.2, 0, -1.6)
	bakery.rotation.y = -0.4
	g.add_child(bakery)
	return g


func _capture() -> void:
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://style_demo.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
