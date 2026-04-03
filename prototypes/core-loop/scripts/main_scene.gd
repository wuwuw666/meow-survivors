# PROTOTYPE - NOT FOR PRODUCTION
# Main game scene: extends GameState, spawns hero, enemies, handles waves, UI, tower placement
# Date: 2026-04-03
extends "res://prototypes/core-loop/scripts/game_state.gd"

# node refs
@onready var player: CharacterBody2D = $Player
@onready var enemy_container: Node2D = $EnemyContainer
@onready var ui: CanvasLayer = $UILayer
var hp_bar: TextureProgressBar
var xp_bar: TextureProgressBar
var coin_label: Label
var wave_label: Label
var damage_number_container: Node2D

var wave_enemies_to_spawn: int = 0
var wave_spawn_timer: float = 0.0
var wave_spawn_interval: float = 1.2
var wave_active: bool = false
var wave_clear: bool = false
var wave_cooldown: float = 0.0
var boss_spawned: bool = false

const SPAWN_POINTS = [
	Vector2(0, 100), Vector2(0, 360), Vector2(0, 620),
	Vector2(1280, 100), Vector2(1280, 360), Vector2(1280, 620),
	Vector2(200, 0), Vector2(1080, 0),
]

const UPGRADE_POOL = [
	{"id": "dmg_up", "name": "伤害 +5", "icon": "⚔️", "apply": "apply_dmg_up"},
	{"id": "aspd_up", "name": "攻速 +20%", "icon": "⚡", "apply": "apply_aspd_up"},
	{"id": "range_up", "name": "射程 +30px", "icon": "🎯", "apply": "apply_range_up"},
	{"id": "hp_up", "name": "生命 +20", "icon": "❤️", "apply": "apply_hp_up"},
	{"id": "speed_up", "name": "移速 +15%", "icon": "💨", "apply": "apply_speed_up"},
	{"id": "tower_dmg", "name": "塔伤害 +3", "icon": "🗼", "apply": "apply_tower_dmg"},
]

var tower_select_panel: PanelContainer
var upgrade_panel: PanelContainer
var selecting_slot: int = -1
var tower_attack_delta: float = 0.0

### ---- GAME STATE overrides ----
func _on_level_up():
	_show_upgrade_panel()

### ---- Core lifecycle ----
func _ready():
	randomize()
	player_damage = 5
	player_attack_speed = 0.8
	player_hp = 100
	player_max_hp = 100
	_build_ui()
	_setup_tower_slots()
	player.position = Vector2(640, 360)
	player.hp = 100
	player.max_hp = 100
	player.attack_cooldown = player_attack_speed
	player.attack_range = player_range
	player.speed = player_speed
	start_wave(1)

func _process(delta: float):
	if game_over:
		_show_game_over()
		return

	tower_attack_delta += delta
	if tower_attack_delta >= 0.1:
		tower_attack_delta = 0.0
		_process_tower_attacks()

	update_hud()

	# wave cooldown logic
	if not is_paused and not wave_active and not wave_clear:
		wave_cooldown -= delta
		if wave_cooldown <= 0:
			start_wave(current_wave + 1)

	# wave clear check
	if wave_active and wave_enemies_to_spawn <= 0 and enemy_container.get_child_count() == 0:
		wave_active = false
		wave_clear = true
		wave_cooldown = 3.0
		wave_label.text = "第 %d 波完成！准备中..." % current_wave

	# wave spawning
	_update_wave_timer(delta)

func _physics_process(delta: float):
	if not game_over and player:
		_check_player_enemy_collision()

func _update_wave_timer(delta: float):
	if not wave_active:
		return
	wave_spawn_timer -= delta
	if wave_spawn_timer <= 0 and wave_enemies_to_spawn > 0:
		wave_spawn_timer = wave_spawn_interval
		_spawn_one_enemy()
		wave_enemies_to_spawn -= 1

