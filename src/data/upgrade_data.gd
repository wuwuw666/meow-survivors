class_name UpgradeData
extends RefCounted

const DATA_PATH: String = "res://assets/data/upgrade_data.json"

var _upgrades: Array[Dictionary] = []

func _init() -> void:
	_load()

func get_candidates(current_wave: int, count: int = 3) -> Array[Dictionary]:
	if _upgrades.is_empty():
		return []

	var wave_num: int = maxi(current_wave, 1)
	var primary_tag: String = Game.get_primary_upgrade_tag()
	var pool: Array[Dictionary] = []
	for upgrade in _upgrades:
		var candidate: Dictionary = upgrade.duplicate(true) as Dictionary
		if not _is_upgrade_available(candidate, wave_num):
			continue
		candidate["computed_weight"] = _compute_weight(candidate, wave_num, primary_tag)
		pool.append(candidate)

	if pool.is_empty():
		return []

	var weighted_pool: Array[Dictionary] = pool.duplicate()
	var picked: Array[Dictionary] = []
	while picked.size() < count and not weighted_pool.is_empty():
		var next_upgrade: Dictionary = _pick_weighted(weighted_pool)
		if next_upgrade.is_empty():
			break
		picked.append(next_upgrade)
		_remove_upgrade(weighted_pool, String(next_upgrade.get("id", "")))

	_apply_soft_guarantees(picked, pool, wave_num, primary_tag)
	Game.record_upgrade_offer_set(picked)
	return picked

func _load() -> void:
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("UpgradeData: failed to open %s" % DATA_PATH)
		return

	var json: JSON = JSON.new()
	var parse_error: int = json.parse(file.get_as_text())
	if parse_error != OK:
		push_warning("UpgradeData: failed to parse %s" % DATA_PATH)
		return

	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		push_warning("UpgradeData: root is not a dictionary")
		return

	var root_dict: Dictionary = root as Dictionary
	var raw_upgrades: Variant = root_dict.get("upgrades", [])
	if typeof(raw_upgrades) != TYPE_ARRAY:
		push_warning("UpgradeData: upgrades is not an array")
		return

	var raw_upgrade_array: Array = raw_upgrades as Array
	_upgrades.clear()
	for item in raw_upgrade_array:
		if typeof(item) == TYPE_DICTIONARY:
			_upgrades.append(((item as Dictionary).duplicate(true) as Dictionary))

func _pick_weighted(pool: Array[Dictionary]) -> Dictionary:
	var total_weight: float = 0.0
	for item in pool:
		total_weight += maxf(float(item.get("computed_weight", item.get("weight", 1.0))), 0.01)

	if total_weight <= 0.0:
		return {}

	var cursor: float = randf() * total_weight
	var acc: float = 0.0
	for item in pool:
		acc += maxf(float(item.get("computed_weight", item.get("weight", 1.0))), 0.01)
		if cursor <= acc:
			return item

	return pool.back() as Dictionary

func _remove_upgrade(pool: Array[Dictionary], upgrade_id: String) -> void:
	for idx in range(pool.size() - 1, -1, -1):
		if String(pool[idx].get("id", "")) == upgrade_id:
			pool.remove_at(idx)
			return

func _is_upgrade_available(upgrade: Dictionary, wave_num: int) -> bool:
	if int(upgrade.get("min_wave", 1)) > wave_num:
		return false

	var upgrade_id: String = String(upgrade.get("id", ""))
	var max_stacks: int = int(upgrade.get("max_stacks", 1))
	if not upgrade_id.is_empty() and Game.get_upgrade_count(upgrade_id) >= max_stacks:
		return false

	var requires_tower_key: String = String(upgrade.get("requires_tower_key", ""))
	if not requires_tower_key.is_empty() and not Game.has_tower_key(requires_tower_key):
		return false

	var prerequisites_variant: Variant = upgrade.get("prerequisites", [])
	if typeof(prerequisites_variant) == TYPE_ARRAY:
		var prerequisites: Array = prerequisites_variant as Array
		for prereq_variant in prerequisites:
			var prereq_id: String = String(prereq_variant)
			if prereq_id.is_empty():
				continue
			if Game.get_upgrade_count(prereq_id) <= 0:
				return false

	var excludes_variant: Variant = upgrade.get("excludes", [])
	if typeof(excludes_variant) == TYPE_ARRAY:
		var excludes: Array = excludes_variant as Array
		for exclude_variant in excludes:
			var exclude_id: String = String(exclude_variant)
			if exclude_id.is_empty():
				continue
			if Game.get_upgrade_count(exclude_id) > 0:
				return false

	return true

