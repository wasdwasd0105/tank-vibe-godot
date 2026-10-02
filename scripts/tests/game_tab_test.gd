extends Node
## Headless test for the settings' GAME tab rules: ENEMY MINES (off, the mine
## tanks fire rapid shells at their rapid counterparts' levels, switching at
## once on the field, and the enemies' laid mines go), ENEMY MINE LEVEL (the
## strongest mine an enemy lays), and a DIFFICULTY changed mid-stage (the
## enemies still to come and the field's limit follow at once; the tanks on the
## field keep their guns and shake no items loose), and the title's settings
## page with its GAME and GENERAL tabs. Being a test scene it runs on its own
## settings file, never the player's.
## Run as an override main scene:
##   Godot --headless res://scenes/test/game_tab_test.tscn

const T := CookieData.CookieType

var _fail := 0
var _game: Node
var _lm: LevelManager
var _spawner: EnemySpawner
var _player: PlayerTank
var _difficulty_signals := 0


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _frames(n: int = 2) -> void:
	for i in range(n):
		await get_tree().physics_frame
	await get_tree().process_frame


func _at(local: Vector2) -> Vector2:
	return _lm.global_position + local


## An enemy of [param type_id] at the game's difficulty now, its AI off.
func _spawn_enemy(local: Vector2, type_id: int, hp: int = 5) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _at(local)
	e.current_direction = Vector2.DOWN
	e.max_health = hp
	e.health = hp
	return e


## Open ground everywhere but the base's own block, so mines and spawns find room.
func _clear_arena() -> void:
	for tile in _lm._fg_tile_data.keys():
		if tile.x < 16 or tile.x > 23 or tile.y < 25:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(tile)


func _clear_field() -> void:
	_lm._clear_mines()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for c in get_tree().get_nodes_in_group("cookies"):
		c.queue_free()
	await _frames(3)


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


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


func _names(rows: Array) -> Array:
	return rows.map(func(row: Button) -> String: return MenuRows.layout_of(row).get_node("Name").text)


func _cookies_of(type: int) -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("cookies"):
		if c.cookie_type == type and not c.is_queued_for_deletion():
			n += 1
	return n


func _read_settings() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(InputSettings.get_save_path())
	return cfg


## The queue's types, counted: {type_id: how many still to come}.
func _queued() -> Dictionary:
	var counts := {}
	for type_id: int in _spawner._spawn_queue:
		counts[type_id] = counts.get(type_id, 0) + 1
	return counts


## Stage 1 listing [param counts] ({type_id: count}) and a limit of
## [param limit], lined up again at the game's difficulty.
func _restage(counts: Dictionary, limit: int) -> void:
	var stage = LevelData.get_stages()[0]
	var listed: Array = []
	listed.resize(24)
	listed.fill(0)
	for type_id: int in counts:
		listed[type_id - 1] = counts[type_id]
	stage.enemy_count = listed
	stage.max_count = limit
	_spawner.prepare_stage(1)


