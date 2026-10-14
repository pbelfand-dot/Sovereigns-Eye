class_name CharacterModel
extends Node3D
## Placeholder 3D body for a character, assembled from primitives.
##
## Built purely from a character's appearance data + occupation, so the same
## function makes the walking NPC and the portrait on the character card.
## When real models arrive, replace `create()` and keep `animate()`'s
## interface. The model faces -Z (Godot's forward).

var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var torso: Node3D
var head: Node3D
var body_height := 1.0
## Game speed for animation playback (set by the NPC each frame).
var anim_time_scale := 1.0


static func create(appearance: Dictionary, occupation: Dictionary, gender: String, age: int) -> CharacterModel:
	var m := CharacterModel.new()
	m.name = "Model"
	m._build(appearance, occupation, gender, age)
	return m


func _build(ap: Dictionary, occ: Dictionary, gender: String, age: int) -> void:
	var height := float(ap.get("height", 1.0))
	var build := float(ap.get("build", 1.0))
	body_height = height
	scale = Vector3.ONE * height
	var skin := Mats.hex(str(ap.get("skin", "#e0b48c")), 0.8)
	var hair := Mats.hex(str(ap.get("hair", "#4a2f1d")), 0.85)
	var primary := Mats.hex(str(ap.get("primary", "#7a6248")))
	var secondary := Mats.hex(str(ap.get("secondary", "#4a3a2a")))
	var boots := Mats.hex("#3a2a1e")
	var outfit := str(occ.get("outfit", "tunic"))
	var metal := Mats.metal(Color("#a7adb5"))
	var is_child := age < 14
	var head_scale := 1.0 + (0.35 if is_child else 0.0)

	# Legs (pivot at the hip so they can swing)
	for side: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.11, 0.86, 0)
		add_child(leg)
		Mats.add_mesh(leg, Mats.capsule_mesh(0.085, 0.86), secondary if outfit != "armor" else metal, Vector3(0, -0.43, 0))
		Mats.box(leg, Vector3(0.16, 0.12, 0.26), Vector3(0, -0.8, -0.04), boots)
		if side < 0.0:
			left_leg = leg
		else:
			right_leg = leg

	torso = Node3D.new()
	torso.position = Vector3(0, 0.86, 0)
	add_child(torso)
	var torso_mat: Material = metal if outfit == "armor" else primary
	Mats.add_mesh(torso, Mats.capsule_mesh(0.21, 0.78), torso_mat, Vector3(0, 0.36, 0), Vector3.ZERO, Vector3(build, 1.0, build * 0.85))
	match outfit:
		"robe", "gown":
			Mats.cylinder(torso, 0.2 * build, 0.36 * build, 0.82, Vector3(0, -0.4, 0), primary, 12)
			Mats.box(torso, Vector3(0.44 * build, 0.07, 0.38), Vector3(0, 0.08, 0), secondary)
		"armor":
			Mats.box(torso, Vector3(0.34 * build, 0.6, 0.06), Vector3(0, 0.3, -0.18 * build), secondary)
			for side: float in [-1.0, 1.0]:
				Mats.sphere(torso, 0.13, Vector3(side * 0.24 * build, 0.62, 0), metal)
		"apron":
			Mats.box(torso, Vector3(0.32 * build, 0.7, 0.05), Vector3(0, 0.1, -0.19 * build), secondary)
		"fine":
			Mats.box(torso, Vector3(0.44 * build, 0.07, 0.38), Vector3(0, 0.08, 0), secondary)
			Mats.box(torso, Vector3(0.46 * build, 0.75, 0.05), Vector3(0, 0.32, 0.17 * build), secondary)
		_:
			Mats.box(torso, Vector3(0.44 * build, 0.07, 0.38), Vector3(0, 0.08, 0), Mats.hex("#4a3424"))

	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * (0.27 * build + 0.02), 0.62, 0)
		torso.add_child(arm)
		Mats.add_mesh(arm, Mats.capsule_mesh(0.07, 0.62), torso_mat, Vector3(0, -0.27, 0))
		Mats.sphere(arm, 0.075, Vector3(0, -0.6, 0), skin)
		if side < 0.0:
			left_arm = arm
		else:
			right_arm = arm

	head = Node3D.new()
	head.position = Vector3(0, 0.86 + 0.88, 0)
	head.scale = Vector3.ONE * head_scale
	add_child(head)
	Mats.sphere(head, 0.17, Vector3.ZERO, skin)
	var eye := Mats.hex(str(ap.get("eyes", "#3b2a1a")), 0.4)
	for side: float in [-1.0, 1.0]:
		Mats.sphere(head, 0.026, Vector3(side * 0.06, 0.02, -0.155), eye)
	Mats.sphere(head, 0.03, Vector3(0, -0.02, -0.17), skin)
	_build_hair(str(ap.get("hair_style", "short")), hair, gender)
	if bool(ap.get("beard", false)):
		Mats.sphere(head, 0.11, Vector3(0, -0.1, -0.09), hair, Vector3(1.0, 0.85, 0.7))
	_build_headwear(str(occ.get("headwear", "")), primary, secondary, metal)
	_build_tool(str(occ.get("tool", "")), metal)


