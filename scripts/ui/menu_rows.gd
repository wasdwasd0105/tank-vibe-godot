class_name MenuRows
extends RefCounted
## Builders for the row-shaped buttons used by the menu screens.
##
## A row is a focusable Button whose visible content lives in a child
## HBoxContainer named "Layout". The labels inside ignore the mouse so the row
## itself receives hover and clicks; only the arrow buttons catch the mouse.

const ROW_HEIGHT := 50.0
const NAME_WIDTH := 230.0
const LAYOUT_MARGIN := 16.0


## An empty row with a horizontal "Layout" container inside.
static func make_row(min_height: float = ROW_HEIGHT) -> Button:
	var row := Button.new()
	row.theme_type_variation = &"RowButton"
	row.focus_mode = Control.FOCUS_ALL
	row.custom_minimum_size = Vector2(0, min_height)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var layout := HBoxContainer.new()
	layout.name = "Layout"
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = LAYOUT_MARGIN
	layout.offset_right = -LAYOUT_MARGIN
	layout.add_theme_constant_override("separation", 14)
	row.add_child(layout)
	return row


## "NAME   <   value   >" — a setting the user cycles through.
static func make_value_row(title: String) -> Button:
	var row := make_row()
	var layout := layout_of(row)
	layout.add_child(_make_name_label(title))
	var left := _make_arrow_button("<")
	left.name = "Left"
	layout.add_child(left)
	var value := Label.new()
	value.name = "Value"
	value.theme_type_variation = &"ValueLabel"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(value)
	var right := _make_arrow_button(">")
	right.name = "Right"
	layout.add_child(right)
	return row


## "NAME            [ key ]" — a row showing a key (or key summary) in a keycap.
static func make_keycap_row(title: String) -> Button:
	var row := make_row()
	var layout := layout_of(row)
	layout.add_child(_make_name_label(title))
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)
	var keycap := Label.new()
	keycap.name = "Value"
	keycap.theme_type_variation = &"KeycapLabel"
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keycap.custom_minimum_size = Vector2(76, 0)
	layout.add_child(keycap)
	return row


## "NAME                    hint" — a row that runs an action when pressed.
static func make_action_row(title: String, hint: String) -> Button:
	var row := make_row()
	var layout := layout_of(row)
	layout.add_child(_make_name_label(title))
	var value := Label.new()
	value.name = "Value"
	value.text = hint
	value.theme_type_variation = &"HintLabel"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(value)
	return row


static func layout_of(row: Button) -> HBoxContainer:
	return row.get_node("Layout") as HBoxContainer


static func value_label(row: Button) -> Label:
	return row.get_node("Layout/Value") as Label


## The "<" (side "Left") or ">" (side "Right") button of a value row.
static func arrow(row: Button, side: String) -> Button:
	return row.get_node("Layout/" + side) as Button


static func _make_name_label(title: String) -> Label:
	var label := Label.new()
	label.name = "Name"
	label.text = title
	label.theme_type_variation = &"RowNameLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(NAME_WIDTH, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


static func _make_arrow_button(symbol: String) -> Button:
	var button := Button.new()
	button.text = symbol
	button.theme_type_variation = &"ArrowButton"
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button
