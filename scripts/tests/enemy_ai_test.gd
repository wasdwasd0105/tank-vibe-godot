extends Node
## Headless test for the enemies' moves, as Tank.exe's (docs/enemy_ai_original_spec.md):
## the way-to-the-base map (EnemyRoutes), the hunter's and the wanderer's
## choices, keeping to the grid, and Sean's case: a wall under the top with gaps
## only at its far ends, which the remake's old AI never got past. Run as an
## override main scene:
##   Godot --headless res://scenes/test/enemy_ai_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _routes: EnemyRoutes
var _player: PlayerTank

const BRICK := 0x19
const HARD_BRICK := 0x29
const SUPER := 0x3D

## The original's maps, digested (_digest), as its builder makes them for
## shipped stages: worked out with the research's model of it (distance_map.py).
## Stage 3 has both water and ice, so its three maps differ; stage 1's base is
## sealed in super steel.
const STAGE_DIGESTS := {
	1: [974446945, 745260356, 974446945],
	3: [1079380685, 1097873098, 505947901],
	20: [666983375, 576852830, 2091321187],
	48: [1083886979, 1464435997, 1083886979],
}
## Stage 3's normal map with tanks standing at map cells 10,5 and 20,20.
const STAGE3_TANKS_DIGEST := 2093321363
## Sean's case, the arena (_arena): super steel along row 6 and hard bricks along
## row 7, columns 4-35, gaps a tank wide or more at both ends; the base ringed in
## bricks, or sealed in super steel.
const ARENA_DIGEST := 1987686846
const SEALED_DIGEST := 790526318


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _frames(count: int = 1) -> void:
	for i in count:
		await get_tree().physics_frame


## The centre of a tank whose footprint's top-left is the field's tile [param tile].
func _spot(tile: Vector2i) -> Vector2:
	return _lm.global_position + Vector2(tile + Vector2i.ONE) * LevelManager.TILE_SIZE


func _enemy(tile: Vector2i, type_id: int = 1, moving: bool = false) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(moving)
	e.global_position = _spot(tile)
	e.is_materializing = false
	e._materialize_timer = 0.0
	e.visible = true
	e.max_health = 10
	e.health = 10
	return e


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await _frames(2)


func _put(cell: Vector2i, code: int) -> void:
	_lm._remove_fg_tile(cell)
	_lm._brick_damage.erase(cell)
	_lm._hard_brick_hp.erase(cell)
	_lm._place_fg_tile(cell, code)


func _clear_field() -> void:
	for cell in _lm._fg_tile_data.keys():
		_lm._remove_fg_tile(cell)
	_lm._brick_damage.clear()
	_lm._hard_brick_hp.clear()
	for cell in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(cell)


## Sean's case: super steel along row 6 and hard bricks along row 7 from column
## 4 to 35, open at both ends; the base ringed in [param ring].
func _arena(ring: int) -> void:
	_clear_field()
	for x in range(4, 36):
		_put(Vector2i(x, 6), SUPER)
		_put(Vector2i(x, 7), HARD_BRICK)
	for x in range(18, 22):
		_put(Vector2i(x, 27), ring)
	for y in [28, 29]:
		_put(Vector2i(18, y), ring)
		_put(Vector2i(21, y), ring)


func _digest(m: PackedInt32Array) -> int:
	var h := 0
	for v in m:
		h = (h * 31 + v) & 0x7FFFFFFF
	return h


func _build(mode: int = EnemyRoutes.Mode.NORMAL, tanks: Array[Vector2i] = []) -> PackedInt32Array:
	_routes.build(mode, tanks)
	return _routes.map_for(mode)


## How often [param e]'s hunter's choice at its spot comes out each way, of
## [param tries]: [up, right, down, left, stop].
func _hunt_counts(e: EnemyTank, tries: int) -> Array:
	var counts := [0, 0, 0, 0, 0]
	for i in tries:
		e._command = EnemyTank.STOP
		e._hunt(_routes, _routes.cell_of(e.global_position))
		counts[e._command] += 1
	return counts


