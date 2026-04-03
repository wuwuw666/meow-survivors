## 敌人基类 (Enemy Base)
## GDD: design/gdd/enemy-system.md
## 敌人追踪英雄移动、响应伤害、死亡时通知下游

class_name EnemyBase
extends CharacterBody2D

## 敌人类型标识
@export var enemy_type: String = "normal_a"

## 生成动画时长
@export var spawn_anim_duration: float = 0.2

## 死亡动画时长
@export var death_anim_duration: float = 0.4

signal enemy_spawned(enemy: Node)
signal enemy_reached_hero(enemy: Node)

# ---------- 敌人数据表 (外部 JSON 配置) ----------
const ENEMY_DATA_PATH: String = "res://assets/data/enemy_data.json"
var ENEMY_DATA: Dictionary = {}

const ENEMY_LAYER: int = 2
const PLAYER_LAYER: int = 1

# ---------- 运行时 ----------
var _state: String = "SPAWNING"
var _data: Dictionary = {}
var _hero: Node2D = null
var _slow_factor: float = 1.0
var _slow_timer: float = 0.0

# ---------- 波次系统引用 ----------
var _wave_system: Node = null

func _ready() -> void:
	_load_enemy_data()
	_setup_health()
	_setup_collision()
	_find_hero()
	_start_spawn_anim()
	# 注册到 enemy 组
	add_to_group("enemy")
	enemy_spawned.emit(self)

func _physics_process(delta: float) -> void:
	match _state:
		"ACTIVE":
			_move_toward_hero(delta)
		_:
			pass

func _move_toward_hero(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return

	var direction: Vector2 = (_hero.global_position - global_position).normalized()
	if direction.is_zero_approx():
		return

	# 减速计时
	if _slow_timer > 0:
		_slow_timer -= delta
		if _slow_timer <= 0:
			_slow_factor = 1.0

	var effective_speed: float = _data.speed * _slow_factor * _get_wave_speed_multiplier()
	velocity = direction * effective_speed
	move_and_slide()

	# 敌人间分离
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or other.get("is_dead") == true or not is_instance_valid(other):
			continue
		var dist := global_position.distance_to(other.global_position)
		var min_dist := _data.body_size + other.get("_data", {}).get("body_size", 14.0)
		if dist < min_dist and dist > 0.01:
			var push := (global_position - other.global_position).normalized()
			position += push * 0.5

## 敌人减速 (被 yarn launcher 命中)
func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = min(_slow_factor, factor)
	_slow_timer = duration

## 伤害由健康组件处理, 这里只监听死亡信号
func _on_enemy_died() -> void:
	_state = "DYING"
	# 禁用碰撞体
	var cs := $CollisionShape2D as CollisionShape2D
	if cs:
		cs.disabled = true
	# 等死亡动画完成
	await get_tree().create_timer(death_anim_duration).timeout
	queue_free()

# ---------- 私有 ----------
func _load_enemy_data() -> void:
	if ENEMY_DATA.is_empty():
		_load_enemy_table()
	if not ENEMY_DATA.has(enemy_type):
		push_error("EnemyBase: unknown enemy_type '%s'" % enemy_type)
		enemy_type = "normal_a"
	_data = ENEMY_DATA[enemy_type].duplicate()

func _load_enemy_table() -> void:
	var file := FileAccess.open(ENEMY_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("EnemyBase: enemy_data.json not found, using defaults")
		ENEMY_DATA = {
			"normal_a": {"hp": 30, "speed": 90.0, "damage": 10, "body_size": 14.0, "coin": 2, "xp": 3},
			"normal_b": {"hp": 60, "speed": 60.0, "damage": 15, "body_size": 18.0, "coin": 2, "xp": 3},
			"normal_c": {"hp": 120, "speed": 40.0, "damage": 20, "body_size": 22.0, "coin": 3, "xp": 5},
			"elite": {"hp": 300, "speed": 55.0, "damage": 25, "body_size": 24.0, "coin": 8, "xp": 10},
			"boss": {"hp": 1000, "speed": 35.0, "damage": 40, "body_size": 48.0, "coin": 25, "xp": 50},
		}
		return
	var text := file.get_as_text()
	ENEMY_DATA = JSON.parse_string(text)
	if ENEMY_DATA.is_empty():
		push_error("EnemyBase: failed to parse enemy_data.json")

func _setup_health() -> void:
	var hc := get_node_or_null("HealthComponent") as HealthComponent
	if hc == null:
		hc = HealthComponent.new()
		hc.name = "HealthComponent"
		add_child(hc)
	hc.max_hp = _data.hp
	hc.is_player = false
	hc.entity_died.connect(func(_e): _on_enemy_died())

func _setup_collision() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = PLAYER_LAYER | ENEMY_LAYER
	var cs := $CollisionShape2D as CollisionShape2D
	if cs and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = _data.body_size

func _find_hero() -> void:
	_hero = get_tree().get_first_node_in_group("player")

func _start_spawn_anim() -> void:
	$CollisionShape2D.disabled = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, spawn_anim_duration)
	tween.finished.connect(_on_spawn_finished)

func _on_spawn_finished() -> void:
	_state = "ACTIVE"
	$CollisionShape2D.disabled = false

func is_alive() -> bool:
	return not is_dead

func _get_wave_speed_multiplier() -> float:
	if _wave_system == null:
		_wave_system = get_tree().get_first_node_in_group("wave_system")
	if _wave_system and _wave_system.has_method("get_wave_speed_multiplier"):
		return _wave_system.get_wave_speed_multiplier()
	return 1.0
