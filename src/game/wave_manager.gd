class_name WaveManager
extends Node

signal wave_started(wave_num: int)
signal spawn_requested(enemy_type: String)

var current_wave: int = 1
var is_wave_active: bool = false

var _wave_cooldown: float = 1.0
var _spawn_timer: float = 0.0
var _spawn_interval: float = 0.35
var _spawn_count: int = 0
var _total_to_spawn: int = 0
var _boss_spawned: bool = false
var _enabled: bool = false
var _main_game: Node = null

func _ready() -> void:
	add_to_group("wave_system")

func enable_waves() -> void:
	_enabled = true
	_wave_cooldown = 0.0
	if not is_wave_active:
		_start_wave(maxi(current_wave, 1))

func get_wave_speed_multiplier() -> float:
	return minf(1.0 + maxf(float(current_wave - 1), 0.0) * 0.01, 1.12)

func bind_main_game(main_game: Node) -> void:
	_main_game = main_game

func _process(delta: float) -> void:
	if not _enabled or Game.is_paused or Game.is_game_over:
		return

	if not is_wave_active:
		_wave_cooldown -= delta
		if _wave_cooldown <= 0.0:
			_start_wave(current_wave)
			return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _spawn_count < _total_to_spawn:
		_spawn_timer = _spawn_interval
		_request_spawn()
		_spawn_count += 1

	if _spawn_count < _total_to_spawn:
		return

	var alive: int = 0
	if _main_game != null and _main_game.has_method("_get_alive_enemy_count"):
		alive = int(_main_game._get_alive_enemy_count())

	if alive == 0:
		is_wave_active = false
		if current_wave % 10 != 0:
			_wave_cooldown = 2.5
		current_wave += 1

func _start_wave(wave_num: int) -> void:
	current_wave = wave_num
	Game.current_wave = wave_num
	is_wave_active = true

	if wave_num == 10 and not _boss_spawned:
		_boss_spawned = true
		_total_to_spawn = 3
		_spawn_interval = 3.5
	elif wave_num <= 2:
		_total_to_spawn = 12 + wave_num * 4
		_spawn_interval = 1.80
	elif wave_num <= 5:
		_total_to_spawn = 18 + wave_num * 4
		_spawn_interval = 1.48
	elif wave_num <= 6:
		_total_to_spawn = 28 + wave_num * 4
		_spawn_interval = 1.22
	elif wave_num <= 9:
		_total_to_spawn = 35 + wave_num * 3
		_spawn_interval = 1.02
	else:
		_total_to_spawn = 50 + wave_num * 2
		_spawn_interval = maxf(0.55, 0.95 - wave_num * 0.02)

	_spawn_count = 0
	_spawn_timer = 0.5
	wave_started.emit(wave_num)

func _request_spawn() -> void:
	if current_wave == 10 and _boss_spawned and _spawn_count == 0:
		spawn_requested.emit("boss")
		return

	var types: Array[String] = ["normal_a", "normal_b", "normal_c"]
	var weights: Array[float] = [0.18, 0.72, 0.10]
	if current_wave >= 7:
		weights = [0.24, 0.38, 0.38]
	elif current_wave >= 3:
		weights = [0.24, 0.60, 0.16]
	elif current_wave >= 2:
		weights = [0.20, 0.70, 0.10]

	if current_wave >= 6:
		types.append("elite")
		weights.append(0.08 if current_wave <= 6 else 0.14)

	var total_weight: float = 0.0
	for weight in weights:
		total_weight += weight

	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	var chosen: String = "normal_a"
	for index in range(types.size()):
		cumulative += weights[index]
		if roll < cumulative:
			chosen = types[index]
			break

	spawn_requested.emit(chosen)
