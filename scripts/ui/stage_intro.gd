extends Control

@onready var stage_label: Label = $StageLabel
@onready var caption_label: Label = $CaptionLabel
var _timer: float = 0.0

func _ready() -> void:
	if stage_label:
		stage_label.text = "STAGE " + str(GameManager.current_stage)
	if caption_label:
		var caption := LevelData.get_stage_caption(GameManager.current_stage)
		if caption.is_empty():
			caption_label.visible = false
		else:
			caption_label.text = caption
			caption_label.visible = true

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 2.0:
		get_tree().change_scene_to_file("res://scenes/game.tscn")
