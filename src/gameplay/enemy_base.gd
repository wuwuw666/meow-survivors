## Enemy base runtime
## GDD: design/gdd/enemy-system.md
## Handles path movement, health, collision, and death signaling.

class_name EnemyBase
extends CharacterBody2D

@export var enemy_type: String = "normal_a"
@export var spawn_anim_duration: float = 0.2
@export var death_anim_duration: float = 0.4

signal enemy_spawned(enemy: Node)
signal enemy_reached_base(enemy: Node)

const ENEMY_DATA_PATH: String = "res://assets/data/enemy_data.json"
const ENEMY_LAYER: int = 2
const PLAYER_LAYER: int = 1

var ENEMY_DATA: Dictionary = {}

var _state: String = "SPAWNING"
var _data: Dictionary = {}
var _hero: Node2D = null
var _slow_factor: float = 1.0
var _slow_timer: float = 0.0
var is_dead: bool = false

var target_path: PackedVector2Array = []
var _target_point_index: int = 0
var _wave_system: Node = null
var _hp_bar: ProgressBar = null

func _ready() -> void:
	_load_enemy_data()
	_setup_visuals()
	_setup_health()
	_setup_health_bar()
	_setup_collision()
	_find_hero()
	_start_spawn_anim()
	add_to_group("enemy")
	enemy_spawned.emit(self)

func _physics_process(delta: float) -> void:
	match _state:
		"ACTIVE":
			_move_toward_hero(delta)
		_:
			pass

func _move_toward_hero(delta: float) -> void:
	if is_dead:
		return
	if target_path.is_empty() or _target_point_index >= target_path.size():
		return

	var target_pos: Vector2 = target_path[_target_point_index]
	var dist_to_target: float = global_position.distance_to(target_pos)
	if dist_to_target < 10.0:
		_target_point_index += 1
		if _target_point_index >= target_path.size():
			enemy_reached_base.emit(self)
			return
		target_pos = target_path[_target_point_index]

	var direction: Vector2 = (target_pos - global_position).normalized()
	if direction.is_zero_approx():
		return

	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_factor = 1.0

	var effective_speed: float = float(_data.get("speed", 60.0)) * _slow_factor * _get_wave_speed_multiplier()
	velocity = direction * effective_speed
	move_and_slide()

	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other) or other.get("is_dead"):
			continue
		var dist: float = global_position.distance_to(other.global_position)
		if dist < 20.0 and dist > 0.0:
			var push: Vector2 = (global_position - other.global_position).normalized()
			position += push * 40.0 * delta

func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = min(_slow_factor, factor)
	_slow_timer = duration

func _on_enemy_died() -> void:
	is_dead = true
	_state = "DYING"
	var cs := $CollisionShape2D as CollisionShape2D
	if cs:
		cs.set_deferred("disabled", true)
	if _hp_bar:
		_hp_bar.visible = false
	await get_tree().create_timer(death_anim_duration).timeout
	queue_free()

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

	var text: String = file.get_as_text()
	ENEMY_DATA = JSON.parse_string(text)
	if ENEMY_DATA.is_empty():
		push_error("EnemyBase: failed to parse enemy_data.json")

func _setup_health() -> void:
	var old_hc := get_node_or_null("HealthComponent")
	if old_hc and not old_hc.has_method("take_damage"):
		old_hc.name = "OldHC_Del"
		old_hc.queue_free()

	var hc := get_node_or_null("HealthComponent") as HealthComponent
	var max_hp: int = int(_data.get("hp", 30))
	if not hc:
		hc = HealthComponent.new()
		hc.name = "HealthComponent"
		hc.max_hp = max_hp
		add_child(hc)
	else:
		hc.max_hp = max_hp

	hc.current_hp = hc.max_hp
	hc.is_dead = false
	hc.is_player = false
	hc.entity_died.connect(func(_e): _on_enemy_died())
	hc.hp_changed.connect(_on_hp_changed)
	hc.hp_changed.emit(hc.current_hp, hc.max_hp)

func _setup_collision() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = ENEMY_LAYER

	var cs := $CollisionShape2D as CollisionShape2D
	var radius: float = float(_data.get("body_size", 14.0))
	if cs and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = radius

	var hitbox := HitboxComponent.new()
	hitbox.name = "HitboxComponent"
	hitbox.damage = int(_data.get("damage", 10))
	hitbox.damage_tick_rate = 1.0
	hitbox.collision_mask = PLAYER_LAYER
	hitbox.collision_layer = 0

	var hitbox_cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
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
		_hp_bar.visible = true

func _setup_visuals() -> void:
	var sprite := get_node_or_null("Sprite") as ColorRect
	if sprite == null:
		return

	var body_size: float = float(_data.get("body_size", 14.0))
	var diameter: float = body_size * 1.45
	sprite.size = Vector2(diameter, diameter)
	sprite.position = Vector2(-diameter * 0.5, -diameter * 0.5)
	sprite.pivot_offset = sprite.size * 0.5
	sprite.rotation = 0.0
	sprite.color = _get_enemy_fill_color()

	if enemy_type == "elite":
		sprite.rotation = deg_to_rad(45.0)
	elif enemy_type == "boss":
		sprite.size *= 1.12
		sprite.position = Vector2(-sprite.size.x * 0.5, -sprite.size.y * 0.5)
		sprite.pivot_offset = sprite.size * 0.5

func _setup_health_bar() -> void:
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HealthBar"
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar_width: float = 40.0
	var bar_height: float = 4.0
	if enemy_type == "elite":
		bar_width = 58.0
		bar_height = 6.0
	elif enemy_type == "boss":
		bar_width = 88.0
		bar_height = 8.0

	_hp_bar.custom_minimum_size = Vector2(bar_width, bar_height)
	_hp_bar.position = Vector2(-bar_width * 0.5, -float(_data.get("body_size", 14.0)) - 10.0)

	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	sb_bg.set_border_width_all(1)
	sb_bg.border_color = Color(0, 0, 0, 0.8)

	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = _get_health_bar_fill_color()
	sb_fg.set_border_width_all(1)
	sb_fg.border_color = Color(0, 0, 0, 0)

	_hp_bar.add_theme_stylebox_override("background", sb_bg)
	_hp_bar.add_theme_stylebox_override("fill", sb_fg)
	_hp_bar.max_value = int(_data.get("hp", 30))
	_hp_bar.value = int(_data.get("hp", 30))
	_hp_bar.visible = true
	add_child(_hp_bar)

func _get_enemy_fill_color() -> Color:
	match enemy_type:
		"normal_b":
			return Color(0.95, 0.45, 0.3)
		"normal_c":
			return Color(0.75, 0.2, 0.2)
		"elite":
			return Color(1.0, 0.72, 0.22)
		"boss":
			return Color(0.78, 0.28, 1.0)
		_:
			return Color(0.9, 0.2, 0.2)

func _get_health_bar_fill_color() -> Color:
	match enemy_type:
		"elite":
			return Color(1.0, 0.82, 0.3)
		"boss":
			return Color(0.9, 0.35, 1.0)
		_:
			return Color(0.9, 0.2, 0.2)

func is_alive() -> bool:
	return not is_dead

func _get_wave_speed_multiplier() -> float:
	if _wave_system == null:
		_wave_system = get_tree().get_first_node_in_group("wave_system")
	if _wave_system and _wave_system.has_method("get_wave_speed_multiplier"):
		return _wave_system.get_wave_speed_multiplier()
	return 1.0
