## 波次控制器 (Wave Manager)
## GDD: design/gdd/wave-system.md
## 负责波次的推进逻辑和生成敌人的频率、类型决策，不负责实体生成与位置（这由调用者执行）
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
	pass

func enable_waves() -> void:
	_enabled = true
	_wave_cooldown = 1.0

## 允许外部传入 main_game 方便获取存活怪物数量
func bind_main_game(main_game: Node) -> void:
	_main_game = main_game

func _process(delta: float) -> void:
	if not _enabled or Game.is_paused or Game.is_game_over:
		return

	if not is_wave_active:
		_wave_cooldown -= delta
		if _wave_cooldown <= 0:
			_start_wave(current_wave)
			
	if is_wave_active:
		_spawn_timer -= delta
		if _spawn_timer <= 0 and _spawn_count < _total_to_spawn:
			_spawn_timer = _spawn_interval
			_request_spawn()
			_spawn_count += 1
			
		# 检查当前波次是否清理完毕
		if _spawn_count >= _total_to_spawn:
			var alive = 0
			if _main_game and _main_game.has_method("_get_alive_enemy_count"):
				alive = _main_game._get_alive_enemy_count()
			
			if alive == 0:
				is_wave_active = false
				if current_wave % 10 != 0:
					_wave_cooldown = 2.5
				current_wave += 1

func _start_wave(wave_num: int) -> void:
	current_wave = wave_num
	is_wave_active = true

	if wave_num == 10 and not _boss_spawned:
		_boss_spawned = true
		_total_to_spawn = 3
		_spawn_interval = 3.5
	elif wave_num <= 3:
		_total_to_spawn = 15 + wave_num * 5
		_spawn_interval = 1.8 
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
	_spawn_timer = 0.5 # 开场半秒后开始刷
	
	wave_started.emit(wave_num)

func _request_spawn() -> void:
	if current_wave == 10 and _boss_spawned and _spawn_count == 0:
		spawn_requested.emit("boss")
		return
		
	var types: Array[String] = ["normal_a", "normal_b", "normal_c"]
	var weights: Array[float] = [0.55, 0.32, 0.13]
	if current_wave >= 4:
		weights = [0.38, 0.38, 0.24]
	elif current_wave >= 7:
		weights = [0.28, 0.42, 0.30]

	var r: float = randf()
	var cumulative: float = 0.0
	var chosen: String = "normal_a"
	for i in range(types.size()):
		cumulative += weights[i]
		if r < cumulative:
			chosen = types[i]
			break

	spawn_requested.emit(chosen)
