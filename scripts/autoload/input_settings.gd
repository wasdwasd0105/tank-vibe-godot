extends Node

## The GAME SPEED setting changed (see save_game_speed).
signal game_speed_changed
## ENEMY MINES was switched (see save_enemy_mines).
signal enemy_mines_changed
## BASE INVINCIBLE was switched (see save_base_invincible).
signal base_invincible_changed
## A player's controller was asked to rumble with their vibration on, whether
## or not one is plugged in (see rumble).
signal rumbled(player_id: int, weak: float, strong: float, duration: float)

const SAVE_PATH: String = "user://settings.cfg"
## A test run keeps its settings here instead, starting from the defaults each
## time, so it never touches (or depends on) the player's own settings.
const TEST_SAVE_PATH: String = "user://test_settings.cfg"

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

# --- Game controllers (Xbox names; Godot's standard joypad mapping) ---
# The first controller plays P1 and the second P2, or both players share one
# (each picks theirs on the controls page). On a controller a player has
# three controls, MOVE (all four directions together), FIRE 1 and FIRE 2, and
# each control has two slots the controls page sets one at a time. A MOVE slot
# holds a whole direction set: the D-pad or a stick (the stick goes whichever
# way it is pushed furthest, PlayerTank). A fire slot holds a button or a
# trigger. A slot may be empty; the empty one is always the second, so emptying
# the first moves the second's input up.
#
# A controller input is kept as a short code: "b<button>" for a button, or
# "a<axis>+" / "a<axis>-" for a stick or trigger pushed one way. "b0" is A,
# "a5+" RT and "a1-" the left stick pushed up.
const PAD_CONTROLS: Array[String] = ["move", "shoot", "shoot2"]
const PAD_CONTROL_NAMES: Array[String] = ["MOVE", "FIRE 1", "FIRE 2"]
const PAD_SLOTS: int = 2
const PLAYERS: Array[String] = ["p1", "p2"]
## The controllers a player can pick: the first and the second plugged in.
const PAD_DEVICE_COUNT: int = 2
const MOVE_DIRECTIONS: Array[String] = ["up", "down", "left", "right"]
## MOVE's direction sets: the input that drives each direction. The D-pad is
## buttons 11-14, the left stick axes 0 (across) and 1 (down), the right stick
## axes 2 and 3.
const PAD_MOVE_SETS: Dictionary = {
	"dpad": {"up": "b11", "down": "b12", "left": "b13", "right": "b14"},
	"ls": {"up": "a1-", "down": "a1+", "left": "a0-", "right": "a0+"},
	"rs": {"up": "a3-", "down": "a3+", "left": "a2-", "right": "a2+"},
}
const PAD_MOVE_SET_NAMES: Dictionary = {"dpad": "D-pad", "ls": "L-stick", "rs": "R-stick"}
## The triggers, the only axes a fire slot takes.
const PAD_TRIGGER_CODES: Array[String] = ["a4+", "a5+"]
## Out of the box: D-pad + left stick to move, A / RT fire 1, X / LT fire 2.
const PAD_DEFAULTS: Dictionary = {
	"move": ["dpad", "ls"],
	"shoot": ["b0", "a5+"],
	"shoot2": ["b2", "a4+"],
}
## Two players on one controller: P1 takes its left half (left stick and D-pad,
## LT and LB), P2 its right (right stick, RT and RB, with A and X to spare).
const PAD_SHARED_DEFAULTS: Dictionary = {
	"p1": {"move": ["ls", "dpad"], "shoot": ["a4+", ""], "shoot2": ["b9", ""]},
	"p2": {"move": ["rs", ""], "shoot": ["a5+", "b0"], "shoot2": ["b10", "b2"]},
}
## How far the stick must lean before the tank drives.
const STICK_DEADZONE: float = 0.35
## Any controller: A confirms and B goes back in the menus, Start pauses. They
## keep these jobs whatever the players bind them to (MenuFocus).
const MENU_PAD_BUTTONS: Dictionary = {
	"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B, "pause": JOY_BUTTON_START,
}
## Buttons no slot can take: Start pauses, View (Back) empties a slot on the
## controls page, and Guide belongs to the system.
const PAD_RESERVED_BUTTONS: Array = [JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_GUIDE]
const PAD_BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LS click", JOY_BUTTON_RIGHT_STICK: "RS click",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
	JOY_BUTTON_MISC1: "Share", JOY_BUTTON_TOUCHPAD: "Touchpad",
	JOY_BUTTON_PADDLE1: "Paddle 1", JOY_BUTTON_PADDLE2: "Paddle 2",
	JOY_BUTTON_PADDLE3: "Paddle 3", JOY_BUTTON_PADDLE4: "Paddle 4",
}
## Stick and trigger names per axis: [pushed the negative way, the positive way].
const PAD_AXIS_NAMES: Dictionary = {
	JOY_AXIS_LEFT_X: ["LS ←", "LS →"], JOY_AXIS_LEFT_Y: ["LS ↑", "LS ↓"],
	JOY_AXIS_RIGHT_X: ["RS ←", "RS →"], JOY_AXIS_RIGHT_Y: ["RS ↑", "RS ↓"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}
## Shown for an empty slot.
const PAD_NONE_NAME: String = "—"

var _config: ConfigFile = ConfigFile.new()
var _save_path: String = SAVE_PATH
## Controller slots per player control ("p1_move", "p2_shoot"...): PAD_SLOTS
## values, "" for an empty slot. A MOVE slot holds a PAD_MOVE_SETS name, a fire
## slot a code.
var _pad_slots: Dictionary = {}

func _ready() -> void:
	if is_test_run():
		_save_path = test_save_path()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))
	load_and_apply()
	_add_menu_pad_buttons()

