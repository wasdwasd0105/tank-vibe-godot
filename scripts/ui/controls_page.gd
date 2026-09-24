class_name ControlsPage
extends PanelContainer
## One player's controls page, shown by the title screen's settings and by the
## pause menu's: a KEYBOARD tab that rebinds the keys, and a GAMEPAD tab with the
## controller the player uses, MOVE / FIRE 1 / FIRE 2 in two slots each, and the
## buttons that never change. It handles its own input while shown and emits
## [signal closed] when the player backs out.
##
## Mouse: hovering focuses, clicking activates, right-clicking a slot empties it.
## Keyboard and controller: up / down move, left / right switch tabs, pick a slot
## or a controller, fire / A / Enter change the focused row, Esc or B goes back,
## and LB / RB switch tabs.

signal closed

enum Tab { KEYBOARD, GAMEPAD }

const TAB_TITLES: Array[String] = ["KEYBOARD", "GAMEPAD"]
## The GAMEPAD tab's rows for the buttons that never change: the row's name and
## the menu actions whose buttons it shows.
const PAD_FIXED_ROWS: Array = [["PAUSE", ["pause"]], ["MENU OK/BACK", ["ui_accept", "ui_cancel"]]]
const FIXED_ROW_TINT := Color(1, 1, 1, 0.5)

@onready var _title: Label = %Title
@onready var _rows: VBoxContainer = %Rows
@onready var _reset_button: Button = %ResetButton
@onready var _back_button: Button = %BackButton
@onready var _prompt: Label = %Prompt

var _nav: MenuFocus
var _player: String = "p1"
var _actions: Array[String] = []
var _tab_row: Button
var _tab: Tab = Tab.KEYBOARD
var _action_rows: Array[Button] = []     # KEYBOARD tab: a key per action
var _controller_row: Button              # GAMEPAD tab: which controller the player uses
var _pad_rows: Array[Button] = []        # GAMEPAD tab: MOVE, FIRE 1, FIRE 2, two slots each
var _fixed_pad_rows: Array[Button] = []  # GAMEPAD tab: the buttons that never change
var _pad_slot: int = 0                   # the slot picked along the GAMEPAD rows
## Waiting for input: the key's action ("p1_up"), or on the GAMEPAD tab the
## control ("move") whose _capture_slot is being set; "" when idle.
var _capture_action: String = ""
var _capture_slot: int = 0


func _ready() -> void:
	_nav = MenuFocus.new(get_viewport())
	_build_rows()
	for button: Button in [_reset_button, _back_button]:
		_focus_on_hover(button)
	_reset_button.pressed.connect(_reset)
	_back_button.pressed.connect(_close)
	# Both tabs' rows: the hidden tab's are skipped.
	var items: Array[Control] = [_tab_row]
	items.append_array(_action_rows)
	items.append(_controller_row)
	items.append_array(_pad_rows)
	items.append(_reset_button)
	items.append(_back_button)
	_nav.items = items
	visibility_changed.connect(_on_visibility_changed)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Shows [param player]'s controls, on the GAMEPAD tab when [param using_pad].
## Call it once the page is visible, so the first row can take the focus.
func open(player: String, using_pad: bool) -> void:
	_player = player
	_actions = InputSettings.get_player_actions(player)
	_title.text = "%s CONTROLS" % player.to_upper()
	_tab = Tab.GAMEPAD if using_pad else Tab.KEYBOARD
	_pad_slot = 0
	_capture_action = ""
	_refresh_rows()
	_set_prompt("")
	(_pad_rows[0] if _tab == Tab.GAMEPAD else _action_rows[0]).grab_focus()


