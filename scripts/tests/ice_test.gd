extends Node
## Headless test for tanks on ice, as Tank.exe's (docs/ice_original_spec.md):
## on ice a tank answers its controls 8 times slower. Released, it slides on and
## stops; told another way, it slides on braking till it's slow enough to turn,
## then gathers speed slowly; anti-ice tanks answer at once, as everywhere off
## ice. Enemies too. Run as an override main scene:
##   Godot --headless res://scenes/test/ice_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank

const ICE := 0x01
const IRON := 0x39
## The player's top speed here (speed level 1).
const TOP := 128.0


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


## The centre of a tank whose footprint's top-left is the field's tile [param tile].
func _spot(tile: Vector2i) -> Vector2:
	return _lm.global_position + Vector2(tile + Vector2i.ONE) * LevelManager.TILE_SIZE


func _clear_field() -> void:
	for cell in _lm._fg_tile_data.keys():
		_lm._remove_fg_tile(cell)
	_lm._brick_damage.clear()
	_lm._hard_brick_hp.clear()
	for cell in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(cell)


## Ice over tiles [param from] to [param to], both included.
func _ice(from: Vector2i, to: Vector2i) -> void:
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			_lm._place_bg_tile(Vector2i(x, y), ICE)


## The player standing at [param tile], facing [param facing], at [param speed].
func _set_player(tile: Vector2i, facing: Vector2, speed: float = 0.0) -> void:
	_player.global_position = _spot(tile)
	_player.current_direction = facing
	_player._update_sprite_direction()
	_player.ice_speed = speed
	_player.velocity = facing * speed
	_player.has_anti_ice = false