### ---- Waves ----
func start_wave(wave_num: int):
	current_wave = wave_num
	if wave_num == 10 and not boss_spawned:
		_spawn_boss()
		wave_enemies_to_spawn = 5
		wave_active = true
		wave_spawn_interval = 2.0
	elif wave_num <= 5:
		wave_enemies_to_spawn = 6 + wave_num * 2
		wave_spawn_interval = 1.0
	elif wave_num <= 9:
		wave_enemies_to_spawn = 8 + wave_num * 2
		wave_spawn_interval = 0.8
	elif wave_num > 10:
		wave_enemies_to_spawn = 15 + wave_num
		wave_spawn_interval = max(0.3, 1.0 - wave_num * 0.03)
	else:
		wave_enemies_to_spawn = 5
		wave_spawn_interval = 1.5

	wave_clear = false
	wave_active = true
	wave_spawn_timer = 0.5
	wave_label.text = "第 %d 波" % wave_num

func _spawn_one_enemy():
	var types = ["normal_a", "normal_b", "normal_c"]
	var weights = [0.6, 0.3, 0.1]
	if current_wave >= 4:
		weights = [0.4, 0.35, 0.25]
	elif current_wave >= 6:
		weights = [0.3, 0.4, 0.3]

	var r = randf()
	var cumulative = 0.0
	var chosen = "normal_a"
	for i in range(types.size()):
		cumulative += weights[i]
		if r < cumulative:
			chosen = types[i]
			break

	var sp = SPAWN_POINTS[randi() % SPAWN_POINTS.size()]
	var offset = Vector2(randf_range(-80, 80), randf_range(-80, 80))
	var spawn_pos = sp + offset

	var enemy_node = Node2D.new()
	enemy_node.set_script(load("res://prototypes/core-loop/scripts/enemy.gd"))
	enemy_container.add_child(enemy_node)
	enemy_node.setup_with_player(chosen, spawn_pos, player)

func _spawn_boss():
	boss_spawned = true
	var sp = SPAWN_POINTS[randi() % SPAWN_POINTS.size()]
	var enemy_node = Node2D.new()
	enemy_node.set_script(load("res://prototypes/core-loop/scripts/enemy.gd"))
	enemy_container.add_child(enemy_node)
	enemy_node.setup_with_player("boss", sp, player)

### ---- Enemy death handling ----
func on_enemy_died(position: Vector2, coins: int, xp: int, is_boss: bool):
	player_coins += coins
	add_xp(xp)

### ---- Player-enemy collision ----
func _check_player_enemy_collision():
	if player.invincible_timer <= 0:
		for enemy in enemy_container.get_children():
			if enemy.get("is_dead") == true or not is_instance_valid(enemy):
				continue
			var d = player.global_position.distance_to(enemy.global_position)
			var enemy_radius = enemy.get("body_radius", 14.0)
			if d < (30 + enemy_radius):
				player.invincible_timer = player.INVINCIBLE_DURATION
				var dmg = enemy.get("damage", 10)
				player.take_damage(max(1, int(dmg)))
				spawn_damage_number(player.global_position, dmg, true)
				break

### ---- Tower attacks ----
func _process_tower_attacks():
	if game_over or is_paused:
		return
	for tw in towers:
		if tw.type in ["attack", "control"]:
			tw.attack_timer += 0.1
			if tw.attack_timer >= tw.attack_interval:
				tw.attack_timer = 0.0
				var best = null
				var best_d = tw.range * tw.range
				for e in enemy_container.get_children():
					if e.get("is_dead") == true:
						continue
					var d = tw.tower_pos.distance_squared_to(e.global_position)
					if d < best_d:
						best_d = d
						best = e
				if best:
					var dmg = tw.damage
					var is_slow = (tw.type == "control")
					best.take_damage(dmg, is_slow)
					spawn_damage_number(best.global_position, dmg, false)

