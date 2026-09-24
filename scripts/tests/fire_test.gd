extends Node
## Headless integration test for the fire weapon (ring-growth field model).
## Run as an override main scene:
##   Godot --headless res://scenes/test/fire_test.tscn

var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS: ", msg)
	else:
		_fail += 1
		print("  FAIL: ", msg)

func _ignitable_count(lm: LevelManager, center: Vector2i, size: int) -> int:
	var n := 0
	for off in FireField.offsets_for(size):
		if lm._fire_tile_ignitable(center + off):
			n += 1
	return n

func _find_open_center(lm: LevelManager) -> Vector2i:
	# Prefer a tile whose full 8x8 growth area is open; fall back to the best.
	var best := Vector2i(20, 14)
	var best_n := -1
	for y in range(5, 25):
		for x in range(5, 35):
			if not lm._fire_tile_ignitable(Vector2i(x, y)):
				continue
			var n := _ignitable_count(lm, Vector2i(x, y), FireField.MAX_SIZE)
			if n > best_n:
				best_n = n
				best = Vector2i(x, y)
				if n == FireField.offsets_for(FireField.MAX_SIZE).size():
					return best
	return best

func _make_bullet(game: Node, pos: Vector2, is_player: bool, fire: bool, dmg: int) -> Bullet:
	# Build a bullet fully configured BEFORE it enters the tree, so no physics
	# frame runs (which would self-destruct it out of bounds) before we use it.
	var b: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	b.direction = Vector2.UP
	b.is_player_bullet = is_player
	b.ignites_ground = fire
	b.damage = dmg
	b.global_position = pos
	game.get_node("Entities/Bullets").add_child(b)  # _ready resolves _level_manager
	b.global_position = pos
	return b

func _ready() -> void:
	_run()

