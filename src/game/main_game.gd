## 主游戏场景 (Main Game)
## 游戏核心循环的总控：输入、生成、波次、升级、塔位、UI、结算
## GDD: design/concept/game-concept.md + systems-index.md

class_name MainGame
extends Node2D

const UpgradeDataScript = preload("res://src/data/upgrade_data.gd")

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
@onready var feedback: CombatFeedbackManager = null
@onready var spawn_manager: SpawnManager = null
@onready var tower_manager: TowerManager = null
var upgrade_data: UpgradeData = null
@onready var tower_mod_manager: TowerModManager = null

# 弹丸场景（预加载）
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/gameplay/projectile.tscn")
const COMBAT_FEEDBACK_MANAGER_SCRIPT := preload("res://src/game/combat_feedback_manager.gd")
const SPAWN_MANAGER_SCRIPT := preload("res://src/game/spawn_manager.gd")
const TOWER_MANAGER_SCRIPT := preload("res://src/game/tower_manager.gd")
const TOWER_DATA_SCRIPT := preload("res://src/data/tower_data.gd")
const TOWER_MOD_MANAGER_SCRIPT := preload("res://src/game/tower_mod_manager.gd")

# Wave state
var wave_manager: WaveManager = null
var _game_started: bool = false # 准备阶段标志

var _tower_data = null
var _selected_slot_id: int = -1
var _hovered_slot_id: int = -1
var _slot_marker_nodes: Dictionary = {}
var _tower_shop_buttons: Dictionary = {}
var _preview_tower_key: String = ""
var _range_preview: Polygon2D = null
var _mod_target_slot_ids: Array[int] = []
var _pending_elite_mod_offers: int = 0

# UI refs
var hp_bar: ProgressBar
var hp_label: Label
var xp_bar: ProgressBar
var xp_label: Label
var coin_label: Label
var wave_label: Label
var tower_indicators: Array[Label] = []
var tower_shop_buttons: Array[Dictionary] = []

# Panels
var upgrade_panel: PanelContainer
var tower_info_panel: PanelContainer
var tower_mod_offer_panel: PanelContainer
var game_over_panel: PanelContainer

# 屏幕震动
var _shake_intensity: float = 0.0
var _shake_decay: float = 8.0

# 玩家受击闪白
var _hit_flash_timer: float = 0.0
var _pending_level_ups: int = 0

const ENEMY_SCENE_PATH: String = "res://scenes/characters/enemy_base.tscn"

# ========== _ready ==========
func _ready() -> void:
	# 注册组，供弹丸系统查找父节点
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_to_group("main_game")
	player.add_to_group("player")
	if ui == null:
		var uilayer = get_node_or_null("UILayer")
		if uilayer:
			ui = Control.new()
			ui.name = "UI"
			ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			uilayer.add_child(ui)

	Game.reset_session()
	_setup_components()
	upgrade_data = UpgradeDataScript.new()
	_setup_tower_data()
	_load_paths_from_nodes()
	_load_tower_slots()
	# 设置背景点击穿透，否则 _unhandled_input 会被拦截
	$Background.mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_setup_signals()

	# 初始处于准备阶段，不自动启动波次
	Game.request_pause(Game.PAUSE_REASON_READY)
	_show_ready_ui()
	if DisplayServer.get_name() == "headless":
		_start_game_from_ready()
	print_rich("[color=cyan][MainGame][/color] 核心系统已就绪，进入 [准备阶段]...")

func _show_ready_ui() -> void:
	var btn := Button.new()
	btn.name = "StartButton"
	btn.text = "开始进攻"
	btn.custom_minimum_size = Vector2(350, 80)
	btn.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# 使用锚点：居中底部
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	btn.offset_bottom = -80
	
	btn.add_theme_font_size_override("font_size", 24)
	ui.add_child(btn)
	
	btn.pressed.connect(func():
		_start_game_from_ready()
		btn.queue_free()
	)
	
	# 呼吸灯动画效果
	var tw := create_tween().set_loops()
	tw.tween_property(btn, "modulate:a", 0.6, 0.8)
	tw.tween_property(btn, "modulate:a", 1.0, 0.8)

func _start_game_from_ready() -> void:
	if _game_started:
		return
	_game_started = true
	Game.release_pause(Game.PAUSE_REASON_READY)
	if wave_manager:
		wave_manager.enable_waves()

func _load_paths_from_nodes() -> void:
	if spawn_manager:
		spawn_manager.load_paths_from_node(get_node_or_null("Paths") as Node2D)

func _setup_tower_data() -> void:
	_tower_data = TOWER_DATA_SCRIPT.new()
	if tower_manager:
		tower_manager.bind_tower_data(_tower_data)

