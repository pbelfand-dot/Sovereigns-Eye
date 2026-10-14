class_name Mats
extends RefCounted
## Shared materials and meshes for primitive (placeholder) art.
##
## Everything is cached: two buildings with the same wall color share one
## material, which keeps draw calls and memory low as the world grows.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _window_material: StandardMaterial3D


static func color(c: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var key := "%s|%.2f" % [c.to_html(), roughness]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	_materials[key] = m
	return m


static func hex(h: String, roughness: float = 0.9) -> StandardMaterial3D:
	return color(Color.from_string(h, Color.MAGENTA), roughness)


static func metal(c: Color) -> StandardMaterial3D:
	var key := "metal|%s" % c.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.7
	m.roughness = 0.35
	_materials[key] = m
	return m


static func emissive(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "emit|%s|%.2f" % [c.to_html(), energy]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_materials[key] = m
	return m


## Material that colors each vertex / MultiMesh instance individually.
static func vertex_colored(roughness: float = 0.95) -> StandardMaterial3D:
	var key := "vcol|%.2f" % roughness
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	# Colors are written as sRGB hex codes, so convert them to linear.
	m.vertex_color_is_srgb = true
	m.roughness = roughness
	_materials[key] = m
	return m


## All windows share one material so the sky controller can light them at night.
static func window() -> StandardMaterial3D:
	if _window_material == null:
		_window_material = StandardMaterial3D.new()
		_window_material.albedo_color = Color("#3c4656")
		_window_material.emission_enabled = true
		_window_material.emission = Color("#ffbf5a")
		_window_material.emission_energy_multiplier = 0.0
	return _window_material


static func set_night_glow(amount: float) -> void:
	window().emission_energy_multiplier = amount * 2.2


# --- Cached meshes --------------------------------------------------------------

static func box_mesh(size: Vector3) -> BoxMesh:
	var key := "box|%s" % str(size)
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func cylinder_mesh(top: float, bottom: float, height: float, segments: int = 12) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top, bottom, height, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func sphere_mesh(radius: float, segments: int = 12, rings: int = 6) -> SphereMesh:
	var key := "sph|%.3f|%d|%d" % [radius, segments, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]


static func prism_mesh(size: Vector3) -> PrismMesh:
	var key := "prism|%s" % str(size)
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]


static func capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var key := "cap|%.3f|%.3f" % [radius, height]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 10
		m.rings = 4
		_meshes[key] = m
	return _meshes[key]


# --- Node helpers ------------------------------------------------------------------

static func add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return add_mesh(parent, box_mesh(size), mat, pos, rot)


static func cylinder(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material, segments: int = 12, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return add_mesh(parent, cylinder_mesh(top, bottom, height, segments), mat, pos, rot)


static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	return add_mesh(parent, sphere_mesh(radius), mat, pos, Vector3.ZERO, scale)
