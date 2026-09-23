class_name HitEffect
extends Sprite2D
## A theme's bullet-hit animation (ThemeManager.get_hit_frames): plays its
## frames once, centred where the shot died, then frees itself.

var _frames: Array = []
var _frame_time: float = 0.025
var _time: float = 0.0


static func spawn(parent: Node, at: Vector2, frames: Array, duration: float) -> HitEffect:
	var fx := HitEffect.new()
	fx._frames = frames
	fx._frame_time = duration / frames.size()
	fx.texture = frames[0]
	fx.z_index = 20  # over tanks and terrain, like the built-in flash
	parent.add_child(fx)
	fx.global_position = at
	return fx


func _process(delta: float) -> void:
	_time += delta
	var frame := int(_time / _frame_time)
	if frame >= _frames.size():
		queue_free()
		return
	texture = _frames[frame]
