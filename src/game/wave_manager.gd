## 波次控制器 (Wave Manager)
## GDD: design/gdd/wave-system.md
## 负责波次推进、刷怪节奏与敌人类型决策，不直接负责实体实例化
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
var _elite_spawn_target: int = 0
var _elite_spawn_count: int = 0
var _enabled: bool = false
var _main_game: Node = null
var _wave_pulses: Array[Dictionary] = []
var _current_pulse_index: int = 0
var _pulse_spawned: int = 0
var _pulse_gap_timer: float = 0.0
var _pressure_valley_timer: float = 0.0
var _spawning_complete: bool = false

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

	if not is_wave_active:
		return

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

	var alive: int = 0
	if _main_game and _main_game.has_method("_get_alive_enemy_count"):
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
	wave_started.emit(wave_num)

func start_pressure_valley(duration_sec: float = 4.0) -> void:
	_pressure_valley_timer = maxf(_pressure_valley_timer, duration_sec)

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

func _get_current_pulse() -> Dictionary:
	if _current_pulse_index < 0 or _current_pulse_index >= _wave_pulses.size():
		return {}
	return _wave_pulses[_current_pulse_index]

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

	var types: Array[String] = ["normal_a", "normal_b", "normal_c"]
	var weights_variant: Variant = pulse.get("weights", [0.18, 0.72, 0.10])
	var weights: Array[float] = []
	for value in weights_variant:
		weights.append(float(value))
	if weights.size() != 3:
		weights = [0.18, 0.72, 0.10]

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
