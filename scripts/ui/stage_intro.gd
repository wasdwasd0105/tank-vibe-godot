extends Control

@onready var stage_label: Label = $StageLabel
@onready var caption_label: Label = $CaptionLabel

const FADE_IN_TIME: float = 0.5
const HOLD_TIME: float = 1.0
const SLIDE_OUT_TIME: float = 0.6
const TOTAL_TIME: float = FADE_IN_TIME + HOLD_TIME + SLIDE_OUT_TIME  # 2.1s

# Caption appears slightly after stage label
const CAPTION_DELAY: float = 0.15

# How far labels slide off screen (pixels)
const SLIDE_DISTANCE: float = 400.0

var _timer: float = 0.0
var _stage_label_orig_y: float = 0.0
var _caption_label_orig_y: float = 0.0

func _ready() -> void:
	if stage_label:
		stage_label.text = "STAGE " + str(GameManager.current_stage)
		stage_label.modulate.a = 0.0
		_stage_label_orig_y = stage_label.position.y
	if caption_label:
		var caption := LevelData.get_stage_caption(GameManager.current_stage)
		if caption.is_empty():
			caption_label.visible = false
		else:
			caption_label.text = caption
			caption_label.visible = true
			caption_label.modulate.a = 0.0
			_caption_label_orig_y = caption_label.position.y

func _process(delta: float) -> void:
	_timer += delta

	# Stage label animation
	if stage_label:
		var alpha := _calc_alpha(_timer, 0.0)
		var offset := _calc_slide_offset(_timer, 0.0, -1.0)  # slides up
		stage_label.modulate.a = alpha
		stage_label.position.y = _stage_label_orig_y + offset

	# Caption label animation (delayed start)
	if caption_label and caption_label.visible:
		var alpha := _calc_alpha(_timer, CAPTION_DELAY)
		var offset := _calc_slide_offset(_timer, CAPTION_DELAY, 1.0)  # slides down
		caption_label.modulate.a = alpha
		caption_label.position.y = _caption_label_orig_y + offset

	if _timer >= TOTAL_TIME:
		get_tree().change_scene_to_file("res://scenes/game.tscn")

func _calc_alpha(time: float, delay: float) -> float:
	var t := time - delay
	if t < 0.0:
		return 0.0
	elif t < FADE_IN_TIME:
		# Fade in
		return t / FADE_IN_TIME
	elif t < FADE_IN_TIME + HOLD_TIME:
		# Hold fully visible
		return 1.0
	elif t < FADE_IN_TIME + HOLD_TIME + SLIDE_OUT_TIME:
		# Fade out during slide
		var slide_t := t - FADE_IN_TIME - HOLD_TIME
		var progress := slide_t / SLIDE_OUT_TIME
		# Ease out: fade faster at the end
		return 1.0 - progress * progress
	return 0.0

func _calc_slide_offset(time: float, delay: float, direction: float) -> float:
	var t := time - delay
	if t < FADE_IN_TIME + HOLD_TIME:
		# No movement during fade-in and hold
		return 0.0
	elif t < FADE_IN_TIME + HOLD_TIME + SLIDE_OUT_TIME:
		# Slide out with ease-in (accelerating)
		var slide_t := t - FADE_IN_TIME - HOLD_TIME
		var progress := slide_t / SLIDE_OUT_TIME
		# Ease-in curve: starts slow, accelerates
		var eased := progress * progress
		return direction * SLIDE_DISTANCE * eased
	return direction * SLIDE_DISTANCE
