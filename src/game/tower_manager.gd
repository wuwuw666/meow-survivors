class_name TowerManager
extends Node

signal tower_placed(slot_id: int, tower_node: Node2D, tower_data: Dictionary)

var _host: Node2D = null
var _projectile_scene: PackedScene = null
var _tower_data = null
var _slots: Array = []
var _slot_nodes_by_id: Dictionary = {}
var _tower_damage_bonus: float = 0.0
var _tower_attack_speed_bonus: float = 0.0
var _tower_range_bonus: float = 0.0
var _tower_cost_multiplier: float = 0.0
var _aura_buff_bonus: float = 0.0
var _fish_split_targets: int = 0
var _yarn_splash_unlocked: bool = false
var _pending_specializations: Dictionary = {}

func bind_host(host: Node2D, projectile_scene: PackedScene) -> void:
	_host = host
	_projectile_scene = projectile_scene

func bind_tower_data(tower_data) -> void:
	_tower_data = tower_data

func get_effective_cost(tw_data: Dictionary) -> int:
	var base_cost: int = int(tw_data.get("cost", 0))
	var scaled: int = int(round(float(base_cost) * (1.0 + _tower_cost_multiplier)))
	return max(scaled, 1)

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

	var tower_cost := get_effective_cost(tw_data)
	if not Game.spend_coins(tower_cost):
		return null

	var index: int = _find_slot_index(slot_id)
	if index == -1:
		return null
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

	var ts := TargetSystem.new()
	ts.name = "TargetSystem"
	tower_node.add_child(ts)

	if String(tw_data.get("type", "")) != "aura":
		var aa := AutoAttackSystem.new()
		aa.name = "AutoAttack"
		aa.tower_key = String(tw_data.get("key", ""))
		aa.base_damage = int(tw_data.get("dmg", 0))
		aa.attack_range = float(tw_data.get("range", 0.0))
		aa.base_range = aa.attack_range
		aa.base_cooldown = float(tw_data.get("iv", 1.0))
		aa.projectile_scene = _projectile_scene
		tower_node.add_child(aa)
		_apply_pending_specialization(tower_node, aa)
		_apply_attack_tower_modifiers(aa)

	var tower_entry := {
		"node": tower_node,
		"slot_id": slot_id,
		"key": String(tw_data.get("key", "")),
		"tower_key": String(tw_data.get("key", "")),
		"type": String(tw_data.get("type", "")),
		"damage": int(tw_data.get("dmg", 0)),
		"cost": tower_cost,
		"range": float(tw_data.get("range", 0.0)),
		"buff": float(tw_data.get("buff", 0.15)) + _aura_buff_bonus,
		"specialization": String(tower_node.get_meta("specialization", "")),
	}
	Game.placed_towers.append(tower_entry)

	slot.assign_tower(tower_node, _build_runtime_tower_data(tw_data, tower_entry))

	tower_placed.emit(slot_id, tower_node, tw_data)
	return tower_node

func apply_upgrade_effect(effect_type: String, value: Variant) -> bool:
	match effect_type:
		"tower_damage_pct":
			_tower_damage_bonus += float(value)
			_refresh_attack_towers()
			return true
		"tower_attack_speed_pct":
			_tower_attack_speed_bonus += float(value)
			_refresh_attack_towers()
			return true
		"tower_range_pct":
			_tower_range_bonus += float(value)
			_refresh_attack_towers()
			return true
		"tower_cost_pct":
			_tower_cost_multiplier += float(value)
			return true
		"aura_buff_flat":
			_aura_buff_bonus += float(value)
			_refresh_aura_towers(float(value))
			return true
		"fish_split_targets":
			_fish_split_targets += int(value)
			_refresh_attack_towers()
			return true
		"yarn_splash_slow_unlock":
			_yarn_splash_unlocked = true
			_refresh_attack_towers()
			return true
		"tower_specialize_fish":
			return _specialize_best_tower("fish")
		"tower_specialize_yarn":
			return _specialize_best_tower("yarn")
	return false

func _build_runtime_tower_data(tw_data: Dictionary, tower_entry: Dictionary) -> Dictionary:
	var runtime_data: Dictionary = tw_data.duplicate(true)
	runtime_data["cost"] = int(tower_entry.get("cost", runtime_data.get("cost", 0)))
	runtime_data["range"] = float(tower_entry.get("range", runtime_data.get("range", 0.0)))
	if runtime_data.has("buff") or tower_entry.has("buff"):
		runtime_data["buff"] = float(tower_entry.get("buff", runtime_data.get("buff", 0.0)))
	return runtime_data

func _refresh_attack_towers() -> void:
	for tw_dict in Game.placed_towers:
		if not tw_dict.has("node"):
			continue
		var tower_node: Node = tw_dict.get("node") as Node
		if not is_instance_valid(tower_node):
			continue
		var aa: AutoAttackSystem = tower_node.get_node_or_null("AutoAttack") as AutoAttackSystem
		if aa == null:
			continue
		_apply_attack_tower_modifiers(aa)

func _refresh_aura_towers(buff_delta: float = 0.0) -> void:
	for idx in range(Game.placed_towers.size()):
		var tw_dict: Dictionary = Game.placed_towers[idx]
		if String(tw_dict.get("type", "")) != "aura":
			continue
		tw_dict["buff"] = float(tw_dict.get("buff", 0.15)) + buff_delta
		Game.placed_towers[idx] = tw_dict

		var slot_id: int = int(tw_dict.get("slot_id", -1))
		var slot = _slot_nodes_by_id.get(slot_id, null)
		if slot and slot.tower_data is Dictionary:
			slot.tower_data["buff"] = tw_dict["buff"]