### ---- UI building ----
func _build_ui():
	var hud_hbox = HBoxContainer.new()
	hud_hbox.position = Vector2(20, 10)
	hud_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.add_child(hud_hbox)

	var hp_label = Label.new()
	hp_label.text = "❤️"
	hp_label.add_theme_font_size_override("font_size", 14)
	hud_hbox.add_child(hp_label)

	hp_bar = TextureProgressBar.new()
	hp_bar.value = 100
	hp_bar.max_value = 100
	hp_bar.custom_minimum_size = Vector2(150, 16)
	hp_bar.add_theme_color_override("fill_color", Color(1.0, 0.42, 0.62))
	hp_bar.add_theme_color_override("background_color", Color(0.2, 0, 0))
	hud_hbox.add_child(hp_bar)

	var hp_text = Label.new()
	hp_text.text = "100/100"
	hp_text.name = "hp_text"
	hud_hbox.add_child(hp_text)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(40, 0)
	hud_hbox.add_child(spacer)

	var star_label = Label.new()
	star_label.text = "⭐"
	hud_hbox.add_child(star_label)

	xp_bar = TextureProgressBar.new()
	xp_bar.value = 0
	xp_bar.max_value = 10
	xp_bar.custom_minimum_size = Vector2(120, 12)
	xp_bar.add_theme_color_override("fill_color", Color(0.4, 0.48, 0.92))
	xp_bar.add_theme_color_override("background_color", Color(0.1, 0.1, 0.18))
	hud_hbox.add_child(xp_bar)

	hud_hbox.add_child(spacer.duplicate())

	coin_label = Label.new()
	coin_label.text = "💰 0"
	coin_label.add_theme_font_size_override("font_size", 16)
	hud_hbox.add_child(coin_label)

	# Wave label
	wave_label = Label.new()
	wave_label.text = "第 1 波"
	wave_label.add_theme_font_size_override("font_size", 20)
	wave_label.position = Vector2(580, 10)
	ui.add_child(wave_label)

	# Tower slot indicators
	var tower_hbox = HBoxContainer.new()
	tower_hbox.position = Vector2(1000, 10)
	ui.add_child(tower_hbox)
	for i in range(TOWER_SLOTS.size()):
		var slot_lbl = Label.new()
		slot_lbl.text = "空槽%d" % i
		slot_lbl.name = "slot_ind_%d" % i
		slot_lbl.add_theme_font_size_override("font_size", 14)
		tower_hbox.add_child(slot_lbl)

	### Tower select panel
	tower_select_panel = PanelContainer.new()
	tower_select_panel.position = Vector2(340, 200)
	tower_select_panel.custom_minimum_size = Vector2(600, 250)
	tower_select_panel.visible = false
	ui.add_child(tower_select_panel)

	var tc_vbox = VBoxContainer.new()
	tc_vbox.position = Vector2(10, 10)
	tower_select_panel.add_child(tc_vbox)

	var tc_title = Label.new()
	tc_title.text = "选择防御塔"
	tc_title.add_theme_font_size_override("font_size", 20)
	tc_vbox.add_child(tc_title)

	var tc_hbox = HBoxContainer.new()
	tc_vbox.add_child(tc_hbox)

	for tower_key in TOWER_DATA:
		var tdata = TOWER_DATA[tower_key]
		var btn = Button.new()
		btn.text = "%s\n伤害:%d 射程:%.0f\n💰%d金币" % [tdata.name, tdata.get("damage", 0), tdata.range, tdata.cost]
		btn.custom_minimum_size = Vector2(180, 90)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_tower_select.bind(tower_key))
		btn.name = "tower_btn_%s" % tower_key
		tc_hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_on_tower_select_cancel)
	tc_vbox.add_child(cancel_btn)

	### Upgrade panel
	upgrade_panel = PanelContainer.new()
	upgrade_panel.position = Vector2(290, 150)
	upgrade_panel.custom_minimum_size = Vector2(700, 350)
	upgrade_panel.visible = false
	ui.add_child(upgrade_panel)

