## 主游戏场景 (Main Game)
## 游戏核心循环的总控：输入、生成、波次、升级、塔位、UI、结算
## GDD: design/gdd/game-concept.md + systems-index.md

class_name MainGame
extends Node2D

# ========== 节点引用 ==========
@onready var player: CharacterBody2D = $Player
@onready var enemy_container: Node2D = $EnemyContainer
@onready var ui: Control = $UILayer/UI
@onready var damage_container: Node2D = $UILayer/DamageNumbers

@onready var movement: MovementSystem = null
@onready var target_sys: TargetSystem = null
@onready var auto_attack: AutoAttackSystem = null
@onready var hero_health: HealthComponent = null

# Wave state
var _wave: int = 1
var _wave_active: bool = false
var _wave_cooldown: float = 2.0
var _spawn_timer: float = 0.0
var _spawn_interval: float = 1.0
var _spawn_count: int = 0
var _total_to_spawn: int = 0
var _boss_spawned: bool = false

# Tower slots
const TOWER_SLOTS: Array[Vector2] = [
	Vector2(440, 300),
	Vector2(640, 220),
	Vector2(840, 300),
	Vector2(540, 480),
	Vector2(740, 480),
]
var slot_occupied: Array[bool] = [false, false, false, false, false]

# UI refs
var hp_bar: ProgressBar
var hp_label: Label
var xp_bar: ProgressBar
var xp_label: Label
var coin_label: Label
var wave_label: Label
var tower_indicators: Array[Label] = []

# Panels
var upgrade_panel: PanelContainer
var tower_select_panel: PanelContainer
var game_over_panel: PanelContainer

const ENEMY_SCENE_PATH: String = "res://scenes/characters/enemy_base.tscn"

# ========== _ready ==========
func _ready() -> void:
	Game.reset_session()
	_setup_components()
	_build_ui()
	_setup_tower_slot_visuals()
	_setup_signals()

func _setup_components() -> void:
	# Hero health
	hero_health = HealthComponent.new()
	hero_health.name = "HealthComponent"
	hero_health.is_player = true
	player.add_child(hero_health)

	# Movement system
	movement = MovementSystem.new()
	movement.name = "MovementSystem"
	player.add_child(movement)
	movement.bind_to(player)

	# Target system
	target_sys = TargetSystem.new()
	target_sys.name = "TargetSystem"
	player.add_child(target_sys)

	# Auto attack
	auto_attack = AutoAttackSystem.new()
	auto_attack.name = "AutoAttack"
	auto_attack.base_damage = Game.player_damage
	player.add_child(auto_attack)

	# Set initial values
	auto_attack.base_damage = 5
	auto_attack.attack_range = 150.0

func _setup_signals() -> void:
	if hero_health:
		hero_health.hp_changed.connect(_on_hp_changed)
		hero_health.player_died.connect(_on_player_died)
	auto_attack.projectile_hit_enemy.connect(_on_projectile_hit)

# ========== _process ==========
func _unhandled_input(event: InputEvent) -> void:
	if Game.is_game_over:
		if event is InputEventKey and event.keycode == KEY_R and event.pressed:
			get_tree().reload_current_scene()
		return

	if Game.is_paused:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_place_tower(event.position)

func _process(delta: float) -> void:
	if Game.is_game_over:
		return

	if not Game.is_paused:
		# input -> movement
		var dir := Vector2.ZERO
		if Input.is_action_pressed("move_up"): dir.y -= 1
		if Input.is_action_pressed("move_down"): dir.y += 1
		if Input.is_action_pressed("move_left"): dir.x -= 1
		if Input.is_action_pressed("move_right"): dir.x += 1
		movement.apply_movement(dir, delta)
		_update_hud()

	if not Game.is_paused and not _wave_active:
		# wave cooldown before next wave
		_wave_cooldown -= delta
		if _wave_cooldown <= 0:
			_start_wave(_wave)

	# wave spawn
	if _wave_active and not Game.is_paused:
		_spawn_timer -= delta
		if _spawn_timer <= 0 and _spawn_count < _total_to_spawn:
			_spawn_timer = _spawn_interval
			_spawn_basic_enemy()
			_spawn_count += 1

		# check wave clear
		if _spawn_count >= _total_to_spawn and _get_alive_enemy_count() == 0:
			_wave_active = false
			if _wave % 10 != 0:
				_wave_cooldown = 3.0

	# tower attacks
	_process_tower_attacks(delta)

