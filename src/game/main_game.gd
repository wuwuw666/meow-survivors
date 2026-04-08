## 主游戏场景 (Main Game)
## 游戏核心循环的总控：输入、生成、波次、升级、塔位、UI、结算
## GDD: design/gdd/game-concept.md + systems-index.md

class_name MainGame
extends Node2D

# ========== 节点引用 ==========
@onready var player: CharacterBody2D = $Player
@onready var enemy_container: Node2D = $EnemyContainer
@onready var ui: Control = get_node_or_null("UILayer/UI")
@onready var damage_container: Node2D = $UILayer/DamageNumbers
@onready var pickup_container: Node2D = $PickupContainer
@onready var effect_container: Node2D = $EffectContainer

@onready var movement: MovementSystem = null
@onready var target_sys: TargetSystem = null
@onready var auto_attack: AutoAttackSystem = null
@onready var hero_health: HealthComponent = null

# 弹丸场景（预加载）
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/gameplay/projectile.tscn")

# 进攻路径定义 (Waypoints - 由场景中的 Path2D 节点动态加载)
var PATHS: Array[PackedVector2Array] = []

# Wave state
var wave_manager: WaveManager = null
var _game_started: bool = false # 准备阶段标志

# Tower Dragging
var _is_dragging_tower: bool = false
var _drag_tower_data: Dictionary = {}
var _ghost_tower: ColorRect = null

# Towers database
var towers_db: Array[Dictionary] = [
	{"key": "bow", "name": "🏹长弓", "cost": 30, "dmg": 25, "range": 350, "iv": 1.2, "type": "attack"},
	{"key": "fish", "name": "🐟小鱼干", "cost": 10, "dmg": 12, "range": 180, "iv": 1.0, "type": "attack"},
	{"key": "yarn", "name": "🧶毛线球", "cost": 15, "dmg": 6, "range": 150, "iv": 1.5, "type": "control"},
	{"key": "aura", "name": "🌿猫薄荷", "cost": 20, "range": 120, "type": "aura", "buff": 0.15},
]

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
var game_over_panel: PanelContainer

# 屏幕震动
var _shake_intensity: float = 0.0
var _shake_decay: float = 8.0

# 玩家受击闪白
var _hit_flash_timer: float = 0.0

const ENEMY_SCENE_PATH: String = "res://scenes/characters/enemy_base.tscn"

# ========== _ready ==========
func _ready() -> void:
	# 注册组，供弹丸系统查找父节点
	add_to_group("main_game")
	if ui == null:
		var uilayer = get_node_or_null("UILayer")
		if uilayer:
			ui = Control.new()
			ui.name = "UI"
			ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			uilayer.add_child(ui)

	Game.reset_session()
	_load_paths_from_nodes()
	_setup_components()
	# 设置背景点击穿透，否则 _unhandled_input 会被拦截
	$Background.mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_setup_signals()

	# 初始处于准备阶段，不自动启动波次
	_show_ready_ui()
	print_rich("[color=cyan][MainGame][/color] 核心系统已就绪，进入 [准备阶段]...")

func _show_ready_ui() -> void:
	var btn := Button.new()
	btn.name = "StartButton"
	btn.text = " — 点击这只猫 开始战斗 — "
	btn.custom_minimum_size = Vector2(350, 80)
	
	# 使用锚点：居中底部
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	btn.offset_bottom = -80
	
	btn.add_theme_font_size_override("font_size", 24)
	ui.add_child(btn)
	
	btn.pressed.connect(func():
		_game_started = true
		wave_manager.enable_waves()
		btn.queue_free()
	)
	
	# 呼吸灯动画效果
	var tw := create_tween().set_loops()
	tw.tween_property(btn, "modulate:a", 0.6, 0.8)
	tw.tween_property(btn, "modulate:a", 1.0, 0.8)

