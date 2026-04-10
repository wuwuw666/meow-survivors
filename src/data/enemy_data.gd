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
var player_attack_speed_bonus: float = 0.0
var player_range: float = 150.0
var player_speed: float = 200.0
var player_speed_mult: float = 1.0

var current_wave: int = 0
var is_paused: bool = false
var is_game_over: bool = false
var _pause_reasons: Dictionary = {}

const PAUSE_REASON_UPGRADE: String = "upgrade_selection"
const PAUSE_REASON_READY: String = "ready_phase"
const PAUSE_REASON_GAME_OVER: String = "game_over"
const RECENT_UPGRADE_MEMORY: int = 6
const KNOWN_UPGRADE_CATEGORIES: Array[String] = ["Hero Offense", "Tower Power", "Survival", "Hybrid"]

## Tower tracking
var placed_towers: Array = []
var taken_upgrade_counts: Dictionary = {}
var taken_upgrade_tag_counts: Dictionary = {}
var taken_upgrade_category_counts: Dictionary = {}
var recent_upgrade_offers: Array[String] = []
var upgrade_offer_gap_by_category: Dictionary = {}

## ---- XP & level ----
func add_xp(amount: int) -> int:
	var levels_gained: int = 0
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

	var next_count: int = int(_pause_reasons[reason]) - 1
	if next_count > 0:
		_pause_reasons[reason] = next_count
	else:
		_pause_reasons.erase(reason)
	_sync_pause_state()

func clear_pause_requests() -> void:
	_pause_reasons.clear()
	_sync_pause_state()

## ---- Upgrade tracking ----
func get_upgrade_count(upgrade_id: String) -> int:
	return int(taken_upgrade_counts.get(upgrade_id, 0))

func record_upgrade(upgrade: Dictionary) -> void:
	var upgrade_id: String = String(upgrade.get("id", ""))
	if not upgrade_id.is_empty():
		taken_upgrade_counts[upgrade_id] = get_upgrade_count(upgrade_id) + 1

	var category: String = String(upgrade.get("category", ""))
	if not category.is_empty():
		taken_upgrade_category_counts[category] = int(taken_upgrade_category_counts.get(category, 0)) + 1

	var tags_variant: Variant = upgrade.get("tags", [])
	if typeof(tags_variant) == TYPE_ARRAY:
		for tag_variant in tags_variant as Array:
			var tag_name: String = String(tag_variant)
			if tag_name.is_empty():
				continue
			taken_upgrade_tag_counts[tag_name] = int(taken_upgrade_tag_counts.get(tag_name, 0)) + 1

func get_primary_upgrade_tag() -> String:
	var best_tag: String = ""
	var best_score: int = -1
	for tag_name in taken_upgrade_tag_counts.keys():
		var score: int = int(taken_upgrade_tag_counts[tag_name])
		if score > best_score:
			best_score = score
			best_tag = String(tag_name)
	return best_tag

func get_category_count(category: String) -> int:
	return int(taken_upgrade_category_counts.get(category, 0))

func get_recent_offer_count(upgrade_id: String) -> int:
	var offer_count: int = 0
	for offered_id in recent_upgrade_offers:
		if offered_id == upgrade_id:
			offer_count += 1
	return offer_count

func get_offer_gap_for_category(category: String) -> int:
	return int(upgrade_offer_gap_by_category.get(category, 0))

func record_upgrade_offer_set(upgrades: Array[Dictionary]) -> void:
	var seen_categories: Dictionary = {}
	for offered_upgrade in upgrades:
		var offered_id: String = String(offered_upgrade.get("id", ""))
		if not offered_id.is_empty():
			recent_upgrade_offers.append(offered_id)
		var category: String = String(offered_upgrade.get("category", ""))
		if not category.is_empty():
			seen_categories[category] = true

	while recent_upgrade_offers.size() > RECENT_UPGRADE_MEMORY:
		recent_upgrade_offers.remove_at(0)

	var known_categories: Dictionary = taken_upgrade_category_counts.duplicate(true)
	for category_name in KNOWN_UPGRADE_CATEGORIES:
		known_categories[category_name] = true
	for category_name_variant in upgrade_offer_gap_by_category.keys():
		known_categories[String(category_name_variant)] = true
	for category_name_variant in seen_categories.keys():
		known_categories[String(category_name_variant)] = true

	for category_name_variant in known_categories.keys():
		var category_name: String = String(category_name_variant)
		if category_name.is_empty():
			continue
		if seen_categories.has(category_name):
			upgrade_offer_gap_by_category[category_name] = 0
		else:
			upgrade_offer_gap_by_category[category_name] = int(upgrade_offer_gap_by_category.get(category_name, 0)) + 1

func has_tower_key(tower_key: String) -> bool:
	for tower_entry in placed_towers:
		if String(tower_entry.get("key", "")) == tower_key:
			return true
	return false

func get_tower_count(tower_key: String) -> int:
	var tower_count: int = 0
	for tower_entry in placed_towers:
		if String(tower_entry.get("key", "")) == tower_key:
			tower_count += 1
	return tower_count

func _sync_pause_state() -> void:
	is_paused = not _pause_reasons.is_empty()
	var tree: SceneTree = get_tree()
	if tree:
		tree.paused = is_paused and not is_game_over

## ---- Reset ----
func reset_session() -> void:
	player_hp = 20
	player_max_hp = 20
	player_xp = 0
	player_xp_needed = 10
	player_level = 1
	player_coins = 60
	player_damage = 5
	player_attack_cooldown = 0.8
	player_attack_speed_bonus = 0.0
	player_range = 150.0
	player_speed = 200.0
	player_speed_mult = 1.0
	current_wave = 0
	is_game_over = false
	_pause_reasons.clear()
	placed_towers.clear()
	taken_upgrade_counts.clear()
	taken_upgrade_tag_counts.clear()
	taken_upgrade_category_counts.clear()
	recent_upgrade_offers.clear()
	upgrade_offer_gap_by_category.clear()
	_sync_pause_state()
