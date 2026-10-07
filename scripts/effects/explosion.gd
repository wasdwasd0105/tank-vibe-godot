extends Node2D

var _timer: float = 0.0
const DURATION: float = 0.4
var _frame: int = 0

func _ready() -> void:
	# Over the tanks and walls, under the grass, as HitEffect (the original's
	# shell, tank and base turned into their hit and explosion pictures under
	# its wall layer). Not named here: this scene loads inside the bullet's,
	# and naming another class from it pulls the tanks' scripts into that load,
	# emptying their bullet scene.
	z_index = 0

func _process(delta: float) -> void:
	_timer += delta
	_frame = int(_timer / DURATION * 4)

	# Scale animation
	var t := _timer / DURATION
	if t < 0.3:
		scale = Vector2(1, 1) * (t / 0.3) * 1.5
	elif t < 0.7:
		scale = Vector2(1.5, 1.5)
	else:
		scale = Vector2(1, 1) * (1.0 - (t - 0.7) / 0.3) * 1.5

	if _timer >= DURATION:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var t := _timer / DURATION
	var radius := 16.0
	var color := Color(1.0, 0.7, 0.0, 1.0 - t)  # Orange fading out
	draw_circle(Vector2.ZERO, radius, color)
	# Inner bright core
	var inner_color := Color(1.0, 1.0, 0.5, 1.0 - t)
	draw_circle(Vector2.ZERO, radius * 0.5, inner_color)
