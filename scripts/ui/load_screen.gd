extends Control
## Load Game screen: every saved game is a clickable row with a MORE button
## that pops up a small window of its options: DUPLICATE, EXPORT and DELETE.
##
## Mouse: click a row to continue it. MORE pops up its options under it:
## DUPLICATE copies the save into a new one beside it, EXPORT writes it to a
## file of your choosing, DELETE and then CONFIRM? removes it. A click outside
## the window closes it. IMPORT brings in an original Tank.exe .sav or an
## exported .tsave.
## Keyboard / controller: up/down move through the saves and the footer, right
## goes from a save to its MORE and left comes back (and moves between IMPORT
## and BACK), fire / Enter / A activate. In the window up/down pick an option
## and Esc / B / left close it; elsewhere Esc / B return to the title screen.

const TITLE_SCENE := "res://scenes/main.tscn"
const MORE_TEXT := "MORE"
const DUPLICATE_TEXT := "DUPLICATE"
const EXPORT_TEXT := "EXPORT"
const DELETE_TEXT := "DELETE"
const CONFIRM_TEXT := "CONFIRM?"
const DEFAULT_HINT := "Click a save to continue it   ·   MORE duplicates, exports or deletes it   ·   Esc goes back"
const OPTIONS_HINT := "DUPLICATE copies the save   ·   EXPORT writes it to a file   ·   DELETE removes it   ·   Esc closes"
const CONFIRM_HINT := "Press CONFIRM? again to delete this save. Moving away cancels."
const ROW_HEIGHT := 84.0
const MORE_WIDTH := 130.0
## The options window: its width, its gap from MORE, and how much it dims the rest.
const POPUP_WIDTH := 230.0
const POPUP_GAP := 8.0
const POPUP_DIM := Color(0, 0, 0, 0.35)
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
## What up/down walk through while the window is closed: the saves and the footer.
var _main_items: Array[Control] = []
# The options window, one for every save: a layer that dims the screen and
# catches clicks outside, the window on it, its title and its buttons.
var _popup_layer: Control
var _popup: PanelContainer
var _popup_title: Label
var _popup_buttons: Array[Button] = []  # DUPLICATE, EXPORT, DELETE
var _delete_button: Button
var _popup_info: Dictionary = {}  # the save the window is open for
var _open_more: Button = null      # and the MORE button that opened it
var _pending_delete := false
var _picker: MenuFilePicker
var _export_picker: MenuFilePicker
var _export_info: Dictionary = {}  # the save EXPORT was pressed on
# Horizontal keyboard neighbours: control -> the control to its right / left.
var _right_of: Dictionary = {}
var _left_of: Dictionary = {}


func _ready() -> void:
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
	_rebuild_list(0)


func _input(event: InputEvent) -> void:
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
	var date := _make_label(_format_date(info), &"HintLabel", 210)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layout.add_child(date)
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
	for option: Array in [[DUPLICATE_TEXT, &"RowActionButton", _on_duplicate_pressed],
			[EXPORT_TEXT, &"RowActionButton", _on_export_pressed],
			[DELETE_TEXT, &"DangerButton", _on_delete_pressed]]:
		var button := _make_row_button(option[0], option[1], 0)
		button.pressed.connect(option[2])
		column.add_child(button)
		_popup_buttons.append(button)
	_delete_button = _popup_buttons[2]
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
