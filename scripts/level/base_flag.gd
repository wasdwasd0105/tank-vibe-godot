class_name BaseFlag
extends StaticBody2D
## The base the players defend. Shows the theme's animated flag strip when the
## theme provides one (healthy, dead and invincible rows); otherwise the default
## eagle sprite, tinted red once destroyed.

const FRAME_TIME := 0.12  # eight frames make roughly one loop per second

@onready var _sprite: Sprite2D = $Sprite2D

var destroyed := false:
	set(value):
		destroyed = value
		_refresh()
var invincible := false:
	set(value):
		invincible = value
		_refresh()

var _default_texture: Texture2D
var _frames: Array = []  # frames of the strip currently shown; empty = default eagle
var _frame := 0
var _time := 0.0


func _ready() -> void:
	_default_texture = _sprite.texture
	ThemeManager.theme_changed.connect(func(_theme_name: String) -> void: _refresh())
	_refresh()


func _process(delta: float) -> void:
	if _frames.is_empty():
		return
	_time += delta
	if _time >= FRAME_TIME:
		_time = fmod(_time, FRAME_TIME)
		_frame = (_frame + 1) % _frames.size()
		_sprite.texture = _frames[_frame]


## "dead", "invincible" or "healthy": the strip row in use.
func state_name() -> String:
	if destroyed:
		return "dead"
	if invincible:
		return "invincible"
	return "healthy"


func _refresh() -> void:
	if _sprite == null:
		return
	_frames = ThemeManager.get_flag_frames(state_name())
	if _frames.is_empty():
		_sprite.texture = _default_texture
		_sprite.modulate = Color.RED if destroyed else Color.WHITE
		return
	_sprite.modulate = Color.WHITE
	_frame = mini(_frame, _frames.size() - 1)
	_sprite.texture = _frames[_frame]