## The player whose controls are shown.
func get_player() -> String:
	return _player


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _capture_action != "":
		_handle_capture_input(event)
		return
	if not MenuFocus.is_navigation_event(event):
		return
	# Backing out can hand the page back to a host that changes scene; keep the viewport.
	var viewport := get_viewport()
	if _is_tab_shortcut(event):
		_select_tab(Tab.KEYBOARD if event.button_index == JOY_BUTTON_LEFT_SHOULDER else Tab.GAMEPAD)
	elif _is_empty_shortcut(event) and _nav.focus_owner() in _pad_rows:
		_empty_pad_slot(_pad_rows.find(_nav.focus_owner()), _pad_slot)
	elif MenuFocus.is_pressed(event, MenuFocus.UP_ACTIONS):
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
		_close()
	else:
		return
	viewport.set_input_as_handled()


# =====================================================================
# Building
# =====================================================================

## The KEYBOARD / GAMEPAD tabs, then the KEYBOARD tab's row per action, or the
## GAMEPAD tab's controller choice, rows of two slots and its fixed buttons.
## Both tabs have six rows, so the page keeps its size.
func _build_rows() -> void:
	_tab_row = MenuRows.make_tab_row(TAB_TITLES, "LB", "RB")
	var layout := _rows.get_parent()
	layout.add_child(_tab_row)
	layout.move_child(_tab_row, _rows.get_index())
	_focus_on_hover(_tab_row)
	_tab_row.pressed.connect(_toggle_tab)
	for i in TAB_TITLES.size():
		var tab := MenuRows.tab(_tab_row, i)
		tab.pressed.connect(_select_tab.bind(i))
		tab.mouse_entered.connect(_tab_row.grab_focus)
	for i in InputSettings.ACTION_DISPLAY_NAMES.size():
		var row := MenuRows.make_keycap_row(InputSettings.ACTION_DISPLAY_NAMES[i])
		_rows.add_child(row)
		_focus_on_hover(row)
		row.pressed.connect(_begin_capture.bind(i))
		_action_rows.append(row)
	_controller_row = MenuRows.make_value_row("CONTROLLER")
	_rows.add_child(_controller_row)
	_focus_on_hover(_controller_row)
	_controller_row.pressed.connect(_cycle_pad_device.bind(1))
	for side: String in ["Left", "Right"]:
		var arrow := MenuRows.arrow(_controller_row, side)
		arrow.pressed.connect(_cycle_pad_device.bind(-1 if side == "Left" else 1))
		arrow.mouse_entered.connect(_controller_row.grab_focus)
	for i in InputSettings.PAD_CONTROLS.size():
		var row := MenuRows.make_slot_row(InputSettings.PAD_CONTROL_NAMES[i], InputSettings.PAD_SLOTS)
		_rows.add_child(row)
		_focus_on_hover(row)
		row.pressed.connect(_on_pad_row_pressed.bind(i))
		row.focus_entered.connect(_refresh_slot_highlight)
		row.focus_exited.connect(_refresh_slot_highlight)
		for slot in InputSettings.PAD_SLOTS:
			var slot_button := MenuRows.slot(row, slot)
			slot_button.mouse_entered.connect(_hover_pad_slot.bind(row, slot))
			slot_button.pressed.connect(_begin_pad_capture.bind(i, slot))
			slot_button.gui_input.connect(_on_slot_gui_input.bind(i, slot))
		_pad_rows.append(row)
	for fixed: Array in PAD_FIXED_ROWS:
		var row := MenuRows.make_keycap_row(fixed[0])
		for i in fixed[1].size():
			var keycap := MenuRows.value_label(row) if i == 0 else MenuRows.add_keycap(row, "")
			keycap.text = InputSettings.get_pad_name("b%d" % InputSettings.MENU_PAD_BUTTONS[fixed[1][i]])
			keycap.custom_minimum_size.x = MenuRows.SLOT_WIDTH
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.modulate = FIXED_ROW_TINT
		_rows.add_child(row)
		_fixed_pad_rows.append(row)


## Hovering a button focuses it, so mouse and keyboard share one highlight.
func _focus_on_hover(button: Button) -> void:
	button.mouse_entered.connect(button.grab_focus)


# =====================================================================
# Showing the rows
# =====================================================================