## True when a test scene (res://scenes/test/...) was started, or a harness
## asked for it with --test-settings.
static func is_test_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://scenes/test/"):
			return true
	return "--test-settings" in OS.get_cmdline_user_args()

## A test run's settings file. A run given --test-profile=NAME gets its own
## (user://test_settings_NAME.cfg), so two processes of one test (an online host
## and its client) never share one.
static func test_save_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-profile="):
			var profile := arg.get_slice("=", 1).validate_filename()
			if not profile.is_empty():
				return "user://test_settings_%s.cfg" % profile
	return TEST_SAVE_PATH

## The settings file in use: the player's, or a test run's own.
func get_save_path() -> String:
	return _save_path

# =====================================================================
# Load / Apply all settings
# =====================================================================

func load_and_apply() -> void:
	# A fresh ConfigFile: load() merges into whatever is already held, so a
	# reload would otherwise keep values the file no longer has.
	_config = ConfigFile.new()
	var err := _config.load(_save_path)
	if err != OK:
		# No saved config — use defaults
		_config = ConfigFile.new()
	_split_vibration()

	# Apply key and controller bindings
	_load_pad_slots()
	for action in DEFAULTS:
		var phys_key: int = _config.get_value("bindings", action, DEFAULTS[action])
		_apply_binding(action, phys_key)

