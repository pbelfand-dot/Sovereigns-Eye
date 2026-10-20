class_name CastleView
extends Node3D
## The house's castle in the world (Phase 5.3): the pieces standing now
## (CastleSystem.pieces), on its levelled site. While the works go on, the
## pieces rise one by one; the old motte and bailey comes down as the stone
## castle goes up. Redrawn only when what stands changes.

var state: WorldState
var _key := ""


func setup(world_state: WorldState) -> void:
	state = world_state
	name = "Castle"
	refresh()


## Brings the pieces up to date (cheap when nothing changed).
func refresh() -> void:
	var c := state.castle
	if c == null or not c.has_site():
		if _key != "":
			_clear()
			_key = ""
		return
	var standing := CastleSystem.pieces(state)
	var key := "%s|%s|%d|%s" % [c.kind, c.works, standing.size(), str(c.site)]
	if key == _key:
		return
	_key = key
	_clear()
	transform = c.transform()
	for p: Array in standing:
		var scene := load(CastleLayout.ROOT + str(p[0]) + ".glb") as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		node.name = str(p[0])
		node.position = p[1]
		node.rotation.y = float(p[2])
		add_child(node, true)


## How many pieces stand (for tests and the capture).
func piece_count() -> int:
	return get_child_count()


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
