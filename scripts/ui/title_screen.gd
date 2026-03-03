extends Control

enum MenuMode { MAIN, SETTINGS, KEYBIND }

# --- Main menu labels ---
@onready var cursor: Label = $Cursor
@onready var option_1p: Label = $Option1P
@onready var option_2p: Label = $Option2P
@onready var option_settings: Label = $OptionSettings

# --- Settings sub-menu labels ---
@onready var settings_title: Label = $SettingsTitle
@onready var settings_map: Label = $SettingsMap
@onready var settings_theme: Label = $SettingsTheme
@onready var settings_p1_keys: Label = $SettingsP1Keys
@onready var settings_p2_keys: Label = $SettingsP2Keys
@onready var settings_back: Label = $SettingsBack

# --- Keybind sub-menu labels ---
@onready var keybind_title: Label = $KeybindTitle
@onready var keybind_up: Label = $KeybindUp
@onready var keybind_down: Label = $KeybindDown
@onready var keybind_left: Label = $KeybindLeft
@onready var keybind_right: Label = $KeybindRight
@onready var keybind_shoot: Label = $KeybindShoot
@onready var keybind_shoot2: Label = $KeybindShoot2
@onready var keybind_reset: Label = $KeybindReset
@onready var keybind_back: Label = $KeybindBack
@onready var keybind_prompt: Label = $KeybindPrompt

# --- Controls info ---
@onready var controls_label: Label = $Controls

var _selected: int = 0
var _mode: MenuMode = MenuMode.MAIN

# Theme state
var _available_themes: Array[String] = []
var _theme_index: int = 0

# Map pool state
var _available_pools: Array = []  # Array of LevelData.MapPool
var _pool_index: int = 0

# Keybind state
var _keybind_player: String = ""  # "p1" or "p2"
var _keybind_actions: Array[String] = []
var _is_waiting_for_key: bool = false
var _waiting_action: String = ""

# Convenience: keybind label array (populated in _ready)
var _keybind_labels: Array[Label] = []

func _ready() -> void:
	# Build keybind label array for indexed access
	_keybind_labels = [keybind_up, keybind_down, keybind_left, keybind_right, keybind_shoot, keybind_shoot2]

	# Load saved theme first
	var saved_theme := InputSettings.get_saved_theme()
	if saved_theme != "":
		ThemeManager.load_theme(saved_theme)

	# Themes
	_available_themes = ThemeManager.get_available_themes()
	for i in range(_available_themes.size()):
		if _available_themes[i] == ThemeManager.current_theme:
			_theme_index = i
			break

	# Load saved map pool
	var saved_pool := InputSettings.get_saved_map_pool()
	if saved_pool != "":
		GameManager.set_map_pool(saved_pool)

	# Map pools
	_available_pools = LevelData.get_available_pools()
	if not _available_pools.is_empty():
		var found := false
		for i in range(_available_pools.size()):
			if _available_pools[i].id == GameManager.current_map_pool_id:
				_pool_index = i
				found = true
				break
		if not found:
			_pool_index = 0
			GameManager.set_map_pool(_available_pools[0].id)

	_update_pool_label()
	_update_theme_label()
	_update_controls_label()
	_update_cursor()

func _process(_delta: float) -> void:
	match _mode:
		MenuMode.MAIN:
			_process_main()
		MenuMode.SETTINGS:
			_process_settings()
		MenuMode.KEYBIND:
			if not _is_waiting_for_key:
				_process_keybind()

func _input(event: InputEvent) -> void:
	if not _is_waiting_for_key:
		return
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	if event.echo:
		return

	var phys_key: int = event.physical_keycode as int
	if phys_key == 0:
		return

	# Block reserved keys (Escape, F11)
	if phys_key == 4194305 or phys_key == 4194342:  # KEY_ESCAPE, F11
		keybind_prompt.text = "Key reserved, try another..."
		get_viewport().set_input_as_handled()
		return

	InputSettings.save_binding(_waiting_action, phys_key)
	_is_waiting_for_key = false
	keybind_prompt.text = ""
	_update_keybind_labels()
	get_viewport().set_input_as_handled()

# =====================================================================
# Main Menu Mode: 1P(0), 2P(1), SETTINGS(2)
# =====================================================================

