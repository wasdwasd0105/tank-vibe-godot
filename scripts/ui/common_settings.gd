class_name CommonSettings
extends RefCounted
## The settings the title screen and the pause menu both offer, as rows added to
## a settings list: SFX and music volume, controller vibration, optionally
## fullscreen, and a row per player that opens their controls page.
##
## The host keeps this object, puts [method rows] in its navigation, passes
## left / right on them through [method adjust], and opens the controls page on
## [signal controls_requested].

signal controls_requested(player: String)

var sfx_row: Button
var music_row: Button
var vibration_row: Button
var fullscreen_row: Button   # null unless asked for
var p1_row: Button
var p2_row: Button


func _init(container: VBoxContainer, with_fullscreen: bool) -> void:
	sfx_row = _add_value_row(container, "SFX VOLUME", _cycle_sfx_volume)
	music_row = _add_value_row(container, "MUSIC VOLUME", _cycle_music_volume)
	vibration_row = _add_value_row(container, "VIBRATION", _toggle_vibration)
	if with_fullscreen:
		fullscreen_row = _add_value_row(container, "FULLSCREEN", _toggle_fullscreen)
		WindowManager.fullscreen_changed.connect(_on_fullscreen_changed)
	p1_row = _add_controls_row(container, "P1 CONTROLS", "p1")
	p2_row = _add_controls_row(container, "P2 CONTROLS", "p2")
	refresh()


## The rows, top to bottom, for the host's navigation.
func rows() -> Array[Control]:
	var list: Array[Control] = [sfx_row, music_row, vibration_row]
	if fullscreen_row:
		list.append(fullscreen_row)
	list.append(p1_row)
	list.append(p2_row)
	return list


## The row that opens [param player]'s controls page.
func controls_row(player: String) -> Button:
	return p1_row if player == "p1" else p2_row


## Left / right on [param focused]: steps its setting. False when it isn't one
## of these rows.
func adjust(focused: Control, direction: int) -> bool:
	if focused == sfx_row:
		_cycle_sfx_volume(direction)
	elif focused == music_row:
		_cycle_music_volume(direction)
	elif focused == vibration_row:
		_toggle_vibration(direction)
	elif fullscreen_row and focused == fullscreen_row:
		_toggle_fullscreen(direction)
	else:
		return false
	return true


func refresh() -> void:
	var sfx := SoundManager.get_sfx_volume()
	var music := SoundManager.get_music_volume()
	MenuRows.value_label(sfx_row).text = format_volume(sfx)
	MenuRows.value_label(music_row).text = format_volume(music)
	MenuRows.arrow(sfx_row, "Left").disabled = sfx <= 0.0
	MenuRows.arrow(sfx_row, "Right").disabled = sfx >= 1.0
	MenuRows.arrow(music_row, "Left").disabled = music <= 0.0
	MenuRows.arrow(music_row, "Right").disabled = music >= 1.0
	MenuRows.value_label(vibration_row).text = "ON" if InputSettings.get_saved_vibration() else "OFF"
	if fullscreen_row:
		MenuRows.value_label(fullscreen_row).text = "ON" if WindowManager.is_fullscreen() else "OFF"
	MenuRows.value_label(p1_row).text = InputSettings.get_player_controls_text("p1")
	MenuRows.value_label(p2_row).text = InputSettings.get_player_controls_text("p2")


## "OFF" or a ten-segment bar plus the percentage.
static func format_volume(value: float) -> String:
	var steps := int(roundf(clampf(value, 0.0, 1.0) * 10.0))
	if steps == 0:
		return "OFF"
	return "%s%s  %d%%" % ["█".repeat(steps), "░".repeat(10 - steps), steps * 10]


## Volume steps in tenths, the granularity the row can show as a bar.
static func _stepped_volume(current: float, direction: int) -> float:
	return clampf(snappedf(current, 0.1) + 0.1 * direction, 0.0, 1.0)


func _cycle_sfx_volume(direction: int) -> void:
	SoundManager.set_sfx_volume(_stepped_volume(SoundManager.get_sfx_volume(), direction))
	refresh()
	SoundManager.play(&"ui_select")  # audible preview of the new level


func _cycle_music_volume(direction: int) -> void:
	SoundManager.set_music_volume(_stepped_volume(SoundManager.get_music_volume(), direction))
	refresh()


## Controller vibration on/off. Switching it on gives every plugged-in
## controller a short buzz, so you feel what it does.
func _toggle_vibration(_direction: int) -> void:
	var enabled := not InputSettings.get_saved_vibration()
	InputSettings.save_vibration(enabled)
	if enabled:
		for device in Input.get_connected_joypads():
			Input.start_joy_vibration(device, 0.4, 0.5, 0.2)
	refresh()


func _toggle_fullscreen(_direction: int) -> void:
	WindowManager.set_fullscreen(not WindowManager.is_fullscreen())


func _on_fullscreen_changed(_on: bool) -> void:
	refresh()


func _add_value_row(container: VBoxContainer, title: String, cycle: Callable) -> Button:
	var row := MenuRows.make_value_row(title)
	container.add_child(row)
	row.mouse_entered.connect(row.grab_focus)   # hovering focuses, as everywhere in the menus
	row.pressed.connect(cycle.bind(1))
	for side: String in ["Left", "Right"]:
		var arrow := MenuRows.arrow(row, side)
		arrow.pressed.connect(cycle.bind(-1 if side == "Left" else 1))
		arrow.mouse_entered.connect(row.grab_focus)
	return row


func _add_controls_row(container: VBoxContainer, title: String, player: String) -> Button:
	var row := MenuRows.make_keycap_row(title)
	container.add_child(row)
	row.mouse_entered.connect(row.grab_focus)
	row.pressed.connect(func() -> void: controls_requested.emit(player))
	return row
