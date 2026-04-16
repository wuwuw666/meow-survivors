class_name TowerManager
extends Node

signal tower_placed(slot_id: int, tower_node: Node2D, tower_data: Dictionary)

var _host: Node2D = null
var _projectile_scene: PackedScene = null
var _tower_data = null
var _slots: Array = []
var _slot_nodes_by_id: Dictionary = {}

func bind_host(host: Node2D, projectile_scene: PackedScene) -> void:
	_host = host
	_projectile_scene = projectile_scene

func bind_tower_data(tower_data) -> void:
	_tower_data = tower_data

func load_slots_from_node(slots_root: Node) -> void:
	_slots.clear()
	_slot_nodes_by_id.clear()
	if slots_root == null:
		push_warning("TowerManager: No TowerSlots node found.")
		return

	var slot_id: int = 0
	for child in slots_root.get_children():
		if child.has_method("configure_slot") and child.has_method("reset_runtime_state"):
			var slot_node = child
			slot_node.configure_slot(slot_id)
			slot_node.reset_runtime_state()
			_slots.append(slot_node)
			_slot_nodes_by_id[slot_id] = slot_node
			slot_id += 1

func get_all_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in _slots:
		result.append(slot.to_runtime_dict())
	return result

func get_slot_data(slot_id: int) -> Dictionary:
	var index := _find_slot_index(slot_id)
	if index == -1:
		return {}
	return _slots[index].to_runtime_dict()

func get_slot_node(slot_id: int):
	return _slot_nodes_by_id.get(slot_id, null)

func can_place_on_slot(slot_id: int) -> bool:
	var index := _find_slot_index(slot_id)
	if index == -1:
		return false

	return _slots[index].can_place()

func find_slot_id_at_position(world_pos: Vector2, radius: float = 36.0) -> int:
	var best_slot_id: int = -1
	var best_distance_sq: float = radius * radius
	for slot in _slots:
		var dist_sq: float = slot.global_position.distance_squared_to(world_pos)
		if dist_sq <= best_distance_sq:
			best_distance_sq = dist_sq
			best_slot_id = slot.slot_id
	return best_slot_id

func get_tower_on_slot(slot_id: int) -> Node2D:
	var index := _find_slot_index(slot_id)
	if index == -1:
		return null
	return _slots[index].tower_node

func place_tower_on_slot(slot_id: int, tower_key: String) -> Node2D:
	if _host == null:
		return null
	if _tower_data == null:
		push_error("TowerManager: tower data is not bound.")
		return null
	if not can_place_on_slot(slot_id):
		return null

	var tw_data: Dictionary = _tower_data.get_tower_by_key(tower_key)
	if tw_data.is_empty():
		push_warning("TowerManager: invalid tower key %s" % tower_key)
		return null
	if not Game.spend_coins(int(tw_data.get("cost", 0))):
		return null

	var index: int = _find_slot_index(slot_id)
	var slot = _slots[index]
	var slot_pos: Vector2 = slot.global_position

	var tower_node := Node2D.new()
	tower_node.name = "Tower_%s_%d" % [String(tw_data.get("key", "tower")), randi() % 1000]
	tower_node.global_position = slot_pos
	_host.add_child(tower_node)

	var sprite := ColorRect.new()
	sprite.size = Vector2(44, 44)
	sprite.pivot_offset = Vector2(22, 22)
	sprite.position = Vector2(-22, -22)
	match String(tw_data.get("type", "")):
		"attack":
			sprite.color = Color(1, 0.45, 0.45)
		"control":
			sprite.color = Color(0.45, 0.75, 1.0)
		"aura":
			sprite.color = Color(0.45, 1.0, 0.55)
	tower_node.add_child(sprite)

	var ts = TargetSystem.new()
	ts.name = "TargetSystem"
	tower_node.add_child(ts)

	if String(tw_data.get("type", "")) != "aura":
		var aa = AutoAttackSystem.new()
		aa.name = "AutoAttack"
		aa.base_damage = int(tw_data.get("dmg", 0))
		aa.attack_range = float(tw_data.get("range", 0.0))
		aa.base_cooldown = float(tw_data.get("iv", 1.0))
		aa.projectile_scene = _projectile_scene
		tower_node.add_child(aa)

	Game.placed_towers.append({
		"node": tower_node,
		"slot_id": slot_id,
		"tower_key": String(tw_data.get("key", "")),
		"type": String(tw_data.get("type", "")),
		"damage": int(tw_data.get("dmg", 0)),
		"buff": float(tw_data.get("buff", 0.15)),
		"range": float(tw_data.get("range", 0.0)),
	})

	slot.assign_tower(tower_node, tw_data)

	tower_placed.emit(slot_id, tower_node, tw_data)
	return tower_node

func _find_slot_index(slot_id: int) -> int:
	for index in range(_slots.size()):
		if _slots[index].slot_id == slot_id:
			return index
	return -1