func _load_paths_from_nodes() -> void:
	PATHS.clear()
	var paths_node: Node2D = get_node_or_null("Paths") as Node2D
	if not paths_node:
		push_warning("MainGame: No 'Paths' node found. Using default empty paths.")
		return
	
	for child in paths_node.get_children():
		if child is Path2D:
			var curve: Curve2D = child.curve
			if curve and curve.point_count > 0:
				var points: PackedVector2Array = curve.get_baked_points()
				PATHS.append(points)
				print_rich("[color=green][Paths][/color] 已从节点 %s 加载路径，点数: %d" % [child.name, points.size()])
	
	if PATHS.is_empty():
		push_error("MainGame: Paths container is empty!")

func _setup_components() -> void:
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
	player.add_child(hurtbox)

	# Movement system
	movement = MovementSystem.new()
	movement.name = "MovementSystem"
	player.add_child(movement)
	movement.bind_to(player)

	# Target system
	target_sys = TargetSystem.new()
	target_sys.name = "TargetSystem"
	player.add_child(target_sys)

	# Auto attack — 绑定弹丸场景
	auto_attack = AutoAttackSystem.new()
	auto_attack.name = "AutoAttack"
	auto_attack.base_damage = 5
	auto_attack.attack_range = 150.0
	auto_attack.projectile_scene = PROJECTILE_SCENE
	player.add_child(auto_attack)

func _setup_signals() -> void:
	if hero_health:
		hero_health.hp_changed.connect(_on_hp_changed)
		hero_health.player_died.connect(_on_player_died)

# ========== _process ==========
func _unhandled_input(event: InputEvent) -> void:
	if Game.is_game_over:
		if event is InputEventKey and event.keycode == KEY_R and event.pressed:
			get_tree().reload_current_scene()
		return

	if Game.is_paused:
		return

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_dragging_tower:
			var pos = get_global_mouse_position()
			if _can_place_tower_at(pos):
				_place_tower(pos, _drag_tower_data)
			else:
				_show_floating_text(pos, "位置被占用", Color(1, 0, 0))
				add_screen_shake(2.0)
			
			if _ghost_tower:
				_ghost_tower.queue_free()
				_ghost_tower = null
			_is_dragging_tower = false

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

		# 处理拾取物（经验球和金币的磁铁吸引）
		_process_pickups(delta)

		# 处理粒子效果生命周期
		_process_effects(delta)

	# 波次由 WaveManager 独立接管

	if _is_dragging_tower and _ghost_tower != null:
		_ghost_tower.global_position = get_global_mouse_position() - Vector2(22, 22)
		
	# 屏幕震动更新
	_update_screen_shake(delta)

	# 受击闪白更新
	_update_hit_flash(delta)

func _get_alive_enemy_count() -> int:
	var count := 0
	for e in enemy_container.get_children():
		if e.has_method("is_alive") and e.is_alive():
			count += 1
	return count

# ========== Wave system ==========
func _on_wave_started(wave_num: int) -> void:
	_update_hud()
	_show_wave_banner(wave_num)

func _show_wave_banner(num: int) -> void:
	var banner := Label.new()
	banner.text = " — 第 %d 波 —\n猫兵正在逼近！" % num
	banner.add_theme_font_size_override("font_size", 42)
	banner.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ui.add_child(banner)
	
	banner.modulate.a = 0
	banner.scale = Vector2(0.5, 0.5)
	banner.pivot_offset = banner.size / 2.0
	
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(1.5)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(banner, "scale", Vector2(1.2, 1.2), 0.4)
	tw.tween_callback(banner.queue_free)

func _on_spawn_requested(enemy_type: String) -> void:
	var pos := _random_edge_position()
	_spawn_enemy(enemy_type, pos)

