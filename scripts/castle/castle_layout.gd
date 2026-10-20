class_name CastleLayout
extends RefCounted
## The house's castle as it stands, assembled from the Lord's Castle family
## (3D/buildings/lords-castle): the layouts the game builds (Phase 5.3,
## CastleSystem) and the capture tool shows. The pieces were made ahead of
## the castle phase as demo castles; their layouts are geometry, kept here
## with the code that places them.
##
## A layout is a list of [model, position, yaw (rad)] in the castle's own
## frame: the ground at y = 0, the gate toward +Z. Pieces are the family's
## GLBs (models/<model>.glb); each was built to join its neighbours on the
## grid its README describes.
##
##   "stone":  a curtain wall round a 38 m square, towers at its front
##             corners and plain angles at the back, a gatehouse in the
##             front, square towers on the sides, a stair up to the wall
##             walk at the back, the keep inside.
##   "timber": a motte with its tower, the bridge down into a palisaded
##             bailey, a gate tower at the bailey's far end.

const ROOT := "res://3D/buildings/lords-castle/models/"
## In the order they are placed: the longer one first.
const KINDS := ["timber", "stone"]

## How far along the wall line each piece reaches (m).
const LENGTH := {
	"SE_Curtain_Wall": 4.0, "SE_Curtain_Stair": 8.0, "SE_Tower_Square": 6.0, "SE_Tower_Corner": 6.0,
	"SE_Curtain_Corner": 6.0, "SE_Gatehouse": 8.0, "SE_Palisade": 4.0, "SE_Palisade_Gate": 4.0,
}
## Half the stone enclosure: from its middle to a corner tower's middle.
const STONE_HALF := 19.0
## Where the keep stands inside the curtain.
const KEEP_AT := Vector3(-4.0, 0, -5.5)
## The bailey's palisade, in the motte's frame (+X from the motte): its far
## (gate) side, its two long sides, and where they end in the motte's flank.
const BAILEY_FAR := 36.0
const BAILEY_HALF := 12.0
const BAILEY_START := 2.0
## The motte's top, where its tower stands.
const MOTTE_TOP := 7.2


static func layout(kind: String) -> Array:
	return stone() if kind == "stone" else timber()


## Each side of the curtain runs from a corner tower toward the next, the
## outside on the left: front (+Z) along +X, then the right side toward -Z,
## the back toward -X, the left toward +Z.
static func stone() -> Array:
	var sides := [
		["SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Gatehouse", "SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Curtain_Wall"],
		["SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Tower_Square", "SE_Curtain_Wall", "SE_Tower_Square", "SE_Curtain_Wall", "SE_Curtain_Wall"],
		["SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Curtain_Stair", "SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Curtain_Wall"],
		["SE_Curtain_Wall", "SE_Curtain_Wall", "SE_Tower_Square", "SE_Curtain_Wall", "SE_Tower_Square", "SE_Curtain_Wall", "SE_Curtain_Wall"],
	]
	# Towers at the front corners; the back ones plain angles.
	var corners := ["SE_Tower_Corner", "SE_Tower_Corner", "SE_Curtain_Corner", "SE_Curtain_Corner"]
	var out := []
	for i in 4:
		var yaw := i * PI * 0.5
		var b := Basis(Vector3.UP, yaw)
		var start := b * Vector3(-STONE_HALF, 0, STONE_HALF)
		var along := b * Vector3.RIGHT
		out.append([corners[i], start, yaw])
		var at: float = LENGTH[corners[i]] * 0.5
		for model: String in sides[i]:
			var l: float = LENGTH[model]
			out.append([model, start + along * (at + l * 0.5), yaw])
			at += l
	# The keep stands back and to one side, its forebuilding toward the
	# gate across an open court.
	out.append(["SE_Keep", KEEP_AT, 0.0])
	return out