func _get_alive_enemy_count() -> int:
	var count := 0
	for e in enemy_container.get_children():
		if e.has_method("is_alive") and e.is_alive():
			count += 1
	return count

# ========== Wave system ==========
func _start_wave(wave_num: int) -> void:
	_wave = wave_num
	_wave_active = true

	if wave_num == 10 and not _boss_spawned:
		_spawn_boss_enemy()
		_boss_spawned = true
		_total_to_spawn = 5
		_spawn_interval = 2.0
	elif wave_num <= 5:
		_total_to_spawn = 6 + wave_num * 2
		_spawn_interval = 1.0
	elif wave_num <= 9:
		_total_to_spawn = 8 + wave_num * 2
		_spawn_interval = 0.8
	else:
		_total_to_spawn = 15 + wave_num
		_spawn_interval = max(0.3, 1.0 - wave_num * 0.03)

	_spawn_count = 0
	wave_label.text = "第 %d 波" % _wave

func _spawn_basic_enemy() -> void:
	var types: Array[String] = ["normal_a", "normal_b", "normal_c"]
	var weights: Array[float] = [0.6, 0.3, 0.1]
	if _wave >= 4:
		weights = [0.4, 0.35, 0.25]
	elif _wave >= 6:
		weights = [0.3, 0.4, 0.3]

	var r := randf()
	var cumulative := 0.0
	var chosen := "normal_a"
	for i in range(types.size()):
		cumulative += weights[i]
		if r < cumulative:
			chosen = types[i]
			break

	var pos := _random_edge_position()
	_spawn_enemy(chosen, pos)

func _spawn_boss_enemy() -> void:
	var pos := _random_edge_position()
	_spawn_enemy("boss", pos)

func _spawn_enemy(enemy_type: String, pos: Vector2) -> void:
	var enemy = load(ENEMY_SCENE_PATH).instantiate() as EnemyBase
	enemy.enemy_type = enemy_type
	enemy.position = pos
	enemy_container.add_child(enemy)

# ========== UI ==========
func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(10, 10)
	vbox.size = Vector2(300, 80)
	ui.add_child(vbox)

	# HP
	var hp_row := HBoxContainer.new()
	var hp_icon := Label.new()
	hp_icon.text = "❤️"
	hp_icon.add_theme_font_size_override("font_size", 14)
	hp_row.add_child(hp_icon)

	hp_bar = ProgressBar.new()
	hp_bar.value = 100
	hp_bar.max_value = 100
	hp_bar.custom_minimum_size = Vector2(150, 14)
	hp_bar.show_percentage = false
	hp_bar.add_theme_color_override("fill_color", Color(1, 0.42, 0.62))
	hp_bar.add_theme_color_override("background_color", Color(0.2, 0, 0))
	hp_row.add_child(hp_bar)

	hp_label = Label.new()
	hp_label.text = "100/100"
	hp_label.add_theme_font_size_override("font_size", 12)
	hp_row.add_child(hp_label)
	vbox.add_child(hp_row)

	# XP
	var xp_row := HBoxContainer.new()
	var xp_icon := Label.new()
	xp_icon.text = "⭐ Lv.1"
	xp_icon.name = "xp_level_label"
	xp_icon.add_theme_font_size_override("font_size", 12)
	xp_row.add_child(xp_icon)

	xp_bar = ProgressBar.new()
	xp_bar.value = 0
	xp_bar.max_value = 10
	xp_bar.custom_minimum_size = Vector2(120, 10)
	xp_bar.show_percentage = false
	xp_bar.add_theme_color_override("fill_color", Color(0.4, 0.5, 0.92))
	xp_bar.add_theme_color_override("background_color", Color(0.05, 0.05, 0.12))
	xp_row.add_child(xp_bar)

	xp_label = Label.new()
	xp_label.text = "0/10"
	xp_label.add_theme_font_size_override("font_size", 10)
	xp_row.add_child(xp_label)
	vbox.add_child(xp_row)

	# coins
	coin_label = Label.new()
	coin_label.text = "💰 0"
	coin_label.position = Vector2(10, 80)
	coin_label.add_theme_font_size_override("font_size", 16)
	ui.add_child(coin_label)

	# wave
	wave_label = Label.new()
	wave_label.text = "第 1 波"
	wave_label.position = Vector2(580, 10)
	wave_label.add_theme_font_size_override("font_size", 20)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.size = Vector2(120, 30)
	ui.add_child(wave_label)

	# slot indicators
	tower_indicators.clear()
	for i in range(TOWER_SLOTS.size()):
		var lbl := Label.new()
		lbl.text = "空槽%d" % i
		lbl.position = TOWER_SLOTS[i] + Vector2(-20, 20)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui.add_child(lbl)
		tower_indicators.append(lbl)