## Shows the active tab's rows with what they hold now, "..." where one waits.
func _refresh_rows() -> void:
	_refresh_tabs()
	var pad := _tab == Tab.GAMEPAD
	_reset_button.text = "RESET BUTTONS" if pad else "RESET KEYS"
	for row in _action_rows:
		row.visible = not pad
	for row in [_controller_row] + _pad_rows + _fixed_pad_rows:
		row.visible = pad
	var device := InputSettings.get_pad_device(_player)
	MenuRows.value_label(_controller_row).text = "%d   ·   %s" % [device + 1,
			Input.get_joy_name(device) if device in Input.get_connected_joypads() else "not plugged in"]
	if _actions.size() == _action_rows.size():
		for i in _action_rows.size():
			var action := _actions[i]
			MenuRows.value_label(_action_rows[i]).text = "..." if action == _capture_action \
					else InputSettings.get_key_name(action)
	for i in _pad_rows.size():
		var control: String = InputSettings.PAD_CONTROLS[i]
		for slot in InputSettings.PAD_SLOTS:
			var waiting := control == _capture_action and slot == _capture_slot
			MenuRows.slot(_pad_rows[i], slot).text = "..." if waiting \
					else InputSettings.get_pad_name(InputSettings.get_pad_slot(_player, control, slot))
	_refresh_slot_highlight()


## The active tab looks pressed; the LB / RB keycaps show while a controller is
## plugged in.
func _refresh_tabs() -> void:
	for i in TAB_TITLES.size():
		MenuRows.tab(_tab_row, i).set_pressed_no_signal(i == _tab)
	var pad_connected := not Input.get_connected_joypads().is_empty()
	MenuRows.tab_hint(_tab_row, "Prev").visible = pad_connected
	MenuRows.tab_hint(_tab_row, "Next").visible = pad_connected


## The picked slot on the focused GAMEPAD row gets a gold outline; a slot
## waiting for its input is solid gold, and while one waits no other is marked,
## wherever the mouse wanders.
func _refresh_slot_highlight() -> void:
	var waiting := _capture_action in InputSettings.PAD_CONTROLS
	for i in _pad_rows.size():
		for slot in InputSettings.PAD_SLOTS:
			var slot_button := MenuRows.slot(_pad_rows[i], slot)
			var picked := not waiting and _pad_rows[i].has_focus() and _pad_slot == slot
			slot_button.set_pressed_no_signal(waiting and _capture_action == InputSettings.PAD_CONTROLS[i] \
					and _capture_slot == slot)
			slot_button.theme_type_variation = &"KeycapButtonPicked" if picked else &"KeycapButton"


## Shows [param text] under the rows; empty shows how to rebind on this tab and,
## on the GAMEPAD tab, which controller the player uses.
func _set_prompt(text: String) -> void:
	if text.is_empty():
		if _tab == Tab.GAMEPAD:
			text = "A / click: change   ·   %s / Delete / right-click: empty\n%s" % [_view_button_name(), _pad_status_text()]
		else:
			text = "Click a row, or press fire on it, to change that key."
	_prompt.text = text


## Which controller this page's player uses and whether it is plugged in, and
## with it missing while the other player's is in, how to share that one.
func _pad_status_text() -> String:
	var who := _player.to_upper()
	var device := InputSettings.get_pad_device(_player)
	var plugged := device in Input.get_connected_joypads()
	var partner := InputSettings.get_pad_partner(_player)
	if partner != "":
		return "%s shares controller %d with %s%s" % [who, device + 1, partner.to_upper(),
				(":  " + Input.get_joy_name(device)) if plugged else ", which is not plugged in."]
	if plugged:
		return "%s plays on controller %d:  %s" % [who, device + 1, Input.get_joy_name(device)]
	var other := "p2" if _player == "p1" else "p1"
	var other_device := InputSettings.get_pad_device(other)
	if other_device in Input.get_connected_joypads():
		return "Controller %d is not plugged in: pick %d to share %s's." % [device + 1, other_device + 1, other.to_upper()]
	return "Controller %d is not plugged in." % (device + 1)


