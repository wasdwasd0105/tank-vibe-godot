class_name ToggleSwitch
extends Control
## An on / off switch: a rounded track with a knob, which slides right and
## lights the track gold when on, and back left, grey, when off. It only shows
## the state: the row it sits in takes the focus, the clicks and the keys
## (MenuRows.make_switch_row).

const SWITCH_SIZE := Vector2(52, 28)
const KNOB_INSET := 4.0
const SLIDE_TIME := 0.12
const TRACK_OFF := Color(0.11, 0.12, 0.15)
const TRACK_ON := Color(0.86, 0.64, 0.15)
const BORDER_OFF := Color(0.36, 0.37, 0.43)
const BORDER_ON := Color(1.0, 0.86, 0.42)
const KNOB_OFF := Color(0.58, 0.59, 0.64)
const KNOB_ON := Color(1.0, 0.97, 0.88)
const KNOB_SHADOW := Color(0, 0, 0, 0.35)

## On (the knob right, the track lit) or off. Shown at once while the switch is
## out of sight; slid to while it shows.
var on: bool = false:
	set(value):
		if value != on:
			on = value
			_slide()

var _knob := 0.0   # where the knob is: 0 off (left) ... 1 on (right)
var _slider: Tween
var _track := StyleBoxFlat.new()


func _init() -> void:
	custom_minimum_size = SWITCH_SIZE
	mouse_filter = MOUSE_FILTER_IGNORE
	size_flags_vertical = SIZE_SHRINK_CENTER
	_track.set_corner_radius_all(int(SWITCH_SIZE.y / 2))
	_track.set_border_width_all(2)
	_track.anti_aliasing = true


## Where the knob is drawn: 0 off ... 1 on (it's 1 or 0 once a slide is over).
func knob() -> float:
	return _knob


func _slide() -> void:
	if _slider:
		_slider.kill()
	var to := 1.0 if on else 0.0
	if not is_visible_in_tree():
		_set_knob(to)
		return
	_slider = create_tween()
	_slider.tween_method(_set_knob, _knob, to, SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_knob(value: float) -> void:
	_knob = value
	queue_redraw()


func _draw() -> void:
	var box := Rect2(((size - SWITCH_SIZE) / 2).round(), SWITCH_SIZE)
	_track.bg_color = TRACK_OFF.lerp(TRACK_ON, _knob)
	_track.border_color = BORDER_OFF.lerp(BORDER_ON, _knob)
	draw_style_box(_track, box)
	var radius := box.size.y / 2 - KNOB_INSET
	var left := box.position.x + KNOB_INSET + radius
	var right := box.end.x - KNOB_INSET - radius
	var centre := Vector2(lerpf(left, right, _knob), box.get_center().y)
	draw_circle(centre + Vector2(0, 1.5), radius + 0.5, KNOB_SHADOW, true, -1.0, true)
	draw_circle(centre, radius, KNOB_OFF.lerp(KNOB_ON, _knob), true, -1.0, true)
