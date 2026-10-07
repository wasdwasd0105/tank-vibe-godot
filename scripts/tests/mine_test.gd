extends Node
## Headless integration test for the mine weapon against the original game's
## rules (docs/mine_weapon_original_spec.md), and a player's bomb setting every
## mine off with the players spared (Sean's rule). Run as an override main scene:
##   Godot --headless res://scenes/test/mine_test.tscn
##
## Test enemies run with physics (AI) disabled so the harness is deterministic;
## the mine still sees them through the physics-server overlap query, and a
## flight is stepped by hand.

const IRON := 0x39
const WATER := 0x05
const GRASS := 0x09

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		_fail += 1
		print("  FAIL: ", msg)


func _ready() -> void:
	_run()


# --- helpers -------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in range(n):
		await get_tree().physics_frame
	await get_tree().process_frame


## Long enough for a contact to register (a physics step) and the mine's next
## frame to act on it, and for the blast it spawns to land its damage.
func _settle() -> void:
	await get_tree().create_timer(0.25).timeout


func _at(local: Vector2) -> Vector2:
	return _lm.global_position + local


func _place(tank: BaseTank, local: Vector2, facing: Vector2) -> void:
	tank.global_position = _at(local)
	tank.current_direction = facing
	tank._update_sprite_direction()


func _spawn_enemy(local: Vector2, type_id: int = 1, hp: int = 10) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)  # no AI in the test harness
	e.global_position = _at(local)
	e.max_health = hp
	e.health = hp
	return e


## Lays for [param tank] and returns the new mine (or null), with its centre.
func _lay(tank: BaseTank, level: int) -> Mine:
	var before := _lm.get_mines()
	if not _lm.try_place_mine(tank, level):
		return null
	for mine in _lm.get_mines():
		if not before.has(mine):
			return mine
	return null


func _offset_of(mine: Mine, tank: BaseTank) -> Vector2:
	return _lm.mine_center(mine.cell) - tank.global_position


func _arm(mine: Mine) -> void:
	mine._age = Mine.ARM_TIME + 0.001


func _reset() -> void:
	_lm._clear_mines()
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for b in get_tree().get_nodes_in_group("effects_container")[0].get_children():
		b.queue_free()
	_player.is_invincible = false
	_player.is_mine_slowed = false
	_place(_player, Vector2(96, 96), Vector2.UP)   # parked in the top-left corner
	await _frames(3)


func _clear_arena() -> void:
	# Keep only the base's own block (bottom middle); everything else open ground.
	for tile in _lm._fg_tile_data.keys():
		if tile.x < 16 or tile.x > 23 or tile.y < 25:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(tile)


func _put_fg(tile: Vector2i, code: int) -> void:
	_lm._remove_fg_tile(tile)
	_lm._place_fg_tile(tile, code)


func _blast_count() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("effects_container")[0].get_children():
		if b is ExplosionBlast and not b.is_queued_for_deletion():
			n += 1
	return n