# =====================================================================
# Navigating the page
# =====================================================================

func _close() -> void:
	_cancel_capture()
	closed.emit()


func _on_visibility_changed() -> void:
	if not visible:
		_capture_action = ""   # a wait ends quietly when the page goes away


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	if not is_visible_in_tree():
		return
	_refresh_rows()
	if _capture_action == "":
		_set_prompt("")


## Left / right: the tab strip switches tabs, the CONTROLLER row picks the
## controller, and a GAMEPAD row picks its slot.
func _adjust(direction: int) -> void:
	var focused := _nav.focus_owner()
	if focused == _tab_row:
		_select_tab(Tab.KEYBOARD if direction < 0 else Tab.GAMEPAD)
	elif focused == _controller_row:
		_cycle_pad_device(direction)
	elif focused in _pad_rows:
		_pad_slot = clampi(_pad_slot + direction, 0, InputSettings.PAD_SLOTS - 1)
		_refresh_slot_highlight()


## Switches tabs. A focused row hands the focus to its counterpart on the other
## tab: UP to RIGHT go with MOVE, and each fire button with itself.
func _select_tab(tab: int) -> void:
	if tab == _tab and _capture_action == "":
		_refresh_tabs()  # a click on the active tab toggled it off
		return
	var focused := _nav.focus_owner()
	var key_row := _action_rows.find(focused)
	var pad_row := 0 if focused == _controller_row else _pad_rows.find(focused)
	_cancel_capture()
	_tab = tab as Tab
	_refresh_rows()
	_set_prompt("")
	if key_row >= 0 and _tab == Tab.GAMEPAD:
		var suffix: String = InputSettings.PLAYER_ACTION_SUFFIXES[key_row]
		_pad_rows[InputSettings.PAD_CONTROLS.find("move" if suffix in InputSettings.MOVE_DIRECTIONS else suffix)].grab_focus()
	elif pad_row >= 0 and _tab == Tab.KEYBOARD:
		var control: String = InputSettings.PAD_CONTROLS[pad_row]
		_action_rows[InputSettings.PLAYER_ACTION_SUFFIXES.find("up" if control == "move" else control)].grab_focus()


func _toggle_tab() -> void:
	_select_tab(Tab.GAMEPAD if _tab == Tab.KEYBOARD else Tab.KEYBOARD)


## LB or RB pressed on a controller: they pick the left or right tab.
func _is_tab_shortcut(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.pressed \
			and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]


