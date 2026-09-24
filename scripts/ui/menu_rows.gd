class_name MenuRows
extends RefCounted
## Builders for the row-shaped buttons used by the menu screens.
##
## A row is a focusable Button whose visible content lives in a child
## HBoxContainer named "Layout". The labels inside ignore the mouse so the row
## itself receives hover and clicks; only the arrow, tab and slot buttons catch
## the mouse.

const ROW_HEIGHT := 46.0
const NAME_WIDTH := 230.0
const LAYOUT_MARGIN := 16.0
const KEYCAP_WIDTH := 76.0
## Slots are wider than a key's keycap, so their columns line up down the rows.
const SLOT_WIDTH := 132.0
## A tab row is taller, so its 36 px tabs sit inside it with room to spare.
const TAB_ROW_HEIGHT := 54.0
const TAB_INSET := 5.0


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
	layout.add_child(_make_spacer())
	layout.add_child(_make_keycap("Value"))
	return row


## Adds one more keycap after a keycap row's last, and returns it.
static func add_keycap(row: Button, text: String) -> Label:
	var layout := layout_of(row)
	var keycap := _make_keycap("Value%d" % layout.get_child_count(), text)
	layout.add_child(keycap)
	return keycap


## "NAME      [ slot ]  [ slot ]" — a row of [param slots] keycaps, "Slot0",
## "Slot1"..., that each hold a binding. The row takes the focus; the slots are
## buttons that only take the mouse, and look pressed while picked.
static func make_slot_row(title: String, slots: int) -> Button:
	var row := make_row()
	var layout := layout_of(row)
	layout.add_child(_make_name_label(title))
	layout.add_child(_make_spacer())
	for i in slots:
		var slot := Button.new()
		slot.name = "Slot%d" % i
		slot.theme_type_variation = &"KeycapButton"
		slot.toggle_mode = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.custom_minimum_size = Vector2(SLOT_WIDTH, 0)
		layout.add_child(slot)
	return row


## "[LB]  [ TAB ]  [ TAB ]  [RB]" — a strip of tabs. The row takes the focus
## (left / right pick a tab); the tabs, "Tab0", "Tab1"..., only take the mouse.
## The two end keycaps, "PrevHint" and "NextHint", name the controller buttons
## that switch tabs, and start hidden.
static func make_tab_row(titles: Array[String], prev_hint: String, next_hint: String) -> Button:
	var row := make_row(TAB_ROW_HEIGHT)
	var layout := layout_of(row)
	layout.offset_top = TAB_INSET
	layout.offset_bottom = -TAB_INSET
	layout.add_child(_make_keycap("PrevHint", prev_hint))
	for i in titles.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = titles[i]
		tab.theme_type_variation = &"TabButton"
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout.add_child(tab)
	layout.add_child(_make_keycap("NextHint", next_hint))
	for hint_name in ["PrevHint", "NextHint"]:
		var hint := layout.get_node(hint_name) as Label
		hint.custom_minimum_size = Vector2.ZERO
		hint.visible = false
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


## The [param index]th slot of a slot row.
static func slot(row: Button, index: int) -> Button:
	return row.get_node("Layout/Slot%d" % index) as Button


## The [param index]th tab of a tab row.
static func tab(row: Button, index: int) -> Button:
	return row.get_node("Layout/Tab%d" % index) as Button


## One of a tab row's end keycaps; side "Prev" or "Next".
static func tab_hint(row: Button, side: String) -> Label:
	return row.get_node("Layout/%sHint" % side) as Label


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


static func _make_keycap(node_name: String, text: String = "") -> Label:
	var keycap := Label.new()
	keycap.name = node_name
	keycap.text = text
	keycap.theme_type_variation = &"KeycapLabel"
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keycap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keycap.custom_minimum_size = Vector2(KEYCAP_WIDTH, 0)
	return keycap


static func _make_spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


static func _make_arrow_button(symbol: String) -> Button:
	var button := Button.new()
	button.text = symbol
	button.theme_type_variation = &"ArrowButton"
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button
