extends Node
## Headless integration test for the AP weapon. Run as an override main scene:
##   Godot --headless res://scenes/test/ap_test.tscn
## Verifies the damage pool, tank pass-through, wall drilling, acceleration,
## bullet-vs-bullet survival, and the moon-shield break rule.

var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		_fail += 1
		print("  FAIL: ", msg)

func _ready() -> void:
	_run()

func _spawn_enemy(game: Node, tile: Vector2i, hp: int) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)  # deterministic harness (AP still hits via body overlap)
	e.max_health = hp
	e.health = hp
	e.global_position = game.get_level_manager().tile_to_world(tile)
	return e

func _fire_ap(tank: BaseTank, config_level: int) -> Bullet:
	var config: Dictionary = CookieData.get_weapon_fire_config("ap", config_level)
	tank._spawn_ap_bullet(config)
	# The freshly-spawned bullet is the last child of the bullets container.
	var container := tank.get_tree().get_first_node_in_group("bullets_container")
	return container.get_child(container.get_child_count() - 1) as Bullet

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

	# Deterministic harness: stop enemy spawning and clear any spawned enemies/bullets.
	var spawner := game.get_node_or_null("EnemySpawner")
	if spawner:
		spawner.set_process(false)
		spawner.set_physics_process(false)
		for c in spawner.get_children():
			if c is Timer:
				(c as Timer).stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	await tree.process_frame

	var lm: LevelManager = game.get_level_manager()
	# Clear the test area so map walls don't eat the shells' pools mid-flight.
	for y in range(10, 28):
		for x in range(6, 35):
			var t := Vector2i(x, y)
			if lm._fg_tile_data.has(t):
				lm._remove_fg_tile(t)
				lm._brick_damage.erase(t)
				lm._hard_brick_hp.erase(t)
	var player: PlayerTank = null
	for p in tree.get_nodes_in_group("players"):
		player = p
	player.set_physics_process(false)
	player.global_position = lm.tile_to_world(Vector2i(8, 15))
	player.current_direction = Vector2.RIGHT

	print("\n[A] Config: damage pool scales with level")
	var c0: Dictionary = CookieData.get_weapon_fire_config("ap", 0)
	var c3: Dictionary = CookieData.get_weapon_fire_config("ap", 3)
	check(int(c0["damage"]) == 8 and int(c3["damage"]) == 14, "pool 8 at L0, 14 at L3")
	check(float(c0["speed"]) < float(c0["max_speed"]), "launches slower than its top speed (accelerates)")

	print("\n[B] Pass-through: one shell kills a line of weak tanks")
	# Three 2-HP enemies in a row to the player's right.
	var e_a := _spawn_enemy(game, Vector2i(12, 15), 2)
	var e_b := _spawn_enemy(game, Vector2i(15, 15), 2)
	var e_c := _spawn_enemy(game, Vector2i(18, 15), 2)
	await tree.process_frame
	var bullet := _fire_ap(player, 2)  # pool 12
	check(bullet != null and bullet.pierces and bullet.damage == 12, "AP shell has pool 12, pierces=true")
	# Let it fly across all three (they're within ~10 tiles; give it time to accelerate).
	await tree.create_timer(1.2).timeout
	var dead := int(not is_instance_valid(e_a)) + int(not is_instance_valid(e_b)) + int(not is_instance_valid(e_c))
	check(dead == 3, "all three 2-HP tanks destroyed by one pool-12 shell (%d/3)" % dead)

	print("\n[C] Last tank takes the remainder; bullet stops")
	# A single 5-HP tank vs a pool-8 shell: tank dies (takes 5), 3 left, then nothing
	# else in the row -> bullet flies to the border. Use a tank that SURVIVES instead:
	var tough := _spawn_enemy(game, Vector2i(14, 12), 20)  # 20 HP > pool 8
	player.global_position = lm.tile_to_world(Vector2i(8, 12))
	player.current_direction = Vector2.RIGHT
	await tree.process_frame
	var b2 := _fire_ap(player, 0)  # pool 8
	await tree.create_timer(1.0).timeout
	check(is_instance_valid(tough) and tough.health == 12, "20-HP tank survives, takes exactly the pool (8) -> 12")
	check(not is_instance_valid(b2), "shell is spent on the surviving tank")

	print("\n[D] Bullet-vs-bullet: AP eats a normal bullet and flies on")
	player.global_position = lm.tile_to_world(Vector2i(8, 20))
	player.current_direction = Vector2.RIGHT
	await tree.process_frame
	var b3 := _fire_ap(player, 3)  # pool 14
	# Spawn an opposing normal bullet crossing its path.
	var opp: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	opp.direction = Vector2.LEFT
	opp.speed = 256.0
	opp.is_player_bullet = false
	opp.damage = 1
	opp.global_position = b3.global_position + Vector2(60, 0)
	opp.set_collision_layer_value(6, true)
	opp.set_collision_mask_value(5, true)
	game.get_node("Entities/Bullets").add_child(opp)
	await tree.create_timer(0.3).timeout
	check(not is_instance_valid(opp), "the normal bullet was destroyed by the AP")
	check(is_instance_valid(b3) and b3.damage == 13, "AP survived, pool 14 -> 13 (lost the bullet's 1 dmg)")
	if is_instance_valid(b3):
		b3._destroy()

	print("\n[E] Wall drilling: AP removes multiple bricks; low pool spends out")
	# ap_drill_tiles directly: give a row of full bricks and drill with a pool.
	var row := Vector2i(25, 5)
	var placed: Array[Vector2i] = []
	for dx in range(4):
		var t := row + Vector2i(dx, 0)
		if not lm._fg_tile_data.has(t):
			lm._place_fg_tile(t, 0x19)  # SOFT_BRICK_FULL
		placed.append(t)
	var pool_after := lm.ap_drill_tiles(placed, 6, Vector2.RIGHT)  # 6 pool, full brick = 2 each
	var removed := 0
	for t in placed:
		if not lm._fg_tile_data.has(t):
			removed += 1
	check(removed == 3 and pool_after == 0, "pool 6 drilled 3 full bricks (cost 2 each), spent out (removed=%d, pool=%d)" % [removed, pool_after])
	check(lm._fg_tile_data.has(placed[3]), "the 4th brick beyond the pool survives")

	print("\n[F] Moon shield: strong AP strips it (no damage), weak AP absorbed")
	var shielded := _spawn_enemy(game, Vector2i(20, 25), 5)
	shielded.has_moon_shield = true
	shielded.current_direction = Vector2.LEFT  # facing the incoming (from its left) shell
	var hp_before: int = shielded.health
	# Strong pool (>=6): shield stripped, tank unhurt.
	var strong: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	strong.pierces = true; strong.damage = 10; strong.is_player_bullet = true; strong.direction = Vector2.RIGHT
	strong.owner_tank = player
	strong.global_position = shielded.global_position
	game.get_node("Entities/Bullets").add_child(strong)
	await tree.process_frame
	strong._ap_on_body(shielded)
	check(not shielded.has_moon_shield, "pool-10 AP stripped the moon shield")
	check(shielded.health == hp_before, "shielded tank took no damage from the shell")

	print("\n[G] 2-wide channel: a perpendicular strip is carved for one strip's cost")
	# Two full bricks side by side across the path of an UP-travelling shell
	# (same travel-axis coord y, different x) — one strip, charged once (max=2).
	var s0 := Vector2i(30, 20)
	var s1 := Vector2i(31, 20)
	for t in [s0, s1]:
		if not lm._fg_tile_data.has(t):
			lm._place_fg_tile(t, 0x19)  # SOFT_BRICK_FULL
	var strip_pool := lm.ap_drill_tiles([s0, s1] as Array[Vector2i], 3, Vector2.UP)
	var both_gone := not lm._fg_tile_data.has(s0) and not lm._fg_tile_data.has(s1)
	check(both_gone, "both side-by-side bricks removed (2-wide channel)")
	check(strip_pool == 1, "the 2-wide strip cost only one brick's worth (pool 3 -> 1, not -1)")

	print("\n[H] AP does NOT strip an INVINCIBLE player's moon shield (bug #5)")
	player.has_moon_shield = true
	player.current_direction = Vector2.LEFT  # facing the incoming (rightward) shell
	player.is_invincible = true
	var php: int = player.health
	var e_ap: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	e_ap.pierces = true; e_ap.damage = 10; e_ap.is_player_bullet = false; e_ap.direction = Vector2.RIGHT
	e_ap.global_position = player.global_position
	game.get_node("Entities/Bullets").add_child(e_ap)
	await tree.process_frame
	e_ap._ap_on_body(player)
	check(player.has_moon_shield, "invincible player's moon shield NOT stripped by AP")
	check(player.health == php, "invincible player took no damage")
	# Control: with invincibility off, the same shell strips the shield.
	player.is_invincible = false
	var e_ap2: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	e_ap2.pierces = true; e_ap2.damage = 10; e_ap2.is_player_bullet = false; e_ap2.direction = Vector2.RIGHT
	e_ap2.global_position = player.global_position
	game.get_node("Entities/Bullets").add_child(e_ap2)
	await tree.process_frame
	e_ap2._ap_on_body(player)
	check(not player.has_moon_shield, "non-invincible player's shield IS stripped (control)")

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
