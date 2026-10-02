extends Node
## Headless test for the ONLINE BATTLE screen: the saved connections, like
## bookmarks. CREATE opens the connection window (USERNAME, ADDRESS, PASSWORD,
## JOIN), which checks what was typed, keeps the connection and joins; each
## connection's MORE pops up CONNECT, EDIT and DELETE; the list keeps the most
## recently used first, a connection once, and is kept in the settings; a join
## says how it goes and stops on Esc; a game that ended says why here. Also the
## address parser and the password's proof. The network parts of joining (the
## password turned away, a real join) are online_test's. A test run keeps its
## own settings, so the player's connections are never touched.
## Run as an override main scene:
##   Godot --headless res://scenes/test/online_screen_test.tscn

const SCREEN := "res://scenes/online_screen.tscn"

var _fail := 0
var _screen    # the screen under test (untyped: the test reads its private state)


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	# If anything changed scene, it would free this node as the current scene.
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	(func() -> void: get_tree().current_scene = stand_in).call_deferred()
	_run.call_deferred()


func _key(code: Key, shift: bool = false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.shift_pressed = shift
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
	await get_tree().process_frame


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


## The mouse coming over [param control]. (A headless run never tells the
## window the mouse is in it, so a mouse motion there hovers nothing: the
## control is told directly.)
func _hover(control: Control) -> void:
	control.mouse_entered.emit()
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _open() -> void:
	if _screen != null:
		get_tree().root.remove_child(_screen)
		_screen.free()
	_screen = load(SCREEN).instantiate()
	get_tree().root.add_child(_screen)
	await get_tree().process_frame
	await get_tree().process_frame


func _wait(cond: Callable, limit: float) -> bool:
	var waited := 0.0
	while not cond.call() and waited < limit:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return cond.call()


func _field(row: Button) -> LineEdit:
	return _screen._field(row)


func _addresses() -> Array:
	var out: Array = []
	for info: Dictionary in _screen._connections:
		out.append(info["address"])
	return out


## What connection [param index]'s row shows, its labels in order.
func _row_texts(index: int) -> Array:
	var out: Array = []
	var pending: Array = [MenuRows.layout_of(_screen._rows[index])]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		if node is Label:
			out.append(node.text)
		pending = node.get_children() + pending
	return out


## The buttons beside connection [param index]'s row.
func _beside(index: int) -> Array:
	var texts: Array = []
	for child in _screen._rows[index].get_parent().get_children():
		if child is Button and child != _screen._rows[index]:
			texts.append(child.text)
	return texts


## The connections as the settings file has them, read afresh.
func _saved() -> Array:
	var config := ConfigFile.new()
	if config.load(InputSettings.get_save_path()) != OK:
		return []
	return config.get_value("online", "connections", [])


## Opens CREATE's window and fills it in, as a player would type it.
func _fill_new(player_name: String, address: String, password: String) -> void:
	_screen._create_button.pressed.emit()
	await get_tree().process_frame
	_field(_screen._name_row).text = player_name
	_field(_screen._address_row).text = address
	_field(_screen._password_row).text = password


## A port nothing listens on.
func _closed_port() -> int:
	var server := TCPServer.new()
	var port := 42000 + randi() % 8000
	server.listen(port, "127.0.0.1")
	server.stop()
	return port


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return
	check(InputSettings.get_online_connections().is_empty(), "a test run starts with no connections of its own")

	print("\n[A] The address and the password's proof")
	var parts := {
		"10.0.0.5": ["10.0.0.5", Net.DEFAULT_PORT], "10.0.0.5:3000": ["10.0.0.5", 3000],
		"  name.lan  ": ["name.lan", Net.DEFAULT_PORT], "[fe80::1]:30000": ["fe80::1", 30000],
		"fe80::1": ["fe80::1", Net.DEFAULT_PORT], "[fe80::1]": ["fe80::1", Net.DEFAULT_PORT],
		"host:0": ["host", 0], "host:70000": ["host", 0], "host:abc": ["host", 0], "[::1]x": ["::1", 0],
	}
	var wrong_parts: Array = []
	for text: String in parts:
		if Net.split_address(text) != parts[text]:
			wrong_parts.append([text, Net.split_address(text)])
	check(wrong_parts.is_empty(), "IP, IP:PORT, a name, IPv6 with and without its port, and bad ports: %s" % str(wrong_parts))
	var nonce := Crypto.new().generate_random_bytes(Net.NONCE_SIZE)
	var proof := Net.password_proof("Tank 1.22", nonce)
	check(proof.size() == 32 and proof == Net.password_proof("Tank 1.22", nonce), "a password's proof: 32 bytes, the same each time")
	check(proof != Net.password_proof("tank 1.22", nonce) and proof != Net.password_proof("Tank 1.22",
			Crypto.new().generate_random_bytes(Net.NONCE_SIZE)), "and different for another password or challenge")
	check(proof.get_string_from_utf8().find("Tank") == -1, "without the password in it")

	print("\n[B] An empty list")
	await _open()
	check(_screen.get_node("Header").text == "ONLINE BATTLE", "headed ONLINE BATTLE")
	check(_screen._empty_label.visible and not _screen._scroll.visible, "no connections: the list says how to add one")
	check(_screen._create_button.text == "CREATE" and _screen._back_button.text == "BACK", "the footer: CREATE and BACK")
	check(_focus() == _screen._create_button, "CREATE has the focus")
	await _key(KEY_RIGHT)
	check(_focus() == _screen._back_button, "right: BACK")
	await _key(KEY_LEFT)
	check(_focus() == _screen._create_button, "left: CREATE")

	print("\n[C] CREATE: the connection window, typed in")
	await _key(KEY_ENTER)
	check(_screen._form_layer.visible and _screen._form_title.text == "NEW CONNECTION"
			and _screen._submit_button.text == "JOIN" and _screen._cancel_button.text == "CANCEL",
			"Enter on CREATE: the NEW CONNECTION window, with JOIN and CANCEL")
	var titles: Array = []
	for row: Button in [_screen._name_row, _screen._address_row, _screen._password_row]:
		titles.append((MenuRows.layout_of(row).get_node("Name") as Label).text)
	check(titles == ["USERNAME", "ADDRESS", "PASSWORD"], "its fields: %s" % str(titles))
	check(_field(_screen._name_row).text == "PLAYER" and _field(_screen._address_row).text.is_empty()
			and _field(_screen._password_row).text.is_empty(), "the name played under before (none yet: PLAYER), the rest empty")
	check(_field(_screen._password_row).placeholder_text == "OPTIONAL" and _field(_screen._password_row).secret,
			"PASSWORD is optional, and shows as dots")
	check(_focus() == _field(_screen._address_row) and _screen._editing == _focus(), "ready to type the address")
	check(_screen._hint.text == _screen.FORM_HINT, "the hint says how to type")
	await _hover(_screen._name_row)
	check(_focus() == _field(_screen._address_row), "the mouse passing over another row doesn't take the keys away")
	await _type("192.168.1.30")
	check(_field(_screen._address_row).text == "192.168.1.30", "typed: %s" % _field(_screen._address_row).text)
	await _key(KEY_ENTER)
	check(_focus() == _field(_screen._password_row), "Enter: on to PASSWORD")
	await _type("sesame")
	check(_field(_screen._password_row).text == "sesame", "a password typed")
	await _key(KEY_TAB)
	check(_focus() == _field(_screen._name_row), "Tab: round to USERNAME")
	await _key(KEY_TAB, true)
	check(_focus() == _field(_screen._password_row), "Shift+Tab: back to PASSWORD")
	await _key(KEY_ENTER)
	check(_focus() == _screen._submit_button and _screen._editing == null, "Enter on the last field: on JOIN, done typing")
	await _key(KEY_RIGHT)
	check(_focus() == _screen._cancel_button, "right: CANCEL")
	await _key(KEY_UP)
	check(_focus() == _screen._password_row, "up, from either button: the PASSWORD row")
	await _key(KEY_ENTER)
	check(_focus() == _field(_screen._password_row), "Enter on a row types in its field")
	await _key(KEY_ESCAPE)
	check(_focus() == _screen._password_row and _screen._editing == null and _screen._form_layer.visible,
			"Esc: done typing, still in the window")
	await _hover(_screen._address_row)
	check(_focus() == _screen._address_row, "not typing, the mouse takes the focus as ever")
	await _key(KEY_ESCAPE)
	check(not _screen._form_layer.visible and _focus() == _screen._create_button, "Esc again closes it, back on CREATE")
	check(InputSettings.get_online_connections().is_empty() and _saved().is_empty(), "and nothing was kept")

	print("\n[D] JOIN checks what was typed")
	await _fill_new("", "10.0.0.5", "")
	_screen._submit_button.pressed.emit()
	check(_screen._form_layer.visible and _screen._form_note.text == "Enter a name first."
			and _screen._form_note.has_theme_color_override("font_color") and _focus() == _screen._name_row,
			"no name: it says so, in red, on USERNAME")
	_field(_screen._name_row).text = "Sean"
	_field(_screen._address_row).text = "   "
	_screen._submit_button.pressed.emit()
	check(_screen._form_note.text == "Enter the host's address first." and _focus() == _screen._address_row,
			"no address: %s" % _screen._form_note.text)
	for bad: String in ["10.0.0.5:99999", "10.0.0.5:abc"]:
		_field(_screen._address_row).text = bad
		_screen._submit_button.pressed.emit()
		check(_screen._form_note.text == "That port isn't a number from 1 to 65535.", "%s: a bad port" % bad)
	check(_screen._form_layer.visible and _saved().is_empty() and not Net.is_online(), "still open, nothing kept, no join")
	_screen._cancel_button.pressed.emit()
	await tree.process_frame
	check(not _screen._form_layer.visible, "CANCEL closes it")

	print("\n[E] JOIN keeps the connection and joins")
	var closed := _closed_port()
	var address := "127.0.0.1:%d" % closed
	await _fill_new(" sean ", address, "Open Sesame")
	_screen._submit_button.pressed.emit()
	await tree.process_frame
	check(not _screen._form_layer.visible and _addresses() == [address], "the window closes; the list has it: %s" % str(_addresses()))
	var saved := _saved()
	check(saved.size() == 1 and saved[0]["name"] == "SEAN" and saved[0]["address"] == address
			and saved[0]["password"] == "Open Sesame" and saved[0]["joined"] == "",
			"kept in the settings: the name as the screens show names, the password as typed: %s" % str(saved))
	check(_row_texts(0) == [address, "SEAN", "PASSWORD SAVED", "NOT JOINED YET"], "its row: %s" % str(_row_texts(0)))
	check(_beside(0) == ["MORE"], "beside it, MORE alone")
	check(Net.is_client() and _screen._busy() and _screen._hint.text == "Connecting to 127.0.0.1 : %d ..." % closed,
			"joining: %s" % _screen._hint.text)
	_screen._create_button.pressed.emit()
	_screen._more_buttons[0].pressed.emit()
	await tree.process_frame
	check(not _screen._form_layer.visible and not _screen._popup_layer.visible, "while it joins, the list waits")
	check(await _wait(func() -> bool: return not _screen._busy(), 10.0), "nothing there: the join ends")
	check(_screen._hint.text == "No game answered at that address." and _screen._hint.has_theme_color_override("font_color")
			and not Net.is_online(), "saying why, in red: %s" % _screen._hint.text)
	await tree.process_frame
	check(get_tree().current_scene.scene_file_path.is_empty() and Net.take_end_reason().is_empty(),
			"here, where it was started: no scene change, nothing left to say later")

	print("\n[F] Esc stops a join under way")
	var silent := TCPServer.new()  # takes the connection, never answers
	var silent_port := closed + 1
	silent.listen(silent_port, "127.0.0.1")
	await _fill_new("SEAN", "127.0.0.1:%d" % silent_port, "")
	_screen._submit_button.pressed.emit()
	await tree.create_timer(0.3).timeout
	check(_screen._busy() and Net.is_client(), "joining a game that doesn't answer")
	check(_addresses() == ["127.0.0.1:%d" % silent_port, address], "the newest first: %s" % str(_addresses()))
	check(_row_texts(0) == ["127.0.0.1:%d" % silent_port, "SEAN", "NOT JOINED YET"], "no password, no PASSWORD SAVED")
	await _key(KEY_ESCAPE)
	check(not _screen._busy() and not Net.is_online() and _screen._hint.text == "Stopped connecting."
			and _screen.is_inside_tree(), "Esc stops it and stays: %s" % _screen._hint.text)
	silent.stop()

	print("\n[G] A connection kept once")
	await _fill_new("sean", address, "new one")
	_screen._submit_button.pressed.emit()
	await tree.process_frame
	check(_addresses() == [address, "127.0.0.1:%d" % silent_port], "the same game under the same name: no second copy, moved up")
	check(_saved().size() == 2 and _saved()[0]["password"] == "new one", "with the password given now")
	await _wait(func() -> bool: return not _screen._busy(), 10.0)

	print("\n[H] Saved connections: newest first, MORE's options")
	var list: Array[Dictionary] = [
		{"name": "SEAN", "address": "192.168.1.20:24680", "password": "", "used": 100.0, "joined": "2026-09-30 20:11:05"},
		{"name": "ALEX", "address": "tank.example.com", "password": "secret", "used": 300.0, "joined": ""},
		{"name": "SEAN", "address": "[fe80::1]:30000", "password": "", "used": 200.0, "joined": "2026-10-01 14:30:00"},
	]
	InputSettings.save_online_connections(list)
	await _open()
	check(_addresses() == ["tank.example.com", "[fe80::1]:30000", "192.168.1.20:24680"], "most recently used first: %s" % str(_addresses()))
	check(_row_texts(1) == ["[fe80::1]:30000", "SEAN", "JOINED 2026-10-01  14:30"], "when it last got in: %s" % str(_row_texts(1)))
	check(_focus() == _screen._rows[0], "the newest has the focus")
	_screen._create_button.pressed.emit()
	check(_field(_screen._name_row).text == "ALEX", "CREATE offers the name last played under: %s" % _field(_screen._name_row).text)
	_screen._cancel_button.pressed.emit()
	_screen._rows[0].grab_focus()
	await _key(KEY_DOWN)
	check(_focus() == _screen._rows[1], "down: the next")
	await _key(KEY_RIGHT)
	check(_focus() == _screen._more_buttons[1], "right: its MORE")
	await _key(KEY_LEFT)
	check(_focus() == _screen._rows[1], "left: back")
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	var options: Array = []
	for button: Button in _screen._popup_buttons:
		options.append(button.text)
	check(_screen._popup_layer.visible and _screen._popup_title.text == "[fe80::1]:30000" and options == ["CONNECT", "EDIT", "DELETE"]
			and _focus() == _screen._popup_buttons[0] and _screen._hint.text == _screen.OPTIONS_HINT,
			"MORE: a window titled with its address: %s" % str(options))
	var window: Rect2 = _screen._popup.get_global_rect()
	var more_rect: Rect2 = _screen._more_buttons[1].get_global_rect()
	check(absf(window.end.x - more_rect.end.x) < 1.0 and window.position.y >= more_rect.end.y,
			"under MORE, lined up with its right edge")
	var walked: Array = []
	for i in 3:
		await _key(KEY_DOWN)
		walked.append(_focus().text)
	check(walked == ["EDIT", "DELETE", "CONNECT"], "down walks the options, round again: %s" % str(walked))
	await _key(KEY_ESCAPE)
	check(not _screen._popup_layer.visible and _focus() == _screen._more_buttons[1], "Esc closes it, back on MORE")

	print("\n[I] EDIT")
	_screen._more_buttons[1].pressed.emit()
	_screen._popup_buttons[1].pressed.emit()
	await tree.process_frame
	check(_screen._form_layer.visible and _screen._form_title.text == "EDIT CONNECTION" and _screen._submit_button.text == "SAVE",
			"EDIT: the EDIT CONNECTION window, with SAVE")
	check(_field(_screen._name_row).text == "SEAN" and _field(_screen._address_row).text == "[fe80::1]:30000"
			and _field(_screen._password_row).text.is_empty() and _focus() == _screen._name_row,
			"what was kept, on USERNAME")
	_field(_screen._name_row).text = "sam"
	_field(_screen._password_row).text = "pw"
	_screen._submit_button.pressed.emit()
	await tree.process_frame
	check(not _screen._form_layer.visible and _addresses()[1] == "[fe80::1]:30000"
			and _row_texts(1) == ["[fe80::1]:30000", "SAM", "PASSWORD SAVED", "JOINED 2026-10-01  14:30"],
			"SAVE: changed in its place: %s" % str(_row_texts(1)))
	check(_saved()[1]["name"] == "SAM" and _saved()[1]["password"] == "pw" and not Net.is_online(),
			"kept in the settings, and nothing joined")
	_screen._more_buttons[1].pressed.emit()
	_screen._popup_buttons[1].pressed.emit()
	_field(_screen._name_row).text = "NOBODY"
	await _key(KEY_ESCAPE)
	check(not _screen._form_layer.visible and _focus() == _screen._more_buttons[1] and _saved()[1]["name"] == "SAM",
			"closed without SAVE: unchanged, back on its MORE")

	print("\n[J] DELETE, after CONFIRM?")
	_screen._more_buttons[2].pressed.emit()
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	check(_screen._delete_button.text == "CONFIRM?" and _screen._hint.text == _screen.CONFIRM_HINT, "DELETE asks first")
	await _key(KEY_UP)
	check(_screen._delete_button.text == "DELETE" and _addresses().size() == 3, "moving away cancels")
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	check(_addresses() == ["tank.example.com", "[fe80::1]:30000"] and _saved().size() == 2,
			"CONFIRM? deletes it, from the settings too")
	check(_focus() == _screen._rows[1], "the focus stays in the list")

	print("\n[K] A game that ended says why here")
	Net._last_end_reason = Net.END_KICKED
	await _open()
	check(_screen._hint.text == "The host removed you from the game." and _screen._hint.has_theme_color_override("font_color"),
			"kicked: %s" % _screen._hint.text)
	await _open()
	check(_screen._hint.text == _screen.DEFAULT_HINT, "said once")

	Net.leave()
	get_tree().root.remove_child(_screen)
	_screen.free()
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
