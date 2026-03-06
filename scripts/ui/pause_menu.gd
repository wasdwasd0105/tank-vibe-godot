extends Control

## Pause menu overlay shown when ESC is pressed during gameplay.
## process_mode is set to WHEN_PAUSED so input works while tree is paused.

signal resume_requested
signal restart_requested
signal main_menu_requested
signal exit_requested

@onready var cursor: Label = $PauseCursor
@onready var opt_resume: Label = $OptResume
@onready var opt_restart: Label = $OptRestart
@onready var opt_main_menu: Label = $OptMainMenu
@onready var opt_exit: Label = $OptExit

var _selected: int = 0
var _options: Array[Label] = []
var _can_open: bool = true  # Disabled during game over / stage clear

func _ready() -> void:
	_options = [opt_resume, opt_restart, opt_main_menu, opt_exit]
	visible = false
	_update_cursor()

func set_can_open(value: bool) -> void:
	_can_open = value

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not visible:
			if _can_open:
				_open()
		else:
			_close_and_resume()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible:
		return

	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		_selected = maxi(_selected - 1, 0)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		_selected = mini(_selected + 1, _options.size() - 1)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
		_select_option()

func _open() -> void:
	_selected = 0
	_update_cursor()
	visible = true
	get_tree().paused = true

func _close_and_resume() -> void:
	visible = false
	get_tree().paused = false

func _update_cursor() -> void:
	if cursor and _selected < _options.size():
		cursor.position.y = _options[_selected].position.y

func _select_option() -> void:
	match _selected:
		0:  # RESUME
			_close_and_resume()
			resume_requested.emit()
		1:  # RESTART STAGE
			visible = false
			get_tree().paused = false
			restart_requested.emit()
		2:  # MAIN MENU
			visible = false
			get_tree().paused = false
			main_menu_requested.emit()
		3:  # EXIT
			exit_requested.emit()