func _process_main() -> void:
	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		_selected = maxi(_selected - 1, 0)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		_selected = mini(_selected + 1, 2)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
		if _selected == 2:
			_enter_settings()
		else:
			_start_game()

# =====================================================================
# Settings Mode: MAP(0), THEME(1), P1 KEYS(2), P2 KEYS(3), BACK(4)
# =====================================================================

func _process_settings() -> void:
	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		_selected = maxi(_selected - 1, 0)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		_selected = mini(_selected + 1, 4)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_left") or Input.is_action_just_pressed("p2_left"):
		if _selected == 0:
			_cycle_pool(-1)
		elif _selected == 1:
			_cycle_theme(-1)
	elif Input.is_action_just_pressed("p1_right") or Input.is_action_just_pressed("p2_right"):
		if _selected == 0:
			_cycle_pool(1)
		elif _selected == 1:
			_cycle_theme(1)
	elif Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
		match _selected:
			0:
				_cycle_pool(1)
			1:
				_cycle_theme(1)
			2:
				_enter_keybind("p1")
			3:
				_enter_keybind("p2")
			4:
				_exit_settings()

# =====================================================================
# Keybind Mode: UP(0), DOWN(1), LEFT(2), RIGHT(3), FIRE1(4), FIRE2(5), RESET(6), BACK(7)
# =====================================================================

func _process_keybind() -> void:
	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		_selected = maxi(_selected - 1, 0)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		_selected = mini(_selected + 1, 7)
		_update_cursor()
	elif Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
		if _selected < 6:
			_start_waiting_for_key(_keybind_actions[_selected])
		elif _selected == 6:
			InputSettings.reset_to_defaults(_keybind_player)
			_update_keybind_labels()
		elif _selected == 7:
			_exit_keybind()

# =====================================================================
# Mode Switching
# =====================================================================

func _enter_settings() -> void:
	_mode = MenuMode.SETTINGS
	# Hide main menu options
	option_1p.visible = false
	option_2p.visible = false
	option_settings.visible = false
	controls_label.visible = false
	# Show settings sub-menu
	settings_title.visible = true
	settings_map.visible = true
	settings_theme.visible = true
	settings_p1_keys.visible = true
	settings_p2_keys.visible = true
	settings_back.visible = true
	_update_p1_keys_label()
	_update_p2_keys_label()
	# Reset cursor to first settings option
	_selected = 0
	_update_cursor()

func _exit_settings() -> void:
	_mode = MenuMode.MAIN
	# Show main menu options
	option_1p.visible = true
	option_2p.visible = true
	option_settings.visible = true
	controls_label.visible = true
	# Hide settings sub-menu
	settings_title.visible = false
	settings_map.visible = false
	settings_theme.visible = false
	settings_p1_keys.visible = false
	settings_p2_keys.visible = false
	settings_back.visible = false
	# Update controls label with latest bindings
	_update_controls_label()
	# Return cursor to SETTINGS option
	_selected = 2
	_update_cursor()

func _enter_keybind(player: String) -> void:
	_mode = MenuMode.KEYBIND
	_keybind_player = player
	_is_waiting_for_key = false
	_waiting_action = ""
	# Build action list for this player
	_keybind_actions = InputSettings.get_player_actions(player)
	# Hide settings labels
	settings_title.visible = false
	settings_map.visible = false
	settings_theme.visible = false
	settings_p1_keys.visible = false
	settings_p2_keys.visible = false
	settings_back.visible = false
	# Show keybind labels
	keybind_title.text = "< %s KEYS >" % player.to_upper()
	keybind_title.visible = true
	for label in _keybind_labels:
		label.visible = true
	keybind_reset.visible = true
	keybind_back.visible = true
	keybind_prompt.visible = true
	keybind_prompt.text = ""
	_update_keybind_labels()
	_selected = 0
	_update_cursor()

func _exit_keybind() -> void:
	_mode = MenuMode.SETTINGS
	_is_waiting_for_key = false
	# Hide keybind labels
	keybind_title.visible = false
	for label in _keybind_labels:
		label.visible = false
	keybind_reset.visible = false
	keybind_back.visible = false
	keybind_prompt.visible = false
	# Show settings labels
	settings_title.visible = true
	settings_map.visible = true
	settings_theme.visible = true
	settings_p1_keys.visible = true
	settings_p2_keys.visible = true
	settings_back.visible = true
	_update_p1_keys_label()
	_update_p2_keys_label()
	# Return cursor to the P1/P2 KEYS option
	_selected = 2 if _keybind_player == "p1" else 3
	_update_cursor()

