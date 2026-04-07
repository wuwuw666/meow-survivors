# 移动系统 (Movement System)
# GDD: design/gdd/movement-system.md
# 驱动猫咪英雄物理位移，消费输入方向，边界钳制，管理速度加成

class_name MovementSystem
extends Node2D

## 基础移动速度（像素/秒）
@export var base_speed: float = 200.0

## 速度加成倍率（升级系统修改此值）
var speed_multiplier: float = 1.0

var _body: CharacterBody2D

## 移动系统就绪后发出的信号，告知外界 hero_position 可用
signal movement_ready

## 绑定到 CharacterBody2D 节点
func bind_to(body: CharacterBody2D) -> void:
	_body = body
	movement_ready.emit()

## 每帧调用，应用移动
func apply_movement(direction: Vector2, _delta: float) -> void:
	if _body == null:
		return
	if direction == Vector2.ZERO:
		_body.velocity = Vector2.ZERO
		return

	var dir = direction.normalized()
	var current_speed = base_speed * speed_multiplier
	_body.velocity = dir * current_speed
	_body.move_and_slide()

	# 边界钳制（假设地图 1280x720，hero 原点居中）
	var hx = _body.global_position.x
	var hy = _body.global_position.y
	hx = clampf(hx, 30.0, 1250.0)
	hy = clampf(hy, 30.0, 690.0)
	_body.global_position = Vector2(hx, hy)
