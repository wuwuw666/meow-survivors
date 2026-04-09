class_name SpawnManager
extends Node

signal enemy_spawned(enemy: EnemyBase)
signal enemy_reached_base(enemy: Node)
signal enemy_died(enemy: Node)
signal enemy_damage_taken(amount: int, current: int, max_hp: int, context: Dictionary, enemy: Node)

var _enemy_container: Node2D = null
var _enemy_scene_path: String = ""
var _paths: Array[PackedVector2Array] = []

func bind_host(enemy_container: Node2D, enemy_scene_path: String) -> void:
	_enemy_container = enemy_container
	_enemy_scene_path = enemy_scene_path

func load_paths_from_node(paths_node: Node2D) -> void:
	_paths.clear()
	if not paths_node:
		push_warning("SpawnManager: No 'Paths' node found.")
		return

	for child in paths_node.get_children():
		if child is Path2D:
			var curve: Curve2D = child.curve
			if curve and curve.point_count > 0:
				var points: PackedVector2Array = curve.get_baked_points()
				_paths.append(points)
				print_rich("[color=green][Paths][/color] 已从节点 %s 加载路径，点数: %d" % [child.name, points.size()])

	if _paths.is_empty():
		push_error("SpawnManager: Paths container is empty!")

func spawn_enemy(enemy_type: String) -> EnemyBase:
	if _enemy_container == null:
		push_error("SpawnManager: enemy container is not bound.")
		return null
	if _enemy_scene_path.is_empty() or not FileAccess.file_exists(_enemy_scene_path):
		push_error("SpawnManager: enemy scene missing at %s" % _enemy_scene_path)
		return null
	if _paths.is_empty():
		push_error("SpawnManager: no paths available for enemy spawn.")
		return null

	var enemy: EnemyBase = load(_enemy_scene_path).instantiate() as EnemyBase
	if enemy == null:
		push_error("SpawnManager: failed to instantiate enemy scene.")
		return null

	enemy.enemy_type = enemy_type

	var path_index: int = randi() % _paths.size()
	var selected_path: PackedVector2Array = _paths[path_index]
	if selected_path.is_empty():
		push_error("SpawnManager: selected path is empty.")
		return null

	enemy.target_path = selected_path
	var jitter := Vector2(randf_range(-20, 20), randf_range(-20, 20))
	enemy.global_position = selected_path[0] + jitter

	print_rich("[color=yellow][Spawn][/color] 敌人: %s, 路径: %d, 始发点: %s" % [enemy_type, path_index + 1, selected_path[0]])

	_enemy_container.add_child(enemy)
	_wire_enemy(enemy)
	enemy_spawned.emit(enemy)
	return enemy

func get_alive_enemy_count() -> int:
	if _enemy_container == null:
		return 0

	var count := 0
	for enemy in _enemy_container.get_children():
		if enemy.has_method("is_alive") and enemy.is_alive():
			count += 1
	return count

func _wire_enemy(enemy: EnemyBase) -> void:
	var hc: HealthComponent = enemy.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.damage_taken.connect(_on_enemy_damage_taken.bind(enemy))
		hc.entity_died.connect(_on_enemy_died)

	enemy.enemy_reached_base.connect(_on_enemy_reached_base)

func _on_enemy_damage_taken(amount: int, current: int, max_hp: int, context: Dictionary, enemy: Node) -> void:
	enemy_damage_taken.emit(amount, current, max_hp, context, enemy)

func _on_enemy_died(enemy: Node) -> void:
	enemy_died.emit(enemy)

func _on_enemy_reached_base(enemy: Node) -> void:
	enemy_reached_base.emit(enemy)