func _spawn_enemy(enemy_type: String, _pos: Vector2) -> void:
	if not FileAccess.file_exists(ENEMY_SCENE_PATH):
		return
	
	var enemy: EnemyBase = load(ENEMY_SCENE_PATH).instantiate() as EnemyBase
	enemy.enemy_type = enemy_type
	
	# 分配随机路径
	var path_index: int = randi() % PATHS.size()
	var selected_path: PackedVector2Array = PATHS[path_index]
	
	# 设置路径
	enemy.set("target_path", selected_path)
	# 增加随机始发偏移，防止在一个点上挤爆
	var jitter := Vector2(randf_range(-20, 20), randf_range(-20, 20))
	enemy.global_position = selected_path[0] + jitter
	
	print_rich("[color=yellow][Spawn][/color] 敌人: %s, 路径: %d, 始发点: %s" % [enemy_type, path_index + 1, selected_path[0]])
	
	# 必须先执行 add_child 以触发敌人的 _ready() 和组件初始化重组
	enemy_container.add_child(enemy)
	
	# 然后才能获取到真实的经过处理的 HealthComponent
	var hc: HealthComponent = enemy.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.entity_died.connect(_on_enemy_died_wrapper)
	
	# 连接抵达基地信号
	enemy.enemy_reached_base.connect(_on_enemy_reached_base)

func _on_enemy_reached_base(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	
	# 扣除基地生命值
	var enemy_base: EnemyBase = enemy as EnemyBase
	var dmg: int = enemy_base._data.get("damage", 1)
	Game.player_hp = clampi(Game.player_hp - dmg, 0, Game.player_max_hp)
	_update_hud()
	
	# 受击提示
	add_screen_shake(8.0)
	_show_floating_text(enemy_base.global_position, "-%d 🏠" % dmg, Color(1, 0, 0))
	
	# 如果生命归零则失败
	if Game.player_hp <= 0:
		_on_player_died()
	
	# 销毁敌人
	if not (enemy as EnemyBase).is_dead:
		enemy.queue_free()

# ========== 拾取物系统 ==========
func _process_pickups(delta: float) -> void:
	if pickup_container == null or player == null:
		return
	var player_pos: Vector2 = player.global_position
	var magnet_range: float = 120.0
	var collect_range: float = 18.0
	var to_remove: Array[Node] = []

	for pickup in pickup_container.get_children():
		if not is_instance_valid(pickup):
			continue
		var vel: Vector2 = pickup.get_meta("velocity", Vector2.ZERO)
		var ptype: String = pickup.get_meta("type", "")
		var dist_sq: float = pickup.global_position.distance_squared_to(player_pos)

		# 磁铁效果：进入范围后被吸引
		if dist_sq < magnet_range * magnet_range:
			var dist: float = sqrt(dist_sq)
			var dir: Vector2 = (player_pos - pickup.global_position).normalized()
			var pull_speed: float = 450.0 * (1.0 - dist / magnet_range)
			vel = vel.lerp(dir * pull_speed, 12.0 * delta)
		else:
			vel *= 0.95
			vel.y += 200.0 * delta

		pickup.set_meta("velocity", vel)
		pickup.global_position += vel * delta

		# 拾取检测
		if dist_sq < collect_range * collect_range:
			match ptype:
				"xp":
					var val: int = pickup.get_meta("xp_value", 3)
					Game.add_xp(val)
					_show_floating_text(pickup.global_position, "+%d XP" % val, Color(0.7, 0.5, 1.0))
					var new_needed := _calc_xp_needed(Game.player_level)
					if Game.player_xp_needed != new_needed:
						Game.player_xp_needed = new_needed
						_show_upgrade_panel()
				"coin":
					var val: int = pickup.get_meta("coin_value", 2)
					Game.add_coins(val)
					_show_floating_text(pickup.global_position, "+%d 💰" % val, Color(1, 0.85, 0.2))
			to_remove.append(pickup)

	for p in to_remove:
		if is_instance_valid(p):
			p.queue_free()

func spawn_xp_orb(pos: Vector2, value: int) -> void:
	if pickup_container == null:
		Game.add_xp(value)
		return
	var orb = Area2D.new()
	orb.name = "XPOrb"
	orb.position = pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))

	# 视觉：紫色小圆球
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	sprite.offset_left = -5.0
	sprite.offset_top = -5.0
	sprite.offset_right = 5.0
	sprite.offset_bottom = 5.0
	sprite.color = Color(0.6, 0.3, 1.0, 1)
	orb.add_child(sprite)

	# 标签
	var lbl := Label.new()
	lbl.text = "+%d XP" % value if value > 1 else "+XP"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	lbl.position = Vector2(-12, -14)
	orb.add_child(lbl)

	# 碰撞体
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	cs.shape = circle
	orb.add_child(cs)

	# 数据
	orb.set_meta("xp_value", value)
	orb.set_meta("velocity", Vector2(randf_range(-50, 50), randf_range(-80, -30)))
	orb.set_meta("type", "xp")

	# 方法绑定
	orb.monitoring = true
	orb.monitorable = false
	orb.collision_layer = 0
	orb.collision_mask = 1  # player layer

	# 给 orb 添加 process_pickup 方法
	orb.set_script(null)  # 确保无冲突脚本
	# 用 Callable 绑定方法
	pickup_container.add_child(orb)

