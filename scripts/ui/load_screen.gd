extends Control
## Load Game screen: every saved game is a clickable row (its stage, players,
## date and the map it plays on) with a MORE button that pops up a small window
## of its options: MAP, RENAME, DUPLICATE, EXPORT and DELETE.
##
## Mouse: click a row to continue it. MORE pops up its options under it: MAP
## shows the map the save plays on and steps it to the next map that reaches
## the save's stage, written into the save; RENAME opens a window to type the
## save's new name in (Enter saves it, Esc cancels); DUPLICATE copies the save
## into a new one beside it, EXPORT writes it to a file of your choosing, DELETE
## and then CONFIRM? removes it. A click outside the options window closes it.
## IMPORT brings in an original Tank.exe .sav or an exported .tsave.
## Keyboard / controller: up/down move through the saves and the footer, right
## goes from a save to its MORE and left comes back (and moves between IMPORT
## and BACK), fire / Enter / A activate. In the window up/down pick an option
## and Esc / B / left close it; elsewhere Esc / B return to the title screen.

const TITLE_SCENE := "res://scenes/main.tscn"
const MORE_TEXT := "MORE"
const MAP_TEXT := "MAP: %s"
const RENAME_TEXT := "RENAME"
const DUPLICATE_TEXT := "DUPLICATE"
const EXPORT_TEXT := "EXPORT"
const DELETE_TEXT := "DELETE"
const CONFIRM_TEXT := "CONFIRM?"
const DEFAULT_HINT := "Click a save to continue it   ·   MORE changes its map, renames, duplicates, exports or deletes it   ·   Esc goes back"
const OPTIONS_HINT := "MAP picks its map   ·   RENAME names it   ·   DUPLICATE copies it   ·   EXPORT writes it to a file   ·   DELETE removes it   ·   Esc closes"
const RENAME_TITLE := "RENAME SAVE"
const RENAME_NOTE := "Letters, digits, spaces, - and _   ·   Enter saves   ·   Esc cancels"
const CONFIRM_HINT := "Press CONFIRM? again to delete this save. Moving away cancels."
const ROW_HEIGHT := 84.0
## The date's column; a longer map name under it widens it, up to MAP_MAX_WIDTH.
const DATE_WIDTH := 210.0
const MAP_MAX_WIDTH := 260.0
const MORE_WIDTH := 130.0
## The options window: its width, its gap from MORE, and how much it dims the rest.
const POPUP_WIDTH := 230.0
const POPUP_GAP := 8.0
const POPUP_DIM := Color(0, 0, 0, 0.35)
## The RENAME window: its width, and how much it dims the screen.
const RENAME_WIDTH := 760.0
const RENAME_DIM := Color(0, 0, 0, 0.55)
const IMPORT_TITLE := "Import a save"
const IMPORT_FILTERS: PackedStringArray = [
	"*.sav, *.SAV, *.tsave ; Saves (Tank.exe .sav or an exported .tsave)",
	"*.sav, *.SAV ; Tank.exe save files",
	"*.tsave ; Battle Tank saves",
]
const EXPORT_TITLE := "Export a save"
const EXPORT_FILTERS: PackedStringArray = ["*.tsave ; Battle Tank saves"]
const ERROR_COLOR := Color(1.0, 0.5, 0.45)

@onready var _scroll: ScrollContainer = %SaveScroll
@onready var _list: VBoxContainer = %SaveList
@onready var _empty_label: Label = %EmptyLabel
@onready var _import_button: Button = %ImportButton
@onready var _back_button: Button = %BackButton
@onready var _hint: Label = %Hint

