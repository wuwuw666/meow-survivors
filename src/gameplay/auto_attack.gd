## 自动攻击系统 (Auto Attack System)
## GDD: design/gdd/auto-attack-system.md
## 猫咪英雄默认攻击行为: 冷却计时 -> 目标查询 -> 发射弹丸 -> 弹丸飞行命中 -> 伤害

class_name AutoAttackSystem
extends Node

## 基础伤害值
@export var base_damage: int = 5

## 攻击射程（像素）
@export var attack_range: float = 150.0

## 基础攻击冷却间隔（秒）
@export var base_cooldown: float = 0.8

## 弹丸飞行速度（像素/秒）
@export var projectile_speed: float = 500.0

## 弹丸场景
@export var projectile_scene: PackedScene

# ---------- 运行时 ----------
var attack_timer: float = 0.0
var attack_cooldown_sec: float = 0.8
var damage_multiplier: float = 1.0
var crit_chance: float = 0.05
var crit_multiplier: float = 1.5

# ---------- 信号 ----------
signal projectile_fired(projectile: Node)
signal projectile_hit_enemy(enemy: Node, damage: int, is_crit: bool)

# ---------- 系统引用 ----------
var _target_system: TargetSystem = null

func _ready() -> void:
	_target_system = get_parent().get_node_or_null("TargetSystem") as TargetSystem
	attack_cooldown_sec = base_cooldown
	# 初始冷却，让玩家入场后才开始攻击
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

	var parent := get_parent() as Node2D
	if parent == null:
		return

	var target := _target_system.get_target(
		parent.global_position,
		attack_range,
		TargetSystem.TargetStrategy.NEAREST
	)
	if target == null:
		return

	_fire_projectile(parent.global_position, target)

## 发射弹丸
func _fire_projectile(from_pos: Vector2, target: Node) -> void:
	var is_crit: bool = randf() < crit_chance
	var dmg: int = _calculate_damage(target)
	if is_crit:
		dmg = int(floor(float(dmg) * crit_multiplier))

	# 创建弹丸
	var proj: Area2D
	if projectile_scene != null:
		proj = projectile_scene.instantiate() as Area2D
	else:
		proj = _make_default_projectile()

	proj.global_position = from_pos
	# 显式且强力地注入弹丸数据
	if proj.has_method("setup"):
		proj.setup(target, dmg, is_crit, projectile_speed)
	else:
		proj.set("damage", dmg)
		proj.set("is_crit", is_crit)
		proj.set("speed", projectile_speed)
		if proj.has_method("_aim_at_target"):
			proj.call("_aim_at_target")

	# 添加到场景树（添加到主场景的弹丸容器）
	var main := get_tree().get_first_node_in_group("main_game")
	if main:
		main.add_child(proj)
		# 连接弹丸命中信号 -> 主游戏显示伤害数字
		if proj.has_signal("hit_enemy"):
			proj.hit_enemy.connect(main._on_projectile_hit)
	else:
		get_parent().get_parent().add_child(proj)

	projectile_fired.emit(proj)

func _make_default_projectile() -> Area2D:
	## 内建 fallback 弹丸（没有预设场景时使用）
	var proj := Area2D.new()
	proj.name = "Projectile"

	# 视觉：黄色小圆点
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	sprite.offset_left = -4.0
	sprite.offset_top = -4.0
	sprite.offset_right = 4.0
	sprite.offset_bottom = 4.0
	sprite.color = Color(1, 0.85, 0.2, 1)  # 金黄色
	proj.add_child(sprite)

	# 碰撞体
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	proj.add_child(shape)

	# 脚本逻辑用内联方式绑定
	var script_node := Node.new()
	script_node.name = "ProjLogic"
	proj.add_child(script_node)

	return proj

func _calculate_damage(_target: Node) -> int:
	var base: int = int(floor(float(base_damage) * damage_multiplier))
	# 应用光环塔加成
	for tw in Game.placed_towers:
		if tw.has("type") and tw.type == "aura":
			base = int(ceil(float(base) * 1.15))
	return max(1, base)

# ---------- 公开 API: 升级系统调用 ----------
func set_damage_bonus(bonus: float) -> void:
	damage_multiplier = 1.0 + bonus

func set_attack_speed_bonus(pct: float) -> void:
	# pct: 百分比加速 0.2 = 20% 更快
	attack_cooldown_sec = max(0.1, base_cooldown * (1.0 - pct))

func set_range_bonus(additional: float) -> void:
	attack_range = max(50.0, 150.0 + additional)

func set_crit_chance(new_chance: float) -> void:
	crit_chance = clampf(new_chance, 0.0, 0.5)

func set_crit_multiplier(new_mult: float) -> void:
	crit_multiplier = max(1.2, new_mult)

func get_current_dps() -> float:
	var expected_damage := float(base_damage) * damage_multiplier
	var crit_bonus := 1.0 + crit_chance * (crit_multiplier - 1.0)
	return (expected_damage / attack_cooldown_sec) * crit_bonus