func spawn_coin(pos: Vector2, value: int) -> void:
	if pickup_container == null:
		Game.add_coins(value)
		return
	var coin = Area2D.new()
	coin.name = "Coin"
	coin.position = pos + Vector2(randf_range(-8, 8), randf_range(-8, 8))

	# 视觉：金色小圆
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	sprite.offset_left = -6.0
	sprite.offset_top = -6.0
	sprite.offset_right = 6.0
	sprite.offset_bottom = 6.0
	sprite.color = Color(1, 0.82, 0.1, 1)
	coin.add_child(sprite)

	# 标签
	var lbl := Label.new()
	lbl.text = "%d" % value
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	lbl.position = Vector2(-6, -12)
	coin.add_child(lbl)

	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	cs.shape = circle
	coin.add_child(cs)

	coin.set_meta("coin_value", value)
	coin.set_meta("velocity", Vector2(randf_range(-60, 60), randf_range(-100, -40)))
	coin.set_meta("type", "coin")

	coin.monitoring = true
	coin.monitorable = false
	coin.collision_layer = 0
	coin.collision_mask = 1

	pickup_container.add_child(coin)

# ========== 敌人死亡处理 ==========
func _on_enemy_died_wrapper(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var enemy_data: Dictionary = (enemy as EnemyBase)._data if enemy is EnemyBase else {}
	var coin_val := int(enemy_data.get("coin", 2))
	var xp_val := int(enemy_data.get("xp", 3))

	# 塔防模式：直接入账，不散落物理拾取物，不用跑过去吃
	Game.add_coins(10)
	Game.add_xp(xp_val)
	_update_hud()
	
	# 原地视觉提示取代掉落
	_show_floating_text(enemy.global_position, "+10 💰", Color(1, 0.85, 0.2))
	_show_floating_text(enemy.global_position + Vector2(0, -15), "+%d XP" % xp_val, Color(0.7, 0.5, 1.0))

	# 死亡爆炸粒子
	_spawn_death_particles(enemy.global_position, enemy_data.get("body_size", 14.0))

	# 小屏幕震动
	add_screen_shake(3.0)

func _calc_xp_needed(level: int) -> int:
	return ceil(10.0 * pow(level, 0.9))

# ========== UI ==========
func _build_ui() -> void:
	# 设置主 UI 容器为全屏并忽略鼠标（防止拦截塔位点击）
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 1. 左上角状态栏 (Margins + VBox)
	var margin_stats := MarginContainer.new()
	margin_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin_stats.add_theme_constant_override("margin_left", 20)
	margin_stats.add_theme_constant_override("margin_top", 20)
	margin_stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.add_child(margin_stats)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.custom_minimum_size = Vector2(320, 0)
	margin_stats.add_child(vbox)

	# HP
	var hp_row := HBoxContainer.new()
	var hp_icon := Label.new()
	hp_icon.text = "❤️"
	hp_icon.add_theme_font_size_override("font_size", 16)
	hp_row.add_child(hp_icon)

	hp_bar = ProgressBar.new()
	hp_bar.value = 100
	hp_bar.max_value = 100
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.custom_minimum_size = Vector2(0, 18)
	hp_bar.show_percentage = false
	hp_bar.add_theme_color_override("fill_color", Color(1, 0.35, 0.5))
	hp_bar.add_theme_color_override("background_color", Color(0.15, 0, 0))
	hp_row.add_child(hp_bar)

	hp_label = Label.new()
	hp_label.text = "100/100"
	hp_label.add_theme_font_size_override("font_size", 14)
	hp_label.custom_minimum_size = Vector2(70, 0)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_row.add_child(hp_label)
	vbox.add_child(hp_row)

	# XP
	var xp_row := HBoxContainer.new()
	var xp_icon := Label.new()
	xp_icon.text = "⭐ Lv.1"
	xp_icon.name = "xp_level_label"
	xp_icon.add_theme_font_size_override("font_size", 14)
	xp_row.add_child(xp_icon)

	xp_bar = ProgressBar.new()
	xp_bar.value = 0
	xp_bar.max_value = 10
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.custom_minimum_size = Vector2(0, 12)
	xp_bar.show_percentage = false
	xp_bar.add_theme_color_override("fill_color", Color(0.4, 0.5, 1.0))
	xp_bar.add_theme_color_override("background_color", Color(0.05, 0.05, 0.15))
	xp_row.add_child(xp_bar)

	xp_label = Label.new()
	xp_label.text = "0/10"
	xp_label.add_theme_font_size_override("font_size", 12)
	xp_label.custom_minimum_size = Vector2(70, 0)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_row.add_child(xp_label)
	vbox.add_child(xp_row)

	# 间隔
	vbox.add_child(Control.new())

	# 金币 (Coin)
	coin_label = Label.new()
	coin_label.text = "💰 0"
	coin_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(coin_label)

	# 2. 顶部中央波次提示
	wave_label = Label.new()
	wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_label.text = "第 1 波"
	wave_label.add_theme_font_size_override("font_size", 24)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	wave_label.offset_top = 15
	ui.add_child(wave_label)

	# 3. 塔的快捷商店 (左下角，不再使用 BOTTOM_LEFT Preset，直接利用屏幕高度固定摆放)
	var shop_margin := MarginContainer.new()
	shop_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 固定位置放置，避免 Anchor 受分辨率和其它层级挤压影响
	shop_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	shop_margin.position = Vector2(20, 600)  # 在 1280x720 环境下的左下方
	ui.add_child(shop_margin)

	var shop_hbox := HBoxContainer.new()
	shop_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_hbox.add_theme_constant_override("separation", 15)
	shop_margin.add_child(shop_hbox)

	var t_lbl := Label.new()
	t_lbl.text = "拖拽建塔 👉 "
	t_lbl.add_theme_font_size_override("font_size", 16)
	shop_hbox.add_child(t_lbl)

	for tw in towers_db:
		var btn := Button.new()
		btn.text = "%s\n💰%d" % [tw.name, tw.cost]
		btn.custom_minimum_size = Vector2(85, 75)
		btn.add_theme_font_size_override("font_size", 14)
		btn.button_down.connect(_on_tower_drag_start.bind(tw))
		shop_hbox.add_child(btn)

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

	var xp_level_lbl: Label = null
	# 搜索正确的节点
	for c in ui.get_children():
		if c.name == "xp_level_label":
			xp_level_lbl = c
			break
		var deep := c.find_child("xp_level_label", true, false)
		if deep:
			xp_level_lbl = deep as Label
			break

	if xp_level_lbl:
		xp_level_lbl.text = "⭐ Lv.%d" % Game.player_level

	coin_label.text = "💰 %d" % Game.player_coins

	# (已移除塔插槽更新)

# ========== Damage numbers & floating text ==========
func _show_damage_number(world_pos: Vector2, value: int, is_crit: bool) -> void:
	var lbl := Label.new()
	lbl.text = str(value)
	if is_crit:
		lbl.add_theme_color_override("font_color", Color(1, 1, 0))
		lbl.add_theme_font_size_override("font_size", 24)
		# 暴击额外屏幕震动
		add_screen_shake(4.0)
	else:
		lbl.add_theme_color_override("font_color", Color(1, 0.25, 0.25))
		lbl.add_theme_font_size_override("font_size", 15)
	lbl.position = world_pos + Vector2(randf_range(-12, 12), -22)
	damage_container.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 50, 0.7).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tween.tween_callback(lbl.queue_free)