var _nav: MenuFocus
var _saves: Array = []  # save info dictionaries from SaveManager.get_save_list()
var _rows: Array[Button] = []
var _more_buttons: Array[Button] = []
var _map_labels: Array[Label] = []  # each row's map, under its date
## What up/down walk through while the window is closed: the saves and the footer.
var _main_items: Array[Control] = []
# The options window, one for every save: a layer that dims the screen and
# catches clicks outside, the window on it, its title and its buttons.
var _popup_layer: Control
var _popup: PanelContainer
var _popup_title: Label
var _popup_buttons: Array[Button] = []  # MAP, DUPLICATE, EXPORT, DELETE
var _map_button: Button
var _delete_button: Button
var _popup_info: Dictionary = {}  # the save the window is open for
var _open_more: Button = null      # and the MORE button that opened it
var _pending_delete := false
var _picker: MenuFilePicker
var _export_picker: MenuFilePicker
var _export_info: Dictionary = {}  # the save EXPORT was pressed on
# The RENAME window: a layer that dims the screen, the NAME row with its field,
# a note (the rules, or what's wrong) and SAVE / CANCEL.
var _rename_layer: Control
var _rename_row: Button
var _rename_field: LineEdit
var _rename_note: Label
var _rename_save_button: Button
var _rename_cancel_button: Button
var _rename_items: Array[Control] = []
var _rename_info: Dictionary = {}  # the save being renamed
# Horizontal keyboard neighbours: control -> the control to its right / left.
var _right_of: Dictionary = {}
var _left_of: Dictionary = {}


func _ready() -> void:
	WindowManager.leave_game()  # the menus stay in the window
	_nav = MenuFocus.new(get_viewport())
	_picker = MenuFilePicker.new(self, IMPORT_TITLE, IMPORT_FILTERS, "save")
	_picker.file_picked.connect(_import_file)
	_export_picker = MenuFilePicker.new(self, EXPORT_TITLE, EXPORT_FILTERS, "export", true)
	_export_picker.file_picked.connect(_export_to)
	_import_button.pressed.connect(_picker.open)
	_import_button.mouse_entered.connect(_import_button.grab_focus)
	_back_button.pressed.connect(_go_back)
	_back_button.mouse_entered.connect(_back_button.grab_focus)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_build_popup()
	_build_rename_window()
	_rebuild_list(0)


func _input(event: InputEvent) -> void:
	if _rename_field.has_focus():
		_typing_input(event)
		return
	if not MenuFocus.is_navigation_event(event):
		return
	# Loading a save or going back changes scene, which removes this node from
	# the tree at once (get_viewport() then returns null), so keep the viewport.
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
		elif _rename_layer.visible:
			_close_rename(true)
		else:
			_go_back()
	else:
		return
	viewport.set_input_as_handled()


## Moves the focus to the focused control's entry in [param neighbours], if any.
func _focus_neighbour(neighbours: Dictionary) -> void:
	var target: Control = neighbours.get(_nav.focus_owner())
	if target:
		target.grab_focus()


# =====================================================================
# List building
# =====================================================================

func _rebuild_list(focus_index: int) -> void:
	_close_options(false)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_more_buttons.clear()
	_map_labels.clear()
	_nav.aliases.clear()
	_right_of.clear()
	_left_of.clear()
	_set_hint(DEFAULT_HINT)

	_saves = SaveManager.get_save_list()
	for info: Dictionary in _saves:
		_add_save_entry(info)

	_empty_label.visible = _saves.is_empty()
	_scroll.visible = not _saves.is_empty()
	_right_of[_import_button] = _back_button
	_left_of[_back_button] = _import_button
	_main_items.assign(_rows)
	_main_items.append(_import_button)
	_main_items.append(_back_button)
	_nav.items = _main_items
	SoundManager.attach_ui_sounds(self)
	if _rows.is_empty():
		_import_button.grab_focus()
	else:
		_rows[clampi(focus_index, 0, _rows.size() - 1)].grab_focus()


