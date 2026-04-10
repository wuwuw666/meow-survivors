class_name AutoAttackSystem
extends Node

@export var base_damage: int = 5
@export var attack_range: float = 150.0
@export var base_range: float = 150.0
@export var tower_key: String = ""
@export var base_cooldown: float = 0.8
@export var projectile_speed: float = 500.0
@export var projectile_scene: PackedScene

var attack_timer: float = 0.0
var attack_cooldown_sec: float = 0.8
var _global_damage_bonus: float = 0.0
var _local_damage_bonus: float = 0.0
var _global_attack_speed_bonus: float = 0.0
var _local_attack_speed_bonus: float = 0.0
var _global_range_bonus: float = 0.0
var _local_range_bonus: float = 0.0
var damage_multiplier: float = 1.0
var crit_chance: float = 0.05
var crit_multiplier: float = 1.5
var split_target_count: int = 0
var split_damage_ratio: float = 0.65
var slow_factor_on_hit: float = 1.0
var slow_duration_on_hit: float = 0.0
var splash_slow_radius: float = 0.0
var splash_slow_max_targets: int = 0

signal projectile_fired(projectile: Node)
signal projectile_hit_enemy(enemy: Node, damage: int, is_crit: bool)

var _target_system: TargetSystem = null

func _ready() -> void:
	_target_system = get_parent().get_node_or_null("TargetSystem") as TargetSystem
	base_range = attack_range
	_recalculate_stats()
	attack_timer = 0.5

func _process(delta: float) -> void:
	if Game.is_paused or Game.is_game_over:
		return
	attack_timer += delta
	if attack_timer >= attack_cooldown_sec:
		attack_timer = 0.0
		_try_attack()

func _try_attack() -> void:
	if _target_system == null:
		return

	var parent_node: Node2D = get_parent() as Node2D
	if parent_node == null:
		return

	var target: Node = _target_system.get_target(
		parent_node.global_position,
		attack_range,
		TargetSystem.TargetStrategy.NEAREST
	)
	if target == null:
		return

	_fire_projectile(parent_node.global_position, target)

func _fire_projectile(from_pos: Vector2, target: Node) -> void:
	var is_crit: bool = randf() < crit_chance
	var damage: int = _calculate_damage(target)
	if is_crit:
		damage = int(floor(float(damage) * crit_multiplier))

	var payload: Dictionary = _build_projectile_payload()
	_spawn_projectile(from_pos, target, damage, is_crit, payload)

	if split_target_count <= 0:
		return

	var extra_targets: Array[Node] = _get_additional_targets(from_pos, target, split_target_count)
	for extra_target in extra_targets:
		var split_damage: int = max(1, int(round(float(damage) * split_damage_ratio)))
		_spawn_projectile(from_pos, extra_target, split_damage, false, payload)

func _make_default_projectile() -> Area2D:
	var projectile: Area2D = Area2D.new()
	projectile.name = "Projectile"

	var sprite: ColorRect = ColorRect.new()
	sprite.name = "Sprite"
	sprite.offset_left = -4.0
	sprite.offset_top = -4.0
	sprite.offset_right = 4.0
	sprite.offset_bottom = 4.0
	sprite.color = Color(1, 0.85, 0.2, 1)
	projectile.add_child(sprite)

	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	projectile.add_child(shape)

	var script_node: Node = Node.new()
	script_node.name = "ProjLogic"
	projectile.add_child(script_node)

	return projectile

func _calculate_damage(_target: Node) -> int:
	var base: int = int(floor(float(base_damage) * damage_multiplier))
	var owner_node: Node2D = get_parent() as Node2D
	var aura_bonus_sum: float = 0.0

	for tower_entry_variant in Game.placed_towers:
		var tower_entry: Dictionary = tower_entry_variant as Dictionary
		if String(tower_entry.get("type", "")) != "aura":
			continue
		var aura_node: Node2D = tower_entry.get("node") as Node2D
		if owner_node == null or aura_node == null or not is_instance_valid(aura_node):
			continue
		var aura_range: float = float(tower_entry.get("range", 120.0))
		if owner_node.global_position.distance_to(aura_node.global_position) > aura_range:
			continue
		aura_bonus_sum += float(tower_entry.get("buff", 0.12))

	if aura_bonus_sum > 0.0:
		base = int(round(float(base) * (1.0 + minf(aura_bonus_sum, 0.60))))

	return max(1, base)

