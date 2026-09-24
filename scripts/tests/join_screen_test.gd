extends Node
## Headless test for the new-game (join) screen: each player joins with their
## fire button or a click on their card, a credit each; fire again, START or a
## controller's Start begins the game; Esc, B or BACK return to the title
## screen, and only a game that really starts counts as played.
## Run as an override main scene:
##   Godot --headless res://scenes/test/join_screen_test.tscn

const JOIN_SCENE := "res://scenes/join_screen.tscn"

var _fail := 0
var _screen    # the join screen (untyped: the test reads its private state)


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
		Input.flush_buffered_events()
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


## A fresh game and its join screen, made the current scene so that leaving it
## (to the title or the game) replaces it instead of this test.
func _open(credits: int) -> void:
	GameManager.reset()
	GameManager.credits = credits
	_screen = load(JOIN_SCENE).instantiate()
	get_tree().root.add_child(_screen)
	get_tree().current_scene = _screen
	await get_tree().process_frame


## Waits for a scene change and returns the scene it led to (then frees it).
func _left_to() -> String:
	for i in 4:
		await get_tree().process_frame
	var scene := get_tree().current_scene
	var path: String = scene.scene_file_path if scene and scene != _screen else ""
	if scene and scene != self and scene != _screen:
		get_tree().root.remove_child(scene)
		scene.free()
	get_tree().current_scene = self
	return path


func _prompt_text(player: int) -> String:
	var parts: PackedStringArray = []
	for child in _screen._prompts[player].get_children():
		if not child.is_queued_for_deletion():
			parts.append(child.text)
	return " ".join(parts)


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return

	print("\n[A] The screen: a card per player, the credits, START waiting")
	await _open(3)
	check(_screen.get_node("Header").text == "NEW GAME" and _screen.theme != null, "a NEW GAME page in the menu style")
	check(_screen._card_buttons.size() == 2 and _screen._card_buttons[0].get_node("Column/Title").text == "PLAYER 1",
		"two cards, PLAYER 1 first")
	var p1_key: String = InputSettings.get_key_name("p1_shoot")
	var p2_key: String = InputSettings.get_key_name("p2_shoot")
	check(_prompt_text(0) == "PRESS %s TO JOIN" % p1_key and _prompt_text(1) == "PRESS %s TO JOIN" % p2_key,
		"each shows its fire key: %s / %s" % [_prompt_text(0), _prompt_text(1)])
	check(_screen._tank_images[0].texture != null and _screen._tank_images[0].modulate.a < 1.0, "a dimmed tank on each")
	_screen._fill_prompt(0, "TO JOIN", true)
	var pad_button: String = InputSettings.get_pad_name(InputSettings.get_pad_slot("p1", "shoot", 0))
	check(_prompt_text(0) == "PRESS %s OR PAD %s TO JOIN" % [p1_key, pad_button],
		"with P1's controller plugged in, its button too, marked PAD: %s" % _prompt_text(0))
	_screen._fill_prompt(0, "TO JOIN", false)
	check(_screen._credits_label.text == "CREDITS   3" and _screen._start_button.disabled, "CREDITS 3, START disabled")

	print("\n[B] Fire joins; a click on a card joins too")
	var played := InputSettings.get_games_played()
	await _key(KEY_T)
	check(_screen._joined == [true, false] and GameManager.credits == 2 and GameManager.player_active[0],
		"P1's fire: P1 joins for a credit")
	check(_screen._status_labels[0].text == "READY" and _prompt_text(0) == "PRESS %s TO START" % p1_key
		and _screen._tank_images[0].modulate.a == 1.0, "P1's card: READY, PRESS %s TO START" % p1_key)
	check(not _screen._start_button.disabled and _screen._credits_label.text == "CREDITS   2", "START on, CREDITS 2")
	_screen._card_buttons[1].pressed.emit()
	check(_screen._joined == [true, true] and GameManager.credits == 1, "a click on P2's card: P2 joins")

	print("\n[C] Esc goes back to the title (and the game is not counted)")
	_screen._back_button.pressed.emit()
	await _left_to()
	# Arrive the way the title's NEW GAME does, through GameManager.start_game().
	var stand_in := Node.new()
	tree.root.add_child(stand_in)
	tree.current_scene = stand_in
	GameManager.start_game()
	for i in 4:
		await tree.process_frame
	_screen = tree.current_scene
	check(_screen.scene_file_path == JOIN_SCENE and InputSettings.get_games_played() == played,
		"NEW GAME opens this screen without counting a game yet")
	await _key(KEY_T)
	await _key(KEY_ESCAPE)
	check(await _left_to() == "res://scenes/main.tscn", "Esc: the title screen")
	check(InputSettings.get_games_played() == played, "no game counted as played")

	print("\n[D] Fire again starts the game")
	await _open(3)
	await _key(KEY_T)
	await _key(KEY_T)
	check(await _left_to() == "res://scenes/game.tscn", "P1's fire twice: the game")
	check(InputSettings.get_games_played() == played + 1, "counted as played once it starts")

	print("\n[E] A controller: B goes back, Start starts once someone joined")
	await _open(3)
	await _pad(JOY_BUTTON_START)
	check(tree.current_scene == _screen, "Start with nobody in: nothing")
	_screen._card_buttons[0].pressed.emit()
	await _pad(JOY_BUTTON_START)
	check(await _left_to() == "res://scenes/game.tscn", "Start after a join: the game")
	await _open(3)
	await _pad(JOY_BUTTON_B)
	check(await _left_to() == "res://scenes/main.tscn", "B: the title screen")

	print("\n[F] The mouse: START and BACK")
	await _open(3)
	_screen._start_button.pressed.emit()
	check(tree.current_scene == _screen, "START does nothing before a join")
	_screen._card_buttons[1].pressed.emit()
	_screen._start_button.pressed.emit()
	check(await _left_to() == "res://scenes/game.tscn", "START after P2 joins: the game")
	await _open(3)
	_screen._back_button.pressed.emit()
	check(await _left_to() == "res://scenes/main.tscn", "BACK: the title screen")

	print("\n[G] Out of credits")
	await _open(1)
	await _key(KEY_T)
	check(_screen._joined == [true, false] and GameManager.credits == 0, "the last credit goes to P1")
	check(_screen._card_buttons[1].disabled and _screen._status_labels[1].text == "NO CREDITS"
		and _screen._prompts[1].modulate.a == 0.0, "P2's card: NO CREDITS, no prompt")
	check(_screen._card_buttons[0].get_node("Column/Title").global_position.y
		== _screen._card_buttons[1].get_node("Column/Title").global_position.y, "the two cards still line up")
	_screen._on_player_fire(1)
	check(_screen._joined == [true, false], "and P2 can't join")
	_screen._back_button.pressed.emit()
	await _left_to()

	await tree.create_timer(0.5).timeout  # let the menu sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
