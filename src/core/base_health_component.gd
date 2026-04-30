## Base durability component
## GDD: design/gdd/health-system.md + settlement-system.md
## Notes: MVP prototype implementation for home-base fail condition
class_name BaseHealthComponent
extends Node

signal hp_changed(current: int, max_hp: int)
signal damage_taken(amount: int, current: int, max_hp: int, context: Dictionary)
signal destroyed

@export var max_hp: int = 5

var current_hp: int = 0
var is_destroyed: bool = false

func _ready() -> void:
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)

func apply_damage(amount: int, context: Dictionary = {}) -> void:
	if is_destroyed:
		return
	if amount <= 0:
		return

	current_hp = maxi(0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)
	damage_taken.emit(amount, current_hp, max_hp, context)

	if current_hp <= 0:
		is_destroyed = true
		destroyed.emit()

func reset_hp() -> void:
	is_destroyed = false
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
