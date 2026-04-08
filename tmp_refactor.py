import re

file_path = r"f:\Project\gameB\meow-survivors\src\game\main_game.gd"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Replace Wave variables
content = re.sub(
    r"# Wave state.*?var _boss_spawned: bool = false\n",
    "# Wave state\nvar wave_manager: WaveManager = null\n",
    content,
    flags=re.DOTALL
)

# 2. Add HurtboxComponent and WaveManager to _setup_components
old_setup = """func _setup_components() -> void:
	# Hero health
	hero_health = HealthComponent.new()
	hero_health.name = "HealthComponent"
	hero_health.is_player = true
	player.add_child(hero_health)"""

new_setup = """func _setup_components() -> void:
	# Wave Manager
	wave_manager = WaveManager.new()
	wave_manager.name = "WaveManager"
	wave_manager.bind_main_game(self)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.spawn_requested.connect(_on_spawn_requested)
	add_child(wave_manager)

	# Hero health
	hero_health = HealthComponent.new()
	hero_health.name = "HealthComponent"
	hero_health.is_player = true
	player.add_child(hero_health)
	
	# Hurtbox for Player
	var hurtbox = HurtboxComponent.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.invincibility_duration = 0.5
	hurtbox.collision_mask = 0
	hurtbox.collision_layer = 1 # PLAYER_LAYER = 1
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	hurtbox.add_child(shape)
	player.add_child(hurtbox)"""

content = content.replace(old_setup, new_setup)

# 3. Modify _show_ready_ui btn.pressed function
content = re.sub(
    r"btn\.pressed\.connect\(func\(\):\n\s*_game_started = true\n\s*_start_wave\(1\)\n\s*btn\.queue_free\(\)\n\s*\)",
    "btn.pressed.connect(func():\n\t\t_game_started = true\n\t\twave_manager.enable_waves()\n\t\tbtn.queue_free()\n\t)",
    content
)

# 4. Remove wave logic from _process
content = re.sub(
    r"\s*if not Game\.is_paused and not _wave_active and _game_started:.*?if current_wave % 10 != 0:\n\s*_wave_cooldown = 2\.5",
    "",
    content,
    flags=re.DOTALL
) # Wait regex might be tricky if it doesn't match exactly. I will use a more robust regex for _process wave logic.

# Better: Look for "# wave spawn" and remove up to "if _is_dragging_tower"
content = re.sub(
    r"\s*if not Game\.is_paused and not _wave_active and _game_started:.*?(?=if _is_dragging_tower)",
    "\n\n\t",
    content,
    flags=re.DOTALL
)

# 5. Remove _start_wave, _spawn_basic_enemy, _spawn_boss_enemy entirely.
content = re.sub(
    r"# ========== Wave system ==========.*?func _spawn_enemy",
    "# ========== Wave system ==========\nfunc _on_wave_started(wave_num: int) -> void:\n\t_update_hud()\n\t_show_wave_banner(wave_num)\n\nfunc _on_spawn_requested(enemy_type: String) -> void:\n\tvar pos := _random_edge_position()\n\t_spawn_enemy(enemy_type, pos)\n\nfunc _spawn_enemy",
    content,
    flags=re.DOTALL
)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Modification complete.")
