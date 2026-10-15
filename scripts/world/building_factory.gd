class_name BuildingFactory
extends RefCounted
## Builds the 3D look of a building.
##
## If the building type in data/buildings.json has a "model" path that exists,
## that scene/model is used. Otherwise a stylized placeholder is assembled from
## primitives. Either way the result is a plain Node3D, so game logic never
## depends on which one was used. The door is always on local +Z.

const PLINTH := 0.3


static func build(b: BuildingData) -> Node3D:
	var root := Node3D.new()
	root.name = "Building_%d" % b.id
	root.position = TerrainHeight.on_ground(b.position)
	root.rotation.y = b.rotation
	var def := b.type_def()
	if VillageKit.has_prefab(b.type):
		var kit := _build_kit(root, b)
		if kit:
			return root
	var model_path := str(def.get("model", ""))
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path)
		if packed:
			var model := packed.instantiate()
			if model is Node3D:
				var s := float(def.get("model_scale", 1.0))
				var off: Array = def.get("model_offset", [0, 0, 0])
				model.scale = Vector3.ONE * s
				model.position = Vector3(float(off[0]), float(off[1]), float(off[2]))
			root.add_child(model)
			return root
	_build_primitive(root, b, def)
	return root


## Quaternius kit building: shared prefab meshes + box collision proxies.
static func _build_kit(root: Node3D, b: BuildingData) -> bool:
	var p := VillageKit.prefab(b.type, b.variant, b.tier)
	if p.is_empty() or (p["shell"] as ArrayMesh).get_surface_count() == 0:
		return false
	# Sit on the lowest corner so no wall floats above sloping ground.
	var lowest := INF
	for k in 5:
		var corner := Vector3.ZERO if k == 4 else Vector3((-1 if k % 2 == 0 else 1) * b.footprint.x * 0.5, 0, (-1 if k < 2 else 1) * b.footprint.y * 0.5)
		var wp := b.position + b.basis() * corner
		lowest = minf(lowest, TerrainHeight.height_at(wp.x, wp.z))
	root.position.y = lowest - 0.05
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = p["shell"]
	root.add_child(shell)
	var details_mesh: ArrayMesh = p["details"]
	if details_mesh.get_surface_count() > 0:
		var details := MeshInstance3D.new()
		details.name = "Details"
		details.mesh = details_mesh
		details.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		details.visibility_range_end = float(VillageKit.config().get("detail_range", 90.0))
		details.visibility_range_end_margin = 8.0
		root.add_child(details)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 2
	body.collision_mask = 0
	for box: AABB in p["boxes"]:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box.size
		shape.shape = bs
		shape.position = box.get_center()
		body.add_child(shape)
	root.add_child(body)
	if p["sails"]:
		_kit_sails(root, p)
	return true


static func _kit_sails(root: Node3D, p: Dictionary) -> void:
	# The kit has no windmill: simple boards in the kit's own wood material.
	var wood: Material = VillageKit.material_named("MI_WoodTrim")
	var trim: Material = wood if wood else Mats.hex("#5a3d2b")
	var hub := Node3D.new()
	hub.set_script(load("res://scripts/world/spinner.gd"))
	hub.position = Vector3(0, float(p["height"]) - 4.6, 2.55)
	root.add_child(hub)
	Mats.cylinder(hub, 0.3, 0.3, 0.6, Vector3.ZERO, trim, 8, Vector3(PI * 0.5, 0, 0))
	var sail := Mats.hex("#e9dfc8")
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = i * PI * 0.5
		hub.add_child(arm)
		Mats.box(arm, Vector3(0.2, 5.6, 0.14), Vector3(0, 2.9, 0.2), trim)
		Mats.box(arm, Vector3(1.3, 4.2, 0.05), Vector3(0.7, 3.4, 0.26), sail)


static func _pick(list: Array, variant: int, fallback: String) -> Color:
	if list.is_empty():
		return Color(fallback)
	return Color(str(list[variant % list.size()]))


