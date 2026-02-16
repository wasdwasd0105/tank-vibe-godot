extends Node

## Global window manager — handles fullscreen toggle and window scaling.
## Press F11 or F to toggle fullscreen from any screen.

func _ready() -> void:
	# Start maximized so the game fills the screen
	get_window().mode = Window.MODE_MAXIMIZED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()

func _toggle_fullscreen() -> void:
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = Window.MODE_MAXIMIZED
	else:
		window.mode = Window.MODE_FULLSCREEN
