class_name FairView
extends Node3D
## The house's fair seen in the village (Phase 6.3): while it's on, the
## stalls of the merchants come from afar stand in a ring inside the square,
## facing in, among the village's own. Presentation only, from
## ManorSystem.fair_on.

var world: VillageWorld
var _up := false


func setup(w: VillageWorld) -> void:
	world = w


func _process(_delta: float) -> void:
	if world == null or world.state == null:
		return
	var on := ManorSystem.fair_on(world.state)
	if on != _up:
		_up = on
		for c in get_children():
			c.queue_free()
		if on:
			build()


## The fair's stalls: where they stand, [[set, Transform3D]] (data only).
static func stalls(state: WorldState) -> Array:
	var out := []
	var n := int(ManorSystem.section("fair").get("stalls", 6))
	var sets: Array = PropKit.config().get("replace", {}).get("stall", ["stall_goods"])
	var c := state.layout.square_center
	var r := state.layout.square_radius * 0.58
	var tries := 0
	var a := 0.3
	while out.size() < n and tries < n * 6:
		tries += 1
		var dir := Vector3(cos(a), 0.0, sin(a))
		a += TAU / float(n * 2)
		var pos := c + dir * r
		var clear := true
		for p: Dictionary in state.layout.props:
			if (p["pos"] as Vector3).distance_to(pos) < 3.2:
				clear = false
				break
		for prev: Array in out:
			if (prev[1] as Transform3D).origin.distance_to(pos) < 4.0:
				clear = false
		if not clear:
			continue
		var yaw := atan2(-dir.x, -dir.z)
		out.append([str(sets[out.size() % sets.size()]), Transform3D(Basis(Vector3.UP, yaw), TerrainHeight.on_ground(pos))])
	return out


func build() -> void:
	if not PropKit.available():
		return
	var items := []
	for s: Array in stalls(world.state):
		items.append_array(PropKit.set_items(str(s[0]), s[1]))
	PropKit.add_merged(self, items)


func stall_count() -> int:
	return stalls(world.state).size() if _up else 0
