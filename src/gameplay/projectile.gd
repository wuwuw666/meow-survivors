## 弹丸 (Projectile)
## 从玩家飞向敌人，命中后造成伤害并产生特效
## 由 AutoAttackSystem 创建和管理

class_name Projectile
extends Area2D

## 飞行速度（像素/秒）
var speed: float = 500.0

## 伤害值
var damage: int = 5

## 是否暴击
var is_crit: bool = false

## 追踪目标
var _target: Node2D = null

## 存活时间（秒），超时自动销毁
var _lifetime: float = 3.0

## 是否已命中（防止重复触发）
var _hit: bool = false

signal hit_enemy(enemy: Node, dmg: int, crit: bool)

func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 2  # enemy layer
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func setup(target: Node, dmg: int, crit: bool, spd: float) -> void:
	_target = target as Node2D
	damage = dmg
	is_crit = crit
	speed = spd
	_aim_at_target()

func _aim_at_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dir := (_target.global_position - global_position).normalized()
	if not dir.is_zero_approx():
		rotation = dir.angle()

func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0 or _hit:
		queue_free()
		return

	# 追踪目标
	if _target != null and is_instance_valid(_target):
		var target_pos: Vector2 = _target.global_position
		var dir := (target_pos - global_position).normalized()
		if not dir.is_zero_approx():
			# 平滑转向（轻微追踪）
			var current_angle: float = rotation
			var target_angle: float = dir.angle()
			rotation = lerp_angle(current_angle, target_angle, 15.0 * delta)
			global_position += Vector2.from_angle(rotation) * speed * delta

			# 检测是否足够接近目标
			if global_position.distance_to(target_pos) < 12.0:
				_do_hit()
	else:
		# 目标已消失，沿最后方向飞行
		global_position += Vector2.from_angle(rotation) * speed * delta

func _on_body_entered(body: Node) -> void:
	if _hit:
		return
	# 检查是否命中敌人
	if body.is_in_group("enemy") and body.has_node("HealthComponent"):
		_do_hit_to(body)

func _on_area_entered(area: Area2D) -> void:
	if _hit:
		return
	var parent := area.get_parent()
	if parent.is_in_group("enemy") and parent.has_node("HealthComponent"):
		_do_hit_to(parent)

func _do_hit() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_do_hit_to(_target)

func _do_hit_to(enemy: Node) -> void:
	if _hit:
		return
	_hit = true

	# 造成伤害
	var hc: Node = enemy.get_node_or_null("HealthComponent")
	if hc and hc.has_method("take_damage"):
		hc.apply_damage(damage, {"kind": "projectile", "crit": is_crit})
	elif enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	hit_enemy.emit(enemy, damage, is_crit)
	# 延迟销毁（让命中特效显示一帧）
	await get_tree().create_timer(0.05).timeout
	queue_free()