## Sends [param n] enemies in, as the waves would, with their AI off.
func _send(n: int) -> void:
	for i in n:
		if _spawner._spawn_enemy():
			var newest: Node = _game.get_node("Entities/Enemies").get_child(-1)
			newest.set_physics_process(false)
	await _frames()


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() == InputSettings.SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return

	print("\n[A] ENEMY MINES and ENEMY MINE LEVEL: saved settings")
	check(InputSettings.get_enemy_mines() and InputSettings.get_enemy_mine_level() == 3,
		"out of the box: enemy mines on, up to level 3")
	InputSettings.save_enemy_mines(false)
	InputSettings.save_enemy_mine_level(2)
	var cfg := _read_settings()
	check(cfg.get_value("game", "enemy_mines", true) == false and cfg.get_value("game", "enemy_mine_level", 0) == 2,
		"saved to the settings file")
	InputSettings.save_enemy_mine_level(9)
	check(InputSettings.get_enemy_mine_level() == 4, "a level past 4 is held to 4")
	InputSettings.save_enemy_mine_level(0)
	check(InputSettings.get_enemy_mine_level() == 1, "and one under 1 to 1")
	cfg = _read_settings()
	cfg.set_value("game", "enemy_mine_level", 9)
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(InputSettings.get_enemy_mine_level() == 4, "a hand-edited 9 reads as 4")
	cfg.set_value("game", "enemy_mines", "maybe")
	cfg.set_value("game", "enemy_mine_level", "lots")
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(InputSettings.get_enemy_mines() and InputSettings.get_enemy_mine_level() == 3,
		"hand-edited nonsense reads as the defaults")

	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	GameManager.difficulty = 1
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_lm = _game.get_level_manager()
	_spawner = _game.get_node("EnemySpawner")
	_spawner.spawn_timer.stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	for p in tree.get_nodes_in_group("players"):
		_player = p
	_clear_arena()
	_player.global_position = _at(Vector2(96, 96))   # parked in a corner
	await _frames(3)

	print("\n[B] With ENEMY MINES off, the mine tanks fire rapid shells")
	var layer := _spawn_enemy(Vector2(320, 320), 22)
	check(layer.special_weapon_type == "mine" and layer.special_weapon_level == 1 and layer.max_bullets == 1,
		"mines on: a type-22 tank lays mines at gun level 1 on EASY, one shell at a time")
	InputSettings.save_enemy_mines(false)
	var gunner := _spawn_enemy(Vector2(480, 320), 22)
	check(gunner.special_weapon_type == "rapid" and gunner._has_rapid_special() and not gunner._has_mine_special(),
		"mines off: a new type-22 tank fires rapid shells instead")
	check(gunner.special_weapon_level == CookieData.get_enemy_weapon_level(6, 1) and gunner.special_weapon_level == 0
		and gunner.max_bullets == EnemyTank.SHELL_SPECIAL_MAX_BULLETS,
		"at its rapid counterpart's level (type 6 on EASY: 0, not the mine level 1), up to 12 shells out")
	check(gunner.can_take_cookie(T.RAPID_COOKIE) and not gunner.can_take_cookie(T.MINE_COOKIE),
		"and its own gun's item is the rapid one")
	await _frames()
	var shells_before := gunner.active_bullets
	check(gunner._shoot_special_rapid() and gunner.active_bullets == shells_before + 1, "it fires a rapid shell")
	check(layer.special_weapon_type == "rapid" and layer.max_bullets == EnemyTank.SHELL_SPECIAL_MAX_BULLETS,
		"the mine tank already on the field switched to rapid at once")
	var regular := _spawn_enemy(Vector2(640, 320), 9)
	check(regular.special_weapon_type == "fire", "other tanks keep their weapons (type 9: fire)")
	InputSettings.save_enemy_mines(true)
	check(layer.special_weapon_type == "mine" and layer.max_bullets == EnemyTank.PLAIN_MAX_BULLETS
		and gunner.special_weapon_type == "mine", "mines on again: both lay mines again")
	await _clear_field()

	print("\n[C] Switching mines off mid-stage keeps what items gave, and clears the enemies' mines")
	var veteran := _spawn_enemy(Vector2(320, 320), 24)   # EASY: mine level 2
	veteran.item_gun_up()
	check(veteran.special_weapon_level == 3, "a type-24 tank on EASY (mine level 2) takes a Power Up: 3")
	var enemy_mine_ok := _lm.try_place_mine(veteran, 1)
	_player.global_position = _at(Vector2(800, 640))
	await _frames()
	var player_mine_ok := _lm.try_place_mine(_player, 1)
	await _frames()
	check(enemy_mine_ok and player_mine_ok and _lm.get_mines().size() == 2, "an enemy's mine and a player's lie on the field")
	InputSettings.save_enemy_mines(false)
	await _frames()
	check(veteran.special_weapon_type == "rapid" and veteran.special_weapon_level == CookieData.get_enemy_weapon_level(8, 1) + 1,
		"mines off: it fires rapid at type 8's level plus the one it took (%d)" % veteran.special_weapon_level)
	var left := _lm.get_mines()
	check(left.size() == 1 and left[0].from_player, "the enemy's mine is gone; the player's stays")
	InputSettings.save_enemy_mines(true)
	check(veteran.special_weapon_type == "mine" and veteran.special_weapon_level == 3, "mines on: back to mine level 3")
	await _clear_field()
	_player.global_position = _at(Vector2(96, 96))
	await _frames()

	print("\n[D] ENEMY MINE LEVEL: the strongest mine an enemy lays")
	GameManager.difficulty = 5
	var toughest := _spawn_enemy(Vector2(320, 320), 24)   # INSANE: gun level 3
	GameManager.difficulty = 1
	check(toughest.special_weapon_level == 3, "an INSANE type-24 tank has gun level 3")
	var laid: Array = []
	for setting in [4, 3, 2, 1]:
		InputSettings.save_enemy_mine_level(setting)
		_lm._clear_mines()
		toughest.current_direction = Vector2.DOWN
		await _frames()
		var ok := toughest._lay_mine_special()
		var mines := _lm.get_mines()
		laid.append(mines[0].level if ok and mines.size() == 1 else -1)
	check(laid == [3, 2, 1, 0], "set to 4, 3, 2, 1 it lays mines of level 4, 3, 2, 1 (Mine.level %s)" % str(laid))
	_lm._clear_mines()
	_player.global_position = _at(Vector2(800, 640))
	await _frames()
	check(_lm.try_place_mine(_player, 3) and _lm.get_mines()[0].level == 3, "a player's mines are not held to it")
	InputSettings.save_enemy_mine_level(InputSettings.DEFAULT_ENEMY_MINE_LEVEL)
	await _clear_field()
	_player.global_position = _at(Vector2(96, 96))

	print("\n[E] DIFFICULTY can change in a game")
	GameManager.difficulty_changed.connect(func() -> void: _difficulty_signals += 1)
	GameManager.set_difficulty(4)
	check(GameManager.difficulty == 4 and InputSettings.get_saved_difficulty() == 4 and _difficulty_signals == 1,
		"set to 4: the game's, saved for new games too, and announced")
	GameManager.set_difficulty(4)
	check(_difficulty_signals == 1, "setting the same again announces nothing")
	GameManager.set_difficulty(9)
	check(GameManager.difficulty == 5, "held to 5")
	GameManager.set_difficulty(0)
	check(GameManager.difficulty == 1, "and to 1")

	print("\n[F] Mid-stage, the enemies still to come follow the new difficulty")
	_restage({21: 8, 6: 4}, 12)   # EASY (75 %): 6 and 3; limit 12 at 83 %
	check(_queued() == {21: 6, 6: 3} and GameManager.enemies_remaining == 9,
		"EASY sends 6 type-21 and 3 type-6 tanks (%s)" % str(_queued()))
	GameManager.set_difficulty(2)   # 100 %; limit 12 at 100 %
	check(_queued() == {21: 8, 6: 4} and GameManager.enemies_remaining == 12 and _spawner.max_concurrent_enemies == 12,
		"NORMAL: 8 and 4 to come, 12 left in all, 12 at once (%s, %d at once)" % [str(_queued()), _spawner.max_concurrent_enemies])
	await _send(5)
	var sent: Dictionary = _spawner._sent_by_type.duplicate()
	var on_field := get_tree().get_nodes_in_group("enemies").size()
	check(on_field == 5 and GameManager.enemies_remaining == 12, "five come on the field, still 12 left")
	GameManager.set_difficulty(5)   # 175 %: 14 and 7
	check(_queued().get(21, 0) == 14 - sent.get(21, 0) and _queued().get(6, 0) == 7 - sent.get(6, 0)
		and GameManager.enemies_remaining == 21 and _spawner.max_concurrent_enemies == 18,
		"INSANE: 14 and 7 in all, less those sent, 21 left, 18 at once (%s)" % str(_queued()))
	_spawner.add_reinforcements(6)   # an enemy took "+1 UP": one more of each type to come
	var with_extras := GameManager.enemies_remaining
	var queued_before := _spawner._spawn_queue.size()
	GameManager.set_difficulty(1)   # 75 %: 6 and 3 in all, and the extra one of each
	var want := {}
	for type_id: int in [21, 6]:
		var still := maxi({21: 6, 6: 3}[type_id] + 1 - sent.get(type_id, 0), 0)
		if still > 0:
			want[type_id] = still
	check(_queued() == want, "EASY again: 6 and 3 in all with a reinforcement each, less those sent (%s, sent %s)"
		% [str(_queued()), str(sent)])
	check(GameManager.enemies_remaining == with_extras + _spawner._spawn_queue.size() - queued_before,
		"and the count left follows (%d)" % GameManager.enemies_remaining)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await _frames(3)
	var cleared := [false]
	Events.all_enemies_defeated.connect(func() -> void: cleared[0] = true, CONNECT_ONE_SHOT)
	_spawner._extra_by_type.clear()
	for type_id: int in [21, 6]:
		_spawner._sent_by_type[type_id] = 99
	GameManager.set_difficulty(3)
	check(_spawner._spawn_queue.is_empty() and cleared[0], "none left to come and none on the field: the stage is won")
	_game._stage_clear_pending = false   # the test goes on in this stage
	_spawner._sent_by_type.clear()   # so a recount would line some up again
	_spawner.halt()
	GameManager.set_difficulty(4)
	check(_spawner._spawn_queue.is_empty(), "a stage that is over takes no notice")

	print("\n[G] The tanks on the field keep their guns, and lowering it shakes no items loose")
	_restage({6: 8}, 8)
	GameManager.set_difficulty(5)
	var rapid := _spawn_enemy(Vector2(640, 320), 6)
	check(rapid.special_weapon_level == 2, "an INSANE type-6 tank: rapid level 2")
	GameManager.set_difficulty(1)
	check(rapid.special_weapon_level == 2, "the difficulty lowered to EASY: it keeps level 2")
	var power_ups := _cookies_of(T.WEAPONS_UP)
	rapid.take_damage(Vector2.UP)
	await _frames()
	check(rapid.health == 4 and _cookies_of(T.WEAPONS_UP) == power_ups,
		"a hit it survives flings no Power Up: level 2 is its own, not an item's")
	var newcomer := _spawn_enemy(Vector2(800, 320), 6)
	check(newcomer.special_weapon_level == 0, "a new type-6 tank comes at EASY's level 0")

	await _check_base_invincible()
	_game.queue_free()
	await _frames(3)
	await _check_title_tabs()
	await tree.create_timer(0.5).timeout   # let the sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