static func _build_primitive(root: Node3D, b: BuildingData, def: Dictionary) -> void:
	var w := b.footprint.x
	var d := b.footprint.y
	var h := float(def.get("wall_height", 3.0))
	var wall := Mats.color(_pick(def.get("walls", []), b.variant, "#e0d0b0"))
	var roof := Mats.color(_pick(def.get("roofs", []), b.variant >> 1, "#8f4e31"))
	var trim := Mats.hex(str(def.get("trim", "#5a3d2b")))
	var stone := Mats.hex("#8e8a80")
	match str(def.get("style", "timber")):
		"manor":
			_manor(root, w, d, h, wall, roof, trim, stone)
		"chapel":
			_chapel(root, w, d, h, wall, roof, trim, stone)
		"smithy":
			_smithy(root, w, d, h, wall, roof, trim, stone)
		"windmill":
			_windmill(root, w, h, wall, roof, trim, stone)
		"barracks":
			_house(root, w, d, h, wall, roof, trim, stone, {"timber": false, "windows": 4, "roof_ratio": 0.35})
			_crenellate(root, w, d, h, stone)
		"barn":
			_house(root, w, d, h, wall, roof, trim, stone, {"timber": true, "windows": 0, "barn_door": true})
		"bakery":
			_house(root, w, d, h, wall, roof, trim, stone, {"timber": true, "windows": 1, "chimney": true})
			Mats.sphere(root, 1.1, Vector3(w * 0.5 + 0.7, PLINTH - 0.2, -d * 0.15), Mats.hex("#a0583a"), Vector3(1, 0.9, 1))
			Mats.box(root, Vector3(0.4, 1.2, 0.4), Vector3(w * 0.5 + 0.9, PLINTH + 1.0, -d * 0.15 - 0.4), stone)
		"workshop":
			_house(root, w, d, h, wall, roof, trim, stone, {"timber": true, "windows": 1, "barn_door": true})
		_:
			var floors := 2 if h > 4.5 else 1
			_house(root, w, d, h, wall, roof, trim, stone, {"timber": true, "windows": 2, "floors": floors, "chimney": true})
			if b.type == "tavern":
				_tavern_sign(root, w, d)


## Generic house: plinth, walls, gable roof, door, windows, optional timber frame.
static func _house(root: Node3D, w: float, d: float, h: float, wall: Material, roof: Material, trim: Material, stone: Material, opts: Dictionary) -> void:
	Mats.box(root, Vector3(w + 0.3, PLINTH, d + 0.3), Vector3(0, PLINTH * 0.5, 0), stone)
	Mats.box(root, Vector3(w, h, d), Vector3(0, PLINTH + h * 0.5, 0), wall)
	_gable_roof(root, w, d, PLINTH + h, roof, float(opts.get("roof_ratio", 0.55)))
	if opts.get("barn_door", false):
		Mats.box(root, Vector3(minf(3.2, w * 0.45), minf(2.8, h - 0.3), 0.14), Vector3(0, PLINTH + minf(2.8, h - 0.3) * 0.5, d * 0.5 + 0.05), trim)
	else:
		Mats.box(root, Vector3(1.1, 1.95, 0.14), Vector3(0, PLINTH + 0.98, d * 0.5 + 0.05), trim)
	var floors := int(opts.get("floors", 1))
	var per_side := int(opts.get("windows", 2))
	for f in floors:
		var y := PLINTH + 1.55 + f * 2.4
		for i in per_side:
			var x := (float(i) + 1.0) / (per_side + 1.0) * w - w * 0.5
			if absf(x) < 1.0 and f == 0:
				x += signf(x if x != 0.0 else 1.0) * 1.3
			Mats.box(root, Vector3(0.75, 0.75, 0.1), Vector3(x, y, d * 0.5 + 0.04), Mats.window())
			Mats.box(root, Vector3(0.75, 0.75, 0.1), Vector3(x, y, -d * 0.5 - 0.04), Mats.window())
		if per_side > 0:
			Mats.box(root, Vector3(0.1, 0.75, 0.75), Vector3(w * 0.5 + 0.04, y, 0), Mats.window())
			Mats.box(root, Vector3(0.1, 0.75, 0.75), Vector3(-w * 0.5 - 0.04, y, 0), Mats.window())
	if opts.get("timber", false):
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				Mats.box(root, Vector3(0.22, h, 0.22), Vector3(sx * w * 0.5, PLINTH + h * 0.5, sz * d * 0.5), trim)
		for f in range(1, floors + 1):
			var by := PLINTH + minf(h, f * 2.6) - 0.1
			Mats.box(root, Vector3(w + 0.06, 0.18, 0.06), Vector3(0, by, d * 0.5 + 0.06), trim)
			Mats.box(root, Vector3(w + 0.06, 0.18, 0.06), Vector3(0, by, -d * 0.5 - 0.06), trim)
	if opts.get("chimney", false):
		Mats.box(root, Vector3(0.6, 2.2, 0.6), Vector3(w * 0.3, PLINTH + h + 0.8, -d * 0.15), stone)


