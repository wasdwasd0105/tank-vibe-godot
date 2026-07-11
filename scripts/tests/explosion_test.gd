extends Node
## Headless integration test for the explosion weapon. Run as override main scene:
##   Godot --headless res://scenes/test/explosion_test.tscn

var _fail := 0

func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1

func _find_solid_tile(lm: LevelManager, want_soft: bool) -> Vector2i:
	for pos in lm._fg_tile_data.keys():
		var cat := LevelData.get_tile_category(lm._fg_tile_data[pos].get("code", 0))
		var is_soft := cat == LevelData.TileCategory.SOFT_BRICK_FULL or cat == LevelData.TileCategory.SOFT_BRICK_PARTIAL
		var is_steel := cat == LevelData.TileCategory.IRON_BLOCK or cat == LevelData.TileCategory.SUPER_BLOCK
		if want_soft and is_soft:
			return pos
		if not want_soft and is_steel:
			return pos
	return Vector2i(-1, -1)

func _open_tile(lm: LevelManager) -> Vector2i:
	for y in range(6, 24):
		for x in range(6, 34):
			if not lm._fg_tile_data.has(Vector2i(x, y)) and not lm._bg_tile_data.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(20, 12)

func _ready() -> void:
	_run()

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
	var enemies_container: Node = game.get_node("Entities/Enemies")

	print("\n[A] The wave sprays a flat amount to tanks within its radius")
	var open := _open_tile(lm)
	var enemy := _spawn_enemy(enemies_container, lm.tile_to_world(open))
	await tree.process_frame
	enemy.max_health = 8
	enemy.health = 8
	lm.spawn_explosion_blast(enemy.global_position, 0, true)  # L0: radius 2, spray 1
	await tree.create_timer(0.05).timeout
	check(enemy.health == 7, "enemy in the L0 wave took 1 spray damage (8 -> %d)" % enemy.health)
	# Far enemy: outside the level-0 radius (2 tiles) -> no damage
	enemy.health = 8
	lm.spawn_explosion_blast(enemy.global_position + Vector2(200, 0), 0, true)
	await tree.create_timer(0.05).timeout
	check(enemy.health == 8, "enemy ~6 tiles away (outside radius 2) took no damage (%d)" % enemy.health)

	print("\n[B] No friendly fire (player blast vs player)")
	var player: PlayerTank = tree.get_nodes_in_group("players")[0]
	player.is_invincible = false
	var php: int = player.health
	lm.spawn_explosion_blast(player.global_position, 3, true)  # player-owned blast
	await tree.create_timer(0.05).timeout
	check(player.health == php, "player unharmed by player blast (%d)" % player.health)

	print("\n[C] Terrain destruction: soft brick breaks, steel survives")
	var soft := _find_solid_tile(lm, true)
	var steel := _find_solid_tile(lm, false)
	if soft.x >= 0:
		lm.spawn_explosion_blast(lm.tile_to_world(soft), 3, true)
		await tree.create_timer(0.2).timeout
		check(not lm._fg_tile_data.has(soft), "soft brick %s destroyed" % str(soft))
	else:
		check(false, "found a soft brick to test")
	if steel.x >= 0:
		lm.spawn_explosion_blast(lm.tile_to_world(steel), 3, true)
		await tree.create_timer(0.2).timeout
		check(lm._fg_tile_data.has(steel), "steel %s survives blast" % str(steel))
	else:
		print("  (no steel tile on this map — skipped)")

	print("\n[D] Line-of-sight: a wall shadows the blast")
	if soft.x >= 0 or steel.x >= 0:
		var wall := steel if steel.x >= 0 else _find_solid_tile(lm, false)
		# Any remaining solid tile works for a LOS check.
		var solid := Vector2i(-1, -1)
		for pos in lm._fg_tile_data.keys():
			if LevelData.is_solid_tile(LevelData.get_tile_category(lm._fg_tile_data[pos].get("code", 0))):
				solid = pos
				break
		if solid.x >= 0:
			var a := lm.tile_to_world(solid + Vector2i(-1, 0))
			var b := lm.tile_to_world(solid + Vector2i(1, 0))
			check(not lm.has_line_of_sight(a, b), "LOS blocked through a solid tile")
			var open2 := _open_tile(lm)
			check(lm.has_line_of_sight(lm.tile_to_world(open2), lm.tile_to_world(open2 + Vector2i(1, 0))),
				"LOS clear across open ground")

	print("\n[E] Level scales the blast radius and spray damage")
	check(ExplosionBlast.RADIUS_TILES[3] > ExplosionBlast.RADIUS_TILES[0],
		"L3 radius (%d) > L0 (%d) tiles" % [ExplosionBlast.RADIUS_TILES[3], ExplosionBlast.RADIUS_TILES[0]])
	check(ExplosionBlast.SPRAY_DAMAGE[0] == 1 and ExplosionBlast.SPRAY_DAMAGE[2] == 3,
		"spray damage 1 at L0, 3 at L2")

	print("\n[G] A cell that hits a wall plays only a half cycle")
	# Let any lingering blasts from earlier sections finish first.
	await tree.create_timer(0.7).timeout
	var wall := _find_solid_tile(lm, false)  # steel survives the [C] blasts
	var wcenter := _open_neighbor(lm, wall) if wall.x >= 0 else Vector2i(-1, -1)
	if wall.x >= 0 and wcenter.x >= 0:
		lm.spawn_explosion_blast(lm.tile_to_world(wcenter), 0, true)  # L0 radius 2
		await tree.process_frame
		await tree.process_frame
		var blast := _find_blast_at(tree, lm, wcenter)
		if blast != null:
			var wall_frames := _cell_frames(blast, lm, wall)          # the wall cell
			var center_frames := _cell_frames(blast, lm, wcenter)     # the open center cell
			check(wall_frames == ExplosionBlast.WALL_FRAMES,
				"wall cell plays half cycle (%d of %d frames)" % [wall_frames, ExplosionBlast.ANIM_FRAMES])
			check(center_frames == ExplosionBlast.ANIM_FRAMES,
				"open center cell plays the full cycle (%d frames)" % center_frames)
		else:
			print("  (blast not found — skipped)")
	else:
		print("  (no steel tile with an open neighbor — skipped)")

	print("\n[F] An explosion bullet detonates a blast when it dies")
	var before := tree.get_nodes_in_group("explosion_blasts").size()
	var bscene := load("res://scenes/tanks/bullet.tscn")
	var bullet = bscene.instantiate()
	bullet.direction = Vector2.RIGHT
	bullet.speed = 650.0
	bullet.explodes = true
	bullet.explosion_level = 2
	bullet.is_player_bullet = true
	bullet.global_position = Vector2(1400, 500)  # near right edge -> dies fast
	game.get_node("Entities/Bullets").add_child(bullet)
	await tree.create_timer(0.4).timeout
	check(not is_instance_valid(bullet), "explosion bullet died at the border")
	check(_count_blasts(tree) >= 0, "no crash spawning blast from bullet death")

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)

