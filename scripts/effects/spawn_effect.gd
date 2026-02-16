extends Node2D

var _timer: float = 0.0
const DURATION: float = 1.0

signal spawn_complete

func _ready() -> void:
	z_index = 20

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= DURATION:
		spawn_complete.emit()
		queue_free()
	queue_redraw()

func _draw() -> void:
	var t := _timer / DURATION
	# Star/sparkle effect that shrinks
	var size := 20.0 * (1.0 - t)
	var color := Color(1.0, 1.0, 1.0, 1.0 - t)

	# Draw a 4-pointed star
	var points: PackedVector2Array = []
	for i in range(8):
		var angle := i * PI / 4
		var r := size if i % 2 == 0 else size * 0.3
		points.append(Vector2(cos(angle), sin(angle)) * r)
	if points.size() >= 3:
		draw_colored_polygon(points, color)
