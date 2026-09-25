extends Node
## Headless test for tanks held by "Hold Enemy", as Tank.exe moved them: the
## hold stops a tank's commands, not its motion, so one that was moving glides
## on straight at the speed it had until a wall, water or an opposing tank stops
## it, then stays put; it neither turns nor drives meanwhile, and gets its
## controls back when the hold ends. Both sides: enemies frozen by a player's
## Hold Enemy, players held by an enemy's.
## Run as an override main scene:
##   Godot --headless res://scenes/test/hold_glide_test.tscn

const IRON := 0x39
const WALL_COLUMN := 30   # an iron wall down tile column 30: x 960..992 on the field

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


func _local(tank: BaseTank) -> Vector2:
	return tank.global_position - _lm.global_position


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _enemy(local: Vector2) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	_game.enemies_container.add_child(e)
	e.global_position = _at(local)
	return e


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active = [true, false]
	GameManager.player_lives = [3, 3]
	GameManager.player_speed_levels = [3, 1]
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_lm = _game.get_level_manager()
	_game.enemy_spawner.halt()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	# Open ground above the base, and an iron wall down column 30.
	for tile in _lm._fg_tile_data.keys():
		if tile.y < 24:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(tile)
	for y in range(0, 24):
		_lm._place_fg_tile(Vector2i(WALL_COLUMN, y), IRON)
	_player = tree.get_nodes_in_group("players")[0]
	while _player.is_materializing:
		await tree.process_frame
	_player.global_position = _at(Vector2(96, 704))
	await _wait(0.1)
	var wall_left := WALL_COLUMN * 32.0

	print("\n[A] An enemy frozen while driving glides on until the wall")
	GameManager.freeze_all_enemies(30.0)
	var glider := _enemy(Vector2(640, 128))
	var parked := _enemy(Vector2(320, 256))
	await tree.physics_frame
	glider.current_direction = Vector2.RIGHT
	glider._update_sprite_direction()
	glider.velocity = Vector2.RIGHT * 256.0
	parked.velocity = Vector2.ZERO
	await _wait(0.4)
	var mid := _local(glider)
	check(mid.x > 700.0 and is_equal_approx(mid.y, 128.0),
		"still moving right, frozen, straight along its row (x %.0f)" % mid.x)
	await _wait(1.5)
	var stopped := _local(glider)
	check(glider.velocity == Vector2.ZERO and absf(stopped.x + 30.0 - wall_left) < 3.0,
		"stopped against the wall (its right edge %.0f, the wall %.0f)" % [stopped.x + 30.0, wall_left])
	check(is_equal_approx(stopped.y, 128.0) and glider.current_direction == Vector2.RIGHT,
		"never turned or slid sideways")
	check(_local(parked) == Vector2(320, 256), "one frozen standing still stays put")
	await _wait(0.5)
	check(_local(glider) == stopped, "and, stopped, it stays for the rest of the hold")

	print("\n[B] A frozen enemy's glide stops at a player in its way")
	var runner := _enemy(Vector2(128, 512))
	await tree.physics_frame
	runner.current_direction = Vector2.RIGHT
	runner._update_sprite_direction()
	runner.velocity = Vector2.RIGHT * 256.0
	_player.global_position = _at(Vector2(448, 512))
	_player.is_invincible = true   # (so nothing that touches it matters)
	await _wait(1.2)
	var gap := _local(_player).x - _local(runner).x
	check(runner.velocity == Vector2.ZERO and gap >= 60.0 and gap < 65.0,
		"it stops short of the player (%.1f px apart, centre to centre)" % gap)

	print("\n[C] When the freeze ends, the enemies drive again")
	GameManager.enemies_frozen = false
	var before := _local(glider)
	await _wait(1.5)
	check(_local(glider) != before or _local(parked) != Vector2(320, 256), "the AI moves them on")
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	await _wait(0.1)

	print("\n[D] A player held while driving glides on, whatever the keys say")
	_player.is_invincible = false
	_player.global_position = _at(Vector2(640, 352))
	await _wait(0.1)
	Input.action_press("p1_right")
	await _wait(0.25)
	check(_player.velocity.x > 0.0, "driving right at %.0f px/s" % _player.velocity.x)
	GameManager.freeze_all_players(7.5)
	Input.action_release("p1_right")
	Input.action_press("p1_up")    # trying to turn
	Input.action_press("p1_shoot")
	var held_at := _local(_player)
	await _wait(0.3)
	var gliding := _local(_player)
	check(gliding.x > held_at.x + 20.0 and is_equal_approx(gliding.y, held_at.y)
		and _player.current_direction == Vector2.RIGHT,
		"held, it glides on right; Up does nothing (%.0f -> %.0f)" % [held_at.x, gliding.x])
	check(_player.active_bullets == 0, "nor does fire")
	await _wait(2.0)
	var rest := _local(_player)
	check(_player.velocity == Vector2.ZERO and absf(rest.x + 30.0 - wall_left) < 3.0 and is_equal_approx(rest.y, held_at.y),
		"stopped against the wall, in its lane (right edge %.0f)" % (rest.x + 30.0))
	await _wait(0.3)
	check(_local(_player) == rest, "and stays there")
	Input.action_release("p1_up")
	Input.action_release("p1_shoot")

	print("\n[E] Standing still when held, a player stays put; free again, it drives")
	GameManager.players_frozen = false
	_player.global_position = _at(Vector2(640, 640))
	_player.stop_moving()
	await _wait(0.1)
	GameManager.freeze_all_players(7.5)
	Input.action_press("p1_left")
	await _wait(0.3)
	Input.action_release("p1_left")
	check(_local(_player) == Vector2(640, 640), "held from a standstill: not an inch")
	GameManager.players_frozen = false
	Input.action_press("p1_left")
	await _wait(0.3)
	Input.action_release("p1_left")
	check(_local(_player).x < 620.0, "the hold over, Left drives it again")

	GameManager.enemies_frozen = false
	GameManager.players_frozen = false
	tree.root.remove_child(_game)
	_game.free()
	await tree.create_timer(0.5).timeout
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
