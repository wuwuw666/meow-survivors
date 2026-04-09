class_name CombatFeedbackManager
extends Node

var _damage_container: Node2D
var _effect_container: Node2D
var _camera: Camera2D
var _player: Node2D

var _shake_intensity: float = 0.0
var _shake_decay: float = 8.0
var _hit_flash_timer: float = 0.0
var _last_reported_player_hp: int = -1

func bind_refs(player: Node2D, damage_container: Node2D, effect_container: Node2D, camera: Camera2D) -> void:
	_player = player
	_damage_container = damage_container
	_effect_container = effect_container
	_camera = camera

func notify_player_hp_changed(current: int) -> void:
	if _last_reported_player_hp >= 0 and current < _last_reported_player_hp:
		_hit_flash_timer = 0.12
		add_screen_shake(5.0)
	_last_reported_player_hp = current

func show_damage_number(world_pos: Vector2, value: int, is_crit: bool) -> void:
	if _damage_container == null:
		return
	var lbl := Label.new()
	lbl.text = str(value)
	if is_crit:
		lbl.add_theme_color_override("font_color", Color(1, 1, 0))
		lbl.add_theme_font_size_override("font_size", 24)
		add_screen_shake(4.0)
	else:
		lbl.add_theme_color_override("font_color", Color(1, 0.25, 0.25))
		lbl.add_theme_font_size_override("font_size", 15)
	lbl.position = world_pos + Vector2(randf_range(-12, 12), -22)
	_damage_container.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 50, 0.7).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tween.tween_callback(lbl.queue_free)

func show_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	if _damage_container == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.position = world_pos + Vector2(randf_range(-8, 8), -16)
	_damage_container.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 36, 0.8).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.3).set_delay(0.5)
	tween.tween_callback(lbl.queue_free)

func add_screen_shake(intensity: float) -> void:
	_shake_intensity = max(_shake_intensity, intensity)

func update(delta: float) -> void:
	_update_screen_shake(delta)
	_update_hit_flash(delta)

func spawn_death_particles(pos: Vector2, size: float) -> void:
	if _effect_container == null:
		return
	var count: int = clampi(int(size / 3.0), 4, 16)
	var base_color: Color = Color(1, 0.25, 0.2)
	for i in range(count):
		var particle := ColorRect.new()
		var psize: float = randf_range(3.0, size * 0.4)
		particle.size = Vector2(psize, psize)
		particle.color = base_color.lightened(randf_range(0.0, 0.4))
		particle.position = pos + Vector2(randf_range(-size, size), randf_range(-size, size))
		particle.rotation = randf() * TAU
		_effect_container.add_child(particle)

		var angle: float = randf() * TAU
		var speed: float = randf_range(60.0, 180.0)
		var lifetime: float = randf_range(0.3, 0.7)
		var tw := create_tween()
		tw.tween_property(particle, "position", particle.position + Vector2(cos(angle), sin(angle)) * speed * lifetime, lifetime)
		tw.parallel().tween_property(particle, "rotation", particle.rotation + randf_range(-TAU, TAU), lifetime)
		tw.parallel().tween_property(particle, "modulate:a", 0.0, lifetime * 0.7).set_delay(lifetime * 0.3)
		tw.tween_callback(particle.queue_free)

func spawn_place_effect(pos: Vector2, color: Color) -> void:
	if _effect_container == null:
		return
	var ring := ColorRect.new()
	ring.size = Vector2(4, 4)
	ring.color = color
	ring.position = pos - Vector2(2, 2)
	_effect_container.add_child(ring)

	var tw := create_tween()
	tw.tween_property(ring, "size", Vector2(48, 48), 0.35).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "position", pos - Vector2(24, 24), 0.35).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	tw.tween_callback(ring.queue_free)

func _update_screen_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_intensity <= 0.01:
		return
	var shake_offset := Vector2(
		randf_range(-1.0, 1.0) * _shake_intensity,
		randf_range(-1.0, 1.0) * _shake_intensity
	)
	_camera.offset = shake_offset
	_camera.offset = lerp(_camera.offset, Vector2.ZERO, 0.3)
	_shake_intensity *= exp(-_shake_decay * delta)
	if _shake_intensity < 0.1:
		_shake_intensity = 0.0
		_camera.offset = Vector2.ZERO

func _update_hit_flash(delta: float) -> void:
	if _player == null:
		return
	var sprite: CanvasItem = _player.get_node_or_null("Sprite") as CanvasItem
	if sprite == null:
		return
	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		var flash: float = _hit_flash_timer / 0.12
		sprite.modulate = Color(1, 1 - flash * 0.6, 1 - flash * 0.6, 1)
	else:
		sprite.modulate = Color.WHITE
