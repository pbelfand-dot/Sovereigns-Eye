class_name CartView
extends Node3D
## The house's carts seen in the village (Phase 6.2): a cart sets out from
## the square along the road toward its seat's side of the realm, its carter
## at the horse's head and its escort behind, and leaves at the village's
## edge; on its last day on the road home it comes in from the edge in the
## evening and stands in the square till the day is done (when its people
## are home and the cart is put away). Presentation only: where a cart is
## comes from MarketData.carts and the time (`where`), so it's the same
## however the frames fall. The cart and horse: 3D/props/carts-transport.

const CART_SCENE := "res://3D/props/carts-transport/models/SE_Cart_Horse.glb"
const LOAD_SCENE := "res://3D/props/carts-transport/models/SE_Cart_Load.glb"
const LEGS := ["Leg_FL", "Leg_FR", "Leg_HL", "Leg_HR"]
## A horse's walk: hind left, fore left, hind right, fore right, a quarter
## of a stride apart.
const GAIT := {"Leg_HL": 0.0, "Leg_FL": 0.25, "Leg_HR": 0.5, "Leg_FR": 0.75}
const STRIDE := 1.7       # metres a stride
const SWING := 0.32       # radians each way at the shoulder or hip
const FLEX := 0.55        # radians the knee or hock bends in the swing

var world: VillageWorld
## cart id -> {node, parts: {name: Node3D}, rest: {name: Basis}, walkers: [CharacterModel], moved, wheel_r}
var _shown: Dictionary = {}


func setup(w: VillageWorld) -> void:
	world = w


static func cfg() -> Dictionary:
	return Trade.section("in_village")


# --- Where a cart is (data only) -------------------------------------------------------------------

## The main road out of the village toward a house's seat on the realm map
## (the map's x is east, its y south, as the village's x and z are).
static func road_toward(state: WorldState, house_id: int) -> Dictionary:
	var h := state.realm.get_house(house_id) if state.realm else {}
	var way := Realm.pos_of(h) - Realm.center() if not h.is_empty() else Vector2(1, 0)
	var best: Dictionary = {}
	var best_dot := -INF
	for road in state.layout.roads:
		if not str(road.get("name", "")) in ["north", "south", "east", "west"]:
			continue
		var pts: PackedVector3Array = road["points"]
		var out := pts[pts.size() - 1] - state.layout.square_center
		var dot := Vector2(out.x, out.z).normalized().dot(way.normalized())
		if dot > best_dot:
			best_dot = dot
			best = road
	return best


