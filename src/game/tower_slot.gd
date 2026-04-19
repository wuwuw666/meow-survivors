## Tower slot runtime state
## GDD: design/gdd/tower-placement-system.md
## Notes: MVP fixed-slot node wrapper for build / inspect interactions
class_name TowerSlot
extends Node2D

@export var slot_id: int = -1

var occupied: bool = false
var tower_node: Node2D = null
var tower_data: Dictionary = {}

func configure_slot(new_slot_id: int) -> void:
	slot_id = new_slot_id

func reset_runtime_state() -> void:
	occupied = false
	tower_node = null
	tower_data = {}

func can_place() -> bool:
	if occupied:
		return false
	if is_instance_valid(tower_node):
		return false
	return true

func assign_tower(node: Node2D, data: Dictionary) -> void:
	tower_node = node
	tower_data = data.duplicate(true)
	occupied = is_instance_valid(node)

func clear_tower() -> void:
	tower_node = null
	tower_data = {}
	occupied = false

func to_runtime_dict() -> Dictionary:
	return {
		"id": slot_id,
		"node": self,
		"position": global_position,
		"occupied": occupied and is_instance_valid(tower_node),
		"tower_node": tower_node,
		"tower_data": tower_data.duplicate(true),
	}
