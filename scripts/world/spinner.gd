extends Node3D
## Slowly spins a node around its local Z axis (windmill sails).

@export var speed: float = 0.5


func _process(delta: float) -> void:
	rotate_object_local(Vector3.FORWARD, speed * delta)
