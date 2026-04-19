## Tower definition catalog
## GDD: design/gdd/tower-system.md + design/gdd/tower-placement-system.md
## Notes: MVP prototype data entry for fixed-slot tower building
class_name TowerData
extends RefCounted

const _TOWERS: Array[Dictionary] = [
	{"key": "bow", "name": "Bow Tower", "cost": 30, "dmg": 25, "range": 350.0, "iv": 1.2, "type": "attack"},
	{"key": "fish", "name": "Fish Tower", "cost": 10, "dmg": 12, "range": 180.0, "iv": 1.0, "type": "attack"},
	{"key": "yarn", "name": "Yarn Tower", "cost": 15, "dmg": 6, "range": 150.0, "iv": 1.5, "type": "control"},
	{"key": "aura", "name": "Catnip Tower", "cost": 20, "dmg": 0, "range": 120.0, "iv": 0.0, "type": "aura", "buff": 0.15},
]

func get_all_towers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tower in _TOWERS:
		result.append(tower.duplicate(true))
	return result

func get_tower_by_key(key: String) -> Dictionary:
	for tower in _TOWERS:
		if String(tower.get("key", "")) == key:
			return tower.duplicate(true)
	return {}

func is_valid_tower_key(key: String) -> bool:
	return not get_tower_by_key(key).is_empty()