## Gable roof whose ridge runs along the longer side.
static func _gable_roof(root: Node3D, w: float, d: float, base_y: float, mat: Material, ratio: float) -> void:
	var overhang := 0.8
	var roof_h := minf(w, d) * ratio
	if w >= d:
		Mats.add_mesh(root, Mats.prism_mesh(Vector3(d + overhang, roof_h, w + overhang)), mat,
			Vector3(0, base_y + roof_h * 0.5, 0), Vector3(0, PI * 0.5, 0))
	else:
		Mats.add_mesh(root, Mats.prism_mesh(Vector3(w + overhang, roof_h, d + overhang)), mat,
			Vector3(0, base_y + roof_h * 0.5, 0))


static func _crenellate(root: Node3D, w: float, d: float, h: float, stone: Material) -> void:
	var y := PLINTH + h + 0.35
	var count := int(w / 1.6)
	for i in count:
		var x := -w * 0.5 + 0.5 + i * (w - 1.0) / maxf(1.0, count - 1)
		Mats.box(root, Vector3(0.6, 0.7, 0.4), Vector3(x, y, d * 0.5 - 0.2), stone)


static func _manor(root: Node3D, w: float, d: float, h: float, wall: Material, roof: Material, trim: Material, stone: Material) -> void:
	_house(root, w, d, h, wall, roof, trim, stone, {"timber": false, "windows": 4, "floors": 2, "chimney": true, "roof_ratio": 0.45})
	# Corner towers with conical roofs
	for sx: float in [-1.0, 1.0]:
		var tx := sx * (w * 0.5)
		var tz := d * 0.5 - 0.5
		Mats.cylinder(root, 1.9, 2.1, h + 3.0, Vector3(tx, PLINTH + (h + 3.0) * 0.5, tz), wall, 14)
		Mats.cylinder(root, 0.0, 2.5, 3.6, Vector3(tx, PLINTH + h + 3.0 + 1.8, tz), roof, 14)
		Mats.box(root, Vector3(0.6, 0.9, 0.1), Vector3(tx, PLINTH + h + 1.0, tz + 2.0), Mats.window())
	# Portico
	for sx: float in [-1.0, 1.0]:
		Mats.cylinder(root, 0.25, 0.3, 3.4, Vector3(sx * 1.6, PLINTH + 1.7, d * 0.5 + 1.6), Mats.hex("#d8d2c4"), 10)
	Mats.box(root, Vector3(4.2, 0.4, 2.4), Vector3(0, PLINTH + 3.5, d * 0.5 + 1.0), roof)
	Mats.box(root, Vector3(5.0, 0.2, 3.4), Vector3(0, 0.1, d * 0.5 + 1.4), stone)


static func _chapel(root: Node3D, w: float, d: float, h: float, wall: Material, roof: Material, trim: Material, stone: Material) -> void:
	_house(root, w, d, h, wall, roof, trim, stone, {"timber": false, "windows": 3, "roof_ratio": 0.8})
	# Bell tower over the entrance
	var tw := 3.0
	var th := h + 5.5
	var tz := d * 0.5 - tw * 0.5
	Mats.box(root, Vector3(tw, th, tw), Vector3(0, PLINTH + th * 0.5, tz), wall)
	Mats.cylinder(root, 0.0, tw * 0.78, 3.8, Vector3(0, PLINTH + th + 1.9, tz), roof, 4, Vector3(0, PI * 0.25, 0))
	Mats.box(root, Vector3(0.9, 1.3, 0.1), Vector3(0, PLINTH + th - 1.4, tz + tw * 0.5 + 0.05), Mats.hex("#2a2a2a"))
	var gold := Mats.metal(Color("#d9b04a"))
	Mats.box(root, Vector3(0.14, 1.2, 0.14), Vector3(0, PLINTH + th + 4.3, tz), gold)
	Mats.box(root, Vector3(0.7, 0.14, 0.14), Vector3(0, PLINTH + th + 4.5, tz), gold)


