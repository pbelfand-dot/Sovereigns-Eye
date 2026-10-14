class_name ConstructionView
extends Node3D
## How a building site looks as the work goes on (data: ConstructionSite):
##   0 - 12%    staked-out ground: a dirt pad, corner stakes and string lines,
##              with timber and stone piled beside it
##   12 - 100%  the walls rise piece by piece from the ground up, inside a
##              scaffold that climbs with them; the roof goes on last
## Kit buildings re-assemble their prefab's own pieces (VillageKit "parts")
## in height order, so the site turns into exactly the finished building.
## Primitive buildings rise as a plain block. The look only changes in a few
## steps (data/territory.json "visual_steps"), so a site costs almost nothing
## per frame.

const STAKE_UNTIL := 0.12
const WOOD := "#a2794b"
const DARK_WOOD := "#6e5034"

var site: ConstructionSite
var _steps := 14
var _shown := -1
var _pieces: Array = []      # [module, Transform3D] sorted bottom-up
var _top := 4.0
var _structure: MeshInstance3D
var _scaffold: MeshInstance3D
var _stakes: Node3D
var _piles: Node3D


func setup(s: ConstructionSite) -> void:
	site = s
	var b := s.building
	name = "Site_%d" % b.id
	position = TerrainHeight.on_ground(b.position) - Vector3(0, 0.05, 0)
	rotation.y = b.rotation
	_steps = maxi(2, int(TerritorySystem.section("construction").get("visual_steps", 14)))
	_top = float(b.type_def().get("wall_height", 3.0)) + 2.0
	if VillageKit.has_prefab(b.type):
		var p := VillageKit.prefab(b.type, b.variant)
		_pieces = (p.get("parts", []) as Array).duplicate()
		_pieces.sort_custom(func(x: Array, y: Array) -> bool: return piece_order(x) < piece_order(y))
		_top = float(p.get("height", _top))
	_build_ground()
	_build_piles()
	_structure = MeshInstance3D.new()
	_structure.name = "Structure"
	add_child(_structure)
	_scaffold = MeshInstance3D.new()
	_scaffold.name = "Scaffold"
	add_child(_scaffold)
	set_progress(s.progress())


## Sort key: lower pieces first; around each course in turn.
static func piece_order(part: Array) -> float:
	var o: Vector3 = (part[1] as Transform3D).origin
	return snappedf(o.y, 0.5) * 1000.0 + fposmod(atan2(o.z, o.x), TAU)


## How many pieces are standing at this progress.
static func pieces_shown(progress: float, total: int) -> int:
	if progress < STAKE_UNTIL:
		return 0
	if progress >= 1.0:
		return total
	return clampi(ceili((progress - STAKE_UNTIL) / (1.0 - STAKE_UNTIL) * total), 1, total)


func set_progress(progress: float) -> void:
	var step := clampi(floori(progress * _steps), 0, _steps)
	if step == _shown:
		return
	_shown = step
	var p := float(step) / _steps
	_stakes.visible = p < STAKE_UNTIL + 0.2
	_piles.visible = p < 0.9
	var height := 0.0
	if not _pieces.is_empty():
		var n := pieces_shown(p, _pieces.size())
		_structure.mesh = VillageKit.assemble(_pieces.slice(0, n)) if n > 0 else null
		if n > 0:
			height = (_pieces[n - 1][1] as Transform3D).origin.y + 2.2
	else:
		_structure.mesh = _block_mesh(p)
		height = _top * clampf((p - STAKE_UNTIL) / (1.0 - STAKE_UNTIL), 0.0, 1.0)
	var scaffold_h := minf(height + 1.0, _top - 1.0)
	_scaffold.mesh = _scaffold_mesh(scaffold_h) if p >= STAKE_UNTIL and p < 1.0 and scaffold_h > 0.8 else null


func _build_ground() -> void:
	var fp := site.building.footprint
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	pad.mesh = Mats.box_mesh(Vector3(fp.x + 1.2, 0.12, fp.y + 1.2))
	pad.material_override = Mats.hex("#7b6248")
	pad.position.y = 0.06
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)
	_stakes = Node3D.new()
	_stakes.name = "Stakes"
	add_child(_stakes)
	var wood := Mats.hex(WOOD)
	var string := Mats.hex("#e8dcc0")
	var hx := fp.x * 0.5
	var hz := fp.y * 0.5
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		Mats.box(_stakes, Vector3(0.1, 0.8, 0.1), a + Vector3(0, 0.4, 0), wood)
		var mid := (a + b) * 0.5
		var along := b - a
		Mats.box(_stakes, Vector3(0.025, 0.025, along.length()), mid + Vector3(0, 0.55, 0), string, Vector3(0, atan2(along.x, along.z), 0))


