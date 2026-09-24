extends Node
## Headless test for the original's stage screens and what they report:
##   the intro before play (no tanks, no pause; fire hurries it), then the
##   players and, 3 s later, the enemies;
##   kills credited to the player whose shell, mine, blast, fire or bomb it was;
##   a cleared stage waiting for its leftover items, then "Mission Complete",
##   the results panels and the reward; a lost stage's "Mission Fail", results
##   and "Game Over"; the rules behind the panels.
## Run as an override main scene:
##   Godot --headless res://scenes/test/stage_screens_test.tscn

var _fail := 0
var _game      # the game scene (untyped: the test reads its private state)
var _overlay   # its StageOverlay
var _events: Array = []


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


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A fresh game scene, added to the tree; [param intro] false starts play at once.
## Leaving the stage (the next stage's autosave, the title) only reports here;
## [param own_results] keeps the game's own hand-over from the results (to
## Game Over, after a loss).
func _new_game(intro: bool, own_results := false) -> void:
	if _game != null:
		get_tree().root.remove_child(_game)
		_game.free()
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = intro
	get_tree().root.add_child(_game)
	_overlay = _game.stage_overlay
	for sig_name: String in ["results_finished", "game_over_finished"]:
		var sig: Signal = _overlay.get(sig_name)
		if not (own_results and sig_name == "results_finished"):
			for c in sig.get_connections():
				if c["callable"].get_object() == _game:
					sig.disconnect(c["callable"])
		sig.connect(func() -> void: _events.append(sig_name))
	await _frames(2)


## An enemy counted by the spawner exactly as EnemySpawner._spawn_enemy does.
func _enemy(type_id: int, tile: Vector2i) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _game.level_manager.tile_to_world(tile)
	e.tree_exited.connect(_game.enemy_spawner._on_enemy_removed)
	_game.enemy_spawner._active_enemies += 1
	return e