# =====================================================================
# Keybind helpers
# =====================================================================

func _start_waiting_for_key(action: String) -> void:
	_is_waiting_for_key = true
	_waiting_action = action
	# Find display name
	var idx := _keybind_actions.find(action)
	var display_name: String = InputSettings.ACTION_DISPLAY_NAMES[idx] if idx >= 0 else action
	keybind_prompt.text = "Press a key for %s..." % display_name

func _update_keybind_labels() -> void:
	for i in range(6):
		var action: String = _keybind_actions[i]
		var key_name: String = InputSettings.get_key_name(action)
		_keybind_labels[i].text = "%s:  %s" % [InputSettings.ACTION_DISPLAY_NAMES[i], key_name]

func _update_p1_keys_label() -> void:
	if settings_p1_keys:
		settings_p1_keys.text = "P1 KEYS: %s" % InputSettings.get_player_controls_text("p1")

func _update_p2_keys_label() -> void:
	if settings_p2_keys:
		settings_p2_keys.text = "P2 KEYS: %s" % InputSettings.get_player_controls_text("p2")

func _update_controls_label() -> void:
	if controls_label:
		controls_label.text = "P1: %s\nP2: %s\nF11: Toggle Fullscreen" % [
			InputSettings.get_player_controls_text("p1"),
			InputSettings.get_player_controls_text("p2"),
		]

# =====================================================================
# Cursor
# =====================================================================

func _update_cursor() -> void:
	if not cursor:
		return
	match _mode:
		MenuMode.MAIN:
			match _selected:
				0:
					cursor.position.y = option_1p.position.y
				1:
					cursor.position.y = option_2p.position.y
				2:
					cursor.position.y = option_settings.position.y
		MenuMode.SETTINGS:
			match _selected:
				0:
					cursor.position.y = settings_map.position.y
				1:
					cursor.position.y = settings_theme.position.y
				2:
					cursor.position.y = settings_p1_keys.position.y
				3:
					cursor.position.y = settings_p2_keys.position.y
				4:
					cursor.position.y = settings_back.position.y
		MenuMode.KEYBIND:
			if _selected < 6:
				cursor.position.y = _keybind_labels[_selected].position.y
			elif _selected == 6:
				cursor.position.y = keybind_reset.position.y
			elif _selected == 7:
				cursor.position.y = keybind_back.position.y

# =====================================================================
# Map pool cycling
# =====================================================================

func _cycle_pool(direction: int) -> void:
	if _available_pools.is_empty():
		return
	_pool_index = (_pool_index + direction) % _available_pools.size()
	if _pool_index < 0:
		_pool_index += _available_pools.size()
	GameManager.set_map_pool(_available_pools[_pool_index].id)
	InputSettings.save_map_pool(_available_pools[_pool_index].id)
	_update_pool_label()

func _update_pool_label() -> void:
	if settings_map:
		if not _available_pools.is_empty():
			var pool: LevelData.MapPool = _available_pools[_pool_index]
			var stage_count := LevelData.get_stage_count()
			settings_map.text = "MAP: %s (%d)" % [pool.display_name, stage_count]
		else:
			settings_map.text = "MAP: (none)"

# =====================================================================
# Theme cycling
# =====================================================================

func _cycle_theme(direction: int) -> void:
	if _available_themes.is_empty():
		return
	_theme_index = (_theme_index + direction) % _available_themes.size()
	if _theme_index < 0:
		_theme_index += _available_themes.size()
	ThemeManager.load_theme(_available_themes[_theme_index])
	InputSettings.save_theme(_available_themes[_theme_index])
	_update_theme_label()

func _update_theme_label() -> void:
	if settings_theme:
		settings_theme.text = "THEME: %s" % ThemeManager.get_theme_display_name()

# =====================================================================
# Start game
# =====================================================================

func _start_game() -> void:
	GameManager.start_game(_selected == 1)
