class_name GroundWear
extends RefCounted
## Bakes where feet and carts wear the grass down (along roads, around the
## square, at doorsteps and field edges) into a small greyscale mask that the
## meadow shader reads. Same layout, same mask.


## Returns an R8 image covering origin .. origin + size (meters, x/z) at
## `res` x `res` pixels. 255 = bare trodden earth, 0 = untouched grass.
## `extra` adds building sites that aren't in the layout yet.
static func bake(layout: VillageLayout, origin: Vector2, size: float, res: int, cfg: Dictionary, extra: Array[BuildingData] = []) -> Image:
	var px := size / res
	var data := PackedFloat32Array()
	data.resize(res * res)
	var road_margin := float(cfg.get("road_margin", 1.8))
	for road in layout.roads:
		var half := float(road["width"]) * 0.5
		var pts: PackedVector3Array = road["points"]
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1].x, pts[i - 1].z)
			var b := Vector2(pts[i].x, pts[i].z)
			var steps := maxi(1, ceili(a.distance_to(b) / px))
			for s in steps + 1:
				_stamp(data, res, origin, px, a.lerp(b, float(s) / steps), half, half + road_margin)
	var sq := Vector2(layout.square_center.x, layout.square_center.z)
	_stamp(data, res, origin, px, sq, layout.square_radius, layout.square_radius + float(cfg.get("square_margin", 3.5)))
	var wall_margin := float(cfg.get("building_margin", 1.6))
	var door_path := float(cfg.get("door_path", 4.0))
	for b in layout.buildings + extra:
		_stamp_rect(data, res, origin, px, Vector2(b.position.x, b.position.z), b.rotation, b.footprint * 0.5, wall_margin)
		var door := b.door_position()
		_stamp(data, res, origin, px, Vector2(door.x, door.z), 0.6, 0.6 + door_path * 0.5)
	var field_margin := float(cfg.get("field_margin", 0.9))
	for f in layout.fields:
		var c: Vector3 = f["center"]
		var half_size: Vector2 = (f["size"] as Vector2) * 0.5 + Vector2(0.4, 0.4)
		_stamp_rect(data, res, origin, px, Vector2(c.x, c.z), float(f["rot"]), half_size, field_margin)
	# Yards drilled on (the training yard): trodden over their whole footprint.
	var yards: Dictionary = cfg.get("yards", {})
	for p: Dictionary in layout.props:
		if yards.has(p["type"]) and VillageLayoutGenerator.YARD_HALF.has(p["type"]):
			var pos: Vector3 = p["pos"]
			_stamp_rect(data, res, origin, px, Vector2(pos.x, pos.z), float(p["rot"]), VillageLayoutGenerator.YARD_HALF[p["type"]], float(cfg.get("yard_margin", 1.0)), float(yards[p["type"]]))
	var bytes := PackedByteArray()
	bytes.resize(res * res)
	for i in data.size():
		bytes[i] = int(clampf(data[i], 0.0, 1.0) * 255.0)
	return Image.create_from_data(res, res, false, Image.FORMAT_R8, bytes)


## Wear at a world point (0..1), read back from a baked mask.
static func sample(mask: Image, origin: Vector2, size: float, p: Vector2) -> float:
	var res := mask.get_width()
	var ix := clampi(int((p.x - origin.x) / size * res), 0, res - 1)
	var iz := clampi(int((p.y - origin.y) / size * res), 0, res - 1)
	return mask.get_pixel(ix, iz).r


## Round patch: full wear inside `inner`, fading out by `outer`.
static func _stamp(data: PackedFloat32Array, res: int, origin: Vector2, px: float, center: Vector2, inner: float, outer: float) -> void:
	var lo := ((center - Vector2(outer, outer) - origin) / px).floor()
	var hi := ((center + Vector2(outer, outer) - origin) / px).ceil()
	for iz in range(maxi(int(lo.y), 0), mini(int(hi.y), res - 1) + 1):
		for ix in range(maxi(int(lo.x), 0), mini(int(hi.x), res - 1) + 1):
			var w := origin + Vector2(ix + 0.5, iz + 0.5) * px
			var v := 1.0 - smoothstep(inner, outer, w.distance_to(center))
			var k := iz * res + ix
			if v > data[k]:
				data[k] = v


## Rotated rectangle (yaw like BuildingData.rotation) worn out to `margin`,
## `strength` at most (1: bare earth).
static func _stamp_rect(data: PackedFloat32Array, res: int, origin: Vector2, px: float, center: Vector2, yaw: float, half: Vector2, margin: float, strength: float = 1.0) -> void:
	var reach := half.length() + margin
	var lo := ((center - Vector2(reach, reach) - origin) / px).floor()
	var hi := ((center + Vector2(reach, reach) - origin) / px).ceil()
	var inv := Basis(Vector3.UP, -yaw)
	for iz in range(maxi(int(lo.y), 0), mini(int(hi.y), res - 1) + 1):
		for ix in range(maxi(int(lo.x), 0), mini(int(hi.x), res - 1) + 1):
			var w := origin + Vector2(ix + 0.5, iz + 0.5) * px - center
			var local := inv * Vector3(w.x, 0.0, w.y)
			var q := Vector2(absf(local.x) - half.x, absf(local.z) - half.y)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
			var v := (1.0 - smoothstep(0.0, margin, d)) * strength
			var k := iz * res + ix
			if v > data[k]:
				data[k] = v