# ========== HUD update ==========
func _update_hud() -> void:
	if hp_bar == null:
		return
	hp_bar.value = Game.player_hp
	hp_bar.max_value = Game.player_max_hp
	hp_label.text = "%d/%d" % [Game.player_hp, Game.player_max_hp]

	xp_bar.value = Game.player_xp
	xp_bar.max_value = Game.player_xp_needed
	xp_label.text = "%d/%d" % [Game.player_xp, Game.player_xp_needed]
	var xp_level_lbl: Label = ui.get_node_or_null("XP/XP Row/xp_level_label")
	if xp_level_lbl == null:
		for c in ui.get_children():
			if c.has_method("get_node"):
				var candidate = c.get_node_or_null("xp_level_label")
				if candidate:
					xp_level_lbl = candidate
					break
	if xp_level_lbl:
		xp_level_lbl.text = "⭐ Lv.%d" % Game.player_level

	coin_label.text = "💰 %d" % Game.player_coins

	# tower indicators
	for i in range(TOWER_SLOTS.size()):
		if tower_indicators[i]:
			if slot_occupied[i]:
				tower_indicators[i].text = "🗼S%d" % i
				tower_indicators[i].add_theme_color_override("font_color", Color(1, 0.85, 0))
			else:
				tower_indicators[i].text = "空槽%d" % i
				tower_indicators[i].add_theme_color_override("font_color", Color.WHITE)

# ========== Enemy death handling ==========
func _on_enemy_died_wrapper(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var enemy_data := enemy.get("_data", {})
	var coin_val := enemy_data.get("coin", 2)
	var xp_val := enemy_data.get("xp", 3)
	var is_boss := enemy.get("enemy_type", "") == "boss"

	Game.add_coins(coin_val)
	Game.add_xp(xp_val)
	_show_xp_gain(coin_val, xp_val, enemy.global_position)

	if Game.player_xp > 0 and Game.player_xp < Game.player_xp_needed:
		pass
	# check level up
	var new_needed := _calc_xp_needed(Game.player_level)
	if Game.player_xp_needed != new_needed:
		Game.player_xp_needed = new_needed
		_show_upgrade_panel()

func _calc_xp_needed(level: int) -> int:
	return ceil(10.0 * (1.0 + (level - 1) * 0.3))

# ========== Damage numbers ==========
func _on_projectile_hit(enemy: Node, dmg: int, is_crit: bool) -> void:
	_show_damage_number(enemy.global_position, dmg, is_crit)

func _show_damage_number(world_pos: Vector2, value: int, is_crit: bool) -> void:
	var lbl := Label.new()
	lbl.text = str(value)
	if is_crit:
		lbl.add_theme_color_override("font_color", Color(1, 1, 0))
		lbl.add_theme_font_size_override("font_size", 20)
	else:
		lbl.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		lbl.add_theme_font_size_override("font_size", 14)
	lbl.position = world_pos + Vector2(randf_range(-15, 15), -25)
	damage_container.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 40, 0.6)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.3)
	tween.tween_callback(lbl.queue_free)

func _show_xp_gain(coins: int, xp: int, pos: Vector2) -> void:
	# XP float text
	var lbl := Label.new()
	lbl.text = "+%d XP" % xp
	lbl.add_theme_color_override("font_color", Color(0.7, 0.5, 1.0))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = pos + Vector2(10, -20)
	damage_container.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 30, 0.8)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.2)
	tween.tween_callback(lbl.queue_free)

