extends RefCounted
## Measures a family's models the way its tests need: their triangles,
## where they cut a level plane, how far they reach along an axis within a
## band, a placed piece's ground plan. Used by the castle and harbour tests.

var dir: String
var _cache := {}


func _init(model_dir: String) -> void:
	dir = model_dir


## Every triangle of a model (three corners each), in its own frame.
func tris(model: String) -> PackedVector3Array:
	if _cache.has(model):
		return _cache[model]
	var out := PackedVector3Array()
	var root := (load(dir + model + ".glb") as PackedScene).instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i: int in arrays[Mesh.ARRAY_INDEX]:
				out.append(mi.transform * verts[i])
	root.free()
	_cache[model] = out
	return out


## Where a model's surfaces cut the level plane at height h: a segment
## [from, to] for each triangle crossing it.
func segments(model: String, h: float) -> Array:
	var t := tris(model)
	var out := []
	for i in range(0, t.size(), 3):
		var pts: Array[Vector3] = []
		for k in 3:
			var a := t[i + k]
			var b := t[i + (k + 1) % 3]
			if (a.y - h) * (b.y - h) < 0.0:
				pts.append(a.lerp(b, (h - a.y) / (b.y - a.y)))
		if pts.size() == 2:
			out.append(pts)
	return out


## The points of those segments.
func section(model: String, h: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for seg: Array in segments(model, h):
		out.append_array(PackedVector3Array(seg))
	return out


## How far a model reaches along `axis` (0 = x, 2 = z) at height h, within
## `band` of `center` on the other axis: the segments clipped to the band.
## (INF, -INF) when nothing is there.
func extent(model: String, h: float, axis: int, band: float = 1.2, center: float = 0.0) -> Vector2:
	var other := 2 - axis
	var lo := INF
	var hi := -INF
	for seg: Array in segments(model, h):
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var t0 := 0.0
		var t1 := 1.0
		var d := b[other] - a[other]
		if absf(d) < 1e-6:
			if absf(a[other] - center) > band:
				continue
		else:
			var ta := (center - band - a[other]) / d
			var tb := (center + band - a[other]) / d
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				continue
		for t in [t0, t1]:
			var v := a.lerp(b, t)
			lo = minf(lo, v[axis])
			hi = maxf(hi, v[axis])
	return Vector2(lo, hi)


## A placed piece [model, position, yaw]'s ground plan (x, z): its section
## at height h above its own origin, or (h = NAN) everything it has.
func plan(piece: Array, h: float = NAN) -> Rect2:
	var xf := Transform3D(Basis(Vector3.UP, float(piece[2])), piece[1])
	var pts := tris(str(piece[0])) if is_nan(h) else section(str(piece[0]), h)
	var r := Rect2()
	for i in pts.size():
		var w := xf * pts[i]
		r = Rect2(w.x, w.z, 0, 0) if i == 0 else r.expand(Vector2(w.x, w.z))
	return r
