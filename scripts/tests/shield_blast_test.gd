extends Node
## Headless test: the moon shield blocks an explosion/mine wave that reaches the
## tank from its shielded FRONT (no damage), but not from the other 3 sides. A
## mine's slow still applies regardless (it is applied by the mine, not the wave).

var _fail := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("  PASS: ", msg)
	else: _fail += 1; print("  FAIL: ", msg)

func _ready() -> void:
	_run()

func _mk_enemy(game: Node, tile: Vector2i, facing: Vector2, shield: bool) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.max_health = 10; e.health = 10
	e.current_direction = facing
	e.has_moon_shield = shield
	e.global_position = game.get_level_manager().tile_to_world(tile)
	return e

func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	var game: Node = load("res://scenes/game.tscn").instantiate()
	tree.root.add_child(game)
	for i in range(5):
		await tree.process_frame
	await tree.create_timer(0.2).timeout
	var spawner := game.get_node_or_null("EnemySpawner")
	if spawner:
		spawner.set_process(false); spawner.set_physics_process(false)
		for c in spawner.get_children():
			if c is Timer: (c as Timer).stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	var lm: LevelManager = game.get_level_manager()
	for y in range(8, 26):
		for x in range(8, 32):
			var t := Vector2i(x, y)
			if lm._fg_tile_data.has(t):
				lm._remove_fg_tile(t)

	print("\n[A] Shield blocks a wave from the FRONT")
	# Enemy faces UP; blast one tile ABOVE it = its shielded front.
	var e1 := _mk_enemy(game, Vector2i(20, 15), Vector2.UP, true)
	lm.spawn_explosion_blast(lm.tile_to_world(Vector2i(20, 14)), 0, true)
	await tree.process_frame
	await tree.process_frame
	check(is_instance_valid(e1) and e1.health == 10, "front-facing shield took NO damage (hp %d)" % e1.health)

	print("\n[B] Shield does NOT block a wave from behind")
	var e2 := _mk_enemy(game, Vector2i(24, 15), Vector2.UP, true)
	lm.spawn_explosion_blast(lm.tile_to_world(Vector2i(24, 16)), 0, true)  # below = behind an up-facing tank
	await tree.process_frame
	await tree.process_frame
	check(is_instance_valid(e2) and e2.health < 10, "wave from behind the shield still damaged the tank (hp %d)" % e2.health)

	print("\n[C] Control: no shield -> damaged from the front")
	var e3 := _mk_enemy(game, Vector2i(28, 15), Vector2.UP, false)
	lm.spawn_explosion_blast(lm.tile_to_world(Vector2i(28, 14)), 0, true)
	await tree.process_frame
	await tree.process_frame
	check(is_instance_valid(e3) and e3.health < 10, "unshielded tank takes front damage as before (hp %d)" % e3.health)

	print("\n[D] A mine still slows a shielded victim (speed-down kept)")
	var e4 := _mk_enemy(game, Vector2i(14, 20), Vector2.UP, true)
	var mtile := Vector2i(14, 20)
	lm._spawn_mine(mtile, 2, true)   # level 2 = blast + slow
	await tree.create_timer(0.3).timeout   # arm
	e4.global_position = lm.tile_to_world(mtile)
	await tree.create_timer(0.2).timeout
	check(is_instance_valid(e4) and e4.is_mine_slowed, "shielded tank on a level-2 mine is still slowed")

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