# ========== Signals ==========
func _on_hp_changed(current: int, max_val: int) -> void:
	Game.player_hp = current
	Game.player_max_hp = max_val
	_update_hud()

func _on_player_died() -> void:
	Game.is_game_over = true
	# small delay for death visual
	await get_tree().create_timer(1.0).timeout
	_show_game_over_panel()

# ========== Upgrade panel ==========
const UPGRADES: Array[Dictionary] = [
	{"name": "⚔️ 伤害 +5", "apply": "damage"},
	{"name": "⚡ 攻速 +20%", "apply": "aspd"},
	{"name": "🎯 射程 +30", "apply": "range"},
	{"name": "❤️ 生命 +40", "apply": "hp"},
	{"name": "💨 移速 +15%", "apply": "speed"},
]

func _show_upgrade_panel() -> void:
	Game.is_paused = true

	if upgrade_panel == null:
		upgrade_panel = PanelContainer.new()
		upgrade_panel.position = Vector2(340, 180)
		upgrade_panel.custom_minimum_size = Vector2(600, 300)
		upgrade_panel.visible = false
		ui.add_child(upgrade_panel)

	upgrade_panel.visible = true
	# clear old children
	for c in upgrade_panel.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	upgrade_panel.add_child(vbox)

	var title := Label.new()
	title.text = "🎉 LEVEL UP! 选择一个升级"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	# pick 3 random
	var opts := UPGRADES.duplicate()
	opts.shuffle()
	opts.resize(3)

	for opt in opts:
		var btn := Button.new()
		btn.text = opt.name
		btn.custom_minimum_size = Vector2(180, 80)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_select_upgrade.bind(opt.apply))
		hbox.add_child(btn)

func _select_upgrade(type_name: String) -> void:
	match type_name:
		"damage":
			Game.player_damage += 5
			if auto_attack:
				auto_attack.base_damage = Game.player_damage
		"aspd":
			if auto_attack:
				auto_attack.set_attack_speed_bonus(0.20)
		"range":
			Game.player_range += 30
			if auto_attack:
				auto_attack.set_range_bonus(Game.player_range - 150.0)
		"hp":
			Game.set_player_max_hp(Game.player_max_hp + 40)
			Game.heal_player(40)
			if hero_health:
				hero_health.max_hp = Game.player_max_hp
				hero_health.heal(40)
		"speed":
			Game.player_speed_mult *= 1.15
			if movement:
				movement.base_speed = 200.0 * Game.player_speed_mult
	upgrade_panel.visible = false
	Game.is_paused = false
	_update_hud()

# ========== Tower placement ==========
func _try_place_tower(mouse_pos: Vector2) -> void:
	if Game.is_paused or Game.is_game_over:
		return

	for i in range(TOWER_SLOTS.size()):
		if slot_occupied[i]:
			continue
		if mouse_pos.distance_to(TOWER_SLOTS[i]) < 25:
			_show_tower_select_panel(i)
			return

func _show_tower_select_panel(slot_index: int) -> void:
	if tower_select_panel == null:
		tower_select_panel = PanelContainer.new()
		tower_select_panel.position = Vector2(340, 250)
		tower_select_panel.custom_minimum_size = Vector2(600, 200)
		tower_select_panel.visible = false
		ui.add_child(tower_select_panel)

	tower_select_panel.visible = true
	for c in tower_select_panel.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	tower_select_panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择防御塔"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var towers: Array[Dictionary] = [
		{"key": "fish", "name": "🐟 小鱼干", "cost": 10, "dmg": 12, "range": 180, "iv": 1.0, "type": "attack"},
		{"key": "yarn", "name": "🧶 毛线球", "cost": 15, "dmg": 6, "range": 150, "iv": 1.5, "type": "control"},
		{"key": "aura", "name": "🌿 猫薄荷", "cost": 20, "range": 120, "type": "aura", "buff": 0.15},
	]

	for tw in towers:
		var btn := Button.new()
		var desc := ""
		if tw.type == "attack":
			desc = "伤害:%d 射程:%.0f 冷却:%.1fs" % [tw.dmg, tw.range, tw.iv]
		elif tw.type == "control":
			desc = "伤害:%d 减速 射程:%.0f" % [tw.dmg, tw.range]
		else:
			desc = "范围内友方伤害 +15%"
		btn.text = "%s\n%s\n💰%d" % [tw.name, desc, tw.cost]
		btn.custom_minimum_size = Vector2(180, 80)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_place_tower.bind(slot_index, tw))
		hbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func(): tower_select_panel.visible = false)
	vbox.add_child(cancel)