func _show_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.position = world_pos + Vector2(randf_range(-8, 8), -16)
	damage_container.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 36, 0.8).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.3).set_delay(0.5)
	tween.tween_callback(lbl.queue_free)

# ========== 弹丸处理 ==========
func _on_projectile_hit(enemy: Node, dmg: int, is_crit: bool) -> void:
	if not is_instance_valid(enemy):
		return
	
	# 特效展示
	_show_damage_number(enemy.global_position, dmg, is_crit)
	
	# 真正扣血：通过寻找敌人的 HealthComponent 节点来执行
	var hc: HealthComponent = enemy.get_node_or_null("HealthComponent") as HealthComponent
	if hc:
		hc.take_damage(dmg)
	elif enemy.has_method("take_damage"):
		enemy.take_damage(dmg)

# ========== Signals ==========
func _on_hp_changed(current: int, max_val: int) -> void:
	Game.player_hp = current
	Game.player_max_hp = max_val
	_update_hud()
	# 受击闪白 + 震动
	_hit_flash_timer = 0.12
	add_screen_shake(5.0)

func _on_player_died() -> void:
	Game.is_game_over = true
	await get_tree().create_timer(0.8).timeout
	_show_game_over_panel()

# ========== 升级面板 ==========
const UPGRADES: Array[Dictionary] = [
	{"name": "⚔️ 伤害+5", "apply": "damage"},
	{"name": "⚡ 攻速+20%", "apply": "aspd"},
	{"name": "🎯 射程+30", "apply": "range"},
	{"name": "❤️ 生命+40", "apply": "hp"},
	{"name": "💨 移速+15%", "apply": "speed"},
]

