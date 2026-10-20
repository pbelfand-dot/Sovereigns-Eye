class_name TerrainHeight
extends RefCounted
## Single source of truth for ground height, shared by the terrain mesh,
## roads, trees and walking NPCs so everything sits on the same surface.
##
## The village core is flat (easy building + pathing); rolling hills rise
## beyond `flat_radius`. A future world generator can replace this with a
## heightmap without touching callers.

static var _noise: FastNoiseLite
static var _detail: FastNoiseLite
static var _flat_radius: float = 92.0
## Ground levelled to the village's height (a castle's site, Phase 5.3):
## [{inv: Transform3D (world -> the pad's frame), rect: Rect2 (x, z),
## blend: metres it eases back into the hills}].
static var _pads: Array = []


static func configure(terrain_seed: int, flat_radius: float) -> void:
	_flat_radius = flat_radius
	_pads = []
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.seed = terrain_seed + 17
	_detail.frequency = 0.05


## Levelled ground for the world now loaded (CastleSystem.pads); [] for none.
static func set_pads(pads: Array) -> void:
	_pads = pads


static func height_at(x: float, z: float) -> float:
	if _noise == null:
		return 0.0
	var d := Vector2(x, z).length()
	var t := smoothstep(_flat_radius - 4.0, _flat_radius + 34.0, d)
	if t <= 0.0:
		return 0.0
	var hills := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 11.0
	var h := t * (hills + 1.5) + t * _detail.get_noise_2d(x, z) * 0.6
	for pad: Dictionary in _pads:
		var l: Vector3 = (pad["inv"] as Transform3D) * Vector3(x, 0.0, z)
		var r: Rect2 = pad["rect"]
		var dx := maxf(maxf(r.position.x - l.x, l.x - r.end.x), 0.0)
		var dz := maxf(maxf(r.position.y - l.z, l.z - r.end.y), 0.0)
		var out := Vector2(dx, dz).length()
		h = lerpf(h, 0.0, 1.0 - smoothstep(0.0, float(pad["blend"]), out))
	return h


static func on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


## Grass tint variation (0..1) for terrain coloring.
static func grass_variation(x: float, z: float) -> float:
	if _detail == null:
		return 0.5
	return _detail.get_noise_2d(x * 0.6, z * 0.6) * 0.5 + 0.5
