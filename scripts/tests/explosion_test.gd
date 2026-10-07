extends Node
## Headless test for the explosion weapon and its blast, as Tank.exe's
## (docs/explosion_weapon_original_spec.md). Run as override main scene:
##   Godot --headless res://scenes/test/explosion_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank
## The open middle of the field: tile (20, 12)'s top-left corner.
var _corner := Vector2i(20, 12)

## The original's blast on open ground, per tile per mille of its power (rows
## top to bottom, columns left to right) and the fireball piece each tile
## shows (-1 none), worked out from its code (the research's model.py).
const OPEN_L0: Array = [
	[0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 152, 388, 388, 152, 0, 0], [0, 0, 388, 832, 832, 388, 0, 0],
	[0, 0, 388, 832, 832, 388, 0, 0], [0, 0, 152, 388, 388, 152, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0]]
const PIECES_L0: Array = [
	[-1, -1, -1, -1, -1, -1, -1, -1], [-1, -1, -1, -1, -1, -1, -1, -1],
	[-1, -1, 0, 4, 4, 2, -1, -1], [-1, -1, 4, 4, 4, 4, -1, -1],
	[-1, -1, 4, 4, 4, 4, -1, -1], [-1, -1, 6, 4, 4, 8, -1, -1],
	[-1, -1, -1, -1, -1, -1, -1, -1], [-1, -1, -1, -1, -1, -1, -1, -1]]
const OPEN_L3: Array = [
	[0, 0, 36, 98, 98, 36, 0, 0], [0, 120, 286, 372, 372, 286, 120, 0],
	[36, 286, 510, 646, 646, 510, 286, 36], [98, 372, 646, 901, 901, 646, 372, 98],
	[98, 372, 646, 901, 901, 646, 372, 98], [36, 286, 510, 646, 646, 510, 286, 36],
	[0, 120, 286, 372, 372, 286, 120, 0], [0, 0, 36, 98, 98, 36, 0, 0]]
const PIECES_L3: Array = [
	[-1, -1, 0, 1, 1, 2, -1, -1], [-1, 4, 4, 4, 4, 4, 4, -1],
	[0, 4, 4, 4, 4, 4, 4, 2], [3, 4, 4, 4, 4, 4, 4, 5],
	[3, 4, 4, 4, 4, 4, 4, 5], [6, 4, 4, 4, 4, 4, 4, 8],
	[-1, 4, 4, 4, 4, 4, 4, -1], [-1, -1, 6, 7, 7, 8, -1, -1]]

const BRICK := 0x19
const HARD_BRICK := 0x29
const IRON := 0x39
const SUPER := 0x3D
const BURNED_GRASS := 0x0D


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


## World position of the tile corner [param offset] tiles from the middle one.
func _at(offset: Vector2 = Vector2.ZERO) -> Vector2:
	return _lm.global_position + (Vector2(_corner) + offset) * LevelManager.TILE_SIZE


func _frames(count: int = 1) -> void:
	for i in count:
		await get_tree().process_frame


## A blast of [param level] centred on the middle corner, built at once: a
## player's unless [param enemy]'s.
func _blast(level: int, enemy: bool = false) -> ExplosionBlast:
	var blast := ExplosionBlast.new()
	blast.setup(level, not enemy, _lm, false, -1, false)
	blast.origin = _corner - Vector2i(4, 4)
	_game.get_node("Entities/Effects").add_child(blast)
	return blast


## Runs [param blast] through to its end (its frames one by one), and lets what
## it did settle.
func _play_out(blast: ExplosionBlast) -> void:
	while is_instance_valid(blast) and not blast.is_queued_for_deletion():
		await get_tree().process_frame
	await _frames(2)


func _enemy(offset: Vector2, hp: int = 10, facing: Vector2 = Vector2.UP) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _at(offset)
	e.max_health = hp
	e.health = hp
	e.current_direction = facing
	e.is_materializing = false
	e._materialize_timer = 0.0
	e.visible = true
	return e


