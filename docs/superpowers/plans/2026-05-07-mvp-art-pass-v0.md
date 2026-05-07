# MVP Art Pass v0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. This project uses user-confirmed collaboration, so ask before editing code files. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current playable prototype into a clearer, warmer "hometown alley" MVP presentation without committing to final production art.

**Architecture:** Keep art-pass logic lightweight and reversible. Runtime visual creation should be centralized in small helper methods or a dedicated feedback manager instead of adding more unrelated responsibility to `main_game.gd`. Generated art is used as direction reference first; shippable prototype visuals should remain simple Godot-native nodes or small temporary assets.

**Tech Stack:** Godot 4.6, GDScript, existing `MainGame`, `TowerManager`, `EnemyBase`, `Projectile`, and runtime-created 2D nodes.

---

## Source Context

- Gameplay source of truth: `design/gdd/*.md`
- UI and feedback rules: `design/gdd/ui-system.md`
- Tower identity rules: `design/gdd/tower-system.md`
- Enemy readability rules: `design/gdd/enemy-system.md`
- Current refactor priorities: `docs/architecture/refactor-checklist.md`
- Main scene: `scenes/game/main_game.tscn`

## Art Direction

Working name: **Hometown Warm Alley**

Keep:
- Warm hometown lane feeling: tiled roofs, old walls, potted plants, stone path, dusk light.
- Cute cat identity: soft shapes, friendly silhouettes, playful pickups.
- Clear combat readability: player, enemies, towers, projectiles, pickups, and feedback must be distinguishable at a glance.

Avoid:
- Final illustration-level detail in runtime scenes.
- Dark, horror, cyber, or cold sci-fi styling.
- Busy backgrounds that hide enemies or projectiles.
- Large permanent asset pipelines before the core loop is stable.

## File Structure

### Create

- `docs/art-direction/mvp-art-pass-v0.md`
  - Human-readable art direction note for this pass.
  - Defines color roles, entity silhouettes, feedback rules, and what is explicitly out of scope.

- `src/game/art_feedback_manager.gd`
  - Owns short-lived visual effects: placement flash, pickup sparkle, enemy pop/death burst, boss warning accents.
  - Does not own gameplay state, damage, spawning, tower placement, or UI panel decisions.

### Modify

- `src/game/main_game.gd`
  - Bind and call `ArtFeedbackManager`.
  - Keep changes limited to integration points that already spawn feedback or pickups.
  - Do not move unrelated gameplay logic in this pass.

- `src/game/tower_manager.gd`
  - Replace generic tower `ColorRect` visuals with clearer prototype tower visuals.
  - Keep tower behavior unchanged.

- `src/gameplay/enemy_base.gd`
  - Add type-based prototype visual styling for normal, fast, heavy, elite, and boss enemies.
  - Add readable hit/death visual hooks without changing enemy stats.

- `src/gameplay/projectile.gd`
  - Add projectile visual differences for fish/yarn/default shots.
  - Keep hit behavior unchanged.

### Optional Later

- `assets/prototype_art/`
  - Store generated or hand-made temporary PNGs only after deciding a specific image is useful in the playable build.
  - Do not move preview-only brainstorming images here unless they become runtime references.

## Task 1: Write Art Direction Note

**Files:**
- Create: `docs/art-direction/mvp-art-pass-v0.md`

- [ ] **Step 1: Create the note**

Write a concise document with these sections:

```markdown
# MVP Art Pass v0: Hometown Warm Alley

## Goal

Make the current playable prototype feel warmer, clearer, and more game-like while keeping every visual easy to replace.

## Runtime Priorities

1. Readable player, enemy, tower, projectile, and pickup silhouettes.
2. Warm hometown lane atmosphere.
3. Short, satisfying combat feedback.
4. No final-art dependency.

## Palette Roles

- Background warm plaster: `#ead7bd`
- Path stone tan: `#c9b28f`
- Grass/potted green: `#8fbc7a`
- Player cream: `#fff0d2`
- Enemy coral: `#f47c6b`
- Heavy enemy blue: `#78aee8`
- Elite gold: `#f4c95d`
- Boss warm red: `#d95f4b`
- XP aqua: `#63c8ff`
- Coin gold: `#ffd15a`

