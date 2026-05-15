# Combat Pacing And Equipment Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. This project uses user-confirmed collaboration, so ask before editing code files. Steps use checkbox (`- [ ]`) syntax for tracking. Do not commit unless the user explicitly asks.

**Goal:** Make combat feel pressured but readable by slowing only the over-fast runner, replacing continuous spawn pressure with wave pulses, and changing tower equipment rewards into a non-pausing queue.

**Architecture:** Keep the first implementation conservative. `WaveManager` owns wave pulse timing and pressure valleys, `TowerModManager` owns equipment offer state, and `MainGame` owns UI wiring and player interaction. Avoid a broad refactor of `main_game.gd`; use small helper methods and clear handoff points.

**Tech Stack:** Godot 4.6, GDScript, existing `MainGame`, `WaveManager`, `SpawnManager`, `TowerManager`, `TowerModManager`, `EnemyBase`, and JSON enemy data.

---

## Source Context

- Primary design baseline: `design/gdd/combat-pacing-baseline-v1.md`
- Existing wave design: `design/gdd/wave-system.md`
- Existing difficulty design: `design/gdd/difficulty-curve-system.md`
- Existing spawn design: `design/gdd/enemy-spawn-system.md`
- Existing tower equipment design: `design/gdd/tower-mod-system.md`
- Main scene: `scenes/game/main_game.tscn`

## File Structure

### Modify

- `assets/data/enemy_data.json`
  - First-pass enemy speed tuning.
  - Only reduce the runner speed initially.

- `src/game/wave_manager.gd`
  - Replace continuous per-wave spawning with pulse-based spawning.
  - Add low-pressure windows after equipment rewards.
  - Preserve current public signal surface: `wave_started(wave_num)` and `spawn_requested(enemy_type)`.

- `src/game/tower_mod_manager.gd`
  - Rename behavior conceptually from debug offer flow to equipment supply flow while keeping class name for now.
  - Add queued supplies, active offers, pending equipment, and compatibility helpers.

- `src/game/main_game.gd`
  - Remove pause calls from tower equipment reward flow.
  - Add a small non-pausing equipment queue UI.
  - Add click flow: open supply -> choose equipment -> highlight compatible towers -> attach to tower.
  - Keep XP upgrade pause behavior unchanged unless a task explicitly touches it.

### Do Not Modify In This Pass

- `project.godot`
- `scenes/game/main_game.tscn`, unless a UI node cannot reasonably be created from code.
- Save, unlock, and long-term meta systems.
- Full XP progression redesign.

---

## Task 1: Tune Runner Speed Only

**Files:**
- Modify: `assets/data/enemy_data.json`
- Modify fallback defaults in: `src/gameplay/enemy_base.gd`

- [ ] **Step 1: Change runner data speed**

In `assets/data/enemy_data.json`, change only `normal_a.speed`:

```json
"normal_a": { "role": "runner",  "hp": 42,  "speed": 84.0, "damage": 10, "body_size": 13.0, "coin": 2, "xp": 3 }
```

Expected effect: on the current `~2550 px` path, runner travel time becomes about `30.4s` before wave speed multipliers.

- [ ] **Step 2: Update fallback default**

In `src/gameplay/enemy_base.gd`, inside `_load_enemy_table()` fallback data, change:

```gdscript
"normal_a": {"role": "runner", "hp": 42, "speed": 94.0, "damage": 10, "body_size": 13.0, "coin": 2, "xp": 3},
```

to:

```gdscript
"normal_a": {"role": "runner", "hp": 42, "speed": 84.0, "damage": 10, "body_size": 13.0, "coin": 2, "xp": 3},
```

- [ ] **Step 3: Verify no unrelated enemy tuning changed**

Run:

```powershell
git diff -- assets/data/enemy_data.json src/gameplay/enemy_base.gd
```

Expected: only `normal_a` speed changes from `94` to `84`.

---

## Task 2: Add Pulse Wave Runtime To WaveManager

**Files:**
- Modify: `src/game/wave_manager.gd`

- [ ] **Step 1: Add pulse state fields**

Add these fields near the existing private wave fields:

```gdscript
var _wave_pulses: Array[Dictionary] = []
var _current_pulse_index: int = 0
var _pulse_spawned: int = 0
var _pulse_gap_timer: float = 0.0
var _pressure_valley_timer: float = 0.0
var _spawning_complete: bool = false
```

- [ ] **Step 2: Add a pulse config builder**

Add this method to `WaveManager`:

