class_name SettingsTabs
extends RefCounted
## A settings page's tab strip, shared by the title screen (GAME | GENERAL) and
## the pause menu (GAME | GENERAL | ONLINE). The strip sits under the page's
## header; each tab's rows are a container of their own, of which only the
## picked tab's shows, all at the height of the tallest so switching never
## resizes the page. A tab can be left out ([method offer]); with one left, the
## strip hides.
##
## A click on a tab picks it, and fire or a click on the strip itself steps to
## the next. The host sends left / right on the focused strip to [method step]
## and controller events to [method handle_shortcut] (LB / RB, from anywhere on
## the page), and moves the focus and refreshes on [signal selected].

## [param tab] was picked; the host puts the focus where it belongs.
signal selected(tab: int)

var strip: Button
## The tab showing.
var current: int = 0
var _pages: Array[Control] = []
var _offered: Array[bool] = []


## A strip of [param titles] above [param pages] (one container per tab, in the
## same order), put where [param above] is in its parent. [param can_hover], if
## valid, says whether hovering the strip may take the focus now.
func _init(above: Control, titles: Array[String], pages: Array[Control], can_hover := Callable()) -> void:
	_pages = pages
	for i in titles.size():
		_offered.append(true)
	strip = MenuRows.make_tab_row(titles, "LB", "RB")
	var layout := above.get_parent()
	layout.add_child(strip)
	layout.move_child(strip, above.get_index())
	var hover := func() -> void:
		if not can_hover.is_valid() or can_hover.call():
			strip.grab_focus()
	strip.mouse_entered.connect(hover)
	strip.pressed.connect(step.bind(1, true))
	for i in titles.size():
		var tab := MenuRows.tab(strip, i)
		tab.pressed.connect(select.bind(i))
		tab.mouse_entered.connect(hover)
	_show(0)


## Shows [param tab] and its rows, and tells the host if that changed the tab.
func select(tab: int) -> void:
	if tab < 0 or tab >= _pages.size() or not _offered[tab] or tab == current:
		_show(current)   # left out, or already showing: a click only toggled its look
		return
	_show(tab)
	selected.emit(tab)


## The next tab offered in [param direction] (-1 left, 1 right), stopping at the
## ends, or going round when [param wrap].
func step(direction: int, wrap := false) -> void:
	var tab := current
	for i in _pages.size() - 1:
		tab += direction
		if wrap:
			tab = wrapi(tab, 0, _pages.size())
		if tab < 0 or tab >= _pages.size():
			return
		if _offered[tab]:
			select(tab)
			return


## LB or RB pressed on a controller: the tab to the left or right. True if
## [param event] was one.
func handle_shortcut(event: InputEvent) -> bool:
	if not (strip.visible and event is InputEventJoypadButton and event.pressed):
		return false
	if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
		step(-1)
	elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		step(1)
	else:
		return false
	return true


## Offers [param tab] or leaves it out. The strip shows while two or more are
## offered; the tab showing moves to the first offered if it was left out.
func offer(tab: int, on: bool) -> void:
	_offered[tab] = on
	MenuRows.tab(strip, tab).visible = on
	strip.visible = _offered.count(true) > 1
	if not _offered[current]:
		_show(_offered.find(true))


## Every tab's rows at the height of the tallest: call once they're built, and
## again if a tab's rows change.
func fit_height() -> void:
	var tallest := 0.0
	for page in _pages:
		page.custom_minimum_size.y = 0.0
		tallest = maxf(tallest, page.get_combined_minimum_size().y)
	for page in _pages:
		page.custom_minimum_size.y = tallest


## The picked tab's look, and the LB / RB keycaps while a controller is plugged in.
func _show(tab: int) -> void:
	current = maxi(tab, 0)
	for i in _pages.size():
		_pages[i].visible = i == current
		MenuRows.tab(strip, i).set_pressed_no_signal(i == current)
	var pad_connected := not Input.get_connected_joypads().is_empty()
	MenuRows.tab_hint(strip, "Prev").visible = pad_connected
	MenuRows.tab_hint(strip, "Next").visible = pad_connected
