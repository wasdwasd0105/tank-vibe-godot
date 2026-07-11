extends Node
## Headless test for the grass-fire mechanic and the 3 owner sprite rows.

var _fail := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("  PASS: ", msg)
	else: _fail += 1; print("  FAIL: ", msg)

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

	print("\n[A] Sprite row by owner")
	var pf := GroundFire.new(); pf.from_player = true
	var ef := GroundFire.new(); ef.from_player = false
	var gf := GroundFire.new(); gf.is_grass_fire = true
	check(pf._current_row() == 3, "player fire uses row 3")
	check(ef._current_row() == 2, "enemy fire uses row 2")
	check(gf._current_row() == 1, "grass fire uses row 1")
	pf.free(); ef.free(); gf.free()

	print("\n[B] Fire burns green grass to grey and spreads slowly")
	# Lay a horizontal strip of green grass, then ignite one end.
	var gy := 14
	var gx0 := 12
	for x in range(gx0, gx0 + 8):
		var t := Vector2i(x, gy)
		# Force the tile to GREEN grass (0x09) so we control the setup.
		if lm._fg_tile_data.has(t):
			lm._remove_fg_tile(t)
		lm._place_fg_tile(t, 0x09)  # GRASS (green)
	check(lm._is_green_grass(Vector2i(gx0, gy)), "test grass tile reads as green")

	lm.ignite_grass(Vector2i(gx0, gy), true)
	await tree.process_frame
	# The ignited tile converts to grey immediately (code +4 -> BURNED_GRASS).
	var lit_cat := LevelData.get_tile_category(lm._fg_tile_data[Vector2i(gx0, gy)].get("code", 0))
	check(lit_cat == LevelData.TileCategory.BURNED_GRASS, "ignited grass turned grey (burned)")
	var count0 := lm._grass_fires.size()
	check(count0 == 1, "one grass fire burning immediately (got %d)" % count0)

	# After a spread interval it creeps to the neighbour; after a few, several burn.
	await tree.create_timer(0.7).timeout
	check(lm._grass_fires.size() > count0, "grass fire spread to neighbouring grass (%d)" % lm._grass_fires.size())
	await tree.create_timer(1.5).timeout
	var burned := 0
	for x in range(gx0, gx0 + 8):
		if LevelData.get_tile_category(lm._fg_tile_data[Vector2i(x, gy)].get("code", 0)) == LevelData.TileCategory.BURNED_GRASS:
			burned += 1
	check(burned >= 4, "the fire crept along the grass strip, greying several tiles (%d/8)" % burned)

	print("\n[C] Grass fire eventually burns out; grey grass remains")
	# The wave takes ~3.5s to cross the 8-tile strip and each tile burns 3s, so
	# wait past the last-lit tile's burn-out.
	await tree.create_timer(6.0).timeout
	check(lm._grass_fires.is_empty(), "all grass fires burned out (%d left)" % lm._grass_fires.size())
	var still_grey := LevelData.get_tile_category(lm._fg_tile_data[Vector2i(gx0, gy)].get("code", 0)) == LevelData.TileCategory.BURNED_GRASS
	check(still_grey, "the burned grass stays grey after the fire is gone")

	print("\n[D] Grass fire hurts BOTH sides (neutral)")
	var pfld := load("res://scenes/tanks/player_tank.tscn")
	# Use a fresh player + enemy and drive a grass fire's damage at each.
	var enemy: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	enemy.tank_type_id = 1
	game.get_node("Entities/Enemies").add_child(enemy)
	enemy.set_physics_process(false)
	enemy.max_health = 5; enemy.health = 5
	# on_fire_contact(from_player=true, reburn, hurts_both=true): a PLAYER-lit grass
	# fire should still damage the player.
	var player: PlayerTank = null
	for p in tree.get_nodes_in_group("players"):
		player = p
	player.is_invincible = false
	player.fire_immunity_timer = 0.0
	var php: int = player.health
	player.on_fire_contact(true, 1.0, true)   # neutral grass fire lit "by a player"
	check(player.health == php - 1, "player-lit grass fire still burns the player (both sides)")
	enemy.fire_immunity_timer = 0.0
	var ehp: int = enemy.health
	enemy.on_fire_contact(true, 1.0, true)
	check(enemy.health == ehp - 1, "the same grass fire also burns the enemy")

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
