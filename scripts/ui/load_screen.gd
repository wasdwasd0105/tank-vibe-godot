extends Control
## Load Game screen: every saved game is a clickable row with its own DELETE button.
##
## Mouse: click a row to continue it; click DELETE, then CONFIRM?, to remove it;
## IMPORT .SAV picks an original Tank.exe save file and adds it to the list.
## Keyboard: up/down move through the saves and the footer buttons, left/right
## jump between a save and its DELETE button (or IMPORT and BACK), fire / Enter
## activate, Esc returns to the title screen.

const TITLE_SCENE := "res://scenes/main.tscn"
const DELETE_TEXT := "DELETE"
const CONFIRM_TEXT := "CONFIRM?"
const DEFAULT_HINT := "Click a save to continue it   ·   IMPORT .SAV brings in a Tank.exe save   ·   Esc goes back"
const CONFIRM_HINT := "Press CONFIRM? again to delete this save. Moving away cancels."
const ROW_HEIGHT := 84.0
const IMPORT_TITLE := "Import a Tank.exe save"
const IMPORT_FILTERS: PackedStringArray = ["*.sav, *.SAV ; Tank.exe save files"]
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
var _delete_buttons: Array[Button] = []
var _pending_delete: Button = null
var _picker: MenuFilePicker
# Horizontal keyboard neighbours: control -> the control to its right / left.
var _right_of: Dictionary = {}
var _left_of: Dictionary = {}


func _ready() -> void:
	_nav = MenuFocus.new(get_viewport())
	_picker = MenuFilePicker.new(self, IMPORT_TITLE, IMPORT_FILTERS, "save")
	_picker.file_picked.connect(_import_file)
	_import_button.pressed.connect(_picker.open)
	_import_button.mouse_entered.connect(_import_button.grab_focus)
	_back_button.pressed.connect(_go_back)
	_back_button.mouse_entered.connect(_back_button.grab_focus)
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
		_focus_neighbour(_left_of)
	elif MenuFocus.is_pressed(event, MenuFocus.ACCEPT_ACTIONS):
		_nav.activate()
	elif MenuFocus.is_pressed(event, MenuFocus.BACK_ACTIONS):
		if _pending_delete:
			_set_pending_delete(null)
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
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	_delete_buttons.clear()
	_nav.aliases.clear()
	_right_of.clear()
	_left_of.clear()
	_pending_delete = null
	_set_hint(DEFAULT_HINT)

	_saves = SaveManager.get_save_list()
	for info: Dictionary in _saves:
		_add_save_entry(info)

	_empty_label.visible = _saves.is_empty()
	_scroll.visible = not _saves.is_empty()
	_right_of[_import_button] = _back_button
	_left_of[_back_button] = _import_button
	var items: Array[Control] = []
	items.assign(_rows)
	items.append(_import_button)
	items.append(_back_button)
	_nav.items = items
	if _rows.is_empty():
		_import_button.grab_focus()
	else:
		_rows[clampi(focus_index, 0, _rows.size() - 1)].grab_focus()


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

	var delete_button := Button.new()
	delete_button.text = DELETE_TEXT
	delete_button.theme_type_variation = &"DangerButton"
	delete_button.focus_mode = Control.FOCUS_ALL
	delete_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	delete_button.custom_minimum_size = Vector2(130, 0)
	delete_button.pressed.connect(_on_delete_pressed.bind(delete_button, info))
	delete_button.mouse_entered.connect(delete_button.grab_focus)
	delete_button.focus_exited.connect(_on_delete_focus_exited.bind(delete_button))
	entry.add_child(delete_button)

	_nav.aliases[delete_button] = row
	_right_of[row] = delete_button
	_left_of[delete_button] = row
	_rows.append(row)
	_delete_buttons.append(delete_button)


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
	return "Stage %d   ·   Difficulty %d   ·   %d %s cleared" % [
		info.get("stage", 1), info.get("difficulty", 1), cleared, "stage" if cleared == 1 else "stages"]


func _format_players(info: Dictionary) -> String:
	var parts: PackedStringArray = []
	if info.get("p1_active", false):
		parts.append("P1  %s" % _format_score(info.get("p1_score", 0)))
	if info.get("p2_active", false):
		parts.append("P2  %s" % _format_score(info.get("p2_score", 0)))
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
# Actions
# =====================================================================

func _load_save(info: Dictionary) -> void:
	SaveManager.load_game(info["filepath"])


func _on_delete_pressed(button: Button, info: Dictionary) -> void:
	if _pending_delete == button:
		var index := _delete_buttons.find(button)
		_pending_delete = null
		SaveManager.delete_save(info["filepath"])
		_rebuild_list(index)
	else:
		_set_pending_delete(button)


func _set_pending_delete(button: Button) -> void:
	if _pending_delete and is_instance_valid(_pending_delete):
		_pending_delete.text = DELETE_TEXT
	_pending_delete = button
	if button:
		button.text = CONFIRM_TEXT
	_set_hint(CONFIRM_HINT if button else DEFAULT_HINT)


func _on_delete_focus_exited(button: Button) -> void:
	if _pending_delete == button:
		_set_pending_delete(null)


func _go_back() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _set_hint(text: String, is_error: bool = false) -> void:
	_hint.text = text
	if is_error:
		_hint.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		_hint.remove_theme_color_override("font_color")


# =====================================================================
# Importing original Tank.exe saves
# =====================================================================

func _import_file(path: String) -> void:
	var result: Dictionary = SaveManager.import_original_save(path)
	if not result.get("ok", false):
		_set_hint("Import failed: %s" % result.get("error", "unknown error"), true)
		return
	_rebuild_list(0)
	for i in _saves.size():
		if _saves[i].get("filepath", "") == result["filepath"]:
			_rows[i].grab_focus()
			break
	_set_hint("Imported \"%s\" from %s   ·   click it to continue" % [result["save_name"], path.get_file()])
