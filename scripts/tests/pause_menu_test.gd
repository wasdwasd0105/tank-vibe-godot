extends Node
## Headless test for the pause menu: Esc or Start opens it over the paused
## stage; RESUME / RESTART STAGE / ENTER FULLSCREEN (it switches and stays) /
## SETTINGS / MAIN MENU / QUIT GAME; the settings page changes sound, whether
## the game always opens fullscreen, the game's speed (the stage's clock follows it,
## and time runs normally again outside the stage), a key and a player's
## vibration without leaving the stage, and opens a player's controls page (the title screen's) on the
## right tab; Esc, B and Start step back a page at a time. The settings' ONLINE
## tab opens the game to remote players (its port, password and most players
## typed and kept), and once someone has joined, HOST shows on the first page.
## Driven by simulated keys and controller buttons. A test run keeps its own
## settings file.
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


## Types [param text] into whatever has the keys, as a keyboard would.
func _type(text: String) -> void:
	for i in text.length():
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.unicode = text.unicode_at(i)
			ev.pressed = pressed
			Input.parse_input_event(ev)
			Input.flush_buffered_events()
	await get_tree().process_frame


## The settings file as it is on disk, read afresh.
func _settings_file() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(InputSettings.get_save_path())
	return config


## The GAME tab's rows' names.
func _game_row_names() -> Array:
	var names: Array = []
	for row: Button in _menu._game.rows():
		names.append(MenuRows.layout_of(row).get_node("Name").text)
	return names


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

	print("\n[B] SETTINGS: the game's rules, sound and fullscreen, straight from the pause")
	await _key(KEY_ESCAPE)
	var order: Array = []
	for button: Button in _menu._page_items(0):
		order.append(button.text)
	check(order == ["RESUME", "RESTART STAGE", "ENTER FULLSCREEN", "SETTINGS", "MAIN MENU", "QUIT GAME"],
		"the order: %s" % str(order))
	var in_panel: Array = []
	for child in _menu._resume_button.get_parent().get_children():
		if child is Button and child.visible:   # PLAYER 2 hides in a one-player game
			in_panel.append(child.text)
	check(in_panel == order, "and the panel shows them in that order")
	for i in 3:
		await _key(KEY_UP)
	check(_focus() == _menu._settings_button, "up three times (round past QUIT GAME and MAIN MENU): SETTINGS")
	await _key(KEY_ENTER)
	check(_menu._settings_panel.visible and not _menu._main_panel.visible and _focus() == _menu._common.sfx_row,
		"Enter: the settings page, on its GENERAL tab, on SFX VOLUME")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(_menu._game_rows.visible and not _menu._settings_rows.visible and _focus() == _menu._game.difficulty_row,
		"RB: the GAME tab, on DIFFICULTY")
	check(_game_row_names() == ["DIFFICULTY", "GAME SPEED", "BASE INVINCIBLE", "ENEMY MINES", "ENEMY MINE LEVEL"],
		"the GAME tab's rows: %s" % str(_game_row_names()))
	var difficulty := GameManager.difficulty
	await _key(KEY_RIGHT)
	check(GameManager.difficulty == difficulty + 1 and InputSettings.get_saved_difficulty() == difficulty + 1
		and MenuRows.value_label(_menu._game.difficulty_row).text.begins_with(str(difficulty + 1)),
		"right on DIFFICULTY: the game's goes up at once, mid-stage, and is kept for new games")
	await _key(KEY_LEFT)
	check(GameManager.difficulty == difficulty, "left: back down")
	var speed_row: Button = _menu._game.game_speed_row
	var speed_text := func() -> String: return MenuRows.value_label(speed_row).text
	await _key(KEY_DOWN)
	check(_focus() == speed_row and speed_text.call() == "100%" and is_equal_approx(Engine.time_scale, 1.0),
		"down: GAME SPEED, 100% as the original's default, the stage at normal time")
	await _key(KEY_RIGHT)
	check(InputSettings.get_saved_game_speed() == 117 and speed_text.call() == "117%"
		and is_equal_approx(Engine.time_scale, 1.17), "right: 117%, saved, and the stage's clock runs at it")
	for i in 4:
		await _key(KEY_RIGHT)
	check(InputSettings.get_saved_game_speed() == 150 and MenuRows.arrow(speed_row, "Right").disabled
		and is_equal_approx(Engine.time_scale, 1.5), "up to 150%, the original's fastest, and no further")
	for i in 5:
		await _key(KEY_LEFT)
	check(InputSettings.get_saved_game_speed() == 83 and MenuRows.arrow(speed_row, "Left").disabled
		and is_equal_approx(Engine.time_scale, 0.83), "down to 83%, its slowest")
	await _key(KEY_RIGHT)
	check(InputSettings.get_saved_game_speed() == 100 and is_equal_approx(Engine.time_scale, 1.0), "and back to 100%")
	var base_row: Button = _menu._game.base_row
	await _key(KEY_DOWN)
	check(_focus() == base_row and MenuRows.value_label(base_row).text == "OFF" and not _game.eagle.invincible,
		"down: BASE INVINCIBLE, OFF")
	await _key(KEY_ENTER)
	check(InputSettings.get_base_invincible() and MenuRows.value_label(base_row).text == "ON" and _game.eagle.invincible,
		"Enter: ON, saved, and the stage's flag shows the guard at once")
	await _key(KEY_ENTER)
	check(not InputSettings.get_base_invincible() and not _game.eagle.invincible, "Enter: OFF again")
	var mines_row: Button = _menu._game.enemy_mines_row
	var level_row: Button = _menu._game.mine_level_row
	await _key(KEY_DOWN)
	check(_focus() == mines_row and MenuRows.value_label(mines_row).text == "ON" and not level_row.disabled,
		"down: ENEMY MINES, ON")
	await _key(KEY_ENTER)
	check(not InputSettings.get_enemy_mines() and MenuRows.value_label(mines_row).text == "OFF" and level_row.disabled
		and level_row.modulate.a < 1.0, "Enter: OFF, and ENEMY MINE LEVEL greys out")
	await _key(KEY_DOWN)
	check(_focus() == _menu._settings_back_button, "down skips the greyed row: BACK")
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	await _key(KEY_DOWN)
	check(InputSettings.get_enemy_mines() and _focus() == level_row and MenuRows.value_label(level_row).text == "3"
		and level_row.modulate.a == 1.0, "ON again: down to ENEMY MINE LEVEL, 3, no longer dimmed")
	await _key(KEY_RIGHT)
	check(InputSettings.get_enemy_mine_level() == 4 and MenuRows.arrow(level_row, "Right").disabled, "right: 4, the most")
	await _key(KEY_LEFT)
	check(InputSettings.get_enemy_mine_level() == 3, "left: 3")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	check(_menu._settings_rows.visible and not _menu._game_rows.visible and _focus() == _menu._common.sfx_row,
		"LB: back to the GENERAL tab, on SFX VOLUME")
	check(_row_names() == ["SFX VOLUME", "MUSIC VOLUME", "FULLSCREEN", "ALWAYS FULLSCREEN", "LANGUAGE",
		"P1 CONTROLS", "P2 CONTROLS"],
		"its rows, VIBRATION being on each player's controls page and GAME SPEED on the GAME tab: %s" % str(_row_names()))
	var sfx := SoundManager.get_sfx_volume()
	await _key(KEY_LEFT)
	check(is_equal_approx(SoundManager.get_sfx_volume(), snappedf(sfx, 0.1) - 0.1)
		and is_equal_approx(InputSettings.get_saved_sfx_volume(), SoundManager.get_sfx_volume()),
		"left on SFX VOLUME turns it down a step, and saves it")
	check(MenuRows.value_label(_menu._common.sfx_row).text == CommonSettings.format_volume(SoundManager.get_sfx_volume()),
		"the row shows the new level")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	check(_focus() == _menu._common.fullscreen_row, "down twice: FULLSCREEN")
	check(MenuRows.value_label(_menu._common.fullscreen_row).text == ("ON" if WindowManager.is_fullscreen() else "OFF"),
		"FULLSCREEN shows the window's state")
	var always_row: Button = _menu._common.always_fullscreen_row
	var asked: Array = []  # what the window was asked for, fullscreen or not
	WindowManager.fullscreen_changed.connect(func(on: bool) -> void: asked.append(on))
	await _key(KEY_DOWN)
	check(_focus() == always_row and MenuRows.value_label(always_row).text == "OFF"
		and not InputSettings.get_always_fullscreen(), "down: ALWAYS FULLSCREEN, OFF out of the box")
	await _key(KEY_RIGHT)
	check(InputSettings.get_always_fullscreen() and MenuRows.value_label(always_row).text == "ON" and asked == [true],
		"right: ON, saved, and in a stage the window goes fullscreen at once (%s)" % str(asked))
	asked.clear()
	WindowManager.leave_game()  # a menu screen comes up
	WindowManager.apply_start_mode()  # as the game opens
	check(asked == [false], "the menus get the window back, and the game opens in it (%s)" % str(asked))
	WindowManager.enter_game()  # a stage entered from the menus
	WindowManager.enter_game()  # the next one
	check(asked == [false, true], "a stage entered from them goes fullscreen; the next stage leaves it be")
	await _key(KEY_LEFT)
	check(not InputSettings.get_always_fullscreen() and MenuRows.value_label(always_row).text == "OFF"
		and asked == [false, true, false], "left: OFF, and the stage goes back to the window at once")
	asked.clear()
	WindowManager.leave_game()
	WindowManager.set_always_fullscreen(true)  # as switched on the title's settings
	check(InputSettings.get_always_fullscreen() and asked.is_empty(), "switched on in the menus: saved, the window left alone")
	WindowManager.set_always_fullscreen(false)
	WindowManager.enter_game()  # back in this stage for the rest of the test
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
	check(_menu._settings_panel.visible and _focus() == _menu._common.sfx_row,
		"down three times, A: the settings, on the GENERAL tab")
	for i in 5:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus() == _menu._common.p1_row,
		"down five times (past FULLSCREEN, ALWAYS FULLSCREEN and LANGUAGE): P1 CONTROLS")
	await _pad(JOY_BUTTON_A)
	check(cp.visible and cp._tab == cp.Tab.GAMEPAD and _focus() == cp._pad_rows[0],
		"A: P1 CONTROLS on the GAMEPAD tab (opened with a pad), on MOVE")
	await _pad(JOY_BUTTON_DPAD_UP)
	check(_focus() == cp._vibration_row and MenuRows.value_label(cp._vibration_row).text == "ON",
		"up: P1's VIBRATION, ON")
	await _pad(JOY_BUTTON_A)
	check(not InputSettings.get_vibration("p1") and InputSettings.get_vibration("p2")
		and MenuRows.value_label(cp._vibration_row).text == "OFF" and tree.paused,
		"A switches P1's vibration off, mid-stage, and leaves P2's on")
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

	print("\n[E2] ENTER FULLSCREEN switches the window and stays in the menu")
	var fullscreen_asks: Array = []
	WindowManager.fullscreen_changed.connect(func(on: bool) -> void: fullscreen_asks.append(on))
	await _key(KEY_ESCAPE)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	check(_focus() == _menu._fullscreen_button and _menu._fullscreen_button.text == "ENTER FULLSCREEN",
		"down twice from RESUME: ENTER FULLSCREEN")
	await _key(KEY_ENTER)
	check(fullscreen_asks == [true] and _menu._fullscreen_button.text == "EXIT FULLSCREEN"
		and _menu.visible and tree.paused and _focus() == _menu._fullscreen_button,
		"Enter: fullscreen, the button now EXIT FULLSCREEN, still paused on it")
	WindowManager.set_fullscreen(false)  # as EXIT FULLSCREEN, F11 or the settings' row would
	check(_menu._fullscreen_button.text == "ENTER FULLSCREEN", "back in a window, however switched: ENTER FULLSCREEN")
	await _key(KEY_ESCAPE)
	check(not _menu.visible and not tree.paused, "Esc: resumed")

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

	await _test_online_tab()

	print("\n[G] The game's speed belongs to the stage")
	InputSettings.save_game_speed(133)
	check(is_equal_approx(Engine.time_scale, 1.33), "133%: the stage runs at it")
	tree.root.remove_child(_game)
	_game.free()
	check(is_equal_approx(Engine.time_scale, 1.0), "the stage gone (the title, the load screen): normal time again")
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false
	tree.root.add_child(_game)
	await tree.process_frame
	check(is_equal_approx(Engine.time_scale, 1.33), "the next stage starts at the setting")
	tree.root.remove_child(_game)
	_game.free()
	InputSettings.save_game_speed(InputSettings.DEFAULT_GAME_SPEED)

	await tree.create_timer(0.5).timeout  # let the menu sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