```gdscript
func _build_wave_pulses(wave_num: int) -> Array[Dictionary]:
	if wave_num == 10:
		return [
			{"count": 1, "interval": 0.1, "gap_after": 2.5, "elite_at": -1, "boss_first": true, "weights": [0.0, 0.0, 0.0]},
			{"count": 8, "interval": 1.05, "gap_after": 1.6, "elite_at": -1, "weights": [0.18, 0.52, 0.30]},
			{"count": 10, "interval": 0.88, "gap_after": 0.0, "elite_at": -1, "weights": [0.22, 0.38, 0.40]},
		]
	if wave_num <= 2:
		return [
			{"count": 6 + wave_num, "interval": 1.85, "gap_after": 3.0, "elite_at": -1, "weights": [0.08, 0.82, 0.10]},
			{"count": 6 + wave_num, "interval": 1.75, "gap_after": 0.0, "elite_at": -1, "weights": [0.14, 0.76, 0.10]},
		]
	if wave_num <= 5:
		var elite_at := 4 if wave_num >= 4 else -1
		return [
			{"count": 8 + wave_num, "interval": 1.45, "gap_after": 2.5, "elite_at": -1, "weights": [0.18, 0.66, 0.16]},
			{"count": 8 + wave_num, "interval": 1.32, "gap_after": 2.0, "elite_at": elite_at, "weights": [0.24, 0.56, 0.20]},
			{"count": 5 + wave_num, "interval": 1.12, "gap_after": 0.0, "elite_at": -1, "weights": [0.28, 0.52, 0.20]},
		]
	if wave_num <= 8:
		return [
			{"count": 10 + wave_num, "interval": 1.18, "gap_after": 2.0, "elite_at": -1, "weights": [0.22, 0.46, 0.32]},
			{"count": 10 + wave_num, "interval": 1.02, "gap_after": 1.8, "elite_at": 5, "weights": [0.24, 0.40, 0.36]},
			{"count": 8 + wave_num, "interval": 0.92, "gap_after": 0.0, "elite_at": -1, "weights": [0.26, 0.36, 0.38]},
		]
	return [
		{"count": 14, "interval": 0.96, "gap_after": 1.6, "elite_at": -1, "weights": [0.24, 0.40, 0.36]},
		{"count": 14, "interval": 0.86, "gap_after": 1.3, "elite_at": 5, "weights": [0.28, 0.34, 0.38]},
		{"count": 14, "interval": 0.78, "gap_after": 0.0, "elite_at": -1, "weights": [0.30, 0.30, 0.40]},
	]
```

- [ ] **Step 3: Replace `_start_wave` setup**

In `_start_wave(wave_num)`, replace the current `if wave_num == 10 ... else ...` block that sets `_total_to_spawn`, `_spawn_interval`, and `_elite_spawn_target` with:

```gdscript
	_wave_pulses = _build_wave_pulses(wave_num)
	_current_pulse_index = 0
	_pulse_spawned = 0
	_pressure_valley_timer = 0.0
	_spawning_complete = _wave_pulses.is_empty()
	_total_to_spawn = 0
	for pulse in _wave_pulses:
		_total_to_spawn += int(pulse.get("count", 0))
	_spawn_count = 0
	_elite_spawn_count = 0
	_spawn_timer = 0.5
	_pulse_gap_timer = 0.0
```

Keep:

```gdscript
	wave_started.emit(wave_num)
```

- [ ] **Step 4: Add pressure valley public method**

Add:

```gdscript
func start_pressure_valley(duration_sec: float = 4.0) -> void:
	_pressure_valley_timer = maxf(_pressure_valley_timer, duration_sec)
```

- [ ] **Step 5: Replace active spawn logic in `_process`**

Replace the section that decrements `_spawn_timer`, calls `_request_spawn()`, increments `_spawn_count`, and checks `_spawn_count < _total_to_spawn` with:

```gdscript
	if _pressure_valley_timer > 0.0:
		_pressure_valley_timer -= delta
		return

	if _pulse_gap_timer > 0.0:
		_pulse_gap_timer -= delta
		return

	if not _spawning_complete:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_request_spawn()
			_spawn_count += 1
			_pulse_spawned += 1

			var pulse := _get_current_pulse()
			_spawn_timer = float(pulse.get("interval", 1.2))
			if _pulse_spawned >= int(pulse.get("count", 0)):
				_current_pulse_index += 1
				_pulse_spawned = 0
				_pulse_gap_timer = float(pulse.get("gap_after", 0.0))
				_spawning_complete = _current_pulse_index >= _wave_pulses.size()

	if not _spawning_complete:
		return
```