## View on a controller, or Delete / Backspace: empties the slot.
func _is_empty_shortcut(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_BACK
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode in [KEY_DELETE, KEY_BACKSPACE]
	return false


## Hovering a slot focuses its row and picks that slot.
func _hover_pad_slot(row: Button, slot: int) -> void:
	_pad_slot = slot
	row.grab_focus()
	_refresh_slot_highlight()


func _on_pad_row_pressed(index: int) -> void:
	_begin_pad_capture(index, _pad_slot)


## A right-click on a slot empties it.
func _on_slot_gui_input(event: InputEvent, index: int, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		MenuRows.slot(_pad_rows[index], slot).accept_event()
		_empty_pad_slot(index, slot)


# =====================================================================
# Changing the bindings
# =====================================================================

## Resets the tab shown: the keys, or the controller buttons.
func _reset() -> void:
	_cancel_capture()
	if _tab == Tab.GAMEPAD:
		InputSettings.reset_pad_to_defaults(_player)
		if InputSettings.is_pad_shared():
			_set_prompt("P1 and P2 are back on their halves of controller %d."
					% (InputSettings.get_pad_device(_player) + 1))
		else:
			_set_prompt("%s controller reset to defaults." % _player.to_upper())
	else:
		InputSettings.reset_to_defaults(_player)
		_set_prompt("%s keys reset to defaults." % _player.to_upper())
	_refresh_rows()


## The CONTROLLER row: puts this page's player on the other controller. Sharing
## one starts both players on their halves of it; parting gives each a whole
## layout again.
func _cycle_pad_device(direction: int) -> void:
	_cancel_capture()
	var was_shared := InputSettings.is_pad_shared()
	var device := wrapi(InputSettings.get_pad_device(_player) + direction, 0, InputSettings.PAD_DEVICE_COUNT)
	InputSettings.set_pad_device(_player, device)
	_refresh_rows()
	if InputSettings.is_pad_shared() and not was_shared:
		_set_prompt("P1 and P2 now share controller %d: P1 has its left half, P2 its right." % (device + 1))
	elif was_shared and not InputSettings.is_pad_shared():
		_set_prompt("P1 and P2 have controllers of their own: each has the whole layout again.")
	else:
		_set_prompt("")


## Empties [param slot] of the GAMEPAD row [param index] (the row's other input
## moves up into the first slot), ending any wait.
func _empty_pad_slot(index: int, slot: int) -> void:
	var control: String = InputSettings.PAD_CONTROLS[index]
	var old := InputSettings.get_pad_slot(_player, control, slot)
	InputSettings.set_pad_slot(_player, control, slot, "")
	_capture_action = ""
	_pad_slot = slot
	_refresh_rows()
	if old == "":
		_set_prompt("")
	else:
		_set_prompt("%s no longer uses %s." % [_pad_control_name(control), InputSettings.get_pad_name(old)])


## KEYBOARD tab: waits for the key of the action in row [param index].
func _begin_capture(index: int) -> void:
	_capture_action = _actions[index]
	_refresh_rows()
	_set_prompt("Press a key for %s   (Esc or B cancels)" % InputSettings.ACTION_DISPLAY_NAMES[index])


## GAMEPAD tab: waits for what goes in [param slot] of the control in row
## [param index].
func _begin_pad_capture(index: int, slot: int) -> void:
	_capture_action = InputSettings.PAD_CONTROLS[index]
	_capture_slot = slot
	_pad_slot = slot
	_refresh_rows()
	_set_prompt(_pad_capture_prompt())


func _cancel_capture() -> void:
	if _capture_action == "":
		return
	_capture_action = ""
	_refresh_rows()
	_set_prompt("")


## Waiting for the new key or controller input. Mouse events pass through, so a
## click on another row, a tab or BACK still works.
func _handle_capture_input(event: InputEvent) -> void:
	if _tab == Tab.GAMEPAD:
		_handle_pad_capture(event)
	else:
		_handle_key_capture(event)


## KEYBOARD tab: the next key pressed is the new key. On a controller B or Start
## backs out, and nothing else does anything meanwhile.
func _handle_key_capture(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		MenuFocus.stick_pushed(event)  # keeps the stick's held state true
		return
	if event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		if event.pressed and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START]:
			_cancel_capture()
		return
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	var physical_key: Key = (event as InputEventKey).physical_keycode
	if physical_key == KEY_NONE:
		return
	if physical_key == KEY_ESCAPE:
		_cancel_capture()
		return
	if physical_key == KEY_F11:
		_set_prompt("F11 is reserved for fullscreen. Press another key.")
		return
	if physical_key == KEY_BACKSLASH or physical_key == KEY_QUOTELEFT:
		_set_prompt("%s is reserved for a debug key. Press another key." % ("\\" if physical_key == KEY_BACKSLASH else "`"))
		return
	var action := _capture_action
	var conflict := _find_conflicting_action(physical_key, action)
	InputSettings.save_binding(action, physical_key)
	_capture_action = ""
	_refresh_rows()
	if conflict != "":
		_set_prompt("%s bound. Note: it is also used by %s." % [InputSettings.get_key_name(action), conflict])
	else:
		_set_prompt("")


## GAMEPAD tab: the next button pressed, or stick or trigger pushed past
## halfway, fills the slot if it fits there: the D-pad or a stick for MOVE, a
## button or a trigger to fire. View or Delete empties the slot, Start or Esc
## backs out, and no other key does anything meanwhile.
func _handle_pad_capture(event: InputEvent) -> void:
	if _is_empty_shortcut(event):
		get_viewport().set_input_as_handled()
		_empty_pad_slot(InputSettings.PAD_CONTROLS.find(_capture_action), _capture_slot)
		return
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			_cancel_capture()
		return
	if event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		if not event.pressed:
			return
		if event.button_index == JOY_BUTTON_START:
			_cancel_capture()
			return
	elif event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		if not MenuFocus.stick_pushed(event):
			return  # a stick already held when the wait began counts once it is let go
	else:
		return
	var code := InputSettings.pad_code_for(event)
	if InputSettings.is_pad_code_reserved(code):
		_set_prompt("%s belongs to the system. Press another.\n%s" % [InputSettings.get_pad_name(code), _pad_capture_hint()])
		return
	var value := InputSettings.pad_value_for(_capture_action, event)
	if value == "":
		var takes := "the D-pad or a stick" if _capture_action == "move" else "a button or a trigger"
		_set_prompt("%s takes %s.\n%s" % [_pad_control_name(_capture_action), takes, _pad_capture_hint()])
		return
	_finish_pad_capture(value)


## Puts [param value] in the waiting slot and says what else moved to make room.
func _finish_pad_capture(value: String) -> void:
	var control := _capture_action
	var old := InputSettings.get_pad_slot(_player, control, _capture_slot)
	var moved := InputSettings.set_pad_slot(_player, control, _capture_slot, value)
	_capture_action = ""
	_refresh_rows()
	if moved.is_empty():
		_set_prompt("")
	elif moved["player"] == _player and moved["control"] == control:
		_set_prompt("The two %s slots swapped." % _pad_control_name(control))
	elif old == "":
		_set_prompt("%s no longer uses %s." % [_moved_name(moved), InputSettings.get_pad_name(value)])
	else:
		_set_prompt("%s had %s, so it takes %s instead." % [_moved_name(moved),
				InputSettings.get_pad_name(value), InputSettings.get_pad_name(old)])


## "FIRE 2" for another of this player's controls, "P2 FIRE 1" for the other
## player's, sharing the controller.
func _moved_name(moved: Dictionary) -> String:
	var control_name := _pad_control_name(moved["control"])
	return control_name if moved["player"] == _player else "%s %s" % [moved["player"].to_upper(), control_name]


func _pad_capture_prompt() -> String:
	var what := "Press the D-pad, or push a stick," if _capture_action == "move" \
			else "Press a button, or pull a trigger,"
	return "%s for %s\n%s" % [what, _pad_control_name(_capture_action), _pad_capture_hint()]


func _pad_capture_hint() -> String:
	return "%s or Delete empties it   ·   Start or Esc cancels" % _view_button_name()


## The controller button that empties a slot, by its name on the pad ("View").
func _view_button_name() -> String:
	return InputSettings.get_pad_name("b%d" % JOY_BUTTON_BACK)


## "FIRE 1" for "shoot".
func _pad_control_name(control: String) -> String:
	return InputSettings.PAD_CONTROL_NAMES[InputSettings.PAD_CONTROLS.find(control)]


## Display name ("P2 FIRE 1") of another action already using [param physical_key], or "".
func _find_conflicting_action(physical_key: int, action: String) -> String:
	for other: String in InputSettings.DEFAULTS:
		if other == action or InputSettings.get_binding(other) != physical_key:
			continue
		return "%s %s" % [other.get_slice("_", 0).to_upper(), _action_display_name(other)]
	return ""


## "FIRE 2" for "p1_shoot2".
func _action_display_name(action: String) -> String:
	var index := InputSettings.PLAYER_ACTION_SUFFIXES.find(action.get_slice("_", 1))
	return InputSettings.ACTION_DISPLAY_NAMES[index] if index >= 0 else action