func _test_online_tab() -> void:
	var tree := get_tree()
	print("\n[H] SETTINGS' ONLINE tab: the game opened to remote players")
	_menu.set_can_open(true)
	await _key(KEY_ESCAPE)
	_menu._settings_button.grab_focus()
	await _key(KEY_ENTER)
	var strip: Button = _menu._tabs.strip
	var tabs: Array = [MenuRows.tab(strip, 0), MenuRows.tab(strip, 1), MenuRows.tab(strip, 2)]
	check(strip.visible and tabs.map(func(tab: Button) -> String: return tab.text) == ["GENERAL", "GAME", "ONLINE"]
		and tabs[0].button_pressed and _focus() == _menu._common.sfx_row,
		"SETTINGS has three tabs, GENERAL first, on SFX VOLUME")
	await tree.process_frame
	var page_rect: Rect2 = _menu._settings_panel.get_global_rect()
	await _key(KEY_UP)
	check(_focus() == strip, "up: the tab strip")
	await _key(KEY_RIGHT)
	check(_menu._game_rows.visible and not _menu._settings_rows.visible and tabs[1].button_pressed
		and _focus() == strip, "right: the GAME tab, still on the strip")
	await tree.process_frame
	check(_menu._settings_panel.get_global_rect() == page_rect, "the page keeps its size")
	await _key(KEY_RIGHT)
	check(_menu._online_tab.visible and not _menu._game_rows.visible and tabs[2].button_pressed
		and not tabs[1].button_pressed and _focus() == strip, "right again: the ONLINE tab, still on the strip")
	await tree.process_frame
	check(_menu._settings_panel.get_global_rect() == page_rect, "still the same size")
	await _key(KEY_RIGHT)
	check(tabs[2].button_pressed, "right at the end stays on ONLINE")
	var titles: Array = []
	for row: Button in [_menu._allow_row, _menu._port_row, _menu._port_type_row, _menu._password_row, _menu._max_row,
			_menu._address_row]:
		titles.append(MenuRows.name_label(row).text)
	check(titles == ["ALLOW REMOTE PLAYERS", "PORT", "PORT TYPE", "PASSWORD", "MAX PLAYERS", "YOUR ADDRESS"],
		"its rows: %s" % str(titles))
	var port_field: LineEdit = MenuRows.field(_menu._port_row)
	var password_field: LineEdit = MenuRows.field(_menu._password_row)
	check(MenuRows.value_label(_menu._allow_row).text == "OFF" and not Net.is_online(), "ALLOW REMOTE PLAYERS: OFF")
	check(port_field.text == "24680" and port_field.editable and password_field.text.is_empty()
		and MenuRows.value_label(_menu._port_type_row).text == "TCP"
		and password_field.placeholder_text == "OPTIONAL" and password_field.secret
		and MenuRows.value_label(_menu._max_row).text == "3 + YOU",
		"out of the box: port 24680 over TCP, no password (dots, when there is one), 3 others besides you")
	check(_menu._players_caption.text == "CONNECTED PLAYERS   0 / 3" and _menu._player_lines[0].text == "NO ONE YET",
		"CONNECTED PLAYERS: nobody")
	await _key(KEY_DOWN)
	check(_focus() == _menu._allow_row, "down: ALLOW REMOTE PLAYERS")

	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	check(_focus() == port_field and _menu._typing == port_field, "Enter on PORT: typing in it")
	_menu._password_row.mouse_entered.emit()
	check(_focus() == port_field, "the mouse passing over another row doesn't take the keys away")
	port_field.text = ""
	await _type("70000")
	await _key(KEY_ENTER)
	check(_focus() == _menu._port_row and _menu._typing == null and port_field.text == "24680"
		and _menu._online_note.text == "That port isn't a number from 1 to 65535."
		and _menu._online_note.has_theme_color_override("font_color"), "70000: not a port, it says so in red; still 24680")
	var port := 42000 + randi() % 8000
	await _key(KEY_ENTER)
	port_field.text = ""
	await _type(str(port))
	await _key(KEY_ENTER)
	check(InputSettings.get_online_port() == port and _settings_file().get_value("online", "port") == port,
		"a port that is one is kept: %d" % port)
	await _key(KEY_DOWN)
	check(_focus() == _menu._port_type_row, "down: PORT TYPE")
	await _key(KEY_RIGHT)
	check(MenuRows.value_label(_menu._port_type_row).text == "UDP" and _settings_file().get_value("online", "port_type") == "UDP",
		"right: UDP, kept")
	await _key(KEY_LEFT)
	check(InputSettings.get_host_port_type() == "TCP", "left: TCP again")
	await _key(KEY_ENTER)
	check(InputSettings.get_host_port_type() == "UDP", "and Enter steps it too: UDP, for the game opened below")
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _type("Tank 1.22")
	await _key(KEY_ESCAPE)
	check(_focus() == _menu._password_row and InputSettings.get_host_password() == "Tank 1.22"
		and _settings_file().get_value("online", "host_password") == "Tank 1.22", "PASSWORD: kept exactly as typed")
	check(_menu.visible and tree.paused and _menu._settings_panel.visible, "Esc while typing only stops the typing")
	_menu._max_row.mouse_entered.emit()
	check(_focus() == _menu._max_row, "not typing, the mouse takes the focus as ever")
	await _key(KEY_LEFT)
	check(MenuRows.value_label(_menu._max_row).text == "2 + YOU" and _settings_file().get_value("online", "max_players") == 2,
		"MAX PLAYERS: left, 2 others, kept")
	await _key(KEY_LEFT)
	await _key(KEY_LEFT)
	check(InputSettings.get_host_max_players() == 1 and MenuRows.arrow(_menu._max_row, "Left").disabled,
		"down to 1, and no further")
	await _key(KEY_RIGHT)
	check(InputSettings.get_host_max_players() == 2, "right: 2")

	_menu._allow_row.grab_focus()
	await _key(KEY_RIGHT)
	check(Net.is_host() and Net.port == port and Net.has_password() and Net.max_clients == 2 and not Net.lock_new,
		"ALLOW REMOTE PLAYERS, right: hosting, on that port, with the password, up to 2 others")
	check(Net.transport == Net.Transport.UDP and Net._peer is ENetMultiplayerPeer, "over UDP: an ENet server")
	check(MenuRows.value_label(_menu._allow_row).text == "ON" and not port_field.editable
		and _menu._online_note.text == "Open: others join from ONLINE BATTLE at YOUR ADDRESS.", "ON, the port fixed while open")
	check(MenuRows.value_label(_menu._address_row).text.ends_with(" : %d" % port),
		"YOUR ADDRESS: %s" % MenuRows.value_label(_menu._address_row).text)
	check(_game.has_node("NetHostWorld") and Net.host_screen == Net.SCREEN_GAME, "the stage goes out to whoever joins")
	check(PlayerInput.seats == [PlayerInput.LOCAL_P1, PlayerInput.NO_SEAT],
		"player 1 keeps tank 1; tank 2, never joined, is free for whoever presses fire")
	check(tree.paused and _menu.visible, "still paused, in the menu")
	_menu._password_row.grab_focus()
	await _key(KEY_ENTER)
	MenuRows.field(_menu._password_row).text = ""
	await _type("Open Sesame")
	await _key(KEY_ENTER)
	check(Net._password == "Open Sesame" and InputSettings.get_host_password() == "Open Sesame",
		"a new password, while open: newcomers need it from now on")
	_menu._max_row.grab_focus()
	await _key(KEY_LEFT)
	check(Net.max_clients == 1, "MAX PLAYERS, while open: at once")
	await _key(KEY_RIGHT)
	_menu._port_row.grab_focus()
	await _key(KEY_ENTER)
	check(_menu._typing == null and _menu._online_note.text == "The port can't change while the game is open.",
		"the port can't be typed in while open")
	_menu._port_type_row.grab_focus()
	await _key(KEY_RIGHT)
	check(InputSettings.get_host_port_type() == "UDP" and MenuRows.value_label(_menu._port_type_row).text == "UDP"
		and _menu._online_note.text == "The port type can't change while the game is open."
		and MenuRows.arrow(_menu._port_type_row, "Right").disabled, "nor its type")
	_menu._address_row.grab_focus()
	await _key(KEY_ENTER)
	check(MenuRows.value_label(_menu._address_row).text.begins_with("COPIED: "), "Enter on YOUR ADDRESS copies it")

	# Someone joins (a stand-in for one: the real thing is online_test's).
	await _key(KEY_ESCAPE)
	check(_menu._main_panel.visible and not _menu._host_button.visible, "the first page: no HOST while nobody has joined")
	Net.peers[7] = {"name": "CLIENTA", "allow": [true, true]}
	PlayerInput.set_seat(1, PlayerInput.controller_key(7, 0))
	Net.session_changed.emit()
	var order: Array = []
	for button: Button in _menu._page_items(0):
		order.append(button.text)
	check(order == ["RESUME", "RESTART STAGE", "ENTER FULLSCREEN", "SETTINGS", "HOST", "MAIN MENU", "QUIT GAME"],
		"someone joined: HOST, under SETTINGS: %s" % str(order))
	_menu._host_button.grab_focus()
	await _key(KEY_ENTER)
	var drive_names: Array = []
	for peer: int in _menu._drive_rows:
		drive_names.append(MenuRows.name_label(_menu._drive_rows[peer]).text)
	check(_menu._host_panel.visible and drive_names == [Net.local_name, "CLIENTA"] and _menu._kick_rows.keys() == [7],
		"HOST: who may drive what, the host too (%s), and KICK for the one who joined" % str(drive_names))
	check(MenuRows.value_label(_menu._drive_rows[7]).text == "P1 + P2   ·   DRIVING P2", "CLIENTA drives P2")
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	check(Net.peers[7]["allow"] == [true, false] and PlayerInput.seats[1] == PlayerInput.NO_SEAT,
		"right on CLIENTA: P1 ONLY, and tank 2 is taken from them")
	await _key(KEY_ESCAPE)
	_menu._settings_button.grab_focus()
	await _key(KEY_ENTER)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(_menu._online_tab.visible and _menu._players_caption.text == "CONNECTED PLAYERS   1 / 2"
		and _menu._player_lines[0].text == "CLIENTA   ·   WATCHING", "RB twice: the ONLINE tab, CLIENTA connected, watching")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	check(_menu._game_rows.visible and not _menu._online_tab.visible, "LB: back to GAME")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_menu._allow_row.grab_focus()
	await _key(KEY_ENTER)
	check(Net.is_host() and Net.lock_new and MenuRows.value_label(_menu._allow_row).text == "OFF"
		and _menu._online_note.text == "Nobody new can join. The players here stay.",
		"OFF with someone here: nobody new gets in, and they stay")
	await _key(KEY_ENTER)
	check(Net.is_host() and not Net.lock_new and MenuRows.value_label(_menu._allow_row).text == "ON", "ON again: open")
	Net.peers.erase(7)
	Net.session_changed.emit()
	check(not _menu._host_button.visible and _menu._player_lines[0].text == "NO ONE YET", "they left: no HOST, nobody listed")
	await _key(KEY_ENTER)
	check(not Net.is_online() and MenuRows.value_label(_menu._allow_row).text == "OFF" and port_field.editable,
		"OFF with nobody here: the game closes to the network")
	check(not _game.has_node("NetHostWorld") and PlayerInput.seats == [PlayerInput.LOCAL_P1, PlayerInput.LOCAL_P2],
		"and plays on offline, the keys driving their own tanks")

	var udp_blocker := PacketPeerUDP.new()
	if udp_blocker.bind(port) == OK:
		await _key(KEY_ENTER)
		check(not Net.is_online() and MenuRows.value_label(_menu._allow_row).text == "OFF"
			and _menu._online_note.text == "That port is in use. Try another."
			and _menu._online_note.has_theme_color_override("font_color"), "a UDP port in use: it says so, and stays OFF")
		udp_blocker.close()
	_menu._port_type_row.grab_focus()
	await _key(KEY_LEFT)
	_menu._allow_row.grab_focus()
	var blocker := TCPServer.new()
	if blocker.listen(port) == OK:
		await _key(KEY_ENTER)
		check(not Net.is_online() and InputSettings.get_host_port_type() == "TCP"
			and _menu._online_note.text == "That port is in use. Try another.", "and a TCP one")
		blocker.stop()
	await _key(KEY_ENTER)
	check(Net.is_host() and Net.transport == Net.Transport.TCP and Net._peer is WebSocketMultiplayerPeer,
		"a free one over TCP: a WebSocket server")
	await _key(KEY_ENTER)
	check(not Net.is_online(), "OFF: closed again")

	_menu.set_online_client(true)
	await _key(KEY_ESCAPE)
	_menu._settings_button.grab_focus()
	await _key(KEY_ENTER)
	check(not strip.visible and _menu._settings_rows.visible and not _menu._game_rows.visible
		and not _menu._page_items(1).has(strip) and _focus() == _menu._common.sfx_row,
		"a client's settings: GENERAL only, no GAME or ONLINE tab (the host's game and its rules aren't theirs)")
	_menu.set_online_client(false)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	check(not _menu.visible and not tree.paused, "Esc, Esc: resumed")