func _build_hair(style: String, hair: Material, gender: String) -> void:
	match style:
		"bald":
			return
		"cropped":
			Mats.sphere(head, 0.178, Vector3(0, 0.035, 0.012), hair, Vector3(1.0, 0.8, 1.0))
		"long":
			Mats.sphere(head, 0.183, Vector3(0, 0.03, 0.015), hair, Vector3(1.02, 0.9, 1.02))
			Mats.box(head, Vector3(0.3, 0.36, 0.1), Vector3(0, -0.12, 0.11), hair)
		"bun":
			Mats.sphere(head, 0.18, Vector3(0, 0.03, 0.012), hair, Vector3(1.0, 0.88, 1.0))
			Mats.sphere(head, 0.08, Vector3(0, 0.13, 0.13), hair)
		"braid":
			Mats.sphere(head, 0.18, Vector3(0, 0.03, 0.012), hair, Vector3(1.0, 0.88, 1.0))
			Mats.add_mesh(head, Mats.capsule_mesh(0.045, 0.42), hair, Vector3(0, -0.2, 0.15))
		_:
			Mats.sphere(head, 0.18, Vector3(0, 0.04, 0.015), hair, Vector3(1.0, 0.75, 1.0))


func _build_headwear(kind: String, primary: Material, secondary: Material, metal: Material) -> void:
	var gold := Mats.metal(Color("#d9b04a"))
	match kind:
		"circlet":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.16
			torus.outer_radius = 0.19
			Mats.add_mesh(head, torus, gold, Vector3(0, 0.1, 0))
		"crown":
			Mats.cylinder(head, 0.2, 0.18, 0.12, Vector3(0, 0.17, 0), gold, 8)
		"helmet":
			Mats.sphere(head, 0.2, Vector3(0, 0.05, 0), metal, Vector3(1.0, 0.85, 1.0))
			Mats.box(head, Vector3(0.03, 0.12, 0.03), Vector3(0, -0.01, -0.19), metal)
		"straw_hat":
			Mats.cylinder(head, 0.34, 0.34, 0.025, Vector3(0, 0.12, 0), Mats.hex("#d9bf6a"), 14)
			Mats.cylinder(head, 0.12, 0.16, 0.13, Vector3(0, 0.19, 0), Mats.hex("#d9bf6a"), 12)
		"hood":
			Mats.sphere(head, 0.21, Vector3(0, 0.03, 0.03), secondary, Vector3(1.0, 1.0, 1.05))
		"cap":
			Mats.sphere(head, 0.185, Vector3(0, 0.07, 0.01), secondary, Vector3(1.0, 0.6, 1.0))
		"baker_hat":
			Mats.cylinder(head, 0.16, 0.15, 0.22, Vector3(0, 0.2, 0), Mats.hex("#f2efe6"), 12)
		"veil":
			Mats.box(head, Vector3(0.36, 0.38, 0.08), Vector3(0, -0.05, 0.12), Mats.hex("#efe9dc"))
			Mats.sphere(head, 0.185, Vector3(0, 0.05, 0.015), Mats.hex("#efe9dc"), Vector3(1.0, 0.75, 1.0))