func _build_piles() -> void:
	var fp := site.building.footprint
	_piles = Node3D.new()
	_piles.name = "Piles"
	add_child(_piles)
	# Timber stacked along the left wall.
	var timber := Mats.hex("#8a6440")
	var lumber := Node3D.new()
	lumber.position = Vector3(-fp.x * 0.5 - 1.3, 0, -fp.y * 0.15)
	_piles.add_child(lumber)
	for i in 5:
		var row := int(i / 3.0)
		Mats.cylinder(lumber, 0.18, 0.18, minf(fp.y, 3.2), Vector3((i % 3) * 0.38 - 0.38 + row * 0.19, 0.18 + row * 0.33, 0), timber, 7, Vector3(PI * 0.5, 0, 0))
	# Cut stone along the right wall (kit brick piles when the kit is here).
	var stone_at := Vector3(fp.x * 0.5 + 1.2, 0, -fp.y * 0.2)
	var brick := VillageKit.module_mesh("Prop_Brick1") if VillageKit.available() else null
	if brick:
		Mats.add_mesh(_piles, brick, null, stone_at, Vector3(0, PI * 0.5, 0))
		var brick2 := VillageKit.module_mesh("Prop_Brick3")
		if brick2:
			Mats.add_mesh(_piles, brick2, null, stone_at + Vector3(0.1, 0, 1.1), Vector3(0, 0.3, 0))
	else:
		var stone := Mats.hex("#a7a196")
		for i in 4:
			Mats.box(_piles, Vector3(0.7, 0.35, 0.45), stone_at + Vector3((i % 2) * 0.75 - 0.37, 0.18 + int(i / 2.0) * 0.36, 0), stone)


## Poles around the walls with plank walkways every 1.5 m, up to `height`.
func _scaffold_mesh(height: float) -> ArrayMesh:
	var fp := site.building.footprint
	var hx := fp.x * 0.5 + 0.55
	var hz := fp.y * 0.5 + 0.55
	var boxes: Array = []  # [size, Transform3D]
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var pole_h := height + 0.8
	for side in 4:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[(side + 1) % 4]
		var length := a.distance_to(b)
		var posts := maxi(2, ceili(length / 2.4) + 1)
		for k in posts - 1:
			var p := a.lerp(b, float(k) / (posts - 1))
			boxes.append([Vector3(0.12, pole_h, 0.12), Transform3D(Basis(), p + Vector3(0, pole_h * 0.5, 0))])
		var yaw := atan2((b - a).x, (b - a).z)
		var level := 1.5
		while level <= height + 0.01:
			var out := (a + b) * 0.5 + Vector3(0, level, 0)
			boxes.append([Vector3(0.45, 0.06, length + 0.3), Transform3D(Basis(Vector3.UP, yaw), out)])
			level += 1.5
		# One diagonal brace per side.
		var brace_len := Vector2(minf(length, 2.4), minf(height, 2.4)).length()
		var tilt := atan2(minf(height, 2.4), minf(length, 2.4))
		var brace_mid := a.lerp(b, 0.5 * minf(2.4, length) / length) + Vector3(0, minf(height, 2.4) * 0.5, 0)
		boxes.append([Vector3(0.07, 0.07, brace_len), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt), brace_mid)])
	return _merge_boxes(boxes, Mats.hex(WOOD))


## Plain rising block for buildings without a kit prefab.
func _block_mesh(p: float) -> Mesh:
	var h := _top * clampf((p - STAKE_UNTIL) / (1.0 - STAKE_UNTIL), 0.0, 1.0)
	if h <= 0.05:
		return null
	var fp := site.building.footprint
	var def := site.building.type_def()
	var walls: Array = def.get("walls", ["#e0d0b0"])
	return _merge_boxes([[Vector3(fp.x, h, fp.y), Transform3D(Basis(), Vector3(0, h * 0.5, 0))]], Mats.hex(str(walls[0])))


static func _merge_boxes(boxes: Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Array in boxes:
		st.append_from(Mats.box_mesh(b[0]), 0, b[1])
	st.set_material(mat)
	return st.commit()
