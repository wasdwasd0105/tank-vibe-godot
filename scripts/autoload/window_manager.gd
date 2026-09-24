extends Node

## Global window manager — handles fullscreen toggle and window scaling.
## Press F11 or F to toggle fullscreen from any screen; the pause menu's
## settings have a FULLSCREEN row too.

signal fullscreen_changed(on: bool)

func _ready() -> void:
	# Start maximized so the game fills the screen
	get_window().mode = Window.MODE_MAXIMIZED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()

func is_fullscreen() -> bool:
	var mode := get_window().mode
	return mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN

## Fullscreen, or back to a maximized window.
func set_fullscreen(on: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_MAXIMIZED
	fullscreen_changed.emit(on)

func _toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())