## Laid out with the bailey toward +X of the motte, then turned so its gate
## faces +Z like the stone castle's.
static func timber() -> Array:
	var raw := [
		["SE_Motte", Vector3.ZERO, 0.0],
		["SE_Motte_Bridge", Vector3.ZERO, 0.0],
		["SE_Timber_Tower", Vector3(0, MOTTE_TOP, 0), 0.0],
	]
	var n := int((BAILEY_FAR - 2.0 - BAILEY_START) / 4.0)
	for k in n:   # the near long side (+Z), its outside +Z
		raw.append(["SE_Palisade", Vector3(BAILEY_START + 2.0 + 4.0 * k, 0, BAILEY_HALF), 0.0])
	raw.append(["SE_Palisade_Corner", Vector3(BAILEY_FAR, 0, BAILEY_HALF), PI * 0.5])
	var far := ["SE_Palisade", "SE_Palisade", "SE_Palisade_Gate", "SE_Palisade", "SE_Palisade"]
	for k in far.size():   # the far side, its outside +X, running toward -Z
		raw.append([far[k], Vector3(BAILEY_FAR, 0, BAILEY_HALF - 4.0 - 4.0 * k), PI * 0.5])
	raw.append(["SE_Palisade_Corner", Vector3(BAILEY_FAR, 0, -BAILEY_HALF), PI])
	for k in n:   # the other long side, its outside -Z, running back toward the motte
		raw.append(["SE_Palisade", Vector3(BAILEY_FAR - 4.0 - 4.0 * k, 0, -BAILEY_HALF), PI])
	var turn := Basis(Vector3.UP, -PI * 0.5)
	var out := []
	for p: Array in raw:
		out.append([p[0], turn * (p[1] as Vector3), float(p[2]) - PI * 0.5])
	return out


## How far out (+Z) the castle's gate stands on its wall line.
static func gate_z(kind: String) -> float:
	return STONE_HALF if kind == "stone" else BAILEY_FAR


## The ground a castle covers, in its own frame (x, z), with room for its
## plinths, overhangs and the motte's foot.
static func footprint(kind: String) -> Rect2:
	if kind == "stone":
		return Rect2(-24.5, -24.5, 49.0, 49.0)
	return Rect2(-15.0, -15.0, 30.0, BAILEY_FAR + 18.0)