func _apply_attack_tower_modifiers(auto_attack: AutoAttackSystem) -> void:
	auto_attack.set_damage_bonus(_tower_damage_bonus)
	auto_attack.set_attack_speed_bonus(_tower_attack_speed_bonus)
	var extra_range: float = auto_attack.base_range * _tower_range_bonus
	auto_attack.set_range_bonus(extra_range)
	auto_attack.set_local_damage_bonus(0.0)
	auto_attack.set_local_attack_speed_bonus(0.0)
	auto_attack.set_local_range_bonus(0.0)
	auto_attack.configure_tower_behavior(_build_behavior_for(auto_attack))

	var tower_node := auto_attack.get_parent() as Node2D
	var specialization: String = ""
	if tower_node:
		specialization = String(tower_node.get_meta("specialization", ""))

	match specialization:
		"fish_core":
			auto_attack.set_local_damage_bonus(0.18)
			auto_attack.set_local_range_bonus(auto_attack.base_range * 0.06)
		"yarn_anchor":
			auto_attack.set_local_attack_speed_bonus(0.08)
			auto_attack.set_local_range_bonus(auto_attack.base_range * 0.05)

	_sync_tower_entry(auto_attack)

func _build_behavior_for(auto_attack: AutoAttackSystem) -> Dictionary:
	var behavior := {
		"split_target_count": 0,
		"split_damage_ratio": 0.65,
		"slow_factor_on_hit": 1.0,
		"slow_duration_on_hit": 0.0,
		"splash_slow_radius": 0.0,
		"splash_slow_max_targets": 0
	}

	match auto_attack.tower_key:
		"fish":
			behavior["split_target_count"] = _fish_split_targets
			behavior["split_damage_ratio"] = 0.52
		"yarn":
			behavior["slow_factor_on_hit"] = 0.86
			behavior["slow_duration_on_hit"] = 1.4
			if _yarn_splash_unlocked:
				behavior["splash_slow_radius"] = 72.0
				behavior["splash_slow_max_targets"] = 3

	var tower_node := auto_attack.get_parent() as Node2D
	var specialization: String = ""
	if tower_node:
		specialization = String(tower_node.get_meta("specialization", ""))

	match specialization:
		"fish_core":
			behavior["split_target_count"] = mini(_fish_split_targets + 1, 2)
			behavior["split_damage_ratio"] = 0.60
		"yarn_anchor":
			behavior["slow_factor_on_hit"] = 0.74
			behavior["slow_duration_on_hit"] = 2.2
			behavior["splash_slow_radius"] = 84.0
			behavior["splash_slow_max_targets"] = 4

	return behavior

func _specialize_best_tower(tower_key: String) -> bool:
	var best_tower: Node2D = null
	var best_score: float = -1.0

	for tower_entry in Game.placed_towers:
		if String(tower_entry.get("key", "")) != tower_key:
			continue
		var tower_node := tower_entry.get("node") as Node2D
		if tower_node == null or not is_instance_valid(tower_node):
			continue
		if String(tower_node.get_meta("specialization", "")) != "":
			continue

		var aa := tower_node.get_node_or_null("AutoAttack") as AutoAttackSystem
		if aa == null:
			continue

		var score: float = aa.get_current_dps()
		if score > best_score:
			best_score = score
			best_tower = tower_node

	if best_tower == null:
		_pending_specializations[tower_key] = int(_pending_specializations.get(tower_key, 0)) + 1
		return true

	var specialization_id: String = "fish_core" if tower_key == "fish" else "yarn_anchor"
	_apply_specialization(best_tower, specialization_id)
	return true

func _apply_pending_specialization(tower_node: Node2D, auto_attack: AutoAttackSystem) -> void:
	var pending_count: int = int(_pending_specializations.get(auto_attack.tower_key, 0))
	if pending_count <= 0:
		return
	var specialization_id: String = "fish_core" if auto_attack.tower_key == "fish" else "yarn_anchor"
	_apply_specialization(tower_node, specialization_id)
	_pending_specializations[auto_attack.tower_key] = pending_count - 1

func _apply_specialization(tower_node: Node2D, specialization_id: String) -> void:
	tower_node.set_meta("specialization", specialization_id)
	var sprite: ColorRect = tower_node.get_child(0) as ColorRect
	if sprite:
		match specialization_id:
			"fish_core":
				sprite.color = Color(1.0, 0.72, 0.35)
				sprite.scale = Vector2(1.08, 1.08)
			"yarn_anchor":
				sprite.color = Color(0.45, 0.95, 1.0)
				sprite.scale = Vector2(1.08, 1.08)

	var auto_attack: AutoAttackSystem = tower_node.get_node_or_null("AutoAttack") as AutoAttackSystem
	if auto_attack:
		_apply_attack_tower_modifiers(auto_attack)

func _sync_tower_entry(auto_attack: AutoAttackSystem) -> void:
	var tower_node := auto_attack.get_parent() as Node2D
	if tower_node == null:
		return
	for idx in range(Game.placed_towers.size()):
		var tower_entry: Dictionary = Game.placed_towers[idx]
		if tower_entry.get("node") != tower_node:
			continue
		tower_entry["specialization"] = String(tower_node.get_meta("specialization", ""))
		Game.placed_towers[idx] = tower_entry
		return

func _find_slot_index(slot_id: int) -> int:
	for index in range(_slots.size()):
		if _slots[index].slot_id == slot_id:
			return index
	return -1