## Entity Rules

- Player uses a soft cat-head silhouette.
- Normal enemies are round and coral.
- Fast enemies are smaller and brighter.
- Heavy enemies are larger and blue.
- Elite enemies add a gold rim or crown-like accent.
- Boss is much larger, warmer red, and visually heavier.
- Fish tower reads as a small launcher.
- Yarn tower reads as a soft control tower.
- Catnip aura reads as a glowing support ring.

## Feedback Rules

- Hit: brief flash and small damage number.
- Death: small pop/burst, no gore.
- Pickup: coin and XP move or sparkle toward the player/HUD.
- Placement: short warm flash at tower slot.
- Boss: stronger but still cute warning.

## Out Of Scope

- Full animation spritesheets.
- Final character art.
- Full UI redesign.
- Store or meta-progression art.
- Complex background illustration in runtime.
```

- [ ] **Step 2: Review against GDD**

Check that the note still supports:
- `design/gdd/ui-system.md`: feedback clarity and growth source clarity.
- `design/gdd/tower-system.md`: towers as the main defense line.
- `design/gdd/enemy-system.md`: cute but readable threat differences.

Expected: no design conflict. If a conflict appears, stop and ask the user whether to change design or implementation.

## Task 2: Add Art Feedback Manager

**Files:**
- Create: `src/game/art_feedback_manager.gd`
- Modify: `src/game/main_game.gd`

- [ ] **Step 1: Create manager script**

Create `src/game/art_feedback_manager.gd`:

```gdscript
class_name ArtFeedbackManager
extends Node

var _effect_container: Node2D = null

func bind_effect_container(effect_container: Node2D) -> void:
	_effect_container = effect_container

func show_place_flash(world_pos: Vector2, color: Color = Color(1.0, 0.82, 0.36)) -> void:
	_spawn_ring(world_pos, 26.0, color, 0.28)

func show_pickup_sparkle(world_pos: Vector2, color: Color) -> void:
	_spawn_dot(world_pos, color, 0.35)

func show_enemy_pop(world_pos: Vector2, color: Color, scale_multiplier: float = 1.0) -> void:
	_spawn_ring(world_pos, 18.0 * scale_multiplier, color, 0.22)
	_spawn_dot(world_pos + Vector2(0, -8.0 * scale_multiplier), color.lightened(0.25), 0.26)

func show_boss_warning(world_pos: Vector2) -> void:
	_spawn_ring(world_pos, 58.0, Color(1.0, 0.45, 0.28), 0.55)

func _spawn_ring(world_pos: Vector2, radius: float, color: Color, duration: float) -> void:
	if _effect_container == null:
		return
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = color
	ring.closed = true
	ring.position = world_pos
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		ring.add_point(Vector2(cos(angle), sin(angle)) * radius)
	_effect_container.add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector2(1.45, 1.45), duration)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	tween.finished.connect(ring.queue_free)

func _spawn_dot(world_pos: Vector2, color: Color, duration: float) -> void:
	if _effect_container == null:
		return
	var dot := ColorRect.new()
	dot.size = Vector2(10, 10)
	dot.pivot_offset = dot.size * 0.5
	dot.position = world_pos - dot.pivot_offset
	dot.color = color
	_effect_container.add_child(dot)
	var tween := dot.create_tween()
	tween.tween_property(dot, "position:y", dot.position.y - 18.0, duration)
	tween.parallel().tween_property(dot, "modulate:a", 0.0, duration)
	tween.finished.connect(dot.queue_free)
```

- [ ] **Step 2: Bind from `main_game.gd`**

Add a preload and member near the other manager declarations:

```gdscript
const ART_FEEDBACK_MANAGER_SCRIPT := preload("res://src/game/art_feedback_manager.gd")