func _place(cell: Vector2i, code: int) -> void:
	_lm._remove_fg_tile(cell)
	_lm._brick_damage.erase(cell)
	_lm._hard_brick_hp.erase(cell)
	_lm._place_fg_tile(cell, code)


func _clear_area() -> void:
	for tile in _lm._fg_tile_data.keys():
		if tile.x >= 8 and tile.x <= 34 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		if tile.x >= 8 and tile.x <= 34 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_bg_tile(tile)


func _grid_matches(blast: ExplosionBlast, heat: Array, pieces: Array) -> bool:
	for y in 8:
		for x in 8:
			if blast._tile_heat[x * 8 + y] != int(heat[y][x]) or blast._tile_piece[x * 8 + y] != int(pieces[y][x]):
				return false
	return true


func _drawn(blast: ExplosionBlast) -> int:
	return blast._tile_piece.count(-1) * -1 + 64


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	await _frames(5)
	await tree.create_timer(0.2).timeout
	_lm = _game.get_level_manager()
	_game.get_node("EnemySpawner").spawn_timer.stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	for p in tree.get_nodes_in_group("players"):
		_player = p
	_player.global_position = _lm.global_position + Vector2(64, 900)  # out of the way
	_clear_area()
	await _frames(2)

	print("\n[A] The heat grid on open ground: the original's, tile for tile")
	var b0 := _blast(0)
	var b3 := _blast(3)
	await _frames()
	check(_grid_matches(b0, OPEN_L0, PIECES_L0), "level 0: centre tiles 832 per mille, 16 tiles drawn, its pieces")
	check(_grid_matches(b3, OPEN_L3, PIECES_L3), "level 3: centre tiles 901 per mille, 52 tiles drawn, its pieces")
	check(b0.power == 250 and b0.falloff == 60 and b3.power == 325 and b3.falloff == 45, "power 250 / falloff 60, +25 / -5 a level")
	var counts := []
	for level in 4:
		var b := _blast(level)
		await _frames()
		counts.append(_drawn(b))
		b.queue_free()
	check(counts == [16, 24, 32, 52], "tiles drawn by level: %s (16, 24, 32, 52)" % str(counts))
	b0.queue_free()
	b3.queue_free()
	await _frames(2)

	print("\n[B] Where it goes: the tile corner nearest what went off")
	var near := ExplosionBlast.grid_origin(Vector2(_corner) * 32.0 + Vector2(10, -12), ExplosionBlast.SHELL_SIZE)
	var tie := ExplosionBlast.grid_origin(Vector2(_corner) * 32.0 + Vector2(16, 16), ExplosionBlast.SHELL_SIZE)
	var mine := ExplosionBlast.grid_origin(Vector2(_corner) * 32.0, ExplosionBlast.MINE_SIZE)
	var tank := ExplosionBlast.grid_origin(Vector2(_corner) * 32.0 + Vector2(8, 8), ExplosionBlast.TANK_SIZE)
	check(near == _corner - Vector2i(4, 4) and tie == _corner + Vector2i(1, 1) - Vector2i(4, 4),
		"a shell's: the nearest corner, an exact half going right and down (%s, %s)" % [near, tie])
	check(mine == _corner - Vector2i(4, 4), "a mine's (on a corner): centred on it")
	check(tank == _corner - Vector2i(4, 4), "a landing tank's: by its own edges")
	var edge := ExplosionBlast.grid_origin(Vector2(40, 40), ExplosionBlast.SHELL_SIZE)
	check(edge == Vector2i(-2, -2), "near the field's top-left edge, a tile further in (the original's truncation): %s" % str(edge))

	print("\n[C] Its frames: 15 ms each, the hotter tiles first, gone after 15")
	var timed := _blast(0)
	var centre := 3 * 8 + 3
	var first_shown := -1
	var shown_by_frame: Array = []
	while is_instance_valid(timed) and not timed.is_queued_for_deletion():
		await tree.process_frame
		if not is_instance_valid(timed):
			break
		if first_shown < 0 and timed._sprites[centre].visible:
			first_shown = timed._frame
		shown_by_frame.append(timed._sprites.filter(func(s: Sprite2D) -> bool: return s.visible).size())
	check(first_shown == 4, "level 0's centre tile first shows on frame 4, 60 ms on (frame %d)" % first_shown)
	var slice := ExplosionBlast._slices[0][4] as AtlasTexture
	check(slice != null and slice.region == Rect2(16, 16, 16, 16), "a tile shows its own 16 px piece of the fireball's frame")
	check(not is_instance_valid(timed) or timed.is_queued_for_deletion(), "gone after its 15 frames")

	print("\n[D] Tanks: by the hottest tile they're on, in one hit as the wave passes")
	var rows := [[Vector2(0, 0), 2], [Vector2(2, 0), 1], [Vector2(3, 0), 0], [Vector2(2, 2), 1], [Vector2(3, 3), 0]]
	var got: Array = []
	var enemies: Array = []
	for row: Array in rows:
		enemies.append(_enemy(row[0]))
	await _frames()
	var hurt := _blast(0)
	await _frames(3)
	var early := (enemies[0] as EnemyTank).health
	await _play_out(hurt)
	for e: EnemyTank in enemies:
		got.append(10 - e.health)
	check(early == 10, "nothing before the wave gets there")
	check(got == rows.map(func(r: Array) -> int: return r[1]),
		"level 0: 2 at the centre, 1 two tiles out, straight or diagonally, none three out (%s)" % str(got))
	check((enemies[0] as EnemyTank)._hits_taken == 1, "one hit, however many points (one downgrade)")
	# A second blast within 0.1875 s of the first doesn't hurt it again.
	var again := enemies[0] as EnemyTank
	again.health = 10
	again.blast_immunity = 0.0
	var first := _blast(0)
	await _play_out(first)
	var second := _blast(0)
	again.blast_immunity = ExplosionBlast.BLAST_IMMUNITY
	await _play_out(second)
	check(again.health == 8, "no second hit while blast-immune (hp %d)" % again.health)
	for e: EnemyTank in enemies:
		e.queue_free()
	await _frames()
	# Level 3 at the centre: 3.
	var big := _enemy(Vector2.ZERO)
	await _frames()
	await _play_out(_blast(3))
	check(big.health == 7, "level 3 at the centre: 3 (hp %d)" % big.health)
	big.queue_free()

	print("\n[E] Sides")
	_player.global_position = _at(Vector2.ZERO)
	_player.is_invincible = false
	var php := _player.health
	await _frames()
	await _play_out(_blast(3))
	check(_player.health == php, "a player's blast never hurts a player")
	var on_both := _enemy(Vector2(-2, 0))
	_player.speed_level = 2
	_player.weapon_level = 2
	var levels_before := _player.speed_level + _player.weapon_level
	var neutral := ExplosionBlast.new()
	neutral.setup(1, true, _lm, true)
	neutral.origin = _corner - Vector2i(4, 4)
	_game.get_node("Entities/Effects").add_child(neutral)
	await _play_out(neutral)
	check(_player.health < php and on_both.health < 10, "a landing's (neither side's) hurts both")
	check(levels_before - _player.speed_level - _player.weapon_level == 1,
		"its 3 points in one hit: the player loses one level for it, not three")
	on_both.queue_free()
	_player.health = php
	await tree.create_timer(PlayerTank.HIT_GRACE + 0.1).timeout
	_player.is_invincible = false
	var spared := ExplosionBlast.new()
	spared.setup(2, false, _lm, false, -1, true)
	spared.origin = _corner - Vector2i(4, 4)
	_game.get_node("Entities/Effects").add_child(spared)
	await _play_out(spared)
	check(_player.health == php, "a mine a player's bomb set off spares the players")
	_player.global_position = _lm.global_position + Vector2(64, 900)
	# Their shells and mines too: an enemy's blast takes a player's shell and sets
	# off a player's mine; one from a mine a player's bomb set off leaves them be.
	var kept: Array = []
	for spare in [false, true]:
		var own_shell: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
		own_shell.is_player_bullet = true
		own_shell.direction = Vector2.LEFT
		_game.get_node("Entities/Bullets").add_child(own_shell)
		own_shell.set_physics_process(false)
		own_shell.global_position = _at(Vector2(0.5, 0.5))
		var own_mine := _lm._spawn_mine(_corner + Vector2i(1, -1), 0, true, 0)
		await _frames()
		own_mine._age = Mine.ARM_TIME + 0.001
		var by_enemy := ExplosionBlast.new()
		by_enemy.setup(2, false, _lm, false, -1, spare)
		by_enemy.origin = _corner - Vector2i(4, 4)
		_game.get_node("Entities/Effects").add_child(by_enemy)
		await _play_out(by_enemy)
		kept.append([is_instance_valid(own_shell) and not own_shell._destroyed, _lm.has_mine(_corner + Vector2i(1, -1))])
		if is_instance_valid(own_shell):
			own_shell.queue_free()
		_lm._clear_mines()
		await tree.create_timer(0.3).timeout
	check(kept[0] == [false, false], "an enemy's blast takes a player's shell and sets off a player's mine (%s)" % str(kept[0]))
	check(kept[1] == [true, true], "a mine a player's bomb set off leaves the players' shells and mines be (%s)" % str(kept[1]))

	print("\n[F] A moon shield facing the centre saves its tank from that side's tiles")
	# Below the centre, facing up: every tile it's on is covered.
	var covered := _enemy(Vector2(0, 1), 10, Vector2.UP)
	covered.has_moon_shield = true
	var heard := int(SoundManager._last_played.get(&"shield_absorb", 0))
	await _frames()
	await _play_out(_blast(0))
	check(covered.health == 10, "below the centre, its shield facing up: no damage (hp %d)" % covered.health)
	check(int(SoundManager._last_played.get(&"shield_absorb", 0)) > heard, "and the shield's sound")
	covered.queue_free()
	var turned := _enemy(Vector2(0, 1), 10, Vector2.DOWN)
	turned.has_moon_shield = true
	await _frames()
	await _play_out(_blast(0))
	check(turned.health < 10, "facing away: hurt (hp %d)" % turned.health)
	turned.queue_free()
	await _frames()

	print("\n[G] Walls: their quarters shadow what's behind; the blast changes the first it reaches")
	# An iron wall right of the centre, two tiles out: the tiles beyond it get nothing.
	for y in range(-4, 4):
		_place(_corner + Vector2i(2, y), IRON)
	var shaded := _blast(3)
	await _frames()
	var beyond := 0
	for y in 8:
		beyond += shaded._tile_heat[7 * 8 + y]
	check(beyond == 0 and shaded._tile_heat[6 * 8 + 3] > 0, "nothing beyond the iron wall; the wall's own tiles lit")
	await _play_out(shaded)
	check(_lm._fg_tile_data.has(_corner + Vector2i(2, 0)), "a level 3 blast leaves iron be")
	_clear_area()
	# Sean's rule: the players' level 3 shell breaks the iron it hits, its blast
	# none. Fired straight at an iron wall two layers thick, it goes off at its
	# face: the two tiles in its way go, a hole a tank wide and one layer deep,
	# and the tiles beside them, in its blast, stay.
	for x in range(-3, 4):
		for y in [-3, -4]:
			_place(_corner + Vector2i(x, y), IRON)
	_shot(3, Vector2(0, 1), Vector2.UP)
	await tree.create_timer(0.8).timeout
	var holes := []
	var behind_holes := 0
	for x in range(-3, 4):
		holes.append(0 if _lm._fg_tile_data.has(_corner + Vector2i(x, -3)) else 1)
		behind_holes += 0 if _lm._fg_tile_data.has(_corner + Vector2i(x, -4)) else 1
	check(holes == [0, 0, 1, 1, 0, 0, 0] and behind_holes == 0,
		"a level 3 shot at an iron wall: the two tiles in its way go, the layer behind stays (%s)" % str(holes))
	_shot(2, Vector2(2, 1), Vector2.UP)
	await tree.create_timer(0.8).timeout
	check(_lm._fg_tile_data.has(_corner + Vector2i(1, -3)) and _lm._fg_tile_data.has(_corner + Vector2i(2, -3)),
		"a level 2 shot leaves iron be")
	var shooter := _enemy(Vector2(2, 2))
	await _frames()
	shooter.active_explosion_bullets = 0
	shooter._spawn_explosion_bullet(CookieData.get_weapon_fire_config("explosion", 3))
	await tree.create_timer(0.8).timeout
	check(_lm._fg_tile_data.has(_corner + Vector2i(1, -3)) and _lm._fg_tile_data.has(_corner + Vector2i(2, -3)),
		"an enemy's level 3 shot leaves iron be: the players' gun only")
	shooter.queue_free()
	_clear_area()
	# At bricks with iron either side, in its blast: the bricks go, the iron stays.
	for x in [-2, 1]:
		_place(_corner + Vector2i(x, -3), IRON)
	for x in [-1, 0]:
		_place(_corner + Vector2i(x, -3), BRICK)
	_shot(3, Vector2(0, 1), Vector2.UP)
	await tree.create_timer(0.8).timeout
	check(not _lm._fg_tile_data.has(_corner + Vector2i(-1, -3)) and not _lm._fg_tile_data.has(_corner + Vector2i(0, -3))
		and _lm._fg_tile_data.has(_corner + Vector2i(-2, -3)) and _lm._fg_tile_data.has(_corner + Vector2i(1, -3)),
		"a level 3 shot at bricks with iron beside them: the bricks go, the iron in its blast stays")
	_clear_area()
	# Bricks and the rest, on tiles it reaches.
	var cells := {
		Vector2i(1, -1): BRICK,          # above the diagonal: keeps its top half
		Vector2i(-2, 0): BRICK,          # below it: keeps its left half
		Vector2i(0, 1): HARD_BRICK,      # loses a point
		Vector2i(-1, -2): BURNED_GRASS,  # goes
		Vector2i(1, 1): SUPER,           # stays
	}
	for offset: Vector2i in cells:
		_place(_corner + offset, cells[offset])
	_place(_corner + Vector2i(-1, 1), BRICK)
	_lm._brick_damage[_corner + Vector2i(-1, 1)] = 0b0011
	_lm._update_brick_visual(_corner + Vector2i(-1, 1), 0b0011)  # half a brick: goes
	var hp_before: int = _lm._hard_brick_hp.get(_corner + Vector2i(0, 1), 0)
	await _play_out(_blast(1))
	check(int(_lm._brick_damage.get(_corner + Vector2i(1, -1), -1)) == 0b1100, "a whole brick above the grid's diagonal keeps its top half")
	check(int(_lm._brick_damage.get(_corner + Vector2i(-2, 0), -1)) == 0b1010, "on or below it, its left half")
	check(not _lm._fg_tile_data.has(_corner + Vector2i(-1, 1)), "half a brick goes")
	check(int(_lm._hard_brick_hp.get(_corner + Vector2i(0, 1), 0)) == hp_before - 1, "a hard brick loses a point")
	check(not _lm._fg_tile_data.has(_corner + Vector2i(-1, -2)), "burned grass goes")
	check(_lm._fg_tile_data.has(_corner + Vector2i(1, 1)), "super steel stays")
	_clear_area()

	print("\n[H] Shells on its burning tiles")
	var theirs: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	theirs.is_player_bullet = false
	theirs.direction = Vector2.LEFT
	_game.get_node("Entities/Bullets").add_child(theirs)
	theirs.set_physics_process(false)
	theirs.global_position = _at(Vector2(0.5, 0.5))
	await _frames()
	await _play_out(_blast(0))
	check(not is_instance_valid(theirs) or theirs._destroyed, "an enemy's shell on them is gone")

	print("\n[I] The shell: as the original's, its heat by level")
	var configs: Array = []
	for level in 4:
		var c := CookieData.get_weapon_fire_config("explosion", level)
		configs.append([c["damage"], c["max_in_flight"]])
	var c0 := CookieData.get_weapon_fire_config("explosion", 0)
	check(configs == [[1, 2], [1, 3], [2, 4], [2, 4]], "heat 1, 1, 2, 2 and 2, 3, 4, 4 in flight (%s)" % str(configs))
	check(is_equal_approx(c0["speed"], 355.6) and is_equal_approx(c0["accel"], 948.0) and is_equal_approx(c0["max_speed"], 711.0),
		"leaves at 355.6 px/s, speeding up by 948 a second to 711")
	# A direct hit: the lesser of its heat and the tank's health, then its blast too.
	var struck := _enemy(Vector2(0, -3))
	await _frames()
	var shell := _shot(0, Vector2(0, 1), Vector2.UP)
	await tree.create_timer(0.5).timeout
	check(struck.health == 10 - 1 - 2, "level 0 on a tank: 1 from the shell and 2 from its blast (hp %d)" % struck.health)
	struck.queue_free()
	# A level 2 shell (2) through a tank of 1 flies on, and goes off further on.
	var weak := _enemy(Vector2(0, -3), 1)
	var behind := _enemy(Vector2(0, -7), 10)
	await _frames()
	shell = _shot(2, Vector2(0, 1), Vector2.UP)
	await tree.create_timer(0.8).timeout
	check(not is_instance_valid(weak) or weak.health <= 0, "a level 2 shell finishes a tank of 1")
	check(is_instance_valid(behind) and behind.health < 10, "and flies on into the next (hp %d)" % (behind.health if is_instance_valid(behind) else -1))
	for e in [weak, behind]:
		if is_instance_valid(e):
			e.queue_free()
	# Walls: a whole brick goes whole to a level 2 shell, which ends there; half a
	# brick breaks and it flies on.
	_place(_corner + Vector2i(0, -3), BRICK)
	_place(_corner + Vector2i(-1, -3), BRICK)
	shell = _shot(2, Vector2(0, 1), Vector2.UP)
	var whole_left := [true]
	var fired := shell != null
	if fired:
		shell.tree_exiting.connect(func() -> void:
			whole_left[0] = _lm._fg_tile_data.has(_corner + Vector2i(0, -3)) or _lm._fg_tile_data.has(_corner + Vector2i(-1, -3)))
	await tree.create_timer(0.6).timeout
	check(fired and not whole_left[0],
		"a level 2 shell breaks whole bricks whole, and ends there (before its blast gets to them)")
	_clear_area()
	_place(_corner + Vector2i(0, -2), BRICK)
	_place(_corner + Vector2i(-1, -2), BRICK)
	for cell: Vector2i in [_corner + Vector2i(0, -2), _corner + Vector2i(-1, -2)]:
		_lm._brick_damage[cell] = 0b0011
		_lm._update_brick_visual(cell, 0b0011)
	var far_wall := _corner + Vector2i(0, -8)
	_place(far_wall, BRICK)
	_place(far_wall + Vector2i(-1, 0), BRICK)
	shell = _shot(2, Vector2(0, 1), Vector2.UP)
	await tree.create_timer(0.9).timeout
	check(not _lm._fg_tile_data.has(_corner + Vector2i(0, -2))
		and (not _lm._fg_tile_data.has(far_wall) or int(_lm._brick_damage.get(far_wall, 0b1111)) != 0b1111),
		"through half bricks with heat to spare, on to the next wall")
	_clear_area()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


## A player's explosion shot of [param level], fired from [param offset] tiles
## off the middle corner, going [param way]: flying here as fired.
func _shot(level: int, offset: Vector2, way: Vector2) -> Bullet:
	var config := CookieData.get_weapon_fire_config("explosion", level)
	_player.current_direction = way
	_player.global_position = _at(offset) - way * BaseTank.TANK_SIZE * 0.5
	_player.active_explosion_bullets = 0
	_player._spawn_explosion_bullet(config)
	var fired: Bullet = null
	for node in get_tree().get_nodes_in_group(NetWorld.GROUP):
		if node is Bullet and (node as Bullet).explodes and not (node as Bullet)._destroyed:
			fired = node
	_player.global_position = _lm.global_position + Vector2(64, 900)
	return fired
