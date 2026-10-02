class_name NetToasts
extends CanvasLayer
## Online notices ("ALICE joined the game.") over whatever screen is up, as the
## original's system messages were: each a line at the top for a few seconds,
## newest last, fading out. Net owns one and feeds it notice_posted.

const SHOW_TIME := 4.0
const FADE_TIME := 0.6
const MAX_LINES := 4
const THEME: Theme = preload("res://assets/ui/menu_theme.tres")

var _column: VBoxContainer


func _init() -> void:
	name = "NetToasts"
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_column = VBoxContainer.new()
	_column.theme = THEME
	_column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_column.offset_left = -500
	_column.offset_right = 500
	_column.offset_top = 22
	_column.add_theme_constant_override(&"separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)


## Shows [param text] for SHOW_TIME, then fades it out.
func show_notice(text: String) -> void:
	var line := Label.new()
	line.text = text
	line.theme_type_variation = &"ValueLabel"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0.03, 0.03, 0.05, 0.78)
	backing.border_color = Color(0.85, 0.62, 0.16, 0.7)
	backing.border_width_bottom = 2
	backing.set_corner_radius_all(6)
	backing.content_margin_left = 18
	backing.content_margin_right = 18
	backing.content_margin_top = 6
	backing.content_margin_bottom = 6
	line.add_theme_stylebox_override(&"normal", backing)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(line)
	while _column.get_child_count() > MAX_LINES:
		var oldest := _column.get_child(0)
		_column.remove_child(oldest)
		oldest.queue_free()
	var tween := line.create_tween()
	tween.tween_interval(SHOW_TIME)
	tween.tween_property(line, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(line.queue_free)
