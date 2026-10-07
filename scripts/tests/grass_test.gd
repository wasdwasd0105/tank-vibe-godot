extends Node
## Headless test for grass, as Tank.exe's (docs/grass_original_spec.md): its
## pictures, solid over the tanks but for their own holes; what draws under it
## and what over it; and that tanks and shells pass through it. Run as an
## override main scene:
##   Godot --headless res://scenes/test/grass_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank

const GRASS := 0x09
const BURNED_GRASS := 0x0D
const BRICK := 0x19


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _frames(count: int = 1) -> void:
	for i in count:
		await get_tree().physics_frame


## Its draw order: the z it ends up with, its own added to its parents' while
## it counts from theirs.
func _abs_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node:
		if node is CanvasItem:
			z += (node as CanvasItem).z_index
			if not (node as CanvasItem).z_as_relative:
				break
		node = node.get_parent()
	return z


## Whether [param a] draws over [param b]: the higher z, or at the same z the
## later in the tree.
func _over(a: CanvasItem, b: CanvasItem) -> bool:
	var za := _abs_z(a)
	var zb := _abs_z(b)
	if za != zb:
		return za > zb
	return a.is_greater_than(b)


## Whether [param item] and every parent of it draw at full strength.
func _solid(item: CanvasItem) -> bool:
	var node: Node = item
	while node:
		if node is CanvasItem and ((node as CanvasItem).modulate.a < 1.0 or (node as CanvasItem).self_modulate.a < 1.0):
			return false
		node = node.get_parent()
	return true


## The share of [param tex]'s pixels that are see-through.
func _holes(tex: Texture2D) -> float:
	var img := tex.get_image()
	var clear := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a < 0.5:
				clear += 1
	return float(clear) / float(img.get_width() * img.get_height())


func _put(cell: Vector2i, code: int) -> Sprite2D:
	if _lm._fg_tile_data.has(cell):
		_lm._remove_fg_tile(cell)
	_lm._brick_damage.erase(cell)
	_lm._hard_brick_hp.erase(cell)
	_lm._place_fg_tile(cell, code)
	return _lm._fg_tile_data[cell]["sprite"]


func _clear_field() -> void:
	_lm._clear_fire()
	for cell in _lm._fg_tile_data.keys():
		_lm._remove_fg_tile(cell)
	_lm._brick_damage.clear()
	_lm._hard_brick_hp.clear()
	for cell in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(cell)


## The centre of a tank whose footprint's top-left is the field's tile [param tile].
func _spot(tile: Vector2i) -> Vector2:
	return _lm.global_position + Vector2(tile + Vector2i.ONE) * LevelManager.TILE_SIZE


func _enemy(tile: Vector2i) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _spot(tile)
	e.is_materializing = false
	e._materialize_timer = 0.0
	e.visible = true
	e.max_health = 10
	e.health = 10
	return e


