extends Node
## Headless test for players and bots blocking each other. They never collide
## physically (a bot must not shove the player), so each checks the other before
## stepping. Two tanks that already overlap (a turn's grid snap, a revive or a
## mine landing can put them there) must still be able to drive apart.
## Run as an override main scene:
##   Godot --headless res://scenes/test/tank_block_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _at(local: Vector2) -> Vector2:
	return _lm.global_position + local


func _spawn_enemy(local: Vector2, facing: Vector2) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _at(local)
	e.current_direction = facing
	e._update_sprite_direction()
	return e


func _face(tank: BaseTank, facing: Vector2) -> void:
	tank.current_direction = facing
	tank._update_sprite_direction()


## Holds a player direction for [param seconds] and returns how far it moved.
func _drive(action: String, seconds: float) -> Vector2:
	var from := _player.global_position
	Input.action_press(action)
	await get_tree().create_timer(seconds).timeout
	Input.action_release(action)
	await get_tree().physics_frame
	return _player.global_position - from


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_lm = _game.get_level_manager()
	_game.get_node("EnemySpawner").spawn_timer.stop()
	for p in tree.get_nodes_in_group("players"):
		_player = p
	while _player.is_materializing:
		await tree.process_frame
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	# Open ground in the middle of the field.
	for tile in _lm._fg_tile_data.keys():
		if tile.x >= 4 and tile.x <= 36 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		if tile.x >= 4 and tile.x <= 36 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_bg_tile(tile)
	_player.is_invincible = true
	_player.invincible_timer = 999.0
	await tree.process_frame

	var home := Vector2(640, 384)

	print("\n[A] Apart, they still stop each other")
	_player.global_position = _at(home)
	_face(_player, Vector2.RIGHT)
	var bot := _spawn_enemy(home + Vector2(61, 0), Vector2.LEFT)   # 1 px gap
	await tree.physics_frame
	await tree.physics_frame
	check(_player._is_enemy_ahead(), "player facing a bot 1 px away is blocked")
	check(bot._is_player_ahead(), "bot facing the player 1 px away is blocked")
	_face(_player, Vector2.UP)
	check(not _player._is_enemy_ahead(), "player facing away from it is not")
	bot.global_position = _at(home + Vector2(160, 0))
	await tree.physics_frame
	var moved := await _drive("p1_right", 1.0)
	var gap: float = bot.global_position.x - _player.global_position.x - 60.0
	check(moved.x > 50.0 and gap >= 0.0 and gap < 3.0, "driving at a bot stops the player against it, no overlap (gap %.1f px)" % gap)
	bot.queue_free()

	print("\n[B] Overlapping, they can always drive apart, never further in")
	# The screenshot's case: the bot up-left of the player, corners 12 px deep.
	_player.global_position = _at(home)
	var stuck := _spawn_enemy(home + Vector2(-48, -48), Vector2.UP)
	await tree.physics_frame
	for c in [[Vector2.DOWN, false], [Vector2.RIGHT, false], [Vector2.UP, true], [Vector2.LEFT, true]]:
		_face(_player, c[0])
		check(_player._is_enemy_ahead() == c[1], "player facing %s: %s" % [c[0], "blocked (into the bot)" if c[1] else "free (away from the bot)"])
	for c in [[Vector2.UP, false], [Vector2.LEFT, false], [Vector2.DOWN, true], [Vector2.RIGHT, true]]:
		_face(stuck, c[0])
		check(stuck._is_player_ahead() == c[1], "bot facing %s: %s" % [c[0], "blocked (into the player)" if c[1] else "free (away from the player)"])
	_face(_player, Vector2.DOWN)
	moved = await _drive("p1_down", 0.5)
	check(moved.y > 30.0, "the player drives out of the overlap (moved %.0f px)" % moved.y)
	# And the bot, left to its own AI with no turns or shots due.
	_player.global_position = _at(home)
	_face(stuck, Vector2.UP)
	stuck._command = 0  # up
	stuck._ai_clock = -99.0
	stuck._shoot_cooldown = 99.0
	var bot_from := stuck.global_position
	stuck.set_physics_process(true)
	await tree.create_timer(0.5).timeout
	stuck.set_physics_process(false)
	check(bot_from.y - stuck.global_position.y > 30.0, "the bot drives out of the overlap (moved %.0f px)" % (bot_from.y - stuck.global_position.y))
	stuck.queue_free()

	print("\n[C] Side by side, touching: slide past, but not into each other")
	_player.global_position = _at(home)
	var beside := _spawn_enemy(home + Vector2(0, -60), Vector2.DOWN)
	await tree.physics_frame
	await tree.physics_frame
	_face(_player, Vector2.RIGHT)
	check(not _player._is_enemy_ahead(), "player can slide along the bot")
	_face(_player, Vector2.UP)
	check(_player._is_enemy_ahead(), "but not drive up into it")
	check(beside._is_player_ahead(), "and the bot can't drive down into the player")
	beside.queue_free()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
