## 生命值组件 (Health Component)
## GDD: design/gdd/health-system.md
## 通用生命值管理, 可附加到英雄、敌人、塔上

class_name HealthComponent
extends Node

## 最大生命值
@export var max_hp: int = 100

## 是否为玩家 (区分玩家和敌人死亡行为)
@export var is_player: bool = false

var current_hp: int
var is_dead: bool = false

signal hp_changed(current: int, max_hp: int)
signal entity_died(entity: Node)
signal player_died

func _ready() -> void:
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	if amount <= 0:
		return

	current_hp = max(0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)

	if current_hp <= 0:
		_die()

func heal(amount: int) -> void:
	if is_dead:
		return
	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)

func _die() -> void:
	is_dead = true
	if is_player:
		player_died.emit()
	else:
		entity_died.emit(get_parent())