## One save: its row, and the MORE button beside it.
func _add_save_entry(info: Dictionary) -> void:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 10)
	_list.add_child(entry)

	var row := MenuRows.make_row(ROW_HEIGHT)
	var layout := MenuRows.layout_of(row)
	layout.add_child(_make_label(str(info.get("save_name", "???")), &"RowNameLabel", 230))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.add_child(_make_label(_format_details(info), &"ValueLabel", 0, true))
	column.add_child(_make_label(_format_players(info), &"HintLabel", 0, true))
	layout.add_child(column)
	# The date, and under it the map the save plays on.
	var side := VBoxContainer.new()
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 2)
	for text: String in [_format_date(info), _map_name(_save_pool_id(info))]:
		var label := _make_label(text, &"HintLabel", DATE_WIDTH)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.add_child(label)
	layout.add_child(side)
	_map_labels.append(side.get_child(1))
	_fit_map_label(_map_labels[-1])
	row.pressed.connect(_load_save.bind(info))
	row.mouse_entered.connect(row.grab_focus)
	entry.add_child(row)

	var more := _make_row_button(MORE_TEXT, &"RowActionButton", MORE_WIDTH)
	more.toggle_mode = true  # shown pressed while its window is open
	more.pressed.connect(_toggle_options.bind(_rows.size()))
	entry.add_child(more)

	# MORE stands in for its row when moving up and down.
	_nav.aliases[more] = row
	_right_of[row] = more
	_left_of[more] = row
	_rows.append(row)
	_more_buttons.append(more)


