## 自动攻击系统 (Auto Attack System)
## GDD: design/gdd/auto-attack-system.md
## 猫咪英雄默认攻击行为控制器, 冷却计时 -> 目标查询 -> 发射弹丸 -> 命中判定 -> 伤害

class_name AutoAttackSystem
extends Node

## 基础伤害值
@export var base_damage: int = 5

## 攻击射程（像素）
@export var attack_range: float = 150.0

## 基础攻击冷却间隔（秒）
@export var base_cooldown: float = 0.8

## 弹丸飞行速度（像素/秒）
@export var projectile_speed: float = 400.0

## 弹丸场景
@export var projectile_scene: PackedScene

# ---------- 运行时 ----------
enum State { Idle, Cooldown, TargetQuery, Firing }
var state: State = State.Idle
var attack_timer: float = 0.0
var attack_cooldown_sec: float = 0.8
var damage_multiplier: float = 1.0
var crit_chance: float = 0.05
var crit_multiplier: float = 1.5

# ---------- 信号 ----------
signal projectile_fired(projectile: Node)
signal projectile_hit_enemy(enemy: Node, damage: int, is_crit: bool)

# ---------- 系统引用 ----------
var _target_system: Node = null

func _ready() -> void:
	_target_system = get_node_or_null("../TargetSystem")
	attack_cooldown_sec = base_cooldown

func _process(delta: float) -> void:
	if Game.is_paused or Game.is_game_over:
		return
	match state:
		State.Cooldown:
			attack_timer += delta
			if attack_timer >= attack_cooldown_sec:
				attack_timer = 0.0
				_try_attack()

func _physics_process(delta: float) -> void:
	pass

func _try_attack() -> void:
	if _target_system == null:
		return

	var parent := get_parent() as Node2D
	if parent == null:
		state = State.Idle
		return

	var target := _target_system.get_target(
		parent.global_position,
		attack_range,
		TargetSystem.TargetStrategy.NEAREST
	)
	if target == null:
		state = State.Idle
		return

	_fire_at(target)

func _fire_at(target: Node) -> void:
	var parent := get_parent() as Node2D
	if parent == null:
		return

	# 直接伤害计算（简化 MVP：弹丸瞬时命中）
	var dmg := _calculate_damage(target)
	var hc := target.get_node_or_null("HealthComponent") as HealthComponent
	if hc and hc.current_hp > 0:
		hc.take_damage(dmg)

	var is_crit := randf() < crit_chance
	if is_crit:
		dmg = floor(dmg * crit_multiplier)

	projectile_hit_enemy.emit(target, dmg, is_crit)
	state = State.Cooldown

func _calculate_damage(target: Node) -> int:
	var base := floor(float(base_damage) * damage_multiplier)
	# 应用光环塔加成
	for tw in Game.placed_towers:
		if tw.has("type") and tw.type == "aura":
			base = ceil(base * 1.15)
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