@onready var art_feedback: ArtFeedbackManager = null
```

In `_setup_components()`, after `feedback` or near other managers:

```gdscript
art_feedback = ART_FEEDBACK_MANAGER_SCRIPT.new()
art_feedback.name = "ArtFeedbackManager"
add_child(art_feedback)
art_feedback.bind_effect_container(effect_container)
```

- [ ] **Step 3: Wire safe feedback calls**

At tower placement success, call:

```gdscript
if art_feedback:
	art_feedback.show_place_flash(tower_node.global_position)
```

At enemy death feedback, call:

```gdscript
if art_feedback:
	var enemy_color := Color(0.96, 0.49, 0.42)
	var pop_scale := 1.0
	if enemy.has_method("get_enemy_type"):
		var enemy_type := String(enemy.get_enemy_type())
		if enemy_type == "boss":
			enemy_color = Color(0.85, 0.37, 0.30)
			pop_scale = 2.0
		elif enemy_type == "elite":
			enemy_color = Color(0.96, 0.79, 0.36)
			pop_scale = 1.35
	art_feedback.show_enemy_pop(enemy.global_position, enemy_color, pop_scale)
```

- [ ] **Step 4: Run syntax check**

Run:

```powershell
F:\godot\Godot_v4.6-stable_win64.exe --headless --path . --check-only
```

Expected: no parse errors.

## Task 3: Improve Tower Prototype Visuals

**Files:**
- Modify: `src/game/tower_manager.gd`

- [ ] **Step 1: Add visual helper methods**

Add helper methods near the bottom of `TowerManager`:

```gdscript
func _build_tower_visual(tower_node: Node2D, tw_data: Dictionary) -> void:
	var tower_key := String(tw_data.get("key", ""))
	match tower_key:
		"fish_shooter":
			_build_fish_tower_visual(tower_node)
		"yarn_launcher":
			_build_yarn_tower_visual(tower_node)
		"catnip_aura":
			_build_catnip_tower_visual(tower_node)
		_:
			_build_default_tower_visual(tower_node)

func _build_default_tower_visual(tower_node: Node2D) -> void:
	var body := ColorRect.new()
	body.size = Vector2(42, 42)
	body.pivot_offset = body.size * 0.5
	body.position = -body.pivot_offset
	body.color = Color(1.0, 0.84, 0.42)
	tower_node.add_child(body)

func _build_fish_tower_visual(tower_node: Node2D) -> void:
	var base := ColorRect.new()
	base.size = Vector2(46, 34)
	base.pivot_offset = base.size * 0.5
	base.position = -base.pivot_offset
	base.color = Color(1.0, 0.76, 0.36)
	tower_node.add_child(base)
	var muzzle := ColorRect.new()
	muzzle.size = Vector2(26, 10)
	muzzle.pivot_offset = muzzle.size * 0.5
	muzzle.position = Vector2(8, -5)
	muzzle.color = Color(1.0, 0.93, 0.68)
	tower_node.add_child(muzzle)

func _build_yarn_tower_visual(tower_node: Node2D) -> void:
	var yarn := Polygon2D.new()
	yarn.color = Color(0.82, 0.60, 1.0)
	var points: PackedVector2Array = []
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		points.append(Vector2(cos(angle), sin(angle)) * 23.0)
	yarn.polygon = points
	tower_node.add_child(yarn)
	var stripe := Line2D.new()
	stripe.width = 3.0
	stripe.default_color = Color(0.58, 0.38, 0.82)
	stripe.add_point(Vector2(-18, -4))
	stripe.add_point(Vector2(18, 6))
	tower_node.add_child(stripe)

func _build_catnip_tower_visual(tower_node: Node2D) -> void:
	var leaf := Polygon2D.new()
	leaf.color = Color(0.48, 0.90, 0.52)
	leaf.polygon = PackedVector2Array([
		Vector2(0, -26), Vector2(18, -8), Vector2(10, 18),
		Vector2(0, 26), Vector2(-10, 18), Vector2(-18, -8)
	])
	tower_node.add_child(leaf)
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(0.65, 1.0, 0.68, 0.65)
	ring.closed = true
	for index in range(36):
		var angle := TAU * float(index) / 36.0
		ring.add_point(Vector2(cos(angle), sin(angle)) * 34.0)
	tower_node.add_child(ring)
