class_name BuildGhost
extends Node3D
## Translucent preview of a building being placed from the Build menu: the
## real building's shape tinted green (fits) or red (doesn't), its footprint,
## the lane that will be laid to the road and the trees that will be felled.

var type := ""
var _body: MeshInstance3D
var _pad: MeshInstance3D
var _lane: MeshInstance3D
var _marks: MultiMeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _lane_mat: StandardMaterial3D


func _init() -> void:
	name = "BuildGhost"
	_ok_mat = _tint(Color(0.45, 0.95, 0.45, 0.42))
	_bad_mat = _tint(Color(1.0, 0.32, 0.25, 0.42))
	_lane_mat = _tint(Color(0.95, 0.85, 0.55, 0.5))


static func _tint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func setup(building_type: String) -> void:
	type = building_type
	var fp := TerritorySystem.footprint(type)
	_body = MeshInstance3D.new()
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if VillageKit.has_prefab(type):
		_body.mesh = VillageKit.prefab(type, 0).get("shell", null)
	if _body.mesh == null or (_body.mesh as Mesh).get_surface_count() == 0:
		var h := float(GameData.building_type(type).get("wall_height", 3.0)) + 1.5
		_body.mesh = Mats.box_mesh(Vector3(fp.x, h, fp.y))
		_body.position.y = h * 0.5
	add_child(_body)
	_pad = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = fp + Vector2(1.2, 1.2)
	_pad.mesh = plane
	_pad.position.y = 0.12
	_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pad)
	_lane = MeshInstance3D.new()
	_lane.material_override = _lane_mat
	_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lane.top_level = true
	add_child(_lane)
	_marks = MultiMeshInstance3D.new()
	_marks.top_level = true
	_marks.material_override = _bad_mat
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marks)


## Moves the preview and colors it from a TerritorySystem.check_placement() result.
func show_at(pos: Vector3, rot: float, check: Dictionary, trees: Array[Vector4]) -> void:
	position = TerrainHeight.on_ground(pos)
	rotation.y = rot
	var mat := _ok_mat if bool(check.get("ok", false)) else _bad_mat
	_body.material_override = mat
	_pad.material_override = mat
	var lane: PackedVector3Array = check.get("lane", PackedVector3Array())
	_lane.mesh = _ribbon(lane, float(TerritorySystem.section("placement").get("lane_width", 3.0))) if lane.size() >= 2 else null
	var felled: Array = check.get("trees", [])
	if felled.is_empty():
		_marks.multimesh = null
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Mats.cylinder_mesh(0.9, 0.9, 0.08, 12)
	mm.instance_count = felled.size()
	for i in felled.size():
		var t := trees[int(felled[i])]
		mm.set_instance_transform(i, Transform3D(Basis(), TerrainHeight.on_ground(Vector3(t.x, 0, t.y)) + Vector3(0, 0.15, 0)))
	_marks.multimesh = mm


static func _ribbon(points: PackedVector3Array, width: float) -> ArrayMesh:
	var pts := VillageBuilder._resample(points, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var side := Vector3(-(b - a).normalized().z, 0, (b - a).normalized().x) * width * 0.5
		var lift := Vector3(0, 0.14, 0)
		var a0 := TerrainHeight.on_ground(a - side) + lift
		var a1 := TerrainHeight.on_ground(a + side) + lift
		var b0 := TerrainHeight.on_ground(b - side) + lift
		var b1 := TerrainHeight.on_ground(b + side) + lift
		for v in [a0, b0, a1, a1, b0, b1]:
			st.add_vertex(v)
	return st.commit()
