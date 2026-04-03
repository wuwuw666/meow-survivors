## 目标选择系统 (Target Selection System)
## GDD: design/gdd/target-selection-system.md
## 输入攻击者位置和射程，返回最优敌人

class_name TargetSystem
extends Node

enum TargetStrategy {
	NEAREST,
	LOWEST_HP,
	HIGHEST_HP,
	FASTEST,
}

var _enemies_in_range: Array[Node] = []

## 查询最优目标
## origin: 攻击发者位置
## range: 射程（像素）
## strategy: 策略（MVP 仅 NEAREST 有效）
func get_target(origin: Vector2, range: float, strategy: TargetStrategy = TargetStrategy.NEAREST) -> Node:
	_enemies_in_range.clear()

	var tree := get_tree()
	if tree == null:
		return null

	var group := tree.get_nodes_in_group("enemy")
	var range_sq := range * range

	for enemy: Node in group:
		if enemy.get("is_dead") == true or not is_instance_valid(enemy):
			continue
		var dist_sq := origin.distance_squared_to(enemy.global_position)
		if dist_sq <= range_sq:
			_enemies_in_range.append(enemy)

	if _enemies_in_range.is_empty():
		return null

	return _select_best(origin, strategy)

func _select_best(origin: Vector2, strategy: TargetStrategy) -> Node:
	match strategy:
		TargetStrategy.NEAREST:
			return _nearest(origin)
		TargetStrategy.LOWEST_HP:
			return _lowest_hp()
		TargetStrategy.HIGHEST_HP:
			return _highest_hp()
		_:
			push_warning("TargetSystem: unknown strategy '%s', falling back to NEAREST" % strategy)
			return _nearest(origin)

func _nearest(origin: Vector2) -> Node:
	var best: Node = null
	var best_dist_sq: float = INF
	for e: Node in _enemies_in_range:
		var d := origin.distance_squared_to(e.global_position)
		if d < best_dist_sq:
			best_dist_sq = d
			best = e
	return best

func _lowest_hp() -> Node:
	var best: Node = null
	var best_hp: int = INF
	for e: Node in _enemies_in_range:
		var hc := e.get_node_or_null("HealthComponent")
		if hc == null:
			continue
		if hc.current_hp < best_hp:
			best_hp = hc.current_hp
			best = e
	return best

func _highest_hp() -> Node:
	var best: Node = null
	var best_hp: int = -1
	for e: Node in _enemies_in_range:
		var hc := e.get_node_or_null("HealthComponent")
		if hc == null:
			continue
		if hc.current_hp > best_hp:
			best_hp = hc.current_hp
			best = e
	return best