func _compute_weight(upgrade: Dictionary, wave_num: int, primary_tag: String) -> float:
	var weight: float = float(upgrade.get("weight", 1.0))
	var category: String = String(upgrade.get("category", ""))
	var tags: Array = upgrade.get("tags", []) as Array
	var rarity: String = String(upgrade.get("rarity", "Common"))
	var upgrade_id: String = String(upgrade.get("id", ""))
	var requires_tower_key: String = String(upgrade.get("requires_tower_key", ""))

	match rarity:
		"Rare":
			weight *= 0.72
		"Epic":
			weight *= 0.45

	if wave_num <= 3 and category == "Tower Power":
		weight *= 1.25

	if wave_num <= 2 and category == "Hero Offense":
		weight *= 0.80

	if wave_num <= 4 and category == "Hybrid":
		weight *= 0.55

	if wave_num >= int(upgrade.get("min_wave", 1)) + 2 and rarity != "Common":
		weight *= 1.10

	if not primary_tag.is_empty():
		for tag_variant in tags:
			if String(tag_variant) == primary_tag:
				weight *= 1.35
				if tags.has("hybrid"):
					weight *= 1.08
				break

	if category == "Tower Power" and Game.get_category_count("Tower Power") == 0 and wave_num <= 3:
		weight *= 1.35

	if category == "Survival" and wave_num >= 4 and Game.get_category_count("Survival") == 0:
		weight *= 1.15

	if Game.get_offer_gap_for_category(category) >= 2:
		weight *= 1.25

	if not requires_tower_key.is_empty():
		var owned_tower_count: int = Game.get_tower_count(requires_tower_key)
		weight *= 1.0 + minf(float(owned_tower_count) * 0.12, 0.36)

	var recent_offer_count: int = Game.get_recent_offer_count(upgrade_id)
	if recent_offer_count > 0:
		weight *= pow(0.78, recent_offer_count)

	return maxf(weight, 0.01)

func _apply_soft_guarantees(picked: Array[Dictionary], pool: Array[Dictionary], wave_num: int, primary_tag: String) -> void:
	if picked.is_empty():
		return

	if wave_num <= 2 and not _has_category(picked, "Hero Offense"):
		var hero_candidate: Dictionary = _find_best_candidate(pool, "Hero Offense", "")
		if not hero_candidate.is_empty():
			picked[0] = hero_candidate

	if wave_num <= 3 and not _has_category(picked, "Tower Power"):
		var tower_candidate: Dictionary = _find_best_candidate(pool, "Tower Power", "")
		if not tower_candidate.is_empty():
			picked[picked.size() - 1] = tower_candidate

	if wave_num <= 3 and not _has_category(picked, "Survival") and not _has_category(picked, "Tower Power"):
		var fallback_candidate: Dictionary = _find_best_candidate(pool, "Survival", "")
		if fallback_candidate.is_empty():
			fallback_candidate = _find_best_candidate(pool, "Tower Power", "")
		if not fallback_candidate.is_empty():
			picked[picked.size() - 1] = fallback_candidate

	if not primary_tag.is_empty() and not _has_tag(picked, primary_tag):
		var tag_candidate: Dictionary = _find_best_candidate(pool, "", primary_tag)
		if not tag_candidate.is_empty():
			picked[picked.size() - 1] = tag_candidate

	_deduplicate_picks(picked, pool)

func _find_best_candidate(pool: Array[Dictionary], category: String, tag_name: String) -> Dictionary:
	var best: Dictionary = {}
	var best_weight: float = -1.0
	for candidate in pool:
		var candidate_id: String = String(candidate.get("id", ""))
		if candidate_id.is_empty():
			continue
		if not category.is_empty() and String(candidate.get("category", "")) != category:
			continue
		if not tag_name.is_empty() and not _candidate_has_tag(candidate, tag_name):
			continue
		var weight: float = float(candidate.get("computed_weight", candidate.get("weight", 1.0)))
		if weight > best_weight:
			best_weight = weight
			best = candidate
	return best

func _has_category(picks: Array[Dictionary], category: String) -> bool:
	for pick in picks:
		if String(pick.get("category", "")) == category:
			return true
	return false

func _has_tag(picks: Array[Dictionary], tag_name: String) -> bool:
	for pick in picks:
		if _candidate_has_tag(pick, tag_name):
			return true
	return false

func _candidate_has_tag(candidate: Dictionary, tag_name: String) -> bool:
	var tags_variant: Variant = candidate.get("tags", [])
	if typeof(tags_variant) != TYPE_ARRAY:
		return false
	var tags: Array = tags_variant as Array
	for tag_variant in tags:
		if String(tag_variant) == tag_name:
			return true
	return false

func _deduplicate_picks(picked: Array[Dictionary], pool: Array[Dictionary]) -> void:
	var seen_ids: Dictionary = {}
	for idx in range(picked.size()):
		var pick_id: String = String(picked[idx].get("id", ""))
		if pick_id.is_empty():
			continue
		if not seen_ids.has(pick_id):
			seen_ids[pick_id] = true
			continue

		for candidate in pool:
			var candidate_id: String = String(candidate.get("id", ""))
			if candidate_id.is_empty() or seen_ids.has(candidate_id):
				continue
			picked[idx] = candidate
			seen_ids[candidate_id] = true
			break
