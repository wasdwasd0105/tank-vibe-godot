extends Node

const SAVE_PATH: String = "user://settings.cfg"

# Actions per player (ordered for keybind UI)
const PLAYER_ACTION_SUFFIXES: Array = ["up", "down", "left", "right", "shoot", "shoot2"]
const ACTION_DISPLAY_NAMES: Array = ["UP", "DOWN", "LEFT", "RIGHT", "FIRE 1", "FIRE 2"]

# Short display names for keys (OS.get_keycode_string returns verbose names)
const SHORT_KEY_NAMES: Dictionary = {
	"Up": "\u2191",
	"Down": "\u2193",
	"Left": "\u2190",
	"Right": "\u2192",
	"Space": "Space",
	"BracketLeft": "[",
	"BracketRight": "]",
	"Backslash": "\\",
	"Semicolon": ";",
	"Apostrophe": "'",
	"Comma": ",",
	"Period": ".",
	"Slash": "/",
	"Minus": "-",
	"Equal": "=",
	"QuoteLeft": "`",
	"Control": "Ctrl",
	"Shift": "Shift",
	"Alt": "Alt",
	"Meta": "Meta",
	"CapsLock": "Caps",
	"Tab": "Tab",
	"Backspace": "Bksp",
	"Delete": "Del",
	"Insert": "Ins",
	"Home": "Home",
	"End": "End",
	"PageUp": "PgUp",
	"PageDown": "PgDn",
	"Enter": "Enter",
	"KP Enter": "NumEnter",
}

# Default physical keycodes (matches project.godot fallbacks)
const DEFAULTS: Dictionary = {
	"p1_up": 87,         # W
	"p1_down": 83,       # S
	"p1_left": 65,       # A
	"p1_right": 68,      # D
	"p1_shoot": 84,      # T
	"p1_shoot2": 89,     # Y
	"p2_up": 4194320,    # Up arrow
	"p2_down": 4194322,  # Down arrow
	"p2_left": 4194319,  # Left arrow
	"p2_right": 4194321, # Right arrow
	"p2_shoot": 91,      # [
	"p2_shoot2": 93,     # ]
}

var _config: ConfigFile = ConfigFile.new()

func _ready() -> void:
	load_and_apply()

# =====================================================================
# Load / Apply all settings
# =====================================================================

func load_and_apply() -> void:
	var err := _config.load(SAVE_PATH)
	if err != OK:
		# No saved config — use defaults
		_config = ConfigFile.new()

	# Apply key bindings
	for action in DEFAULTS:
		var phys_key: int = _config.get_value("bindings", action, DEFAULTS[action])
		_apply_binding(action, phys_key)

