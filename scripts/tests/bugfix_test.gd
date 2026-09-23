extends Node
## Headless tests for two of the batch bug fixes:
##   #6 fortify (protect cookie) must NOT downgrade a super base block to iron
##   #4 losing anti-water while afloat sinks the tank
## (#1/#2/#3 fire-on-special-tiles live in fire_test; #5 AP+invincible in ap_test.)

var _fail := 0

func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1

func _cat(lm: LevelManager, pos: Vector2i) -> int:
	if not lm._fg_tile_data.has(pos):
		return -1
	return LevelData.get_tile_category(lm._fg_tile_data[pos].get("code", 0))

func _ready() -> void:
	_run()

## An enemy counted by the spawner exactly as EnemySpawner._spawn_enemy does.
func _add_tracked_enemy(game: Node, spawner: EnemySpawner, world: Vector2) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = world
	e.tree_exited.connect(spawner._on_enemy_removed)
	spawner._active_enemies += 1
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
	await tree.create_timer(0.7).timeout  # let the player finish materializing
	var lm: LevelManager = game.get_level_manager()

	print("\n[A] #6 - fortify keeps super base blocks, only reinforces weaker walls")
	var walls: Array = lm._original_base_walls.keys()
	check(walls.size() >= 2, "base has >=2 walls (%d)" % walls.size())
	var super_pos: Vector2i = walls[0]
	var brick_pos: Vector2i = walls[1]
	# Seed one base wall as a super block, another as a soft brick.
	lm._remove_fg_tile(super_pos); lm._place_fg_tile(super_pos, 0x3D); lm._original_base_walls[super_pos] = 0x3D
	lm._remove_fg_tile(brick_pos); lm._place_fg_tile(brick_pos, 0x19); lm._original_base_walls[brick_pos] = 0x19
	lm.fortify_base(10.0)
	check(_cat(lm, super_pos) == LevelData.TileCategory.SUPER_BLOCK, "super base wall stays super after fortify")
	check(_cat(lm, brick_pos) == LevelData.TileCategory.IRON_BLOCK, "soft-brick base wall reinforced to iron after fortify")
	lm._revert_fortification()
	check(_cat(lm, super_pos) == LevelData.TileCategory.SUPER_BLOCK, "super base wall still super after revert")
	check(_cat(lm, brick_pos) == LevelData.TileCategory.SOFT_BRICK_FULL, "brick base wall restored after revert")

	print("\n[B] #4 - losing anti-water while on water sinks the tank")
	var water := Vector2i(-1, -1)
	for pos in lm._bg_tile_data.keys():
		if LevelData.get_tile_category(lm._bg_tile_data[pos].get("code", 0)) == LevelData.TileCategory.WATER:
			water = pos
			break
	check(water.x >= 0, "found a water tile %s" % str(water))
	var wworld := lm.tile_to_world(water)
	check(lm.is_water_at_world(wworld), "is_water_at_world true over water")
	check(not lm.is_water_at_world(lm.tile_to_world(Vector2i(20, 14))), "is_water_at_world false over open ground")

	var players := tree.get_nodes_in_group("players")
	check(players.size() >= 1, "player present")
	var player: PlayerTank = players[0]
	player.is_invincible = false
	player.global_position = wworld
	player.apply_addon("anti-water")
	check(player.has_boat, "player gained the boat (anti-water)")
	# With a boat, the sink check leaves it afloat.
	player._sink_if_stranded_on_water()
	await tree.process_frame
	check(is_instance_valid(player), "boated tank stays afloat on water")
	# Lose the boat while afloat -> it sinks.
	var lives_before: int = GameManager.player_lives[0]
	player._remove_utility_addon()  # has_boat=false + deferred sink check
	await tree.process_frame
	await tree.process_frame
	check(not is_instance_valid(player) or GameManager.player_lives[0] < lives_before,
		"tank sank after losing the boat on water")

	print("\n[C] Leaving the game while enemies are alive is not a stage clear")
	var spawner: EnemySpawner = game.get_node("EnemySpawner")
	spawner.spawn_timer.stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	await tree.process_frame
	# The real stage-clear flow advances the stage (and writes a save) after 10 s,
	# so count the signals instead.
	Events.all_enemies_defeated.disconnect(game._on_all_enemies_defeated)
	var counts := {"defeated": 0, "cleared": 0}
	var on_defeated := func() -> void: counts["defeated"] += 1
	var on_cleared := func() -> void: counts["cleared"] += 1
	Events.all_enemies_defeated.connect(on_defeated)
	Events.stage_cleared.connect(on_cleared)
	spawner._spawn_queue.clear()   # late in a stage: every enemy already spawned
	spawner._active_enemies = 0
	var last := _add_tracked_enemy(game, spawner, lm.tile_to_world(Vector2i(20, 12)))
	await tree.process_frame
	last.destroy()
	await tree.process_frame
	await tree.process_frame
	check(counts["defeated"] == 1, "the last enemy dying clears the stage")
	_add_tracked_enemy(game, spawner, lm.tile_to_world(Vector2i(20, 12)))
	await tree.process_frame
	tree.root.remove_child(game)   # what leaving the scene does (menu, restart, game over)
	check(counts["defeated"] == 1, "closing the game with an enemy alive does not clear the stage")
	game._on_all_enemies_defeated()   # a stray stage clear reaching the closed game
	check(counts["cleared"] == 0, "a closed game ignores it: no stage-clear jingle, no null get_tree()")
	Events.all_enemies_defeated.disconnect(on_defeated)
	Events.stage_cleared.disconnect(on_cleared)
	game.free()
	await tree.create_timer(1.2).timeout  # let the explosion sound finish before quitting

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
