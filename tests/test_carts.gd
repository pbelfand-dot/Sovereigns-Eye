extends TestCase
## The Carts & Transport family (3D/props/carts-transport) and how the
## village draws it (CartView): the cart and horse keep the node contract
## CartView turns (names, parents, pivots, rest), stand on the ground, the
## load fits the bed; rolling, the wheels turn and the legs swing.

const DIR := "res://3D/props/carts-transport/models/"
const PARENT := {
	"Cart": "", "Wheel_L": "", "Wheel_R": "", "Horse": "", "Load_Anchor": "",
	"Leg_FL": "Horse", "Leg_FR": "Horse", "Leg_HL": "Horse", "Leg_HR": "Horse",
	"Leg_FL_Lower": "Leg_FL", "Leg_FR_Lower": "Leg_FR", "Leg_HL_Lower": "Leg_HL", "Leg_HR_Lower": "Leg_HR",
	"Neck": "Horse", "Head": "Neck", "Tail": "Horse",
}


## A node's transform in its scene root's frame (no tree needed).
func _in_rig(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p.get_parent() != null and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := _in_rig(mi) * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func test_the_cart_and_horse_keep_their_contract() -> void:
	var rig := (load(DIR + "SE_Cart_Horse.glb") as PackedScene).instantiate() as Node3D
	for n: String in PARENT:
		var node := rig.find_child(n, true, false) as Node3D
		check(node != null, "%s is there" % n)
		if node == null:
			continue
		var parent: String = str(node.get_parent().name) if node.get_parent() != rig else ""
		check_eq(parent, str(PARENT[n]), "%s hangs from %s" % [n, PARENT[n] if PARENT[n] != "" else "the rig"])
		check(node.basis.is_equal_approx(Basis.IDENTITY), "%s rests unturned" % n)
	var horse := rig.find_child("Horse", true, false) as Node3D
	check(_in_rig(horse).origin.x > 2.0, "the horse is ahead of the cart (+X)")
	for leg: String in ["Leg_FL", "Leg_FR", "Leg_HL", "Leg_HR"]:
		var upper := _in_rig(rig.find_child(leg, true, false) as Node3D).origin
		var lower := _in_rig(rig.find_child(leg + "_Lower", true, false) as Node3D).origin
		check(upper.y > lower.y and lower.y > 0.2, "%s: the knee or hock below the shoulder or hip" % leg)
		var hoof := _bounds(rig.find_child(leg + "_Lower", true, false) as Node3D)
		check(absf(hoof.position.y) < 0.01, "%s's hoof on the ground (%.3f)" % [leg, hoof.position.y])
	for w: String in ["Wheel_L", "Wheel_R"]:
		var wheel := rig.find_child(w, true, false) as MeshInstance3D
		var box := _in_rig(wheel) * wheel.mesh.get_aabb()
		check(absf(box.position.y) < 0.01 and absf(box.size.y * 0.5 - wheel.position.y) < 0.02, "%s rolls on the ground about its hub (radius %.2f)" % [w, wheel.position.y])
	var anchor := _in_rig(rig.find_child("Load_Anchor", true, false) as Node3D).origin
	rig.free()
	var load_n := (load(DIR + "SE_Cart_Load.glb") as PackedScene).instantiate() as Node3D
	var lb := _bounds(load_n)
	check(lb.position.y > -0.01 and lb.position.x > -1.0 and lb.end.x < 1.0 and absf(lb.position.z) < 0.58 and lb.end.z < 0.58,
		"the load fits the bed (%.2f m wide, on its floor %.2f m up)" % [lb.size.z, anchor.y])
	load_n.free()
	var cart := (load(DIR + "SE_Cart.glb") as PackedScene).instantiate() as Node3D
	check(absf(_bounds(cart).position.y) < 0.02, "the unhitched cart stands on the ground")
	cart.free()


func test_the_cart_rolls_and_the_horse_walks() -> void:
	Game.state = WorldGenerator.generate("carts-walk")
	var st := Game.state
	st.minutes = float(3 * Calendar.MINUTES_PER_DAY + 9 * 60)
	st.territory.stock["cloth"] = 60.0
	var world: VillageWorld = load("res://scenes/world/world.tscn").instantiate()
	runner.add_child(world)
	await frames(2)
	var r := Trade.send(st, int(st.realm.houses[0]["id"]), {"cloth": 40}, 1)
	world.apply_life_events([{"text": "", "away": r["away"]}])
	st.minutes += 5.0
	await frames(2)
	var node := world.cart_view.shown_node(int(r["cart"]["id"]))
	check(node != null, "the cart is seen")
	if node == null:
		world.queue_free()
		return
	var wheel := node.find_child("Wheel_L", true, false) as Node3D
	var leg := node.find_child("Leg_FL", true, false) as Node3D
	check(node.find_child("Load_Anchor", true, false).get_child_count() == 1, "laden with its goods")
	var wheel_before := wheel.basis
	var poses := {}
	for i in 6:
		st.minutes += 0.37
		await frames(1)
		poses[snappedf(leg.rotation.z, 0.01)] = true
	check(not wheel.basis.is_equal_approx(wheel_before), "the wheels turn as it rolls")
	check(poses.size() >= 3, "the horse's legs swing (%d poses)" % poses.size())
	world.queue_free()
	await frames(2)
