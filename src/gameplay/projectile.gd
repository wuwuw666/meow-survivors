class_name Projectile
extends Area2D

var speed: float = 500.0
var damage: int = 5
var is_crit: bool = false
var extra_data: Dictionary = {}

var _target: Node2D = null
var _lifetime: float = 3.0
var _hit: bool = false

signal hit_enemy(enemy: Node, dmg: int, crit: bool)

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func setup(target: Node, dmg: int, crit: bool, spd: float, payload: Dictionary = {}) -> void:
	_target = target as Node2D
	damage = dmg
	is_crit = crit
	speed = spd
	extra_data = payload.duplicate(true)
	_aim_at_target()

func _aim_at_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var direction: Vector2 = (_target.global_position - global_position).normalized()
	if not direction.is_zero_approx():
		rotation = direction.angle()

func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0 or _hit:
		queue_free()
		return

	if _target != null and is_instance_valid(_target):
		var target_pos: Vector2 = _target.global_position
		var direction: Vector2 = (target_pos - global_position).normalized()
		if not direction.is_zero_approx():
			var current_angle: float = rotation
			var target_angle: float = direction.angle()
			rotation = lerp_angle(current_angle, target_angle, 15.0 * delta)
			global_position += Vector2.from_angle(rotation) * speed * delta
			if global_position.distance_to(target_pos) < 12.0:
				_do_hit()
	else:
		global_position += Vector2.from_angle(rotation) * speed * delta

func _on_body_entered(body: Node) -> void:
	if _hit:
		return
	if body.is_in_group("enemy") and body.has_node("HealthComponent"):
		_do_hit_to(body)

func _on_area_entered(area: Area2D) -> void:
	if _hit:
		return
	var parent_node: Node = area.get_parent()
	if parent_node.is_in_group("enemy") and parent_node.has_node("HealthComponent"):
		_do_hit_to(parent_node)

func _do_hit() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_do_hit_to(_target)

func _do_hit_to(enemy: Node) -> void:
	if _hit:
		return
	_hit = true

	var health_component: Node = enemy.get_node_or_null("HealthComponent")
	if health_component != null and health_component.has_method("apply_damage"):
		health_component.apply_damage(damage, {"kind": "projectile", "crit": is_crit})
	elif enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	_apply_on_hit_effects(enemy)

	hit_enemy.emit(enemy, damage, is_crit)
	await get_tree().create_timer(0.05).timeout
	queue_free()

func _apply_on_hit_effects(hit_enemy_node: Node) -> void:
	if hit_enemy_node == null or not is_instance_valid(hit_enemy_node):
		return

	var slow_duration: float = float(extra_data.get("slow_duration", 0.0))
	var slow_factor: float = float(extra_data.get("slow_factor", 1.0))
	if slow_duration > 0.0 and hit_enemy_node.has_method("apply_slow"):
		hit_enemy_node.apply_slow(slow_factor, slow_duration)

	var splash_radius: float = float(extra_data.get("splash_slow_radius", 0.0))
	var splash_targets: int = int(extra_data.get("splash_slow_max_targets", 0))
	if splash_radius <= 0.0 or splash_targets <= 0:
		return

	var hit_enemy_body: Node2D = hit_enemy_node as Node2D
	if hit_enemy_body == null:
		return

	var affected: int = 0
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		if affected >= splash_targets:
			break
		if enemy_node == hit_enemy_node or not is_instance_valid(enemy_node) or enemy_node.get("is_dead") == true:
			continue
		var enemy_body: Node2D = enemy_node as Node2D
		if enemy_body == null:
			continue
		if hit_enemy_body.global_position.distance_to(enemy_body.global_position) > splash_radius:
			continue
		if enemy_node.has_method("apply_slow"):
			enemy_node.apply_slow(slow_factor, slow_duration)
			affected += 1
