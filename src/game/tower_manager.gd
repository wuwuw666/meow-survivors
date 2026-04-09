class_name TowerManager
extends Node

signal tower_placed(pos: Vector2, tower_data: Dictionary)

var _host: Node2D = null
var _projectile_scene: PackedScene = null

func bind_host(host: Node2D, projectile_scene: PackedScene) -> void:
	_host = host
	_projectile_scene = projectile_scene

func can_place_tower_at(pos: Vector2) -> bool:
	for tw_dict in Game.placed_towers:
		if is_instance_valid(tw_dict.node) and pos.distance_to(tw_dict.node.global_position) < 45.0:
			return false
	return true

func build_ghost_tower(tw_data: Dictionary, mouse_pos: Vector2) -> ColorRect:
	var ghost := ColorRect.new()
	ghost.size = Vector2(44, 44)
	ghost.pivot_offset = Vector2(22, 22)
	ghost.position = mouse_pos - Vector2(22, 22)
	ghost.modulate.a = 0.5
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE

	match String(tw_data.get("type", "")):
		"attack":
			ghost.color = Color(1, 0.45, 0.45)
		"control":
			ghost.color = Color(0.45, 0.75, 1.0)
		"aura":
			ghost.color = Color(0.45, 1.0, 0.55)

	return ghost

func place_tower(pos: Vector2, tw_data: Dictionary) -> Node2D:
	if _host == null:
		return null
	if not Game.spend_coins(int(tw_data.get("cost", 0))):
		return null

	var tower_node := Node2D.new()
	tower_node.name = "Tower_%s_%d" % [String(tw_data.get("key", "tower")), randi() % 1000]
	tower_node.global_position = pos
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
		aa.base_damage = int(tw_data.get("dmg", 0))
		aa.attack_range = float(tw_data.get("range", 0.0))
		aa.base_cooldown = float(tw_data.get("iv", 1.0))
		aa.projectile_scene = _projectile_scene
		tower_node.add_child(aa)

	Game.placed_towers.append({
		"node": tower_node,
		"type": String(tw_data.get("type", "")),
		"damage": int(tw_data.get("dmg", 0)),
	})

	tower_placed.emit(pos, tw_data)
	return tower_node