func _load_tower_slots() -> void:
	if tower_manager:
		tower_manager.load_slots_from_node(get_node_or_null("TowerSlots"))
		_build_slot_markers()
		_ensure_range_preview()

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
	hero_health.max_hp = Game.player_max_hp
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

	feedback = COMBAT_FEEDBACK_MANAGER_SCRIPT.new()
	feedback.name = "CombatFeedbackManager"
	add_child(feedback)
	feedback.bind_refs(player, damage_container, effect_container, $Camera2D)

	spawn_manager = SPAWN_MANAGER_SCRIPT.new()
	spawn_manager.name = "SpawnManager"
	add_child(spawn_manager)
	spawn_manager.bind_host(enemy_container, ENEMY_SCENE_PATH)
	spawn_manager.enemy_reached_base.connect(_on_enemy_reached_base)
	spawn_manager.enemy_died.connect(_on_enemy_died_wrapper)
	spawn_manager.enemy_damage_taken.connect(_on_enemy_damage_taken)

	tower_manager = TOWER_MANAGER_SCRIPT.new()
	tower_manager.name = "TowerManager"
	add_child(tower_manager)
	tower_manager.bind_host(self, PROJECTILE_SCENE)
	tower_manager.tower_placed.connect(_on_tower_placed)

	tower_mod_manager = TOWER_MOD_MANAGER_SCRIPT.new()
	tower_mod_manager.name = "TowerModManager"
	add_child(tower_mod_manager)
	tower_mod_manager.mod_applied.connect(_on_tower_mod_applied)

func _setup_signals() -> void:
	if hero_health:
		hero_health.hp_changed.connect(_on_hp_changed)
		hero_health.damage_taken.connect(_on_player_damage_taken)
		hero_health.player_died.connect(_on_player_died)
		_on_hp_changed(hero_health.current_hp, hero_health.max_hp)

# ========== _process ==========
func _unhandled_input(event: InputEvent) -> void:
	if Game.is_game_over:
		if event is InputEventKey and event.keycode == KEY_R and event.pressed:
			get_tree().reload_current_scene()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if tower_mod_offer_panel and tower_mod_offer_panel.visible:
			_close_tower_mod_offer_flow()
			_show_floating_text(player.global_position + Vector2(0, -72), "已取消这次塔改造选择", Color(0.9, 0.9, 1.0))
			return
		if _is_waiting_for_mod_target():
			_close_tower_mod_offer_flow()
			_show_floating_text(player.global_position + Vector2(0, -72), "已取消这次塔改造装备", Color(0.9, 0.9, 1.0))
			return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		if not Game.is_paused:
			_open_debug_tower_mod_offer()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var slot_id: int = tower_manager.find_slot_id_at_position(get_global_mouse_position())
		if slot_id != -1:
			if _is_waiting_for_mod_target():
				_try_apply_pending_mod(slot_id)
			elif not Game.is_paused:
				_select_tower_slot(slot_id)
			return

	if Game.is_paused:
		return

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
	_try_open_pending_tower_mod_offer()
	_update_hovered_slot()
	_update_range_preview()
		
	# 屏幕震动更新
	_update_screen_shake(delta)

	# 受击闪白更新
	_update_hit_flash(delta)

func _get_alive_enemy_count() -> int:
	if spawn_manager:
		return spawn_manager.get_alive_enemy_count()
	return 0

# ========== Wave system ==========
func _on_wave_started(wave_num: int) -> void:
	Game.current_wave = wave_num
	if wave_label:
		wave_label.text = "第 %d 波" % wave_num
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
	if spawn_manager:
		var spawned_enemy = spawn_manager.spawn_enemy(enemy_type)
		if enemy_type == "elite" and is_instance_valid(spawned_enemy):
			_show_floating_text(spawned_enemy.global_position + Vector2(0, -26), "精英来袭！", Color(1.0, 0.7, 0.3))

