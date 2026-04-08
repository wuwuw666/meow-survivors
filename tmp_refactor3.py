file_path = r"f:\Project\gameB\meow-survivors\src\game\main_game.gd"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Start replacing accurately
# Wave state
old_wave_state = """# Wave state
var _wave: int = 1
var _wave_active: bool = false
var _wave_cooldown: float = 1.0
var _spawn_timer: float = 0.0
var _spawn_interval: float = 0.35
var _spawn_count: int = 0
var _total_to_spawn: int = 0
var _boss_spawned: bool = false
var _game_started: bool = false # 准备阶段标志"""
new_wave_state = """# Wave state
var wave_manager: WaveManager = null
var _game_started: bool = false # 准备阶段标志"""
content = content.replace(old_wave_state, new_wave_state)

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

btn = """	btn.pressed.connect(func():
		_game_started = true
		_start_wave(1)
		btn.queue_free()
	)"""
new_btn = """	btn.pressed.connect(func():
		_game_started = true
		wave_manager.enable_waves()
		btn.queue_free()
	)"""
content = content.replace(btn, new_btn)

process_remove = """	if not Game.is_paused and not _wave_active and _game_started:
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
content = content.replace(process_remove, "")

del_start_wave = """func _start_wave(wave_num: int) -> void:
	_wave = wave_num
	_wave_active = true

	if wave_num == 10 and not _boss_spawned:
		_spawn_boss_enemy()
		_boss_spawned = true
		_total_to_spawn = 3
		_spawn_interval = 3.5 # 大幅增加 Boss 生成间隔
	elif wave_num <= 3:
		_total_to_spawn = 15 + wave_num * 5
		_spawn_interval = 1.8 # 取非常慢的间距，确保能清楚看到一个一个出来
	elif wave_num <= 6:
		_total_to_spawn = 25 + wave_num * 4
		_spawn_interval = 1.5
	elif wave_num <= 9:
		_total_to_spawn = 35 + wave_num * 3
		_spawn_interval = 1.2
	else:
		_total_to_spawn = 50 + wave_num * 2
		_spawn_interval = max(0.6, 1.2 - wave_num * 0.02)

	_spawn_count = 0
	_update_hud()
	
	# 显示大的波次提示动画
	_show_wave_banner(wave_num)"""
content = content.replace(del_start_wave, """func _on_wave_started(wave_num: int) -> void:
	_update_hud()
	_show_wave_banner(wave_num)""")

del_spawns = """func _spawn_basic_enemy() -> void:
	var types: Array[String] = ["normal_a", "normal_b", "normal_c"]
	var weights: Array[float] = [0.55, 0.32, 0.13]
	if _wave >= 4:
		weights = [0.38, 0.38, 0.24]
	elif _wave >= 7:
		weights = [0.28, 0.42, 0.30]

	var r: float = randf()
	var cumulative: float = 0.0
	var chosen: String = "normal_a"
	for i in range(types.size()):
		cumulative += weights[i]
		if r < cumulative:
			chosen = types[i]
			break

	var pos := _random_edge_position()
	_spawn_enemy(chosen, pos)

func _spawn_boss_enemy() -> void:
	var pos := _random_edge_position()
	_spawn_enemy("boss", pos)"""
content = content.replace(del_spawns, """func _on_spawn_requested(enemy_type: String) -> void:
	var pos := _random_edge_position()
	_spawn_enemy(enemy_type, pos)""")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("done")
