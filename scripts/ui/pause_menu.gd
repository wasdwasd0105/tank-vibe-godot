extends Control
## The pause screen, in the menus' style: RESUME, RESTART STAGE, MAIN MENU,
## SETTINGS and QUIT GAME over the dimmed stage. SETTINGS changes the sound,
## vibration, fullscreen and each player's controls (the same controls page as
## the title screen) without leaving the stage; changes apply at once.
##
## Esc or Start opens it. Esc, B or Start go back a page, and from the first page
## resume. Mouse, keys and controller work as in the other menus. It runs while
## the tree is paused (process mode ALWAYS).

signal resume_requested
signal restart_requested
signal main_menu_requested
signal exit_requested

enum Page { MAIN, SETTINGS, CONTROLS }

const PAGE_FADE_TIME := 0.12

@onready var _main_panel: Control = %MainPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_panel: Control = %SettingsPanel
@onready var _settings_rows: VBoxContainer = %SettingsRows
@onready var _settings_back_button: Button = %SettingsBackButton
@onready var _controls: ControlsPage = %ControlsPage

var _page: Page = Page.MAIN
var _nav: MenuFocus
var _common: CommonSettings
var _can_open: bool = true  # off during game over / stage clear
## True while a controller drives the menu, so the controls page opens on its
## GAMEPAD tab.
var _using_pad: bool = false


func _ready() -> void:
	visible = false
	_nav = MenuFocus.new(get_viewport())
	_common = CommonSettings.new(_settings_rows, true)
	_common.controls_requested.connect(_open_controls)
	for button: Button in [_resume_button, _settings_button, _restart_button, _main_menu_button,
			_quit_button, _settings_back_button]:
		button.mouse_entered.connect(button.grab_focus)   # hover focuses, as in every menu
	_resume_button.pressed.connect(_resume)
	_settings_button.pressed.connect(_open_settings)
	_restart_button.pressed.connect(_leave.bind(restart_requested))
	_main_menu_button.pressed.connect(_leave.bind(main_menu_requested))
	_quit_button.pressed.connect(_leave.bind(exit_requested))
	_settings_back_button.pressed.connect(_close_settings)
	_controls.closed.connect(_close_controls)
	SoundManager.attach_ui_sounds(self)


func set_can_open(value: bool) -> void:
	_can_open = value


func _input(event: InputEvent) -> void:
	var device := MenuFocus.device_of(event)
	if device >= 0:
		_using_pad = device == 1
	if not visible:
		if _can_open and event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_open()
		return
	# The controls page handles its own input (it gets each event first).
	if _page == Page.CONTROLS or not MenuFocus.is_navigation_event(event):
		return
	# Leaving can change scene and take this node out of the tree; keep the viewport.
	var viewport := get_viewport()
	if MenuFocus.is_pressed(event, MenuFocus.UP_ACTIONS):
		_nav.move(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.DOWN_ACTIONS):
		_nav.move(1)
	elif MenuFocus.is_pressed(event, MenuFocus.LEFT_ACTIONS):
		_adjust(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.RIGHT_ACTIONS):
		_adjust(1)
	elif MenuFocus.is_pressed(event, MenuFocus.ACCEPT_ACTIONS):
		_nav.activate()
	elif MenuFocus.is_pressed(event, MenuFocus.BACK_ACTIONS):
		_go_back()
	else:
		return
	viewport.set_input_as_handled()


func _open() -> void:
	visible = true
	get_tree().paused = true
	_common.refresh()
	_show_page(Page.MAIN, _resume_button)


func _resume() -> void:
	_close()
	resume_requested.emit()


## Closes the menu, unpauses, and hands [param request] to the game.
func _leave(request: Signal) -> void:
	_close()
	request.emit()


func _close() -> void:
	visible = false
	_page = Page.MAIN
	get_tree().paused = false


func _go_back() -> void:
	match _page:
		Page.MAIN:
			_resume()
		Page.SETTINGS:
			_close_settings()


func _show_page(page: Page, focus_target: Control) -> void:
	_page = page
	_main_panel.visible = page == Page.MAIN
	_settings_panel.visible = page == Page.SETTINGS
	_controls.visible = page == Page.CONTROLS
	_nav.items = _page_items(page)
	var shown: Control = [_main_panel, _settings_panel, _controls][page]
	shown.modulate.a = 0.0
	create_tween().tween_property(shown, "modulate:a", 1.0, PAGE_FADE_TIME)
	if focus_target:
		focus_target.grab_focus()


func _page_items(page: Page) -> Array[Control]:
	var items: Array[Control] = []
	match page:
		Page.MAIN:
			items.assign([_resume_button, _restart_button, _main_menu_button, _settings_button, _quit_button])
		Page.SETTINGS:
			items.assign(_common.rows())
			items.append(_settings_back_button)
		# Page.CONTROLS: the controls page runs its own navigation.
	return items


func _adjust(direction: int) -> void:
	if _page == Page.SETTINGS:
		_common.adjust(_nav.focus_owner(), direction)


func _open_settings() -> void:
	_common.refresh()
	_show_page(Page.SETTINGS, _common.sfx_row)


func _close_settings() -> void:
	_show_page(Page.MAIN, _settings_button)


func _open_controls(player: String) -> void:
	_show_page(Page.CONTROLS, null)
	_controls.open(player, _using_pad)


func _close_controls() -> void:
	_common.refresh()
	_show_page(Page.SETTINGS, _common.controls_row(_controls.get_player()))
