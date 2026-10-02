extends Control
## Title -> ONLINE BATTLE: the games this player connects to, kept like
## bookmarks so joining one again is a click (docs/network_design.md). Each
## connection is the name to play as, the host's address ("IP", or "IP:PORT"
## when the host's port isn't the game's own) and the game's password, if it has
## one.
##
## Mouse: click a connection to join its game. MORE pops up its options under
## it: CONNECT joins, EDIT opens it in the connection window, DELETE and then
## CONFIRM? removes it. CREATE opens the connection window for a new one:
## USERNAME, ADDRESS, PASSWORD (optional) and JOIN, which keeps it at the top of
## the list and joins. Joining, the hint line says how it goes, and why when it
## fails; a game that ended under this player says why here too.
## Keyboard / controller: as on Load Game. Up/down move through the connections
## and the footer, right goes from a connection to its MORE and left comes back
## (and moves between CREATE and BACK), fire / Enter / A activate, Esc / B close
## a window or go back (and stop a join under way). In the connection window a
## field takes typing after a click, or fire or Enter on its row; Enter moves on
## to the next field and Esc hands the keys back.
##
## Hosting isn't here: a game is opened to others from its pause menu
## (SETTINGS, the ONLINE tab).

const TITLE_SCENE := "res://scenes/main.tscn"
const MORE_TEXT := "MORE"
const CONNECT_TEXT := "CONNECT"
const EDIT_TEXT := "EDIT"
const DELETE_TEXT := "DELETE"
const CONFIRM_TEXT := "CONFIRM?"
const DEFAULT_HINT := "Click a connection to join its game   ·   MORE connects, edits or deletes it   ·   Esc goes back"
const OPTIONS_HINT := "CONNECT joins its game   ·   EDIT changes it   ·   DELETE removes it   ·   Esc closes"
const CONFIRM_HINT := "Press CONFIRM? again to delete this connection. Moving away cancels."
const FORM_HINT := "Click a field, or press Enter on it, to type   ·   Enter moves on   ·   Esc closes"
const FORM_NOTE := "ADDRESS: the host's IP address or name, with :PORT if its port isn't %d"
const CREATE_TITLE := "NEW CONNECTION"
const EDIT_TITLE := "EDIT CONNECTION"
const PASSWORD_SAVED_TEXT := "PASSWORD SAVED"
const NOT_JOINED_TEXT := "NOT JOINED YET"
const JOINED_TEXT := "JOINED %s"
const ROW_HEIGHT := 84.0
const ADDRESS_WIDTH := 430.0
const JOINED_WIDTH := 270.0
const MORE_WIDTH := 130.0
## The options window: its width, its gap from MORE, and how much it dims the rest.
const POPUP_WIDTH := 300.0
const POPUP_GAP := 8.0
const POPUP_DIM := Color(0, 0, 0, 0.35)
## The connection window: its width, and how much it dims the list.
const FORM_WIDTH := 860.0
const FORM_DIM := Color(0, 0, 0, 0.55)
const ADDRESS_MAX := 270
const PASSWORD_MAX := 32
const ERROR_COLOR := Color(1.0, 0.5, 0.45)

@onready var _scroll: ScrollContainer = %ConnectionScroll
@onready var _list: VBoxContainer = %ConnectionList
@onready var _empty_label: Label = %EmptyLabel
@onready var _create_button: Button = %CreateButton
@onready var _back_button: Button = %BackButton
@onready var _hint: Label = %Hint

var _nav: MenuFocus
## The saved connections, most recently used first (see
## InputSettings.get_online_connections).
var _connections: Array[Dictionary] = []
var _rows: Array[Button] = []
var _more_buttons: Array[Button] = []
## What up/down walk through while no window is open: the connections and the footer.
var _main_items: Array[Control] = []
# Horizontal keyboard neighbours: control -> the control to its right / left.
var _right_of: Dictionary = {}
var _left_of: Dictionary = {}

# The options window, one for every connection: a layer that dims the screen
# and catches clicks outside, the window on it, its title and its buttons.
var _popup_layer: Control
var _popup: PanelContainer
var _popup_title: Label
var _popup_buttons: Array[Button] = []  # CONNECT, EDIT, DELETE
var _delete_button: Button
var _popup_index := -1           # the connection the window is open for
var _open_more: Button = null    # and the MORE button that opened it
var _pending_delete := false

