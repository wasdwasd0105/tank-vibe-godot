extends Node
## Headless test for game controller support: the Xbox layout on each player's
## actions, the stick driving the tank along its main axis, menu navigation with
## the stick counting once per push, and Start / B in the pause menu. Events are
## fed through Input.parse_input_event as a pad would send them.
## Run as an override main scene:
##   Godot --headless res://scenes/test/controller_test.tscn

var _fail := 0
var _game: Node
var _player: PlayerTank


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _has_button(action: String, button: JoyButton, device: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button and ev.device == device:
			return true
	return false


func _has_axis(action: String, axis: JoyAxis, way: float, device: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and ev.axis == axis and signf(ev.axis_value) == way and ev.device == device:
			return true
	return false


func _stick(device: int, x: float, y: float) -> void:
	for axis_value in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
		var ev := InputEventJoypadMotion.new()
		ev.device = device
		ev.axis = axis_value[0]
		ev.axis_value = axis_value[1]
		Input.parse_input_event(ev)
	Input.flush_buffered_events()   # parsed events otherwise wait for the next frame


func _button(device: int, button: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _motion(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	return ev


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame

	print("\n[A] Each player's actions carry the controller layout")
	for p in [["p1", 0], ["p2", 1]]:
		var pre: String = p[0]
		var dev: int = p[1]
		check(_has_button(pre + "_up", JOY_BUTTON_DPAD_UP, dev) and _has_axis(pre + "_up", JOY_AXIS_LEFT_Y, -1.0, dev),
			"%s up: D-pad up or stick up on controller %d" % [pre, dev + 1])
		check(_has_button(pre + "_right", JOY_BUTTON_DPAD_RIGHT, dev) and _has_axis(pre + "_right", JOY_AXIS_LEFT_X, 1.0, dev),
			"%s right: D-pad right or stick right" % pre)
		check(_has_button(pre + "_shoot", JOY_BUTTON_A, dev) and _has_axis(pre + "_shoot", JOY_AXIS_TRIGGER_RIGHT, 1.0, dev),
			"%s fire 1: A or RT" % pre)
		check(_has_button(pre + "_shoot2", JOY_BUTTON_X, dev) and _has_axis(pre + "_shoot2", JOY_AXIS_TRIGGER_LEFT, 1.0, dev),
			"%s fire 2: X or LT" % pre)
	check(_has_button("ui_accept", JOY_BUTTON_A, -1) and _has_button("ui_cancel", JOY_BUTTON_B, -1)
		and _has_button("pause", JOY_BUTTON_START, -1), "any controller: A confirms, B backs out, Start pauses")
	var saved_key := InputSettings.get_binding("p1_shoot")
	InputSettings._apply_binding("p1_shoot", KEY_J)   # rebinding a key...
	check(InputSettings.get_binding("p1_shoot") == KEY_J and _has_button("p1_shoot", JOY_BUTTON_A, 0),
		"rebinding P1's fire key keeps its controller buttons")
	InputSettings._apply_binding("p1_shoot", saved_key)

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
	_player = tree.get_nodes_in_group("players")[0]
	while _player.is_materializing:
		await tree.process_frame
	_player.is_invincible = true
	_player.invincible_timer = 999.0
	# Open ground to drive on, away from the walled base.
	var lm: LevelManager = _game.get_level_manager()
	for tile in lm._fg_tile_data.keys():
		if tile.y < 22:
			lm._remove_fg_tile(tile)
	for tile in lm._bg_tile_data.keys():
		lm._remove_bg_tile(tile)
	_player.global_position = lm.global_position + Vector2(640, 384)
	await tree.physics_frame

	print("\n[B] The stick drives along whichever axis it leans on most")
	var cases := [
		[Vector2(0.9, -0.4), Vector2.RIGHT], [Vector2(0.3, -0.9), Vector2.UP],
		[Vector2(-0.7, 0.6), Vector2.LEFT], [Vector2(0.2, 0.2), Vector2.ZERO],
	]
	for c in cases:
		_stick(0, c[0].x, c[0].y)
		check(_player._read_move_direction() == c[1], "stick at %s drives %s" % [c[0], c[1]])
	_stick(0, 0.0, 0.0)
	_button(0, JOY_BUTTON_DPAD_DOWN, true)
	check(_player._read_move_direction() == Vector2.DOWN, "D-pad down drives down")
	_button(0, JOY_BUTTON_DPAD_DOWN, false)
	Input.action_press("p1_up")
	Input.action_press("p1_right")
	check(_player._read_move_direction() == Vector2.UP, "two keys at once keep the old priority (up wins)")
	Input.action_release("p1_up")
	Input.action_release("p1_right")
	_stick(1, 1.0, 0.0)
	check(_player._read_move_direction() == Vector2.ZERO and Input.get_action_strength("p2_right") > 0.9,
		"the second controller drives P2, not P1")
	_stick(1, 0.0, 0.0)
	var from := _player.global_position
	_stick(0, 1.0, 0.0)
	await tree.create_timer(0.5).timeout
	_stick(0, 0.0, 0.0)
	await tree.physics_frame
	check(_player.global_position.x - from.x > 30.0, "holding the stick right drives P1 right (%.0f px)" % (_player.global_position.x - from.x))

	print("\n[C] A fires the main gun")
	var shots_before := _game.get_node("Entities/Bullets").get_child_count()
	_player.can_shoot = true
	_button(0, JOY_BUTTON_A, true)
	await tree.physics_frame
	await tree.physics_frame
	_button(0, JOY_BUTTON_A, false)
	check(_game.get_node("Entities/Bullets").get_child_count() > shots_before, "pressing A fired a shell")

	print("\n[D] Menus: a stick push counts once, until it comes back")
	var push := _motion(0, JOY_AXIS_LEFT_Y, 0.9)
	check(MenuFocus.is_navigation_event(push), "stick motion is a navigation event")
	check(MenuFocus.is_pressed(push, MenuFocus.DOWN_ACTIONS) and MenuFocus.is_pressed(push, MenuFocus.DOWN_ACTIONS),
		"the first push counts (and stays counted for that event)")
	check(not MenuFocus.is_pressed(push, MenuFocus.UP_ACTIONS), "and only for its own direction")
	check(not MenuFocus.is_pressed(_motion(0, JOY_AXIS_LEFT_Y, 1.0), MenuFocus.DOWN_ACTIONS), "holding it does not repeat")
	check(not MenuFocus.is_pressed(_motion(0, JOY_AXIS_LEFT_Y, 0.4), MenuFocus.DOWN_ACTIONS)
		and not MenuFocus.is_pressed(_motion(0, JOY_AXIS_LEFT_Y, 0.8), MenuFocus.DOWN_ACTIONS),
		"easing off only a little does not re-press it")
	MenuFocus.is_pressed(_motion(0, JOY_AXIS_LEFT_Y, 0.0), MenuFocus.DOWN_ACTIONS)
	check(MenuFocus.is_pressed(_motion(0, JOY_AXIS_LEFT_Y, 0.9), MenuFocus.DOWN_ACTIONS), "back to centre, then a new push counts")
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	check(MenuFocus.is_pressed(a, MenuFocus.ACCEPT_ACTIONS) and MenuFocus.is_pressed(b, MenuFocus.BACK_ACTIONS)
		and not MenuFocus.is_pressed(b, MenuFocus.ACCEPT_ACTIONS), "A confirms, B backs out and never confirms")

	print("\n[E] Start pauses, B resumes")
	var pause_menu: Control = _game.get_node("PauseLayer/PauseMenu")
	_button(0, JOY_BUTTON_START, true)
	_button(0, JOY_BUTTON_START, false)
	await tree.process_frame
	check(pause_menu.visible and tree.paused, "Start opened the pause menu")
	_button(0, JOY_BUTTON_B, true)
	_button(0, JOY_BUTTON_B, false)
	await tree.process_frame
	check(not pause_menu.visible and not tree.paused, "B closed it and the game resumed")

	await tree.create_timer(1.0).timeout  # let the shot's sound finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