Leave the existing alive-enemy clear check after this block.

- [ ] **Step 6: Add current pulse helper**

Add:

```gdscript
func _get_current_pulse() -> Dictionary:
	if _current_pulse_index < 0 or _current_pulse_index >= _wave_pulses.size():
		return {}
	return _wave_pulses[_current_pulse_index]
```

- [ ] **Step 7: Update `_request_spawn` to use pulse data**

Replace `_request_spawn()` with:

```gdscript
func _request_spawn() -> void:
	var pulse := _get_current_pulse()
	if pulse.is_empty():
		return

	if bool(pulse.get("boss_first", false)) and _pulse_spawned == 0:
		spawn_requested.emit("boss")
		return

	if int(pulse.get("elite_at", -1)) == _pulse_spawned:
		_elite_spawn_count += 1
		spawn_requested.emit("elite")
		return

	var weights_variant: Variant = pulse.get("weights", [0.18, 0.72, 0.10])
	var weights: Array[float] = []
	for value in weights_variant:
		weights.append(float(value))
	if weights.size() != 3:
		weights = [0.18, 0.72, 0.10]

	var types: Array[String] = ["normal_a", "normal_b", "normal_c"]
	var total_weight: float = 0.0
	for weight in weights:
		total_weight += weight
	if total_weight <= 0.0:
		spawn_requested.emit("normal_b")
		return

	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	var chosen: String = "normal_b"
	for index in range(types.size()):
		cumulative += weights[index]
		if roll < cumulative:
			chosen = types[index]
			break

	spawn_requested.emit(chosen)
```

- [ ] **Step 8: Run parse check**

Run:

```powershell
godot --headless --path . --check-only
```

Expected: no parse errors. If `godot` is not on PATH, locate the local Godot executable or use the editor's run command manually.

---

## Task 3: Convert Elite Equipment Reward To Non-Pausing Queue

**Files:**
- Modify: `src/game/tower_mod_manager.gd`
- Modify: `src/game/main_game.gd`

- [ ] **Step 1: Add queued supply state to `TowerModManager`**

Add:

```gdscript
signal equipment_supply_queued(queue_size: int)
signal equipment_supply_opened(offers: Array[Dictionary])

const MAX_QUEUED_SUPPLIES: int = 2

var _queued_supply_count: int = 0
```

- [ ] **Step 2: Add queue API to `TowerModManager`**

Add:

```gdscript
func queue_equipment_supply() -> bool:
	if _queued_supply_count >= MAX_QUEUED_SUPPLIES:
		return false
	_queued_supply_count += 1
	equipment_supply_queued.emit(_queued_supply_count)
	return true

func get_queued_supply_count() -> int:
	return _queued_supply_count

func can_open_supply() -> bool:
	return _queued_supply_count > 0 and _current_offers.is_empty() and _pending_mod.is_empty()

func open_next_supply(slots: Array[Dictionary], max_count: int = 3) -> Array[Dictionary]:
	if not can_open_supply():
		return []
	var offers := get_debug_offers(slots, max_count)
	if offers.is_empty():
		return []
	_queued_supply_count -= 1
	start_offer(offers)
	equipment_supply_opened.emit(offers)
	equipment_supply_queued.emit(_queued_supply_count)
	return offers
```

- [ ] **Step 3: Rename user-facing strings in `MainGame` equipment panel**

In `_show_tower_mod_offer_panel`, change:

```gdscript
title.text = "调试塔改造"
subtitle.text = "按 M 打开。先选择一个改造，再点击兼容的塔位装备。"
```

to:

```gdscript
title.text = "塔装备补给"
subtitle.text = "战斗不会暂停。选一个装备，再点击高亮塔位装配。"
```

- [ ] **Step 4: Remove pause from equipment offer open path**

In `_open_debug_tower_mod_offer()`, delete or do not call:

```gdscript
Game.request_pause("tower_mod_offer")
```

In `_try_open_pending_tower_mod_offer()`, this flow will be replaced in Task 4. Do not leave any `Game.request_pause("tower_mod_offer")` call for equipment offers.

- [ ] **Step 5: Remove pause release from equipment selection**

In `_on_tower_mod_offer_selected`, remove:

```gdscript
Game.release_pause("tower_mod_offer")
```

In `_close_tower_mod_offer_flow`, remove:

