class_name StyleUnifier
extends RefCounted
## Gives models from any source one consistent look.
##
## Replaces every surface material under a node with the unified toon shader,
## keeping the original base color/texture but pulling its colors toward the
## master palette in data/art_style.json. Asset packs, AI-generated meshes
## and the procedural primitives can then sit side by side.

const SHADER_PATH := "res://shaders/unified_toon.gdshader"

static var _shader: Shader
static var _palette: ImageTexture
static var _palette_size := 0
static var _cache: Dictionary = {}


static func _ensure() -> void:
	if _shader:
		return
	_shader = load(SHADER_PATH)
	var colors: Array = GameData.load_file("art_style").get("palette", ["#ffffff"])
	_palette_size = colors.size()
	var img := Image.create(_palette_size, 1, false, Image.FORMAT_RGBA8)
	for i in _palette_size:
		img.set_pixel(i, 0, Color(str(colors[i])))
	_palette = ImageTexture.create_from_image(img)


static func strength() -> float:
	return float(GameData.load_file("art_style").get("palette_strength", 0.85))


## Unified version of a material (cached so identical inputs share one material).
static func unify_material(source: Material) -> Material:
	_ensure()
	var color := Color.WHITE
	var tex: Texture2D = null
	var vertex_colors := false
	var vertex_srgb := false
	if source is BaseMaterial3D:
		var base := source as BaseMaterial3D
		color = base.albedo_color
		tex = base.albedo_texture
		vertex_colors = base.vertex_color_use_as_albedo
		vertex_srgb = base.vertex_color_is_srgb
	var key := "%s|%s|%s" % [color.to_html(), str(tex.get_rid()) if tex else "-", vertex_colors]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo_color", color)
	m.set_shader_parameter("use_texture", tex != null)
	m.set_shader_parameter("use_vertex_color", vertex_colors)
	m.set_shader_parameter("vertex_color_is_srgb", vertex_srgb)
	if tex:
		m.set_shader_parameter("albedo_texture", tex)
	m.set_shader_parameter("palette", _palette)
	m.set_shader_parameter("palette_size", _palette_size)
	m.set_shader_parameter("palette_strength", strength())
	_cache[key] = m
	return m


## Applies the unified look to every mesh under `root`.
static func apply(root: Node) -> void:
	for node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.material_override:
				mi.material_override = unify_material(mi.material_override)
				continue
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat:
					mi.set_surface_override_material(s, unify_material(mat))
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).material_override:
			var mmi := node as MultiMeshInstance3D
			mmi.material_override = unify_material(mmi.material_override)