func _run() -> void:
	var tree := get_tree()
	await tree.process_frame

	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false

	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_intro = false  # straight into play
	tree.root.add_child(game)
	for i in range(5):
		await tree.process_frame
	await tree.create_timer(0.2).timeout

	var lm: LevelManager = game.get_level_manager()
	check(lm != null, "level_manager available")

	print("\n[S] Fire spreads on water, ice & burned grass like ground")
	var wtile := Vector2i(-1, -1)
	var itile := Vector2i(-1, -1)
	for pos in lm._bg_tile_data.keys():
		var c = LevelData.get_tile_category(lm._bg_tile_data[pos].get("code", 0))
		if c == LevelData.TileCategory.WATER and wtile.x < 0:
			wtile = pos
		if c == LevelData.TileCategory.ICE and itile.x < 0:
			itile = pos
	var gtile := Vector2i(-1, -1)
	for pos in lm._fg_tile_data.keys():
		if LevelData.get_tile_category(lm._fg_tile_data[pos].get("code", 0)) == LevelData.TileCategory.GRASS:
			gtile = pos
			break
	if wtile.x >= 0:
		check(lm._fire_tile_ignitable(wtile), "fire CAN burn water (%s)" % str(wtile))
	if itile.x >= 0:
		check(lm._fire_tile_ignitable(itile), "fire CAN burn ice (%s)" % str(itile))
	if gtile.x >= 0:
		lm._convert_grass_to_burned(gtile)  # green -> burned (no fire side effect)
		check(lm._fire_tile_ignitable(gtile), "fire CAN burn burned grass (%s)" % str(gtile))

	# Clear the test area to open ground so grass tiles don't divert to (neutral)
	# grass fires and ice/water don't alter the count — this test exercises the
	# weapon-fire field geometry, not the wildfire or special tiles.
	for y in range(4, 27):
		for x in range(4, 37):
			var t := Vector2i(x, y)
			if lm._fg_tile_data.has(t):
				lm._remove_fg_tile(t)
				lm._brick_damage.erase(t)
				lm._hard_brick_hp.erase(t)
			if lm._bg_tile_data.has(t):
				lm._remove_bg_tile(t)

	print("\n[A] Rule 1 — base fire is 4x4 minus corners = 12 tiles")
	check(FireField.offsets_for(4).size() == 12, "size 4 = 12 tiles")
	check(FireField.offsets_for(5).size() == 21, "size 5 = 21 tiles")
	check(FireField.offsets_for(6).size() == 32, "size 6 = 32 tiles")
	check(FireField.offsets_for(7).size() == 45, "size 7 = 45 tiles")
	check(FireField.offsets_for(8).size() == 60, "size 8 = 60 tiles (max)")
	var corners := [Vector2i(-1,-1), Vector2i(2,-1), Vector2i(-1,2), Vector2i(2,2)]
	var geo_ok := true
	for c in corners:
		if c in FireField.offsets_for(4):
			geo_ok = false
	check(geo_ok, "the 4 corners are excluded at size 4")

	print("\n[B] Rule 3 — a fire bullet on the burning area grows the field a ring at a time")
	# Centre of the cleared region: its full 8x8 growth AND 1-tile border are open,
	# so no edge tile diverts to a (neighbour-seeded) grass fire.
	var center := Vector2i(20, 14)
	print("  (open center %s: %d/60 tiles ignitable)" %
		[str(center), _ignitable_count(lm, center, FireField.MAX_SIZE)])
	lm.ignite_fire_patch(center, true)
	var field: FireField = lm._fire_index.get(center)
	check(field != null and field.size == 4, "first ignition makes a size-4 field")
	check(field._tiles.size() == _ignitable_count(lm, center, 4), "12 tiles burning")
	# Feed the SAME area 4 more times -> 5,6,7,8, then capped at 8.
	for target in [5, 6, 7, 8, 8]:
		lm.ignite_fire_patch(center, true)
		check(field.size == target, "grew to size %d" % target)
	check(field._tiles.size() == _ignitable_count(lm, center, 8), "size-8 field has 60 tiles on open ground (got %d)" % field._tiles.size())

	print("\n[C] Rule 2/3 — a cycle with no new fire shrinks one ring; size-4 dies out")
	# Force the burn timer to expire and tick the manager.
	field._burn_timer = 0.001
	await tree.process_frame
	await tree.process_frame
	check(field.size == 7, "grown field shrank 8 -> 7 after a cycle")
	check(not field.is_dead(), "grown field still alive at size 7")
	# A fresh size-4 field should fully extinguish when its cycle ends.
	var c2 := _find_open_center(lm)
	if c2 == center:
		c2 = center + Vector2i(0, 12)
	lm.ignite_fire_patch(c2, false)
	var f2: FireField = lm._fire_index.get(c2)
	check(f2 != null and f2.size == 4, "second field starts size 4")
	f2._burn_timer = 0.001
	await tree.process_frame
	await tree.process_frame
	check(f2.is_dead(), "size-4 field dies when its cycle ends with no new fire")

	print("\n[D] Solid tiles never catch fire")
	var brick_found := false
	for pos in lm._fg_tile_data.keys():
		var code: int = lm._fg_tile_data[pos].get("code", 0)
		if LevelData.is_solid_tile(LevelData.get_tile_category(code)):
			brick_found = true
			check(not lm._fire_tile_ignitable(pos), "brick tile %s not ignitable" % str(pos))
			break
	check(brick_found, "found a solid tile to test")

	print("\n[E] Fire damage side rules (player tank)")
	var player: PlayerTank = null
	for p in tree.get_nodes_in_group("players"):
		player = p
		break
	if player:
		player.is_invincible = false
		player.fire_immunity_timer = 0.0
		var hp0: int = player.health
		player.on_fire_contact(true, 1.0)   # player-owned fire
		check(player.health == hp0, "player immune to player-owned fire")
		player.fire_immunity_timer = 0.0
		player.on_fire_contact(false, 1.0)  # enemy-owned fire
		check(player.health == hp0 - 1, "player takes 1 HP from enemy-owned fire")
		var hp1: int = player.health
		player.on_fire_contact(false, 1.0)  # within immunity window
		check(player.health == hp1, "immunity window blocks repeat damage")
	else:
		check(false, "player tank spawned")

	print("\n[F] Rule 4 — fire bullet drops & ignites at max range")
	var before: int = lm._fire_fields.size()
	var bscene := load("res://scenes/tanks/bullet.tscn")
	var bullet = bscene.instantiate()
	bullet.direction = Vector2.RIGHT
	bullet.speed = 520.0
	bullet.max_range = 96.0
	bullet.ignites_ground = true
	bullet.is_player_bullet = true
	bullet.global_position = lm.tile_to_world(_find_open_center(lm)) + Vector2(200, 0)
	game.get_node("Entities/Bullets").add_child(bullet)
	await tree.create_timer(0.5).timeout
	check(not is_instance_valid(bullet), "fire bullet destroyed at range end")
	check(lm._fire_fields.size() > before, "fire bullet left a burning field")

	print("\n[G] Rule 6 — fire bullet subtracts its damage from a crossed enemy bullet")
	var valid_pos := lm.tile_to_world(_find_open_center(lm))
	var fire_b := _make_bullet(game, valid_pos, true, true, 1)
	var enemy_b := _make_bullet(game, valid_pos, false, false, 2)
	fire_b._on_area_entered(enemy_b)
	check(fire_b._destroyed, "fire bullet drops on contact")
	check(not enemy_b._destroyed and enemy_b.damage == 1,
		"tough enemy bullet survives with damage reduced 2 -> 1")
	# A 1-damage enemy bullet should be killed outright.
	var fire_b2 := _make_bullet(game, valid_pos, true, true, 1)
	var enemy_b2 := _make_bullet(game, valid_pos, false, false, 1)
	fire_b2._on_area_entered(enemy_b2)
	check(enemy_b2._destroyed, "weak enemy bullet is destroyed (damage 1 - 1 = 0)")

	await _check_ice_melt(lm)
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


