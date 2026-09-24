class_name MenuFocus
extends RefCounted
## Keyboard and controller navigation helper shared by the menu screens.
##
## Keeps an ordered list of focusable controls and moves the viewport focus
## through it, skipping hidden or disabled entries. It also groups the game's
## input actions so every screen accepts the same keys: P1/P2 movement keys,
## arrows, fire, Enter/Space and Esc, and on a controller the D-pad or the
## players' sticks, A or the fire buttons, and B or Start to go back.

const UP_ACTIONS: Array[String] = ["p1_up", "p2_up", "ui_up"]
const DOWN_ACTIONS: Array[String] = ["p1_down", "p2_down", "ui_down"]
const LEFT_ACTIONS: Array[String] = ["p1_left", "p2_left", "ui_left"]
const RIGHT_ACTIONS: Array[String] = ["p1_right", "p2_right", "ui_right"]
const ACCEPT_ACTIONS: Array[String] = ["p1_shoot", "p2_shoot", "p1_shoot2", "p2_shoot2", "ui_accept", "ui_select"]
const BACK_ACTIONS: Array[String] = ["pause", "ui_cancel"]

## Ordered controls the up/down keys cycle through.
var items: Array[Control] = []
## Controls that stand in for one of [member items] during navigation
## (e.g. a save row's DELETE button counts as its row).
var aliases: Dictionary = {}

## A stick (or trigger) counts as pressed once it leans this far...
const STICK_PRESS: float = 0.5
## ...and must come back inside this before it can press again.
const STICK_RELEASE: float = 0.3
## "device:axis" -> the way that axis is held (-1, 0 or 1).
static var _stick_held: Dictionary = {}
static var _stick_event_id: int = 0
static var _stick_event_pressed: bool = false

var _viewport: Viewport


func _init(viewport: Viewport) -> void:
	_viewport = viewport


## True when [param event] is a fresh (non-echo) press of any of [param actions].
## A controller's A, B and Start only ever do their menu job (confirm, back,
## pause), whatever the players have bound them to in the game.
static func is_pressed(event: InputEvent, actions: Array[String]) -> bool:
	if event.is_echo():
		return false
	if event is InputEventJoypadMotion and not stick_pushed(event):
		return false
	var menu_job := _menu_job(event)
	for action in actions:
		if menu_job != "" and action != menu_job:
			continue
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


## The menu action a controller button is kept for ("ui_accept" for A...), or "".
static func _menu_job(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var buttons: Dictionary = InputSettings.MENU_PAD_BUTTONS
		for action: String in buttons:
			if buttons[action] == event.button_index:
				return action
	return ""


## True for the key, joypad button and stick events the menus navigate with.
static func is_navigation_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion


## What [param event] says about the device driving the menus: 1 a controller,
## 0 the keyboard or mouse, -1 nothing (a release, a stick barely moved, the
## mouse only moving).
static func device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return 1 if event.pressed else -1
	if event is InputEventJoypadMotion:
		return 1 if absf(event.axis_value) >= STICK_PRESS else -1
	if (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		return 0
	return -1


## A stick streams motion events while it is held, so it only counts once per
## push, like a button: when it first leans past STICK_PRESS, and not again
## until it has come back inside STICK_RELEASE. Worked out once per event; every
## motion event should pass through here so the held state stays true.
static func stick_pushed(event: InputEventJoypadMotion) -> bool:
	if event.get_instance_id() == _stick_event_id:
		return _stick_event_pressed
	_stick_event_id = event.get_instance_id()
	var key := "%d:%d" % [event.device, event.axis]
	var held: int = _stick_held.get(key, 0)
	var way := held
	if absf(event.axis_value) >= STICK_PRESS:
		way = 1 if event.axis_value > 0.0 else -1
	elif absf(event.axis_value) <= STICK_RELEASE:
		way = 0
	_stick_held[key] = way
	_stick_event_pressed = way != 0 and way != held
	return _stick_event_pressed


func focus_owner() -> Control:
	return _viewport.gui_get_focus_owner()


## Index of the focused control (or its alias) in [member items], or -1.
func current_index() -> int:
	var focused := focus_owner()
	if focused == null:
		return -1
	if aliases.has(focused):
		focused = aliases[focused]
	return items.find(focused)


## Moves the focus [param direction] steps (+1 down, -1 up), wrapping around.
func move(direction: int) -> void:
	var count := items.size()
	if count == 0:
		return
	var index := current_index()
	if index == -1:
		index = -1 if direction > 0 else count
	for _step in count:
		index = wrapi(index + direction, 0, count)
		if _selectable(items[index]):
			items[index].grab_focus()
			return


func focus_first() -> void:
	for item in items:
		if _selectable(item):
			item.grab_focus()
			return


## Presses the focused button if it belongs to this menu. Returns false otherwise.
func activate() -> bool:
	var focused := focus_owner()
	if focused is BaseButton and not focused.disabled and (items.has(focused) or aliases.has(focused)):
		focused.pressed.emit()
		return true
	return false


func _selectable(control: Control) -> bool:
	if not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return false
	return not (control is BaseButton and control.disabled)
