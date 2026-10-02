extends Node
## Headless test for rebinding the controller: InputSettings' slots (MOVE, FIRE 1
## and FIRE 2, two slots each; MOVE takes a whole D-pad or stick, a fire slot a
## button or a trigger; a taken input swaps rather than doubles; saved and
## reloaded), A / B / Start keeping their menu jobs, the title screen's
## controls page with its KEYBOARD and GAMEPAD tabs driven by simulated keys and
## controller input, two players sharing one controller, and each player's
## VIBRATION switch. Being a test scene it runs on its own settings file, never
## the player's.
## Run as an override main scene:
##   Godot --headless res://scenes/test/controls_page_test.tscn

var _fail := 0
var _screen   # the title screen (untyped: the test reads its private state)
var _cp       # its controls page (ControlsPage)


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


## The controller codes [param action] answers to on its player's controller.
func _pad_codes(action: String) -> Array:
	var device := InputSettings.get_pad_device(action.get_slice("_", 0))
	var codes: Array = []
	for ev in InputMap.action_get_events(action):
		if (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) and ev.device == device:
			codes.append(InputSettings.pad_code_for(ev))
	codes.sort()
	return codes


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _slots(control: String, player: String = "p1") -> Array:
	return Array(InputSettings.get_pad_slots(player, control))


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()   # parsed events otherwise wait for the next frame
	await get_tree().process_frame


func _pad(button: JoyButton, device: int = 0) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = device
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _axis(axis: JoyAxis, value: float, device: int = 0) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame


## A stick or trigger pushed and let go again.
func _flick(axis: JoyAxis, value: float) -> void:
	await _axis(axis, value)
	await _axis(axis, 0.0)


## The settings file as it is on disk now (a fresh ConfigFile: load() merges).
func _read_settings() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(InputSettings.get_save_path())
	return cfg