func _players() -> Array:
	return get_tree().get_nodes_in_group("players")


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return
	var theme_before: String = ThemeManager.current_theme
	ThemeManager.load_theme("juezhuantanke")
	GameManager.current_stage = 1
	GameManager.difficulty = 2
	GameManager.credits = 3
	GameManager.player_active = [true, true]
	GameManager.player_lives = [3, 3]
	GameManager.player_scores = [0, 0]
	Events.stage_cleared.connect(func() -> void: _events.append("stage_cleared"))
	Events.game_over.connect(func() -> void: _events.append("game_over"))

	print("\n[A] The intro plays over the new map; the tanks come after it")
	await _new_game(true)
	var spawner: EnemySpawner = _game.enemy_spawner
	check(_game.get_phase() == "intro" and _overlay.get_screen() == "intro" and _overlay.visible,
		"the stage opens on its intro")
	check(_overlay._stage_text == "Stage 01", "\"Stage 01\" (%s)" % _overlay._stage_text)
	check(_players().is_empty() and tree.get_nodes_in_group("enemies").is_empty(), "no tanks yet")
	check(GameManager.enemies_remaining == spawner._spawn_queue.size() and GameManager.enemies_remaining > 0,
		"but the HUD already counts the stage's %d enemies" % GameManager.enemies_remaining)
	GameManager.player_hp[0] = 3
	check(_game.hud._get_player_hp(0) == 3, "and each player's HP (no tank: the next one's)")
	await _key(KEY_ESCAPE)
	check(not _game.pause_menu.visible and not tree.paused, "Esc doesn't pause over the intro")
	Input.action_press("p1_shoot")
	check(is_equal_approx(_overlay._speed(), 3.5), "one player holding fire runs it 3.5x")
	Input.action_press("p2_shoot2")
	check(is_equal_approx(_overlay._speed(), 6.0), "both, 6x")
	Input.action_release("p1_shoot")
	Input.action_release("p2_shoot2")
	_overlay.advance(2.6 - _overlay.get_time())
	check(_game.get_phase() == "intro" and _players().is_empty(), "still on at 2.6 s")
	_overlay.advance(0.03)
	check(_game.get_phase() == "play" and not _overlay.visible, "over at 2.625 s: play")
	await _frames(2)
	check(_players().size() == 2, "both players' tanks roll in")
	check(spawner._first_wave_pending and spawner.spawn_timer.time_left > 2.5
		and tree.get_nodes_in_group("enemies").is_empty(), "the first enemy comes 3 s later")
	await _key(KEY_ESCAPE)
	check(_game.pause_menu.visible and tree.paused, "now Esc pauses")
	await _key(KEY_ESCAPE)
	check(not tree.paused, "and resumes")

	print("\n[B] A kill is the player's whose weapon it was")
	spawner.halt()
	for p in _players():
		p.is_invincible = true
	var lm: LevelManager = _game.level_manager
	GameManager.player_scores = [0, 0]
	GameManager.reset_stage_stats()
	# P2's shell.
	var e1 := _enemy(1, Vector2i(6, 6))
	await _frames(1)
	var p2: PlayerTank = null
	for p in _players():
		if p.player_id == 1:
			p2 = p
	var shell: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	p2.get_parent().get_parent().get_node("Bullets").add_child(shell)
	shell.global_position = Vector2(4000, 4000)
	shell.owner_tank = p2
	shell.is_player_bullet = true
	shell.owner_player = 1
	shell._on_body_entered(e1)
	check(e1.killed_by == 1 and GameManager.player_kills[1].get(1, 0) == 1
		and GameManager.player_scores[1] > 0 and GameManager.player_scores[0] == 0,
		"P2's shell: P2's kill and points (were all P1's before)")
	# P1's mine.
	var e2 := _enemy(13, Vector2i(12, 6))
	await _frames(1)
	e2.health = 1
	var mine = lm._spawn_mine(Vector2i(30, 20), 2, true, 0)
	check(mine.owner_id == 0, "a mine knows who laid it")
	mine._on_tank_contact(e2)   # a level-2 mine throws it; the hit comes on landing
	check(e2.is_flying and e2.health == 1, "its throw costs nothing yet")
	e2._land_from_flight()
	check(e2.killed_by == 0 and GameManager.player_kills[0].get(13, 0) == 1, "P1's mine: P1's kill, on landing")
	# P2's blast.
	var e3 := _enemy(21, Vector2i(18, 6))
	await _frames(1)
	e3.health = 1
	lm.spawn_explosion_blast(e3.global_position, 0, true, false, null, 1)
	await _frames(2)
	check(not is_instance_valid(e3) or e3.killed_by == 1, "P2's blast: P2's kill")
	check(GameManager.player_kills[1].get(21, 0) == 1, "counted for P2 (%s)" % str(GameManager.player_kills[1]))
	# P1's fire.
	var e4 := _enemy(17, Vector2i(24, 8))
	await _frames(1)
	e4.health = 1
	lm.ignite_fire_patch(lm.world_to_tile(e4.global_position), true, 0)
	var field = lm._fire_fields[-1]
	check(field.owner_id == 0, "a fire field knows whose shell lit it")
	await tree.create_timer(0.4).timeout
	var tile_owners: Array = []
	for t in field._tiles.values():
		tile_owners.append(t.owner_id)
	check(not tile_owners.is_empty() and tile_owners.count(0) == tile_owners.size(), "and so do its tiles")
	check(GameManager.player_kills[0].get(17, 0) == 1, "P1's fire: P1's kill (%s)" % str(GameManager.player_kills[0]))
	lm._clear_fire()
	# P2's bomb.
	var e5 := _enemy(3, Vector2i(30, 6))
	var e6 := _enemy(15, Vector2i(34, 6))
	await _frames(1)
	Events.bomb_all_enemies.emit(1)
	check(GameManager.player_kills[1].get(3, 0) == 1 and GameManager.player_kills[1].get(15, 0) == 1,
		"P2's bomb: every kill P2's")
	# Nobody's: a grass fire (neutral) finishing an enemy.
	var e7 := _enemy(2, Vector2i(6, 12))
	await _frames(1)
	var scores: Array = GameManager.player_scores.duplicate()
	e7.on_fire_contact(false, 1.0, true)
	check(e7.killed_by == -1 and GameManager.player_scores == scores
		and not GameManager.player_kills[0].has(2) and not GameManager.player_kills[1].has(2),
		"a grass fire's kill is nobody's: no points, no tally")
	# Hit chains: a tough enemy hit three times in a row by P1.
	var e8 := _enemy(16, Vector2i(12, 12))
	await _frames(1)
	e8.health = 10
	GameManager.reset_stage_stats()   # no chain left running from the kills above
	for i in 3:
		e8.hit_by = 0
		e8.take_damage()
	GameManager.settle_chains()
	check(GameManager.player_max_hits[0] == 3 and GameManager.player_max_hits[1] == 0,
		"three quick hits: P1's best chain is 3 (%s)" % str(GameManager.player_max_hits))
	e8.hit_by = 1
	e8.take_damage()
	check(e8.hit_by == -1, "a hit is spent once taken")
	e8.queue_free()
	await _frames(2)

	print("\n[C] A cleared stage waits for its leftover items")
	for c in tree.get_nodes_in_group("cookies"):
		c.queue_free()
	await _frames(1)
	spawner._spawn_queue.clear()
	spawner._active_enemies = 0
	for e in tree.get_nodes_in_group("enemies"):
		e.tree_exited.disconnect(spawner._on_enemy_removed)
		e.queue_free()
	await _frames(1)
	var cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	cookie.setup(CookieData.CookieType.HP_UP)
	_game.powerups_container.add_child(cookie)
	cookie.global_position = lm.tile_to_world(Vector2i(4, 2))
	# The panels' tallies: P2 ahead.
	GameManager.player_kills = [{1: 2}, {13: 1, 9: 1}]
	var last := _enemy(1, Vector2i(20, 4))
	await _frames(1)
	last.hit_by = 0
	last.take_damage()
	await _frames(2)
	check(_game._stage_clear_pending and _game.get_phase() == "play", "the last kill clears it; play goes on")
	await tree.create_timer(1.2).timeout
	check(_game.get_phase() == "play", "one item left: still waiting after 1.2 s")
	await tree.create_timer(1.3).timeout
	check(_game.get_phase() == "mission", "the item had its 2.25 s: the stage ends")

	print("\n[D] Mission Complete, the results and the reward")
	check(_overlay.get_screen() == "mission" and _overlay._title == "Mission Complete",
		"\"Mission Complete\"")
	check(_events.count("stage_cleared") == 1, "with the win jingle, once")
	check(_overlay._picture != null and _overlay._picture == ThemeManager.get_screen_texture("stage_win"),
		"the theme's win picture closes in")
	check(spawner.spawn_timer.is_stopped(), "no more enemies")
	await _key(KEY_ESCAPE)
	check(not tree.paused, "no pausing")
	Input.action_press("p1_shoot")
	var t0: float = _overlay.get_time()
	_overlay._process(0.1)
	Input.action_release("p1_shoot")
	check(is_equal_approx(_overlay.get_time() - t0, 0.1), "and fire can't hurry it")
	GameManager.player_max_hits = [5, 2]
	GameManager.player_max_combos = [1, 4]
	_overlay.advance(2.95 - _overlay.get_time())
	check(_game.get_phase() == "mission", "3 s long")
	_overlay.advance(0.06)
	check(_game.get_phase() == "results" and _overlay.get_screen() == "results", "then the results")
	check(_overlay._panel_x(0) + StageOverlay.PANEL_SIZE.x <= 0.0 and _overlay._panel_x(1) >= StageOverlay.SCREEN_SIZE.x,
		"the panels start off the screen, each beyond its own side")
	await _frames(2)
	check(_players().is_empty() and tree.get_nodes_in_group("cookies").is_empty()
		and _game.bullets_container.get_child_count() == 0, "the field is cleared under the picture")
	var panels: Array = _overlay._panels
	check(panels.size() == 2 and panels[0].player == 0 and panels[1].player == 1, "a panel for each player")
	check(panels[0].kills == [[3, 0], [0, 0], [0, 0], [0, 0]] and panels[0].total == 3,
		"P1: 3 plain tanks, total 3 (%s)" % str(panels[0].kills))
	check(panels[1].kills == [[0, 0], [0, 0], [0, 1], [1, 0]] and panels[1].total == 7,
		"P2: a fire tank (x3) and an AP tank (x4), total 7 (%s)" % str(panels[1].kills))
	check(panels[0].max_hits == 5 and panels[1].max_combos == 4, "with their best chains")
	check(panels[0].reward == 0 and panels[1].reward == 3000 and panels[1].copies.size() == 6,
		"P2 beat P1: 30 x 100 = 3000 in 6 copies; P1 nothing")
	var before: Array = GameManager.player_scores.duplicate()
	_overlay.advance(1.49 - _overlay.get_time())
	check(is_equal_approx(_overlay._panel_x(1), StageOverlay.PANEL_HOME_X[1]), "slid in by 0.75 s")
	check(GameManager.player_scores == before, "no reward before the count ends")
	_overlay.advance(0.02)
	check(GameManager.player_scores[1] == before[1] + 3000 and GameManager.player_scores[0] == before[0],
		"the count ends at 1.5 s: P2's score +3000")
	_overlay.advance(5.49 - _overlay.get_time())
	check(_events.count("results_finished") == 0, "still up at 5.49 s")
	_overlay.advance(0.02)
	check(_events.count("results_finished") == 1, "over at 5.5 s (the game then autosaves, next stage)")

	print("\n[E] Out of lives with no credits: Mission Fail, results, Game Over")
	GameManager.player_active = [true, false]
	GameManager.player_lives = [0, 3]
	GameManager.credits = 0
	await _new_game(false, true)
	await _frames(2)
	var p1: PlayerTank = _players()[0]
	p1.is_invincible = false
	p1._hit_grace_frame = -1
	p1.health = 1
	p1.take_damage()
	await _frames(3)
	check(GameManager.player_lives[0] < 0, "P1's last tank is gone")
	check(_game.get_phase() == "mission" and _overlay._title == "Mission Fail", "\"Mission Fail\" at once")
	check(_events.count("game_over") == 1, "with the lose jingle")
	check(_overlay._picture == ThemeManager.get_screen_texture("stage_lose"), "the lose picture")
	check(_game.hud._lives_text(0) == "GAME OVER", "P1's corner reads GAME OVER")
	GameManager.player_kills[0] = {1: 5}
	_overlay.advance(3.01)
	check(_game.get_phase() == "results" and _overlay._panels.size() == 1, "results: P1's panel alone")
	var lost_scores: Array = GameManager.player_scores.duplicate()
	_overlay.advance(2.0)
	check(_overlay._panels[0].reward == 0 and GameManager.player_scores == lost_scores, "no reward for a lost stage")
	_overlay.advance(3.99 - _overlay.get_time())
	check(_game.get_phase() == "results", "held until 4.0 s")
	_overlay.advance(0.02)
	check(_game.get_phase() == "game_over" and _overlay.get_screen() == "game_over", "then Game Over")
	check(_overlay._letters.size() == 8 and _overlay._letters[0].glyph == "G"
		and is_equal_approx(_overlay._letters[0].home.x, 176.0 * StageOverlay.SCALE), "its 8 letters from x 176")
	_overlay.advance(4.12)
	check(_events.count("game_over_finished") == 0, "on until 4.125 s")
	_overlay.advance(0.01)
	check(_events.count("game_over_finished") == 1, "then back to the title")

	print("\n[F] With credits, a rejoin window first; losing the base with none ends it")
	GameManager.player_lives = [0, 3]
	GameManager.credits = 2
	await _new_game(false)
	await _frames(2)
	p1 = _players()[0]
	p1.is_invincible = false
	p1._hit_grace_frame = -1
	p1.health = 1
	p1.take_damage()
	await _frames(3)
	check(_game.get_phase() == "play" and _game.get_game_over_countdown() > 4.5
		and _game.get_game_over_countdown() <= 5.0, "a 5 s countdown to rejoin")
	check(_game.enemy_spawner.spawn_timer.paused, "the enemies hold their reinforcements")
	Input.action_press("p1_shoot")
	await _frames(1)
	Input.action_release("p1_shoot")
	await _frames(1)
	check(GameManager.player_lives[0] == 3 and GameManager.credits == 1 and _game.get_game_over_countdown() < 0
		and not _game.enemy_spawner.spawn_timer.paused, "fire: rejoined for a credit, the countdown off")
	# Out again, and nobody rejoins: the stage is lost when the 5 s run out.
	var fails: int = _events.count("game_over")
	GameManager.player_lives[0] = 0
	p1 = _players()[0]
	p1.is_invincible = false
	p1._hit_grace_frame = -1
	p1.health = 1
	p1.take_damage()
	await tree.create_timer(4.6).timeout
	check(_game.get_phase() == "play", "still open 4.6 s later")
	await tree.create_timer(0.6).timeout
	check(_game.get_phase() == "mission" and _events.count("game_over") == fails + 1,
		"closed at 5 s: Mission Fail")
	GameManager.player_lives = [0, 3]
	GameManager.credits = 0
	await _new_game(false)
	await _frames(2)
	fails = _events.count("game_over")
	Events.base_destroyed.emit()
	await _frames(2)
	check(_game.get_phase() == "mission" and _events.count("game_over") == fails + 1,
		"the base destroyed with no credits: Mission Fail at once")

	print("\n[G] The panel's rules")
	var every: Dictionary = {}
	for type_id in range(1, 25):
		every[type_id] = 1
	check(StageOverlay.cell_kills(every) == [[2, 2], [4, 4], [4, 4], [2, 2]], "all 24 types have a cell")
	check(StageOverlay.cell_kills({5: 2, 22: 1, 11: 3}) == [[0, 0], [2, 1], [0, 3], [0, 0]],
		"rapid left, mines right (x2); explosive left, fire right (x3)")
	var r: Array = StageOverlay.rewards_for([5] as Array[int], 2)
	check(r[0]["amount"] == 1000 and r[0]["copies"] == 4, "alone: 10 x 100")
	check(StageOverlay.rewards_for([0] as Array[int], 2)[0]["amount"] == 0, "alone with no kills: nothing")
	r = StageOverlay.rewards_for([4, 4] as Array[int], 2)
	check(r[0]["amount"] == 1000 and r[1]["amount"] == 1000, "level: both 10x")
	r = StageOverlay.rewards_for([0, 0] as Array[int], 2)
	check(r[0]["amount"] == 0 and r[1]["amount"] == 0, "level at nothing: nothing")
	check(StageOverlay.rewards_for([5] as Array[int], 5)[0]["amount"] == 2500
		and StageOverlay.rewards_for([5] as Array[int], 9)[0]["amount"] == 2500,
		"hardest difficulty: 10 x 250 (and past it)")
	check(StageOverlay.rewards_for([5] as Array[int], 1)[0]["amount"] == 660, "easy: 10 x 66")

	print("\n[H] Theme pictures")
	check(ThemeManager.get_stage_picture("si01.jpg") != null, "a stage picture is found whatever its case")
	check(ThemeManager.get_stage_picture("SI5.JPG") == null, "a missing one is null (the intro plays over the map)")
	check(ThemeManager.get_screen_texture("results_panel") != null, "the results panel picture")
	ThemeManager.load_theme("default")
	check(ThemeManager.get_screen_texture("stage_win") == null, "a theme without pictures has none")
	_overlay.play_mission(true)
	check(_overlay._plain_backdrop, "so its stage end closes a plain backdrop over the field")

	get_tree().root.remove_child(_game)
	_game.free()
	ThemeManager.load_theme(theme_before)
	SoundManager.stop_music()   # the stage-end tracks run 15 s and more
	await tree.create_timer(0.8).timeout  # let the sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