## Rebuilds [param action] from its key and its controller slots.
func _apply_binding(action: String, phys_keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = phys_keycode as Key
	ev.device = -1
	InputMap.action_add_event(action, ev)
	_add_pad_events(action)

## The player's controller inputs for [param action] ("p1_up", "p2_shoot2"...),
## on that player's controller: a direction takes its part of each MOVE set.
func _add_pad_events(action: String) -> void:
	var player := action.get_slice("_", 0)
	var suffix := action.get_slice("_", 1)
	var codes: Array[String] = []
	if suffix in MOVE_DIRECTIONS:
		for set_name in get_pad_slots(player, "move"):
			if PAD_MOVE_SETS.has(set_name):
				codes.append(PAD_MOVE_SETS[set_name][suffix])
		InputMap.action_set_deadzone(action, STICK_DEADZONE)
	elif suffix in PAD_CONTROLS:
		for code in get_pad_slots(player, suffix):
			if code != "":
				codes.append(code)
	for code in codes:
		var ev := _pad_event(code)
		if ev == null:
			continue
		ev.device = get_pad_device(player)
		InputMap.action_add_event(action, ev)

func _add_menu_pad_buttons() -> void:
	for action in MENU_PAD_BUTTONS:
		if not InputMap.has_action(action):
			continue
		var button := InputEventJoypadButton.new()
		button.button_index = MENU_PAD_BUTTONS[action]
		button.device = -1
		if not InputMap.action_has_event(action, button):
			InputMap.action_add_event(action, button)

# =====================================================================
# Key binding management
# =====================================================================

func save_binding(action: String, phys_keycode: int) -> void:
	_apply_binding(action, phys_keycode)
	_config.set_value("bindings", action, phys_keycode)
	_config.save(_save_path)

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
	_config.save(_save_path)

# =====================================================================
# Controller binding management
# =====================================================================

## The controller [param player] ("p1", "p2") plays on: 0 is the first plugged
## in, 1 the second. Unless picked otherwise, P1 has the first and P2 the second.
func get_pad_device(player: String) -> int:
	var fallback := 0 if player == "p1" else 1
	var device: Variant = _config.get_value("controller", player + "_device", fallback)
	return device if device is int and device >= 0 and device < PAD_DEVICE_COUNT else fallback

## True while both players play on the same controller.
func is_pad_shared() -> bool:
	return get_pad_device("p1") == get_pad_device("p2")

## The player sharing [param player]'s controller, or "".
func get_pad_partner(player: String) -> String:
	return ("p2" if player == "p1" else "p1") if is_pad_shared() else ""

## Puts [param player] on controller [param device]. Starting or ending a share
## gives both players the defaults of their new setup: sharing, P1 takes the
## controller's left half and P2 its right; apart, each has a whole layout.
func set_pad_device(player: String, device: int) -> void:
	device = clampi(device, 0, PAD_DEVICE_COUNT - 1)
	if device == get_pad_device(player):
		return
	var was_shared := is_pad_shared()
	_config.set_value("controller", player + "_device", device)
	if is_pad_shared() != was_shared:
		for each in PLAYERS:
			_store_default_pad_slots(each)
	for each in PLAYERS:
		_apply_pad(each)
	_config.save(_save_path)

## [param player]'s slots for [param control] ("move", "shoot", "shoot2"), one
## value per slot and "" where a slot is empty.
func get_pad_slots(player: String, control: String) -> PackedStringArray:
	return _pad_slots.get(player + "_" + control, PackedStringArray(_default_pad_slots(player, control)))

func get_pad_slot(player: String, control: String, slot: int) -> String:
	return get_pad_slots(player, control)[slot]

## Puts [param value] in one of [param player]'s slots, or empties it for "".
## Another slot on the same controller that held the value (the player's own,
## or the other player's while they share it) takes this slot's old value
## instead, so one input never drives two things. An emptied first slot takes
## the second's input. Returns the other slot that changed as {"player",
## "control", "slot", "value"}, or {} when nothing else did.
func set_pad_slot(player: String, control: String, slot: int, value: String) -> Dictionary:
	if value != "" and not is_pad_value_for(control, value):
		return {}
	var old := get_pad_slot(player, control, slot)
	if value == old:
		return {}
	var moved := {}
	if value != "":
		for other_player in _players_on_pad(player):
			for other_control in PAD_CONTROLS:
				for other_slot in PAD_SLOTS:
					var same_slot := other_player == player and other_control == control and other_slot == slot
					if not same_slot and get_pad_slot(other_player, other_control, other_slot) == value:
						_store_pad_slot(other_player, other_control, other_slot, old)
						moved = {"player": other_player, "control": other_control, "slot": other_slot, "value": old}
	_store_pad_slot(player, control, slot, value)
	for each in PLAYERS:
		for each_control in PAD_CONTROLS:
			_pack_pad_slots(each, each_control)
		_apply_pad(each)
	_config.save(_save_path)
	# An input moved into its own control's empty slot ends up where it was.
	if moved.get("player", "") == player and moved.get("control", "") == control and old == "":
		return {}
	return moved

## Puts [param player]'s layout back to its defaults. While two players share a
## controller both get their halves back, as one player's defaults could clash
## with what the other has changed.
func reset_pad_to_defaults(player: String) -> void:
	for each in _players_on_pad(player):
		_store_default_pad_slots(each)
	for each in PLAYERS:
		_apply_pad(each)
	_config.save(_save_path)

## What [param event] puts in a [param control] slot: for "move" the direction
## set it belongs to ("dpad", "ls", "rs"), for a fire button its own code ("b0",
## "a5+"). "" when such a slot can't take it.
func pad_value_for(control: String, event: InputEvent) -> String:
	var code := pad_code_for(event)
	if control == "move":
		for set_name: String in PAD_MOVE_SETS:
			if code in PAD_MOVE_SETS[set_name].values():
				return set_name
		return ""
	return code if is_pad_value_for(control, code) else ""

## True when [param value] fits a [param control] slot: a direction set for
## MOVE; for a fire button a trigger, or any button but the D-pad's and the
## reserved ones.
func is_pad_value_for(control: String, value: String) -> bool:
	if control == "move":
		return PAD_MOVE_SETS.has(value)
	if value in PAD_TRIGGER_CODES:
		return true
	var ev := _pad_event(value)
	return ev is InputEventJoypadButton and pad_code_for(ev) == value \
			and not value in PAD_MOVE_SETS["dpad"].values() and not is_pad_code_reserved(value)

## The code for a controller button, or for a stick or trigger pushed the way
## [param event] leans; "" for anything else.
func pad_code_for(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return "b%d" % event.button_index
	if event is InputEventJoypadMotion and event.axis_value != 0.0:
		return "a%d%s" % [event.axis, "+" if event.axis_value > 0.0 else "-"]
	return ""

## True for the buttons no slot can take (Start, View, Guide).
func is_pad_code_reserved(code: String) -> bool:
	var ev := _pad_event(code)
	return ev is InputEventJoypadButton and ev.button_index in PAD_RESERVED_BUTTONS

## Display name of a slot value or code: "D-pad", "L-stick", "A", "RT"..., and a
## dash for an empty slot. Words are in the menus' language ("十字键"); the
## letters and the names printed on the pads stay as they are.
func get_pad_name(value: String) -> String:
	if PAD_MOVE_SET_NAMES.has(value):
		return tr(PAD_MOVE_SET_NAMES[value])
	var ev := _pad_event(value)
	if ev is InputEventJoypadButton:
		if PAD_BUTTON_NAMES.has(ev.button_index):
			return tr(PAD_BUTTON_NAMES[ev.button_index])
		return tr("Button %d") % ev.button_index
	if ev is InputEventJoypadMotion:
		var positive: bool = ev.axis_value > 0.0
		if PAD_AXIS_NAMES.has(ev.axis):
			return PAD_AXIS_NAMES[ev.axis][1 if positive else 0]
		return tr("Axis %d%s") % [ev.axis, "+" if positive else "-"]
	return PAD_NONE_NAME

## [param player] and whoever shares their controller.
func _players_on_pad(player: String) -> Array[String]:
	var on_pad: Array[String] = [player]
	var partner := get_pad_partner(player)
	if partner != "":
		on_pad.append(partner)
	return on_pad

## The layout [param player] starts from: half a controller while sharing one.
func _default_pad_slots(player: String, control: String) -> Array:
	return PAD_SHARED_DEFAULTS[player][control] if is_pad_shared() else PAD_DEFAULTS[control]

func _store_default_pad_slots(player: String) -> void:
	for control in PAD_CONTROLS:
		for slot in PAD_SLOTS:
			_store_pad_slot(player, control, slot, _default_pad_slots(player, control)[slot])

## Reads both players' slots from the settings, keeping only values their slots
## can take, each once per controller; a control saved as anything but a list
## keeps its defaults. Entries of an older layout are dropped.
func _load_pad_slots() -> void:
	var taken_on := {}   # controller -> the values already taken on it
	for player in PLAYERS:
		var taken: Array = taken_on.get(get_pad_device(player), [])
		taken_on[get_pad_device(player)] = taken
		for control in PAD_CONTROLS:
			var saved: Variant = _config.get_value("pad_bindings", player + "_" + control, _default_pad_slots(player, control))
			if not (saved is Array or saved is PackedStringArray):
				saved = _default_pad_slots(player, control)
			var slots := PackedStringArray()
			for slot in PAD_SLOTS:
				var value: Variant = saved[slot] if slot < saved.size() else ""
				if not value is String or not is_pad_value_for(control, value) or value in taken:
					value = ""
				if value != "":
					taken.append(value)
				slots.append(value)
			_pad_slots[player + "_" + control] = slots
			_pack_pad_slots(player, control)
		for suffix in PLAYER_ACTION_SUFFIXES:
			if not suffix in PAD_CONTROLS and _config.has_section_key("pad_bindings", player + "_" + suffix):
				_config.erase_section_key("pad_bindings", player + "_" + suffix)

## Moves a control's inputs to the front, so an empty slot is always the last.
func _pack_pad_slots(player: String, control: String) -> void:
	var packed := PackedStringArray()
	for value in get_pad_slots(player, control):
		if value != "":
			packed.append(value)
	while packed.size() < PAD_SLOTS:
		packed.append("")
	for slot in PAD_SLOTS:
		if get_pad_slot(player, control, slot) != packed[slot]:
			_store_pad_slot(player, control, slot, packed[slot])

func _store_pad_slot(player: String, control: String, slot: int, value: String) -> void:
	var slots := get_pad_slots(player, control).duplicate()
	slots[slot] = value
	_pad_slots[player + "_" + control] = slots
	_config.set_value("pad_bindings", player + "_" + control, slots)

## Rebuilds [param player]'s actions after a slot changed.
func _apply_pad(player: String) -> void:
	for action in get_player_actions(player):
		_apply_binding(action, get_binding(action))

## The input event a controller code stands for (device not set), or null.
func _pad_event(code: String) -> InputEvent:
	if code.begins_with("b") and code.substr(1).is_valid_int():
		var index := code.substr(1).to_int()
		if index < 0 or index >= JOY_BUTTON_MAX:
			return null
		var button := InputEventJoypadButton.new()
		button.button_index = index as JoyButton
		return button
	var axis := code.substr(1, code.length() - 2)
	if code.begins_with("a") and (code.ends_with("+") or code.ends_with("-")) and axis.is_valid_int():
		var index := axis.to_int()
		if index < 0 or index >= JOY_AXIS_MAX:
			return null
		var motion := InputEventJoypadMotion.new()
		motion.axis = index as JoyAxis
		motion.axis_value = 1.0 if code.ends_with("+") else -1.0
		return motion
	return null

# =====================================================================
# Map persistence
# =====================================================================

func save_map_pool(pool_id: String) -> void:
	_config.set_value("game", "map_pool", pool_id)
	_config.save(_save_path)

func get_saved_map_pool() -> String:
	return _config.get_value("game", "map_pool", "")

func save_difficulty(value: int) -> void:
	_config.set_value("game", "difficulty", clampi(value, 1, 5))
	_config.save(_save_path)

func get_saved_difficulty() -> int:
	return _config.get_value("game", "difficulty", 1)

## ENEMY MINES: whether the mine tanks lay mines. Off, they fire rapid shells
## instead (EnemyTank); players found the original's mines made it too hard.
func save_enemy_mines(on: bool) -> void:
	_config.set_value("game", "enemy_mines", on)
	_config.save(_save_path)
	enemy_mines_changed.emit()

func get_enemy_mines() -> bool:
	var on: Variant = _config.get_value("game", "enemy_mines", true)
	return on if on is bool else true

## BASE INVINCIBLE: no shell can destroy the base (Bullet._hit_base), and its
## flag shows the guard for as long as it's on. Off out of the box.
func save_base_invincible(on: bool) -> void:
	_config.set_value("game", "base_invincible", on)
	_config.save(_save_path)
	base_invincible_changed.emit()

func get_base_invincible() -> bool:
	var on: Variant = _config.get_value("game", "base_invincible", false)
	return on if on is bool else false

## ENEMY MINE LEVEL: the strongest mine an enemy lays, as players count mine
## levels (1-4; Mine.level is 0-3). Out of the box 3, Sean's old cap: the ringed
## level-4 mines the original's toughest mine tank laid on EXPERT and INSANE
## stay out.
const ENEMY_MINE_LEVEL_MIN := 1
const ENEMY_MINE_LEVEL_MAX := 4
const DEFAULT_ENEMY_MINE_LEVEL := 3

func save_enemy_mine_level(level: int) -> void:
	_config.set_value("game", "enemy_mine_level", clampi(level, ENEMY_MINE_LEVEL_MIN, ENEMY_MINE_LEVEL_MAX))
	_config.save(_save_path)

func get_enemy_mine_level() -> int:
	var level: Variant = _config.get_value("game", "enemy_mine_level", DEFAULT_ENEMY_MINE_LEVEL)
	return clampi(level, ENEMY_MINE_LEVEL_MIN, ENEMY_MINE_LEVEL_MAX) if level is int else DEFAULT_ENEMY_MINE_LEVEL

## The original's game speeds, in percent: its clock ran at speed / 75 ticks a
## millisecond (0x4c7a3b; table 0x4d3c58), 100 % unless changed in its options.
const GAME_SPEEDS: Array[int] = [83, 100, 117, 133, 150]
const DEFAULT_GAME_SPEED := 100

func save_game_speed(percent: int) -> void:
	_config.set_value("game", "game_speed", percent)
	_config.save(_save_path)
	game_speed_changed.emit()

## ALWAYS FULLSCREEN: the stages play fullscreen, the menus in the window
## (WindowManager.enter_game / leave_game).
func save_always_fullscreen(on: bool) -> void:
	_config.set_value("game", "always_fullscreen", on)
	_config.save(_save_path)

func get_always_fullscreen() -> bool:
	return _config.get_value("game", "always_fullscreen", false)

## The GAME SPEED setting, one of GAME_SPEEDS.
func get_saved_game_speed() -> int:
	var percent: int = _config.get_value("game", "game_speed", DEFAULT_GAME_SPEED)
	return percent if percent in GAME_SPEEDS else DEFAULT_GAME_SPEED

## The menus' language, a locale code ("en", "zh_CN"); see Localization.
func save_language(code: String) -> void:
	_config.set_value("game", "language", code)
	_config.save(_save_path)

func get_saved_language() -> String:
	return _config.get_value("game", "language", "")

## Folder a file was last imported from, per purpose ("save", "map"), so the
## file pickers reopen there.
func save_import_dir(purpose: String, path: String) -> void:
	_config.set_value("import", purpose + "_dir", path)
	_config.save(_save_path)

func get_saved_import_dir(purpose: String) -> String:
	return _config.get_value("import", purpose + "_dir", "")

# =====================================================================
# Online play: hosting (the pause menu's ONLINE tab) and the ONLINE BATTLE list
# =====================================================================

## The game's default port (Net.DEFAULT_PORT; not named here, as Net loads after
## this).
const DEFAULT_ONLINE_PORT: int = 24680
## Hosting lets in up to this many remote players (Net.MAX_CLIENTS).
const MAX_HOST_PLAYERS: int = 3

## The port, password ("" for none) and most remote players a game opened to
## others uses.
func save_host_settings(port: int, password: String, max_players: int) -> void:
	_config.set_value("online", "port", port)
	_config.set_value("online", "host_password", password)
	_config.set_value("online", "max_players", clampi(max_players, 1, MAX_HOST_PLAYERS))
	_config.save(_save_path)

func get_online_port() -> int:
	var value: Variant = _config.get_value("online", "port", DEFAULT_ONLINE_PORT)
	return value if value is int and value > 0 and value < 65536 else DEFAULT_ONLINE_PORT

func get_host_password() -> String:
	var value: Variant = _config.get_value("online", "host_password", "")
	return value if value is String else ""

func get_host_max_players() -> int:
	var value: Variant = _config.get_value("online", "max_players", MAX_HOST_PLAYERS)
	return clampi(value, 1, MAX_HOST_PLAYERS) if value is int else MAX_HOST_PLAYERS

## The name the player goes by online: the one their most recently used
## connection plays under, or PLAYER.
func get_online_name() -> String:
	var newest: Dictionary = {}
	for connection: Dictionary in get_online_connections():
		if newest.is_empty() or connection["used"] > newest["used"]:
			newest = connection
	return newest.get("name", "PLAYER")

## The games the player has saved on the ONLINE BATTLE screen, each as
## {"name": the name to play as, "address": the host's, as typed,
## "password": the game's ("" for none), "used": when it was saved or last
## connected to (Unix time), "joined": when it last got in (local ISO date and
## time, "" never)}. Entries that aren't whole are left out.
func get_online_connections() -> Array[Dictionary]:
	var connections: Array[Dictionary] = []
	var saved: Variant = _config.get_value("online", "connections", [])
	if not saved is Array:
		return connections
	for entry: Variant in saved:
		if not entry is Dictionary:
			continue
		var name: Variant = entry.get("name")
		var address: Variant = entry.get("address")
		if not name is String or not address is String or (name as String).is_empty() \
				or (address as String).is_empty():
			continue
		connections.append({"name": name, "address": address, "password": str(entry.get("password", "")),
				"used": float(entry.get("used", 0.0)), "joined": str(entry.get("joined", ""))})
	return connections

func save_online_connections(connections: Array[Dictionary]) -> void:
	_config.set_value("online", "connections", connections)
	for old_key: String in ["address", "name"]:  # the last address and name, from before the list
		if _config.has_section_key("online", old_key):
			_config.erase_section_key("online", old_key)
	_config.save(_save_path)

# =====================================================================
# Audio volume persistence (0.0 - 1.0)
# =====================================================================

func save_sfx_volume(value: float) -> void:
	_config.set_value("audio", "sfx_volume", clampf(value, 0.0, 1.0))
	_config.save(_save_path)

func get_saved_sfx_volume() -> float:
	return _config.get_value("audio", "sfx_volume", 0.8)

func save_music_volume(value: float) -> void:
	_config.set_value("audio", "music_volume", clampf(value, 0.0, 1.0))
	_config.save(_save_path)

func get_saved_music_volume() -> float:
	return _config.get_value("audio", "music_volume", 0.7)

# =====================================================================
# Controller vibration
# =====================================================================

## True when [param player]'s ("p1", "p2") controller rumbles: on unless the
## player switched it off on their controls page.
func get_vibration(player: String) -> bool:
	var enabled: Variant = _config.get_value("controller", player + "_vibration", true)
	return enabled if enabled is bool else true

func set_vibration(player: String, enabled: bool) -> void:
	_config.set_value("controller", player + "_vibration", enabled)
	_config.save(_save_path)

## Vibration used to be one switch for both players; each starts from it.
func _split_vibration() -> void:
	if not _config.has_section_key("controller", "vibration"):
		return
	var enabled: Variant = _config.get_value("controller", "vibration")
	for player in PLAYERS:
		if not _config.has_section_key("controller", player + "_vibration"):
			_config.set_value("controller", player + "_vibration", enabled)
	_config.erase_section_key("controller", "vibration")

## Rumbles player [param player_id]'s controller (P1's for 0, P2's for 1) if it
## is plugged in and that player has vibration on. [param weak] and
## [param strong] drive the light and heavy motors, 0 to 1.
func rumble(player_id: int, weak: float, strong: float, duration: float) -> void:
	if player_id < 0 or player_id >= PLAYERS.size() or not get_vibration(PLAYERS[player_id]):
		return
	rumbled.emit(player_id, weak, strong, duration)
	var device := get_pad_device(PLAYERS[player_id])
	if device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, weak, strong, duration)
