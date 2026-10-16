extends Node3D
## Renders every kit building prefab (and, if present, a lineup of villagers)
## to PNGs for review. Needs a display/GPU (use xvfb-run on servers).
##
##   godot --path . res://tools/prefab_gallery.tscn -- <output_dir> [people|wear|nature|props]

var out_dir := "user://gallery"
var _camera: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(file_name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(file_name))
	print("saved ", out_dir.path_join(file_name))


func _look(from: Vector3, at: Vector3, fov: float = 40.0) -> void:
	_camera.position = from
	_camera.fov = fov
	_camera.look_at(at, Vector3.UP)


func _run() -> void:
	var sky := SkyController.new()
	add_child(sky)
	sky.set_time(10.5 * 60.0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	ground.material_override = Mats.hex("#5d7a3a")
	add_child(ground)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()

	var types: Array = GameData.load_file("buildings").get("types", {}).keys()
	var x := 0.0
	var centers := {}
	for t: String in types:
		var def := GameData.building_type(t)
		var fp: Array = def.get("footprint", [6, 6])
		var b := BuildingData.new()
		b.id = centers.size()
		b.type = t
		b.footprint = Vector2(float(fp[0]), float(fp[1]))
		x += b.footprint.x * 0.5 + 4.0
		b.position = Vector3(x, 0, 0)
		x += b.footprint.x * 0.5 + 4.0
		add_child(BuildingFactory.build(b))
		centers[t] = b
	var mid := x * 0.5
	if OS.get_cmdline_user_args().has("people"):
		await _people()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("wear"):
		await _wear()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("nature"):
		await _nature()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("props"):
		await _props()
		get_tree().quit()
		return
	_look(Vector3(mid, 55, 70), Vector3(mid, 0, 0), 55.0)
	await _shot("prefabs_all.png")
	for t: String in centers:
		var b: BuildingData = centers[t]
		var size := maxf(b.footprint.x, b.footprint.y)
		_look(b.position + Vector3(size * 0.9, size * 0.75 + 3.0, size * 1.3 + 6.0), b.position + Vector3(0, 2.5, 0))
		await _shot("prefab_%s.png" % t)
	# Back view of the cottage and manor to check the rear walls and gables.
	for t: String in ["cottage", "manor"]:
		var b: BuildingData = centers[t]
		var size := maxf(b.footprint.x, b.footprint.y)
		_look(b.position + Vector3(-size * 0.8, size * 0.6 + 3.0, -size * 1.3 - 6.0), b.position + Vector3(0, 2.5, 0))
		await _shot("prefab_%s_back.png" % t)
	await _people()
	get_tree().quit()


## Status Wear (3D/characters/status-wear): one villager per headwear and
## apron, men and women, short and long hair, standing (idle) and walking.
## WEAR_MODE=walk poses them mid-stride.
func _wear() -> void:
	var w := WorldGenerator.generate("gallery")
	var base: CharacterData = null
	for c in w.characters:
		if c.age >= 25 and c.age < 50:
			base = c
			break
	var lineup := [
		["farmer", "male", "short"], ["farmer", "female", "long"], ["miller", "male", "long"], ["merchant", "female", "short"],
		["baker", "male", "short"], ["baker", "female", "bun"], ["lord", "male", "short"], ["lady", "female", "long"],
		["king", "male", "long"], ["queen", "female", "long"], ["soldier", "male", "short"], ["guard_captain", "female", "long"],
		["dowager", "female", "bun"], ["blacksmith", "male", "short"], ["carpenter", "female", "long"], ["innkeeper", "male", "cropped"],
		["housekeeper", "female", "long"], ["dowager", "male", "short"],
	]
	var mode := OS.get_environment("WEAR_MODE")
	var models: Array[CharacterModel] = []
	for i in lineup.size():
		var c := CharacterData.from_dict(base.to_dict())
		c.id = 9000 + i
		c.occupation_id = str(lineup[i][0])
		c.gender = str(lineup[i][1])
		c.appearance["hair_style"] = str(lineup[i][2])
		c.appearance["beard"] = false
		var m := HumanModel.for_character(c)
		add_child(m)
		m.position = Vector3(-8.5 + (i % 9) * 2.1, 0, 40 - floorf(i / 9.0) * 3.0)
		m.rotation.y = PI
		models.append(m)
		print("%d %s %s %s look %s" % [i, c.occupation_id, c.gender, c.appearance["hair_style"], OutfitKit.look_for(c)["parts"]])
	for f in 30:
		for m in models:
			m.animate(mode if not mode.is_empty() else "idle", f * 0.1, 1.0 / 30.0)
	_look(Vector3(0, 2.6, 49), Vector3(0, 1.0, 38.5), 55.0)
	await _shot("wear_lineup.png")
	# Each villager alone: the head close, then the whole figure.
	for i in models.size():
		for j in models.size():
			models[j].visible = j == i
		var at := models[i].position
		var head_y := models[i].head_height() * 0.93
		_look(at + Vector3(0.45, head_y + 0.08, 1.15), at + Vector3(0, head_y, 0), 32.0)
		await _shot("wear_head_%02d.png" % i)
		_look(at + Vector3(0.9, 1.3, 3.4), at + Vector3(0, 0.9, 0), 38.0)
		await _shot("wear_body_%02d.png" % i)
	for m in models:
		m.visible = true


## A lineup of generated villagers in different outfits, ages and poses.
func _people() -> void:
	var w := WorldGenerator.generate("gallery")
	var picks: Array[CharacterData] = []
	var seen := {}
	for c in w.characters:
		var key := str(c.occupation().get("outfit", "")) + ("child" if c.age < 14 else "") + c.gender
		if not seen.has(key):
			seen[key] = true
			picks.append(c)
	picks = picks.slice(0, 12)
	var modes := ["idle", "walk", "work", "talk"]
	var models: Array[CharacterModel] = []
	for i in picks.size():
		var m := HumanModel.for_character(picks[i])
		add_child(m)
		m.position = Vector3(-11.0 + i * 2.0, 0, 40)
		m.rotation.y = PI  # face the camera (and the sun)
		models.append(m)
	for f in 40:
		for i in models.size():
			models[i].animate(modes[i % modes.size()], f * 0.1, 1.0 / 30.0)
	_look(Vector3(0, 2.2, 49), Vector3(0, 1.1, 40), 60.0)
	await _shot("people_lineup.png")
	_look(Vector3(-5, 1.7, 44.5), Vector3(-5, 1.3, 40), 45.0)
	await _shot("people_close.png")
	_look(Vector3(5, 1.7, 44.5), Vector3(5, 1.3, 40), 45.0)
	await _shot("people_close2.png")
	_look(Vector3(-3, 1.6, 42.4), Vector3(-3, 1.55, 40), 30.0)
	await _shot("people_face.png")
	for i in picks.size():
		print("%d %s %s age %d %s %s hair=%s %s" % [i, picks[i].full_name(), picks[i].gender, picks[i].age, picks[i].occupation_id, picks[i].occupation().get("outfit", ""), picks[i].appearance.get("hair_style", ""), modes[i % modes.size()]])


## Every Stylized Nature MegaKit model, one row per group, labelled.
func _nature() -> void:
	var dir := "res://3D/environments/quaternius-stylized-nature-standard/models/"
	var rows := {"trees": [], "plants": [], "rocks": []}
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gltf"):
			continue
		var n := f.get_basename()
		var group := "plants"
		if n.contains("Tree") or n.begins_with("Pine"):
			group = "trees"
		elif n.begins_with("Rock") or n.begins_with("Pebble"):
			group = "rocks"
		rows[group].append(n)
	var z := 60.0
	for group: String in ["trees", "plants", "rocks"]:
		var names: Array = rows[group]
		var step := 4.5 if group == "trees" else 2.2
		for i in names.size():
			var inst := (load(dir + names[i] + ".gltf") as PackedScene).instantiate() as Node3D
			add_child(inst)
			inst.position = Vector3((i - names.size() * 0.5) * step, 0, z)
			var label := Label3D.new()
			label.text = str(names[i]).replace("_", "\n")
			label.font_size = 48 if group == "trees" else 28
			label.pixel_size = 0.004
			label.position = inst.position + Vector3(0, -0.4, 1.6)
			label.rotation.x = -0.6
			add_child(label)
		var width := names.size() * step
		_look(Vector3(0, 6.0 if group == "trees" else 2.6, z + width * 0.55), Vector3(0, 2.6 if group == "trees" else 0.5, z), 60.0)
		await _shot("nature_%s.png" % group)
		z += 40.0


## Every Fantasy Props MegaKit model in rows of 12, seen from +Z (the side a
## prop shows when unrotated). Prints the grid order.
func _props() -> void:
	var dir := "res://3D/props/quaternius-fantasy-props-standard/models/"
	var names: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gltf"):
			names.append(f.get_basename())
	names.sort()
	var per_row := 12
	for i in names.size():
		var inst := (load(dir + names[i] + ".gltf") as PackedScene).instantiate() as Node3D
		add_child(inst)
		inst.position = Vector3((i % per_row - per_row * 0.5) * 3.2, 0, 80.0 - floori(float(i) / per_row) * 4.0)
		print("%d %s" % [i, names[i]])
	var rows := ceili(float(names.size()) / per_row)
	for r in rows:
		_look(Vector3(0, 3.2, 80.0 - r * 4.0 + 10.5), Vector3(0, 0.6, 80.0 - r * 4.0), 70.0)
		await _shot("props_row_%d.png" % r)