func _setup_tower_slots():
	for i in range(TOWER_SLOTS.size()):
		var marker = Marker2D.new()
		marker.position = TOWER_SLOTS[i]
		marker.name = "TowerSlot_%d" % i
		add_child(marker)
		# visual indicator on map
		var dot = ColorRect.new()
		dot.size = Vector2(16, 16)
		dot.color = Color(0.3, 0.3, 0.4, 0.5)
		dot.position = Vector2(-8, -8)
		dot.name = "SlotVisual_%d" % i
		marker.add_child(dot)

func update_hud():
	if hp_bar == null:
		return
	hp_bar.value = player_hp
	hp_bar.max_value = player_max_hp
	var hp_text = ui.find_children("hp_text", "Label", true)
	if hp_text.size() > 0:
		hp_text[0].text = "%d/%d" % [player_hp, player_max_hp]

	xp_bar.value = player_xp
	xp_bar.max_value = player_xp_needed

	if coin_label:
		coin_label.text = "💰 %d" % player_coins

	for i in range(TOWER_SLOTS.size()):
		var ind = ui.find_children("slot_ind_%d" % i, "Label", true)
		if ind.size() > 0:
			if slot_occupied[i]:
				ind[0].text = "🗼S%d" % i
				ind[0].add_theme_color_override("font_color", Color(1, 0.85, 0))
			else:
				ind[0].text = "空槽%d" % i

func update_hp_bar():
	update_hud()

### ---- Damage numbers ----
func spawn_damage_number(world_pos: Vector2, value: int, is_player_dmg: bool):
	var label = Label.new()
	if is_player_dmg:
		label.text = "-%d" % value
		label.add_theme_color_override("font_color", Color(1, 0, 0))
	else:
		label.text = str(value)
		label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	label.add_theme_font_size_override("font_size", 16)
	label.position = world_pos + Vector2(randf_range(-20, 20), -30)
	label.z_index = 100
	ui.add_child(label)
	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 50, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(label.queue_free)

func spawn_death_effect(world_pos: Vector2):
	for i in range(4):
		var p = ColorRect.new()
		p.size = Vector2(6, 6)
		p.color = Color(1, 0.5, 0.3)
		p.position = world_pos + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		ui.add_child(p)
		var tween = create_tween()
		tween.tween_property(p, "position:y", p.position.y - 30, 0.5)
		tween.tween_property(p, "modulate:a", 0.0, 0.2)
		tween.tween_callback(p.queue_free)

### ---- Tower placement input ----
func _unhandled_input(event: InputEvent):
	if game_over or is_paused:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if tower_select_panel.visible or upgrade_panel.visible:
			return
		var click_pos: Vector2 = event.position
		for i in range(TOWER_SLOTS.size()):
			var slot_screen_pos = TOWER_SLOTS[i]
			if click_pos.distance_to(slot_screen_pos) < 30:
				if not slot_occupied[i]:
					selecting_slot = i
					_show_tower_select_panel()
				return

func _show_tower_select_panel():
	for tower_key in TOWER_DATA:
		var tdata = TOWER_DATA[tower_key]
		var btn = tower_select_panel.find_children("tower_btn_%s" % tower_key, "Button", true)
		if btn.size() > 0:
			btn[0].disabled = player_coins < tdata.cost
	tower_select_panel.visible = true

func _on_tower_select(tower_type: String):
	var tdata = TOWER_DATA[tower_type]
	if player_coins < tdata.cost:
		return
	player_coins -= tdata.cost
	slot_occupied[selecting_slot] = true

	var tw_data = tdata.duplicate()
	tw_data.slot_index = selecting_slot
	tw_data.tower_type = tower_type
	tw_data.tower_pos = TOWER_SLOTS[selecting_slot]
	tw_data.attack_timer = 0.0
	towers.append(tw_data)

	var tw_marker = Marker2D.new()
	tw_marker.position = TOWER_SLOTS[selecting_slot]
	tw_marker.name = "PlacedTower_%d" % selecting_slot
	add_child(tw_marker)
	tw_marker.add_child(_make_tower_visual(tower_type))

	selecting_slot = -1
	tower_select_panel.visible = false
	update_hud()

