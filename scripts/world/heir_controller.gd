class_name HeirController
extends RefCounted
## Direct control of the heir: walk (WASD, left stick or the touch joystick)
## relative to the camera, run with Shift, and never through buildings,
## trunks or props. The heir moves at the same real-time pace at any game
## speed and stands still while the game is paused.
##
## Optional accessibility: click-to-move (`walk_to`) follows the roads to a
## spot and stops at the first touch of a movement key.

var world: VillageWorld
var npc: NPC
## Off while talking, during a reveal, in the map-table overview or a menu.
var enabled := true
## Scripted input for demos and tests: a Vector2 (x right, y forward) or null.
var scripted_move: Variant = null
var scripted_run := false
## The on-screen joystick (TouchControls).
var touch_move := Vector2.ZERO
var speed := 0.0

var _auto_path := PackedVector3Array()
var _auto_index := 0
var _auto_stop := 0.0


func _init(owner_world: VillageWorld, body: NPC) -> void:
	world = owner_world
	npc = body
	npc.driven = true


static func cfg() -> Dictionary:
	return GameData.load_file("controls").get("walk", {})


## Movement wanted this frame: x = right, y = forward, length 0..1.
func move_input() -> Vector2:
	if scripted_move != null:
		return (scripted_move as Vector2).limit_length(1.0)
	var v := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if touch_move.length() > v.length():
		v = touch_move
	return v.limit_length(1.0)


func is_running() -> bool:
	return scripted_run or Input.is_action_pressed("run")


## Walk along the roads to a point (click-to-move). `stop_short` meters
## before it (e.g. to stand in front of someone).
func walk_to(point: Vector3, stop_short: float = 0.0) -> void:
	_auto_path = world.graph.find_path(npc.global_position, TerrainHeight.on_ground(point))
	if _auto_path.size() < 2:
		_auto_path = PackedVector3Array([npc.global_position, point])
	_auto_index = 1
	_auto_stop = stop_short


func is_auto_walking() -> bool:
	return _auto_index > 0 and _auto_index < _auto_path.size()


func cancel_auto_walk() -> void:
	_auto_path = PackedVector3Array()
	_auto_index = 0


func update(delta: float) -> void:
	var c := npc.character
	if c.inside_building_id >= 0:
		# The heir is always out where the player can see them.
		var b := world.state.get_building(c.inside_building_id)
		if b:
			npc.teleport(b.door_position())
		c.inside_building_id = -1
		npc.set_inside(false)
	var w := cfg()
	if not enabled or world.time_scale() <= 0.0:
		speed = 0.0
		npc.drive(Vector3.ZERO, delta)
		return
	var input := move_input()
	var dir := Vector3.ZERO
	var amount := 0.0
	if input.length() > 0.12:
		cancel_auto_walk()
		dir = world.camera_rig.right_flat() * input.x + world.camera_rig.forward_flat() * input.y
		amount = input.length()
	elif is_auto_walking():
		var target := _auto_path[_auto_index]
		var to := target - npc.global_position
		to.y = 0
		var last := _auto_index == _auto_path.size() - 1
		if to.length() <= (maxf(_auto_stop, 0.25) if last else 0.6):
			_auto_index += 1
		else:
			dir = to
			amount = 1.0
	var top := float(w.get("run_speed", 5.2)) if is_running() else float(w.get("walk_speed", 2.6))
	var wanted := top * amount
	speed = move_toward(speed, wanted, float(w.get("accel", 14.0)) * delta)
	if dir.length() < 0.001 or speed < 0.01:
		npc.drive(Vector3.ZERO, delta)
		c.activity_text = "Looking around the village"
		return
	var before := npc.global_position
	var p := before + dir.normalized() * speed * delta
	p = WorldGeometry.resolve(world.state, _away_from_villagers(p), float(w.get("body_radius", 0.35)))
	npc.global_position = TerrainHeight.on_ground(p)
	npc.drive(npc.global_position - before, delta)
	c.activity_text = "Walking through the village"


## Villagers aren't walked through: a gentle push to the side.
func _away_from_villagers(p: Vector3) -> Vector3:
	var r := float(GameData.load_file("controls").get("villager_radius", 0.3)) + float(cfg().get("body_radius", 0.35))
	for other: NPC in world.npcs.values():
		if other == npc or not other.visible:
			continue
		var o := other.global_position
		if absf(o.x - p.x) > r or absf(o.z - p.z) > r:
			continue
		var d := Vector2(p.x - o.x, p.z - o.z)
		if d.length() < r and d.length() > 0.0001:
			var q := Vector2(o.x, o.z) + d.normalized() * r
			p = Vector3(q.x, p.y, q.y)
	return p
