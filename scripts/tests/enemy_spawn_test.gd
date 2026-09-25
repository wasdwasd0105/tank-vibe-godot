extends Node
## Headless test for where, when and which enemies come in, as Tank.exe sent
## them (docs/enemy_spawn_original_spec.md): each on a random tank-sized spot
## along the top of the field with no wall or water on it (grass and ice are
## fine), never on another tank, and no wall broken for it; in waves of one to
## four tries, 0.9375 s a try apart, a try refused while the field is full or
## none are left; each a random one of the types still to come, whatever their
## numbers.
## Run as an override main scene:
##   Godot --headless res://scenes/test/enemy_spawn_test.tscn

var _fail := 0
var _game: Node
var _spawner: EnemySpawner
var _lm: LevelManager


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


## The spot (its top-left tile) an enemy came in on.
func _spot_of(enemy: Node2D) -> Vector2i:
	return _lm.world_to_tile(enemy.global_position) - Vector2i(1, 1)


func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(
		func(e: Node) -> bool: return not e.is_queued_for_deletion())


## Takes every enemy off the field, their count with them.
func _clear() -> void:
	for e in _enemies():
		e.queue_free()
	await get_tree().process_frame


## Sends [param n] enemies in one at a time, each taken off again before the
## next: {spot: how many came there}. Unmet tries count under NO_SPOT. One is
## always left to come, so the stage never counts as won.
func _spots_used(n: int) -> Dictionary:
	var seen := {}
	for i in n:
		_spawner._spawn_queue = [1, 1]
		var spot := EnemySpawner.NO_SPOT
		if _spawner._spawn_enemy():
			var e: Node2D = _enemies()[0]
			spot = _spot_of(e)
			e.queue_free()
		seen[spot] = seen.get(spot, 0) + 1
	await get_tree().process_frame
	return seen


