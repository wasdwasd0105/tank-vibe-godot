extends Node2D

var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer += delta
	queue_redraw()

func _draw() -> void:
	# Flashing shield circle around the tank
	var alpha := 0.5 + 0.3 * sin(_timer * 10.0)
	var color := Color(0.5, 0.5, 1.0, alpha)
	draw_arc(Vector2.ZERO, 36, 0, TAU, 32, color, 2.0)
	draw_arc(Vector2.ZERO, 34, 0, TAU, 32, Color(1.0, 1.0, 1.0, alpha * 0.5), 1.0)
