extends Node
## Headless integration test for the mine weapon. Run as an override main scene:
##   Godot --headless res://scenes/test/mine_test.tscn
## Drives placement, arming, contact-trigger, blast, the fly effect and the slow.
##
## Test enemies run with physics (AI) disabled so the harness is deterministic —
## the mine detects them via the physics-server overlap query regardless, and the
## fly is stepped manually. (Enemy AI is exercised by the real game, not here.)

var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		_fail += 1
		print("  FAIL: ", msg)

func _ready() -> void:
	_run()

func _spawn_enemy(game: Node, tile: Vector2i, hp: int = 10) -> EnemyTank:
	var scene := load("res://scenes/tanks/enemy_tank.tscn")
	var e: EnemyTank = scene.instantiate()
	e.tank_type_id = 1
	game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)  # no AI in the test harness
	var lm: LevelManager = game.get_level_manager()
	e.global_position = lm.tile_to_world(tile)
	e.max_health = hp
	e.health = hp
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

	var lm: LevelManager = game.get_level_manager()
	var player: PlayerTank = null
	for p in tree.get_nodes_in_group("players"):
		player = p
	check(lm != null and player != null, "level_manager + player available")

	var base_tile := Vector2i(20, 10)
	player.global_position = lm.tile_to_world(base_tile)
	player.current_direction = Vector2.UP
	player.is_invincible = false

	print("\n[A] Laying a mine behind the tank")
	var laid: bool = lm.try_place_mine(player.global_position, Vector2.UP, 1, true)
	check(laid, "mine placed on a free tile")
	check(lm.has_mine(base_tile + Vector2i(0, 1)), "mine laid on the tile behind an up-facing tank")

	print("\n[B] One mine per tile — second lay uses a different tile")
	var n_before := lm._mine_tiles.size()
	var again: bool = lm.try_place_mine(player.global_position, Vector2.UP, 1, true)
	check(again and lm._mine_tiles.size() == n_before + 1, "second mine went to a different tile")

	print("\n[C] Arm delay + own side never triggers")
	lm._clear_mines()
	var mtile := Vector2i(20, 14)
	lm._spawn_mine(mtile, 1, true)  # player mine
	await tree.process_frame
	var mine = lm._mine_tiles[mtile]
	check(is_instance_valid(mine) and not mine._armed, "mine starts un-armed")
	player.global_position = lm.tile_to_world(mtile)   # owner (player) on a player mine
	await tree.create_timer(0.4).timeout
	check(lm._mine_tiles.has(mtile), "player mine ignores the player (same side)")
	player.global_position = lm.tile_to_world(base_tile)

	print("\n[D] Enemy contact detonates (level 1: blast, no fly)")
	lm._clear_mines()
	var enemy := _spawn_enemy(game, Vector2i(20, 14), 10)
	lm._spawn_mine(mtile, 1, true)
	await tree.create_timer(0.3).timeout   # arm
	await tree.create_timer(0.15).timeout  # detect overlap + detonate
	check(not lm._mine_tiles.has(mtile), "mine consumed on enemy contact")
	check(is_instance_valid(enemy) and enemy.health < 10, "enemy took blast damage (-> %d)" % enemy.health)
	check(is_instance_valid(enemy) and not enemy.is_flying, "level-1 mine does NOT fly the tank")

	print("\n[E] Level 2 mine slows the victim")
	var slot := Vector2i(24, 14)
	var e2 := _spawn_enemy(game, slot, 10)
	lm._spawn_mine(slot, 2, true)
	await tree.create_timer(0.3).timeout
	await tree.create_timer(0.15).timeout
	check(is_instance_valid(e2) and e2.is_mine_slowed, "level-2 mine slowed the enemy")
	# A cookie / clear lifts it.
	if is_instance_valid(e2):
		e2.clear_mine_slow()
		check(not e2.is_mine_slowed, "clear_mine_slow lifts the slow")

	print("\n[F] Level 3 mine flies the victim, then a landing blast")
	var ftile := Vector2i(20, 20)
	var e3 := _spawn_enemy(game, ftile, 30)
	lm._spawn_mine(ftile, 3, true)
	await tree.create_timer(0.3).timeout
	await tree.create_timer(0.15).timeout
	check(is_instance_valid(e3) and e3.is_flying, "level-3 mine launched the tank")
	check(is_instance_valid(e3) and e3.collision_layer == 0, "flying tank is uncollidable/helpless")
	var mines_before_land := lm._mine_tiles.size()
	# Step the fly to completion manually (physics is disabled on the test enemy).
	var steps := 0
	while is_instance_valid(e3) and e3.is_flying and steps < 300:
		e3._update_flying(1.0 / 60.0)
		steps += 1
	check(is_instance_valid(e3) and not e3.is_flying, "tank landed (fly ended after %d steps)" % steps)
	check(is_instance_valid(e3) and e3.collision_layer != 0, "collision restored after landing")

	print("\n[G] Mines refuse solid tiles")
	var solid_found := false
	for pos in lm._fg_tile_data.keys():
		if LevelData.is_solid_tile(LevelData.get_tile_category(lm._fg_tile_data[pos].get("code", 0))):
			solid_found = true
			check(not lm._mine_tile_placeable(pos), "cannot place a mine on a brick %s" % str(pos))
			break
	check(solid_found, "found a solid tile to test placement rejection")

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