```

- [ ] **Step 2: Replace old `ColorRect` tower block**

In `place_tower_on_slot`, replace the existing `ColorRect` sprite creation block with:

```gdscript
_build_tower_visual(tower_node, tw_data)
```

- [ ] **Step 3: Manual verify**

Run the game and place each tower type.

Expected:
- Fish tower reads as a launcher.
- Yarn tower reads as a ball.
- Catnip aura reads as support/ring.
- Tower placement and behavior still work.

## Task 4: Improve Enemy Prototype Visuals

**Files:**
- Modify: `src/gameplay/enemy_base.gd`

- [ ] **Step 1: Locate enemy visual creation**

Find where enemy body/sprite visuals are created or styled. If visuals are currently just a single shape or sprite, preserve node names and add styling around that existing node.

- [ ] **Step 2: Add enemy visual mapping**

Add a helper:

```gdscript
func _get_enemy_visual_config(enemy_type: String) -> Dictionary:
	match enemy_type:
		"normal_a":
			return {"color": Color(1.0, 0.42, 0.36), "radius": 14.0, "accent": Color(1.0, 0.76, 0.68)}
		"normal_b":
			return {"color": Color(0.96, 0.49, 0.42), "radius": 18.0, "accent": Color(1.0, 0.82, 0.72)}
		"normal_c":
			return {"color": Color(0.48, 0.68, 0.92), "radius": 23.0, "accent": Color(0.80, 0.90, 1.0)}
		"elite":
			return {"color": Color(0.96, 0.72, 0.28), "radius": 27.0, "accent": Color(1.0, 0.92, 0.58)}
		"boss":
			return {"color": Color(0.82, 0.31, 0.25), "radius": 48.0, "accent": Color(1.0, 0.66, 0.45)}
	return {"color": Color(0.96, 0.49, 0.42), "radius": 18.0, "accent": Color(1.0, 0.82, 0.72)}
```

- [ ] **Step 3: Apply visual config**

Use the returned config to style the enemy's visual node. If no visual node exists, create one:

```gdscript
func _apply_prototype_visual(enemy_type: String) -> void:
	var config := _get_enemy_visual_config(enemy_type)
	var radius := float(config.get("radius", 18.0))
	var body := Polygon2D.new()
	body.name = "PrototypeBody"
	body.color = config.get("color", Color.WHITE)
	var points: PackedVector2Array = []
	for index in range(28):
		var angle := TAU * float(index) / 28.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	body.polygon = points
	add_child(body)

	var shine := Polygon2D.new()
	shine.name = "PrototypeAccent"
	shine.color = config.get("accent", Color.WHITE)
	shine.polygon = PackedVector2Array([
		Vector2(-radius * 0.35, -radius * 0.35),
		Vector2(radius * 0.10, -radius * 0.45),
		Vector2(radius * 0.02, -radius * 0.12),
		Vector2(-radius * 0.42, -radius * 0.05)
	])
	add_child(shine)
```

Call this once after enemy type/data is known.

- [ ] **Step 4: Manual verify**

Spawn waves until multiple enemy types appear.

Expected:
- Fast enemies are smaller.
- Heavy enemies are larger/blue.
- Elite enemies are gold.
- Boss is clearly oversized and warmer red.

## Task 5: Improve Projectile Visuals

**Files:**
- Modify: `src/gameplay/projectile.gd`

- [ ] **Step 1: Identify projectile tower key**

Find whether `Projectile` receives `tower_key`, damage context, or effect data. Use existing fields only.

- [ ] **Step 2: Add visual helper**

Add:

```gdscript
func _apply_projectile_visual() -> void:
	var key := ""
	if "tower_key" in self:
		key = String(tower_key)
	match key:
		"fish_shooter":
			_make_fish_projectile()
		"yarn_launcher":
			_make_yarn_projectile()
		_:
			_make_default_projectile()

func _make_default_projectile() -> void:
	var body := ColorRect.new()
	body.size = Vector2(12, 6)
	body.pivot_offset = body.size * 0.5
	body.position = -body.pivot_offset
	body.color = Color(1.0, 0.86, 0.42)
	add_child(body)

