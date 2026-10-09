extends Node

## Global window manager — handles fullscreen toggle and window scaling.
## Press F11 or F to toggle fullscreen from any screen; the pause menu has a
## FULLSCREEN option and its settings a FULLSCREEN row.
##
## ALWAYS FULLSCREEN is for play only (Sean): the menus stay in the window, a
## stage entered from them goes fullscreen, and the menus get the window back.

signal fullscreen_changed(on: bool)

## Between entering a stage from the menus and the next menu screen.
var _in_game := false
## ALWAYS FULLSCREEN took the window fullscreen, so the menus give it back.
var _made_fullscreen := false

func _ready() -> void:
	apply_start_mode()

## How the game opens: maximized so it fills the screen, whatever ALWAYS
## FULLSCREEN says (the menus stay in the window).
func apply_start_mode() -> void:
	get_window().mode = Window.MODE_MAXIMIZED

## A stage has started (game.gd). From the menus, ALWAYS FULLSCREEN takes the
## window fullscreen; the next stage, or the same one restarted, leaves it be.
func enter_game() -> void:
	if _in_game:
		return
	_in_game = true
	if InputSettings.get_always_fullscreen() and not is_fullscreen():
		_made_fullscreen = true
		set_fullscreen(true)

## A menu screen is up (title, load, join): the window ALWAYS FULLSCREEN took is
## given back. Fullscreen switched on by the player stays.
func leave_game() -> void:
	_in_game = false
	if _made_fullscreen:
		_made_fullscreen = false
		set_fullscreen(false)

## ALWAYS FULLSCREEN on or off, kept in the settings. In a stage it applies at
## once; in the menus it waits for the next stage.
func set_always_fullscreen(on: bool) -> void:
	InputSettings.save_always_fullscreen(on)
	if not _in_game:
		return
	if on and not is_fullscreen():
		_made_fullscreen = true
		set_fullscreen(true)
	elif not on and _made_fullscreen:
		_made_fullscreen = false
		set_fullscreen(false)

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
