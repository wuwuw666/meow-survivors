class_name ArtFeedbackManager
extends Node

var _effect_container: Node2D = null

func bind_effect_container(effect_container: Node2D) -> void:
	_effect_container = effect_container

func show_place_flash(world_pos: Vector2, color: Color = Color(1.0, 0.82, 0.36)) -> void:
	_spawn_ring(world_pos, 26.0, color, 0.28)

func show_pickup_sparkle(world_pos: Vector2, color: Color) -> void:
	_spawn_dot(world_pos, color, 0.35)

func show_enemy_pop(world_pos: Vector2, color: Color, scale_multiplier: float = 1.0) -> void:
	_spawn_ring(world_pos, 18.0 * scale_multiplier, color, 0.22)
	_spawn_dot(world_pos + Vector2(0, -8.0 * scale_multiplier), color.lightened(0.25), 0.26)

func show_boss_warning(world_pos: Vector2) -> void:
	_spawn_ring(world_pos, 58.0, Color(1.0, 0.45, 0.28), 0.55)

func _spawn_ring(world_pos: Vector2, radius: float, color: Color, duration: float) -> void:
	if _effect_container == null:
		return
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = color
	ring.closed = true
	ring.position = world_pos
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		ring.add_point(Vector2(cos(angle), sin(angle)) * radius)
	_effect_container.add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector2(1.45, 1.45), duration)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	tween.finished.connect(ring.queue_free)

func _spawn_dot(world_pos: Vector2, color: Color, duration: float) -> void:
	if _effect_container == null:
		return
	var dot := ColorRect.new()
	dot.size = Vector2(10, 10)
	dot.pivot_offset = dot.size * 0.5
	dot.position = world_pos - dot.pivot_offset
	dot.color = color
	_effect_container.add_child(dot)
	var tween := dot.create_tween()
	tween.tween_property(dot, "position:y", dot.position.y - 18.0, duration)
	tween.parallel().tween_property(dot, "modulate:a", 0.0, duration)
	tween.finished.connect(dot.queue_free)
