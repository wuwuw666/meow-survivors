## 游戏管理器 (Game Manager)
## 单例 autoload, 提供全局访问游戏状态
## 管理: 游戏循环协调、金币/经验/等级追踪、塔状态

class_name GameManager
extends Node

## ---- Session state ----
var player_hp: int = 100
var player_max_hp: int = 100
var player_xp: int = 0
var player_xp_needed: int = 10
var player_level: int = 1
var player_coins: int = 0
var player_damage: int = 5
var player_attack_cooldown: float = 0.8
var player_range: float = 150.0
var player_speed: float = 200.0
var player_speed_mult: float = 1.0

var current_wave: int = 0
var is_paused: bool = false
var is_game_over: bool = false
var _pause_reasons: Dictionary = {}

const PAUSE_REASON_UPGRADE := "upgrade_selection"
const PAUSE_REASON_READY := "ready_phase"
const PAUSE_REASON_GAME_OVER := "game_over"

## Tower tracking
var placed_towers: Array = []

## ---- XP & level ----
func add_xp(amount: int) -> int:
	var levels_gained := 0
	player_xp += amount
	while player_xp >= player_xp_needed:
		player_xp -= player_xp_needed
		player_level += 1
		levels_gained += 1
		player_xp_needed = _calc_xp_needed(player_level)
	return levels_gained

func _calc_xp_needed(level: int) -> int:
	return ceil(10.0 * (1.0 + (level - 1) * 0.3))

## ---- Coins ----
func add_coins(amount: int) -> void:
	player_coins += amount

func spend_coins(amount: int) -> bool:
	if player_coins < amount:
		return false
	player_coins -= amount
	return true

## ---- Health ----
func heal_player(amount: int) -> void:
	player_hp = min(player_max_hp, player_hp + amount)

func set_player_max_hp(new_max: int) -> void:
	player_max_hp = new_max
	player_hp = min(player_hp, player_max_hp)

## ---- Pause ----
func request_pause(reason: String = "manual") -> void:
	if reason.is_empty():
		reason = "manual"
	_pause_reasons[reason] = int(_pause_reasons.get(reason, 0)) + 1
	_sync_pause_state()

func release_pause(reason: String = "manual") -> void:
	if not _pause_reasons.has(reason):
		return

	var next_count := int(_pause_reasons[reason]) - 1
	if next_count > 0:
		_pause_reasons[reason] = next_count
	else:
		_pause_reasons.erase(reason)
	_sync_pause_state()

func clear_pause_requests() -> void:
	_pause_reasons.clear()
	_sync_pause_state()

func _sync_pause_state() -> void:
	is_paused = not _pause_reasons.is_empty()
	var tree := get_tree()
	if tree:
		tree.paused = is_paused and not is_game_over

## ---- Reset ----
func reset_session() -> void:
	player_hp = 20
	player_max_hp = 20
	player_xp = 0
	player_xp_needed = 10
	player_level = 1
	player_coins = 100
	player_damage = 5
	player_attack_cooldown = 0.8
	player_range = 150.0
	player_speed = 200.0
	player_speed_mult = 1.0
	current_wave = 0
	is_game_over = false
	_pause_reasons.clear()
	placed_towers.clear()
	_sync_pause_state()