# The connection window CREATE and EDIT open, over a layer that dims the list.
var _form_layer: Control
var _form_title: Label
var _name_row: Button
var _address_row: Button
var _password_row: Button
var _form_note: Label
var _submit_button: Button       # JOIN, or SAVE when editing
var _cancel_button: Button
var _form_items: Array[Control] = []
var _form_index := -1            # the connection EDIT opened; -1 for CREATE's new one
## Each field row's LineEdit.
var _fields: Dictionary = {}
var _editing: LineEdit = null

## The connection being joined, until it gets in or fails.
var _joining: Dictionary = {}


func _ready() -> void:
	WindowManager.leave_game()  # the menus stay in the window
	get_tree().paused = false
	_nav = MenuFocus.new(get_viewport())
	_create_button.pressed.connect(_open_form.bind(-1))
	_back_button.pressed.connect(_go_back)
	for button: Button in [_create_button, _back_button]:
		_focus_on_hover(button)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	Net.join_failed.connect(_on_join_failed)
	Net.join_succeeded.connect(_on_join_succeeded)
	_build_popup()
	_build_form()
	_rebuild_list(0)
	# A game that ended under this player (the host left, a kick, a lost line).
	var reason := Net.take_end_reason()
	if not reason.is_empty():
		_set_hint(Net.end_text(reason), true)


func _input(event: InputEvent) -> void:
	if _editing != null:
		_edit_input(event)
		return
	if not MenuFocus.is_navigation_event(event):
		return
	# Going back changes scene, which removes this node from the tree at once
	# (get_viewport() then returns null), so keep the viewport.
	var viewport := get_viewport()
	if MenuFocus.is_pressed(event, MenuFocus.UP_ACTIONS):
		_nav.move(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.DOWN_ACTIONS):
		_nav.move(1)
	elif MenuFocus.is_pressed(event, MenuFocus.RIGHT_ACTIONS):
		_focus_neighbour(_right_of)
	elif MenuFocus.is_pressed(event, MenuFocus.LEFT_ACTIONS):
		if _open_more:
			_close_options(true)
		else:
			_focus_neighbour(_left_of)
	elif MenuFocus.is_pressed(event, MenuFocus.ACCEPT_ACTIONS):
		_nav.activate()
	elif MenuFocus.is_pressed(event, MenuFocus.BACK_ACTIONS):
		if _pending_delete:
			_set_pending_delete(false)
		elif _open_more:
			_close_options(true)
		elif _form_layer.visible:
			_close_form(true)
		else:
			_go_back()
	else:
		return
	viewport.set_input_as_handled()


## While a field is being typed in, it has the keys: only Esc (or any pad
## button) hands them back, and Tab / Shift+Tab move to the next / last field.
func _edit_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or (event is InputEventJoypadButton and event.pressed):
		_end_edit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_edit_next(-1 if event.shift_pressed else 1, true)
	else:
		return
	get_viewport().set_input_as_handled()


## Moves the focus to the focused control's entry in [param neighbours], if any.
func _focus_neighbour(neighbours: Dictionary) -> void:
	var target: Control = neighbours.get(_nav.focus_owner())
	if target:
		target.grab_focus()


## Hovering takes the focus, as everywhere in the menus, unless a field is
## being typed in: that would take the keys away from it.
func _focus_on_hover(control: Control) -> void:
	control.mouse_entered.connect(func() -> void:
		if _editing == null:
			control.grab_focus())


# =====================================================================
# The list
# =====================================================================

