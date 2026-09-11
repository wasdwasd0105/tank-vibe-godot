class_name MenuFocus
extends RefCounted
## Keyboard navigation helper shared by the menu screens.
##
## Keeps an ordered list of focusable controls and moves the viewport focus
## through it, skipping hidden or disabled entries. It also groups the game's
## input actions so every screen accepts the same keys: P1/P2 movement keys,
## arrows, fire, Enter/Space and Esc.

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

var _viewport: Viewport


func _init(viewport: Viewport) -> void:
	_viewport = viewport


## True when [param event] is a fresh (non-echo) press of any of [param actions].
static func is_pressed(event: InputEvent, actions: Array[String]) -> bool:
	if event.is_echo():
		return false
	for action in actions:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


## True for the key and joypad button events the menus navigate with.
static func is_navigation_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventJoypadButton


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