## A 6x6 sheet of ice around [param center] on cleared ground.
func _lay_ice(lm: LevelManager, center: Vector2i) -> Array:
	var tiles: Array = []
	for y in range(center.y - 3, center.y + 3):
		for x in range(center.x - 3, center.x + 3):
			var t := Vector2i(x, y)
			if lm._fg_tile_data.has(t):
				lm._remove_fg_tile(t)
			if lm._bg_tile_data.has(t):
				lm._remove_bg_tile(t)
			lm._place_bg_tile(t, 0x01)
			tiles.append(t)
	return tiles


func _ice_left(lm: LevelManager, tiles: Array) -> int:
	var n := 0
	for t in tiles:
		n += int(lm._is_ice(t))
	return n


## Tank.exe's fire terrain step: a player's fire melts the ice under it into
## bare ground, 0.375-0.75 s after landing; enemy fire never does.
func _check_ice_melt(lm: LevelManager) -> void:
	var tree := get_tree()
	print("\n[I] A player's fire melts the ice under it; enemy fire does not")
	lm._clear_fire()
	var center := Vector2i(12, 10)
	var sheet := _lay_ice(lm, center)
	var patch: Array = []
	for off in FireField.offsets_for(FireField.MIN_SIZE):
		patch.append(center + off)
	lm.ignite_fire_patch(center, true)
	var burning := 0
	for t in patch:
		burning += int(lm._fire_index.has(t))
	check(burning == patch.size(), "a player's fire lands on ice: all %d tiles burn (%d)" % [patch.size(), burning])
	await tree.create_timer(0.25).timeout
	check(_ice_left(lm, patch) == patch.size(), "0.25 s in, the ice under it still holds")
	await tree.create_timer(0.7).timeout
	check(_ice_left(lm, patch) == 0, "by 0.95 s every ice tile under the fire has melted (%d left)" % _ice_left(lm, patch))
	check(_ice_left(lm, sheet) == sheet.size() - patch.size(), "the ice around the patch stays")
	var world := lm.global_position + Vector2((center.x + 0.5) * LevelManager.TILE_SIZE, (center.y + 0.5) * LevelManager.TILE_SIZE)
	check(lm.ice_tiles_under(world) == 0, "a tank there is no longer on ice")

	lm._clear_fire()
	var enemy_center := Vector2i(28, 18)
	var enemy_sheet := _lay_ice(lm, enemy_center)
	lm.ignite_fire_patch(enemy_center, false)
	check(lm._fire_index.has(enemy_center), "an enemy fire lands on ice too")
	await tree.create_timer(1.0).timeout
	check(_ice_left(lm, enemy_sheet) == enemy_sheet.size(), "but melts none of it")

	lm._clear_fire()
	var reload_sheet := _lay_ice(lm, center)
	lm.ignite_fire_patch(center, true)
	lm._clear_fire()   # as a stage reload does
	await tree.create_timer(1.0).timeout
	check(_ice_left(lm, reload_sheet) == reload_sheet.size(), "a fire cleared away before melting leaves the ice")
