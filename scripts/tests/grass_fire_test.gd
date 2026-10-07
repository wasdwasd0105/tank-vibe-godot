extends Node
## Headless test for burning grass, as Tank.exe's (docs/fire_weapon_original_spec.md
## section 5), and the 3 rows of fire by whose it is.

var _fail := 0
func check(cond: bool, msg: String) -> void:
	if cond: print("  PASS: ", msg)
	else: _fail += 1; print("  FAIL: ", msg)

func _ready() -> void:
	_run()

func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	seed(20261008)
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_intro = false  # straight into play
	tree.root.add_child(game)
	for i in range(5):
		await tree.process_frame
	await tree.create_timer(0.2).timeout
	# No enemies: a fire tank's shots would light more grass mid-test.
	game.get_node("EnemySpawner").halt()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	var lm: LevelManager = game.get_level_manager()
	lm._clear_fire()

	print("\n[A] Its row by whose it is: red burning grass over the tanks, the sides' under them")
	var pf := GroundFire.new(); pf.side = 1
	var ef := GroundFire.new(); ef.side = 0
	var gf := GroundFire.new(); gf.side = -1
	check(pf._current_row() == 3 and ef._current_row() == 2 and gf._current_row() == 1,
		"a player's row 3 (yellow), the enemies' row 2 (orange), burning grass row 1 (red)")
	check(pf.from_player and not ef.from_player and gf.is_grass_fire, "whose it is, by its side")
	pf.free(); ef.free(); gf.free()

	print("\n[B] A fire beside grass burns it grey, lighting nobody's fire there, which walks on along it")
	var gy := 14
	var gx0 := 12
	for x in range(gx0 - 4, gx0 + 8):
		var t := Vector2i(x, gy)
		for row in [gy - 1, gy, gy + 1]:
			var c := Vector2i(x, row)
			if lm._fg_tile_data.has(c):
				lm._remove_fg_tile(c)
			if lm._bg_tile_data.has(c):
				lm._remove_bg_tile(c)
		if x >= gx0:
			lm._place_fg_tile(t, 0x09)  # GRASS (green)
	check(lm._is_green_grass(Vector2i(gx0, gy)), "test grass tile reads as green")
	# Burning grass right of nothing but the strip: lit on the tile before it.
	lm._new_fire(Vector2i(gx0 - 1, gy), -1, -1, 0, 4000.0, 0.09, 0, true)
	await tree.create_timer(0.3).timeout
	check(lm._is_green_grass(Vector2i(gx0, gy)), "0.3 s on, still green")
	await tree.create_timer(0.5).timeout
	check(not lm._is_green_grass(Vector2i(gx0, gy)), "by 0.8 s burned grey (a fire's step comes 0.375-0.75 s after it's lit)")
	var lit := lm.fires_at(Vector2i(gx0, gy))
	check(lit.size() == 1 and lit[0].is_grass_fire and lit[0].visible, "with burning grass on it, seen at once")
	await tree.create_timer(2.5).timeout
	var burned := 0
	for x in range(gx0, gx0 + 8):
		if LevelData.get_tile_category(lm._fg_tile_data[Vector2i(x, gy)].get("code", 0)) == LevelData.TileCategory.BURNED_GRASS:
			burned += 1
	check(burned >= 4 and burned < 8, "it walks along the strip a tile at a time: %d of 8 grey by 3.3 s" % burned)

	print("\n[C] Each tile of it burns about 3 s; the grey stays")
	var first_lit: GroundFire = lit[0] if not lit.is_empty() else null
	check(first_lit != null and is_instance_valid(first_lit) and first_lit.fuel > 0.0, "the first still burns 2.5 s after it was lit")
	await tree.create_timer(6.0).timeout
	check(lm._fires_at.is_empty(), "all burned out (%d tiles left)" % lm._fires_at.size())
	check(LevelData.get_tile_category(lm._fg_tile_data[Vector2i(gx0, gy)].get("code", 0)) == LevelData.TileCategory.BURNED_GRASS,
		"the burned grass stays grey after the fire is gone")

	print("\n[D] Burning grass burns both sides, a point every 1.125 s")
	var enemy: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	enemy.tank_type_id = 1
	game.get_node("Entities/Enemies").add_child(enemy)
	enemy.set_physics_process(false)
	enemy.is_materializing = false
	enemy.max_health = 5; enemy.health = 5
	var player: PlayerTank = null
	for p in tree.get_nodes_in_group("players"):
		player = p
	player.set_physics_process(false)
	player.is_invincible = false
	player.fire_immunity_timer = 0.0
	var php: int = player.health
	player.burn(true, -1)
	check(player.health == php - 1 and is_equal_approx(player.fire_immunity_timer, LevelManager.GRASS_FIRE_WINDOW),
		"a player: one point, then 1.125 s before the next")
	var ehp: int = enemy.health
	enemy.burn(true, -1)
	check(enemy.health == ehp - 1 and is_equal_approx(enemy.fire_immunity_timer, LevelManager.GRASS_FIRE_WINDOW),
		"an enemy the same")
	enemy.queue_free()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
