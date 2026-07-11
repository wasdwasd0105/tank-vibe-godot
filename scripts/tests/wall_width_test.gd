extends Node
## Headless test: Fire and Explosion bullets damage the full 2-tile tank width
## when they hit a wall (matching regular shots and the AP fix).

var _fail := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("  PASS: ", msg)
	else: _fail += 1; print("  FAIL: ", msg)

func _ready() -> void:
	_run()

func _last_bullet(tree: SceneTree) -> Bullet:
	var c := tree.get_first_node_in_group("bullets_container")
	return c.get_child(c.get_child_count() - 1) as Bullet

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
	var player: PlayerTank = null
	for p in tree.get_nodes_in_group("players"):
		player = p
	player.set_physics_process(false)

	print("\n[A] Fire bullet has two collision lanes (2-tile wide)")
	player.global_position = lm.tile_to_world(Vector2i(20, 22))
	player.current_direction = Vector2.UP
	player._spawn_fire_bullet(CookieData.get_weapon_fire_config("fire", 0))
	var fb := _last_bullet(tree)
	check(fb.collision_lane_offsets.size() == 2, "fire bullet samples 2 lanes")
	fb._destroy()
	await tree.process_frame

	print("\n[B] Fire bullet damages a 2-wide brick wall")
	# Clear the corridor, then a 2x2 full-brick block in the two columns the tank
	# straddles (player-tile column and the one to its right).
	for y in range(14, 24):
		for x in range(18, 24):
			var t := Vector2i(x, y)
			if lm._fg_tile_data.has(t):
				lm._remove_fg_tile(t); lm._brick_damage.erase(t)
	var cols := [Vector2i(20, 17), Vector2i(21, 17), Vector2i(20, 16), Vector2i(21, 16)]
	for t in cols:
		lm._place_fg_tile(t, 0x19)  # SOFT_BRICK_FULL (mask 0b1111)
	player.global_position = lm.tile_to_world(Vector2i(20, 22))
	player.current_direction = Vector2.UP
	player._spawn_fire_bullet(CookieData.get_weapon_fire_config("fire", 0))
	await tree.create_timer(0.5).timeout
	# Both columns should have a damaged (or removed) brick in the row that was hit.
	var col20_hit: bool = (not lm._fg_tile_data.has(Vector2i(20, 17))) or int(lm._brick_damage.get(Vector2i(20, 17), 0b1111)) != 0b1111
	var col21_hit: bool = (not lm._fg_tile_data.has(Vector2i(21, 17))) or int(lm._brick_damage.get(Vector2i(21, 17), 0b1111)) != 0b1111
	check(col20_hit and col21_hit, "both brick columns were damaged by one fire bullet")

	print("\n[C] Explosion bullet has two collision lanes (2-tile wide)")
	player.global_position = lm.tile_to_world(Vector2i(10, 10))
	player.current_direction = Vector2.RIGHT
	player._spawn_explosion_bullet(CookieData.get_weapon_fire_config("explosion", 0))
	var eb := _last_bullet(tree)
	check(eb.collision_lane_offsets.size() == 2, "explosion bullet samples 2 lanes")
	eb._destroy()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