## The newest child of [param parent] that [param test] accepts, or null.
func _newest(parent: Node, test: Callable) -> Node:
	for i in range(parent.get_child_count() - 1, -1, -1):
		var n := parent.get_child(i)
		if test.call(n):
			return n
	return null


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	seed(20261008)
	ThemeManager.load_theme(ThemeManager.GAME_THEME)
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
	var effects: Node = _game.get_node("Entities/Effects")

	print("\n[A] Its pictures: solid, but for their own holes, a quarter of green grass and half of burned")
	var green := _put(Vector2i(10, 10), GRASS)
	var burned := _put(Vector2i(11, 10), BURNED_GRASS)
	check(_solid(green) and _solid(burned), "drawn at full strength, not faded")
	var green_holes := _holes(green.texture)
	var burned_holes := _holes(burned.texture)
	check(green_holes > 0.2 and green_holes < 0.35 and burned_holes > 0.45 and burned_holes < 0.6,
		"the original's pictures: %d%% of green grass see-through, %d%% of burned" % [green_holes * 100, burned_holes * 100])
	var looks := []
	for code in range(GRASS, GRASS + 4):
		looks.append(_put(Vector2i(14 + code - GRASS, 10), code).texture)
	check(looks[0] != looks[1] and looks[1] != looks[2] and looks[2] != looks[3] and looks[0] != looks[3],
		"its 4 pictures picked by the map's code")
	_lm._convert_grass_to_burned(Vector2i(15, 10))
	check(_lm._fg_tile_data[Vector2i(15, 10)]["sprite"].texture == _lm._grass_texture(BURNED_GRASS + 1),
		"burned, it keeps its picture's number")

	print("\n[B] Under the grass: tanks, shells, mines, the base, a side's fire, a shot's end, a tank appearing or blowing up")
	var enemy := _enemy(Vector2i(20, 12))
	_player.global_position = _spot(Vector2i(24, 12))
	await _frames(2)
	var grass_at := _put(Vector2i(20, 12), GRASS)
	check(_over(grass_at, enemy) and _over(grass_at, _player), "over the tanks, an enemy's and a player's")
	var shell: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	_game.get_node("Entities/Bullets").add_child(shell)
	shell.global_position = _spot(Vector2i(20, 16))
	shell.set_physics_process(false)
	check(_over(grass_at, shell), "over the shells")
	_player.is_invincible = false
	check(_lm.try_place_mine(_player, 0), "a mine laid on open ground")
	await _frames(2)  # it joins the field at the frame's end
	var mine: Mine = _lm.get_mines().back() if not _lm.get_mines().is_empty() else null
	check(mine != null and _over(grass_at, mine), "over the mines")
	_player.is_invincible = true
	check(_over(grass_at, _game.eagle), "over the base")
	_lm.ignite_fire_patch(Vector2i(26, 18), true, 0, 0)
	await _frames(2)
	var side_fire: GroundFire = _lm.fires_at(Vector2i(26, 18))[0] if not _lm.fires_at(Vector2i(26, 18)).is_empty() else null
	check(side_fire != null and _over(grass_at, side_fire), "over a side's fire")
	Bullet.show_end(tree, "regular", _spot(Vector2i(20, 12)), Vector2.UP, [0.0])
	var shot_end := _newest(effects, func(n: Node) -> bool: return n is HitEffect)
	check(shot_end != null and _over(grass_at, shot_end) and _over(shot_end, enemy), "over a shot's end, which is over the tank it hit")
	var flash: Node2D = load("res://scenes/effects/explosion.tscn").instantiate()
	flash.scale = Vector2.ONE
	effects.add_child(flash)
	check(_over(grass_at, flash), "over a shot's built-in flash (a theme without hit pictures)")
	SpawnBurst.spawn_at(tree, _spot(Vector2i(20, 12)))
	var burst := _newest(effects, func(n: Node) -> bool: return n is SpawnBurst)
	check(burst != null and _over(grass_at, burst) and _over(burst, enemy), "over a tank appearing, which is over the tanks")
	enemy._spawn_explosion()
	var boom := _newest(effects, func(n: Node) -> bool: return n is HitEffect)
	check(boom != null and boom != shot_end and _over(grass_at, boom) and _over(boom, enemy), "over a tank's explosion")
	var big_flash: Node2D = load("res://scenes/effects/explosion.tscn").instantiate()
	big_flash.scale = Vector2(2, 2)
	effects.add_child(big_flash)
	check(_over(grass_at, big_flash), "over a tank's built-in explosion")

	print("\n[C] Over the grass: burning grass, blasts, items, words, a thrown tank")
	var stubble := _put(Vector2i(22, 12), BURNED_GRASS)
	var grass_fire := _lm._new_fire(Vector2i(22, 12), -1, -1, 0, 4000.0, GroundFire.ARM, 0, true)
	await _frames(2)
	check(_over(grass_fire, stubble) and _over(grass_fire, grass_at) and _over(grass_fire, enemy),
		"burning grass over the burned grass it's on, the grass and the tanks")
	_lm.spawn_explosion_blast(_spot(Vector2i(20, 20)), 0, true)
	await _frames(2)
	var blast := _newest(effects, func(n: Node) -> bool: return n is ExplosionBlast)
	check(blast != null and _over(blast, grass_at), "a blast")
	var item: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	item.setup(CookieData.CookieType.INVINCIBLE_HELMET)
	_game.powerups_container.add_child(item)
	item.global_position = _spot(Vector2i(20, 12))
	check(_over(item, grass_at) and _over(item, grass_fire) and _over(item, blast),
		"an item, over the burning grass and the blasts too")
	var words := PickupText.spawn(effects, CookieData.CookieType.INVINCIBLE_HELMET, _spot(Vector2i(20, 12)))
	check(words != null and _over(words, grass_at) and _over(words, item), "an item's words, over the item")
	var kill := KillText.spawn(effects, 100, 1, _spot(Vector2i(20, 12)))
	check(kill != null and _over(kill, grass_at) and _over(kill, item), "a kill's words")
	enemy.launch_mine_fly(1, enemy.global_position + Vector2(0, 40))
	check(_over(enemy, grass_at) and _over(enemy, item), "a thrown tank, over everything on the field")
	var panel: CanvasItem = _game.hud.get_node("LeftPanel")
	check(_over(panel, enemy) and _over(panel, words) and _over(panel, kill) and _over(panel, item),
		"and the HUD's side panels over all of it, words spilling off the field too")
	item.queue_free()
	_lm._clear_fire()

	print("\n[D] Online: a client shows a tank's explosion and a shot's end under the grass too")
	var client := NetClientWorld.new()
	client.setup(null, null, null, {}, effects)
	client._play([NetWorld.EV_HIT, "tank", 400.0, 400.0])
	var c_boom := _newest(effects, func(n: Node) -> bool: return n is HitEffect)
	client._play([NetWorld.EV_HIT, "regular", 420.0, 400.0])
	var c_shot := _newest(effects, func(n: Node) -> bool: return n is HitEffect)
	check(c_boom != null and c_shot != null and c_boom != c_shot and _over(grass_at, c_boom) and _over(grass_at, c_shot),
		"themed pictures")
	client._play([NetWorld.EV_EXPLOSION, 400.0, 440.0, 2.0])
	var c_big: Node = effects.get_child(effects.get_child_count() - 1)
	client._play([NetWorld.EV_EXPLOSION, 440.0, 440.0, 1.0])
	var c_small: Node = effects.get_child(effects.get_child_count() - 1)
	check(c_big != c_small and _over(grass_at, c_big) and _over(grass_at, c_small), "built-in flashes")
	client.free()

	print("\n[E] Tanks and shells go through it")
	enemy.queue_free()
	_clear_field()
	for x in range(12, 20):
		for y in range(10, 12):
			_put(Vector2i(x, y), GRASS)
	_put(Vector2i(22, 10), BRICK)
	_put(Vector2i(22, 11), BRICK)
	_player.global_position = _spot(Vector2i(10, 10))
	_player._turn_to(Vector2.RIGHT)
	_player.global_position = _spot(Vector2i(10, 10))
	await _frames(2)
	check(not _player.test_move(_player.global_transform, Vector2(64, 0)), "a tank drives into the grass")
	_player.can_shoot = true
	_player.shoot_regular()
	await tree.create_timer(1.5).timeout  # 320 px at 256 px/s
	var brick_hit := not _lm._fg_tile_data.has(Vector2i(22, 10)) or not _lm._fg_tile_data.has(Vector2i(22, 11)) \
		or int(_lm._brick_damage.get(Vector2i(22, 10), 15)) != 15 or int(_lm._brick_damage.get(Vector2i(22, 11), 15)) != 15
	var grass_left := 0
	for x in range(12, 20):
		for y in range(10, 12):
			grass_left += 1 if _lm._is_green_grass(Vector2i(x, y)) else 0
	check(brick_hit and grass_left == 16, "a shell flies over 8 tiles of grass to the brick behind, leaving the grass")

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
