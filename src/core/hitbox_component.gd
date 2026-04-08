## 伤害判定框 (Hitbox Component)
## 用于给重叠的 Hurtbox 造成持续或单次伤害
class_name HitboxComponent
extends Area2D

@export var damage: int = 10
@export var damage_tick_rate: float = 0.5 ## 持续接触时的伤害频率(秒/次)

var _tick_timer: float = 0.0

func _ready() -> void:
	# 配置为主被动检测：只要本身存在，便主动监控
	monitoring = true
	monitorable = false
	
	# 设置碰撞层掩码：通常 Hitbox 会扫描对方的 Hurtbox 层
	# 默认可以配置，但如果通过组管理也可以。
	
func _process(delta: float) -> void:
	if _tick_timer > 0:
		_tick_timer -= delta
		
	if _tick_timer <= 0:
		var areas = get_overlapping_areas()
		var hit_something = false
		for area in areas:
			if area is HurtboxComponent:
				if area.try_take_damage(damage):
					hit_something = true
		
		# 如果造成了伤害，重置冷却
		if hit_something:
			_tick_timer = damage_tick_rate