func _make_tower_visual(tower_type: String) -> Node2D:
	var n = Node2D.new()
	var c = ColorRect.new()
	var colors = {"fish_shooter": Color(1, 0.7, 0.3), "yarn_launcher": Color(0.6, 0.4, 1.0), "catnip_aura": Color(0.3, 1.0, 0.3)}
	c.size = Vector2(24, 24)
	c.color = colors.get(tower_type, Color.WHITE)
	c.position = Vector2(-12, -12)
	n.add_child(c)
	var l = Label.new()
	var emojis = {"fish_shooter": "🐟", "yarn_launcher": "🧶", "catnip_aura": "🌿"}
	l.text = emojis.get(tower_type, "?")
	l.position = Vector2(-8, -16)
	l.add_theme_font_size_override("font_size", 16)
	n.add_child(l)

	# aura range visualization
	if tower_type == "catnip_aura":
		var ring = Line2D.new()
		ring.width = 2
		ring.default_color = Color(0.3, 1.0, 0.3, 0.3)
		var pts = 32
		var r = TOWER_DATA["catnip_aura"].range
		for i in range(pts + 1):
			var angle = (i / float(pts)) * TAU
			ring.add_point(Vector2(cos(angle) * r, sin(angle) * r))
		n.add_child(ring)

	return n

func _on_tower_select_cancel():
	selecting_slot = -1
	tower_select_panel.visible = false

### ---- Upgrade panel ----
func _show_upgrade_panel():
	upgrade_panel.visible = true

	var options = UPGRADE_POOL.duplicate()
	options.shuffle()
	options = options.slice(0, 3)

	for c in upgrade_panel.get_children():
		c.queue_free()

	var vbox = VBoxContainer.new()
	upgrade_panel.add_child(vbox)

	var title = Label.new()
	title.text = "🎉 LEVEL UP! 选择一个升级"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	for opt in options:
		var btn = Button.new()
		btn.text = "%s\n%s" % [opt.icon, opt.name]
		btn.custom_minimum_size = Vector2(200, 100)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_select_upgrade.bind(opt.apply))
		hbox.add_child(btn)

func _select_upgrade(apply_fn: String):
	match apply_fn:
		"apply_dmg_up":
			player_damage += 5
		"apply_aspd_up":
			player_attack_speed *= 0.8
			player.attack_cooldown = player_attack_speed
		"apply_range_up":
			player_range += 30
			player.attack_range = player_range
		"apply_hp_up":
			player_max_hp += 20
			player_hp = min(player_hp + 20, player_max_hp)
		"apply_speed_up":
			player_speed *= 1.15
			player.speed = player_speed
		"apply_tower_dmg":
			for tw in towers:
				if tw.has("damage"):
					tw.damage += 3

	upgrade_panel.visible = false
	is_paused = false
	get_tree().paused = false

### ---- Game over overlay ----
var game_over_label: Label

func _show_game_over():
	if game_over_label:
		return
	get_tree().paused = true

	game_over_label = Label.new()
	game_over_label.text = "💔 猫咪倒下了... 按 R 重新开始"
	game_over_label.add_theme_font_size_override("font_size", 24)
	game_over_label.position = Vector2(390, 340)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(game_over_label)

	# stats
	var stats = Label.new()
	stats.text = "第 %d 波 | Lv.%d | 💰%d | 击杀: 统计中..." % [current_wave, player_level, player_coins]
	stats.add_theme_font_size_override("font_size", 16)
	stats.position = Vector2(440, 380)
	ui.add_child(stats)

func _unhandled_input(event: InputEvent):
	# also check restart
	if game_over and event is InputEventKey and event.keycode == KEY_R and event.pressed:
		get_tree().reload_current_scene()