func _rebuild_list(focus_index: int) -> void:
	_close_options(false)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_more_buttons.clear()
	_nav.aliases.clear()
	_right_of.clear()
	_left_of.clear()
	_set_hint(DEFAULT_HINT)

	_connections = InputSettings.get_online_connections()
	_connections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["used"] > b["used"])
	for info: Dictionary in _connections:
		_add_connection_entry(info)

	_empty_label.visible = _connections.is_empty()
	_scroll.visible = not _connections.is_empty()
	_right_of[_create_button] = _back_button
	_left_of[_back_button] = _create_button
	_right_of[_submit_button] = _cancel_button
	_left_of[_cancel_button] = _submit_button
	_nav.aliases[_cancel_button] = _submit_button  # up and down go from either button
	_main_items.assign(_rows)
	_main_items.append(_create_button)
	_main_items.append(_back_button)
	_nav.items = _main_items
	SoundManager.attach_ui_sounds(self)
	if _rows.is_empty():
		_create_button.grab_focus()
	else:
		_rows[clampi(focus_index, 0, _rows.size() - 1)].grab_focus()


## One connection: its row (the address; the name and whether a password is
## kept; when it last got in), and the MORE button beside it.
func _add_connection_entry(info: Dictionary) -> void:
	var index := _rows.size()
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 10)
	_list.add_child(entry)

	var row := MenuRows.make_row(ROW_HEIGHT)
	var layout := MenuRows.layout_of(row)
	layout.add_child(_make_label(info["address"], &"RowNameLabel", ADDRESS_WIDTH, false, true))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.add_child(_make_label(info["name"], &"ValueLabel", 0, true, true))
	if not str(info["password"]).is_empty():
		column.add_child(_make_label(PASSWORD_SAVED_TEXT, &"HintLabel", 0, true))
	layout.add_child(column)
	var joined := _make_label(_joined_text(info), &"HintLabel", JOINED_WIDTH)
	joined.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layout.add_child(joined)
	row.pressed.connect(_connect_to.bind(index))
	_focus_on_hover(row)
	entry.add_child(row)

	var more := _make_row_button(MORE_TEXT, &"RowActionButton", MORE_WIDTH)
	more.toggle_mode = true  # shown pressed while its window is open
	more.pressed.connect(_toggle_options.bind(index))
	entry.add_child(more)

	# MORE stands in for its row when moving up and down.
	_nav.aliases[more] = row
	_right_of[row] = more
	_left_of[more] = row
	_rows.append(row)
	_more_buttons.append(more)


## "JOINED 2026-10-01  14:30", or NOT JOINED YET.
func _joined_text(info: Dictionary) -> String:
	var joined: String = info["joined"]
	if joined.length() < 16:
		return tr(NOT_JOINED_TEXT)
	return tr(JOINED_TEXT) % (joined.substr(0, 10) + "  " + joined.substr(11, 5))