## [H] The title screen's settings: a GAME | GENERAL strip over the two tabs'
## rows, the page one size whichever shows.
func _check_title_tabs() -> void:
	print("\n[H] The title's settings: GENERAL and GAME tabs")
	var tree := get_tree()
	var title = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(title)
	await tree.process_frame
	await tree.process_frame
	title._settings_button.grab_focus()
	await _key(KEY_ENTER)
	var strip: Button = title._tabs.strip
	check(title._page == title.Page.SETTINGS and title._tabs.current == title.SettingsTab.GENERAL
		and _focus() == title._common.sfx_row and strip.visible and MenuRows.tab(strip, 0).text == "GENERAL"
		and MenuRows.tab(strip, 1).text == "GAME", "SETTINGS opens on its GENERAL tab, on SFX VOLUME, under GENERAL | GAME")
	var game_rows: Array = [title._map_row, title._import_map_row]
	game_rows.append_array(title._game.rows())
	check(_names(game_rows) == ["MAP", "IMPORT MAP", "DIFFICULTY", "GAME SPEED", "BASE INVINCIBLE", "ENEMY MINES",
		"ENEMY MINE LEVEL"], "the GAME tab: %s" % str(_names(game_rows)))
	check(not "_credits_row" in title and _names(title._common.rows()).find("CREDITS") < 0,
		"and no CREDITS anywhere: they are unlimited")
	await tree.process_frame
	var page_rect: Rect2 = title._settings_page.get_global_rect()
	await _key(KEY_UP)
	check(_focus() == strip, "up from SFX VOLUME: the strip")
	await _key(KEY_RIGHT)
	check(title._tabs.current == title.SettingsTab.GAME and _focus() == strip and title._game_rows.visible
		and not title._settings_rows.visible, "right: GAME, the focus still on the strip")
	await tree.process_frame
	check(title._settings_page.get_global_rect() == page_rect, "the page keeps its size (%s)" % str(page_rect.size))
	await _key(KEY_DOWN)
	check(_focus() == title._map_row, "down: its first row, MAP")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	check(title._tabs.current == title.SettingsTab.GENERAL and _focus() == title._common.sfx_row,
		"LB: GENERAL again, on SFX VOLUME")
	MenuRows.tab(strip, 1).pressed.emit()
	check(title._tabs.current == title.SettingsTab.GAME, "a click on GAME picks it")
	MenuRows.tab(strip, 1).pressed.emit()
	check(title._tabs.current == title.SettingsTab.GAME and MenuRows.tab(strip, 1).button_pressed,
		"a second click on it changes nothing")
	title._game.difficulty_row.grab_focus()
	var before := InputSettings.get_saved_difficulty()
	await _key(KEY_RIGHT)
	check(InputSettings.get_saved_difficulty() == before + 1 and GameManager.difficulty == before + 1
		and MenuRows.value_label(title._game.difficulty_row).text.begins_with(str(before + 1)),
		"DIFFICULTY on the title: new games' difficulty, saved")
	await _key(KEY_LEFT)
	await _key(KEY_ESCAPE)
	check(title._page == title.Page.MAIN and _focus() == title._settings_button, "Esc: the main menu, on SETTINGS")
	await _key(KEY_ENTER)
	check(title._tabs.current == title.SettingsTab.GENERAL and _focus() == title._common.sfx_row,
		"SETTINGS again: GENERAL, on SFX VOLUME")
	title.queue_free()
	await tree.process_frame


