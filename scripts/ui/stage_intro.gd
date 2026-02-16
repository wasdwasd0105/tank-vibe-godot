extends Control

@onready var stage_label: Label = $StageLabel
var _timer: float = 0.0

func _ready() -> void:
	if stage_label:
		stage_label.text = "STAGE " + str(GameManager.current_stage)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 2.0:
		get_tree().change_scene_to_file("res://scenes/game.tscn")
