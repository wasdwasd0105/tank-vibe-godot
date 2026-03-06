extends Control

## Load Game screen — displays saved game list for selection.
## Navigated to from the title screen's LOAD GAME option.

const MAX_VISIBLE := 8  # Maximum save entries visible at once

@onready var title_label: Label = $Title
@onready var cursor: Label = $Cursor
@onready var back_label: Label = $BackLabel

# Dynamically created save entry labels
var _entry_labels: Array[Label] = []
var _save_list: Array = []  # Array of save info dictionaries
var _selected: int = 0
var _scroll_offset: int = 0  # For scrolling when more saves than MAX_VISIBLE

func _ready() -> void:
	_save_list = SaveManager.get_save_list()
	_build_entry_labels()
	_update_display()
	_update_cursor()

func _process(_delta: float) -> void:
	var total_items := _save_list.size() + 1  # saves + BACK

	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		_selected = maxi(_selected - 1, 0)
		_ensure_visible()
		_update_display()
		_update_cursor()
	elif Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		_selected = mini(_selected + 1, total_items - 1)
		_ensure_visible()
		_update_display()
		_update_cursor()
	elif Input.is_action_just_pressed("p1_shoot") or Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("ui_select"):
		_select_item()
	elif Input.is_action_just_pressed("pause"):
		_go_back()

func _select_item() -> void:
	if _selected < _save_list.size():
		# Load selected save
		var info: Dictionary = _save_list[_selected]
		SaveManager.load_game(info["filepath"])
	else:
		# BACK option
		_go_back()

func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# =====================================================================
# Build UI
# =====================================================================

func _build_entry_labels() -> void:
	# Create labels for save entries (up to MAX_VISIBLE)
	var count := mini(_save_list.size(), MAX_VISIBLE)
	for i in range(count):
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 28)
		label.position = Vector2(300, 200 + i * 60)
		label.size = Vector2(1000, 50)
		add_child(label)
		_entry_labels.append(label)

	# Position BACK label after entries
	if back_label:
		back_label.position.y = 200 + count * 60 + 20

	# Handle empty list
	if _save_list.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved games"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 28)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		empty_label.position = Vector2(300, 200)
		empty_label.size = Vector2(1000, 50)
		add_child(empty_label)
		if back_label:
			back_label.position.y = 280

func _update_display() -> void:
	# Update entry label texts based on scroll offset
	for i in range(_entry_labels.size()):
		var save_idx := _scroll_offset + i
		if save_idx < _save_list.size():
			_entry_labels[i].text = _format_save_entry(_save_list[save_idx])
			_entry_labels[i].visible = true
		else:
			_entry_labels[i].visible = false

func _format_save_entry(info: Dictionary) -> String:
	var name_str: String = info.get("save_name", "???")
	var stage: int = info.get("stage", 1)
	var counter: int = info.get("counter", 0)
	var difficulty: int = info.get("difficulty", 1)
	var p1_score: int = info.get("p1_score", 0)
	var p1_active: bool = info.get("p1_active", false)
	var p2_active: bool = info.get("p2_active", false)

	var date_str := ""
	var saved_iso: String = info.get("saved_iso", "")
	if saved_iso.length() >= 10:
		date_str = saved_iso.substr(0, 10)

	var players_str := ""
	if p1_active:
		players_str += "P1:%s" % _format_score(p1_score)
	if p2_active:
		var p2_score: int = info.get("p2_score", 0)
		if players_str != "":
			players_str += " "
		players_str += "P2:%s" % _format_score(p2_score)

	return "%s | Stg %d D%d #%d | %s | %s" % [name_str, stage, difficulty, counter, players_str, date_str]

func _format_score(score: int) -> String:
	if score >= 1000000:
		return "%.1fM" % (score / 1000000.0)
	elif score >= 1000:
		return "%.1fK" % (score / 1000.0)
	return str(score)

# =====================================================================
# Cursor
# =====================================================================

func _update_cursor() -> void:
	if not cursor:
		return
	if _selected < _save_list.size():
		# Cursor on a save entry
		var visual_idx := _selected - _scroll_offset
		if visual_idx >= 0 and visual_idx < _entry_labels.size():
			cursor.position.y = _entry_labels[visual_idx].position.y
	else:
		# Cursor on BACK
		cursor.position.y = back_label.position.y

func _ensure_visible() -> void:
	# Adjust scroll so selected item is visible
	if _selected < _save_list.size():
		if _selected < _scroll_offset:
			_scroll_offset = _selected
		elif _selected >= _scroll_offset + MAX_VISIBLE:
			_scroll_offset = _selected - MAX_VISIBLE + 1