func _on_enemy_reached_base(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	
	# 扣除基地生命值
	var enemy_base: EnemyBase = enemy as EnemyBase
	var dmg: int = enemy_base._data.get("damage", 1)
	if hero_health:
		hero_health.apply_damage(dmg, {"kind": "base_reach"})
	else:
		Game.player_hp = clampi(Game.player_hp - dmg, 0, Game.player_max_hp)
		_update_hud()
	
	# 如果生命归零则失败
	if hero_health and hero_health.current_hp <= 0:
		_on_player_died()
	elif Game.player_hp <= 0:
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
					_grant_xp(val)
					_show_floating_text(pickup.global_position, "+%d XP" % val, Color(0.7, 0.5, 1.0))
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
		_grant_xp(value)
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
	var enemy_type: String = (enemy as EnemyBase).enemy_type if enemy is EnemyBase else ""
	var coin_val := int(enemy_data.get("coin", 2))
	var xp_val := int(enemy_data.get("xp", 3))

	# 塔防模式：直接入账，不散落物理拾取物，不用跑过去吃
	Game.add_coins(coin_val)
	_grant_xp(xp_val)
	_update_hud()
	
	# 原地视觉提示取代掉落
	_show_floating_text(enemy.global_position, "+%d 💰" % coin_val, Color(1, 0.85, 0.2))
	_show_floating_text(enemy.global_position + Vector2(0, -15), "+%d XP" % xp_val, Color(0.7, 0.5, 1.0))

	# 死亡爆炸粒子
	_spawn_death_particles(enemy.global_position, enemy_data.get("body_size", 14.0))

	# 小屏幕震动
	add_screen_shake(3.0)

	if enemy_type == "elite":
		_queue_elite_tower_mod_offer(enemy.global_position)

func _calc_xp_needed(level: int) -> int:
	return ceil(10.0 * pow(level, 0.9))

func _grant_xp(amount: int) -> void:
	var levels_gained := Game.add_xp(amount)
	if levels_gained > 0:
		_pending_level_ups += levels_gained
		if not Game.is_game_over and (upgrade_panel == null or not upgrade_panel.visible):
			_open_next_upgrade_panel()

func _open_next_upgrade_panel() -> void:
	if _pending_level_ups <= 0 or Game.is_game_over:
		return
	_pending_level_ups -= 1
	_show_upgrade_panel()

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
	shop_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	shop_margin.offset_left = 20
	shop_margin.offset_top = -100
	shop_margin.offset_right = 20
	shop_margin.offset_bottom = -20
	ui.add_child(shop_margin)

	var shop_hbox := HBoxContainer.new()
	shop_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_hbox.add_theme_constant_override("separation", 15)
	shop_margin.add_child(shop_hbox)

	var t_lbl := Label.new()
	t_lbl.text = "先点塔位，再建塔 👉 "
	t_lbl.add_theme_font_size_override("font_size", 16)
	shop_hbox.add_child(t_lbl)

	for tw in _tower_data.get_all_towers():
		var btn := Button.new()
		btn.text = _format_tower_button_text(tw)
		btn.custom_minimum_size = Vector2(85, 75)
		btn.add_theme_font_size_override("font_size", 14)
		var tower_key := String(tw.get("key", ""))
		btn.pressed.connect(_on_build_tower_button_pressed.bind(tower_key))
		btn.mouse_entered.connect(_on_shop_button_hovered.bind(tower_key))
		btn.mouse_exited.connect(_on_shop_button_unhovered.bind(tower_key))
		shop_hbox.add_child(btn)
		tower_shop_buttons.append({"button": btn, "data": tw})
		_tower_shop_buttons[tower_key] = btn

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
	_refresh_tower_shop_buttons()

	# (已移除塔插槽更新)

# ========== Damage numbers & floating text ==========
func _show_damage_number(world_pos: Vector2, value: int, is_crit: bool) -> void:
	if feedback:
		feedback.show_damage_number(world_pos, value, is_crit)

func _show_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	if feedback:
		feedback.show_floating_text(world_pos, text, color)

# ========== 弹丸处理 ==========
func _on_projectile_hit(enemy: Node, dmg: int, is_crit: bool) -> void:
	pass

# ========== Signals ==========
func _on_hp_changed(current: int, max_val: int) -> void:
	Game.player_hp = current
	Game.player_max_hp = max_val
	_update_hud()
	if feedback:
		feedback.notify_player_hp_changed(current)

func _on_player_damage_taken(amount: int, _current: int, _max_hp: int, context: Dictionary) -> void:
	_show_floating_text(player.global_position + Vector2(0, -28), "-%d" % amount, Color(1, 0.2, 0.2))
	if String(context.get("kind", "")) == "base_reach":
		_show_floating_text(player.global_position + Vector2(0, -52), "-%d 🏠" % amount, Color(1, 0, 0))

func _on_enemy_damage_taken(amount: int, _current: int, _max_hp: int, context: Dictionary, enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	var is_crit := bool(context.get("crit", false))
	_show_damage_number(enemy.global_position, amount, is_crit)

func _on_player_died() -> void:
	Game.is_game_over = true
	Game.request_pause(Game.PAUSE_REASON_GAME_OVER)
	await get_tree().create_timer(0.8).timeout
	_show_game_over_panel()

func _show_upgrade_panel() -> void:
	if upgrade_panel == null:
		upgrade_panel = PanelContainer.new()
		# 使用锚点居中
		upgrade_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		upgrade_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		upgrade_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		upgrade_panel.custom_minimum_size = Vector2(700, 340)
		upgrade_panel.visible = false
		upgrade_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		upgrade_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		upgrade_panel.z_index = 100
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
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	var opts: Array[Dictionary] = []
	if upgrade_data:
		opts = upgrade_data.get_candidates(max(Game.current_wave, 1), 3)
	if opts.is_empty():
		opts = [{
			"name": "锋利猫爪",
			"desc": "主角补刀更疼，更容易清掉漏怪（伤害 +5）",
			"rarity": "Common",
			"apply": "hero_damage_flat",
			"value": 5
		}]

	for opt in opts:
		var btn := Button.new()
		btn.text = "%s\n%s" % [String(opt.get("name", "升级")), String(opt.get("desc", ""))]
		btn.custom_minimum_size = Vector2(210, 120)
		btn.add_theme_font_size_override("font_size", 16)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_stylebox_override("normal", _make_upgrade_card_style(String(opt.get("rarity", "Common")), false))
		btn.add_theme_stylebox_override("hover", _make_upgrade_card_style(String(opt.get("rarity", "Common")), true))
		btn.pressed.connect(_select_upgrade.bind(opt))
		hbox.add_child(btn)

	# 弹入动画
	upgrade_panel.modulate.a = 0.0
	upgrade_panel.scale = Vector2(0.8, 0.8)
	Game.request_pause(Game.PAUSE_REASON_UPGRADE)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(upgrade_panel, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(upgrade_panel, "modulate:a", 1.0, 0.15)

func _select_upgrade(upgrade: Dictionary) -> void:
	var applied: bool = _apply_upgrade(upgrade)
	if applied:
		Game.record_upgrade(upgrade)
		_show_floating_text(player.global_position + Vector2(0, -60), "已升级: %s" % String(upgrade.get("name", "升级")), Color(0.8, 1.0, 0.65))

	# 收起动画
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(upgrade_panel, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func(): upgrade_panel.visible = false)
	tw.finished.connect(func():
		_update_hud()
		if _pending_level_ups > 0:
			_open_next_upgrade_panel()
		else:
			Game.release_pause(Game.PAUSE_REASON_UPGRADE)
	)

func _apply_upgrade(upgrade: Dictionary) -> bool:
	var apply_key: String = String(upgrade.get("apply", ""))
	var value: Variant = upgrade.get("value")

	match apply_key:
		"hero_damage_flat":
			Game.player_damage += int(value)
			if auto_attack:
				auto_attack.base_damage = Game.player_damage
			return true
		"hero_attack_speed_pct":
			Game.player_attack_speed_bonus += float(value)
			if auto_attack:
				auto_attack.set_attack_speed_bonus(Game.player_attack_speed_bonus)
			return true
		"hero_range_flat":
			Game.player_range += float(value)
			if auto_attack:
				auto_attack.set_range_bonus(Game.player_range - auto_attack.base_range)
			return true
		"hero_hp_flat":
			Game.set_player_max_hp(Game.player_max_hp + int(value))
			Game.heal_player(int(value))
			if hero_health:
				hero_health.max_hp = Game.player_max_hp
				hero_health.heal(int(value))
			return true
		"hero_speed_pct":
			Game.player_speed_mult *= 1.0 + float(value)
			if movement:
				movement.base_speed = Game.player_speed * Game.player_speed_mult
			return true
		"tower_damage_pct", "tower_attack_speed_pct", "tower_range_pct", "tower_cost_pct", "aura_buff_flat", "fish_split_targets", "yarn_splash_slow_unlock", "tower_specialize_fish", "tower_specialize_yarn":
			if tower_manager:
				return tower_manager.apply_upgrade_effect(apply_key, value)

	return false

func _on_build_tower_button_pressed(tower_key: String) -> void:
	if _selected_slot_id == -1:
		_show_floating_text(get_global_mouse_position(), "先选择一个塔位", Color(1, 1, 0.4))
		return
	_request_place_tower(_selected_slot_id, tower_key)

func _request_place_tower(slot_id: int, tower_key: String) -> void:
	var tower_data: Dictionary = _tower_data.get_tower_by_key(tower_key)
	if tower_data.is_empty():
		return
	if Game.player_coins < int(tower_data.get("cost", 0)):
		_show_floating_text(get_global_mouse_position(), "金币不足！", Color(1, 0.2, 0.2))
		add_screen_shake(2.0)
		return
	if not tower_manager.can_place_on_slot(slot_id):
		var slot_info: Dictionary = tower_manager.get_slot_data(slot_id)
		var pos: Vector2 = slot_info.get("position", get_global_mouse_position())
		_show_floating_text(pos, "该塔位已被占用", Color(1, 0.2, 0.2))
		add_screen_shake(2.0)
		return
	tower_manager.place_tower_on_slot(slot_id, tower_key)

func _select_tower_slot(slot_id: int) -> void:
	var slot_info: Dictionary = tower_manager.get_slot_data(slot_id)
	var is_occupied := bool(slot_info.get("occupied", false))
	if slot_id == _selected_slot_id and is_occupied and tower_info_panel and tower_info_panel.visible:
		_selected_slot_id = -1
		_hide_tower_info_panel()
		_preview_tower_key = ""
		_refresh_slot_markers()
		return

	_selected_slot_id = slot_id
	_refresh_slot_markers()
	var slot_pos: Vector2 = slot_info.get("position", get_global_mouse_position())
	if is_occupied:
		_show_tower_info_panel(slot_id)
		_show_floating_text(slot_pos, "已选中已有塔位", Color(0.7, 0.85, 1.0))
	else:
		_hide_tower_info_panel()
		_preview_tower_key = ""
		_show_floating_text(slot_pos, "已选中空塔位", Color(0.7, 1.0, 0.7))

func _on_tower_placed(slot_id: int, tower_node: Node2D, tw_data: Dictionary) -> void:
	_spawn_place_effect(tower_node.global_position, Color.WHITE)
	add_screen_shake(2.0)
	_update_hud()
	_selected_slot_id = -1
	_preview_tower_key = ""
	_hide_tower_info_panel()
	_refresh_slot_markers()
	print_rich("[color=orange][Tower][/color] 已建造: %s 于 slot %d" % [String(tw_data.get("name", "Tower")), slot_id])

func _build_slot_markers() -> void:
	for marker in _slot_marker_nodes.values():
		if is_instance_valid(marker):
			marker.queue_free()
	_slot_marker_nodes.clear()

	for slot in tower_manager.get_all_slots():
		var slot_id := int(slot.get("id", -1))
		var slot_node = tower_manager.get_slot_node(slot_id)
		if slot_node == null:
			continue

		var marker := ColorRect.new()
		marker.name = "SlotMarker"
		marker.size = Vector2(54, 54)
		marker.position = Vector2(-27, -27)
		marker.color = Color(0.9, 0.9, 0.95, 0.25)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_node.add_child(marker)
		_slot_marker_nodes[slot_id] = marker

	_refresh_slot_markers()

func _refresh_slot_markers() -> void:
	for slot in tower_manager.get_all_slots():
		var slot_id := int(slot.get("id", -1))
		var marker := _slot_marker_nodes.get(slot_id, null) as ColorRect
		if marker == null:
			continue

		if bool(slot.get("occupied", false)):
			var tower_data: Dictionary = slot.get("tower_data", {})
			marker.color = _get_slot_base_color(bool(slot.get("occupied", false)), String(tower_data.get("type", "")))
		else:
			marker.color = _get_slot_base_color(false, "")

		if _mod_target_slot_ids.has(slot_id):
			marker.color = Color(1.0, 0.65, 0.2, 0.6)

		if slot_id == _hovered_slot_id and slot_id != _selected_slot_id:
			marker.color = Color(1.0, 1.0, 1.0, 0.42)

		if slot_id == _selected_slot_id:
			marker.color = _get_slot_selected_color(slot)

func _show_tower_info_panel(slot_id: int) -> void:
	var slot_info: Dictionary = tower_manager.get_slot_data(slot_id)
	if slot_info.is_empty() or not bool(slot_info.get("occupied", false)):
		_hide_tower_info_panel()
		return

	var tower_data: Dictionary = slot_info.get("tower_data", {})
	var tower_node := slot_info.get("tower_node", null) as Node2D
	if tower_data.is_empty() or tower_node == null:
		_hide_tower_info_panel()
		return

	if tower_info_panel == null:
		tower_info_panel = PanelContainer.new()
		tower_info_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		tower_info_panel.offset_left = -300
		tower_info_panel.offset_top = 24
		tower_info_panel.offset_right = -24
		tower_info_panel.offset_bottom = 220
		tower_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tower_info_panel.visible = false
		ui.add_child(tower_info_panel)

	tower_info_panel.visible = true
	for child in tower_info_panel.get_children():
		child.queue_free()

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 10)
	tower_info_panel.add_child(info_box)

	var title := Label.new()
	title.text = "塔信息"
	title.add_theme_font_size_override("font_size", 22)
	info_box.add_child(title)

	var badge := Label.new()
	badge.text = _get_tower_info_badge_text(String(tower_data.get("type", "")))
	badge.add_theme_color_override("font_color", _get_tower_type_accent(String(tower_data.get("type", ""))))
	badge.add_theme_font_size_override("font_size", 14)
	info_box.add_child(badge)

	var name_label := Label.new()
	name_label.text = "%s  |  Slot %d" % [String(tower_data.get("name", "未知塔")), slot_id + 1]
	name_label.add_theme_font_size_override("font_size", 18)
	info_box.add_child(name_label)

	var role_label := Label.new()
	role_label.text = "类型: %s" % _get_tower_role_text(String(tower_data.get("type", "")))
	info_box.add_child(role_label)

	var effect_label := Label.new()
	effect_label.text = _build_tower_effect_text(tower_data, tower_node)
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(effect_label)

	if tower_data.has("applied_mod_name"):
		var mod_label := Label.new()
		mod_label.text = "改造: %s" % String(tower_data.get("applied_mod_name", ""))
		mod_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
		mod_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(mod_label)

	var tip_label := Label.new()
	tip_label.text = "再次点击这座塔可收起面板，点击空塔位可切回建塔。"
	tip_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(tip_label)

func _hide_tower_info_panel() -> void:
	if tower_info_panel:
		tower_info_panel.visible = false

func _update_hovered_slot() -> void:
	var next_hovered_slot := -1
	if not Game.is_paused and not Game.is_game_over:
		next_hovered_slot = tower_manager.find_slot_id_at_position(get_global_mouse_position())
	if next_hovered_slot != _hovered_slot_id:
		_hovered_slot_id = next_hovered_slot
		_refresh_slot_markers()

func _on_shop_button_hovered(tower_key: String) -> void:
	_preview_tower_key = tower_key

func _on_shop_button_unhovered(tower_key: String) -> void:
	if _preview_tower_key == tower_key:
		_preview_tower_key = ""

func _open_debug_tower_mod_offer() -> void:
	var offers: Array[Dictionary] = tower_mod_manager.get_debug_offers(tower_manager.get_all_slots())
	if offers.is_empty():
		_show_floating_text(player.global_position + Vector2(0, -72), "当前没有可用的塔改造目标", Color(1.0, 0.8, 0.35))
		return

	_show_tower_mod_offer_panel(offers)
	Game.request_pause("tower_mod_offer")

func _queue_elite_tower_mod_offer(world_pos: Vector2) -> void:
	_pending_elite_mod_offers += 1
	_show_floating_text(world_pos + Vector2(0, -32), "精英掉落了塔改造机会", Color(1.0, 0.8, 0.35))
	_try_open_pending_tower_mod_offer()

func _try_open_pending_tower_mod_offer() -> void:
	if _pending_elite_mod_offers <= 0:
		return
	if Game.is_game_over or Game.is_paused:
		return
	if _is_waiting_for_mod_target():
		return
	if tower_mod_offer_panel and tower_mod_offer_panel.visible:
		return
	if upgrade_panel and upgrade_panel.visible:
		return

	var offers: Array[Dictionary] = tower_mod_manager.get_debug_offers(tower_manager.get_all_slots())
	if offers.is_empty():
		return

	_pending_elite_mod_offers -= 1
	_show_tower_mod_offer_panel(offers)
	Game.request_pause("tower_mod_offer")

func _show_tower_mod_offer_panel(offers: Array[Dictionary]) -> void:
	tower_mod_manager.start_offer(offers)
	_mod_target_slot_ids.clear()

	if tower_mod_offer_panel == null:
		tower_mod_offer_panel = PanelContainer.new()
		tower_mod_offer_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		tower_mod_offer_panel.custom_minimum_size = Vector2(760, 320)
		tower_mod_offer_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		tower_mod_offer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		tower_mod_offer_panel.visible = false
		tower_mod_offer_panel.z_index = 120
		ui.add_child(tower_mod_offer_panel)

	tower_mod_offer_panel.visible = true
	for child in tower_mod_offer_panel.get_children():
		child.queue_free()

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	tower_mod_offer_panel.add_child(root)

	var title := Label.new()
	title.text = "调试塔改造"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "按 M 打开。先选择一个改造，再点击兼容的塔位装备。"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
	root.add_child(subtitle)

	var options := HBoxContainer.new()
	options.alignment = BoxContainer.ALIGNMENT_CENTER
	options.add_theme_constant_override("separation", 18)
	root.add_child(options)

	for offer in offers:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(210, 150)
		btn.text = "%s\n%s" % [String(offer.get("name", "")), String(offer.get("description", ""))]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_tower_mod_offer_selected.bind(String(offer.get("id", ""))))
		options.add_child(btn)

func _on_tower_mod_offer_selected(mod_id: String) -> void:
	var mod_data: Dictionary = tower_mod_manager.select_offer(mod_id)
	if mod_data.is_empty():
		return

	_mod_target_slot_ids = tower_mod_manager.get_compatible_slot_ids(tower_manager.get_all_slots())
	if _mod_target_slot_ids.is_empty():
		_show_floating_text(player.global_position + Vector2(0, -72), "没有兼容这次改造的塔位", Color(1.0, 0.4, 0.35))
		_close_tower_mod_offer_flow()
		return

	if tower_mod_offer_panel:
		tower_mod_offer_panel.visible = false
	Game.release_pause("tower_mod_offer")
	_selected_slot_id = -1
	_hide_tower_info_panel()
	_preview_tower_key = ""
	_refresh_slot_markers()
	_show_floating_text(player.global_position + Vector2(0, -72), "选择一座高亮塔位来装备改造", Color(1.0, 0.8, 0.35))

func _is_waiting_for_mod_target() -> bool:
	return tower_mod_manager and tower_mod_manager.has_pending_mod() and not _mod_target_slot_ids.is_empty()

func _try_apply_pending_mod(slot_id: int) -> void:
	if not _mod_target_slot_ids.has(slot_id):
		var slot_info: Dictionary = tower_manager.get_slot_data(slot_id)
		var slot_pos: Vector2 = slot_info.get("position", get_global_mouse_position())
		_show_floating_text(slot_pos, "这座塔不兼容当前改造", Color(1.0, 0.45, 0.35))
		return

	var slot_node = tower_manager.get_slot_node(slot_id)
	var applied_mod: Dictionary = tower_mod_manager.apply_pending_mod_to_slot(slot_id, slot_node)
	if applied_mod.is_empty():
		return

	_mod_target_slot_ids.clear()
	_refresh_slot_markers()
	_show_tower_info_panel(slot_id)

func _on_tower_mod_applied(slot_id: int, mod_data: Dictionary) -> void:
	var slot_info: Dictionary = tower_manager.get_slot_data(slot_id)
	var slot_pos: Vector2 = slot_info.get("position", player.global_position)
	_show_floating_text(slot_pos, "改造完成: %s" % String(mod_data.get("name", "")), Color(1.0, 0.82, 0.35))
	add_screen_shake(2.0)

func _close_tower_mod_offer_flow() -> void:
	_mod_target_slot_ids.clear()
	if tower_mod_manager:
		tower_mod_manager.clear_offer_state()
	if tower_mod_offer_panel:
		tower_mod_offer_panel.visible = false
	_selected_slot_id = -1
	_preview_tower_key = ""
	_hide_tower_info_panel()
	if Game.is_paused:
		Game.release_pause("tower_mod_offer")
	_refresh_slot_markers()

func _ensure_range_preview() -> void:
	if _range_preview != null:
		return

	_range_preview = Polygon2D.new()
	_range_preview.name = "RangePreview"
	_range_preview.visible = false
	_range_preview.z_index = -1
	add_child(_range_preview)

func _update_range_preview() -> void:
	if _range_preview == null:
		return

	var preview_info := _get_range_preview_info()
	if preview_info.is_empty():
		_range_preview.visible = false
		return

	var center: Vector2 = preview_info.get("position", Vector2.ZERO)
	var radius: float = float(preview_info.get("radius", 0.0))
	var color: Color = preview_info.get("color", Color(1, 1, 1, 0.18))
	if radius <= 0.0:
		_range_preview.visible = false
		return

	_range_preview.polygon = _build_circle_polygon(radius, 40)
	_range_preview.position = center
	_range_preview.color = color
	_range_preview.visible = true

func _get_range_preview_info() -> Dictionary:
	if _selected_slot_id == -1:
		return {}

	var slot_info: Dictionary = tower_manager.get_slot_data(_selected_slot_id)
	if slot_info.is_empty():
		return {}

	var slot_pos: Vector2 = slot_info.get("position", Vector2.ZERO)
	var is_occupied := bool(slot_info.get("occupied", false))
	var tower_data: Dictionary = {}
	if is_occupied:
		tower_data = slot_info.get("tower_data", {})
	elif not _preview_tower_key.is_empty():
		tower_data = _tower_data.get_tower_by_key(_preview_tower_key)

	if tower_data.is_empty():
		return {}

	var tower_type := String(tower_data.get("type", ""))
	var preview_color := _get_tower_type_accent(tower_type)
	preview_color.a = 0.14
	return {
		"position": slot_pos,
		"radius": float(tower_data.get("range", 0.0)),
		"color": preview_color,
	}

func _build_circle_polygon(radius: float, points: int = 32) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	polygon.append(Vector2.ZERO)
	for i in range(points + 1):
		var angle := TAU * float(i) / float(points)
		polygon.append(Vector2(cos(angle), sin(angle)) * radius)
	return polygon

func _build_tower_effect_text(tower_data: Dictionary, tower_node: Node2D) -> String:
	var tower_type := String(tower_data.get("type", ""))
	if tower_type == "aura":
		var buff_pct := int(round(float(tower_data.get("buff", 0.0)) * 100.0))
		var aura_range := int(round(float(tower_data.get("range", 0.0))))
		return "效果: 为范围内友方提供 %d%% 增益\n覆盖: %d px" % [buff_pct, aura_range]

	var auto_attack_node := tower_node.get_node_or_null("AutoAttack") as AutoAttackSystem
	var damage := int(tower_data.get("dmg", 0))
	var attack_range := int(round(float(tower_data.get("range", 0.0))))
	var cooldown := float(tower_data.get("iv", 0.0))
	if auto_attack_node:
		damage = auto_attack_node.base_damage
		attack_range = int(round(auto_attack_node.attack_range))
		cooldown = auto_attack_node.base_cooldown

	return "伤害: %d\n范围: %d px\n间隔: %.1f s" % [damage, attack_range, cooldown]

func _get_tower_role_text(tower_type: String) -> String:
	match tower_type:
		"attack":
			return "输出塔"
		"control":
			return "控制输出塔"
		"aura":
			return "辅助塔"
		_:
			return "未知"

func _get_slot_base_color(is_occupied: bool, tower_type: String) -> Color:
	if not is_occupied:
		return Color(0.9, 0.9, 0.95, 0.25)

	match tower_type:
		"attack":
			return Color(1.0, 0.45, 0.45, 0.35)
		"control":
			return Color(0.45, 0.75, 1.0, 0.35)
		"aura":
			return Color(0.45, 1.0, 0.55, 0.35)
		_:
			return Color(0.35, 0.55, 0.8, 0.35)

func _get_slot_selected_color(slot: Dictionary) -> Color:
	var is_occupied := bool(slot.get("occupied", false))
	if not is_occupied:
		return Color(1.0, 0.9, 0.35, 0.55)

	var tower_data: Dictionary = slot.get("tower_data", {})
	var accent := _get_tower_type_accent(String(tower_data.get("type", "")))
	return Color(accent.r, accent.g, accent.b, 0.58)

func _get_tower_type_accent(tower_type: String) -> Color:
	match tower_type:
		"attack":
			return Color(1.0, 0.55, 0.48)
		"control":
			return Color(0.52, 0.8, 1.0)
		"aura":
			return Color(0.55, 1.0, 0.65)
		_:
			return Color(1.0, 0.9, 0.35)

func _get_tower_info_badge_text(tower_type: String) -> String:
	match tower_type:
		"attack":
			return "主力输出"
		"control":
			return "控场输出"
		"aura":
			return "范围辅助"
		_:
			return "未知定位"

# ========== 屏幕震动 ==========

# ========== 屏幕震动 ==========
func add_screen_shake(intensity: float) -> void:
	if feedback:
		feedback.add_screen_shake(intensity)

func _update_screen_shake(delta: float) -> void:
	if feedback:
		feedback.update(delta)

# ========== 受击闪白 ==========
func _update_hit_flash(delta: float) -> void:
	pass

# ========== 粒子特效 ==========
func _spawn_death_particles(pos: Vector2, size: float) -> void:
	if feedback:
		feedback.spawn_death_particles(pos, size)

func _spawn_place_effect(pos: Vector2, color: Color) -> void:
	if feedback:
		feedback.spawn_place_effect(pos, color)

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
	var final_wave := Game.current_wave
	if wave_manager:
		final_wave = wave_manager.current_wave
	stats.text = "存活到第 %d 波 | Lv.%d | 💰%d\n\n按 R 重新开始" % [final_wave, Game.player_level, Game.player_coins]
	stats.add_theme_font_size_override("font_size", 17)
	stats.position = Vector2(0, 20)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

# ========== Helper ==========
func _make_upgrade_card_style(rarity: String, is_hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	match rarity:
		"Rare":
			style.bg_color = Color(0.12, 0.18, 0.34, 0.96)
			style.border_color = Color(0.45, 0.72, 1.0)
		"Epic":
			style.bg_color = Color(0.20, 0.12, 0.34, 0.96)
			style.border_color = Color(0.82, 0.56, 1.0)
		_:
			style.bg_color = Color(0.20, 0.20, 0.24, 0.96)
			style.border_color = Color(0.72, 0.72, 0.72)

	if is_hovered:
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		style.expand_margin_left = 2
		style.expand_margin_top = 2
		style.expand_margin_right = 2
		style.expand_margin_bottom = 2

	return style

func _format_tower_button_text(tw_data: Dictionary) -> String:
	var effective_cost := int(tw_data.get("cost", 0))
	if tower_manager:
		effective_cost = tower_manager.get_effective_cost(tw_data)
	return "%s\n💰%d" % [String(tw_data.get("name", "塔")), effective_cost]

func _refresh_tower_shop_buttons() -> void:
	for entry in tower_shop_buttons:
		var btn := entry.get("button") as Button
		var tw_data := entry.get("data", {}) as Dictionary
		if btn == null:
			continue
		btn.text = _format_tower_button_text(tw_data)
		var effective_cost := int(tw_data.get("cost", 0))
		if tower_manager:
			effective_cost = tower_manager.get_effective_cost(tw_data)
		var affordable := Game.player_coins >= effective_cost
		btn.modulate = Color(1, 1, 1, 1) if affordable else Color(0.75, 0.75, 0.75, 0.85)
