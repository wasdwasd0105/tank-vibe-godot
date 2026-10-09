extends Node
## Headless test for PLAYER 2 ON / OFF in the pause menu's OPTIONS: in a two-player game
## one person can sit player 2 out and play on. Player 2's tank leaves the field
## with everything kept (lives, score, HP, levels, weapon, add-ons, in the save
## too); player 2's fire doesn't bring them back and they don't hold the stage
## open; switched back on, their tank returns with all of it. Driven by keys.
## Run as an override main scene:
##   Godot --headless res://scenes/test/player_toggle_test.tscn

var _fail := 0
var _game: Node
var _menu      # PauseLayer/PauseMenu (untyped: the test reads its private state)
var _hud       # the HUD (untyped, as above)
var _deaths: Array = []


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


func _frames(n: int = 2) -> void:
	for i in range(n):
		await get_tree().physics_frame
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _tank(pid: int) -> PlayerTank:
	for node in get_tree().get_nodes_in_group("players"):
		if node is PlayerTank and node.player_id == pid and not node.is_queued_for_deletion():
			return node
	return null


func _page_texts() -> Array:
	var texts: Array = []
	for button: Button in _menu._menu_items():
		texts.append(button.text)
	return texts


func _option_texts() -> Array:
	return _menu._option_items().map(func(button: Button) -> String: return button.text)


func _bursts_at(pos: Vector2) -> int:
	var n := 0
	for fx in _game.effects_container.get_children():
		if fx is SpawnBurst and fx.global_position.distance_to(pos) < 1.0:
			n += 1
	return n


