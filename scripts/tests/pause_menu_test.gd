extends Node
## Headless test for the pause menu: Esc or Start opens it over the paused
## stage; RESUME / RESTART STAGE / MAIN MENU / SETTINGS / QUIT GAME; the
## settings page changes sound, vibration and a key without leaving the stage,
## and opens a player's controls page (the title screen's) on the right tab;
## Esc, B and Start step back a page at a time. Driven by simulated keys and
## controller buttons. A test run keeps its own settings file.
## Run as an override main scene:
##   Godot --headless res://scenes/test/pause_menu_test.tscn

var _fail := 0
var _game: Node
var _menu      # PauseLayer/PauseMenu (untyped: the test reads its private state)
var _requests: Array = []


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()   # parsed events otherwise wait for the next frame
	await get_tree().process_frame


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _row_names() -> Array:
	var names: Array = []
	for row: Button in _menu._common.rows():
		names.append(MenuRows.layout_of(row).get_node("Name").text)
	return names


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_game.get_node("EnemySpawner").spawn_timer.stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	_menu = _game.get_node("PauseLayer/PauseMenu")
	# RESTART / MAIN MENU / QUIT only report here, instead of restarting or quitting.
	for sig_name: String in ["restart_requested", "main_menu_requested", "exit_requested"]:
		var sig: Signal = _menu.get(sig_name)
		for c in sig.get_connections():
			sig.disconnect(c["callable"])
		sig.connect(func() -> void: _requests.append(sig_name))
	_menu.resume_requested.connect(func() -> void: _requests.append("resume_requested"))

	print("\n[A] Esc pauses and opens the menu; Esc again resumes")
	check(not _menu.visible and not tree.paused, "the stage starts running")
	await _key(KEY_ESCAPE)
	check(_menu.visible and tree.paused and _focus() == _menu._resume_button, "Esc: paused, RESUME focused")
	check(_menu._main_panel.visible and not _menu._settings_panel.visible and not _menu._controls.visible,
		"the first page shows")
	check(_menu._resume_button.theme_type_variation == &"MenuItemButton" and _menu.theme != null,
		"in the title menus' style")
	await _key(KEY_ESCAPE)
	check(not _menu.visible and not tree.paused and _requests == ["resume_requested"], "Esc again: resumed")

	print("\n[B] SETTINGS: sound, vibration and fullscreen, straight from the pause")
	await _key(KEY_ESCAPE)
	var order: Array = []
	for button: Button in _menu._page_items(0):
		order.append(button.text)
	check(order == ["RESUME", "RESTART STAGE", "MAIN MENU", "SETTINGS", "QUIT GAME"], "the order: %s" % str(order))
	var in_panel: Array = []
	for child in _menu._resume_button.get_parent().get_children():
		if child is Button:
			in_panel.append(child.text)
	check(in_panel == order, "and the panel shows them in that order")
	await _key(KEY_UP)
	await _key(KEY_UP)
	check(_focus() == _menu._settings_button, "up twice (round past QUIT GAME): SETTINGS")
	await _key(KEY_ENTER)
	check(_menu._settings_panel.visible and not _menu._main_panel.visible and _focus() == _menu._common.sfx_row,
		"Enter: the settings page, on SFX VOLUME")
	check(_row_names() == ["SFX VOLUME", "MUSIC VOLUME", "VIBRATION", "FULLSCREEN", "P1 CONTROLS", "P2 CONTROLS"],
		"its rows: %s" % str(_row_names()))
	var sfx := SoundManager.get_sfx_volume()
	await _key(KEY_LEFT)
	check(is_equal_approx(SoundManager.get_sfx_volume(), snappedf(sfx, 0.1) - 0.1)
		and is_equal_approx(InputSettings.get_saved_sfx_volume(), SoundManager.get_sfx_volume()),
		"left on SFX VOLUME turns it down a step, and saves it")
	check(MenuRows.value_label(_menu._common.sfx_row).text == CommonSettings.format_volume(SoundManager.get_sfx_volume()),
		"the row shows the new level")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	check(_focus() == _menu._common.vibration_row, "down twice: VIBRATION")
	var vibration := InputSettings.get_saved_vibration()
	await _key(KEY_ENTER)
	check(InputSettings.get_saved_vibration() != vibration
		and MenuRows.value_label(_menu._common.vibration_row).text == ("ON" if not vibration else "OFF"),
		"Enter toggles vibration")
	check(MenuRows.value_label(_menu._common.fullscreen_row).text == ("ON" if WindowManager.is_fullscreen() else "OFF"),
		"FULLSCREEN shows the window's state")
	check(tree.paused and _menu.visible, "and the stage stays paused throughout")

	print("\n[C] P1 CONTROLS: the controls page, inside the pause")
	_menu._common.p1_row.grab_focus()
	await _key(KEY_ENTER)
	var cp = _menu._controls
	check(cp.visible and not _menu._settings_panel.visible and cp._title.text == "P1 CONTROLS"
		and cp._tab == cp.Tab.KEYBOARD, "Enter: P1 CONTROLS on the KEYBOARD tab (opened with a key)")
	check(_focus() == cp._action_rows[0], "focus on UP")
	cp._action_rows[4].grab_focus()   # FIRE 1
	await _key(KEY_ENTER)
	check(cp._capture_action == "p1_shoot", "Enter on FIRE 1 waits for a key")
	await _key(KEY_ESCAPE)
	check(cp._capture_action == "" and cp.visible and _menu.visible and tree.paused,
		"Esc during the wait cancels it, and nothing else")
	await _key(KEY_ENTER)
	await _key(KEY_K)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	check(InputSettings.get_binding("p1_shoot") == KEY_K and InputMap.event_is_action(k, "p1_shoot"),
		"K is P1's fire key now, in the game straight away")
	await _key(KEY_ESCAPE)
	check(_menu._settings_panel.visible and not cp.visible and _focus() == _menu._common.p1_row,
		"Esc: back to the settings, on P1 CONTROLS")
	check(MenuRows.value_label(_menu._common.p1_row).text.contains("K"), "whose keys now read %s" % MenuRows.value_label(_menu._common.p1_row).text)
	await _key(KEY_ESCAPE)
	check(_menu._main_panel.visible and _focus() == _menu._settings_button, "Esc: back to the first page, on SETTINGS")
	await _key(KEY_ESCAPE)
	check(not _menu.visible and not tree.paused, "Esc: resumed")
	InputSettings.reset_to_defaults("p1")

	print("\n[D] With a controller: Start, the D-pad, A and B")
	await _pad(JOY_BUTTON_START)
	check(_menu.visible and tree.paused, "Start pauses")
	for i in 3:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	check(_menu._settings_panel.visible, "down three times, A: the settings")
	for i in 4:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus() == _menu._common.p1_row, "down four times: P1 CONTROLS")
	await _pad(JOY_BUTTON_A)
	check(cp.visible and cp._tab == cp.Tab.GAMEPAD and _focus() == cp._pad_rows[0],
		"A: P1 CONTROLS on the GAMEPAD tab (opened with a pad), on MOVE")
	await _pad(JOY_BUTTON_B)
	check(_menu._settings_panel.visible and _focus() == _menu._common.p1_row, "B: back to the settings")
	await _pad(JOY_BUTTON_B)
	check(_menu._main_panel.visible, "B: back to the first page")
	await _pad(JOY_BUTTON_START)
	check(not _menu.visible and not tree.paused, "Start: resumed")

	print("\n[E] RESTART STAGE, MAIN MENU and QUIT GAME hand over to the game")
	for pick: Array in [[_menu._restart_button, "restart_requested"], [_menu._main_menu_button, "main_menu_requested"],
			[_menu._quit_button, "exit_requested"]]:
		_requests.clear()
		await _key(KEY_ESCAPE)
		(pick[0] as Button).grab_focus()
		await _key(KEY_ENTER)
		check(_requests == [pick[1]] and not _menu.visible and not tree.paused,
			"%s: unpaused, then %s" % [(pick[0] as Button).text, pick[1]])

	print("\n[F] Mouse, and no pausing during a game over")
	await _key(KEY_ESCAPE)
	_menu._settings_button.mouse_entered.emit()
	check(_focus() == _menu._settings_button, "hovering a button focuses it")
	await _key(KEY_ESCAPE)
	_menu.set_can_open(false)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	check(not _menu.visible and not tree.paused, "while it can't open, Esc does nothing")
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

	await tree.create_timer(0.5).timeout  # let the menu sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