func _show_upgrade_panel() -> void:
	Game.is_paused = true

	if upgrade_panel == null:
		upgrade_panel = PanelContainer.new()
		# 使用锚点居中
		upgrade_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		upgrade_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		upgrade_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		upgrade_panel.custom_minimum_size = Vector2(700, 340)
		upgrade_panel.visible = false
		ui.add_child(upgrade_panel)

	upgrade_panel.visible = true
	for c in upgrade_panel.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	upgrade_panel.add_child(vbox)

	var title := Label.new()
	title.text = "⬆️ LEVEL UP!"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "选择一个升级..."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	var opts := UPGRADES.duplicate()
	opts.shuffle()
	opts.resize(3)

	for opt in opts:
		var btn := Button.new()
		btn.text = opt.name
		btn.custom_minimum_size = Vector2(200, 90)
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(_select_upgrade.bind(opt.apply))
		hbox.add_child(btn)

	# 弹入动画
	upgrade_panel.modulate.a = 0.0
	upgrade_panel.scale = Vector2(0.8, 0.8)
	var tw := create_tween()
	tw.tween_property(upgrade_panel, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(upgrade_panel, "modulate:a", 1.0, 0.15)

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

	# 收起动画
	var tw := create_tween()
	tw.tween_property(upgrade_panel, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func(): upgrade_panel.visible = false; Game.is_paused = false)
	tw.finished.connect(func(): _update_hud())

# ========== 塔位拖放系统 ==========
func _on_tower_drag_start(tw_data: Dictionary) -> void:
	if Game.player_coins < tw_data.cost:
		_show_floating_text(get_global_mouse_position(), "金币不足！", Color(1, 0.2, 0.2))
		add_screen_shake(2.0)
		return
		
	_is_dragging_tower = true
	_drag_tower_data = tw_data
	
	if _ghost_tower:
		_ghost_tower.queue_free()
		
	_ghost_tower = ColorRect.new()
	_ghost_tower.size = Vector2(44, 44)
	_ghost_tower.pivot_offset = Vector2(22, 22)
	_ghost_tower.position = get_global_mouse_position() - Vector2(22, 22)
	_ghost_tower.modulate.a = 0.5
	_ghost_tower.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	match tw_data.type:
		"attack": _ghost_tower.color = Color(1, 0.45, 0.45)
		"control": _ghost_tower.color = Color(0.45, 0.75, 1.0)
		"aura": _ghost_tower.color = Color(0.45, 1.0, 0.55)

	add_child(_ghost_tower)

func _can_place_tower_at(pos: Vector2) -> bool:
	# 检查是否叠在其他塔的极近距离上（45像素为塔基座身位）
	for tw_dict in Game.placed_towers:
		if is_instance_valid(tw_dict.node) and pos.distance_to(tw_dict.node.global_position) < 45.0:
			return false
	return true

func _place_tower(pos: Vector2, tw_data: Dictionary) -> void:
	if not Game.spend_coins(tw_data.cost):
		return

	# 1. 创建物理塔节点
	var tower_node := Node2D.new()
	tower_node.name = "Tower_%s_%d" % [tw_data.key, randi() % 1000]
	tower_node.global_position = pos
	add_child(tower_node)
	
	# 2. 视觉表现 (小猫造型占位符)
	var sprite := ColorRect.new()
	sprite.size = Vector2(44, 44)
	sprite.pivot_offset = Vector2(22, 22)
	sprite.position = Vector2(-22, -22)
	match tw_data.type:
		"attack": sprite.color = Color(1, 0.45, 0.45) # 红色攻击
		"control": sprite.color = Color(0.45, 0.75, 1.0) # 蓝色控制
		"aura": sprite.color = Color(0.45, 1.0, 0.55) # 绿色光环
	tower_node.add_child(sprite)
	
	# 3. 注入战斗组件 (寻敌系统)
	var ts := TargetSystem.new()
	ts.name = "TargetSystem"
	tower_node.add_child(ts)
	
	# 4. 注入开火系统 (AutoAttack) - 仅限攻击/控制型
	if tw_data.type != "aura":
		var aa := AutoAttackSystem.new()
		aa.name = "AutoAttack"
		aa.base_damage = tw_data.dmg
		aa.attack_range = tw_data.range
		aa.base_cooldown = tw_data.iv
		aa.projectile_scene = PROJECTILE_SCENE
		tower_node.add_child(aa)
		
		# （子弹发出的命中信号在 auto_attack.gd 内部已经自动寻址并连接主游戏，
		# 这里无需重复连接，否则会导致 already connected 刷屏警告）
	
	# 5. 保存数据到全局用于统计或光环计算
	var tw_dict := {
		"node": tower_node,
		"type": tw_data.type,
		"damage": tw_data.get("dmg", 0),
	}
	Game.placed_towers.append(tw_dict)
	
	# 放置特效
	_spawn_place_effect(pos, Color.WHITE)
	add_screen_shake(2.0)
	
	# 刷新界面
	_update_hud()
	print_rich("[color=orange][Tower][/color] 已建造: %s 于 %s" % [tw_data.name, pos])

# ========== 屏幕震动 ==========

# ========== 屏幕震动 ==========
func add_screen_shake(intensity: float) -> void:
	_shake_intensity = max(_shake_intensity, intensity)

func _update_screen_shake(delta: float) -> void:
	if _shake_intensity <= 0.01:
		return
	var shake_offset: Vector2 = Vector2(
		randf_range(-1.0, 1.0) * _shake_intensity,
		randf_range(-1.0, 1.0) * _shake_intensity
	)
	$Camera2D.offset = shake_offset
	$Camera2D.offset = lerp($Camera2D.offset, Vector2.ZERO, 0.3)
	_shake_intensity *= exp(-_shake_decay * delta)
	if _shake_intensity < 0.1:
		_shake_intensity = 0.0
		$Camera2D.offset = Vector2.ZERO

# ========== 受击闪白 ==========
func _update_hit_flash(delta: float) -> void:
	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		var flash: float = _hit_flash_timer / 0.12
		var sprite: CanvasItem = player.get_node_or_null("Sprite") as CanvasItem
		if sprite:
			sprite.modulate = Color(1, 1 - flash * 0.6, 1 - flash * 0.6, 1)
	else:
		var sprite: CanvasItem = player.get_node_or_null("Sprite") as CanvasItem
		if sprite:
			sprite.modulate = Color.WHITE

# ========== 粒子特效 ==========
func _spawn_death_particles(pos: Vector2, size: float) -> void:
	var count: int = clampi(int(size / 3.0), 4, 16)
	var base_color: Color = Color(1, 0.25, 0.2)
	for i in range(count):
		var particle: ColorRect = ColorRect.new()
		var psize: float = randf_range(3.0, size * 0.4)
		particle.size = Vector2(psize, psize)
		particle.color = base_color.lightened(randf_range(0.0, 0.4))
		particle.position = pos + Vector2(randf_range(-size, size), randf_range(-size, size))
		particle.rotation = randf() * TAU
		effect_container.add_child(particle)

		# 物理运动 + 淡出
		var angle: float = randf() * TAU
		var speed: float = randf_range(60.0, 180.0)
		var lifetime: float = randf_range(0.3, 0.7)
		var tw: Tween = create_tween()
		tw.tween_property(particle, "position", particle.position + Vector2(cos(angle), sin(angle)) * speed * lifetime, lifetime)
		tw.parallel().tween_property(particle, "rotation", particle.rotation + randf_range(-TAU, TAU), lifetime)
		tw.parallel().tween_property(particle, "modulate:a", 0.0, lifetime * 0.7).set_delay(lifetime * 0.3)
		tw.tween_callback(particle.queue_free)

func _spawn_place_effect(pos: Vector2, color: Color) -> void:
	# 放置塔时的扩散环
	var ring: ColorRect = ColorRect.new()
	ring.size = Vector2(4, 4)
	ring.color = color
	ring.position = pos - Vector2(2, 2)
	effect_container.add_child(ring)

	var tw := create_tween()
	tw.tween_property(ring, "size", Vector2(48, 48), 0.35).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "position", pos - Vector2(24, 24), 0.35).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	tw.tween_callback(ring.queue_free)