func _make_row_button(text: String, variation: StringName, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(min_width, 0)
	_focus_on_hover(button)
	return button


## [param players_text]: the text is the player's own (an address, a name), shown
## as typed and never translated.
func _make_label(text: String, variation: StringName, min_width: float, expand: bool = false,
		players_text: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size = Vector2(min_width, 0)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if players_text:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


func _save_connections() -> void:
	InputSettings.save_online_connections(_connections)


# =====================================================================
# The options window MORE opens
# =====================================================================

## Builds the window, hidden: a panel titled with the connection's address over
## a layer that dims the screen and closes the window when clicked.
func _build_popup() -> void:
	_popup_layer = _make_layer("OptionsLayer", POPUP_DIM)
	_popup_layer.gui_input.connect(_on_popup_layer_input)
	_popup = _make_window("OptionsWindow", 14.0)
	_popup.custom_minimum_size = Vector2(POPUP_WIDTH, 0)
	_popup_layer.add_child(_popup)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_popup.add_child(column)
	_popup_title = _make_label("", &"HintLabel", 0, false, true)
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_popup_title)
	for option: Array in [[CONNECT_TEXT, &"RowActionButton", _on_connect_pressed],
			[EDIT_TEXT, &"RowActionButton", _on_edit_pressed],
			[DELETE_TEXT, &"DangerButton", _on_delete_pressed]]:
		var button := _make_row_button(option[0], option[1], 0)
		button.pressed.connect(option[2])
		column.add_child(button)
		_popup_buttons.append(button)
	_delete_button = _popup_buttons[2]
	_delete_button.focus_exited.connect(_on_delete_focus_exited)


## A full-screen layer, hidden, that dims what is under it with [param dim] and
## takes the clicks.
func _make_layer(layer_name: String, dim: Color) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.visible = false
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = dim
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	return layer


## A window: the menu panel, gold-edged, with [param margin] inside.
func _make_window(window_name: String, margin: float) -> PanelContainer:
	var window := PanelContainer.new()
	window.name = window_name
	window.theme_type_variation = &"MenuPanel"
	var style := (get_theme_stylebox(&"panel", &"MenuPanel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.set_content_margin_all(margin)
	style.bg_color.a = 0.98
	style.border_color = Color(0.98, 0.78, 0.22)
	window.add_theme_stylebox_override(&"panel", style)
	return window


## Opens the window for connection [param index], or closes it if it is open for it.
func _toggle_options(index: int) -> void:
	var more := _more_buttons[index]
	if _open_more == more:
		_close_options(true)
		return
	if _busy():
		more.set_pressed_no_signal(false)
		return
	_close_options(false)
	_open_more = more
	_popup_index = index
	_popup_title.text = _connections[index]["address"]
	more.set_pressed_no_signal(true)
	_popup_layer.visible = true
	_place_popup(more)
	# Up and down stay in the window while it is open.
	var buttons: Array[Control] = []
	buttons.assign(_popup_buttons)
	_nav.items = buttons
	_popup_buttons[0].grab_focus()
	_set_hint(OPTIONS_HINT)


## Right under [param more], lined up with its right edge; above it when there
## is no room below.
func _place_popup(more: Button) -> void:
	_popup.reset_size()
	var window_size := _popup.get_combined_minimum_size()
	var anchor := more.get_global_rect()
	var at := Vector2(anchor.end.x - window_size.x, anchor.end.y + POPUP_GAP)
	if at.y + window_size.y > get_viewport_rect().size.y - POPUP_GAP:
		at.y = anchor.position.y - POPUP_GAP - window_size.y
	_popup.position = at - _popup_layer.get_global_rect().position
	_popup.size = window_size


## Closes the window; [param refocus_more] puts the focus back on its MORE.
func _close_options(refocus_more: bool) -> void:
	if _open_more == null:
		return
	var more := _open_more
	_set_pending_delete(false)
	_popup_layer.visible = false
	_open_more = null
	_popup_index = -1
	_nav.items = _main_items
	_set_hint(DEFAULT_HINT)
	if is_instance_valid(more):
		more.set_pressed_no_signal(false)
		if refocus_more:
			more.grab_focus()


## A click anywhere outside the window closes it.
func _on_popup_layer_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_popup_layer.accept_event()
		_close_options(true)


## The focus leaving the window closes it.
func _on_focus_changed(control: Control) -> void:
	if _open_more == null or control == null or _popup.is_ancestor_of(control):
		return
	_close_options(false)


func _on_connect_pressed() -> void:
	_connect_to(_popup_index)


func _on_edit_pressed() -> void:
	_open_form(_popup_index)


## DELETE asks first: its first press turns it into CONFIRM?, the second deletes.
func _on_delete_pressed() -> void:
	if not _pending_delete:
		_set_pending_delete(true)
		return
	var index := _popup_index
	_connections.remove_at(index)
	_save_connections()
	_rebuild_list(index)


func _set_pending_delete(pending: bool) -> void:
	_pending_delete = pending
	_delete_button.text = CONFIRM_TEXT if pending else DELETE_TEXT
	if pending:
		_set_hint(CONFIRM_HINT)
	elif _open_more:
		_set_hint(OPTIONS_HINT)


func _on_delete_focus_exited() -> void:
	if _pending_delete:
		_set_pending_delete(false)


# =====================================================================
# The connection window CREATE and EDIT open
# =====================================================================

## Builds the window, hidden: its title, the USERNAME, ADDRESS and PASSWORD
## fields, a line that explains the address or says what is wrong, and JOIN (or
## SAVE) and CANCEL. Clicks outside it do nothing: what was typed stays until
## CANCEL.
func _build_form() -> void:
	_form_layer = _make_layer("ConnectionLayer", FORM_DIM)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_layer.add_child(center)
	var window := _make_window("ConnectionWindow", 26.0)
	window.custom_minimum_size = Vector2(FORM_WIDTH, 0)
	center.add_child(window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	window.add_child(column)

	_form_title = Label.new()
	_form_title.theme_type_variation = &"RowNameLabel"
	_form_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_form_title)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	column.add_child(rows)
	_name_row = _field_row(rows, "USERNAME", Net.NAME_MAX, "YOUR NAME")
	_address_row = _field_row(rows, "ADDRESS", ADDRESS_MAX, "192.168.1.2")
	_password_row = _field_row(rows, "PASSWORD", PASSWORD_MAX, "OPTIONAL")
	_field(_password_row).secret = true
	_form_note = _make_label("", &"HintLabel", 0)
	_form_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_form_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form_note.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	column.add_child(_form_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	column.add_child(buttons)
	_submit_button = _window_button("JOIN", _submit_form)
	_cancel_button = _window_button("CANCEL", _close_form.bind(true))
	buttons.add_child(_submit_button)
	buttons.add_child(_cancel_button)
	_form_items.assign([_name_row, _address_row, _password_row, _submit_button])  # CANCEL: right of JOIN


func _window_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"MenuItemButton"
	button.custom_minimum_size = Vector2(260, 64)
	button.pressed.connect(action)
	_focus_on_hover(button)
	return button


## "TITLE   [ text field ]": pressing the row (fire, Enter, a click) types in it.
func _field_row(parent: Node, title: String, max_length: int, placeholder: String) -> Button:
	var row := MenuRows.make_field_row(title, max_length, placeholder)
	MenuRows.name_label(row).custom_minimum_size.x = 250
	var field := MenuRows.field(row)
	field.focus_entered.connect(_on_field_focused.bind(field))
	field.text_submitted.connect(func(_text: String) -> void: _edit_next(1, false))
	field.focus_exited.connect(_on_field_left.bind(row))
	_fields[row] = field
	parent.add_child(row)
	_focus_on_hover(row)
	row.pressed.connect(_begin_edit.bind(row))
	return row


func _field(row: Button) -> LineEdit:
	return _fields[row]


## Opens the window: for connection [param index] (EDIT), or for a new one
## (CREATE, index -1) with the name last played under and the address to type.
func _open_form(index: int) -> void:
	if _busy():
		return
	_close_options(false)
	_form_index = index
	var info: Dictionary = _connections[index] if index >= 0 else {}
	_form_title.text = EDIT_TITLE if index >= 0 else CREATE_TITLE
	_submit_button.text = "SAVE" if index >= 0 else "JOIN"
	_field(_name_row).text = info.get("name", _last_name())
	_field(_address_row).text = info.get("address", "")
	_field(_password_row).text = info.get("password", "")
	_set_note(tr(FORM_NOTE) % Net.DEFAULT_PORT)
	_form_layer.visible = true
	_nav.items = _form_items
	_set_hint(FORM_HINT)
	if index < 0:
		_field(_address_row).grab_focus()  # ready to type the address
	else:
		_name_row.grab_focus()


## Closes the window; [param refocus] gives the focus back to what opened it.
func _close_form(refocus: bool) -> void:
	if not _form_layer.visible:
		return
	if _editing:
		_editing.release_focus()
	_form_layer.visible = false
	_nav.items = _main_items
	_set_hint(DEFAULT_HINT)
	if refocus:
		if _form_index >= 0 and _form_index < _more_buttons.size():
			_more_buttons[_form_index].grab_focus()
		else:
			_create_button.grab_focus()
	_form_index = -1


## The name to offer a new connection: the one last played under.
func _last_name() -> String:
	return InputSettings.get_online_name()


## JOIN keeps the new connection at the top of the list and joins its game;
## SAVE keeps the changes. Either first checks the fields.
func _submit_form() -> void:
	var player_name := Net.clean_name(_field(_name_row).text)
	var address := _field(_address_row).text.strip_edges()
	var parts := Net.split_address(address)
	if player_name.is_empty():
		_form_error(Net.end_text(Net.END_BAD_NAME), _name_row)
		return
	if str(parts[0]).is_empty():
		_form_error(tr("Enter the host's address first."), _address_row)
		return
	if int(parts[1]) == 0:
		_form_error(tr("That port isn't a number from 1 to 65535."), _address_row)
		return
	var password := _field(_password_row).text
	if _form_index >= 0:
		var edited := _connections[_form_index]
		edited["name"] = player_name
		edited["address"] = address
		edited["password"] = password
		_save_connections()
		var index := _form_index
		_close_form(false)
		_rebuild_list(index)  # it keeps its place: its last use is unchanged
		return
	# The same game under the same name is kept once.
	var info: Dictionary = {}
	for saved: Dictionary in _connections:
		if saved["address"] == address and saved["name"] == player_name:
			info = saved
	if info.is_empty():
		info = {"name": player_name, "address": address, "joined": ""}
		_connections.append(info)
	info["password"] = password
	info["used"] = Time.get_unix_time_from_system()
	_save_connections()
	_close_form(false)
	_rebuild_list(0)  # it's the newest, so it's first
	_connect_to(0)


func _form_error(text: String, row: Button) -> void:
	_set_note(text, true)
	row.grab_focus()


func _set_note(text: String, is_error: bool = false) -> void:
	_form_note.text = text
	if is_error:
		_form_note.add_theme_color_override(&"font_color", ERROR_COLOR)
	else:
		_form_note.remove_theme_color_override(&"font_color")


# --- Typing in the fields ---

func _begin_edit(row: Button) -> void:
	_field(row).grab_focus()


func _on_field_focused(field: LineEdit) -> void:
	_editing = field
	field.caret_column = field.text.length()


## Enter (and Tab) go on to the next field, and from the last to JOIN / SAVE;
## Shift+Tab goes back one. [param wrap] (Tab) goes round from the last field
## to the first instead.
func _edit_next(step: int, wrap: bool) -> void:
	var order: Array[Button] = [_name_row, _address_row, _password_row]
	var row: Button = _fields.find_key(_editing)
	var next := order.find(row) + step
	if wrap:
		next = wrapi(next, 0, order.size())
	if next >= order.size():
		_submit_button.grab_focus()
	elif next >= 0:
		_field(order[next]).grab_focus()


## Esc, or a pad's button: the menu has the keys again.
func _end_edit() -> void:
	if _editing == null:
		return
	var row: Button = _fields.find_key(_editing)
	_editing.release_focus()
	if row:
		row.grab_focus()


## A field was left: a name is tidied the way the screens show names, an
## address loses stray spaces; a password stays exactly as typed.
func _on_field_left(row: Button) -> void:
	var field := _field(row)
	if row == _name_row:
		field.text = Net.clean_name(field.text)
	elif row == _address_row:
		field.text = field.text.strip_edges()
	if _editing == field:
		_editing = null


# =====================================================================
# Joining
# =====================================================================

## True while a join is under way: the list waits for it.
func _busy() -> bool:
	return not _joining.is_empty()


## Joins connection [param index]'s game.
func _connect_to(index: int) -> void:
	if _busy() or index < 0 or index >= _connections.size():
		return
	_close_options(false)
	var info := _connections[index]
	var parts := Net.split_address(info["address"])
	info["used"] = Time.get_unix_time_from_system()
	_save_connections()
	if str(parts[0]).is_empty() or int(parts[1]) == 0 \
			or Net.join(parts[0], parts[1], info["name"], info["password"]) != OK:
		_set_hint(Net.end_text(Net.END_NO_HOST), true)
		return
	_joining = info
	_rows[index].grab_focus()
	_set_hint(tr("Connecting to %s : %d ...") % [parts[0], parts[1]])


func _on_join_succeeded() -> void:
	if _joining.is_empty():
		return
	_joining["joined"] = Time.get_datetime_string_from_system(false, true)
	_save_connections()
	_set_hint(tr("Joined %s's game. Waiting for the host...") % Net.host_name)


func _on_join_failed(reason: String) -> void:
	_joining = {}
	_set_hint(Net.end_text(reason), true)


func _go_back() -> void:
	if _busy():
		# Stop the join, and stay.
		_joining = {}
		Net.leave()
		_set_hint(tr("Stopped connecting."))
		return
	get_tree().change_scene_to_file(TITLE_SCENE)


func _set_hint(text: String, is_error: bool = false) -> void:
	_hint.text = text
	if is_error:
		_hint.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		_hint.remove_theme_color_override("font_color")