func _place_tower(slot_index: int, tw_data: Dictionary) -> void:
	if not Game.spend_coins(tw_data.cost):
		return

	slot_occupied[slot_index] = true
	var tw := {
		"slot": slot_index,
		"position": TOWER_SLOTS[slot_index],
		"type": tw_data.type,
		"damage": tw_data.get("dmg", 0),
		"range": tw_data.get("range", 120.0),
		"attack_cooldown": tw_data.get("iv", 1.0),
		"attack_timer": 0.0,
		"buff": tw_data.get("buff", 0.0),
		"level": 1,
	}
	Game.placed_towers.append(tw)

	# place visual
	var tw_marker := ColorRect.new()
	tw_marker.size = Vector2(20, 20)
	var colors := {"attack": Color(1, 0.7, 0.3), "control": Color(0.6, 0.4, 1.0), "aura": Color(0.3, 1.0, 0.3)}
	tw_marker.color = colors.get(tw_data.type, Color.WHITE)
	tw_marker.position = TOWER_SLOTS[slot_index] - Vector2(10, 10)
	add_child(tw_marker)

	tower_select_panel.visible = false
	_update_hud()

func _process_tower_attacks(delta: float) -> void:
	if Game.is_paused or Game.is_game_over:
		return

	for tw in Game.placed_towers:
		if tw.type == "aura":
			continue
		tw.attack_timer += delta
		if tw.attack_timer >= tw.attack_cooldown:
			tw.attack_timer = 0.0
			# find nearest enemy in range
			var best: Node2D = null
			var best_d: float = tw.range * tw.range
			for e in enemy_container.get_children():
				if e.has_method("is_alive") and not e.is_alive():
					continue
				var d: float = tw.position.distance_squared_to(e.global_position)
				if d < best_d:
					best_d = d
					best = e as Node2D
			if best:
				var dmg: int = tw.damage
				# find enemy health component
				var hc := best.get_node_or_null("HealthComponent") as HealthComponent
				if hc:
					hc.take_damage(dmg)
				# show damage number
				_show_damage_number(best.global_position, dmg, false)
				if tw.type == "control":
					best.call("apply_slow", 0.7, 2.0)

# ========== Game over ==========
func _show_game_over_panel() -> void:
	get_tree().paused = true

	if game_over_panel == null:
		game_over_panel = PanelContainer.new()
		game_over_panel.position = Vector2(390, 200)
		game_over_panel.custom_minimum_size = Vector2(500, 300)
		ui.add_child(game_over_panel)

	game_over_panel.visible = true
	for c in game_over_panel.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	game_over_panel.add_child(vbox)

	var title := Label.new()
	title.text = "💔 猫咪倒下了..."
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var stats := Label.new()
	stats.text = "第 %d 波 | Lv.%d | 💰%d\n按 R 重新开始" % [_wave, Game.player_level, Game.player_coins]
	stats.add_theme_font_size_override("font_size", 16)
	stats.position = Vector2(0, 50)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

	_spawn_timer = 0

# ========== Helper: random spawn at screen edge ==========
func _random_edge_position() -> Vector2:
	var edge := randi() % 4
	match edge:
		0: return Vector2(randf_range(0, 1280), -20)
		1: return Vector2(randf_range(0, 1280), 740)
		2: return Vector2(-20, randf_range(0, 720))
		3: return Vector2(1300, randf_range(0, 720))
	return Vector2(0, 0)

func _setup_tower_slot_visuals() -> void:
	for pos in TOWER_SLOTS:
		var dot := ColorRect.new()
		dot.size = Vector2(12, 12)
		dot.color = Color(0.3, 0.3, 0.4, 0.6)
		dot.position = pos - Vector2(6, 6)
		add_child(dot)
