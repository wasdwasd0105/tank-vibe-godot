extends Control

var _selected: int = 0  # 0 = 1 player, 1 = 2 players, 2 = theme
@onready var cursor: Label = $Cursor
@onready var option_1p: Label = $Option1P
@onready var option_2p: Label = $Option2P
@onready var option_theme: Label = $OptionTheme

var _available_themes: Array[String] = []
var _theme_index: int = 0

func _ready() -> void:
	_available_themes = ThemeManager.get_available_themes()
	# Find the current theme index
	for i in range(_available_themes.size()):
		if _available_themes[i] == ThemeManager.current_theme:
			_theme_index = i
			break
	_update_theme_label()
	_update_cursor()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		_selected = maxi(_selected - 1, 0)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		_selected = mini(_selected + 1, 2)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_left") or Input.is_action_just_pressed("p2_left"):
		if _selected == 2:
			_cycle_theme(-1)
	elif Input.is_action_just_pressed("p1_right") or Input.is_action_just_pressed("p2_right"):
		if _selected == 2:
			_cycle_theme(1)
	elif Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
		if _selected == 2:
			_cycle_theme(1)
		else:
			_start_game()

func _update_cursor() -> void:
	if not cursor:
		return
	match _selected:
		0:
			cursor.position.y = option_1p.position.y
		1:
			cursor.position.y = option_2p.position.y
		2:
			cursor.position.y = option_theme.position.y

func _cycle_theme(direction: int) -> void:
	if _available_themes.is_empty():
		return
	_theme_index = (_theme_index + direction) % _available_themes.size()
	if _theme_index < 0:
		_theme_index += _available_themes.size()
	ThemeManager.load_theme(_available_themes[_theme_index])
	_update_theme_label()

func _update_theme_label() -> void:
	if option_theme:
		option_theme.text = "THEME: %s" % ThemeManager.get_theme_display_name()

func _start_game() -> void:
	GameManager.start_game(_selected == 1)