func _build_tool(kind: String, metal: Material) -> void:
	var wood := Mats.hex("#6b4a32")
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.6, 0)
	right_arm.add_child(hand)
	match kind:
		"spear":
			Mats.cylinder(hand, 0.025, 0.025, 2.0, Vector3(0, 0.55, -0.05), wood, 6)
			Mats.cylinder(hand, 0.0, 0.05, 0.22, Vector3(0, 1.65, -0.05), metal, 6)
		"sword":
			Mats.box(hand, Vector3(0.05, 0.8, 0.02), Vector3(0, -0.35, 0), metal)
			Mats.box(hand, Vector3(0.2, 0.04, 0.04), Vector3(0, 0.05, 0), Mats.metal(Color("#c9a14a")))
		"hammer":
			Mats.cylinder(hand, 0.02, 0.02, 0.45, Vector3(0, -0.05, -0.1), wood, 6, Vector3(PI * 0.5, 0, 0))
			Mats.box(hand, Vector3(0.09, 0.09, 0.16), Vector3(0, -0.05, -0.32), metal)
		"pitchfork":
			Mats.cylinder(hand, 0.022, 0.022, 1.7, Vector3(0, 0.4, -0.05), wood, 6)
			Mats.box(hand, Vector3(0.22, 0.03, 0.03), Vector3(0, 1.25, -0.05), metal)
			for i in 3:
				Mats.box(hand, Vector3(0.02, 0.2, 0.02), Vector3(-0.09 + i * 0.09, 1.36, -0.05), metal)
		"axe":
			Mats.cylinder(hand, 0.022, 0.022, 0.8, Vector3(0, 0.15, -0.05), wood, 6)
			Mats.box(hand, Vector3(0.03, 0.16, 0.2), Vector3(0, 0.48, -0.13), metal)
		"book":
			Mats.box(hand, Vector3(0.16, 0.2, 0.05), Vector3(0, 0.0, -0.08), Mats.hex("#6a2a2a"))
		"staff":
			Mats.cylinder(hand, 0.025, 0.03, 1.6, Vector3(0, 0.35, -0.06), wood, 6)


## Height of the face (meters, in the parent's space), for cameras and labels.
func head_height() -> float:
	return (0.86 + 0.88) * body_height


## mode: "idle", "walk", "work", "talk". phase advances continuously.
func animate(mode: String, phase: float, delta: float) -> void:
	var k := 1.0 - exp(-12.0 * delta)
	var leg_target := 0.0
	var arm_l := 0.0
	var arm_r := 0.0
	var bob := 0.0
	match mode:
		"walk":
			leg_target = sin(phase) * 0.55
			arm_l = -sin(phase) * 0.45
			arm_r = sin(phase) * 0.45
			bob = absf(sin(phase)) * 0.04
		"work":
			# Positive X rotation swings a limb forward (model faces -Z).
			arm_r = 1.2 + sin(phase * 0.7) * 0.9
			arm_l = 0.3 + sin(phase * 0.7 + 1.0) * 0.2
			bob = absf(sin(phase * 0.7)) * 0.02
		"talk":
			arm_r = 0.4 + sin(phase * 0.5) * 0.35
			bob = sin(phase * 0.3) * 0.006
		_:
			bob = sin(phase * 0.25) * 0.006
	left_leg.rotation.x = lerpf(left_leg.rotation.x, leg_target, k)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, -leg_target, k)
	left_arm.rotation.x = lerpf(left_arm.rotation.x, arm_l, k)
	right_arm.rotation.x = lerpf(right_arm.rotation.x, arm_r, k)
	torso.position.y = 0.86 + bob
	head.position.y = 0.86 + 0.88 + bob