func _make_row_button(text: String, variation: StringName, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(min_width, 0)
	button.mouse_entered.connect(button.grab_focus)
	return button


func _make_label(text: String, variation: StringName, min_width: float, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size = Vector2(min_width, 0)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _format_details(info: Dictionary) -> String:
	var cleared: int = info.get("counter", 0)
	var template := "Stage %d   ·   Difficulty %d   ·   %d stage cleared" if cleared == 1 \
			else "Stage %d   ·   Difficulty %d   ·   %d stages cleared"
	return tr(template) % [info.get("stage", 1), info.get("difficulty", 1), cleared]


func _format_players(info: Dictionary) -> String:
	var parts: PackedStringArray = []
	if info.get("p1_active", false):
		parts.append("P1  %s" % _format_score(info.get("p1_score", 0)))
	if info.get("p2_active", false):
		parts.append("P2  %s%s" % [_format_score(info.get("p2_score", 0)),
			"  (%s)" % tr("OFF") if info.get("p2_disabled", false) else ""])  # sitting out
	return "    ".join(parts)


func _format_date(info: Dictionary) -> String:
	var saved_iso: String = info.get("saved_iso", "")
	if saved_iso.length() >= 16:
		return saved_iso.substr(0, 10) + "  " + saved_iso.substr(11, 5)
	return saved_iso


## 45230 -> "45,230"
func _format_score(score: int) -> String:
	var digits := str(absi(score))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-" if score < 0 else "") + grouped


# =====================================================================
# The options window MORE opens
# =====================================================================

## Builds the window, hidden: a panel titled with the save's name over a layer
## that dims the screen and closes the window when clicked.
func _build_popup() -> void:
	_popup_layer = Control.new()
	_popup_layer.name = "OptionsLayer"
	_popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_layer.visible = false
	_popup_layer.gui_input.connect(_on_popup_layer_input)
	add_child(_popup_layer)
	var dim := ColorRect.new()
	dim.color = POPUP_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_layer.add_child(dim)

	_popup = PanelContainer.new()
	_popup.name = "OptionsWindow"
	_popup.theme_type_variation = &"MenuPanel"
	var style := (get_theme_stylebox(&"panel", &"MenuPanel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.set_content_margin_all(14.0)
	style.bg_color.a = 0.98
	style.border_color = Color(0.98, 0.78, 0.22)
	_popup.add_theme_stylebox_override(&"panel", style)
	_popup.custom_minimum_size = Vector2(POPUP_WIDTH, 0)
	_popup_layer.add_child(_popup)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_popup.add_child(column)
	_popup_title = _make_label("", &"HintLabel", 0)
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_popup_title)
	_map_button = _make_row_button("", &"RowActionButton", 0)
	_map_button.pressed.connect(_on_map_pressed)
	column.add_child(_map_button)
	_popup_buttons.append(_map_button)
	for option: Array in [[RENAME_TEXT, &"RowActionButton", _on_rename_pressed],
			[DUPLICATE_TEXT, &"RowActionButton", _on_duplicate_pressed],
			[EXPORT_TEXT, &"RowActionButton", _on_export_pressed],
			[DELETE_TEXT, &"DangerButton", _on_delete_pressed]]:
		var button := _make_row_button(option[0], option[1], 0)
		button.pressed.connect(option[2])
		column.add_child(button)
		_popup_buttons.append(button)
	_delete_button = _popup_buttons[4]
	_delete_button.focus_exited.connect(_on_delete_focus_exited)


## Opens the window for save [param index], or closes it if it is open for it.
func _toggle_options(index: int) -> void:
	var more := _more_buttons[index]
	if _open_more == more:
		_close_options(true)
		return
	_close_options(false)
	_open_more = more
	_popup_info = _saves[index]
	_popup_title.text = str(_popup_info.get("save_name", ""))
	_refresh_map_button()
	more.set_pressed_no_signal(true)
	_popup_layer.visible = true
	_place_popup(more)
	# Up and down stay in the window while it is open (skipping a greyed MAP).
	var buttons: Array[Control] = []
	buttons.assign(_popup_buttons)
	_nav.items = buttons
	(_popup_buttons[1] if _map_button.disabled else _map_button).grab_focus()
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
	_popup_info = {}
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


# =====================================================================
# Actions
# =====================================================================

func _load_save(info: Dictionary) -> void:
	SaveManager.load_game(info["filepath"])


## The map save [param info] plays on: its own record, else (a save from before
## saves kept one) the map selected when it loads.
func _save_pool_id(info: Dictionary) -> String:
	var pool_id: String = info.get("map_pool", "")
	return pool_id if not pool_id.is_empty() else GameManager.current_map_pool_id


## The maps save [param info] can play on: those that reach its stage.
func _map_choices(info: Dictionary) -> Array[String]:
	var choices: Array[String] = []
	for pool: LevelData.MapPool in LevelData.get_available_pools():
		if LevelData.get_pool_stage_count(pool) >= int(info.get("stage", 1)):
			choices.append(pool.id)
	return choices


## Widens a row's map line to its name, within MAP_MAX_WIDTH (longer ones trim).
func _fit_map_label(label: Label) -> void:
	var width := label.get_theme_font(&"font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size(&"font_size")).x
	label.custom_minimum_size.x = clampf(ceilf(width), DATE_WIDTH, MAP_MAX_WIDTH)


## The name map pool [param pool_id] goes by in the menus; the id itself if
## it's gone (an imported map since deleted).
func _map_name(pool_id: String) -> String:
	for pool: LevelData.MapPool in LevelData.get_available_pools():
		if pool.id == pool_id:
			return pool.display_name
	return pool_id


## MAP shows the open save's map, greyed out when no other map reaches its stage.
func _refresh_map_button() -> void:
	var current := _save_pool_id(_popup_info)
	_map_button.text = tr(MAP_TEXT) % _map_name(current)
	var choices := _map_choices(_popup_info)
	_map_button.disabled = choices.is_empty() or (choices.size() == 1 and choices[0] == current)


## MAP: the next map that reaches the save's stage, written into the save.
func _on_map_pressed() -> void:
	if _map_button.disabled:
		return
	var choices := _map_choices(_popup_info)
	var next: String = choices[(choices.find(_save_pool_id(_popup_info)) + 1) % choices.size()]
	var result: Dictionary = SaveManager.set_save_map_pool(_popup_info["filepath"], next)
	if not result.get("ok", false):
		_set_hint(result.get("error", tr("unknown error")), true)
		return
	_popup_info["map_pool"] = next
	var row_map := _map_labels[_saves.find(_popup_info)]
	row_map.text = _map_name(next)
	_fit_map_label(row_map)
	_refresh_map_button()
	_place_popup(_open_more)  # the name's width may have changed


func _on_rename_pressed() -> void:
	_open_rename(_popup_info)


func _on_duplicate_pressed() -> void:
	_duplicate(_popup_info)


func _on_export_pressed() -> void:
	_export(_popup_info)


func _duplicate(info: Dictionary) -> void:
	var result: Dictionary = SaveManager.duplicate_save(info["filepath"])
	if not result.get("ok", false):
		_set_hint(tr("Duplicate failed: %s") % result.get("error", tr("unknown error")), true)
		return
	_rebuild_list(0)
	_focus_save(result["filepath"])
	_set_hint(tr("Duplicated \"%s\" as \"%s\"") % [info.get("save_name", "?"), result["save_name"]])


## Asks where to write [param info]'s save; _export_to() writes it there.
func _export(info: Dictionary) -> void:
	_export_info = info
	_close_options(true)
	_export_picker.open(str(info.get("save_name", "save")) + ".tsave")


func _export_to(path: String) -> void:
	if _export_info.is_empty():
		return
	var result: Dictionary = SaveManager.export_save(_export_info["filepath"], path)
	if result.get("ok", false):
		_set_hint(tr("Exported \"%s\" to %s") % [_export_info.get("save_name", "?"), result["path"]])
	else:
		_set_hint(tr("Export failed: %s") % result.get("error", tr("unknown error")), true)


## Focuses the row of the save stored at [param filepath].
func _focus_save(filepath: String) -> void:
	for i in _saves.size():
		if _saves[i].get("filepath", "") == filepath:
			_rows[i].grab_focus()
			return


## DELETE asks first: its first press turns it into CONFIRM?, the second deletes.
func _on_delete_pressed() -> void:
	if not _pending_delete:
		_set_pending_delete(true)
		return
	var filepath: String = _popup_info["filepath"]
	var index := _saves.find(_popup_info)
	SaveManager.delete_save(filepath)
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


func _go_back() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _set_hint(text: String, is_error: bool = false) -> void:
	_hint.text = text
	if is_error:
		_hint.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		_hint.remove_theme_color_override("font_color")


# =====================================================================
# The RENAME window
# =====================================================================

## Builds the window, hidden, centred over a layer that dims the screen: its
## title, the NAME row with its field, a note, and SAVE and CANCEL. Clicks
## outside it do nothing; CANCEL or Esc close it.
func _build_rename_window() -> void:
	_rename_layer = Control.new()
	_rename_layer.name = "RenameLayer"
	_rename_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rename_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_rename_layer.visible = false
	add_child(_rename_layer)
	var dim := ColorRect.new()
	dim.color = RENAME_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rename_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rename_layer.add_child(center)

	var window := PanelContainer.new()
	window.name = "RenameWindow"
	window.theme_type_variation = &"MenuPanel"
	var style := (get_theme_stylebox(&"panel", &"MenuPanel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.set_content_margin_all(26.0)
	style.bg_color.a = 0.98
	style.border_color = Color(0.98, 0.78, 0.22)
	window.add_theme_stylebox_override(&"panel", style)
	window.custom_minimum_size = Vector2(RENAME_WIDTH, 0)
	center.add_child(window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	window.add_child(column)

	var title := _make_label(RENAME_TITLE, &"RowNameLabel", 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_rename_row = MenuRows.make_field_row("NAME", SaveManager.SAVE_NAME_MAX, "")
	MenuRows.name_label(_rename_row).custom_minimum_size.x = 160
	_rename_field = MenuRows.field(_rename_row)
	_rename_field.keep_editing_on_text_submit = true   # a name refused is typed on
	_rename_field.focus_entered.connect(func() -> void: _rename_field.select_all())
	_rename_field.text_submitted.connect(func(_text: String) -> void: _submit_rename())
	_rename_row.pressed.connect(_rename_field.grab_focus)   # fire, Enter or a click types in it
	_rename_row.mouse_entered.connect(_hover_rename.bind(_rename_row))
	column.add_child(_rename_row)
	_rename_note = _make_label("", &"HintLabel", 0)
	_rename_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_rename_note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	column.add_child(buttons)
	_rename_save_button = _rename_button("SAVE", _submit_rename)
	_rename_cancel_button = _rename_button("CANCEL", _close_rename.bind(true))
	buttons.add_child(_rename_save_button)
	buttons.add_child(_rename_cancel_button)
	_rename_items.assign([_rename_row, _rename_save_button])  # CANCEL: right of SAVE


func _rename_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"MenuItemButton"
	button.custom_minimum_size = Vector2(260, 64)
	button.pressed.connect(action)
	button.mouse_entered.connect(_hover_rename.bind(button))
	return button


## Hovering takes the focus, as everywhere in the menus, but not from the field
## being typed in: that would take the keys away from it.
func _hover_rename(control: Control) -> void:
	if not _rename_field.has_focus():
		control.grab_focus()


## Opens the window for save [param info]: its name in the field, all of it
## picked, so typing replaces it.
func _open_rename(info: Dictionary) -> void:
	_close_options(false)
	_rename_info = info
	_rename_field.text = str(info.get("save_name", ""))
	_set_rename_note(RENAME_NOTE)
	_rename_layer.visible = true
	_nav.items = _rename_items
	_right_of[_rename_save_button] = _rename_cancel_button
	_left_of[_rename_cancel_button] = _rename_save_button
	_rename_field.grab_focus()


## Closes the window; [param refocus] puts the focus back on the save's MORE.
func _close_rename(refocus: bool) -> void:
	if not _rename_layer.visible:
		return
	_rename_field.release_focus()
	_rename_layer.visible = false
	_nav.items = _main_items
	var index := _saves.find(_rename_info)
	_rename_info = {}
	if refocus and index >= 0:
		_more_buttons[index].grab_focus()


## While the name is being typed, the field has the keys: Esc cancels the
## rename, and a controller's button hands the keys back to the menu.
func _typing_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_close_rename(true)
	elif event is InputEventJoypadButton and event.pressed:
		_rename_row.grab_focus()
	else:
		return
	get_viewport().set_input_as_handled()


## SAVE, or Enter in the field: renames the save, or says what's wrong with
## the name. The same name again just closes the window.
func _submit_rename() -> void:
	var old_name := str(_rename_info.get("save_name", ""))
	if SaveManager.clean_save_name(_rename_field.text) == old_name:
		_close_rename(true)
		return
	var result: Dictionary = SaveManager.rename_save(_rename_info["filepath"], _rename_field.text)
	if not result.get("ok", false):
		_set_rename_note(result.get("error", tr("unknown error")), true)
		_rename_field.grab_focus()
		return
	_close_rename(false)
	_rebuild_list(0)
	_focus_save(result["filepath"])
	_set_hint(tr("Renamed \"%s\" to \"%s\"") % [old_name, result["save_name"]])


func _set_rename_note(text: String, is_error: bool = false) -> void:
	_rename_note.text = text
	if is_error:
		_rename_note.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		_rename_note.remove_theme_color_override("font_color")


# =====================================================================
# Importing saves: original Tank.exe .sav files and exported .tsave files
# =====================================================================

func _import_file(path: String) -> void:
	var result: Dictionary = SaveManager.import_save_file(path)
	if not result.get("ok", false):
		_set_hint(tr("Import failed: %s") % result.get("error", tr("unknown error")), true)
		return
	_rebuild_list(0)
	_focus_save(result["filepath"])
	_set_hint(tr("Imported \"{name}\" from {file}   ·   click it to continue").format(
			{"name": result["save_name"], "file": path.get_file()}))