func _start_game() -> void:
	var tree := get_tree()
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_game.enemy_spawner.halt()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	_menu = _game.get_node("PauseLayer/PauseMenu")
	_hud = _game.hud
	for pid in range(2):
		while _tank(pid) and _tank(pid).is_materializing:
			await tree.process_frame


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return
	GameManager.current_stage = 1
	GameManager.difficulty = 1  # EASY, where stage 1's limit always works out to 4
	GameManager.player_active = [true, true]
	GameManager.player_disabled = [false, false]
	GameManager.player_lives = [2, 4]
	GameManager.player_scores = [12300, 8700]
	GameManager.player_hp = [4, 6]
	GameManager.player_speed_levels = [1, 3]
	GameManager.player_weapon_levels = [0, 2]
	GameManager.player_secondary_weapon_types = ["rapid", "fire"]
	GameManager.player_secondary_weapon_counts = [50, 42]
	GameManager.player_addons = [[], ["moon-shield", "anti-ice"]]
	Events.player_died.connect(func(pid: int) -> void: _deaths.append(pid))
	await _start_game()
	var p2 := _tank(1)
	check(_tank(0) != null and p2 != null and p2.has_moon_shield and p2.speed_level == 3,
		"a two-player stage: both tanks out, player 2 with its levels and add-ons")
	var stage_cap: int = _game.enemy_spawner.max_concurrent_enemies
	check(stage_cap == 4,
		"two in play: the stage's own 4 enemies at once, as in the original, not more (%d)" % stage_cap)

	print("\n[A] The pause menu of a two-player game has PLAYER 2")
	await _key(KEY_ESCAPE)
	check(_menu.visible and tree.paused, "Esc: paused")
	check(_page_texts() == ["RESUME", "RESTART STAGE", "SETTINGS", "MAIN MENU", "QUIT GAME"]
		and _option_texts() == ["PLAYER 2: ON", "SOUND: ON", "ONLINE: OFF", "FULLSCREEN: OFF"],
		"first of the OPTIONS beside the menu: %s" % str(_option_texts()))

	print("\n[B] Switching player 2 off: the tank leaves, everything kept")
	p2.health = 5  # took a hit this stage
	var p2_at := p2.global_position
	await _key(KEY_RIGHT)
	check(_focus() == _menu._p2_button, "right from RESUME reaches PLAYER 2, level with it")
	await _key(KEY_ENTER)
	check(GameManager.player_disabled[1] and _menu._p2_button.text == "PLAYER 2: OFF"
		and _menu.visible and _focus() == _menu._p2_button, "Enter: PLAYER 2: OFF, still in the menu")
	check(_hud.p2_lives_label.text == "OFF" and is_equal_approx(_hud.p2_score_label.modulate.a, 0.4)
		and _hud.p2_score_label.text == "8700" and _hud.p2_score_label.visible,
		"the HUD shows it at once: player 2's panel dimmed, OFF for lives, the score kept")
	await _key(KEY_ESCAPE)
	await _frames()
	check(_tank(1) == null and _tank(0) != null, "resumed: player 2's tank is gone, player 1's plays on")
	check(_bursts_at(p2_at) == 1, "leaving in a burst where it stood")
	check(_deaths.is_empty() and GameManager.player_lives[0] == 2 and GameManager.player_lives[1] == 4
		and GameManager.player_scores[1] == 8700,
		"no death, no life lost, the score kept")
	check(GameManager.player_hp[1] == 5 and GameManager.player_addons[1] == ["moon-shield", "anti-ice"]
		and GameManager.player_speed_levels[1] == 3 and GameManager.player_weapon_levels[1] == 2
		and GameManager.player_secondary_weapon_types[1] == "fire" and GameManager.player_secondary_weapon_counts[1] == 42,
		"its HP, add-ons, levels and weapon are kept")
	check(_game.enemy_spawner.max_concurrent_enemies == stage_cap, "one in play: the same enemy count")

	print("\n[C] While player 2 sits out")
	Input.action_press("p2_shoot")
	await _frames(4)
	Input.action_release("p2_shoot")
	await _frames()
	check(_tank(1) == null, "player 2's fire doesn't bring them back")
	var data: Dictionary = SaveManager._build_save_data()
	var saved = data["players"]["player2"]
	check(saved is Dictionary and saved["lives"] == 4 and saved["score"] == 8700 and saved["hp"] == 5
		and saved["speed_level"] == 3 and saved["weapon_level"] == 2 and saved["special_weapon_type"] == "fire"
		and saved["special_weapon_count"] == 42 and saved["defense_addon_type_2"] != "" and saved.get("disabled") == true,
		"the save keeps player 2, all of it, marked as sitting out")
	var path := SaveManager.get_save_dir() + "p2_off_probe.tsave"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var info: Dictionary = SaveManager._read_save_info(path)
	DirAccess.remove_absolute(path)
	var screen = load("res://scripts/ui/load_screen.gd").new()
	var line: String = screen._format_players(info)
	screen.free()
	check(line.contains("P2") and line.ends_with("(OFF)"), "Load Game lists it that way: \"%s\"" % line)

	print("\n[D] A click flips it too; left goes back to the menu")
	await _key(KEY_ESCAPE)
	_menu._p2_button.mouse_entered.emit()
	_menu._p2_button.pressed.emit()
	check(not GameManager.player_disabled[1] and _menu._p2_button.text == "PLAYER 2: ON" and _tank(1) != null
		and _focus() == _menu._p2_button, "a click: back on, a tank beside the base")
	await _key(KEY_ENTER)
	check(GameManager.player_disabled[1] and _menu._p2_button.text == "PLAYER 2: OFF", "Enter: off again")
	await _key(KEY_LEFT)
	check(_focus() == _menu._resume_button and GameManager.player_disabled[1], "left: RESUME, nothing flipped")
	await _key(KEY_ESCAPE)
	await _frames()
	check(_tank(1) == null and GameManager.player_hp[1] == 5 and GameManager.player_addons[1].size() == 2,
		"gone again, nothing lost")

	print("\n[E] Player 2 sitting out doesn't hold the stage open")
	GameManager.player_lives[0] = 0
	_tank(0).health = 0
	_tank(0).destroy()   # player 1's last tank
	await _frames(3)
	check(GameManager.player_lives[0] < 0 and _game.get_game_over_countdown() > 0,
		"player 1 out of lives: the countdown to Mission Fail starts")
	await _key(KEY_ESCAPE)
	check(_menu._p2_button.text == "PLAYER 2: OFF" and not _menu._p2_button.disabled, "PLAYER 2 can still come on")
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	check(_tank(1) != null and _game.get_game_over_countdown() < 0,
		"switched on, player 2's tank comes and the countdown stops")
	check(_menu._p2_button.text == "PLAYER 2: ON" and _menu._p2_button.disabled,
		"and can't go off again while player 1 is out: nobody would be left")
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	check(not GameManager.player_disabled[1], "(not with Enter, nor right, which stays put)")
	await _key(KEY_ESCAPE)
	var back := _tank(1)
	while back.is_materializing:
		await tree.process_frame
	check(back.health == 5 and back.has_moon_shield and back._current_utility_addon == "anti-ice"
		and back.speed_level == 3 and back.weapon_level == 2 and back.secondary_weapon_type == "fire"
		and back.secondary_weapon_count == 42 and GameManager.player_lives[1] == 4,
		"back with everything: HP 5, moon shield, anti-ice, speed 3, gun 2, 42 fire, 4 lives")
	check(_hud.p2_lives_label.text == "Lives: 4" and is_equal_approx(_hud.p2_score_label.modulate.a, 1.0),
		"its panel lit again")
	check(_game.enemy_spawner.max_concurrent_enemies == stage_cap, "and still the same enemy count")

	print("\n[F] A stage begun with player 2 sitting out")
	tree.root.remove_child(_game)
	_game.free()
	GameManager.player_lives = [2, 4]
	GameManager.player_disabled = [false, true]
	await _start_game()
	check(_tank(0) != null and _tank(1) == null, "only player 1's tank comes")
	check(_game.enemy_spawner.max_concurrent_enemies == stage_cap, "the same enemy count")
	check(not _game._played_stage[1], "player 2 won't get a results panel for it")
	await _key(KEY_ESCAPE)
	check(_menu._p2_button.text == "PLAYER 2: OFF", "the menu says so")
	await _key(KEY_ESCAPE)

	print("\n[G] Player 2 dying, then sitting out before the new tank comes")
	_game.set_player_enabled(1, true)
	await _frames()
	var doomed := _tank(1)
	while doomed.is_materializing:
		await tree.process_frame
	doomed.health = 0
	doomed.destroy()
	_game.set_player_enabled(1, false)
	await tree.create_timer(1.3).timeout
	check(_tank(1) == null and GameManager.player_lives[1] == 3,
		"the life lost stands, but no new tank comes while player 2 sits out")

	print("\n[G2] The base falling ends the stage for a benched player 2 as well")
	check(GameManager.player_disabled[1] and GameManager.player_lives[1] == 3, "(player 2 sitting out, 3 lives)")
	Events.base_destroyed.emit()
	await _frames()
	check(GameManager.player_lives[1] < 0 and _game.get_game_over_countdown() > 0,
		"its lives go with everyone's, and the countdown runs")
	Input.action_press("p2_shoot")
	await _frames(4)
	Input.action_release("p2_shoot")
	await _frames()
	check(GameManager.player_lives[1] < 0 and _tank(1) == null,
		"sitting out, player 2's fire doesn't rejoin them either")
	_game.set_player_enabled(1, true)
	await _frames()
	check(_tank(1) == null and _game.get_game_over_countdown() > 0,
		"switched on, no tank comes: player 2 has no life left")
	GameManager.player_lives[1] = 3   # (for the save checks below)

	print("\n[H] A one-player game has no PLAYER 2")
	GameManager.player_active[1] = false
	GameManager.player_disabled[1] = false
	await _key(KEY_ESCAPE)
	check(not _menu._p2_button.visible and _option_texts() == ["SOUND: ON", "ONLINE: OFF", "FULLSCREEN: OFF"],
		"PLAYER 2 is hidden: %s" % str(_option_texts()))
	await _key(KEY_ESCAPE)

	print("\n[I] A save with player 2 sitting out loads that way")
	GameManager.player_active = [true, true]
	GameManager.player_disabled = [false, true]
	var round_trip: Dictionary = SaveManager._build_save_data()
	GameManager.player_disabled = [false, false]
	SaveManager._restore_from_data(round_trip)
	check(GameManager.player_active[1] and GameManager.player_disabled[1] and GameManager.player_lives[1] == 3,
		"player 2 comes back in the game, sitting out, lives and all")
	round_trip["players"]["player2"] = null
	SaveManager._restore_from_data(round_trip)
	check(not GameManager.player_active[1] and not GameManager.player_disabled[1],
		"a save without player 2 leaves no one sitting out")
	GameManager.player_active = [true, true]
	GameManager.player_disabled = [false, true]
	GameManager.reset()
	check(not GameManager.player_disabled[0] and not GameManager.player_disabled[1], "and so does a new game")

	tree.root.remove_child(_game)
	_game.free()
	GameManager.player_disabled = [false, false]
	await tree.create_timer(0.8).timeout  # let the sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
