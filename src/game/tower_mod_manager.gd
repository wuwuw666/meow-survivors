## Tower mod runtime manager
## GDD: design/gdd/tower-mod-system.md
## Notes: MVP debug skeleton for in-run tower mod offers
class_name TowerModManager
extends Node

signal mod_offer_started(offers: Array[Dictionary])
signal mod_selected(mod_data: Dictionary)
signal mod_applied(slot_id: int, mod_data: Dictionary)

const _MOD_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "rapid_bones",
		"name": "Rapid Bones",
		"description": "Attack interval is reduced by 35%.",
		"tower_keys": ["fish", "bow"],
		"effect": {"cooldown_mult": 0.65},
	},
	{
		"id": "barbed_bones",
		"name": "Barbed Bones",
		"description": "Damage +6.",
		"tower_keys": ["fish", "bow"],
		"effect": {"damage_add": 6},
	},
	{
		"id": "heavy_yarn",
		"name": "Heavy Yarn",
		"description": "Damage +4, range +20.",
		"tower_keys": ["yarn"],
		"effect": {"damage_add": 4, "range_add": 20.0},
	},
	{
		"id": "condensed_catnip",
		"name": "Condensed Catnip",
		"description": "Buff is raised to 25% and range is reduced to 100.",
		"tower_keys": ["aura"],
		"effect": {"buff_override": 0.25, "range_override": 100.0},
	},
]

var _current_offers: Array[Dictionary] = []
var _pending_mod: Dictionary = {}

func get_debug_offers(slots: Array[Dictionary], max_count: int = 3) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for mod in _MOD_DEFINITIONS:
		if _has_compatible_slot(slots, mod):
			offers.append(mod.duplicate(true))

	offers.shuffle()
	if offers.size() > max_count:
		offers.resize(max_count)
	return offers

func start_offer(offers: Array[Dictionary]) -> void:
	_current_offers = []
	for offer in offers:
		_current_offers.append(offer.duplicate(true))
	_pending_mod = {}
	mod_offer_started.emit(_current_offers)

func clear_offer_state() -> void:
	_current_offers.clear()
	_pending_mod = {}

func select_offer(mod_id: String) -> Dictionary:
	for offer in _current_offers:
		if String(offer.get("id", "")) == mod_id:
			_pending_mod = offer.duplicate(true)
			mod_selected.emit(_pending_mod)
			return _pending_mod.duplicate(true)
	return {}

func has_pending_mod() -> bool:
	return not _pending_mod.is_empty()

func get_pending_mod() -> Dictionary:
	return _pending_mod.duplicate(true)

func get_compatible_slot_ids(slots: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	if _pending_mod.is_empty():
		return result

	for slot in slots:
		if can_apply_to_slot(slot):
			result.append(int(slot.get("id", -1)))
	return result

func can_apply_to_slot(slot_info: Dictionary) -> bool:
	if _pending_mod.is_empty():
		return false
	if not bool(slot_info.get("occupied", false)):
		return false

	var tower_data: Dictionary = slot_info.get("tower_data", {})
	if tower_data.is_empty():
		return false
	if tower_data.has("applied_mod_id"):
		return false

	var tower_key: String = String(tower_data.get("key", ""))
	var valid_keys: Array = _pending_mod.get("tower_keys", [])
	return valid_keys.has(tower_key)

func apply_pending_mod_to_slot(slot_id: int, slot) -> Dictionary:
	if slot == null or not has_pending_mod():
		return {}
	if not can_apply_to_slot(slot.to_runtime_dict()):
		return {}

	var mod_data: Dictionary = _pending_mod.duplicate(true)
	_apply_mod_effect(slot, mod_data)
	slot.tower_data["applied_mod_id"] = String(mod_data.get("id", ""))
	slot.tower_data["applied_mod_name"] = String(mod_data.get("name", ""))
	slot.tower_data["applied_mod_description"] = String(mod_data.get("description", ""))
	_sync_global_tower_record(slot_id, slot, mod_data)

	clear_offer_state()
	mod_applied.emit(slot_id, mod_data)
	return mod_data

func _has_compatible_slot(slots: Array[Dictionary], mod_data: Dictionary) -> bool:
	for slot in slots:
		if not bool(slot.get("occupied", false)):
			continue
		var tower_data: Dictionary = slot.get("tower_data", {})
		if tower_data.has("applied_mod_id"):
			continue
		if mod_data.get("tower_keys", []).has(String(tower_data.get("key", ""))):
			return true
	return false

func _apply_mod_effect(slot, mod_data: Dictionary) -> void:
	var effect: Dictionary = mod_data.get("effect", {})
	var auto_attack := slot.tower_node.get_node_or_null("AutoAttack") as AutoAttackSystem

	if auto_attack:
		if effect.has("damage_add"):
			auto_attack.base_damage += int(effect.get("damage_add", 0))
		if effect.has("range_add"):
			var range_add: float = float(effect.get("range_add", 0.0))
			auto_attack.base_range += range_add
			auto_attack.attack_range += range_add
		if effect.has("cooldown_mult"):
			var mult: float = float(effect.get("cooldown_mult", 1.0))
			auto_attack.base_cooldown *= mult
			auto_attack.attack_cooldown_sec *= mult

	if effect.has("buff_override"):
		slot.tower_data["buff"] = float(effect.get("buff_override", slot.tower_data.get("buff", 0.15)))
	if effect.has("range_override"):
		slot.tower_data["range"] = float(effect.get("range_override", slot.tower_data.get("range", 0.0)))
	elif effect.has("range_add"):
		slot.tower_data["range"] = float(slot.tower_data.get("range", 0.0)) + float(effect.get("range_add", 0.0))

	if effect.has("damage_add"):
		slot.tower_data["dmg"] = int(slot.tower_data.get("dmg", 0)) + int(effect.get("damage_add", 0))
	if effect.has("cooldown_mult"):
		slot.tower_data["iv"] = float(slot.tower_data.get("iv", 1.0)) * float(effect.get("cooldown_mult", 1.0))

func _sync_global_tower_record(slot_id: int, slot, mod_data: Dictionary) -> void:
	for tower_record in Game.placed_towers:
		if int(tower_record.get("slot_id", -1)) != slot_id:
			continue

		tower_record["key"] = String(slot.tower_data.get("key", ""))
		tower_record["tower_key"] = String(slot.tower_data.get("key", ""))
		tower_record["type"] = String(slot.tower_data.get("type", ""))
		tower_record["damage"] = int(slot.tower_data.get("dmg", 0))
		tower_record["buff"] = float(slot.tower_data.get("buff", 0.15))
		tower_record["range"] = float(slot.tower_data.get("range", 0.0))
		tower_record["applied_mod_id"] = String(mod_data.get("id", ""))
		tower_record["applied_mod_name"] = String(mod_data.get("name", ""))
		return
