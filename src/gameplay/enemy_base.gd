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
signal enemy_reached_base(enemy: Node)

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
var is_dead: bool = false

# 路径追踪逻辑
var target_path: PackedVector2Array = []
var _target_point_index: int = 0

# ---------- 波次系统引用 ----------
var _wave_system: Node = null

# ---------- UI 引用 ----------
var _hp_bar: ProgressBar = null

func _ready() -> void:
	_load_enemy_data()
	_setup_health()
	_setup_health_bar()
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
	if is_dead: return
	
	# 如果没有路径或已抵达终点
	if target_path.is_empty() or _target_point_index >= target_path.size():
		return

	var target_pos: Vector2 = target_path[_target_point_index]
	var dist_to_target := global_position.distance_to(target_pos)
	
	# 抵达当前路点，转向下一个
	if dist_to_target < 10.0:
		_target_point_index += 1
		if _target_point_index >= target_path.size():
			# 抵达基地（终点）
			enemy_reached_base.emit(self)
			return
		target_pos = target_path[_target_point_index]

	var direction: Vector2 = (target_pos - global_position).normalized()
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

	# 敌人间简单的排斥分离
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other) or other.get("is_dead"):
			continue
		var dist: float = global_position.distance_to(other.global_position)
		if dist < 20.0 and dist > 0:
			var push: Vector2 = (global_position - other.global_position).normalized()
			position += push * 40.0 * delta

## 敌人减速 (被 yarn launcher 命中)
func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = min(_slow_factor, factor)
	_slow_timer = duration

## 伤害由健康组件处理, 这里只监听死亡信号
func _on_enemy_died() -> void:
	is_dead = true
	_state = "DYING"
	# 禁用碰撞体
	var cs := $CollisionShape2D as CollisionShape2D
	if cs:
		cs.set_deferred("disabled", true)
	# 隐藏血条
	if _hp_bar:
		_hp_bar.visible = false
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
	var old_hc = get_node_or_null("HealthComponent")
	if old_hc and not old_hc.has_method("take_damage"):
		old_hc.name = "OldHC_Del"
		old_hc.queue_free()
	
	var hc = get_node_or_null("HealthComponent") as HealthComponent
	if not hc:
		hc = HealthComponent.new()
		hc.name = "HealthComponent"
		add_child(hc)
		
	hc.max_hp = _data.hp
	hc.is_player = false
	hc.entity_died.connect(func(_e): _on_enemy_died())
	hc.hp_changed.connect(_on_hp_changed)

func _setup_collision() -> void:
	collision_layer = ENEMY_LAYER
	# Enemies should not body-block the player; damage comes from the hitbox.
	collision_mask = ENEMY_LAYER
	var cs := $CollisionShape2D as CollisionShape2D
	var radius = _data.body_size
	if cs and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = radius
		
	# 动态添加 HitboxComponent 方便伤害碰触到的玩家实体
	var hitbox = HitboxComponent.new()
	hitbox.name = "HitboxComponent"
	hitbox.damage = _data.get("damage", 10)
	hitbox.damage_tick_rate = 1.0 # 如果玩家一直碰到，每秒受到一次伤害
	
	# 设置 Hitbox 层级 (通常监控 Hurtbox，这里设置监控和实体层一致)
	hitbox.collision_mask = PLAYER_LAYER
	hitbox.collision_layer = 0
	
	# 加入一个形状，刚好比本体大一点点
	var hitbox_cs = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius + 2.0
	hitbox_cs.shape = circle
	hitbox.add_child(hitbox_cs)
	
	add_child(hitbox)


func _find_hero() -> void:
	_hero = get_tree().get_first_node_in_group("player")

func _start_spawn_anim() -> void:
	$CollisionShape2D.disabled = true
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, spawn_anim_duration)
	tween.finished.connect(_on_spawn_finished)

func _on_spawn_finished() -> void:
	_state = "ACTIVE"
	$CollisionShape2D.disabled = false

func _on_hp_changed(current: int, max_val: int) -> void:
	if _hp_bar:
		_hp_bar.value = current
		_hp_bar.max_value = max_val
		# 始终显示，而不是只有扣血才显示
		_hp_bar.visible = true

func _setup_health_bar() -> void:
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HealthBar"
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 设置尺寸与位置 (位于敌人中心上方)
	var bar_width := 40.0
	var bar_height := 4.0
	_hp_bar.custom_minimum_size = Vector2(bar_width, bar_height)
	_hp_bar.position = Vector2(-bar_width/2.0, -_data.body_size - 10.0)
	
	# 样式：背景与填充
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.6) # 深灰色透明背景
	sb_bg.set_border_width_all(1)
	sb_bg.border_color = Color(0, 0, 0, 0.8)
	
	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.9, 0.2, 0.2) # 鲜红色填充
	sb_fg.set_border_width_all(1)
	sb_fg.border_color = Color(0, 0, 0, 0)
	
	_hp_bar.add_theme_stylebox_override("background", sb_bg)
	_hp_bar.add_theme_stylebox_override("fill", sb_fg)
	
	# 初始化血量值
	_hp_bar.max_value = _data.hp
	_hp_bar.value = _data.hp
	_hp_bar.visible = true # 满血时也显示
	
	add_child(_hp_bar)

func is_alive() -> bool:
	return not is_dead

func _get_wave_speed_multiplier() -> float:
	if _wave_system == null:
		_wave_system = get_tree().get_first_node_in_group("wave_system")
	if _wave_system and _wave_system.has_method("get_wave_speed_multiplier"):
		return _wave_system.get_wave_speed_multiplier()
	return 1.0