static func _smithy(root: Node3D, w: float, d: float, h: float, wall: Material, roof: Material, trim: Material, stone: Material) -> void:
	Mats.box(root, Vector3(w + 0.3, PLINTH, d + 0.3), Vector3(0, PLINTH * 0.5, 0), stone)
	# Back and side walls only: an open-fronted forge.
	Mats.box(root, Vector3(w, h, 0.4), Vector3(0, PLINTH + h * 0.5, -d * 0.5 + 0.2), wall)
	Mats.box(root, Vector3(0.4, h, d), Vector3(-w * 0.5 + 0.2, PLINTH + h * 0.5, 0), wall)
	Mats.box(root, Vector3(0.4, h, d), Vector3(w * 0.5 - 0.2, PLINTH + h * 0.5, 0), wall)
	for sx: float in [-1.0, 1.0]:
		Mats.box(root, Vector3(0.3, h, 0.3), Vector3(sx * (w * 0.5 - 0.2), PLINTH + h * 0.5, d * 0.5 - 0.2), trim)
	_gable_roof(root, w, d, PLINTH + h, roof, 0.45)
	# Forge with glowing coals, chimney and anvil
	Mats.box(root, Vector3(2.2, 1.1, 1.6), Vector3(-w * 0.2, PLINTH + 0.55, -d * 0.25), stone)
	Mats.box(root, Vector3(1.6, 0.12, 1.0), Vector3(-w * 0.2, PLINTH + 1.12, -d * 0.25), Mats.emissive(Color("#ff6a1a"), 3.0))
	Mats.box(root, Vector3(1.0, h + 1.6, 1.0), Vector3(-w * 0.2, PLINTH + (h + 1.6) * 0.5, -d * 0.5 + 0.5), stone)
	Mats.box(root, Vector3(0.5, 0.6, 0.4), Vector3(w * 0.15, PLINTH + 0.3, d * 0.1), Mats.hex("#4a3a2c"))
	Mats.box(root, Vector3(0.9, 0.25, 0.35), Vector3(w * 0.15, PLINTH + 0.72, d * 0.1), Mats.metal(Color("#3a3d42")))


static func _windmill(root: Node3D, w: float, h: float, wall: Material, roof: Material, trim: Material, stone: Material) -> void:
	var r := w * 0.42
	Mats.cylinder(root, r * 0.75, r, h, Vector3(0, h * 0.5, 0), wall, 12)
	Mats.cylinder(root, 0.0, r * 0.95, 2.6, Vector3(0, h + 1.3, 0), roof, 12)
	Mats.box(root, Vector3(1.1, 1.9, 0.2), Vector3(0, 0.95, r - 0.05), trim)
	Mats.box(root, Vector3(0.7, 0.7, 0.1), Vector3(0, h * 0.6, r * 0.82), Mats.window())
	# Sails turn slowly (Spinner script).
	var hub := Node3D.new()
	hub.set_script(load("res://scripts/world/spinner.gd"))
	hub.position = Vector3(0, h - 0.6, r * 0.8 + 0.5)
	root.add_child(hub)
	Mats.cylinder(hub, 0.3, 0.3, 0.6, Vector3.ZERO, trim, 8, Vector3(PI * 0.5, 0, 0))
	var sail := Mats.hex("#efe6d2")
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = i * PI * 0.5
		hub.add_child(arm)
		Mats.box(arm, Vector3(0.18, 5.6, 0.12), Vector3(0, 2.9, 0.2), trim)
		Mats.box(arm, Vector3(1.2, 4.2, 0.05), Vector3(0.65, 3.4, 0.26), sail)


static func _tavern_sign(root: Node3D, w: float, d: float) -> void:
	var trim := Mats.hex("#4a3424")
	Mats.box(root, Vector3(0.12, 0.12, 1.2), Vector3(1.6, 2.9, d * 0.5 + 0.6), trim)
	Mats.box(root, Vector3(0.9, 0.7, 0.08), Vector3(1.6, 2.4, d * 0.5 + 1.05), Mats.hex("#b8873e"))
