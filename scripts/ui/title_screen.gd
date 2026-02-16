extends Control

var _selected: int = 0  # 0 = 1 player, 1 = 2 players
@onready var cursor: Label = $Cursor
@onready var option_1p: Label = $Option1P
@onready var option_2p: Label = $Option2P

func _ready() -> void:
	_update_cursor()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		_selected = 0
		_update_cursor()
	elif Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		_selected = 1
		_update_cursor()
	elif Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
		_start_game()

func _update_cursor() -> void:
	if cursor and option_1p and option_2p:
		if _selected == 0:
			cursor.position.y = option_1p.position.y
		else:
			cursor.position.y = option_2p.position.y

func _start_game() -> void:
	GameManager.start_game(_selected == 1)
