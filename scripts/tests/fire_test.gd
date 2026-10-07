extends Node
## Headless test for the fire weapon and ground fire, as Tank.exe's
## (docs/fire_weapon_original_spec.md): the shell, its patch, fuel by level,
## feeding and spreading, burning tanks, grass and ice. Run as an override main
## scene:
##   Godot --headless res://scenes/test/fire_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank

const BRICK := 0x19
const HARD_BRICK := 0x29
const IRON := 0x39
const SUPER := 0x3D
const GRASS := 0x09
const WATER := 0x05
const ICE := 0x01
## The patch round its anchor: a 4x4 from one up-left, less its corners.
const PATCH: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(2, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2)]
const INNER: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _frames(count: int = 1) -> void:
	for i in count:
		await get_tree().physics_frame


func _clear_field() -> void:
	_lm._clear_fire()
	for cell in _lm._fg_tile_data.keys():
		_lm._remove_fg_tile(cell)
	_lm._brick_damage.clear()
	_lm._hard_brick_hp.clear()
	for cell in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(cell)


func _put(cell: Vector2i, code: int) -> void:
	_lm._remove_fg_tile(cell)
	_lm._brick_damage.erase(cell)
	_lm._hard_brick_hp.erase(cell)
	_lm._place_fg_tile(cell, code)


## The fires of [param side] on [param cell].
func _fires(cell: Vector2i, side: int = 1) -> Array:
	return _lm.fires_at(cell).filter(func(f: GroundFire) -> bool: return f.side == side)


## The first fire of [param side] on [param cell], or null.
func _first(cell: Vector2i, side: int = 1) -> GroundFire:
	var list := _fires(cell, side)
	return list[0] if not list.is_empty() else null


## Whether the first fire of its side on [param cell] is armed (false if none).
func _armed(cell: Vector2i) -> bool:
	var fire := _first(cell)
	return fire != null and fire.is_armed()


## The fuel of the first fire of its side on [param cell], -1 if none.
func _fuel(cell: Vector2i) -> float:
	var fire := _first(cell)
	return fire.fuel if fire else -1.0


## The centre of a tank whose footprint's top-left is the field's tile [param tile].
func _spot(tile: Vector2i) -> Vector2:
	return _lm.global_position + Vector2(tile + Vector2i.ONE) * LevelManager.TILE_SIZE


func _enemy(tile: Vector2i, hp: int = 10) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _spot(tile)
	e.is_materializing = false
	e._materialize_timer = 0.0
	e.visible = true
	e.max_health = hp
	e.health = hp
	return e