func _make_fish_projectile() -> void:
	var fish := Polygon2D.new()
	fish.color = Color(1.0, 0.78, 0.42)
	fish.polygon = PackedVector2Array([
		Vector2(10, 0), Vector2(-4, -6), Vector2(-10, 0), Vector2(-4, 6)
	])
	add_child(fish)

func _make_yarn_projectile() -> void:
	var yarn := Polygon2D.new()
	yarn.color = Color(0.78, 0.58, 1.0)
	var points: PackedVector2Array = []
	for index in range(18):
		var angle := TAU * float(index) / 18.0
		points.append(Vector2(cos(angle), sin(angle)) * 7.0)
	yarn.polygon = points
	add_child(yarn)
```

Call `_apply_projectile_visual()` after projectile data is initialized, before it starts moving.

- [ ] **Step 3: Manual verify**

Place fish and yarn towers.

Expected:
- Fish tower shoots fish-like diamond projectiles.
- Yarn tower shoots round purple yarn projectiles.
- Projectile hit behavior remains unchanged.

## Task 6: Add Pickup and Placement Feedback Hooks

**Files:**
- Modify: `src/game/main_game.gd`

- [ ] **Step 1: XP pickup feedback**

Where XP pickup is collected, add:

```gdscript
if art_feedback:
	art_feedback.show_pickup_sparkle(player.global_position, Color(0.39, 0.78, 1.0))
```

- [ ] **Step 2: Coin pickup feedback**

Where coin pickup is collected, add:

```gdscript
if art_feedback:
	art_feedback.show_pickup_sparkle(player.global_position, Color(1.0, 0.82, 0.35))
```

- [ ] **Step 3: Tower placement feedback**

After a tower is placed successfully, add:

```gdscript
if art_feedback:
	art_feedback.show_place_flash(tower_node.global_position)
```

- [ ] **Step 4: Manual verify**

Run a short session.

Expected:
- Picking XP produces aqua sparkle.
- Picking coins produces gold sparkle.
- Placing a tower produces warm flash.
- No gameplay values change.

## Task 7: Hometown Map Atmosphere Pass

**Files:**
- Modify: `scenes/game/main_game.tscn` only if scene-side decorative nodes are preferred.
- Or modify: `src/game/main_game.gd` only if temporary runtime decoration is preferred.

- [ ] **Step 1: Choose implementation style with user**

Ask:

```text
Should the map atmosphere start as fixed decorative scene nodes, or as temporary runtime-generated decoration?
```

Recommended: scene nodes, because visual placement is easier to inspect in Godot.

- [ ] **Step 2: Add low-noise decorations**

Add only:
- warm path tint
- a few potted plants
- low wall blocks
- roof/courtyard hints at screen edges

Do not add details inside combat-critical path areas.

- [ ] **Step 3: Manual verify**

Run the scene.

Expected:
- Enemies and projectiles remain readable.
- Background feels warmer.
- Nothing blocks movement or tower placement unless intentionally configured.

## Verification

Run:

```powershell
F:\godot\Godot_v4.6-stable_win64.exe --headless --path . --check-only
```

Then manually verify:
- Start the main scene.
- Survive at least two waves.
- Place each tower type.
- Observe at least three enemy types.
- Pick up XP and coins.
- Confirm no new parse errors, no startup crash, and no major readability regression.

## Completion Criteria

- Player, enemy, tower, projectile, pickup, and short feedback visuals are clearer than before.
- The game reads warmer and closer to the old-hometown reference direction.
- No gameplay tuning is changed.
- `main_game.gd` receives only minimal integration changes.
- Generated images remain reference material unless explicitly copied into runtime assets.

## Implementation Choice

Before implementation, confirm one of these:

1. **Conservative pass:** Godot-native shapes only, fastest and safest.
2. **Mixed pass:** Godot-native shapes plus 1-3 generated temporary PNGs for background/tower flavor.
3. **Asset-heavy pass:** Generate more PNG assets now. Not recommended until the loop is more stable.

Recommended: **Conservative pass** first, then add generated PNGs only where the shape-based version cannot express the desired feeling.