## [I] BASE INVINCIBLE: no shell destroys the base while it's on, and the flag
## shows the guard all the while. Last of the stage's checks: with it off again,
## a shell takes the base, as ever.
func _check_base_invincible() -> void:
	print("\n[I] BASE INVINCIBLE: no shell destroys the base")
	var eagle: BaseFlag = _game.eagle
	check(not InputSettings.get_base_invincible() and not eagle.invincible, "out of the box: off, the flag unguarded")
	var falls := [0]
	var count_fall := func() -> void: falls[0] += 1
	Events.base_destroyed.connect(count_fall)
	InputSettings.save_base_invincible(true)
	check(eagle.invincible and eagle.state_name() == "invincible" and _read_settings().get_value("game", "base_invincible", false),
		"switched on mid-stage: saved, and the flag shows the guard at once")
	for pierces in [false, true]:
		var shell: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
		shell.is_player_bullet = false
		shell.pierces = pierces
		_game.get_node("Entities/Bullets").add_child(shell)
		shell.global_position = _at(Vector2(64, 64))   # out of the way: the hit is handed to it
		shell._on_body_entered(eagle)
		check(falls[0] == 0 and shell._destroyed and not _game._base_destroyed,
			"an enemy %s reaching the base just stops there: the base stands" % ("AP shell" if pierces else "shell"))
	_lm.fortify_base(60.0)
	_lm._revert_fortification()
	check(eagle.invincible, "Flag On Guard running out leaves the guard showing")
	eagle.invincible = false   # as a new stage's flag starts
	_lm.load_stage(1)
	check(eagle.invincible, "and a stage begun with it on starts guarded")
	InputSettings.save_base_invincible(false)
	check(not eagle.invincible, "switched off: the flag unguarded again")
	var last: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	last.is_player_bullet = false
	_game.get_node("Entities/Bullets").add_child(last)
	last.global_position = _at(Vector2(64, 64))
	last._on_body_entered(eagle)
	check(falls[0] == 1 and _game._base_destroyed, "and a shell reaching it destroys it, as ever")
	Events.base_destroyed.disconnect(count_fall)
	var cfg := _read_settings()
	cfg.set_value("game", "base_invincible", "yes")
	cfg.save(InputSettings.get_save_path())
	InputSettings.load_and_apply()
	check(not InputSettings.get_base_invincible(), "a hand-edited value that isn't ON or OFF reads as off")