## The way a cart takes: from where it's loaded in the square out along the
## road to the village's edge (on the ground).
static func route(state: WorldState, cart: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var road := road_toward(state, int(cart["house"]))
	if road.is_empty():
		return out
	var pts: PackedVector3Array = road["points"]
	var c := state.layout.square_center
	var dir := (pts[0] - c)
	dir.y = 0.0
	out.append(c + dir.normalized() * state.layout.square_radius * float(cfg().get("start", 0.45)))
	out.append_array(pts)
	for i in out.size():
		out[i] = TerrainHeight.on_ground(out[i])
	return out


static func length_of(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## Where a cart is at `minutes`: {shown, at (metres along its route from the
## square), heading (1 going out, -1 coming in), moving}.
static func where(state: WorldState, cart: Dictionary, minutes: float) -> Dictionary:
	var hidden := {"shown": false, "at": 0.0, "heading": 1, "moving": false}
	var speed := float(cfg().get("speed", 0.9))
	var length := length_of(route(state, cart))
	if length <= 0.0:
		return hidden
	var going := (minutes - float(cart.get("set_out_min", 0.0))) * speed
	if str(cart["stage"]) == "out" or not bool(cart.get("road_home", false)):
		if going >= 0.0 and going < length:
			return {"shown": true, "at": going, "heading": 1, "moving": true}
		return hidden
	var home := float((int(cart["back"]) - 1) * Calendar.MINUTES_PER_DAY + int(cfg().get("home_hour", 16)) * Calendar.MINUTES_PER_HOUR)
	if minutes < home:
		return {"shown": true, "at": going, "heading": 1, "moving": true} if going >= 0.0 and going < length else hidden
	var coming := (minutes - home) * speed
	if coming < length:
		return {"shown": true, "at": length - coming, "heading": -1, "moving": true}
	return {"shown": true, "at": 0.0, "heading": -1, "moving": false}


## A point `d` metres along a route and the way it runs there.
static func along(pts: PackedVector3Array, d: float) -> Dictionary:
	if pts.size() < 2:
		return {"at": pts[0] if not pts.is_empty() else Vector3.ZERO, "dir": Vector3.RIGHT}
	var left := maxf(0.0, d)
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if left <= seg or i == pts.size() - 1:
			var t := clampf(left / maxf(seg, 0.001), 0.0, 1.0 if i < pts.size() - 1 else 1.5)
			return {"at": pts[i - 1].lerp(pts[i], t), "dir": (pts[i] - pts[i - 1]).normalized()}
		left -= seg
	return {"at": pts[pts.size() - 1], "dir": (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()}


# --- Drawing ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null or world.state == null or world.state.market == null:
		return
	var st := world.state
	visible = not world.passing
	var live := {}
	for cart: Dictionary in st.market.carts:
		var w := where(st, cart, st.minutes)
		if not w["shown"]:
			continue
		var id := int(cart["id"])
		live[id] = true
		if not _shown.has(id):
			_shown[id] = _make(st, cart, int(w["heading"]))
		_place(st, cart, _shown[id], w, delta)
	for id: int in _shown.keys():
		if not live.has(id):
			(_shown[id]["node"] as Node3D).queue_free()
			_shown.erase(id)


## How many carts are in sight (for tests and the capture).
func shown_count() -> int:
	return _shown.size()


func shown_node(cart_id: int) -> Node3D:
	return _shown[cart_id]["node"] if _shown.has(cart_id) else null


func _make(st: WorldState, cart: Dictionary, heading: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Cart%d" % int(cart["id"])
	add_child(root)
	var rig: Node3D = (load(CART_SCENE) as PackedScene).instantiate() if ResourceLoader.exists(CART_SCENE) else _stand_in()
	root.add_child(rig)
	var parts := {}
	var rest := {}
	for n in ["Wheel_L", "Wheel_R", "Horse", "Neck", "Head", "Tail", "Load_Anchor"] + LEGS + LEGS.map(func(l: String) -> String: return l + "_Lower"):
		var node := rig.find_child(n, true, false) as Node3D
		if node:
			parts[n] = node
			rest[n] = node.basis
	# Its load going out; what didn't sell coming home.
	var laden := not (cart["load"] as Dictionary).is_empty() if heading > 0 else not (cart["unsold"] as Dictionary).is_empty()
	if laden and parts.has("Load_Anchor") and ResourceLoader.exists(LOAD_SCENE):
		(parts["Load_Anchor"] as Node3D).add_child((load(LOAD_SCENE) as PackedScene).instantiate())
	var walkers: Array = []
	for id: int in [int(cart["carter"])] + Array(cart["escort"]):
		var c := st.get_character(id)
		if c == null:
			continue
		var m := HumanModel.for_character(c)
		root.add_child(m)
		walkers.append(m)
	var wheel_r := 0.65
	if parts.has("Wheel_L"):
		wheel_r = maxf(0.3, (parts["Wheel_L"] as Node3D).position.y)
	return {"node": root, "rig": rig, "parts": parts, "rest": rest, "walkers": walkers, "moved": 0.0, "last": -1.0, "wheel_r": wheel_r}


func _place(st: WorldState, cart: Dictionary, v: Dictionary, w: Dictionary, delta: float) -> void:
	var pts := route(st, cart)
	var d := float(w["at"])
	var heading := int(w["heading"])
	if float(v["last"]) >= 0.0:
		v["moved"] = float(v["moved"]) + absf(d - float(v["last"]))
	v["last"] = d
	var here := along(pts, d)
	var fwd: Vector3 = here["dir"] * heading
	var rig: Node3D = v["rig"]
	rig.position = here["at"]
	rig.rotation = Vector3(0.0, atan2(-fwd.z, fwd.x), 0.0)
	_animate(v, bool(w["moving"]))
	# The carter at the horse's head, the escort behind, two by two.
	var walkers: Array = v["walkers"]
	for i in walkers.size():
		var m: CharacterModel = walkers[i]
		var ahead := 2.7 if i == 0 else -2.6 - 1.5 * floorf((i - 1) / 2.0)
		var side := 1.0 if i == 0 else (0.65 if (i - 1) % 2 == 0 else -0.65)
		var at := along(pts, d + ahead * heading)
		var f: Vector3 = at["dir"] * heading
		var left := Vector3(f.z, 0.0, -f.x)
		m.position = TerrainHeight.on_ground(at["at"] + left * side)
		m.rotation = Vector3(0.0, atan2(-f.x, -f.z), 0.0)
		m.anim_time_scale = world.time_scale()
		m.animate("walk" if w["moving"] else "idle", 0.0, delta)


## The wheels turn and the horse walks with the ground covered; standing,
## it rests (a flick of the tail).
func _animate(v: Dictionary, moving: bool) -> void:
	var parts: Dictionary = v["parts"]
	var rest: Dictionary = v["rest"]
	var moved := float(v["moved"])
	# Rolling toward +X the wheel turns about -Z (its top runs ahead).
	var spin := moved / float(v["wheel_r"])
	for wheel: String in ["Wheel_L", "Wheel_R"]:
		if parts.has(wheel):
			(parts[wheel] as Node3D).basis = rest[wheel] * Basis(Vector3.BACK, -spin)
	var phase := moved / STRIDE * TAU
	for leg: String in LEGS:
		if not parts.has(leg):
			continue
		var p := phase + float(GAIT[leg]) * TAU
		# About +Z a leg's hoof swings toward +X (forward); it comes forward
		# while cos(p) > 0.
		var swing := SWING * sin(p) if moving else 0.0
		(parts[leg] as Node3D).basis = rest[leg] * Basis(Vector3.BACK, swing)
		var lower := leg + "_Lower"
		if parts.has(lower):
			# The fore knee folds back as the leg comes forward; the hind hock the other way.
			var bend := FLEX * maxf(0.0, cos(p)) if moving else 0.0
			(parts[lower] as Node3D).basis = rest[lower] * Basis(Vector3.BACK, -bend if leg.begins_with("Leg_F") else bend)
	if parts.has("Neck"):
		(parts["Neck"] as Node3D).basis = rest["Neck"] * Basis(Vector3.BACK, -0.05 * sin(phase * 2.0) if moving else 0.0)
	if parts.has("Tail"):
		var t := Time.get_ticks_msec() / 1000.0
		(parts["Tail"] as Node3D).basis = rest["Tail"] * Basis(Vector3.RIGHT, 0.12 * sin(t * (1.3 if moving else 0.7)))


## Without the family's models: a box for the cart and one for the horse.
func _stand_in() -> Node3D:
	var rig := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.2, 0.6, 1.3)
	body.mesh = box
	body.position = Vector3(0, 0.9, 0)
	rig.add_child(body)
	var horse := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(1.6, 0.8, 0.5)
	horse.mesh = hb
	horse.name = "Horse"
	horse.position = Vector3(2.8, 1.1, 0)
	rig.add_child(horse)
	var anchor := Node3D.new()
	anchor.name = "Load_Anchor"
	anchor.position = Vector3(0, 1.2, 0)
	rig.add_child(anchor)
	return rig