func set_damage_bonus(bonus: float) -> void:
	_global_damage_bonus = bonus
	_recalculate_stats()

func set_local_damage_bonus(bonus: float) -> void:
	_local_damage_bonus = bonus
	_recalculate_stats()

func set_attack_speed_bonus(pct: float) -> void:
	_global_attack_speed_bonus = pct
	_recalculate_stats()

func set_local_attack_speed_bonus(pct: float) -> void:
	_local_attack_speed_bonus = pct
	_recalculate_stats()

func set_range_bonus(additional: float) -> void:
	_global_range_bonus = additional
	_recalculate_stats()

func set_local_range_bonus(additional: float) -> void:
	_local_range_bonus = additional
	_recalculate_stats()

func configure_tower_behavior(config: Dictionary) -> void:
	split_target_count = int(config.get("split_target_count", 0))
	split_damage_ratio = float(config.get("split_damage_ratio", 0.65))
	slow_factor_on_hit = float(config.get("slow_factor_on_hit", 1.0))
	slow_duration_on_hit = float(config.get("slow_duration_on_hit", 0.0))
	splash_slow_radius = float(config.get("splash_slow_radius", 0.0))
	splash_slow_max_targets = int(config.get("splash_slow_max_targets", 0))

func set_crit_chance(new_chance: float) -> void:
	crit_chance = clampf(new_chance, 0.0, 0.5)

func set_crit_multiplier(new_mult: float) -> void:
	crit_multiplier = max(1.2, new_mult)

func get_current_dps() -> float:
	var expected_damage: float = float(base_damage) * damage_multiplier
	var crit_bonus: float = 1.0 + crit_chance * (crit_multiplier - 1.0)
	return (expected_damage / attack_cooldown_sec) * crit_bonus

func _recalculate_stats() -> void:
	damage_multiplier = 1.0 + _global_damage_bonus + _local_damage_bonus
	var total_attack_speed_bonus: float = _global_attack_speed_bonus + _local_attack_speed_bonus
	attack_cooldown_sec = maxf(0.1, base_cooldown * (1.0 - total_attack_speed_bonus))
	attack_range = maxf(50.0, base_range + _global_range_bonus + _local_range_bonus)

func _spawn_projectile(from_pos: Vector2, target: Node, damage: int, is_crit: bool, payload: Dictionary) -> void:
	var projectile: Area2D
	if projectile_scene != null:
		projectile = projectile_scene.instantiate() as Area2D
	else:
		projectile = _make_default_projectile()

	projectile.global_position = from_pos
	if projectile.has_method("setup"):
		projectile.setup(target, damage, is_crit, projectile_speed, payload)
	else:
		projectile.set("damage", damage)
		projectile.set("is_crit", is_crit)
		projectile.set("speed", projectile_speed)
		if projectile.has_method("_aim_at_target"):
			projectile.call("_aim_at_target")

	var main_game: Node = get_tree().get_first_node_in_group("main_game")
	if main_game:
		main_game.add_child(projectile)
		if projectile.has_signal("hit_enemy") and main_game.has_method("_on_projectile_hit"):
			projectile.connect("hit_enemy", Callable(main_game, "_on_projectile_hit"))
	else:
		get_parent().get_parent().add_child(projectile)

	projectile_fired.emit(projectile)

func _build_projectile_payload() -> Dictionary:
	return {
		"tower_key": tower_key,
		"slow_factor": slow_factor_on_hit,
		"slow_duration": slow_duration_on_hit,
		"splash_slow_radius": splash_slow_radius,
		"splash_slow_max_targets": splash_slow_max_targets
	}

func _get_additional_targets(origin: Vector2, primary_target: Node, extra_count: int) -> Array[Node]:
	var extra_targets: Array[Node] = []
	var candidates: Array[Dictionary] = []
	var range_sq: float = attack_range * attack_range

	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy_node):
			continue
		if enemy_node == primary_target or enemy_node.get("is_dead") == true:
			continue
		var enemy_body: Node2D = enemy_node as Node2D
		if enemy_body == null:
			continue
		var dist_sq: float = origin.distance_squared_to(enemy_body.global_position)
		if dist_sq > range_sq:
			continue
		candidates.append({"enemy": enemy_node, "dist_sq": dist_sq})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("dist_sq", INF)) < float(b.get("dist_sq", INF))
	)

	for candidate in candidates:
		if extra_targets.size() >= extra_count:
			break
		extra_targets.append(candidate.get("enemy") as Node)

	return extra_targets
