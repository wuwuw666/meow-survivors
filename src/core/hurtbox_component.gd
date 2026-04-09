## 受击判定框 (Hurtbox Component)
## 受到 Hitbox 伤害，附带无敌帧机制，并将伤害传递给同级的 HealthComponent
class_name HurtboxComponent
extends Area2D

@export var invincibility_duration: float = 0.5 ## 受击后的无敌时间(秒)

var _is_invincible: bool = false
var _invincible_timer: float = 0.0

signal took_damage(amount: int)

func _ready() -> void:
	monitoring = false
	monitorable = true

func _process(delta: float) -> void:
	if _is_invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0:
			_is_invincible = false

## 尝试接受伤害，如果处于无敌状态则返回 false
func try_take_damage(amount: int) -> bool:
	if _is_invincible:
		return false
	
	# 设置无敌状态
	if invincibility_duration > 0:
		_is_invincible = true
		_invincible_timer = invincibility_duration
		
	# 查找同级的 HealthComponent，自动扣血
	if get_parent():
		var hc = get_parent().get_node_or_null("HealthComponent") as HealthComponent
		if hc:
			hc.apply_damage(amount, {"kind": "contact"})
			took_damage.emit(amount)
			return true
	
	return false