## The castle as nodes: one instance of each piece's model.
static func build(kind: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Castle_" + kind
	for p: Array in layout(kind):
		var scene := load(ROOT + str(p[0]) + ".glb") as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		node.name = str(p[0])
		node.position = p[1]
		node.rotation.y = float(p[2])
		holder.add_child(node, true)
	return holder


## Places for both castles near the village, {kind: Transform3D}: the
## first (the longer) at the nearest spot from which the second still finds
## one of its own. Empty if they don't both fit.
static func find_spots(lay: VillageLayout) -> Dictionary:
	var first: String = KINDS[0]
	var second: String = KINDS[1]
	for xf: Transform3D in spots(lay, first, [], 40):
		var taken := [[xf, footprint(first).grow(3.0)]]
		var other := spots(lay, second, taken, 1)
		if not other.is_empty():
			return {first: xf, second: other[0]}
	return {}


## Up to `count` places for a castle, nearest first: on rings round the
## middle, its gate toward the square if it can, else turned a little or
## side on, where its footprint, with a few metres to spare, keeps off
## buildings, fields, roads, yards and the footprints in `taken`
## ([Transform3D, Rect2]), inside the map.
static func spots(lay: VillageLayout, kind: String, taken: Array, count: int) -> Array[Transform3D]:
	return spots_for(lay, footprint(kind).grow(3.0), taken, count)


## The ground the house's castle needs (CastleSystem): room for the motte
## and bailey and for the stone castle that takes its place.
static func site_rect() -> Rect2:
	return footprint("stone").merge(footprint("timber"))


## As `spots`, for any footprint `rect` (in the castle's own frame). For the
## house's own castle (`house`, CastleSystem) see spot_clear.
static func spots_for(lay: VillageLayout, rect: Rect2, taken: Array, count: int, house: bool = false) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	# The house's castle keeps to the edge of the land the village builds on,
	# leaving that land to the village.
	var dist := maxf(50.0, lay.flat_radius) if house else 50.0
	while dist < lay.extent * 1.45:
		for k in 48:
			var ang := k * TAU / 48.0
			var at := Vector3(sin(ang), 0, cos(ang)) * dist
			var to := -at.normalized()
			for turn in [0.0, PI * 0.25, -PI * 0.25, PI * 0.5, -PI * 0.5]:
				var xf := Transform3D(Basis(Vector3.UP, atan2(to.x, to.z) + turn), at)
				if spot_clear(lay, xf, rect, taken, house):
					out.append(xf)
					if out.size() >= count:
						return out
					break
		dist += 4.0
	return out


## For the house's own castle (`house`), boulders don't stand in the way
## (they're cleared, CastleSystem.clear_site) and its back may reach
## HOUSE_REACH metres past the map's edge into the woods, so long as the
## ground before its gate is in the village's reach.
const HOUSE_REACH := 24.0


static func spot_clear(lay: VillageLayout, xf: Transform3D, rect: Rect2, taken: Array, house: bool = false) -> bool:
	var inv := xf.affine_inverse()
	var bound := lay.extent + HOUSE_REACH if house else lay.extent - 4.0
	for c in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]:
		var w := xf * Vector3(c.x, 0, c.y)
		if absf(w.x) > bound or absf(w.z) > bound:
			return false
	if house and (xf * Vector3(0, 0, rect.end.y + 10.0)).length() > lay.extent - 8.0:
		return false
	var hits := func(p: Vector3, r: float) -> bool:
		var l := inv * p
		return rect.grow(r).has_point(Vector2(l.x, l.z))
	for b: BuildingData in lay.buildings:
		if hits.call(b.position, b.radius()):
			return false
	for f: Dictionary in lay.fields:
		if hits.call(f["center"], (f["size"] as Vector2).length() * 0.5):
			return false
	for p: Dictionary in lay.props:
		if house and str(p["type"]) == "rock":
			continue
		if hits.call(p["pos"], 3.0):
			return false
	for road: Dictionary in lay.roads:
		var pts: PackedVector3Array = road["points"]
		for i in pts.size():
			var a := pts[i]
			var steps := 1 if i == 0 else maxi(1, ceili(a.distance_to(pts[i - 1]) / 2.0))
			for s in steps:
				var q := a if i == 0 else pts[i - 1].lerp(a, float(s + 1) / steps)
				if hits.call(q, float(road["width"]) * 0.5 + 1.0):
					return false
	for t: Array in taken:
		var other: Transform3D = t[0]
		var orect: Rect2 = t[1]
		for c in [orect.position, orect.position + Vector2(orect.size.x, 0), orect.end, orect.position + Vector2(0, orect.size.y), orect.get_center()]:
			if hits.call(other * Vector3(c.x, 0, c.y), 0.0):
				return false
		for c in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y), rect.get_center()]:
			var l := other.affine_inverse() * (xf * Vector3(c.x, 0, c.y))
			if orect.has_point(Vector2(l.x, l.z)):
				return false
	return true


## The layout's trees standing in a castle's footprint, within `apron`
## metres of it or on the approach to its gate (indices), to clear: the
## ground round a castle was kept open.
static func trees_in(lay: VillageLayout, xf: Transform3D, kind: String, apron: float = 12.0) -> Array[int]:
	var rect := footprint(kind).grow(apron)
	var approach := Rect2(-8.0, gate_z(kind), 16.0, 40.0)
	var inv := xf.affine_inverse()
	var out: Array[int] = []
	for i in lay.trees.size():
		var l := inv * Vector3(lay.trees[i].x, 0, lay.trees[i].y)
		if rect.has_point(Vector2(l.x, l.z)) or approach.has_point(Vector2(l.x, l.z)):
			out.append(i)
	return out