## [param e]'s wanderer's picks from its spot, of [param tries], as a set of
## commands seen, with [param command] its last and [param moving] whether it
## moves.
func _wander_picks(e: EnemyTank, command: int, moving: bool, tries: int) -> Dictionary:
	var seen := {}
	for i in tries:
		e._command = command
		e._moving = moving
		e._wander(_routes.cell_of(e.global_position))
		seen[e._command] = int(seen.get(e._command, 0)) + 1
	return seen


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	seed(20261008)
	GameManager.set_map_pool("v1_2_2")
	GameManager.difficulty = 2
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	await tree.process_frame
	await tree.create_timer(0.3).timeout
	_lm = _game.get_level_manager()
	_routes = _lm.routes
	_routes.set_physics_process(false)  # no maps made on the clock till [J]
	_game.get_node("EnemySpawner").spawn_timer.stop()
	await _clear_enemies()
	for p in tree.get_nodes_in_group("players"):
		_player = p
	_player.global_position = _spot(Vector2i(36, 27))  # out of the way, bottom right
	_player.set_physics_process(false)
	_player.is_invincible = true
	_game.eagle.invincible = true

	print("\n[A] The map: the original's, value for value")
	for stage: int in STAGE_DIGESTS:
		_lm.load_stage(stage)
		var got := []
		for mode in 3:
			got.append(_digest(_build(mode)))
		check(got == STAGE_DIGESTS[stage], "stage %d's three maps (normal, anti-water, anti-ice): %s" % [stage, str(got)])
	_lm.load_stage(3)
	var two: Array[Vector2i] = [Vector2i(10, 5), Vector2i(20, 20)]
	check(_digest(_build(EnemyRoutes.Mode.NORMAL, two)) == STAGE3_TANKS_DIGEST, "and with two tanks standing in the way")
	_lm.load_stage(1)
	var sealed := _build()
	var reached := 0
	for x in range(1, EnemyRoutes.W - 1):
		for y in range(1, EnemyRoutes.H - 1):
			if sealed[x * EnemyRoutes.H + y] < EnemyRoutes.UNREACHED:
				reached += 1
	check(reached == 4, "stage 1, Tourist: its base sealed in super steel, nothing but the base reached (%d cells)" % reached)
	_arena(BRICK)
	check(_digest(_build()) == ARENA_DIGEST, "Sean's case, the base ringed in bricks")
	_arena(SUPER)
	check(_digest(_build()) == SEALED_DIGEST, "and sealed in super steel")

	print("\n[B] What a cell costs: on a line of fire 2/3 of it")
	var costs := []
	for row: Array in [[-1, -1], [24, -1], [28, -1], [40, -1], [44, -1], [56, -1], [60, -1], [-1, 4], [-1, 0]]:
		costs.append([EnemyRoutes.cost(row[0], row[1], false, EnemyRoutes.Mode.NORMAL),
				EnemyRoutes.cost(row[0], row[1], true, EnemyRoutes.Mode.NORMAL)])
	check(costs == [[3, 2], [8, 5], [6, 4], [16, 10], [3, 2], [4096, 2730], [100000, 100000], [6147, 4098], [15, 10]],
		"open 3, brick 8, what's left of one 6, hard brick 16 (3 once damaged), iron 4096, super steel 100000, water +6144, ice +12: %s" % str(costs))
	check(EnemyRoutes.cost(-1, 4, false, EnemyRoutes.Mode.AMPHI) == 3 and EnemyRoutes.cost(-1, 0, false, EnemyRoutes.Mode.ANTISKID) == 3,
		"water costs nothing more with anti-water, nor ice with anti-ice")

	print("\n[C] A hunter takes the cheapest way: round the wall through the nearer gap")
	_arena(BRICK)
	_build()
	var hunter := _enemy(Vector2i(9, 4))
	await _frames()
	var cases := [[Vector2i(9, 4), 3], [Vector2i(27, 4), 1], [Vector2i(2, 4), 2], [Vector2i(2, 9), 1], [Vector2i(36, 9), 3],
			[Vector2i(19, 27), 2]]
	var picked := []
	for c: Array in cases:
		hunter.global_position = _spot(c[0])
		var counts := _hunt_counts(hunter, 30)
		picked.append(counts.find(30))
	check(picked == cases.map(func(c: Array) -> int: return c[1]),
		"over the wall's left half it heads left, its right half right, down the gaps, then in to the base: %s" % str(picked))
	hunter.global_position = _spot(Vector2i(19, 4))
	var tie := _hunt_counts(hunter, 3000)
	check(tie[1] + tie[3] == 3000 and tie[3] > 850 and tie[3] < 1150,
		"over the middle, left and right equal: the later way taken 1 time in 3 (%d of 3000)" % tie[3])
	hunter.global_position = _lm.global_position + Vector2(20, 29) * LevelManager.TILE_SIZE
	check(_hunt_counts(hunter, 10)[EnemyTank.STOP] == 10, "on the base, nothing lower: it stops")
	_arena(SUPER)
	_build()
	hunter.global_position = _spot(Vector2i(9, 4))
	check(not hunter._hunt(_routes, _routes.cell_of(hunter.global_position)), "the base sealed: cut off, it wanders instead")

	print("\n[D] When a hunter decides: standing, or on the half cell before a grid line")
	_arena(BRICK)
	_build()
	var lines := []
	for c: Array in [[Vector2(0, 5.3), Vector2.UP, true], [Vector2(0, 5.7), Vector2.UP, false], [Vector2(0, 5.7), Vector2.DOWN, true],
			[Vector2(0, 5.3), Vector2.DOWN, false], [Vector2(5.4, 0), Vector2.LEFT, true], [Vector2(5.6, 0), Vector2.RIGHT, true],
			[Vector2(5.4, 0), Vector2.RIGHT, false], [Vector2(5.0, 0), Vector2.LEFT, true]]:
		hunter.global_position = _lm.global_position + (Vector2(10, 10) + c[0]) * LevelManager.TILE_SIZE
		hunter.current_direction = c[1]
		lines.append(hunter._at_line(_routes.cell_of(hunter.global_position)) == c[2])
	check(lines.all(func(ok: bool) -> bool: return ok), "going up at 5.3 tiles, yes; at 5.7, not yet; down, the other way round: %s" % str(lines))
	var halves := [EnemyRoutes.round_even(2.5), EnemyRoutes.round_even(3.5), EnemyRoutes.round_even(4.49), EnemyRoutes.round_even(4.51)]
	check(halves == [2, 4, 4, 5], "a tank's cell rounds as Delphi's Round: halves to the even one (%s)" % str(halves))
	hunter.global_position = _spot(Vector2i(9, 4)) + Vector2(20, 0)
	hunter.current_direction = Vector2.LEFT
	hunter._command = EnemyTank.STOP
	hunter._moving = true
	hunter._ai_step()
	var moving_kept := hunter._command == EnemyTank.STOP
	hunter._moving = false
	hunter._ai_step()
	check(moving_kept and hunter._command == 3, "between lines it keeps on; standing, it decides at once")

	print("\n[E] A wanderer's picks")
	_arena(SUPER)
	_build()
	var wanderer := hunter
	wanderer.hunts_base = false
	wanderer.global_position = _spot(Vector2i(19, 12))
	wanderer.current_direction = Vector2.DOWN
	var after_down := _wander_picks(wanderer, 2, false, 600)
	var after_up := _wander_picks(wanderer, 0, false, 600)
	var after_stop := _wander_picks(wanderer, EnemyTank.STOP, false, 600)
	check(not after_down.has(0) and after_down.has(1) and after_down.has(2) and after_down.has(3) and after_down.has(4),
		"after down: never back up; right, down, left or stop: %s" % str(after_down))
	check(after_up.has(2) and after_up.has(0), "after up: down too (only down may turn back): %s" % str(after_up))
	check(not after_stop.has(EnemyTank.STOP), "never stop twice: %s" % str(after_stop))
	wanderer.global_position = _spot(Vector2i(0, 0))
	var corner := _wander_picks(wanderer, 2, false, 600)
	check(not corner.has(0) and not corner.has(3), "in the top-left corner: never up or left: %s" % str(corner))
	wanderer.global_position = _spot(Vector2i(38, 28))
	var other := _wander_picks(wanderer, 0, false, 600)
	check(not other.has(1) and not other.has(2), "in the bottom-right corner: never right or down: %s" % str(other))
	wanderer.global_position = _spot(Vector2i(19, 12))
	wanderer.current_direction = Vector2.RIGHT
	var kept := _wander_picks(wanderer, 1, true, 7500)
	var turned: int = 7500 - int(kept.get(1, 0))
	var period := wanderer._turn_period()
	check(period == 75 and turned > 50 and turned < 105,
		"moving, it picks again 1 step in its turn period (75 for type 1 at medium): about 100 of 7500, %d" % turned)
	wanderer.global_position = _spot(Vector2i(0, 12))
	wanderer.current_direction = Vector2.LEFT
	var at_edge := _wander_picks(wanderer, 3, true, 200)
	check(not at_edge.has(3), "driving into the field's edge, it must pick again: %s" % str(at_edge))
	wanderer._hit_hold = EnemyTank.HIT_HOLD
	var held := _wander_picks(wanderer, 3, false, 50)
	wanderer._hit_hold = 0.0
	check(held.keys() == [3], "while a hit holds it: no pick")
	wanderer.queue_free()
	await _frames()

	print("\n[F] A hit holds its course; a shot turns it on the shooter")
	_arena(BRICK)
	_build()
	var struck := _enemy(Vector2i(9, 12))
	await _frames()
	struck._command = 2
	struck.take_damage(Vector2.RIGHT)  # the shooter is to its left
	var turned_on := struck._command
	struck._moving = false
	struck._ai_step()
	var held_course := struck._command == 3 and struck._hit_hold > 0.0
	struck._hit_hold = 0.0
	struck._ai_step()
	check(turned_on == 3 and held_course and struck.current_direction == Vector2.LEFT,
		"shot by a shell going right: it faces left, and decides nothing for a moment")
	check(struck._command == 1, "then it hunts on: right, its way to the base from there")
	struck.queue_free()
	await _frames()

	print("\n[G] On the grid: a moving enemy keeps to the line across its way")
	var drifting := _enemy(Vector2i(9, 12), 1, true)
	drifting.global_position += Vector2(13, 0)
	drifting._command = 2
	drifting._ai_clock = -99.0
	drifting._shoot_cooldown = 999.0
	await _frames(3)
	var across := drifting.global_position.x - _lm.global_position.x
	check(is_equal_approx(fmod(across, 32.0), 0.0) and drifting.global_position.y > _spot(Vector2i(9, 12)).y,
		"going down 13 px off the line: back on it (x %.1f), and on its way" % across)
	drifting.queue_free()
	await _frames()

	print("\n[H] Tanks standing in the way: higher ground, so others go round")
	_arena(BRICK)
	var plain := _build()
	var parked: Array[Vector2i] = [Vector2i(10, 5)]
	var with_tank := _build(EnemyRoutes.Mode.NORMAL, parked)
	var tank_cells := [with_tank[10 * 32 + 5], with_tank[11 * 32 + 5], with_tank[10 * 32 + 6], with_tank[11 * 32 + 6]]
	check(tank_cells == [131, 131, 134, 134] and plain[10 * 32 + 5] < 131,
		"a tank standing at map cell 10,5: its cells take the highest value round them (%s)" % str(tank_cells))
	var mover := _enemy(Vector2i(9, 4))
	await _frames()
	_routes._seen[mover.get_instance_id()] = [mover.global_position, 200.0]
	_routes.build(EnemyRoutes.Mode.NORMAL)
	var moving_map := _routes.map_for(EnemyRoutes.Mode.NORMAL)
	_routes._seen[mover.get_instance_id()] = [mover.global_position, 0.0]
	_routes.build(EnemyRoutes.Mode.NORMAL)
	var standing_map := _routes.map_for(EnemyRoutes.Mode.NORMAL)
	check(moving_map[10 * 32 + 5] == plain[10 * 32 + 5] and standing_map[10 * 32 + 5] == 131,
		"one on the move isn't in the way; standing, it is")
	mover.queue_free()
	await _frames()

	print("\n[I] When the maps are made: the normal one every 1.8 s, the others every 3.6 s")
	_routes.set_physics_process(false)
	_arena(BRICK)
	_routes.restart()
	var amphi_before := _routes.map_for(EnemyRoutes.Mode.AMPHI).duplicate()
	_put(Vector2i(2, 10), SUPER)  # changed after the build
	var normal_then := _routes.map_for(EnemyRoutes.Mode.NORMAL).duplicate()
	for i in 59:
		_routes._tick()
	var amphi_at_59 := _routes.map_for(EnemyRoutes.Mode.AMPHI) == amphi_before
	_routes._tick()
	var amphi_at_60 := _routes.map_for(EnemyRoutes.Mode.AMPHI) != amphi_before
	for i in 59:
		_routes._tick()
	var normal_at_119 := _routes.map_for(EnemyRoutes.Mode.NORMAL) == normal_then
	_routes._tick()
	var normal_at_120 := _routes.map_for(EnemyRoutes.Mode.NORMAL) != normal_then
	check(amphi_at_59 and amphi_at_60, "the anti-water map 0.9 s after the start (60 frames), not before")
	check(normal_at_119 and normal_at_120, "a wall changed: the normal map takes it at its next making, 1.8 s on, not before")

	print("\n[J] Sean's case, played: a wall under the top, gaps only at its ends")
	_routes.set_physics_process(true)
	Engine.time_scale = 4.0
	_arena(BRICK)
	_routes.restart()
	var starts := [Vector2i(8, 1), Vector2i(14, 1), Vector2i(24, 1), Vector2i(30, 1)]
	var hunters: Array[EnemyTank] = []
	for s: Vector2i in starts:
		var e := _enemy(s, 1, true)
		e._shoot_cooldown = 999.0
		hunters.append(e)
	var crossed := {}
	var off_grid := 0
	var waited := 0.0
	while waited < 25.0 and crossed.size() < hunters.size():
		await _frames()
		waited += get_physics_process_delta_time()  # (time_scale in it)
		for e: EnemyTank in hunters:
			var field := e.global_position - _lm.global_position
			if e._moving and e._command != EnemyTank.STOP:
				var cross := field.x if e.current_direction.y != 0.0 else field.y
				if not is_equal_approx(fmod(cross, 32.0), 0.0):
					off_grid += 1
			if field.y > 8.5 * 32.0 and not crossed.has(e):
				crossed[e] = field.x / 32.0  # where it passes the wall
	var sides := hunters.map(func(e: EnemyTank) -> String:
		return "-" if not crossed.has(e) else ("left" if crossed[e] < 6.0 else ("right" if crossed[e] > 34.0 else "middle")))
	check(sides == ["left", "left", "right", "right"],
		"hunters: all four through, each by its nearer gap, in %.0f s of play: %s" % [waited, str(sides)])
	check(off_grid == 0, "never off the grid line across their way while moving (%d times)" % off_grid)
	for e in hunters:
		e.queue_free()
	await _frames(2)
	_arena(SUPER)
	_routes.restart()
	var wanderers: Array[EnemyTank] = []
	for s: Vector2i in starts:
		var e := _enemy(s, 1, true)
		e._shoot_cooldown = 999.0
		wanderers.append(e)
	var down := {}
	waited = 0.0
	while waited < 90.0 and down.size() < 2:
		await _frames()
		waited += get_physics_process_delta_time()
		for e: EnemyTank in wanderers:
			if (e.global_position - _lm.global_position).y > 9.0 * 32.0:
				down[e] = true
	check(down.size() >= 2, "the base sealed, so they wander: still, through the end gaps (%d of 4 in %.0f s)" % [down.size(), waited])
	Engine.time_scale = 1.0
	for e in wanderers:
		e.queue_free()
	await _frames(2)

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