## Drives the player with [param dir] held for [param frames] physics frames.
func _hold(dir: Vector2, frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		_player._drive(dir)


## Drives the player with nothing held till it stands, at most [param limit]
## frames: [distance, frames].
func _coast(limit: int = 300) -> Array:
	var from := _player.global_position
	var frames := 0
	while frames < limit:
		await get_tree().physics_frame
		_player._drive(Vector2.ZERO)
		frames += 1
		if _player.velocity == Vector2.ZERO:
			break
	return [_player.global_position.distance_to(from), frames]


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	await tree.process_frame
	await tree.create_timer(0.3).timeout
	_lm = _game.get_level_manager()
	_game.get_node("EnemySpawner").spawn_timer.stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	for p in tree.get_nodes_in_group("players"):
		_player = p
	while _player.is_materializing:
		await tree.process_frame
	_player.set_physics_process(false)  # driven by hand here
	_player.is_invincible = true
	_player.move_speed = TOP
	_clear_field()
	_ice(Vector2i(2, 4), Vector2i(37, 20))
	var dt := 1.0 / Engine.physics_ticks_per_second

	print("\n[A] On ice: two or more of the four tiles under it")
	var on := []
	for c: Array in [[Vector2i(1, 4), true], [Vector2i(0, 4), false], [Vector2i(1, 3), false], [Vector2i(2, 3), true], [Vector2i(10, 10), true]]:
		_set_player(c[0], Vector2.RIGHT)
		_player._drive(Vector2.ZERO)
		on.append(_player.is_on_ice == c[1])
	check(on.all(func(ok: bool) -> bool: return ok), "half over ice, it's on it; a quarter, it isn't: %s" % str(on))
	_set_player(Vector2i(10, 10), Vector2.RIGHT)
	_player.has_anti_ice = true
	_player._drive(Vector2.ZERO)
	check(not _player.is_on_ice, "anti-ice: never")
	_player.has_anti_ice = false

	print("\n[B] Let go at full speed on ice, it slides on and stops")
	_set_player(Vector2i(6, 10), Vector2.RIGHT, TOP)
	var coasted := await _coast()
	var stop_time: float = coasted[1] * dt
	# Braking by 2/8 of 60/650 of its top speed every 0.03 s: 1.3 s, 83 px from 128 px/s.
	check(coasted[0] > 70.0 and coasted[0] < 95.0 and stop_time > 1.15 and stop_time < 1.45,
		"from 128 px/s: %.0f px in %.2f s (the original: 1.3 s, 0.65 s at its top speed)" % [coasted[0], stop_time])
	_set_player(Vector2i(6, 24), Vector2.RIGHT, TOP)  # off the ice
	var dry := await _coast()
	check(dry[0] < 3.0, "off ice it stops at once, as the remake's tanks do (%.1f px)" % dry[0])

	print("\n[C] Told another way on ice: it slides on braking, turns when slow, then gathers speed slowly")
	_set_player(Vector2i(6, 10), Vector2.RIGHT, TOP)
	var start := _player.global_position
	var turned_at := -1
	var right_by := 0.0
	for i in 120:
		await tree.physics_frame
		_player._drive(Vector2.DOWN)
		if _player.current_direction == Vector2.DOWN:
			turned_at = i
			right_by = _player.global_position.x - start.x
			break
	var turn_time := (turned_at + 1) * dt
	# Down from 128 to the original's 200 (53.3 px/s) at 98.5 px/s a second: 0.76 s, 69 px on.
	check(turned_at > 0 and turn_time > 0.65 and turn_time < 0.9 and right_by > 55.0 and right_by < 80.0,
		"it slid on %.0f px the way it went, and turned after %.2f s" % [right_by, turn_time])
	await _hold(Vector2.DOWN, 60)
	var speed_after_1s := _player.velocity.length()
	# From next to nothing, gaining 49.2 px/s a second.
	check(_player.current_direction == Vector2.DOWN and speed_after_1s > 40.0 and speed_after_1s < 60.0,
		"then a slow start: %.0f px/s a second after the turn (full speed 128)" % speed_after_1s)
	await _hold(Vector2.DOWN, 150)
	check(is_equal_approx(_player.velocity.length(), TOP), "in time, full speed (%.0f)" % _player.velocity.length())

	print("\n[D] From standing on ice")
	_set_player(Vector2i(6, 10), Vector2.RIGHT, 0.0)
	await _hold(Vector2.RIGHT, 30)
	var same_way := _player.velocity.length()
	_set_player(Vector2i(6, 10), Vector2.RIGHT, 0.0)
	await _hold(Vector2.DOWN, 1)
	var new_way := _player.velocity.length()
	check(same_way > 20.0 and same_way < 30.0, "the way it faces: from nothing, 8 times slower (%.1f px/s after 0.5 s)" % same_way)
	check(_player.current_direction == Vector2.DOWN and new_way > 50.0 and new_way < 58.0,
		"another way: it turns at once, off at the original's 200 (%.1f px/s)" % new_way)

	print("\n[E] Against a wall on ice it stops dead: no speed kept for when it's gone")
	_set_player(Vector2i(6, 10), Vector2.RIGHT, TOP)
	for y in [10, 11]:
		_lm._place_fg_tile(Vector2i(9, y), IRON)
	await _hold(Vector2.RIGHT, 60)
	var kept := _player.ice_speed
	for y in [10, 11]:
		_lm._remove_fg_tile(Vector2i(9, y))
	await _hold(Vector2.RIGHT, 1)
	check(kept < 2.0 and _player.velocity.length() < 5.0,
		"pushing at the wall, a step's speed at most (%.1f px/s); a frame after it's gone, still next to nothing (%.1f)" % [kept, _player.velocity.length()])

	print("\n[F] Anti-ice: on ice as off it")
	_set_player(Vector2i(6, 10), Vector2.RIGHT, 0.0)
	_player.has_anti_ice = true
	await _hold(Vector2.DOWN, 1)
	var at_once := _player.velocity
	var slid := await _coast()
	_player.has_anti_ice = false
	check(at_once == Vector2.DOWN * TOP and slid[0] < 3.0, "full speed at once (%s), and it stops at once (%.1f px)" % [at_once, slid[0]])

	print("\n[H] Driven onto ice, it goes on at the speed it had")
	_set_player(Vector2i(10, 22), Vector2.UP, 0.0)  # below the ice, which ends at row 20
	var entered := -1
	for i in 90:
		await tree.physics_frame
		_player._drive(Vector2.UP)
		if _player.is_on_ice:
			entered = i
			break
	check(entered > 0 and _player.velocity.length() > TOP * 0.95,
		"onto the ice after %d frames at full speed: %.0f px/s on it" % [entered, _player.velocity.length()])
	var onto := await _coast()
	check(onto[0] > 70.0, "and let go there, it slides on (%.0f px)" % onto[0])

	print("\n[G] Enemies slide on ice too")
	var enemy: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	enemy.tank_type_id = 1
	_game.get_node("Entities/Enemies").add_child(enemy)
	enemy.is_materializing = false
	enemy._materialize_timer = 0.0
	enemy.global_position = _spot(Vector2i(6, 14))
	enemy._ai_clock = -99.0  # no AI steps: its commands are set here
	enemy._shoot_cooldown = 999.0
	enemy._command = 1
	enemy.current_direction = Vector2.RIGHT
	enemy.ice_speed = enemy.move_speed
	await tree.physics_frame
	await tree.physics_frame
	var e_from := enemy.global_position
	enemy._command = EnemyTank.STOP
	var e_frames := 0
	while e_frames < 200:
		await tree.physics_frame
		e_frames += 1
		if enemy.velocity == Vector2.ZERO:
			break
	var e_slide := enemy.global_position.distance_to(e_from)
	# 64 px/s, braking at 49.2 px/s a second: 1.3 s, 42 px.
	check(e_slide > 34.0 and e_slide < 50.0 and e_frames * dt > 1.15,
		"told to stop at 64 px/s, it slid %.0f px in %.2f s" % [e_slide, e_frames * dt])
	enemy._command = 2
	enemy.ice_speed = 0.0
	enemy.current_direction = Vector2.RIGHT
	enemy.global_position += Vector2(13, 0)  # off its grid line
	await tree.physics_frame
	await tree.physics_frame
	var across := fmod(enemy.global_position.x - _lm.global_position.x, 32.0)
	check(enemy.current_direction == Vector2.DOWN and is_equal_approx(across, 0.0),
		"standing, told down: it turns at once, onto its grid line (x off by %.1f)" % across)
	enemy.queue_free()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
