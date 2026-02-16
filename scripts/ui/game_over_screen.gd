extends Control

var _timer: float = 0.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer > 3.0:
		if Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
			get_tree().change_scene_to_file("res://scenes/main.tscn")
	if _timer > 10.0:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
