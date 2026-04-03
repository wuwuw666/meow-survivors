# PROTOTYPE - NOT FOR PRODUCTION
# Date: 2026-04-03
extends CharacterBody2D

@export var hp: int = 100
@export var max_hp: int = 100
@export var speed: float = 200.0
@export var attack_damage: int = 5
@export var attack_cooldown: float = 0.8
@export var attack_range: float = 150.0

var attack_timer: float = 0.0
var invincible_timer: float = 0.0
const INVINCIBLE_DURATION: float = 1.2

var game

func _ready():
	# Get reference to the game state (grandparent = MainScene)
	game = get_parent().get_parent()
	if game.has_method("_ready_player_ref"):
		game._ready_player_ref(self)

func _physics_process(delta: float):
	if game and (game.game_over or game.is_paused):
		return

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"): input_dir.y -= 1
	if Input.is_action_pressed("move_down"): input_dir.y += 1
	if Input.is_action_pressed("move_left"): input_dir.x -= 1
	if Input.is_action_pressed("move_right"): input_dir.x += 1

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()

	velocity = input_dir * speed
	move_and_slide()

	position.x = clampf(position.x, 40, 1240)
	position.y = clampf(position.y, 40, 680)

	if invincible_timer > 0:
		invincible_timer -= delta

	attack_timer += delta
	if game and attack_timer >= attack_cooldown and not game.game_over and not game.is_paused:
		attack_timer = 0.0
		_try_attack()

func _try_attack():
	if game == null:
		return
	var enemy_container = game.get_node_or_null("EnemyContainer")
	if enemy_container == null:
		return

	var best_enemy = null
	var best_dist_sq = attack_range * attack_range

	for enemy in enemy_container.get_children():
		if enemy.get("is_dead") == true or not is_instance_valid(enemy):
			continue
		var d: float = global_position.distance_squared_to(enemy.global_position)
		if d < best_dist_sq:
			best_dist_sq = d
			best_enemy = enemy

	if best_enemy == null:
		return

	var dmg = game.calc_final_damage()
	if "take_damage" in best_enemy:
		best_enemy.take_damage(dmg, false)

	if game.has_method("spawn_damage_number"):
		game.spawn_damage_number(best_enemy.global_position, dmg, false)