func _button_event(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev


## "D-pad | L-stick": the slots shown on GAMEPAD row [param index].
func _shown(index: int) -> String:
	var row: Button = _cp._pad_rows[index]
	return "%s | %s" % [MenuRows.slot(row, 0).text, MenuRows.slot(row, 1).text]


## How GAMEPAD row [param index]'s slots are marked, a letter per slot: "p"
## picked (outlined), "w" waiting (solid), "-" neither.
func _marks(index: int) -> String:
	var row: Button = _cp._pad_rows[index]
	var marks := ""
	for slot in InputSettings.PAD_SLOTS:
		var button := MenuRows.slot(row, slot)
		if button.button_pressed:
			marks += "w"
		elif button.theme_type_variation == &"KeycapButtonPicked":
			marks += "p"
		else:
			marks += "-"
	return marks


func _visible_rows(rows: Array) -> int:
	var n := 0
	for row: Control in rows:
		n += int(row.visible)
	return n


## "PAUSE Start": a fixed row's name and keycaps.
func _fixed_line(row: Button) -> String:
	var line: Array = []
	for part in MenuRows.layout_of(row).get_children():
		if part is Label and part.text != "":
			line.append(part.text)
	return " ".join(line)


func _row_name(row: Button) -> String:
	return MenuRows.layout_of(row).get_node("Name").text


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	check(InputSettings.get_save_path() == InputSettings.TEST_SAVE_PATH,
		"a test run keeps its own settings file, not the player's")
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		tree.quit(1)   # never go on to rewrite the player's settings
		return

	print("\n[A] MOVE, FIRE 1 and FIRE 2 each have two slots, set one at a time")
	check(_slots("move") == ["dpad", "ls"] and _slots("shoot") == ["b0", "a5+"] and _slots("shoot2") == ["b2", "a4+"],
		"defaults: D-pad + L-stick, A + RT, X + LT")
	check(_pad_codes("p1_up") == ["a1-", "b11"] and _pad_codes("p1_right") == ["a0+", "b14"]
		and _pad_codes("p1_shoot") == ["a5+", "b0"], "each direction takes its part of both MOVE sets")
	check(InputSettings.get_pad_name("dpad") == "D-pad" and InputSettings.get_pad_name("rs") == "R-stick"
		and InputSettings.get_pad_name("b0") == "A" and InputSettings.get_pad_name("a5+") == "RT"
		and InputSettings.get_pad_name("") == InputSettings.PAD_NONE_NAME, "names: D-pad, R-stick, A, RT, and a dash for empty")
	check(InputSettings.set_pad_slot("p1", "move", 1, "rs").is_empty() and _slots("move") == ["dpad", "rs"]
		and _pad_codes("p1_up") == ["a3-", "b11"] and _pad_codes("p1_left") == ["a2-", "b13"],
		"MOVE's second slot to the right stick: all four directions follow")
	var moved: Dictionary = InputSettings.set_pad_slot("p1", "move", 0, "rs")
	check(_slots("move") == ["rs", "dpad"] and moved == {"player": "p1", "control": "move", "slot": 1, "value": "dpad"},
		"the right stick into the first slot: the two MOVE slots swap")
	InputSettings.set_pad_slot("p1", "move", 1, "")
	check(_slots("move") == ["rs", ""] and _pad_codes("p1_down") == ["a3+"], "a slot can be emptied")
	InputSettings.set_pad_slot("p1", "move", 1, "dpad")
	InputSettings.set_pad_slot("p1", "move", 0, "")
	check(_slots("move") == ["dpad", ""] and _pad_codes("p1_up") == ["b11"],
		"emptying the first slot moves the second's input up, so only the second is ever empty")
	check(InputSettings.set_pad_slot("p1", "move", 1, "dpad").is_empty() and _slots("move") == ["dpad", ""],
		"moving the only input into its own empty slot changes nothing")
	InputSettings.set_pad_slot("p1", "move", 0, "rs")
	check(InputSettings.set_pad_slot("p1", "shoot", 0, "b1").is_empty() and _slots("shoot") == ["b1", "a5+"]
		and _pad_codes("p1_shoot") == ["a5+", "b1"], "FIRE 1's first slot to B: B replaces A, RT stays")
	moved = InputSettings.set_pad_slot("p1", "shoot", 1, "a4+")
	check(_slots("shoot") == ["b1", "a4+"] and _slots("shoot2") == ["b2", "a5+"]
		and moved == {"player": "p1", "control": "shoot2", "slot": 1, "value": "a5+"}, "FIRE 1 takes LT: FIRE 2 gets RT in its place")
	InputSettings.set_pad_slot("p1", "shoot", 0, "b2")
	check(_slots("shoot") == ["b2", "a4+"] and _slots("shoot2") == ["b1", "a5+"], "and X from FIRE 2, which gets B")
	InputSettings.set_pad_slot("p1", "shoot2", 1, "")
	InputSettings.set_pad_slot("p1", "shoot", 1, "")
	moved = InputSettings.set_pad_slot("p1", "shoot", 1, "b1")   # FIRE 2's only button
	check(_slots("shoot") == ["b2", "b1"] and _slots("shoot2") == ["", ""]
		and moved == {"player": "p1", "control": "shoot2", "slot": 0, "value": ""}, "taking a control's only input leaves it empty")
	InputSettings.set_pad_slot("p1", "shoot", 1, "a4+")
	InputSettings.set_pad_slot("p1", "shoot2", 0, "b1")
	InputSettings.set_pad_slot("p1", "shoot2", 1, "a5+")
	for bad in [["shoot", "b11"], ["shoot", "b6"], ["shoot", "b4"], ["shoot", "b5"], ["shoot", "a0+"], ["move", "b0"], ["move", "a5+"]]:
		InputSettings.set_pad_slot("p1", bad[0], 0, bad[1])
	check(_slots("shoot") == ["b2", "a4+"] and _slots("move") == ["rs", ""],
		"refused: the D-pad, Start, Back, Guide and a stick to fire; a button or a trigger to move")
	check(_pad_codes("p2_shoot") == ["a5+", "b0"] and _pad_codes("p2_up") == ["a1-", "b11"], "P2's controller is left alone")
	InputSettings.save_binding("p1_shoot", KEY_J)
	check(InputSettings.get_binding("p1_shoot") == KEY_J and _pad_codes("p1_shoot") == ["a4+", "b2"],
		"rebinding the key keeps the slots")
	var cfg := _read_settings()
	check(Array(cfg.get_value("pad_bindings", "p1_move", [])) == ["rs", ""]
		and Array(cfg.get_value("pad_bindings", "p1_shoot", [])) == ["b2", "a4+"], "saved to settings.cfg")
	InputSettings.load_and_apply()
	check(_slots("move") == ["rs", ""] and _slots("shoot2") == ["b1", "a5+"] and _pad_codes("p1_up") == ["a3-"],
		"and loaded back from it")
	cfg = _read_settings()
	cfg.set_value("pad_bindings", "p1_shoot", ["b11", "b3"])
	cfg.set_value("pad_bindings", "p1_shoot2", ["b3", 7])
	cfg.set_value("pad_bindings", "p1_move", "garbage")
	cfg.set_value("pad_bindings", "p1_up", PackedStringArray(["b11", "a1-"]))   # an entry of the old layout
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(_slots("shoot") == ["b3", ""] and _slots("shoot2") == ["", ""] and _slots("move") == ["dpad", "ls"],
		"a hand-edited file keeps what fits, each input once (%s %s %s)" % [_slots("shoot"), _slots("shoot2"), _slots("move")])
	InputSettings.reset_pad_to_defaults("p1")
	check(not _read_settings().has_section_key("pad_bindings", "p1_up"), "the old layout's entries are dropped")
	check(_slots("shoot") == ["b0", "a5+"] and _slots("move") == ["dpad", "ls"] and _pad_codes("p1_shoot") == ["a5+", "b0"]
		and InputSettings.get_binding("p1_shoot") == KEY_J, "resetting the controller leaves the keys alone")
	var bare := ConfigFile.new()
	bare.set_value("controller", "p1_vibration", true)
	bare.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(not InputSettings._config.has_section("pad_bindings"), "a reload forgets what the file no longer has")
	InputSettings.reset_to_defaults("p1")

	print("\n[B] A, B and Start keep their menu jobs whatever fire is bound to")
	InputSettings.set_pad_slot("p1", "shoot", 0, "b1")   # fire 1 on B
	var b := _button_event(JOY_BUTTON_B)
	check(InputMap.event_is_action(b, "p1_shoot"), "B fires in the game")
	check(not MenuFocus.is_pressed(b, MenuFocus.ACCEPT_ACTIONS) and MenuFocus.is_pressed(b, MenuFocus.BACK_ACTIONS),
		"but in the menus B only goes back")
	InputSettings.set_pad_slot("p1", "shoot", 0, "b10")   # fire 1 on RB, so A is on nothing
	check(MenuFocus.is_pressed(_button_event(JOY_BUTTON_A), MenuFocus.ACCEPT_ACTIONS), "A still confirms")
	check(MenuFocus.is_pressed(_button_event(JOY_BUTTON_RIGHT_SHOULDER), MenuFocus.ACCEPT_ACTIONS),
		"and the new fire button confirms too")
	InputSettings.reset_pad_to_defaults("p1")

	print("\n[C] The controls page: KEYBOARD and GAMEPAD tabs")
	_screen = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_screen)
	_cp = _screen._keybind_page
	await tree.process_frame
	await tree.process_frame
	_screen._settings_button.grab_focus()
	await _key(KEY_ENTER)
	check(_screen._tabs.current == _screen.SettingsTab.GENERAL and _focus() == _screen._common.sfx_row,
		"the settings open on their GENERAL tab, on SFX VOLUME")
	var common_rows: Array = _screen._common.rows().map(_row_name)
	check(common_rows == ["SFX VOLUME", "MUSIC VOLUME", "ALWAYS FULLSCREEN", "LANGUAGE", "P1 CONTROLS", "P2 CONTROLS"],
		"no VIBRATION row (it is on each player's controls page), nor GAME SPEED (the GAME tab's) (%s)"
		% str(common_rows))
	_screen._common.p1_row.grab_focus()
	check(MenuRows.layout_of(_screen._common.p1_row).get_node("Name").text == "P1 CONTROLS", "the settings row is P1 CONTROLS")
	await _key(KEY_ENTER)
	check(_screen._page == _screen.Page.KEYBIND and _cp._title.text == "P1 CONTROLS"
		and _cp._tab == _cp.Tab.KEYBOARD, "opened with Enter: P1 CONTROLS, on the KEYBOARD tab")
	check(_visible_rows(_cp._action_rows) == 6 and _visible_rows(_cp._pad_rows) == 0
		and not _cp._vibration_row.visible and MenuRows.tab(_cp._tab_row, 0).button_pressed, "KEYBOARD: the six key rows")
	check(MenuRows.value_label(_cp._action_rows[0]).text == "W" and MenuRows.value_label(_cp._action_rows[4]).text == "T",
		"showing W for UP and T for FIRE 1")
	var keyboard_size: Vector2 = _cp.get_combined_minimum_size()
	await _key(KEY_UP)   # from the UP row up to the tabs
	check(_focus() == _cp._tab_row, "the tab strip sits above the rows")
	await _key(KEY_D)    # P1 right
	await tree.process_frame
	check(_cp._tab == _cp.Tab.GAMEPAD and MenuRows.tab(_cp._tab_row, 1).button_pressed
		and _visible_rows(_cp._action_rows) == 0 and _visible_rows(_cp._pad_rows) == 3
		and _cp._controller_row.visible and _cp._vibration_row.visible and _visible_rows(_cp._fixed_pad_rows) == 1,
		"right on the strip: GAMEPAD, with CONTROLLER, VIBRATION, MOVE, FIRE 1, FIRE 2 and a fixed row")
	check(MenuRows.value_label(_cp._controller_row).text.begins_with("1"), "P1 is on controller 1")
	check(_shown(0) == "D-pad | L-stick" and _shown(1) == "A | RT" and _shown(2) == "X | LT",
		"its slots: D-pad | L-stick, A | RT, X | LT (%s, %s, %s)" % [_shown(0), _shown(1), _shown(2)])
	var fixed: Array = _cp._fixed_pad_rows.map(_fixed_line)
	check(fixed == ["PAUSE Start"] and _cp._fixed_pad_rows[0].focus_mode == Control.FOCUS_NONE,
		"the fixed row: PAUSE Start, and it takes no focus (%s)" % str(fixed))
	check(_cp.get_combined_minimum_size() == keyboard_size,
		"both tabs are the same size, so the page does not jump (%s)" % str(keyboard_size))
	check(_cp._reset_button.text == "RESET BUTTONS" and _cp._prompt.text.to_lower().contains("controller 1"),
		"RESET BUTTONS, and the prompt says which controller P1 uses")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	check(_cp._tab == _cp.Tab.KEYBOARD, "LB: KEYBOARD")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(_cp._tab == _cp.Tab.GAMEPAD, "RB: GAMEPAD")
	MenuRows.tab(_cp._tab_row, 0).pressed.emit()
	check(_cp._tab == _cp.Tab.KEYBOARD, "clicking a tab picks it")
	_cp._action_rows[4].grab_focus()   # FIRE 1's key
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(_focus() == _cp._pad_rows[1], "switching tabs on FIRE 1 lands on FIRE 1's slots")
	_cp._pad_rows[0].grab_focus()      # MOVE
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	check(_focus() == _cp._action_rows[0], "and MOVE lands on UP")
	await _pad(JOY_BUTTON_B)
	check(_screen._page == _screen.Page.SETTINGS and _focus() == _screen._common.p1_row,
		"B goes back to the settings, on P1 CONTROLS")
	await _pad(JOY_BUTTON_A)
	check(_screen._page == _screen.Page.KEYBIND and _cp._tab == _cp.Tab.GAMEPAD
		and _focus() == _cp._pad_rows[0], "opened with A on a controller: straight to GAMEPAD, on MOVE")

	print("\n[D] Setting the GAMEPAD slots one at a time")
	check(_marks(0) == "p-" and _marks(1) == "--", "the first slot of the focused row is picked")
	var picked_slot := MenuRows.slot(_cp._pad_rows[0], 0)
	check(picked_slot.get_theme_stylebox("normal") != MenuRows.slot(_cp._pad_rows[1], 0).get_theme_stylebox("normal")
		and picked_slot.get_theme_stylebox("normal") != picked_slot.get_theme_stylebox("pressed"),
		"a picked slot is outlined: unlike a plain one, and unlike the solid one that waits")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	check(_marks(0) == "-p" and _focus() == _cp._pad_rows[0], "right picks the second slot")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_marks(0) == "--" and _marks(1) == "-p", "and the pick stays in its column going down")
	await _pad(JOY_BUTTON_DPAD_UP)
	await _pad(JOY_BUTTON_A)
	check(_cp._capture_action == "move" and _cp._capture_slot == 1 and _shown(0) == "D-pad | ..."
		and _marks(0) == "-w", "A waits for MOVE's second slot, now solid")
	_cp._pad_rows[1].grab_focus()   # the mouse wanders onto FIRE 1 meanwhile
	check(_marks(0) == "-w" and _marks(1) == "--", "only the waiting slot stays marked")
	_cp._pad_rows[0].grab_focus()
	await _flick(JOY_AXIS_RIGHT_Y, -0.9)
	check(_cp._capture_action == "" and _shown(0) == "D-pad | R-stick" and _pad_codes("p1_up") == ["a3-", "b11"],
		"pushing the right stick any way makes the whole slot the right stick")
	check(_focus() == _cp._pad_rows[0], "and the push did not move the focus")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	check(_cp._capture_action == "move" and _cp._prompt.text.begins_with("MOVE takes the D-pad or a stick."),
		"A is refused for MOVE, and the wait goes on")
	await _flick(JOY_AXIS_LEFT_X, -0.9)
	check(_shown(0) == "L-stick | R-stick" and _pad_codes("p1_up") == ["a1-", "a3-"], "the left stick fills the first slot")
	check(_cp._prompt.text.to_lower().contains("controller 1"), "nothing else moved, so the prompt is back to normal")
	await _pad(JOY_BUTTON_DPAD_RIGHT)   # the D-pad is no longer MOVE's, yet still steps through the menu
	check(_marks(0) == "-p", "the D-pad still works the menu once MOVE lets it go")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_BACK)
	check(_shown(0) == "L-stick | \u2014" and _pad_codes("p1_up") == ["a1-"]
		and _cp._prompt.text == "MOVE no longer uses R-stick.", "View empties the waiting slot")
	await _pad(JOY_BUTTON_A)
	await _flick(JOY_AXIS_RIGHT_X, 0.9)
	check(_shown(0) == "L-stick | R-stick", "an empty slot takes the right stick")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_A)
	await _flick(JOY_AXIS_RIGHT_Y, 0.9)
	check(_shown(0) == "R-stick | L-stick" and _cp._prompt.text == "The two MOVE slots swapped.",
		"the right stick into the first slot: the two slots swap")
	await _pad(JOY_BUTTON_BACK)   # on the picked first slot, with no wait
	check(_shown(0) == "L-stick | \u2014" and _cp._capture_action == "" and _pad_codes("p1_up") == ["a1-"]
		and _cp._prompt.text == "MOVE no longer uses R-stick.",
		"View on a picked slot empties it at once, and the second input moves up")
	_cp._pad_rows[1].grab_focus()   # FIRE 1
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_Y)
	check(_shown(1) == "Y | RT" and _pad_codes("p1_shoot") == ["a5+", "b3"], "FIRE 1's first slot to Y")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_A)
	await _flick(JOY_AXIS_TRIGGER_LEFT, 1.0)
	check(_shown(1) == "Y | LT" and _shown(2) == "X | RT", "its second slot to LT: FIRE 2 takes RT")
	check(_cp._prompt.text == "FIRE 2 had LT, so it takes RT instead.", "the prompt says so")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_cp._capture_action == "shoot" and _cp._prompt.text.begins_with("FIRE 1 takes a button or a trigger."),
		"the D-pad is refused for FIRE 1")
	await _flick(JOY_AXIS_RIGHT_X, 0.9)
	check(_cp._capture_action == "shoot" and _shown(1) == "Y | ...", "and so is a stick")
	await _pad(JOY_BUTTON_START)
	check(_cp._capture_action == "" and _shown(1) == "Y | LT" and _screen._page == _screen.Page.KEYBIND,
		"Start backs out and changes nothing")
	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_GUIDE)
	check(_cp._capture_action == "shoot" and _cp._prompt.text.begins_with("Guide belongs to the system"),
		"Guide is refused")
	await _key(KEY_ESCAPE)
	check(_cp._capture_action == "", "Esc backs out")
	var fire2_slot: Button = MenuRows.slot(_cp._pad_rows[2], 1)
	fire2_slot.mouse_entered.emit()
	check(_focus() == _cp._pad_rows[2] and _marks(2) == "-p" and _marks(1) == "--",
		"hovering FIRE 2's second slot focuses the row and picks the slot")
	fire2_slot.pressed.emit()
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(_shown(2) == "X | RB" and _cp._tab == _cp.Tab.GAMEPAD, "clicked, it waits, and takes RB rather than switching tabs")
	await _pad(JOY_BUTTON_A)
	await _key(KEY_DELETE)
	check(_shown(2) == "X | —" and _pad_codes("p1_shoot2") == ["b2"], "Delete empties a slot too")
	_cp._pad_rows[1].grab_focus()      # FIRE 1: Y | LT
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.9)   # LT fires, so in the menu it confirms: the wait begins...
	check(_cp._capture_action == "shoot" and _cp._capture_slot == 0, "pulling LT, a fire button, starts the wait")
	await _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)   # ...with LT still held
	check(_cp._capture_action == "shoot" and _shown(1) == "... | LT", "the trigger held since then does not bind itself")
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _flick(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	check(_cp._capture_action == "" and _shown(1) == "RT | LT", "let go, the next pull does: RT")
	check(_focus() == _cp._pad_rows[1], "and the focus stayed on FIRE 1")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	MenuRows.slot(_cp._pad_rows[1], 0).gui_input.emit(right_click)
	check(_shown(1) == "LT | \u2014" and _cp._prompt.text == "FIRE 1 no longer uses RT.",
		"right-clicking a slot empties it")
	await _key(KEY_DELETE)
	check(_shown(1) == "\u2014 | \u2014" and _pad_codes("p1_shoot") == [] and _cp._capture_action == "",
		"and Delete on the picked slot, down to nothing at all")
	_cp._reset_button.grab_focus()
	await _pad(JOY_BUTTON_A)
	check(_shown(0) == "D-pad | L-stick" and _shown(1) == "A | RT" and _shown(2) == "X | LT"
		and _cp._prompt.text == "P1 controller reset to defaults.", "RESET BUTTONS puts it all back")

	print("\n[E] Rebinding on the KEYBOARD tab still works")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_cp._action_rows[4].grab_focus()
	await _key(KEY_ENTER)
	check(_cp._capture_action == "p1_shoot" and MenuRows.value_label(_cp._action_rows[4]).text == "...",
		"Enter on FIRE 1 waits for a key")
	await _pad(JOY_BUTTON_Y)
	check(_cp._capture_action == "p1_shoot", "a controller button does not end a key wait")
	await _key(KEY_K)
	check(MenuRows.value_label(_cp._action_rows[4]).text == "K" and InputSettings.get_binding("p1_shoot") == KEY_K
		and _pad_codes("p1_shoot") == ["a5+", "b0"], "K is fire 1's key now, and A / RT still fire")
	await _key(KEY_ENTER)
	await _pad(JOY_BUTTON_B)
	check(_cp._capture_action == "" and MenuRows.value_label(_cp._action_rows[4]).text == "K", "B backs out of a key wait")
	_cp._reset_button.grab_focus()
	await _key(KEY_ENTER)
	check(MenuRows.value_label(_cp._action_rows[4]).text == "T" and _cp._reset_button.text == "RESET KEYS",
		"RESET KEYS puts T back")

	await _check_sharing()
	await _check_vibration()
	_screen.queue_free()
	await tree.create_timer(0.5).timeout  # let the menu sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


## [F] Two players on one controller, as with a single pad: P1 on its left half,
## P2 on its right, both driven from device 0; and back to a controller each.
func _check_sharing() -> void:
	print("\n[F] Two players sharing one controller")
	_screen.set_process_input(false)   # the pad events below are for the tanks, not the menu
	_cp.set_process_input(false)
	InputSettings.reset_pad_to_defaults("p1")
	InputSettings.reset_pad_to_defaults("p2")
	check(not InputSettings.is_pad_shared() and InputSettings.get_pad_device("p2") == 1
		and _pad_codes("p2_up") == ["a1-", "b11"], "out of the box P2 has controller 2, with the whole layout")
	InputSettings.set_pad_device("p2", 0)
	check(InputSettings.is_pad_shared() and InputSettings.get_pad_partner("p1") == "p2",
		"P2 picks controller 1: the two share it")
	check(_slots("move") == ["ls", "dpad"] and _slots("shoot") == ["a4+", ""] and _slots("shoot2") == ["b9", ""],
		"P1 takes the left half: L-stick and D-pad, LT, LB")
	check(_slots("move", "p2") == ["rs", ""] and _slots("shoot", "p2") == ["a5+", "b0"]
		and _slots("shoot2", "p2") == ["b10", "b2"], "P2 the right: R-stick, RT or A, RB or X")
	check(_pad_codes("p2_up") == ["a3-"] and _pad_codes("p2_shoot") == ["a5+", "b0"] and _pad_codes("p1_shoot") == ["a4+"],
		"P2's actions now listen to controller 1 as well")
	var clash := false
	for p1_action in InputSettings.get_player_actions("p1"):
		for p2_action in InputSettings.get_player_actions("p2"):
			for code in _pad_codes(p1_action):
				clash = clash or (code in _pad_codes(p2_action))
	check(not clash, "no input on the shared controller drives both players")
	await _axis(JOY_AXIS_RIGHT_Y, -1.0)
	check(Input.get_action_strength("p2_up") > 0.9 and Input.get_action_strength("p1_up") == 0.0,
		"the right stick drives P2, not P1")
	await _axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _axis(JOY_AXIS_LEFT_X, 1.0)
	check(Input.get_action_strength("p1_right") > 0.9 and Input.get_action_strength("p2_right") == 0.0,
		"the left stick drives P1, not P2")
	await _axis(JOY_AXIS_LEFT_X, 0.0)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	check(Input.is_action_pressed("p2_shoot") and not Input.is_action_pressed("p1_shoot"), "RT fires for P2 only")
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	var moved: Dictionary = InputSettings.set_pad_slot("p2", "move", 0, "ls")
	check(_slots("move", "p2") == ["ls", ""] and _slots("move") == ["rs", "dpad"]
		and moved == {"player": "p1", "control": "move", "slot": 0, "value": "rs"},
		"P2 takes the left stick: P1 gets the right one in its place")
	InputSettings.reset_pad_to_defaults("p2")
	check(_slots("move") == ["ls", "dpad"] and _slots("move", "p2") == ["rs", ""],
		"resetting while sharing puts both players back on their halves")
	var cfg := _read_settings()
	cfg.set_value("pad_bindings", "p2_shoot", ["a4+", "a5+"])   # LT is P1's
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(_slots("shoot", "p2") == ["a5+", ""] and _slots("shoot") == ["a4+", ""],
		"a saved clash on the shared controller is dropped from P2 (%s)" % [str(_slots("shoot", "p2"))])
	InputSettings.set_pad_device("p2", 1)
	check(not InputSettings.is_pad_shared() and _slots("move") == ["dpad", "ls"] and _slots("move", "p2") == ["dpad", "ls"]
		and _pad_codes("p2_up") == ["a1-", "b11"], "P2 back on controller 2: each has the whole layout again")

	print("\n[G] The CONTROLLER row")
	_screen.set_process_input(true)
	_cp.set_process_input(true)
	_screen._open_keybinds("p2")
	_cp._select_tab(1)
	_cp._controller_row.grab_focus()
	check(MenuRows.value_label(_cp._controller_row).text.begins_with("2"), "P2's page: controller 2")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	check(InputSettings.get_pad_device("p2") == 0 and MenuRows.value_label(_cp._controller_row).text.begins_with("1")
		and _shown(0) == "R-stick | \u2014" and _shown(1) == "RT | A",
		"right: P2 moves to controller 1 and shows its half (%s, %s)" % [_shown(0), _shown(1)])
	check(_cp._prompt.text.begins_with("P1 and P2 now share controller 1"), "the prompt says they share it")
	_cp._set_prompt("")
	check(_cp._prompt.text.contains("P2 shares controller 1 with P1"), "and the status line keeps saying so")
	_cp._pad_rows[0].grab_focus()   # P2's MOVE
	await _pad(JOY_BUTTON_DPAD_LEFT)
	await _pad(JOY_BUTTON_A)
	await _flick(JOY_AXIS_LEFT_Y, -0.9)
	check(_shown(0) == "L-stick | \u2014" and _cp._prompt.text == "P1 MOVE had L-stick, so it takes R-stick instead.",
		"taking P1's stick from P2's page says what P1 got instead")
	_cp._controller_row.grab_focus()
	await _pad(JOY_BUTTON_DPAD_LEFT)
	check(InputSettings.get_pad_device("p2") == 1 and not InputSettings.is_pad_shared()
		and _cp._prompt.text.begins_with("P1 and P2 have controllers of their own")
		and _shown(0) == "D-pad | L-stick", "left: P2 back on controller 2, whole layout again")


## [H] Vibration: a switch per player, on the GAMEPAD tab of their controls page.
func _check_vibration() -> void:
	print("\n[H] VIBRATION, for each player on their own")
	check(InputSettings.get_vibration("p1") and InputSettings.get_vibration("p2"), "out of the box both players' controllers rumble")
	_screen._open_keybinds("p1")
	_cp._select_tab(1)
	_cp._pad_rows[0].grab_focus()   # MOVE
	await _pad(JOY_BUTTON_DPAD_UP)
	check(_focus() == _cp._vibration_row and MenuRows.value_label(_cp._vibration_row).text == "ON",
		"up from MOVE: VIBRATION, reading ON")
	await _pad(JOY_BUTTON_DPAD_UP)
	check(_focus() == _cp._controller_row, "with CONTROLLER above it")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	check(not InputSettings.get_vibration("p1") and InputSettings.get_vibration("p2")
		and MenuRows.value_label(_cp._vibration_row).text == "OFF", "A switches P1's off, and P2's stays on")
	check(_focus() == _cp._vibration_row and _screen._page == _screen.Page.KEYBIND, "the page stays, on VIBRATION")
	var cfg := _read_settings()
	check(cfg.get_value("controller", "p1_vibration", true) == false, "saved to settings.cfg")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	check(InputSettings.get_vibration("p1") and MenuRows.value_label(_cp._vibration_row).text == "ON", "right switches it back on")
	await _key(KEY_A)   # P1 left
	check(not InputSettings.get_vibration("p1"), "and left off again")
	MenuRows.arrow(_cp._vibration_row, "Right").pressed.emit()
	check(InputSettings.get_vibration("p1"), "clicking an arrow switches it too")
	_cp._vibration_row.pressed.emit()
	check(not InputSettings.get_vibration("p1"), "and clicking the row")
	_cp._pad_rows[1].grab_focus()
	_cp._vibration_row.mouse_entered.emit()
	check(_focus() == _cp._vibration_row, "hovering it focuses it")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	check(_cp._tab == _cp.Tab.KEYBOARD and _focus() == _cp._action_rows[0], "switching tabs on VIBRATION lands on UP")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_cp._reset_button.grab_focus()
	await _pad(JOY_BUTTON_A)
	check(not InputSettings.get_vibration("p1") and _shown(0) == "D-pad | L-stick", "RESET BUTTONS leaves VIBRATION alone")
	await _pad(JOY_BUTTON_B)
	_screen._open_keybinds("p2")
	_cp._select_tab(1)
	check(MenuRows.value_label(_cp._vibration_row).text == "ON", "P2's page shows P2's own switch: ON")
	_cp._pad_rows[0].grab_focus()
	await _pad(JOY_BUTTON_A)   # a wait on P2's MOVE...
	_cp._vibration_row.pressed.emit()   # ...ended by a click on VIBRATION
	check(_cp._capture_action == "" and not InputSettings.get_vibration("p2") and not InputSettings.get_vibration("p1"),
		"a click on it during a wait ends the wait and switches P2's off")
	InputSettings.set_vibration("p2", true)

	cfg = ConfigFile.new()   # a settings file from when one switch served both players
	cfg.set_value("controller", "vibration", false)
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(not InputSettings.get_vibration("p1") and not InputSettings.get_vibration("p2"),
		"an older file's single VIBRATION OFF carries over to both players")
	InputSettings.set_vibration("p2", true)
	cfg = _read_settings()
	check(not cfg.has_section_key("controller", "vibration") and cfg.get_value("controller", "p1_vibration", true) == false
		and cfg.get_value("controller", "p2_vibration", false) == true, "and is saved as the two players' own switches")
	cfg.set_value("controller", "vibration", true)   # an old copy of the game saved its switch again
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(not InputSettings.get_vibration("p1") and InputSettings.get_vibration("p2"), "a player's own switch wins over the old one")
	cfg.set_value("controller", "p1_vibration", "loud")
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(InputSettings.get_vibration("p1"), "a hand-edited value that isn't ON or OFF counts as on")
	await _pad(JOY_BUTTON_B)
