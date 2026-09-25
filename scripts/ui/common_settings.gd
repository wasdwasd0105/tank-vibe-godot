class_name CommonSettings
extends RefCounted
## The settings the title screen and the pause menu both offer, as rows added to
## a settings list: SFX and music volume, optionally fullscreen, whether the
## game always opens fullscreen, the game's speed, the menus' language, and a
## row per player that opens their controls page (keys, controller buttons,
## vibration).
##
## The host keeps this object, puts [method rows] in its navigation, passes
## left / right on them through [method adjust], and opens the controls page on
## [signal controls_requested].

signal controls_requested(player: String)

var sfx_row: Button
var music_row: Button
var fullscreen_row: Button   # null unless asked for
var always_fullscreen_row: Button
var game_speed_row: Button
var language_row: Button
var p1_row: Button
var p2_row: Button


func _init(container: VBoxContainer, with_fullscreen: bool) -> void:
	sfx_row = _add_value_row(container, "SFX VOLUME", _cycle_sfx_volume)
	music_row = _add_value_row(container, "MUSIC VOLUME", _cycle_music_volume)
	if with_fullscreen:
		fullscreen_row = _add_value_row(container, "FULLSCREEN", _toggle_fullscreen)
		WindowManager.fullscreen_changed.connect(_on_fullscreen_changed)
	always_fullscreen_row = _add_value_row(container, "ALWAYS FULLSCREEN", _toggle_always_fullscreen)
	game_speed_row = _add_value_row(container, "GAME SPEED", _cycle_game_speed)
	language_row = _add_value_row(container, "LANGUAGE", _cycle_language)
	p1_row = _add_controls_row(container, "P1 CONTROLS", "p1")
	p2_row = _add_controls_row(container, "P2 CONTROLS", "p2")
	refresh()


## The rows, top to bottom, for the host's navigation.
func rows() -> Array[Control]:
	var list: Array[Control] = [sfx_row, music_row]
	if fullscreen_row:
		list.append(fullscreen_row)
	list.append(always_fullscreen_row)
	list.append(game_speed_row)
	list.append(language_row)
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
	elif fullscreen_row and focused == fullscreen_row:
		_toggle_fullscreen(direction)
	elif focused == always_fullscreen_row:
		_toggle_always_fullscreen(direction)
	elif focused == game_speed_row:
		_cycle_game_speed(direction)
	elif focused == language_row:
		_cycle_language(direction)
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
	if fullscreen_row:
		MenuRows.value_label(fullscreen_row).text = "ON" if WindowManager.is_fullscreen() else "OFF"
	MenuRows.value_label(always_fullscreen_row).text = "ON" if InputSettings.get_always_fullscreen() else "OFF"
	var speed := InputSettings.get_saved_game_speed()
	MenuRows.value_label(game_speed_row).text = "%d%%" % speed
	MenuRows.arrow(game_speed_row, "Left").disabled = speed <= InputSettings.GAME_SPEEDS[0]
	MenuRows.arrow(game_speed_row, "Right").disabled = speed >= InputSettings.GAME_SPEEDS[-1]
	# Each language's name is written in itself, whichever is shown.
	MenuRows.value_label(language_row).text = Localization.get_language_name(Localization.get_language())
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


## ALWAYS FULLSCREEN on or off, kept for the next start; switched on, the
## window goes fullscreen now too.
func _toggle_always_fullscreen(_direction: int) -> void:
	var on := not InputSettings.get_always_fullscreen()
	InputSettings.save_always_fullscreen(on)
	if on and not WindowManager.is_fullscreen():
		WindowManager.set_fullscreen(true)
	refresh()


## The next speed of the original's five, stopping at either end; a running
## stage takes it up at once (game.gd).
func _cycle_game_speed(direction: int) -> void:
	var speeds := InputSettings.GAME_SPEEDS
	var at := speeds.find(InputSettings.get_saved_game_speed())
	InputSettings.save_game_speed(speeds[clampi(at + direction, 0, speeds.size() - 1)])
	refresh()


## The menus change language at once; the hosts rebuild what they composed on
## NOTIFICATION_TRANSLATION_CHANGED.
func _cycle_language(direction: int) -> void:
	Localization.step_language(direction)
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
