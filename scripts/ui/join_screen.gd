extends Control

@onready var title_label: Label = $Title
@onready var p1_label: Label = $P1Status
@onready var p2_label: Label = $P2Status
@onready var credits_label: Label = $CreditsLabel
@onready var instruction_label: Label = $Instruction

var _p1_joined: bool = false
var _p2_joined: bool = false

func _ready() -> void:
	_update_labels()

func _process(_delta: float) -> void:
	# P1 join/start
	if Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p1_shoot2"):
		if not _p1_joined:
			if GameManager.join_player(0):
				_p1_joined = true
				_update_labels()
		else:
			_start_game()

	# P2 join/start
	if Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("p2_shoot2"):
		if not _p2_joined:
			if GameManager.join_player(1):
				_p2_joined = true
				_update_labels()
		else:
			_start_game()

func _update_labels() -> void:
	if credits_label:
		credits_label.text = "Credits: %d" % GameManager.credits

	var p1_key := InputSettings.get_key_name("p1_shoot")
	var p2_key := InputSettings.get_key_name("p2_shoot")

	if p1_label:
		if _p1_joined:
			p1_label.text = "P1: READY!"
			p1_label.modulate = Color(0.3, 1.0, 0.3)
		elif GameManager.credits > 0:
			p1_label.text = "P1: press %s" % p1_key
			p1_label.modulate = Color.WHITE
		else:
			p1_label.text = "P1: No credits"
			p1_label.modulate = Color(0.5, 0.5, 0.5)

	if p2_label:
		if _p2_joined:
			p2_label.text = "P2: READY!"
			p2_label.modulate = Color(0.3, 1.0, 0.3)
		elif GameManager.credits > 0:
			p2_label.text = "P2: press %s" % p2_key
			p2_label.modulate = Color.WHITE
		else:
			p2_label.text = "P2: No credits"
			p2_label.modulate = Color(0.5, 0.5, 0.5)

	if instruction_label:
		if _p1_joined or _p2_joined:
			instruction_label.text = "Fire again to start"
			instruction_label.visible = true
		else:
			instruction_label.visible = false

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/stage_intro.tscn")