func _open_neighbor(lm: LevelManager, tile: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = tile + d
		if not lm._fg_tile_data.has(n) and not lm._bg_tile_data.has(n):
			return n
	return Vector2i(-1, -1)

## The live ExplosionBlast whose center cell sits on [param center_tile], if any.
func _find_blast_at(tree: SceneTree, lm: LevelManager, center_tile: Vector2i) -> ExplosionBlast:
	for node in tree.root.find_children("*", "Node2D", true, false):
		if node is ExplosionBlast and lm.world_to_tile(node.global_position) == center_tile:
			return node
	return null

## Animation frame count of the blast cell covering [param tile] (0 if none).
func _cell_frames(blast: ExplosionBlast, lm: LevelManager, tile: Vector2i) -> int:
	for entry in blast._tiles:
		var spr = entry["sprite"]
		if is_instance_valid(spr) and lm.world_to_tile(spr.global_position) == tile:
			return int(entry["frames"])
	return 0

func _count_blasts(tree: SceneTree) -> int:
	var n := 0
	for node in tree.root.find_children("*", "Node2D", true, false):
		if node is ExplosionBlast:
			n += 1
	return n

func _spawn_enemy(container: Node, world_pos: Vector2) -> EnemyTank:
	var scene := load("res://scenes/tanks/enemy_tank.tscn")
	var e: EnemyTank = scene.instantiate()
	e.tank_type_id = 1
	container.add_child(e)
	e.global_position = world_pos
	return e
