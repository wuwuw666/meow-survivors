import re

file_path = r"f:\Project\gameB\meow-survivors\src\game\main_game.gd"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Variables
content = re.sub(
    r"# Wave state\nvar _wave: int = 1.*?var _boss_spawned: bool = false\n",
    "# Wave state\nvar wave_manager: WaveManager = null\n",
    content,
    flags=re.DOTALL
)

# 2. _setup_components
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
	hurtbox.collision_layer = 1
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	hurtbox.add_child(shape)
	player.add_child(hurtbox)"""
content = content.replace(old_setup, new_setup)

# 3. _show_ready_ui
content = content.replace("btn.pressed.connect(func():\n\t\t_game_started = true\n\t\t_start_wave(1)\n\t\tbtn.queue_free()\n\t)", "btn.pressed.connect(func():\n\t\t_game_started = true\n\t\twave_manager.enable_waves()\n\t\tbtn.queue_free()\n\t)")


# 4. _process logic
process_wave_logic = """	if not Game.is_paused and not _wave_active and _game_started:
		_wave_cooldown -= delta
		if _wave_cooldown <= 0:
			_start_wave(_wave)

	# wave spawn
	if _wave_active and not Game.is_paused and _game_started:
		_spawn_timer -= delta
		if _spawn_timer <= 0 and _spawn_count < _total_to_spawn:
			_spawn_timer = _spawn_interval
			_spawn_basic_enemy()
			_spawn_count += 1

		# check wave clear
		if _spawn_count >= _total_to_spawn and _get_alive_enemy_count() == 0:
			_wave_active = false
			if _wave % 10 != 0:
				_wave_cooldown = 2.5"""
content = content.replace(process_wave_logic, "")


# 5. Functions
content = re.sub(r"func _start_wave\(wave_num: int\) -> void:.*?_show_wave_banner\(wave_num\)", "func _on_wave_started(wave_num: int) -> void:\n\t_update_hud()\n\t_show_wave_banner(wave_num)", content, flags=re.DOTALL)

content = re.sub(r"func _spawn_basic_enemy\(\) -> void:.*?_spawn_enemy\(chosen, pos\)", "func _on_spawn_requested(enemy_type: String) -> void:\n\tvar pos := _random_edge_position()\n\t_spawn_enemy(enemy_type, pos)", content, flags=re.DOTALL)

content = re.sub(r"func _spawn_boss_enemy\(\) -> void:.*?_spawn_enemy\(\"boss\", pos\)", "", content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Modification complete.")