# --- the test ------------------------------------------------------------

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
	check(_lm != null and _player != null, "level_manager + player available")
	while _player.is_materializing:
		await tree.process_frame
	_clear_arena()
	await _reset()

	# The tank's block top-left is (10,10), so its centre is the corner (352, 352).
	var home := Vector2(352, 352)

	print("\n[A] A mine goes 2 tiles straight behind, on a tile corner")
	var want := {
		Vector2.UP: Vector2(0, 64), Vector2.RIGHT: Vector2(-64, 0),
		Vector2.DOWN: Vector2(0, -64), Vector2.LEFT: Vector2(64, 0),
	}
	for facing in want:
		_lm._clear_mines()
		_place(_player, home, facing)
		var m := _lay(_player, 0)
		check(m != null and _offset_of(m, _player) == want[facing],
			"facing %s -> mine at %s (got %s)" % [facing, want[facing], _offset_of(m, _player) if m else "none"])
	await _frames()
	var corner_ok := true
	for m in _lm.get_mines():
		var local := m.global_position - _lm.global_position
		corner_ok = corner_ok and fmod(local.x, 32.0) == 0.0 and fmod(local.y, 32.0) == 0.0
	check(corner_ok, "mine nodes sit on tile corners, not tile centres")

	print("\n[B] Ring order: behind, then the neighbour either side, then round")
	_lm._clear_mines()
	_place(_player, home, Vector2.UP)
	_put_fg(Vector2i(11, 12), IRON)   # right column of the block behind
	var m1 := _lay(_player, 0)
	check(m1 != null and _offset_of(m1, _player) == Vector2(-32, 64), "right half walled -> shifts one tile left (%s)" % (_offset_of(m1, _player) if m1 else "none"))
	_lm._remove_fg_tile(Vector2i(11, 12))
	_lm._clear_mines()
	_put_fg(Vector2i(10, 12), IRON)   # left column: blocks behind AND behind-left
	var m2 := _lay(_player, 0)
	check(m2 != null and _offset_of(m2, _player) == Vector2(32, 64), "left half walled -> shifts one tile right (%s)" % (_offset_of(m2, _player) if m2 else "none"))
	_lm._remove_fg_tile(Vector2i(10, 12))
	_lm._clear_mines()
	var laid: Array[Vector2] = []
	for i in range(3):
		var m := _lay(_player, 0)
		if m:
			laid.append(_offset_of(m, _player))
	check(laid == [Vector2(0, 64), Vector2(-32, 64), Vector2(32, 64)],
		"standing still, unarmed mines fill behind, behind-left, behind-right (%s)" % str(laid))

	print("\n[C] Delphi rounding when the tank sits between tiles")
	_lm._clear_mines()
	_place(_player, Vector2(688, 352), Vector2.UP)   # x/32 - 1 = 20.5 -> 20 (even)
	var r1 := _lay(_player, 0)
	check(r1 != null and _offset_of(r1, _player) == Vector2(-16, 64), "20.5 rounds down to even (%s)" % (_offset_of(r1, _player) if r1 else "none"))
	_lm._clear_mines()
	_place(_player, Vector2(720, 352), Vector2.UP)   # 21.5 -> 22 (even)
	var r2 := _lay(_player, 0)
	check(r2 != null and _offset_of(r2, _player) == Vector2(16, 64), "21.5 rounds up to even (%s)" % (_offset_of(r2, _player) if r2 else "none"))
	_lm._clear_mines()
	_place(_player, Vector2(352, 368), Vector2.UP)   # y 10.5 -> 10: its own body blocks behind
	var r3 := _lay(_player, 0)
	check(r3 != null and _offset_of(r3, _player) == Vector2(-64, 16), "a tank between rows blocks its own rear slots -> side (%s)" % (_offset_of(r3, _player) if r3 else "none"))

	print("\n[D] What blocks a spot")
	_lm._clear_mines()
	_place(_player, home, Vector2.UP)
	_put_fg(Vector2i(10, 12), GRASS)
	var g := _lay(_player, 0)
	check(g != null and _offset_of(g, _player) == Vector2(0, 64), "grass does not block")
	_lm._remove_fg_tile(Vector2i(10, 12))
	_lm._clear_mines()
	_lm._place_bg_tile(Vector2i(10, 13), WATER)
	var w1 := _lay(_player, 0)
	check(w1 != null and _offset_of(w1, _player) == Vector2(32, 64), "water blocks a normal tank")
	_lm._clear_mines()
	_player.apply_addon("anti-water")
	var w2 := _lay(_player, 0)
	check(w2 != null and _offset_of(w2, _player) == Vector2(0, 64), "anti-water lays on water")
	_player._remove_utility_addon()
	_lm._remove_bg_tile(Vector2i(10, 13))
	_lm._clear_mines()
	var blocker := _spawn_enemy(home + Vector2(0, 64))
	await _frames()
	var p1 := _lay(_player, 0)
	check(p1 != null and _offset_of(p1, _player) == Vector2(-64, 32), "a tank near the rear spots pushes the mine to the side (%s)" % (_offset_of(p1, _player) if p1 else "none"))
	blocker.queue_free()
	_lm._clear_mines()
	_place(_player, Vector2(5 * 32, 29 * 32), Vector2.UP)  # bottom edge, facing up
	var e1 := _lay(_player, 0)
	check(e1 != null and _offset_of(e1, _player) == Vector2(-64, 0), "off-field rear spots are skipped (%s)" % (_offset_of(e1, _player) if e1 else "none"))
	_lm._clear_mines()
	_place(_player, home, Vector2.UP)
	var walls: Array[Vector2i] = []
	for y in range(8, 14):
		for x in range(8, 14):
			if x < 10 or x > 11 or y < 10 or y > 11:
				walls.append(Vector2i(x, y))
				_put_fg(Vector2i(x, y), IRON)
	_player.set_secondary_weapon("mine")
	var ammo := _player.secondary_weapon_count
	_player._shoot_secondary_mine()
	check(_lm.get_mines().is_empty() and _player.secondary_weapon_count == ammo and _player.can_shoot,
		"all 12 spots blocked: nothing laid, no ammo or cooldown spent")
	for t in walls:
		_lm._remove_fg_tile(t)
	await _frames()

	print("\n[E] Level = gun level 0-3, sprite row = level, hidden while deploying")
	await _reset()
	_place(_player, home, Vector2.UP)
	for lvl in range(4):
		_lm._clear_mines()
		_player.weapon_level = lvl
		_player.can_shoot = true
		_player._shoot_secondary_mine()
		var mines := _lm.get_mines()
		check(mines.size() == 1 and mines[0].level == lvl, "gun level %d lays a level-%d mine" % [lvl, lvl])
	_player.weapon_level = 0
	_lm._clear_mines()
	var dep := _lm._spawn_mine(Vector2i(20, 6), 1, true)
	await get_tree().create_timer(0.1).timeout
	check(not dep.visible and not dep.is_armed(), "0.1 s in: still hidden and inert")
	await get_tree().create_timer(0.25).timeout
	check(dep.visible and dep.is_armed(), "0.35 s in: surfaced and armed")
	check(dep._sprite.texture == Mine._load_row(1)[3], "level 1 holds the last frame of sheet row 1")
	for lvl in [0, 2]:
		var mm := _lm._spawn_mine(Vector2i(4 + lvl * 3, 6), lvl, true)
		await _frames()
		_arm(mm)
		mm._age = 1.0
		await _frames()
		check(mm._sprite.texture == Mine._load_row(lvl)[3], "level %d shows sheet row %d, last frame" % [lvl, lvl])
	var l3 := _lm._spawn_mine(Vector2i(14, 6), 3, true)
	await _frames()
	l3._age = 1.0
	await _frames()
	check(Mine._load_row(4).has(l3._sprite.texture), "level 3 loops the ringed row (sheet row 4)")

	print("\n[F] Enemy mines fade in near a player or the base")
	await _reset()
	var em := _lm._spawn_mine(Vector2i(20, 6), 0, false)
	await _frames()
	_arm(em)
	var mc := _lm.mine_center(em.cell) - _lm.global_position
	var cases := [
		[Vector2(0, 192), true, 64], [Vector2(0, 200), true, 64],
		[Vector2(0, 208), false, 48], [Vector2(0, 96), true, 160], [Vector2(0, 48), true, 192],
	]
	for c in cases:
		_place(_player, mc + c[0], Vector2.UP)
		await _frames()
		var a := roundi(em._sprite.modulate.a * 255.0)
		check(em.visible == c[1] and a == c[2], "player %d px away: visible=%s alpha=%d (got %s, %d)" % [int(c[0].y), c[1], c[2], em.visible, a])
	_place(_player, mc + Vector2(0, 320), Vector2.UP)
	_player.set_physics_process(false)  # hold it "airborne" without a real flight
	_player.is_flying = true
	await _frames()
	check(em.visible, "an airborne player spots it 8 steps further out (320 px)")
	_player.is_flying = false
	_player.set_physics_process(true)
	_player.apply_addon("anti-ice")
	_place(_player, mc + Vector2(0, 256), Vector2.UP)
	await _frames()
	check(em.visible, "anti-ice spots it 4 steps further out (256 px)")
	_place(_player, mc + Vector2(0, 288), Vector2.UP)
	await _frames()
	check(not em.visible, "anti-ice at 288 px: still hidden")
	_player._remove_utility_addon()
	var eagle: Node2D = get_tree().get_first_node_in_group("eagle")
	var near_base := _lm._spawn_mine(_lm.world_to_tile(eagle.global_position + Vector2(-32, -32 - 288)), 0, false)
	var far_base := _lm._spawn_mine(_lm.world_to_tile(eagle.global_position + Vector2(-32, -32 - 320)), 0, false)
	_place(_player, Vector2(96, 96), Vector2.UP)
	await _frames()
	_arm(near_base)
	_arm(far_base)
	await _frames()
	check(near_base.global_position.distance_to(eagle.global_position) == 288.0 and near_base.visible, "the base reveals a mine 288 px away")
	check(far_base.global_position.distance_to(eagle.global_position) == 320.0 and not far_base.visible, "but not 320 px away")
	var pm := _lm._spawn_mine(Vector2i(30, 6), 0, true)
	await _frames()
	_arm(pm)
	await _frames()
	check(pm.visible and pm._sprite.modulate.a == 1.0, "a player's own mine is always fully drawn")

	print("\n[G] What a mine does to the tank that touches it")
	await _reset()
	# [level, enemy type (add-on), exploded, slowed, thrown, hp lost on landing, add-on left]
	# Levels 0-3 here are 1-4 in play. A thrown tank loses nothing in the air; on
	# landing it loses its moon shield or else another add-on, and 1 HP (L2) or 2
	# (L3) (Sean's rule).
	var rows := [
		[0, 1, true, false, false, -1, ""],
		[1, 1, true, true, false, -1, ""],
		[2, 1, true, true, true, 1, ""],
		[3, 1, true, true, true, 2, ""],
		[2, 6, false, false, false, 0, "anti-ice"],     # anti-ice skates over L0-L2
		[3, 6, true, false, true, 2, ""],               # L3: thrown; lands without anti-ice, 2 HP down
		[2, 4, true, true, true, 1, ""],                # the moon shield goes on landing, and 1 HP
		[3, 4, true, true, true, 2, ""],
		[2, 8, true, false, true, 1, ""],               # memory-save: no slow below L3, but thrown all
		[3, 8, true, true, true, 2, ""],                # the same, and it lands without it
	]
	var col := 0
	for row in rows:
		var cell := Vector2i(3 + (col % 5) * 7, 6 + (col / 5) * 8)
		col += 1
		var mine := _lm._spawn_mine(cell, row[0], true)
		await _frames()
		_arm(mine)
		var local := _lm.mine_center(cell) - _lm.global_position
		var e := _spawn_enemy(local, row[1], 10)
		e._hits_taken = 5  # keep the remake's second-hit add-on drop out of this
		var addon_before: String = e.addons[0] if not e.addons.is_empty() else ""
		await _settle()
		var label := "L%d on type %d" % [row[0], row[1]]
		check(_lm.has_mine(cell) != row[2], "%s: mine %s" % [label, "went off" if row[2] else "stayed"])
		check(e.is_mine_slowed == row[3], "%s: slowed=%s" % [label, row[3]])
		check(e.is_flying == row[4], "%s: thrown=%s" % [label, row[4]])
		if row[4]:
			var aloft_addon: String = e.addons[0] if not e.addons.is_empty() else ""
			check(e.health == 10 and aloft_addon == addon_before,
				"%s: nothing lost in the air, the blast can't reach it (hp %d, add-on '%s')" % [label, e.health, aloft_addon])
			while e.is_flying:
				e._update_flying(1.0 / 60.0)
			check(e.health == 10 - row[5], "%s: lands and loses %d HP (hp %d)" % [label, row[5], e.health])
		elif row[5] == 0:
			check(e.health == 10, "%s: untouched (hp %d)" % [label, e.health])
		else:
			check(e.health < 10 or not row[2], "%s: the blast hit it (hp %d)" % [label, e.health])
		var left: String = e.addons[0] if not e.addons.is_empty() else ""
		check(left == row[6], "%s: add-on left = '%s' (got '%s')" % [label, row[6], left])
		e.queue_free()
		await _frames()
	check(is_equal_approx(BaseTank.MINE_SLOW_FACTOR, 0.25), "the slow is a quarter of move speed")
	_player.apply_mine_slow()
	_player.try_move(Vector2.UP)
	check(is_equal_approx(_player.velocity.length(), _player.move_speed * 0.25), "a slowed player moves at quarter speed")
	_player.stop_moving()
	await _reset()
	var own := _lm._spawn_mine(Vector2i(20, 12), 3, true)
	await _frames()
	_arm(own)
	_place(_player, _lm.mine_center(own.cell) - _lm.global_position, Vector2.UP)
	await _settle()
	check(_lm.has_mine(own.cell), "the layer's own side never sets it off")
	await _reset()
	var enemy_l3 := _lm._spawn_mine(Vector2i(20, 12), 3, false)
	await _frames()
	_arm(enemy_l3)
	_player.is_invincible = true
	_player.invincible_timer = 30.0
	_player.apply_addon("moon-shield")
	var hp := _player.health
	_place(_player, _lm.mine_center(Vector2i(20, 12)) - _lm.global_position, Vector2.UP)
	await _settle()
	check(not _lm.has_mine(Vector2i(20, 12)) and _player.is_flying and not _player.is_mine_slowed and _player.health == hp,
		"an invincible player is thrown all the same, but takes no slow")
	while _player.is_flying:
		_player._update_flying(1.0 / 60.0)
	check(_player.health == hp and _player.has_moon_shield,
		"and, still invincible when it lands, keeps its HP and its moon shield")
	_player.is_invincible = false
	_player.invincible_timer = 0.0
	# Not invincible: the moon shield goes first, then the HP; the landing hit
	# costs no level and starts no hit grace.
	await _reset()
	var thrower := _lm._spawn_mine(Vector2i(20, 12), 3, false)
	await _frames()
	_arm(thrower)
	_player.apply_addon("anti-water")
	_player.health = 4
	var levels := [_player.speed_level, _player.weapon_level]
	_place(_player, _lm.mine_center(Vector2i(20, 12)) - _lm.global_position, Vector2.UP)
	await _settle()
	check(_player.is_flying and _player.health == 4 and _player.has_moon_shield and _player.has_boat,
		"a player thrown by an L3 mine loses nothing in the air")
	while _player.is_flying:
		_player._update_flying(1.0 / 60.0)
	check(_player.health == 2 and not _player.has_moon_shield and _player.has_boat,
		"on landing: the moon shield goes (the boat stays), and 2 HP (hp %d)" % _player.health)
	check([_player.speed_level, _player.weapon_level] == levels and not _player.is_invincible,
		"no level lost and no hit grace for it")
	_player.health = 4
	await _settle()   # the landing blast
	check(_player.health < 4, "its own landing blast hurts it too, as the original's (hp %d)" % _player.health)
	_player.lose_addon("anti-water")
	_player.health = 4
	var bare := _lm._spawn_mine(Vector2i(20, 12), 2, false)
	await _frames()
	_arm(bare)
	_player.apply_addon("anti-ice")
	_player.is_invincible = false
	_place(_player, _lm.mine_center(Vector2i(20, 12)) - _lm.global_position, Vector2.UP)
	await _settle()
	# Anti-ice skates over an L2 mine, so this one has nothing else to lose: the
	# add-on stays and the mine too.
	check(_lm.has_mine(Vector2i(20, 12)) and not _player.is_flying, "anti-ice skates over an L2 mine")
	_player.lose_addon("anti-ice")
	await _settle()
	check(_player.is_flying, "without it, the L2 mine throws the player")
	while _player.is_flying:
		_player._update_flying(1.0 / 60.0)
	check(_player.health == 3, "and with no add-on to lose it lands 1 HP down (hp %d)" % _player.health)
	await _settle()
	_player.health = 4
	# Sean's case (2026-09-24): memory-save and a moon shield, driving into an
	# enemy L2 mine. The original kept a memory-save tank on the ground.
	var sean := _lm._spawn_mine(Vector2i(20, 12), 2, false)
	await _frames()
	_arm(sean)
	_player.apply_addon("memory-save")
	_player.apply_addon("moon-shield")
	_player.is_invincible = false
	_place(_player, _lm.mine_center(Vector2i(20, 12)) - _lm.global_position + Vector2(0, 44), Vector2.UP)
	await _settle()
	check(not _lm.has_mine(Vector2i(20, 12)) and _player.is_flying, "memory-save no longer keeps a player on the ground")
	while _player.is_flying:
		_player._update_flying(1.0 / 60.0)
	check(_player.health == 3 and not _player.has_moon_shield and _player.has_memory_save,
		"it lands without its moon shield (memory-save stays), 1 HP down (hp %d)" % _player.health)
	await _settle()
	_player.lose_addon("memory-save")
	_player.health = 4

	print("\n[H] Flight: thrown back the way it came, as the original's TFlyingTank")
	# A tank touches a mine 44 px short of its centre (its 60 px box against the
	# mine's 32 px), and is thrown 8x that at L2 (352 px, 11 tiles), 10x at L3.
	# [level, mine cell, where the tank sat when it touched, relative to the mine]
	var throws := [
		[2, Vector2i(26, 12), Vector2(-44, 0)],   # drove in from the left: thrown left
		[3, Vector2i(26, 12), Vector2(-44, 0)],
		[2, Vector2i(14, 5), Vector2(0, 44)],     # drove up into it: thrown back down
	]
	for t in throws:
		await _reset()
		var lvl: int = t[0]
		var fm := _lm._spawn_mine(t[1], lvl, true)
		await _frames()
		_arm(fm)
		var fmc := _lm.mine_center(t[1]) - _lm.global_position
		var fe := _spawn_enemy(fmc + t[2], 1, 10)
		fe.current_direction = -(t[2] as Vector2).normalized()   # facing the mine it drove at
		fe._update_sprite_direction()
		fe.special_weapon_level = 1
		var start: Vector2 = fe.global_position
		var z_before := fe.z_index
		await _settle()
		check(fe.is_flying and fe.z_index > z_before, "L%d: airborne, drawn above the field" % lvl)
		var base_scale: float = fe._fly_base_sprite_scale.x
		var facing_before := BaseTank.FACINGS.find(fe.current_direction)
		var steps := 0
		var peak := 1.0
		var lifted := false
		while fe.is_flying and steps < 400:
			fe._update_flying(1.0 / 60.0)
			steps += 1
			if fe.is_flying:
				peak = maxf(peak, fe.sprite.scale.x / base_scale)
				lifted = lifted or fe.sprite.position != Vector2.ZERO
		var aloft := steps / 60.0
		var want_aloft := 1.2 if lvl == 2 else 1.5
		check(absf(aloft - want_aloft) <= 0.05, "L%d: aloft %.2f s (original %.1f s)" % [lvl, aloft, want_aloft])
		var moved: Vector2 = fe.global_position - start
		var want_moved: Vector2 = (t[2] as Vector2) * (8.0 if lvl == 2 else 10.0)
		check(moved.distance_to(want_moved) < 16.0, "L%d: thrown %s, back the way it came (got %s)" % [lvl, want_moved, moved.round()])
		var want_peak := 2.6 if lvl == 2 else 3.5
		check(absf(peak - want_peak) < 0.1 and not lifted, "L%d: grows to %.1fx at the top without leaving its spot (got %.2fx)" % [lvl, want_peak, peak])
		var units := aloft / BaseTank.FLY_TIME_UNIT
		var want_turns := (lvl * 200.0 * units - 55.0 * units * units / 2.0) / 256.0
		check(absf(absf(fe._fly_angle) / 256.0 - want_turns) < 0.03, "L%d: tumbles %.2f turns (got %.2f)" % [lvl, want_turns, absf(fe._fly_angle) / 256.0])
		var quarter := posmod(roundi(fe._fly_angle), 256) >> 6
		check(fe.current_direction == BaseTank.FACINGS[(facing_before + quarter) % 4], "L%d: lands facing where the tumble stopped" % lvl)
		check(fe.z_index == z_before and fe.collision_layer != 0, "L%d: back on the ground, collidable, normal draw order" % lvl)
		await _frames()
		var landing: ExplosionBlast = null
		for b in get_tree().get_nodes_in_group("effects_container")[0].get_children():
			if b is ExplosionBlast and b.neutral:
				landing = b
		check(landing != null and landing.level == 1
			and landing.origin == ExplosionBlast.grid_origin(fe.global_position - _lm.global_position, ExplosionBlast.TANK_SIZE),
			"L%d: neutral landing blast at the victim's gun level 1, where it came down" % lvl)
		fe.queue_free()
	await _reset()
	# Near the edge the throw stops at the field's border.
	var edge_cell := Vector2i(36, 12)
	var edge_mine := _lm._spawn_mine(edge_cell, 3, true)
	await _frames()
	_arm(edge_mine)
	var edge := _spawn_enemy(_lm.mine_center(edge_cell) - _lm.global_position + Vector2(44, 0), 1, 10)
	await _settle()
	var edge_steps := 0
	while edge.is_flying and edge_steps < 400:
		edge._update_flying(1.0 / 60.0)
		edge_steps += 1
	check(is_equal_approx(edge.global_position.x, BaseTank.PLAYFIELD_MAX_X), "thrown towards the edge, it lands against the border (x %.0f)" % edge.global_position.x)
	edge.queue_free()
	await get_tree().create_timer(0.6).timeout

	print("\n[I] Explosions set off opposing mines, if strong and close enough")
	# [blast level, blast side (player?), neutral, mine level, mine side (player?), armed, offset in tiles, wall between, goes off]
	var chains := [
		[2, true, false, 1, false, true, Vector2i(2, 0), false, true],
		[2, true, false, 2, false, true, Vector2i(2, 0), false, false],   # equal level: next tile only
		[2, true, false, 2, false, true, Vector2i(1, 0), false, true],
		[2, true, false, 3, false, true, Vector2i(1, 0), false, false],   # blast weaker than the mine
		[3, true, false, 0, true, true, Vector2i(1, 0), false, false],    # own side never
		[3, true, false, 0, false, false, Vector2i(1, 0), false, false],  # still deploying
		[1, true, true, 0, true, true, Vector2i(2, 0), false, true],      # neutral hits player mines
		[1, true, true, 0, false, true, Vector2i(0, 2), false, true],     # ... and enemy mines
		[3, true, false, 0, false, true, Vector2i(3, 0), false, true],
		[3, true, false, 0, false, true, Vector2i(3, 0), true, false],    # a wall shadows it
	]
	var blast_cell := Vector2i(20, 12)
	for c in chains:
		await _reset()
		var mine := _lm._spawn_mine(blast_cell + c[6], c[3], c[4])
		await _frames()
		if c[5]:
			_arm(mine)
		else:
			mine._age = -100.0  # keep it deploying for the whole case
		if c[7]:
			_put_fg(blast_cell + Vector2i(2, 0), IRON)
			_put_fg(blast_cell + Vector2i(2, 1), IRON)
		await _frames()
		_lm.spawn_explosion_blast(_lm.mine_center(blast_cell), c[0], c[1], c[2])
		await get_tree().create_timer(0.4).timeout
		var gone := not _lm.has_mine(blast_cell + c[6])
		check(gone == c[8], "L%d %s blast vs %s L%d mine %s tiles off%s%s: %s" % [
			c[0], "neutral" if c[2] else ("player" if c[1] else "enemy"),
			"player" if c[4] else "enemy", c[3], str(c[6]),
			"" if c[5] else " (unarmed)", " behind a wall" if c[7] else "",
			"goes off" if c[8] else "stays"])
		if c[7]:
			_lm._remove_fg_tile(blast_cell + Vector2i(2, 0))
			_lm._remove_fg_tile(blast_cell + Vector2i(2, 1))
	await _reset()
	# Across sides: a player blast sets off an enemy mine, whose blast sets off
	# the player's mine next to it that the first blast would never touch.
	var ea := _lm._spawn_mine(blast_cell + Vector2i(1, 0), 0, false)
	var pb := _lm._spawn_mine(blast_cell + Vector2i(2, 0), 0, true)
	await _frames()
	_arm(ea)
	_arm(pb)
	await _frames()
	_lm.spawn_explosion_blast(_lm.mine_center(blast_cell), 0, true)
	await get_tree().create_timer(0.5).timeout
	check(not _lm.has_mine(blast_cell + Vector2i(1, 0)) and not _lm.has_mine(blast_cell + Vector2i(2, 0)),
		"chains cross sides: player blast -> enemy mine -> player mine")

	print("\n[J] Only add-on and MAX pickups lift the slow")
	await _reset()
	var cookie_scene := load("res://scenes/powerups/powerup.tscn")
	for c in [[CookieData.CookieType.HP_UP, false], [CookieData.CookieType.SCORE_500, false],
			[CookieData.CookieType.ANTI_ICE_COOKIE, true], [CookieData.CookieType.MAX_UP, true]]:
		_player.apply_mine_slow()
		var cookie = cookie_scene.instantiate()
		cookie.setup(c[0])
		_game.get_node("Entities/PowerUps").add_child(cookie)
		cookie._apply_effect(_player)
		cookie.queue_free()
		check(_player.is_mine_slowed != c[1], "cookie %d %s the slow" % [c[0], "lifts" if c[1] else "keeps"])
		_player._remove_utility_addon()

	print("\n[K] Enemies lay mines at their special-weapon level, with the lay sound")
	await _reset()
	var layer := _spawn_enemy(home, 21, 10)
	layer.special_weapon_level = 2
	layer.current_direction = Vector2.DOWN
	await get_tree().create_timer(0.1).timeout  # clear the lay-sound repeat guard
	await _frames()
	var sound_before: int = SoundManager._last_played.get(&"lay_mine", -1)
	layer.current_direction = Vector2.DOWN  # its AI may have turned it while we waited
	check(layer._lay_mine_special(), "enemy laid a mine")
	check(SoundManager._last_played.get(&"lay_mine", -1) > sound_before, "an enemy laying a mine plays the lay sound")
	var laid_mines := _lm.get_mines()
	check(laid_mines.size() == 1 and laid_mines[0].level == 2 and not laid_mines[0].from_player
		and _offset_of(laid_mines[0], layer) == Vector2(0, -64), "level 2, enemy side, behind a down-facing tank")

	print("\n[L] Mine tanks' levels follow the original's type table and difficulty")
	# Types 21-24 have base gun levels 0/1/1/2; EXPERT and above add one.
	var by_difficulty := {1: [0, 1, 1, 2], 2: [0, 1, 1, 2], 3: [0, 1, 1, 2], 4: [1, 2, 2, 3], 5: [1, 2, 2, 3], 7: [1, 2, 2, 3]}
	for d in by_difficulty:
		var got: Array[int] = []
		for t in range(21, 25):
			got.append(CookieData.get_enemy_weapon_level(t, d))
		check(got == by_difficulty[d], "difficulty %d: types 21-24 have gun levels %s (got %s)" % [d, str(by_difficulty[d]), str(got)])
	var saved_difficulty: int = GameManager.difficulty
	GameManager.difficulty = 5
	var hard_layer := _spawn_enemy(home + Vector2(256, 0), 24, 10)
	GameManager.difficulty = saved_difficulty
	hard_layer.current_direction = Vector2.DOWN
	await _frames()
	_lm._clear_mines()
	check(hard_layer._lay_mine_special() and _lm.get_mines().size() == 1 and _lm.get_mines()[0].level == 2
		and hard_layer.special_weapon_level == 3,
		"an INSANE type-24 tank (gun level 3) lays level-2 mines: enemy mines stop at L2")

	print("\n[M] A player's bomb_cookie sets every mine off, sparing the players (Sean)")
	await _reset()
	_clear_arena()
	_place(_player, Vector2(320, 320), Vector2.UP)
	var bomb_hp := _player.health
	var near_enemy_mine := _lm._spawn_mine(Vector2i(12, 9), 3, false)   # 3 tiles right: its blast reaches 4
	var own_mine := _lm._spawn_mine(Vector2i(6, 9), 2, true, 0)         # 3 tiles left, the player's
	var laying_mine := _lm._spawn_mine(Vector2i(24, 20), 1, false)   # still being laid
	_put_fg(Vector2i(14, 9), 0x19)   # a brick beside the enemy mine
	var bomb_victim := _spawn_enemy(Vector2(640, 480))
	# Player 2, not the one taking the bomb (whose pickup grace would cover it),
	# 3 tiles below the enemy mine.
	var p2: PlayerTank = load("res://scenes/tanks/player_tank.tscn").instantiate()
	p2.player_id = 1
	_game.get_node("Entities/Players").add_child(p2)
	p2.global_position = _at(Vector2(416, 416))
	await _frames()
	p2.is_invincible = false
	var p2_hp := p2.health
	_arm(near_enemy_mine)
	_arm(own_mine)
	laying_mine._age = -100.0
	await _frames()
	var bomb_cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	bomb_cookie.setup(CookieData.CookieType.TANK_BOMB)
	_game.get_node("Entities/PowerUps").add_child(bomb_cookie)
	bomb_cookie._apply_effect(_player)
	bomb_cookie.queue_free()
	await _frames()
	check(_lm.get_mines().is_empty() and not is_instance_valid(near_enemy_mine) and not is_instance_valid(own_mine)
		and not is_instance_valid(laying_mine), "every mine goes off, the one still being laid too")
	check(_blast_count() == 3, "each in its own blast (%d)" % _blast_count())
	await _settle()
	check(_player.health == bomb_hp and not _player.is_flying and not _player.is_mine_slowed,
		"the player, within the enemy L3 mine's reach, is unhurt, not thrown, not slowed (HP %d)" % _player.health)
	check(p2.health == p2_hp and not p2.is_flying and not p2.is_mine_slowed,
		"and so is player 2, in reach and not invincible (HP %d of %d)" % [p2.health, p2_hp])
	check(not is_instance_valid(bomb_victim), "and the enemies are gone, as the bomb does")
	p2.queue_free()
	check(not _lm._fg_tile_data.has(Vector2i(14, 9)) or int(_lm._brick_damage.get(Vector2i(14, 9), 0b1111)) != 0b1111,
		"the brick beside the enemy mine breaks (a whole one keeps half), as in any mine blast")
	# The control: the same mine going off as usual_mine hurts the player.
	await _reset()
	_clear_arena()
	_place(_player, Vector2(320, 320), Vector2.UP)
	var usual_mine := _lm._spawn_mine(Vector2i(12, 9), 3, false)
	await _frames()
	_arm(usual_mine)
	await _frames()
	usual_mine.set_off()
	await _settle()
	check(_player.health < bomb_hp, "while the same mine going off on its own hurts the player (HP %d)" % _player.health)
	_player.health = bomb_hp

	# The last lay sound (0.92 s) must finish, or the engine reports its playback
	# as leaked when the test quits.
	await get_tree().create_timer(1.2).timeout
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
