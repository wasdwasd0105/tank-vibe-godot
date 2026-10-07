extends Node
## Headless test for the players' grid, as Tank.exe's (docs/enemy_ai_original_spec.md
## section 9): a moving tank keeps to the grid line across its way, the field's
## tiles, rounded as Delphi rounds, every frame. So a player turning within half
## a tile of a gap a tank wide lines up with it and drives through at once.
## Run as an override main scene:
##   Godot --headless res://scenes/test/tunnel_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank

const IRON := 0x39
const ICE := 0x01
const T := LevelManager.TILE_SIZE


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _clear_field() -> void:
	for cell in _lm._fg_tile_data.keys():
		_lm._remove_fg_tile(cell)
	_lm._brick_damage.clear()
	_lm._hard_brick_hp.clear()
	for cell in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(cell)


## The player at field position [param field] (its centre), facing [param facing].
func _set_player(field: Vector2, facing: Vector2) -> void:
	_player.global_position = _lm.global_position + field
	_player.current_direction = facing
	_player._update_sprite_direction()
	_player.velocity = Vector2.ZERO
	_player.ice_speed = 0.0
	_player.has_anti_ice = false


## Its centre, in the field.
func _field() -> Vector2:
	return _player.global_position - _lm.global_position


## Drives the player with [param dir] held for [param frames] physics frames.
func _hold(dir: Vector2, frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		_player._drive(dir)


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
	_player.move_speed = 192.0  # its top speed, to keep the test short
	_clear_field()
	await _hold(Vector2.ZERO, 2)

	print("\n[A] A turn lines it up with the nearest grid line across its new way, rounded as Delphi rounds")
	var lands := []
	for x: float in [10 * T + 10, 10 * T + 17, 10 * T + 16, 11 * T + 16, 10 * T - 15]:
		_set_player(Vector2(x, 17 * T), Vector2.RIGHT)
		await _hold(Vector2.UP, 1)
		lands.append(_field().x)
	var want := [10 * T, 11 * T, 10 * T, 12 * T, 10 * T]
	var ok := true
	for i in want.size():
		ok = ok and absf(lands[i] - want[i]) < 0.01
	check(ok, "from 10 and 17 px past a line, to the nearer; half way, to the even one: %s" % str(lands))
	_set_player(Vector2(17 * T, 9 * T + 11), Vector2.UP)
	await _hold(Vector2.RIGHT, 1)
	check(absf(_field().y - 9 * T) < 0.01, "across a way right too, on the field's own lines (y %.1f)" % _field().y)

	print("\n[B] A tunnel a tank wide: a turn within half a tile of it drives straight in")
	_clear_field()
	for y in range(4, 14):
		_lm._place_fg_tile(Vector2i(9, y), IRON)
		_lm._place_fg_tile(Vector2i(12, y), IRON)
	await _hold(Vector2.ZERO, 2)
	# The tunnel is tiles 10-11: a tank in it has its centre on x = 11 tiles.
	var through := []
	var blocked := []
	for off: float in [-15.0, -12.0, -9.0, -5.0, 0.0, 5.0, 9.0, 12.0, 15.0]:
		_set_player(Vector2(11 * T + off, 15 * T), Vector2.RIGHT)
		await _hold(Vector2.UP, 150)  # 2.5 s: 11 tiles to go
		if _field().y < 4 * T:
			through.append(off)
		else:
			blocked.append(off)
	check(blocked.is_empty(), "from up to 15 px either side, all through it at the first go (blocked from %s)" % str(blocked))
	var past := []
	for off: float in [-17.0, 17.0]:
		_set_player(Vector2(11 * T + off, 15 * T), Vector2.RIGHT)
		await _hold(Vector2.UP, 90)
		past.append(_field().y > 13 * T)
	check(past == [true, true], "more than half a tile off, it lines up with the next line, against the wall")

	print("\n[C] Every moving frame, not only a turn: one set down off its line takes it as it drives")
	_set_player(Vector2(11 * T + 6, 17 * T), Vector2.UP)
	await _hold(Vector2.UP, 1)
	check(absf(_field().x - 11 * T) < 0.01, "6 px off, driving on the way it faces: on its line at once (x %.1f)" % _field().x)
	_set_player(Vector2(11 * T + 6, 17 * T), Vector2.UP)
	await _hold(Vector2.ZERO, 3)
	check(absf(_field().x - (11 * T + 6)) < 0.01, "standing, it stays where it is")

	print("\n[D] On ice: it turns onto its line once slow enough")
	_clear_field()
	for x in range(2, 30):
		for y in range(14, 20):
			_lm._place_bg_tile(Vector2i(x, y), ICE)
	_set_player(Vector2(11 * T + 4, 17 * T), Vector2.RIGHT)
	_player.ice_speed = 192.0
	_player.velocity = Vector2.RIGHT * 192.0
	await _hold(Vector2.UP, 120)
	check(_player.current_direction == Vector2.UP and fmod(_field().x, T) < 0.01 and _field().x > 11 * T,
		"slid on, turned up, and on a tile line, not half way (x %.1f)" % _field().x)

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