```gdscript
if Game.is_paused:
	Game.release_pause("tower_mod_offer")
```

Expected behavior: choosing and equipping tower equipment never changes `Game.is_paused`.

---

## Task 4: Add Equipment Queue UI In MainGame

**Files:**
- Modify: `src/game/main_game.gd`

- [ ] **Step 1: Add UI variables**

Near panel variables, add:

```gdscript
var equipment_queue_button: Button
var equipment_queue_label: Label
```

- [ ] **Step 2: Build queue UI**

At the end of `_build_ui()`, after tower shop setup, add:

```gdscript
	var equipment_box := VBoxContainer.new()
	equipment_box.name = "EquipmentQueueBox"
	equipment_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	equipment_box.offset_left = -210
	equipment_box.offset_top = 84
	equipment_box.offset_right = -20
	equipment_box.offset_bottom = 170
	equipment_box.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(equipment_box)

	equipment_queue_label = Label.new()
	equipment_queue_label.text = "塔装备补给 x0"
	equipment_queue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equipment_queue_label.add_theme_font_size_override("font_size", 16)
	equipment_box.add_child(equipment_queue_label)

	equipment_queue_button = Button.new()
	equipment_queue_button.text = "打开补给"
	equipment_queue_button.disabled = true
	equipment_queue_button.custom_minimum_size = Vector2(180, 42)
	equipment_queue_button.pressed.connect(_on_equipment_queue_button_pressed)
	equipment_box.add_child(equipment_queue_button)
```

- [ ] **Step 3: Add queue UI refresh method**

Add:

```gdscript
func _refresh_equipment_queue_ui() -> void:
	if equipment_queue_label == null or equipment_queue_button == null:
		return
	var count := 0
	if tower_mod_manager:
		count = tower_mod_manager.get_queued_supply_count()
	equipment_queue_label.text = "塔装备补给 x%d" % count
	equipment_queue_button.disabled = count <= 0 or _is_waiting_for_mod_target() or (tower_mod_offer_panel and tower_mod_offer_panel.visible)
```

- [ ] **Step 4: Call refresh from `_update_hud()`**

At the end of `_update_hud()`, add:

```gdscript
	_refresh_equipment_queue_ui()
```

- [ ] **Step 5: Add button handler**

Add:

```gdscript
func _on_equipment_queue_button_pressed() -> void:
	if tower_mod_manager == null:
		return
	if Game.is_game_over:
		return
	var offers := tower_mod_manager.open_next_supply(tower_manager.get_all_slots())
	if offers.is_empty():
		_show_floating_text(player.global_position + Vector2(0, -72), "当前没有可装配的塔装备", Color(1.0, 0.8, 0.35))
		_refresh_equipment_queue_ui()
		return
	_show_tower_mod_offer_panel(offers)
	_refresh_equipment_queue_ui()
```

- [ ] **Step 6: Refresh when equipment flow changes**

Add `_refresh_equipment_queue_ui()` at the end of:

```gdscript
_show_tower_mod_offer_panel
_on_tower_mod_offer_selected
_try_apply_pending_mod
_close_tower_mod_offer_flow
```

Expected: the button disables while the player is choosing or attaching equipment.

---

## Task 5: Route Elite Death To Queue And Pressure Valley

**Files:**
- Modify: `src/game/main_game.gd`

- [ ] **Step 1: Replace pending elite offer counter use**

In `_queue_elite_tower_mod_offer(world_pos)`, replace the body with:

```gdscript
func _queue_elite_tower_mod_offer(world_pos: Vector2) -> void:
	if tower_mod_manager == null:
		return
	var queued := tower_mod_manager.queue_equipment_supply()
	if queued:
		_show_floating_text(world_pos + Vector2(0, -32), "获得塔装备补给", Color(1.0, 0.8, 0.35))
	else:
		_show_floating_text(world_pos + Vector2(0, -32), "补给队列已满", Color(1.0, 0.55, 0.35))
	if wave_manager:
		wave_manager.start_pressure_valley(4.0)
	_refresh_equipment_queue_ui()
```

- [ ] **Step 2: Disable automatic offer opening**

Replace `_try_open_pending_tower_mod_offer()` with:

```gdscript
func _try_open_pending_tower_mod_offer() -> void:
	_refresh_equipment_queue_ui()
```

Expected: elite deaths add supplies to the queue but never auto-open a selection panel.

- [ ] **Step 3: Keep debug key but make it non-pausing**