func _apply_binding(action: String, phys_keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = phys_keycode as Key
	ev.device = -1
	InputMap.action_add_event(action, ev)

# =====================================================================
# Key binding management
# =====================================================================

func save_binding(action: String, phys_keycode: int) -> void:
	_apply_binding(action, phys_keycode)
	_config.set_value("bindings", action, phys_keycode)
	_config.save(SAVE_PATH)

func get_binding(action: String) -> int:
	var events := InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			return ev.physical_keycode as int
	return DEFAULTS.get(action, 0)

func get_key_name(action: String) -> String:
	var phys: int = get_binding(action)
	return _phys_to_short_name(phys)

func _phys_to_short_name(phys_keycode: int) -> String:
	if phys_keycode == 0:
		return "?"
	var display_keycode: int = DisplayServer.keyboard_get_keycode_from_physical(phys_keycode as Key) as int
	var raw_name: String
	if display_keycode != 0:
		raw_name = OS.get_keycode_string(display_keycode as Key)
	else:
		raw_name = OS.get_keycode_string(phys_keycode as Key)
	# Use short name if available
	if SHORT_KEY_NAMES.has(raw_name):
		return SHORT_KEY_NAMES[raw_name]
	return raw_name

func get_player_actions(player: String) -> Array[String]:
	var actions: Array[String] = []
	for suffix in PLAYER_ACTION_SUFFIXES:
		actions.append(player + "_" + suffix)
	return actions

func get_player_controls_text(player: String) -> String:
	var keys: Array[String] = []
	for suffix in PLAYER_ACTION_SUFFIXES:
		var action: String = player + "_" + suffix
		keys.append(get_key_name(action))
	# Check for known compact patterns
	var move_text: String = _get_compact_movement(keys[0], keys[1], keys[2], keys[3])
	return "%s + %s + %s" % [move_text, keys[4], keys[5]]

func _get_compact_movement(up: String, down: String, left: String, right: String) -> String:
	# Check WASD
	if up == "W" and down == "S" and left == "A" and right == "D":
		return "WASD"
	# Check Arrows
	if up == "\u2191" and down == "\u2193" and left == "\u2190" and right == "\u2192":
		return "\u2190\u2191\u2193\u2192"
	# Check IJKL
	if up == "I" and down == "K" and left == "J" and right == "L":
		return "IJKL"
	# Fallback: list all four
	return "%s %s %s %s" % [up, down, left, right]

func reset_to_defaults(player: String) -> void:
	for suffix in PLAYER_ACTION_SUFFIXES:
		var action: String = player + "_" + suffix
		var default_key: int = DEFAULTS.get(action, 0)
		_apply_binding(action, default_key)
		_config.set_value("bindings", action, default_key)
	_config.save(SAVE_PATH)

# =====================================================================
# Theme / Map persistence
# =====================================================================

func save_theme(theme_name: String) -> void:
	_config.set_value("game", "theme", theme_name)
	_config.save(SAVE_PATH)

func save_map_pool(pool_id: String) -> void:
	_config.set_value("game", "map_pool", pool_id)
	_config.save(SAVE_PATH)

func get_saved_theme() -> String:
	return _config.get_value("game", "theme", "")

func get_saved_map_pool() -> String:
	return _config.get_value("game", "map_pool", "")

func save_max_credits(value: int) -> void:
	_config.set_value("game", "max_credits", clampi(value, 1, 50))
	_config.save(SAVE_PATH)

func get_saved_max_credits() -> int:
	return _config.get_value("game", "max_credits", 3)

func save_difficulty(value: int) -> void:
	_config.set_value("game", "difficulty", clampi(value, 1, 5))
	_config.save(SAVE_PATH)

func get_saved_difficulty() -> int:
	return _config.get_value("game", "difficulty", 1)

## Folder a file was last imported from, per purpose ("save", "map"), so the
## file pickers reopen there.
func save_import_dir(purpose: String, path: String) -> void:
	_config.set_value("import", purpose + "_dir", path)
	_config.save(SAVE_PATH)

func get_saved_import_dir(purpose: String) -> String:
	return _config.get_value("import", purpose + "_dir", "")

# =====================================================================
# Audio volume persistence (0.0 - 1.0)
# =====================================================================

func save_sfx_volume(value: float) -> void:
	_config.set_value("audio", "sfx_volume", clampf(value, 0.0, 1.0))
	_config.save(SAVE_PATH)

func get_saved_sfx_volume() -> float:
	return _config.get_value("audio", "sfx_volume", 0.8)

func save_music_volume(value: float) -> void:
	_config.set_value("audio", "music_volume", clampf(value, 0.0, 1.0))
	_config.save(SAVE_PATH)

func get_saved_music_volume() -> float:
	return _config.get_value("audio", "music_volume", 0.7)

# =====================================================================
# Stats persistence
# =====================================================================

func get_games_played() -> int:
	return _config.get_value("stats", "games_played", 0)

func increment_games_played() -> void:
	var count: int = get_games_played() + 1
	_config.set_value("stats", "games_played", count)
	_config.save(SAVE_PATH)
