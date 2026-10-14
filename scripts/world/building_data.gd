class_name BuildingData
extends RefCounted
## One placed building. Pure data: the 3D look is produced by BuildingFactory
## from the building's type definition (data/buildings.json).

var id: int = -1
var type: String = "cottage"
var name: String = ""
## Ground position of the building's center.
var position: Vector3 = Vector3.ZERO
## Yaw in radians. The door is on the local +Z side.
var rotation: float = 0.0
## Width (x) and depth (z) of the footprint in meters.
var footprint: Vector2 = Vector2(6, 5)
var variant: int = 0


func type_def() -> Dictionary:
	return GameData.building_type(type)


func type_name() -> String:
	return str(type_def().get("name", type.capitalize()))


func basis() -> Basis:
	return Basis(Vector3.UP, rotation)


## Point just outside the front door, where people enter and leave.
func door_position() -> Vector3:
	return position + basis() * Vector3(0, 0, footprint.y * 0.5 + 1.2)


## Direction the front of the building faces.
func forward() -> Vector3:
	return basis() * Vector3(0, 0, 1)


## A spot in front of the building where a worker stands. `slot` spreads
## several workers apart.
func work_spot(slot: int) -> Vector3:
	var side := (slot % 3 - 1) * 1.6
	var depth := 2.4 + floori(slot / 3.0) * 1.2
	return position + basis() * Vector3(side, 0, footprint.y * 0.5 + depth)


## Rough radius used to keep things from overlapping.
func radius() -> float:
	return footprint.length() * 0.5


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"name": name,
		"pos": [snappedf(position.x, 0.01), snappedf(position.z, 0.01)],
		"rot": snappedf(rotation, 0.0001),
		"size": [footprint.x, footprint.y],
		"variant": variant,
	}


static func from_dict(d: Dictionary) -> BuildingData:
	var b := BuildingData.new()
	b.id = int(d.get("id", -1))
	b.type = str(d.get("type", "cottage"))
	b.name = str(d.get("name", ""))
	var p: Array = d.get("pos", [0, 0])
	b.position = Vector3(float(p[0]), 0.0, float(p[1]))
	b.rotation = float(d.get("rot", 0.0))
	var s: Array = d.get("size", [6, 5])
	b.footprint = Vector2(float(s[0]), float(s[1]))
	b.variant = int(d.get("variant", 0))
	return b
