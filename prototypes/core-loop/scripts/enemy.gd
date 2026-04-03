# PROTOTYPE - NOT FOR PRODUCTION
# Date: 2026-04-03
extends Node2D

@export var enemy_type: String = "normal_a"
@export var hp: int = 30
@export var move_speed: float = 60.0
@export var body_radius: float = 14.0

var damage: int = 10
var xp_value: int = 3
var coin_value: int = 2
var is_dead: bool = false
var slow_factor: float = 1.0
var slow_timer: float = 0.0

var player_ref: Node2D
var game_ref = null

const TYPE_COLORS = {
	"normal_a": Color(1.0, 0.6, 0.6),
	"normal_b": Color(0.6, 0.8, 1.0),
	"normal_c": Color(0.6, 1.0, 0.6),
	"elite": Color(1.0, 0.85, 0.0),
	"boss": Color(0.9, 0.2, 0.2),
}

const ENEMY_STATS = {
	"normal_a": {"hp": 30, "speed": 90.0, "damage": 10, "radius": 14.0, "coin": 2, "xp": 3},
	"normal_b": {"hp": 60, "speed": 60.0, "damage": 15, "radius": 18.0, "coin": 2, "xp": 3},
	"normal_c": {"hp": 120, "speed": 40.0, "damage": 20, "radius": 22.0, "coin": 3, "xp": 5},
	"elite": {"hp": 300, "speed": 55.0, "damage": 25, "radius": 24.0, "coin": 8, "xp": 10},
	"boss": {"hp": 1000, "speed": 35.0, "damage": 40, "radius": 48.0, "coin": 25, "xp": 50},
}

func setup_with_player(type_name: String, world_pos: Vector2, player_node: Node2D):
	enemy_type = type_name
	var stats = ENEMY_STATS.get(type_name, ENEMY_STATS["normal_a"])
	hp = stats.hp
	move_speed = stats.speed
	damage = stats.damage
	body_radius = stats.radius
	xp_value = stats.xp
	coin_value = stats.coin
	position = world_pos
	player_ref = player_node
	# game_ref = parent (MainScene)
	game_ref = get_parent().get_parent()
	queue_redraw()

func _draw():
	var color = TYPE_COLORS.get(enemy_type, Color.WHITE)
	draw_circle(Vector2.ZERO, body_radius, color)
	var max_hp = ENEMY_STATS[enemy_type].hp
	var hp_ratio = max(0.0, float(hp) / float(max_hp))
	var bw = body_radius * 1.5
	draw_rect(Rect2(-bw/2, -body_radius - 10, bw, 4), Color(0.3,0,0))
	draw_rect(Rect2(-bw/2, -body_radius - 10, bw * hp_ratio, 4), Color(1,0.2,0.2))

func _physics_process(delta: float):
	if is_dead:
		return
	if game_ref and (game_ref.game_over or game_ref.is_paused):
		return

	if slow_timer > 0:
		slow_timer -= delta
		if slow_timer <= 0:
			slow_factor = 1.0

	if player_ref == null or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player")

	if player_ref == null or not is_instance_valid(player_ref):
		return

	var dir = (player_ref.global_position - global_position).normalized()
	var wave_mult = 1.0
	if game_ref and game_ref.has_method("get_wave_speed_mult"):
		wave_mult = game_ref.get_wave_speed_mult()
	var effective_speed = move_speed * slow_factor * wave_mult
	position += dir * effective_speed * delta

	# separation
	if get_parent():
		for other in get_parent().get_children():
			if other == self or other.get("is_dead") == true or not is_instance_valid(other):
				continue
			var dist = global_position.distance_to(other.global_position)
			var min_dist = body_radius + other.get("body_radius", 14.0)
			if dist < min_dist and dist > 0.01:
				var push = (global_position - other.global_position).normalized()
				position += push * 0.5

	queue_redraw()

func take_damage(amount: int, apply_slow: bool = false):
	if is_dead:
		return
	hp -= amount
	if apply_slow:
		slow_factor = min(slow_factor, 0.7)
		slow_timer = 2.0
	queue_redraw()
	if hp <= 0:
		die()

func die():
	is_dead = true
	if game_ref and game_ref.has_method("on_enemy_died"):
		game_ref.on_enemy_died(global_position, coin_value, xp_value, enemy_type == "boss")
	if game_ref and game_ref.has_method("spawn_death_effect"):
		game_ref.spawn_death_effect(global_position)
	await get_tree().create_timer(0.3).timeout
	queue_free()