## The walls along the top two rows: {tile: code}.
func _top_walls() -> Dictionary:
	var walls := {}
	for tile: Vector2i in _lm._fg_tile_data:
		if tile.y <= 1:
			walls[tile] = _lm._fg_tile_data[tile].get("code", 0)
	return walls


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.difficulty = 2
	GameManager.player_active = [true, false]
	GameManager.player_disabled = [false, false]
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	await tree.process_frame
	_spawner = _game.enemy_spawner
	_lm = _game.level_manager

	print("\n[A] Play starts: the first wave 3 s in, as the original's 4000 ticks")
	check(_enemies().is_empty() and is_equal_approx(_spawner.spawn_timer.wait_time, 3.0)
		and not _spawner.spawn_timer.is_stopped(),
		"no enemy yet, the first wave set for 3 s (%.2f)" % _spawner.spawn_timer.wait_time)
	check(_spawner.get_children().filter(func(c: Node) -> bool: return c is Marker2D).is_empty(),
		"no fixed spawn points left in the scene")
	_spawner.halt()
	# Room for every try below; the ones taken off leave at the frame's end.
	_spawner.max_concurrent_enemies = 100000
	for p in tree.get_nodes_in_group("players"):
		p.queue_free()  # out of the way of the spots; [D] brings a tank back
	await tree.process_frame

	print("\n[B] Stage 1, Tourist: in between its bricks along the top, never through them")
	var open := [3, 7, 11, 15, 19, 23, 27, 31, 35]
	for col in LevelManager.GRID_WIDTH - 1:
		if _lm.is_open_ground(Vector2i(col, 0), EnemySpawner.SPOT_SIZE) != (col in open):
			check(false, "spot %d is %s" % [col, "open" if col not in open else "walled"])
	var walls := _top_walls()
	var seen := await _spots_used(360)
	var cols: Array = seen.keys().map(func(s: Vector2i) -> int: return s.x)
	cols.sort()
	check(cols == open, "the enemies came in on all 9 open spots and no others: %s" % str(cols))
	check(seen.keys().all(func(s: Vector2i) -> bool: return s.y == 0), "each with its top on the field's top row")
	check(seen.values().all(func(n: int) -> bool: return n >= 20),
		"about evenly, 40 each on average: %s" % str(seen.values()))
	check(_top_walls() == walls, "no brick broken for them (%d along the top)" % walls.size())

	print("\n[C] Stage 50, X: walled along the top but for its two corners")
	_lm.load_stage(50)
	walls = _top_walls()
	seen = await _spots_used(80)
	cols = seen.keys().map(func(s: Vector2i) -> int: return s.x)
	cols.sort()
	check(cols == [0, 38], "only in the corners: %s" % str(cols))
	check(_top_walls() == walls, "the wall between them kept whole")

	print("\n[D] Never on a tank: one on the field, one still appearing, one in a wave")
	_lm.load_stage(2)  # open all along the top
	var sitter: Node2D = load("res://scenes/tanks/player_tank.tscn").instantiate()
	sitter.player_id = 0
	_game.players_container.add_child(sitter)
	sitter.global_position = _lm.tile_to_world(Vector2i(10, 0)) + Vector2(16, 16)
	seen = await _spots_used(300)
	var near := seen.keys().filter(func(s: Vector2i) -> bool: return absi(s.x - 10) <= 1 and s.y == 0)
	check(near.is_empty() and seen.size() >= 30,
		"a player on spot 10: never on 9, 10 or 11, the rest all used (%d spots)" % seen.size())
	sitter.queue_free()
	await tree.process_frame
	_lm.load_stage(50)
	_spawner._spawn_queue = [1, 1, 1, 1]
	var sent := 0
	for i in 4:
		if _spawner._spawn_enemy():
			sent += 1
	var both: Array = _enemies().map(func(e: Node2D) -> int: return _spot_of(e).x)
	both.sort()
	check(sent == 2 and both == [0, 38] and _enemies().all(func(e: EnemyTank) -> bool: return e.is_materializing),
		"X, four tries at once: one in each corner while they appear, the other two refused (%s)" % str(both))
	check(_spawner._spawn_queue.size() == 2, "the refused two still to come")
	await _clear()

	print("\n[E] Water is no spot; ice and grass are")
	_lm.load_stage(2)
	for col in LevelManager.GRID_WIDTH:
		for row in 2:
			var tile := Vector2i(col, row)
			_lm._remove_fg_tile(tile)
			_lm._remove_bg_tile(tile)
			if col < 20:
				_lm._place_bg_tile(tile, 0x05)  # water
			elif col < 30:
				_lm._place_bg_tile(tile, 0x01)  # ice
			else:
				_lm._place_fg_tile(tile, 0x09)  # grass
	seen = await _spots_used(300)
	cols = seen.keys().map(func(s: Vector2i) -> int: return s.x)
	check(cols.all(func(c: int) -> bool: return c >= 20) and cols.size() == 19,
		"water on columns 0-19: none there, and all of 20-38 on ice and grass (%d spots)" % cols.size())

	print("\n[F] A top walled all along, which hung the original: a spot is cleared")
	_lm.load_stage(50)
	for col in LevelManager.GRID_WIDTH:
		for row in 2:
			_lm._remove_fg_tile(Vector2i(col, row))
			_lm._place_fg_tile(Vector2i(col, row), 0x39)  # iron
	_spawner._spawn_queue = [1, 1]
	check(_spawner._spawn_enemy(), "an enemy still comes in")
	var cleared: Vector2i = _spot_of(_enemies()[0])
	check(_lm.is_open_ground(cleared, EnemySpawner.SPOT_SIZE) and cleared.y == 0,
		"on a top-row spot cleared for it (%s)" % str(cleared))
	await _clear()

	print("\n[G] Waves: one to four tries, then 0.9375 s for each")
	_lm.load_stage(2)
	await tree.process_frame
	var sizes := {}
	var gaps_match := true
	for i in 200:
		_spawner._spawn_queue = [1, 1, 1, 1, 1, 1]
		_spawner._send_wave()
		var came := _enemies().size()
		sizes[came] = sizes.get(came, 0) + 1
		gaps_match = gaps_match and is_equal_approx(_spawner.spawn_timer.wait_time, came * 0.9375) \
			and not _spawner.spawn_timer.is_stopped()
		_spawner.spawn_timer.stop()  # these waves are the test's own
		await _clear()
	var counts: Array = sizes.keys()
	counts.sort()
	check(counts == [1, 2, 3, 4] and sizes.values().all(func(n: int) -> bool: return n >= 25),
		"1, 2, 3 or 4 at once, about equally often: %s" % str(sizes))
	check(gaps_match, "the next wave k × 0.9375 s later when all k tries came, the timer on for it")

	print("\n[H] A try refused ends the wave; the wait is still the tries'")
	_spawner.max_concurrent_enemies = 2
	var capped := true
	var long_wait := false
	for i in 120:
		_spawner._spawn_queue = [1, 1, 1, 1, 1, 1]
		_spawner._send_wave()
		_spawner.spawn_timer.stop()
		var tries := roundi(_spawner.spawn_timer.wait_time / 0.9375)
		capped = capped and _enemies().size() == mini(tries, 2)
		long_wait = long_wait or (tries == 4 and _enemies().size() == 2)
		await _clear()
	check(capped, "a limit of 2 on the field: never more, however many tries")
	check(long_wait, "four tries, two in: the next wave still 3.75 s away")
	_spawner.max_concurrent_enemies = 99
	_spawner._spawn_queue.clear()
	_spawner._send_wave()
	check(_enemies().is_empty() and not _spawner.spawn_timer.is_stopped(),
		"none left to come: nothing, but the waves go on for any that join")
	_spawner.halt()

	print("\n[I] Which type: any still to come, as likely as any other")
	var picks := {}
	for i in 600:
		_spawner._spawn_queue = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 5]
		var picked := _spawner._take_type()
		picks[picked] = picks.get(picked, 0) + 1
	check(picks.get(5, 0) > 240 and picks.get(5, 0) < 360,
		"nineteen of type 1 and one of type 5: type 5 first half the time, not 1 in 20 (%d of 600)" % picks.get(5, 0))
	_spawner._spawn_queue = [3, 3, 7]
	var taken := _spawner._take_type()
	var left := _spawner._spawn_queue.duplicate()
	left.sort()
	check((taken == 3 and left == [3, 7]) or (taken == 7 and left == [3, 3]),
		"one of its type taken off the queue (%d, leaving %s)" % [taken, str(left)])

	tree.root.remove_child(_game)
	_game.free()
	await tree.create_timer(0.8).timeout  # let the sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
