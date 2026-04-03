# PROTOTYPE - NOT FOR PRODUCTION
# Game state embedded in main scene, no autoload needed
# Date: 2026-04-03
extends Node2D

# ---- Game state (session) ----
var player_hp: int = 100
var player_max_hp: int = 100
var player_xp: int = 0
var player_xp_needed: int = 10
var player_level: int = 1
var player_coins: int = 0
var player_damage: int = 5
var player_attack_speed: float = 0.8
var player_speed: float = 200.0
var player_range: float = 150.0

var current_wave: int = 1
var total_waves: int = 10
var is_paused: bool = false
var game_over: bool = false

var towers: Array = []
const TOWER_SLOTS = [
	Vector2(400, 300),
	Vector2(640, 180),
	Vector2(880, 300),
	Vector2(520, 450),
	Vector2(760, 450),
]

var slot_occupied: Array[bool] = [false, false, false, false, false]

const TOWER_DATA = {
	"fish_shooter": {
		"name": "小鱼干发射器",
		"type": "attack",
		"damage": 12,
		"range": 180.0,
		"attack_interval": 1.0,
		"cost": 10,
	},
	"yarn_launcher": {
		"name": "毛线球发射器",
		"type": "control",
		"damage": 6,
		"range": 150.0,
		"attack_interval": 1.5,
		"slow_factor": 0.7,
		"slow_duration": 2.0,
		"cost": 15,
	},
	"catnip_aura": {
		"name": "猫薄荷光环塔",
		"type": "aura",
		"range": 120.0,
		"aura_buff": 0.15,
		"cost": 20,
	},
}

func calc_xp_needed(level: int) -> int:
	return ceil(10.0 * (1.0 + (level - 1) * 0.3))

func add_xp(amount: int):
	player_xp += amount
	while player_xp >= player_xp_needed:
		player_xp -= player_xp_needed
		player_level += 1
		player_xp_needed = calc_xp_needed(player_level)
		get_tree().paused = true
		is_paused = true
		_on_level_up()

func _on_level_up():
	pass  # overridden by main_scene.gd script subclass

func take_damage(amount: int):
	player_hp = max(0, player_hp - amount)
	if player_hp <= 0:
		game_over = true

func calc_final_damage(tower_type: String = "") -> int:
	var base = player_damage
	if tower_type != "":
		if TOWER_DATA.has(tower_type):
			base = TOWER_DATA[tower_type].damage
	for tw in towers:
		if tw.has("tower_type") and tw.tower_type == "catnip_aura":
			base = ceil(base * 1.15)
	return base

func get_wave_speed_mult() -> float:
	return 1.0 + (current_wave - 1) * 0.03