In `_open_debug_tower_mod_offer()`, replace direct offer generation with:

```gdscript
func _open_debug_tower_mod_offer() -> void:
	if tower_mod_manager == null:
		return
	tower_mod_manager.queue_equipment_supply()
	_on_equipment_queue_button_pressed()
```

Expected: pressing `M` still lets developers test equipment without pausing combat.

---

## Task 6: Guard Equipment UI Against Gameplay Blocking

**Files:**
- Modify: `src/game/main_game.gd`

- [ ] **Step 1: Make offer panel non-pausing**

In `_show_tower_mod_offer_panel`, change:

```gdscript
tower_mod_offer_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
```

to:

```gdscript
tower_mod_offer_panel.process_mode = Node.PROCESS_MODE_INHERIT
```

- [ ] **Step 2: Keep offer panel click-blocking only inside its bounds**

Keep:

```gdscript
tower_mod_offer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
```

Expected: the panel itself receives clicks, but the game tree is not paused.

- [ ] **Step 3: Ensure movement still works after panel closes**

After choosing an offer, `_on_tower_mod_offer_selected` should hide the panel and allow normal world clicks:

```gdscript
if tower_mod_offer_panel:
	tower_mod_offer_panel.visible = false
```

Expected: once the player chooses an equipment item, clicking a highlighted tower equips it; clicking elsewhere can still move the player if not on a tower slot.

---

## Task 7: Verify Tower Equipment Attach Flow

**Files:**
- Modify only if bugs are found: `src/game/main_game.gd`, `src/game/tower_mod_manager.gd`

- [ ] **Step 1: Run parse check**

Run:

```powershell
godot --headless --path . --check-only
```

Expected: no parse errors.

- [ ] **Step 2: Manual test debug supply**

Run the main scene and press `M`.

Expected:
- Combat continues.
- Equipment queue increments or opens.
- Opening supply shows 3 choices if compatible towers exist.
- Selecting an item hides the panel.
- Compatible towers highlight.
- Clicking a compatible tower applies the equipment.
- No pause occurs at any point.

- [ ] **Step 3: Manual test elite reward**

Play until an elite dies.

Expected:
- A floating text says `获得塔装备补给`.
- Queue count increments.
- Combat continues.
- The next high-pressure spawn pulse is delayed by about 4 seconds.

---

## Task 8: Verify Pacing Feel Against Baseline

**Files:**
- Modify only if tuning adjustments are needed:
  - `assets/data/enemy_data.json`
  - `src/game/wave_manager.gd`
  - `src/data/tower_data.gd`

- [ ] **Step 1: Check early wave readability**

Play waves 1-2.

Expected:
- Basic enemies are readable from spawn to first tower contact.
- Runner enemies do not dominate the first two waves.
- Player can place at least one tower and see it fire multiple times.

- [ ] **Step 2: Check Fish hit opportunities**

Place one Fish tower near a useful path segment.

Expected:
- A basic enemy crossing that segment receives at least 3 Fish shots in common cases.

- [ ] **Step 3: Check non-pausing equipment usability**

Open and attach a supply during combat.

Expected:
- The decision feels tense but usable.
- If it feels impossible, first increase pressure valley duration from `4.0` to `5.0`, not global enemy speed.

- [ ] **Step 4: Record first-pass tuning findings**

Append a short note to `production/session-logs/session-log.md`:

```markdown
## 2026-05-14 Combat Pacing Playtest

- Runner speed tested: 84 px/s
- Equipment flow: non-pausing queue
- Early wave readability:
- Fish hit opportunities:
- Elite reward usability:
- Next tuning adjustment:
```

Ask the user before writing this log entry.

---

## Completion Criteria

- Runner speed is reduced without globally slowing all enemies.
- Waves spawn in readable pulses instead of uninterrupted pressure.
- Elite rewards enter a queue instead of immediately pausing or opening a modal.
- Tower equipment choice and attachment happen without pausing combat.
- A pressure valley gives the player a fair but non-free window after elite rewards.
- The game still starts from `res://scenes/game/main_game.tscn` with no parse errors.

## Implementation Notes

- This plan intentionally keeps XP upgrade behavior mostly unchanged. Removing tower effects from XP and fully separating long-term build belongs in a later progression redesign pass.
- `TowerModManager` keeps its current class name to avoid broad renaming churn. User-facing text should call the feature "塔装备" or "塔装备补给".
- No commits are included because `AGENTS.md` says not to commit without explicit user request.