func _process_effects(_delta: float) -> void:
	pass  # 粒子由 tween 管理，这里预留清理逻辑

# ========== Game over ==========
func _show_game_over_panel() -> void:
	if game_over_panel == null:
		game_over_panel = PanelContainer.new()
		# 使用锚点居中
		game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		game_over_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		game_over_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		game_over_panel.custom_minimum_size = Vector2(600, 340)
		ui.add_child(game_over_panel)

	game_over_panel.visible = true
	for c in game_over_panel.get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	game_over_panel.add_child(vbox)

	var title := Label.new()
	title.text = "💔 猫咪倒下了..."
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var stats := Label.new()
	stats.text = "存活到第 %d 波 | Lv.%d | 💰%d\n\n按 R 重新开始" % [_wave, Game.player_level, Game.player_coins]
	stats.add_theme_font_size_override("font_size", 17)
	stats.position = Vector2(0, 20)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

	_spawn_timer = 0

# ========== Helper ==========
func _random_edge_position() -> Vector2:
	var edge := randi() % 4
	match edge:
		0: return Vector2(randf_range(0, 1280), -25)
		1: return Vector2(randf_range(0, 1280), 745)
		2: return Vector2(-25, randf_range(0, 720))
		3: return Vector2(1305, randf_range(0, 720))
	return Vector2(0, 0)
