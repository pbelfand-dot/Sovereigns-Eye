class_name WorldGeometry
extends RefCounted
## What's solid in the village, for walking and for sight.
##
## Buildings (and the footprints of new building sites) are boxes nobody
## walks through; finished buildings also block the view. Tree trunks and
## props are small circles. Static and data-only, so tests can check paths
## and sightlines without a scene.


static func cfg() -> Dictionary:
	return GameData.load_file("controls")


## Buildings standing in the way: finished ones, plus new building sites.
static func solid_buildings(state: WorldState) -> Array[BuildingData]:
	var out: Array[BuildingData] = []
	out.append_array(state.layout.buildings)
	if state.territory:
		for s in state.territory.sites:
			if not s.is_upgrade():
				out.append(s.building)
	return out


## Point `p` pushed out of a box (building footprint grown by `radius`).
## Returns p unchanged when it isn't inside.
static func _out_of_box(b: BuildingData, p: Vector3, radius: float) -> Vector3:
	var basis := b.basis()
	var local := basis.inverse() * (p - b.position)
	var hx := b.footprint.x * 0.5 + radius
	var hz := b.footprint.y * 0.5 + radius
	if absf(local.x) >= hx or absf(local.z) >= hz:
		return p
	if hx - absf(local.x) < hz - absf(local.z):
		local.x = hx * (1.0 if local.x >= 0.0 else -1.0)
	else:
		local.z = hz * (1.0 if local.z >= 0.0 else -1.0)
	var out := b.position + basis * local
	return Vector3(out.x, p.y, out.z)


static func _out_of_circle(center: Vector2, r: float, p: Vector3) -> Vector3:
	var d := Vector2(p.x, p.z) - center
	var len := d.length()
	if len >= r:
		return p
	var dir := d / len if len > 0.0001 else Vector2(1, 0)
	var q := center + dir * r
	return Vector3(q.x, p.y, q.y)


## Where a body of `radius` at `p` ends up after being pushed out of
## buildings, trunks and props, and kept inside the map.
static func resolve(state: WorldState, p: Vector3, radius: float) -> Vector3:
	var c := cfg()
	for pass_i in 2:
		for b in solid_buildings(state):
			if Vector2(b.position.x - p.x, b.position.z - p.z).length() < b.footprint.length() * 0.5 + radius + 0.5:
				p = _out_of_box(b, p, radius)
		var tr := float(c.get("tree_radius", 0.45))
		var cleared: Array[int] = []
		if state.territory:
			cleared = state.territory.cleared_trees
		for i in state.layout.trees.size():
			var t := state.layout.trees[i]
			if absf(t.x - p.x) > 3.0 or absf(t.y - p.z) > 3.0 or cleared.has(i):
				continue
			p = _out_of_circle(Vector2(t.x, t.y), tr * maxf(t.z, 0.6) + radius, p)
		var radii: Dictionary = c.get("props", {})
		var charter := state.territory.charter if state.territory else 0
		for prop: Dictionary in state.layout.props:
			var pp: Vector3 = prop["pos"]
			if absf(pp.x - p.x) > 3.0 or absf(pp.z - p.z) > 3.0:
				continue
			if not PropKit.present(str(prop["type"]), charter):
				continue
			p = _out_of_circle(Vector2(pp.x, pp.z), float(radii.get(str(prop["type"]), 0.4)) + radius, p)
	var limit := state.layout.extent - float(c.get("walk", {}).get("edge_margin", 6.0))
	var flat := Vector2(p.x, p.z)
	if flat.length() > limit:
		flat = flat.normalized() * limit
		p = Vector3(flat.x, p.y, flat.y)
	return p


## Is `p` inside a building (or site) footprint?
static func inside_building(state: WorldState, p: Vector3, radius: float = 0.0) -> bool:
	for b in solid_buildings(state):
		if _out_of_box(b, p, radius) != p:
			return true
	return false


## Does a finished building stand between a and b? (Building sites are low
## scaffolding and don't block the view.)
static func line_blocked(state: WorldState, a: Vector3, b: Vector3) -> bool:
	for bd in state.layout.buildings:
		if _segment_hits_box(bd, a, b):
			return true
	return false


## Liang-Barsky clip of the flat segment a-b against the footprint box,
## shrunk a little so grazing a corner doesn't count.
static func _segment_hits_box(b: BuildingData, a: Vector3, z: Vector3) -> bool:
	var inv := b.basis().inverse()
	var p0 := inv * (a - b.position)
	var p1 := inv * (z - b.position)
	var hx := b.footprint.x * 0.5 - 0.15
	var hz := b.footprint.y * 0.5 - 0.15
	var dx := p1.x - p0.x
	var dz := p1.z - p0.z
	var t0 := 0.0
	var t1 := 1.0
	for edge in 4:
		var p := 0.0
		var q := 0.0
		match edge:
			0:
				p = -dx
				q = p0.x + hx
			1:
				p = dx
				q = hx - p0.x
			2:
				p = -dz
				q = p0.z + hz
			3:
				p = dz
				q = hz - p0.z
		if absf(p) < 0.000001:
			if q < 0.0:
				return false
			continue
		var r := q / p
		if p < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return false
	return true
