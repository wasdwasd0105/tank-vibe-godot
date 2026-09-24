extends Node
## Headless test for the state-effect visuals extracted from Tank_Out.bmp / Tank_T.bmp:
##   - spawn burst (plays where a new tank appears, then frees itself)
##   - invincibility shield wreath (player, Tank_T row 1)
##   - freeze frost wreath (enemy, Tank_T row 2)
## Run as override main scene:
##   Godot --headless res://scenes/test/effects_test.tscn

var _fail := 0

func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1

func _open_tile(lm: LevelManager) -> Vector2i:
	for y in range(6, 24):
		for x in range(6, 34):
			if not lm._fg_tile_data.has(Vector2i(x, y)) and not lm._bg_tile_data.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(20, 12)

func _spawn_enemy(container: Node, world_pos: Vector2) -> EnemyTank:
	var scene := load("res://scenes/tanks/enemy_tank.tscn")
	var e: EnemyTank = scene.instantiate()
	e.tank_type_id = 1
	container.add_child(e)
	e.global_position = world_pos
	return e

func _count_bursts(tree: SceneTree) -> int:
	var n := 0
	for node in tree.root.find_children("*", "Node2D", true, false):
		if node is SpawnBurst:
			n += 1
	return n

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
	var enemies_container: Node = game.get_node("Entities/Enemies")

	print("\n[A] Effect frame strips load")
	check(BaseTank.get_shield_frames().size() == 8, "8 shield frames loaded")
	check(BaseTank.get_freeze_frames().size() == 8, "8 freeze frames loaded")

	print("\n[B] A spawn burst plays at the spawn point then frees itself")
	SpawnBurst.spawn_at(tree, lm.tile_to_world(_open_tile(lm)))
	await tree.process_frame
	await tree.process_frame
	check(_count_bursts(tree) >= 1, "spawn burst created in effects_container")
	check(SpawnBurst._frames.size() == 6, "6 spawn frames loaded")
	await tree.create_timer(0.8).timeout  # > 6 * 0.09s
	check(_count_bursts(tree) == 0, "spawn burst freed after its 6 frames")

	print("\n[C] Only the helmet shows the shield wreath; every other invincibility blinks")
	var players := tree.get_nodes_in_group("players")
	check(players.size() >= 1, "player present")
	var player: PlayerTank = players[0]
	# Player spawned on the clear corridor left of the base (cols 15-16), not on the
	# fortress bricks — so it stays put instead of being ejected by depenetration.
	var pf: Vector2 = lm.global_position
	var want_p1 := Vector2(pf.x + 15 * 32 + 32, pf.y + 28 * 32 + 32)
	check(player.global_position.distance_to(want_p1) < 4.0,
		"player at clear spawn %s (got %s)" % [str(want_p1), str(player.global_position)])
	var seen := func() -> Array:   # the tank's visibility over the next 6 frames
		var out: Array = []
		for i in range(6):
			await tree.process_frame
			out.append(player.visible)
		return out
	while player.is_invincible:   # let the spawn protection run out first
		await tree.process_frame
	await tree.process_frame
	player.activate_helmet(5.0)
	var frames_helmet: Array = await seen.call()
	check(player._state_fx_sprite != null and player._state_fx_sprite.visible,
		"helmet: the wreath shows")
	check(not frames_helmet.has(false), "helmet: the tank stays solid under the wreath")
	player.invincible_timer = 2.0   # into the helmet's last 2.25 s
	var frames_ending: Array = await seen.call()
	check(not player._state_fx_sprite.visible and frames_ending.has(true) and frames_ending.has(false),
		"helmet running out: the wreath goes and the tank blinks (%s)" % str(frames_ending))
	player.invincible_timer = 0.05
	await tree.create_timer(0.3).timeout
	check(not player.is_invincible and player.visible and not player._state_fx_sprite.visible,
		"invincibility over: solid tank, no wreath")
	player.activate_pickup_invincibility()
	var frames_pickup: Array = await seen.call()
	var alternates := true
	for i in range(1, frames_pickup.size()):
		alternates = alternates and frames_pickup[i] != frames_pickup[i - 1]
	check(not player._state_fx_sprite.visible and alternates,
		"pickup invincibility: no wreath, drawn every other frame (%s)" % str(frames_pickup))
	while player.visible:   # catch the blink on a blank frame, then pause there
		await tree.process_frame
	tree.paused = true
	await tree.process_frame
	check(player.visible, "paused on a blank blink frame: the tank is shown, not left invisible")
	tree.paused = false
	player.invincible_timer = 0.05
	await tree.create_timer(0.3).timeout
	check(player.visible and not player.is_invincible, "blink over: solid tank")

	print("\n[D] Frozen enemies show the frost wreath, then hide it")
	var enemy := _spawn_enemy(enemies_container, lm.tile_to_world(_open_tile(lm)))
	await tree.process_frame
	GameManager.freeze_all_enemies(5.0)
	await tree.process_frame
	await tree.process_frame
	check(enemy._state_fx_sprite != null and enemy._state_fx_sprite.visible,
		"frost overlay visible while frozen")
	check(enemy._frost_shown, "_frost_shown flag set while frozen")
	GameManager.enemies_frozen = false
	GameManager.freeze_timer = 0.0
	await tree.process_frame
	await tree.process_frame
	check(enemy._state_fx_sprite != null and not enemy._state_fx_sprite.visible,
		"frost overlay hidden once unfrozen")
	check(not enemy._frost_shown, "_frost_shown cleared once unfrozen")

	print("\n[E] A tank materializes (hidden + intangible) then appears after the burst")
	var e2 := _spawn_enemy(enemies_container, lm.tile_to_world(_open_tile(lm)))
	await tree.process_frame
	var saved_layer := e2.collision_layer
	e2.begin_materialize(0.2)
	await tree.process_frame
	check(not e2.visible and e2.collision_layer == 0,
		"materializing tank is hidden + intangible (layer 0)")
	check(e2.is_materializing, "is_materializing true during the burst")
	await tree.create_timer(0.3).timeout
	check(e2.visible and e2.collision_layer == saved_layer,
		"tank appears + collision restored after the burst")
	check(not e2.is_materializing, "is_materializing cleared after the burst")

	print("\n[F] Revive resolves beside the base, else the nearest clear block")
	var eagle: Node = game.get_node("Playfield/Eagle")
	var etl: Vector2i = lm.world_to_tile(eagle.global_position) - Vector2i(1, 1)
	# The eagle's own 2x2 is reserved — never a spawn spot.
	check(not lm.is_area_clear(etl, Vector2i(2, 2)), "eagle's own 2x2 is not a valid spawn area")
	# Stage 1's base is walled, so P1/P2 fall back to a clear block flanking it —
	# clear, not solid, not on the eagle.
	var p1_tl: Vector2i = lm.find_clear_area(Vector2i(etl.x - 2, etl.y), Vector2i(2, 2))
	var p2_tl: Vector2i = lm.find_clear_area(Vector2i(etl.x + 2, etl.y), Vector2i(2, 2))
	check(lm.is_area_clear(p1_tl, Vector2i(2, 2)) and p1_tl.x < etl.x,
		"P1 revives on a clear block left of the base (%s)" % str(p1_tl))
	check(lm.is_area_clear(p2_tl, Vector2i(2, 2)) and p2_tl.x > etl.x,
		"P2 revives on a clear block right of the base (%s)" % str(p2_tl))
	# An already-clear ideal is used as-is (revive right there, no search).
	check(lm.find_clear_area(p1_tl, Vector2i(2, 2)) == p1_tl,
		"an already-clear ideal block is returned unchanged")

	print("\n[G] A destroyed tank plays the theme's explosion strip, else the built-in burst")
	var prev_theme: String = ThemeManager.current_theme
	var effects: Node = game.get_node("Entities/Effects")
	# The bots from the earlier sections keep shooting, and their bullet hits add
	# effects of their own; clear them out and look only where the victim died.
	for e in enemies_container.get_children():
		e.queue_free()
	await tree.process_frame
	for theme_name in ["juezhuantanke", "default"]:
		ThemeManager.load_theme(theme_name)
		var strip: Array = ThemeManager.get_tank_explode_frames()
		if theme_name == "juezhuantanke":
			check(strip.size() == 8 and (strip[0] as Texture2D).get_size() == Vector2(96, 96),
				"juezhuantanke: 8 explosion frames of 96 px (the original's 48 px _B_48, doubled)")
		else:
			check(strip.is_empty(), "default: no explosion strip")
		for fx in effects.get_children():
			fx.free()
		var victim := _spawn_enemy(enemies_container, lm.tile_to_world(_open_tile(lm)))
		await tree.process_frame
		var at := victim.global_position
		victim.destroy()
		var themed: HitEffect = null
		var bursts := 0
		for fx in effects.get_children():
			if not (fx is Node2D) or (fx as Node2D).global_position != at:
				continue
			if fx is HitEffect and fx._frames == strip:
				themed = fx
			elif fx.get_script() and fx.get_script().resource_path == "res://scripts/effects/explosion.gd":
				bursts += 1
		if theme_name == "juezhuantanke":
			check(themed != null and bursts == 0,
				"juezhuantanke: a destroyed bot plays the original's explosion, not the yellow circle")
			await tree.create_timer(0.5).timeout
			check(not is_instance_valid(themed), "the explosion frees itself once its 0.4 s are up")
		else:
			check(themed == null and bursts == 1, "default: a destroyed bot keeps the built-in burst")
	ThemeManager.load_theme(prev_theme)
	await tree.create_timer(1.5).timeout  # let the explosion sounds finish before quitting

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