## How many points [param tank] loses standing still for [param seconds].
func _burned(tank: BaseTank, seconds: float) -> int:
	var hp := tank.health
	await get_tree().create_timer(seconds).timeout
	return hp - tank.health


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	seed(20261008)
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	await tree.process_frame
	await tree.create_timer(0.3).timeout
	_lm = _game.get_level_manager()
	_game.get_node("EnemySpawner").halt()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	for p in tree.get_nodes_in_group("players"):
		_player = p
	_player.set_physics_process(false)
	_player.global_position = _spot(Vector2i(37, 27))  # out of the way
	_player.is_invincible = true
	_game.eagle.invincible = true
	_clear_field()
	await _frames(2)

	print("\n[A] The patch: 12 tiles round where the shell dropped, the middle four alight first")
	var anchor := Vector2i(10, 8)
	_lm.ignite_fire_patch(anchor, true, 0, 0)
	var laid := []
	for dy in range(-1, 3):
		for dx in range(-1, 3):
			laid.append(_fires(anchor + Vector2i(dx, dy)).size())
	var expected := []
	for dy in range(-1, 3):
		for dx in range(-1, 3):
			expected.append(1 if Vector2i(dx, dy) in PATCH else 0)
	check(laid == expected, "4x4 from one up-left of it, less the corners: %s" % str(laid))
	await _frames(5)  # its 4th frame (one more is under way)
	var inner_armed := INNER.all(func(o: Vector2i) -> bool: return _armed(anchor + o))
	var outer_armed := PATCH.filter(func(o: Vector2i) -> bool: return not o in INNER).any(
			func(o: Vector2i) -> bool: return _armed(anchor + o))
	check(inner_armed and not outer_armed, "4 frames on, the middle 2x2 burns, the rest not yet")
	await _frames(2)
	check(PATCH.all(func(o: Vector2i) -> bool: return _armed(anchor + o)), "6 frames on, all of it")
	var shell_at := _lm.global_position + Vector2(20 * 32 + 3, 14 * 32 + 20)
	check(_lm.fire_anchor(shell_at) == Vector2i(19, 14), "a shell's patch goes round the cell under its top-left corner")
	_lm._clear_fire()

	print("\n[B] Where fire lies: open ground, grass, water, ice and half a brick; no walls")
	var cells := {Vector2i(4, 4): BRICK, Vector2i(5, 4): HARD_BRICK, Vector2i(6, 4): IRON, Vector2i(7, 4): SUPER, Vector2i(8, 4): GRASS}
	for cell: Vector2i in cells:
		_put(cell, cells[cell])
	_put(Vector2i(9, 4), BRICK)
	_lm._brick_damage[Vector2i(9, 4)] = 0b0011  # half a brick
	_put(Vector2i(10, 4), BRICK)
	_lm._brick_damage[Vector2i(10, 4)] = 0b0001  # a quarter
	_lm._place_bg_tile(Vector2i(11, 4), WATER)
	_lm._place_bg_tile(Vector2i(12, 4), ICE)
	var lies := []
	for x in range(4, 14):
		lies.append(_lm.fire_can_lie(Vector2i(x, 4)))
	check(lies == [false, false, false, false, true, true, false, true, true, true],
		"brick, hard brick, iron, super steel no; grass, half a brick yes; a quarter no; water, ice, open ground yes: %s" % str(lies))
	_clear_field()

	print("\n[C] Fuel by level: a level 1 patch burns 1.3-1.7 s, a level 4 one 4.7-5.1 s")
	_lm.ignite_fire_patch(Vector2i(10, 8), true, 0, 0)
	_lm.ignite_fire_patch(Vector2i(20, 8), true, 0, 3)
	var weak: Array = PATCH.map(func(o: Vector2i) -> float: return _fuel(Vector2i(10, 8) + o))
	var strong: Array = PATCH.map(func(o: Vector2i) -> float: return _fuel(Vector2i(20, 8) + o))
	check(weak.min() >= 1750.0 and weak.max() <= 2249.0 and strong.min() >= 6250.0 and strong.max() <= 6749.0,
		"fuel 1750-2249 ticks, 1500 more a level (%d-%d, %d-%d)" % [weak.min(), weak.max(), strong.min(), strong.max()])
	await tree.create_timer(1.25).timeout
	var still := PATCH.filter(func(o: Vector2i) -> bool: return not _fires(Vector2i(10, 8) + o).is_empty()).size()
	await tree.create_timer(0.55).timeout
	var after := PATCH.filter(func(o: Vector2i) -> bool: return not _fires(Vector2i(10, 8) + o).is_empty()).size()
	var strong_left := PATCH.filter(func(o: Vector2i) -> bool: return not _fires(Vector2i(20, 8) + o).is_empty()).size()
	check(still == 12 and after == 0 and strong_left == 12, "level 1: all 12 at 1.25 s, none at 1.8 s, while level 4 burns on")
	_lm._clear_fire()

	print("\n[D] Another shell of its side feeds the fire; the other side's burns beside it")
	_lm.ignite_fire_patch(Vector2i(10, 8), true, 0, 3)
	var first := _first(Vector2i(10, 8))
	var before := _fuel(Vector2i(10, 8))
	_lm.ignite_fire_patch(Vector2i(10, 8), true, 0, 3)
	var fed := _fuel(Vector2i(10, 8)) - before
	# Fresh 6250-6749, boost = fresh * 6 / 9 = 4166-4499, added as it's below what it had.
	check(_fires(Vector2i(10, 8)).size() == 1 and fed >= 4166.0 and fed <= 4500.0,
		"the same fire, fed %d ticks: fresh * (level + 3) / 9" % fed)
	_lm.ignite_fire_patch(Vector2i(10, 8), true, 1, 0)
	check(first != null and first.strength == 0 and first.owner_id == 1, "a level 1 shell lowers its strength; its owner is the newest shooter's")
	_lm.ignite_fire_patch(Vector2i(10, 8), false, -1, 0)
	check(_fires(Vector2i(10, 8)).size() == 1 and _fires(Vector2i(10, 8), 0).size() == 1,
		"the enemies' shell lays its own fire on the same tile")
	_lm._clear_fire()

	print("\n[E] A big fire spreads: fed level 4 fire pushes a ring out; water and walls stop it")
	_lm._place_bg_tile(Vector2i(14, 8), WATER)
	_put(Vector2i(14, 9), BRICK)
	_lm.ignite_fire_patch(Vector2i(11, 8), true, 0, 3)
	_lm.ignite_fire_patch(Vector2i(11, 8), true, 0, 3)
	await tree.create_timer(0.8).timeout
	var ring := [Vector2i(11, 6), Vector2i(12, 6), Vector2i(9, 8), Vector2i(9, 9), Vector2i(11, 11), Vector2i(12, 11)]
	var spread_to := ring.filter(func(c: Vector2i) -> bool: return not _fires(c).is_empty())
	check(spread_to.size() >= 4, "fires beyond the patch within 0.8 s: %d of 6 around it" % spread_to.size())
	check(not _fires(Vector2i(13, 8)).is_empty() and _fires(Vector2i(14, 8)).is_empty() and _fires(Vector2i(14, 9)).is_empty(),
		"none spread onto the water or the brick beside it")
	var children := _lm.fires_at(Vector2i(11, 6)).filter(func(f: GroundFire) -> bool: return not f.registered)
	check(not children.is_empty() and children[0].side == 1 and children[0].strength == 3,
		"what spread is the same side's, of its strength, and not in its grid")
	_lm._clear_fire()
	_clear_field()
	for i in 12:
		_lm.ignite_fire_patch(Vector2i(11, 8), true, 0, 0)
	await tree.create_timer(0.8).timeout
	check(_fires(Vector2i(11, 6)).is_empty() and _fires(Vector2i(9, 8)).is_empty(), "level 1 fire never spreads, however fed")
	_lm._clear_fire()
	# Exactly: a fire of 8000 ticks, with its side's 4000-tick fire above it and
	# nothing on its other sides, gives each side a quarter of what it had at
	# the start above what's there: 1000 up, 2000 to each new fire.
	var big := _lm._new_fire(Vector2i(20, 15), 1, 0, 3, 8000.0, GroundFire.ARM, 0)
	var above := _lm._new_fire(Vector2i(20, 14), 1, 1, 1, 4000.0, GroundFire.ARM, 0)
	for f: GroundFire in [big, above]:
		f.registered = true
		_lm._fire_grid[1][f.tile_pos] = f
	_lm.spread_fire(big)
	var given: Array = [Vector2i(21, 15), Vector2i(20, 16), Vector2i(19, 15)].map(
			func(c: Vector2i) -> float: return _fuel(c) if _fires(c).size() == 1 and not _first(c).registered else -1.0)
	check(is_equal_approx(above.fuel, 5000.0) and above.strength == 3 and above.owner_id == 0 and given == [2000.0, 2000.0, 2000.0]
			and is_equal_approx(big.fuel, 1000.0),
		"a quarter each of what it had at the start: %d up (its strength and owner now the giver's), %s to new fires, %d kept" % [above.fuel, str(given), big.fuel])
	_lm._clear_fire()
	# How often: walled in (so it keeps its fuel), a level 4 fire's next pulse
	# comes 300 ticks after one, a level 2 fire's 500.
	var l4 := _lm._new_fire(Vector2i(20, 15), 1, 0, 3, 40000.0, GroundFire.ARM, 0)
	var l2 := _lm._new_fire(Vector2i(28, 15), 1, 0, 1, 40000.0, GroundFire.ARM, 0)
	for f: GroundFire in [l4, l2]:
		for d in LevelManager.FIRE_DIRS:
			_put(f.tile_pos + d, BRICK)
		f._spread = 1.0
	await _frames(3)
	check(l4._spread > 150.0 and l4._spread <= 300.0 and l2._spread > 350.0 and l2._spread <= 500.0,
		"it spreads every 600 - 100 x its strength ticks: next in %d at level 4, %d at level 2" % [l4._spread, l2._spread])
	_lm._clear_fire()
	_clear_field()

	print("\n[F] Burning tanks: the other side's fire, a point every 0.5625 s; burning grass everyone every 1.125 s")
	var victim := _enemy(Vector2i(9, 7))
	await _frames(2)
	_lm.ignite_fire_patch(Vector2i(10, 8), true, 0, 3)
	var lost := await _burned(victim, 1.3)
	check(lost == 3, "an enemy in a player's fire: 3 points in 1.3 s, 0.5625 s apart: %d" % lost)
	check(victim._hits_taken == 3, "each an ordinary hit")
	_lm._clear_fire()
	_lm.ignite_fire_patch(Vector2i(10, 8), false, -1, 3)
	victim.fire_immunity_timer = 0.0
	check(await _burned(victim, 0.6) == 0, "the enemies' own fire never burns an enemy")
	_player.global_position = _spot(Vector2i(9, 7)) + Vector2(0, 64)
	_player.is_invincible = false
	_player.fire_immunity_timer = 0.0
	check(await _burned(_player, 0.3) == 1, "but burns a player")
	_player.global_position = _spot(Vector2i(37, 27))
	_player.is_invincible = true
	_lm._clear_fire()
	victim.fire_immunity_timer = 0.0
	var grass_fire := _lm._new_fire(Vector2i(10, 8), -1, -1, 0, 5000.0, 0.0, 0, true)
	grass_fire.registered = false
	await _frames(2)
	var grass_lost := await _burned(victim, 1.3)
	check(grass_lost == 2, "burning grass, nobody's: 2 points in 1.3 s, 1.125 s apart: %d" % grass_lost)
	victim.health = 10
	victim.fire_immunity_timer = 0.0
	victim.global_position = _lm.global_position + Vector2(10 * 32 - 27, 8 * 32 + 16)  # 27 px left of that tile
	check(await _burned(victim, 0.3) == 0, "its box is its picture less 6 px a side: 27 px off, not burned")
	victim.global_position = _lm.global_position + Vector2(10 * 32 - 25, 8 * 32 + 16)
	victim.fire_immunity_timer = 0.0
	check(await _burned(victim, 0.3) == 1, "25 px off, burned")
	victim.global_position = _spot(Vector2i(9, 7))
	victim.health = 10
	victim.fire_immunity_timer = 0.0
	victim.is_materializing = true
	victim._materialize_timer = 5.0
	victim.fire_immunity_timer = 0.0
	check(await _burned(victim, 0.3) == 0, "a tank still appearing doesn't burn")
	# A blinking player (its helmet): its box is its picture and 12 px more a
	# side, and the window starts though it takes nothing.
	_player.is_invincible = true
	_player.global_position = _lm.global_position + Vector2(10 * 32 - 43, 8 * 32 + 16)  # 43 px left of that tile
	_player.fire_immunity_timer = 0.0
	var blinking_hp := _player.health
	await _frames(3)
	check(_player.fire_immunity_timer > 0.0 and _player.health == blinking_hp,
		"a blinking player 43 px off is burned, taking nothing, and its window starts")
	_player.global_position = _lm.global_position + Vector2(10 * 32 - 45, 8 * 32 + 16)
	_player.fire_immunity_timer = 0.0
	await _frames(3)
	check(_player.fire_immunity_timer == 0.0, "45 px off, not")
	_player.global_position = _spot(Vector2i(37, 27))
	victim.is_materializing = false
	victim.queue_free()
	_lm._clear_fire()

	print("\n[G] Grass: a fire's step burns the grass beside it, lighting nobody's fire there, which walks on")
	_clear_field()
	for x in range(12, 20):
		_put(Vector2i(x, 8), GRASS)
	_lm.ignite_fire_patch(Vector2i(10, 8), true, 0, 0)
	await tree.create_timer(0.3).timeout
	check(_lm._is_green_grass(Vector2i(12, 8)), "0.3 s in, the grass beside it is still green")
	await tree.create_timer(0.5).timeout
	var lit := _lm.fires_at(Vector2i(12, 8)).filter(func(f: GroundFire) -> bool: return f.is_grass_fire)
	check(not _lm._is_green_grass(Vector2i(12, 8)) and lit.size() == 1, "by 0.8 s it's burned grey, with burning grass on it")
	check(lit.size() == 1 and lit[0]._current_row() == 1 and lit[0].z_index > 10, "red, and drawn over the tanks")
	await tree.create_timer(3.0).timeout
	var grey := 0
	for x in range(12, 20):
		grey += 0 if _lm._is_green_grass(Vector2i(x, 8)) else 1
	check(grey >= 5, "3 s later it has walked along the grass: %d of 8 tiles grey" % grey)
	_lm._clear_fire()

	print("\n[H] Ice: a side's fire melts the ice under it at its step; burning grass doesn't")
	_clear_field()
	for y in range(6, 12):
		for x in range(8, 14):
			_lm._place_bg_tile(Vector2i(x, y), ICE)
	_lm.ignite_fire_patch(Vector2i(10, 8), true, 0, 0)
	await tree.create_timer(0.3).timeout
	var ice_then := PATCH.filter(func(o: Vector2i) -> bool: return _lm._is_ice(Vector2i(10, 8) + o)).size()
	await tree.create_timer(0.55).timeout
	var ice_now := PATCH.filter(func(o: Vector2i) -> bool: return _lm._is_ice(Vector2i(10, 8) + o)).size()
	check(ice_then == 12 and ice_now == 0 and _lm._is_ice(Vector2i(8, 6)), "a player's: none melted at 0.3 s, all 12 by 0.85 s, and only those")
	_lm._clear_fire()
	_clear_field()
	for y in range(6, 12):
		for x in range(8, 14):
			_lm._place_bg_tile(Vector2i(x, y), ICE)
	_lm.ignite_fire_patch(Vector2i(10, 8), false, -1, 0)
	await tree.create_timer(0.85).timeout
	check(PATCH.all(func(o: Vector2i) -> bool: return not _lm._is_ice(Vector2i(10, 8) + o)), "the enemies' fire melts it too")
	_lm._clear_fire()
	_lm._place_bg_tile(Vector2i(20, 8), ICE)
	_put(Vector2i(20, 8), GRASS)
	_lm.ignite_fire_patch(Vector2i(22, 8), true, 0, 0)  # its patch beside the grass, not on it
	await tree.create_timer(1.8).timeout
	check(not _lm._is_green_grass(Vector2i(20, 8)) and _lm._is_ice(Vector2i(20, 8)), "burning grass on ice leaves the ice")
	_lm._clear_fire()
	_clear_field()

	print("\n[I] The shell: 1 point at every level, slowing as it flies, dropping its patch about 496 px out")
	_player.global_position = _spot(Vector2i(2, 14))
	_player.current_direction = Vector2.RIGHT
	_player.active_fire_bullets = 0
	_player._spawn_fire_bullet(CookieData.get_weapon_fire_config("fire", 3))
	var shell: Bullet = null
	for node in tree.get_nodes_in_group(NetWorld.GROUP):
		if node is Bullet and (node as Bullet).ignites_ground:
			shell = node
	var from := shell.global_position
	check(shell.damage == 1 and shell.fire_level == 3 and is_equal_approx(shell.speed, 622.2), "level 4: damage 1, leaves at 622 px/s")
	await tree.create_timer(0.5).timeout
	var mid_speed := shell.speed if is_instance_valid(shell) else 0.0
	check(mid_speed > 520.0 and mid_speed < 545.0, "half a second on, 533 px/s (%.0f)" % mid_speed)
	var end_at := Vector2.ZERO
	var lasted := 0.5
	while is_instance_valid(shell) and not shell._destroyed and lasted < 2.0:
		end_at = shell.global_position
		await _frames()
		lasted += get_physics_process_delta_time()
	var flew := end_at.x - from.x
	check(flew > 480.0 and flew < 510.0, "it dropped %.0f px out" % flew)
	var dropped := _lm.fires_at(_lm.fire_anchor(end_at))
	check(not dropped.is_empty() and dropped[0].strength == 3, "its patch there, level 4 fire")
	_player.global_position = _spot(Vector2i(37, 27))
	_lm._clear_fire()

	print("\n[J] It drops on what it meets: an enemy shell of 2 loses 1, one of 1 goes")
	var mine_b := _bullet(_spot(Vector2i(20, 20)), true, true, 1)
	var theirs := _bullet(_spot(Vector2i(20, 20)), false, false, 2)
	mine_b._on_area_entered(theirs)
	check(mine_b._destroyed and not theirs._destroyed and theirs.damage == 1, "the fire shell drops; theirs goes on with 1")
	var mine_c := _bullet(_spot(Vector2i(22, 20)), true, true, 1)
	var weak_b := _bullet(_spot(Vector2i(22, 20)), false, false, 1)
	mine_c._on_area_entered(weak_b)
	check(weak_b._destroyed, "one of 1 goes")

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


func _bullet(pos: Vector2, is_player: bool, fire: bool, dmg: int) -> Bullet:
	# Configured before it enters the tree, so no physics frame runs first.
	var b: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	b.direction = Vector2.UP
	b.is_player_bullet = is_player
	b.ignites_ground = fire
	b.damage = dmg
	b.global_position = pos
	_game.get_node("Entities/Bullets").add_child(b)
	b.global_position = pos
	return b
