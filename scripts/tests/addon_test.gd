extends Node
## Headless test for how tank add-ons are drawn, against Tank.exe (0x00493720):
## each add-on sits at the tank's own spot, pushed along its facing (moon shield
## 4 px ahead, memory-save 2 px behind, anti-water and anti-ice 2 px behind
## while driving but 1 px when still or on ice; original px, doubled here). The
## anti-ice wings and the moon shield have a drawn frame per facing; the rings
## stay upright and cycle a frame every 0.25 s. A flying tank draws no add-on.
## Run as an override main scene:
##   Godot --headless res://scenes/test/addon_test.tscn

const FACINGS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const ICE := 0x01

var _fail := 0
var _game: Node
var _lm: LevelManager


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _spawn_enemy(type_id: int, local: Vector2) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _lm.global_position + local
	return e


func _face(tank: BaseTank, facing: Vector2, moving: bool) -> void:
	tank.current_direction = facing
	tank._update_sprite_direction()
	tank.velocity = facing * 100.0 if moving else Vector2.ZERO
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	ThemeManager.load_theme("juezhuantanke")
	_game = load("res://scenes/game.tscn").instantiate()
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_lm = _game.get_level_manager()
	_game.get_node("EnemySpawner").spawn_timer.stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	for tile in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(tile)
	await tree.process_frame

	print("\n[A] Anti-ice wings: a drawn frame per facing, 2 px back driving, 1 px still")
	var skater := _spawn_enemy(22, Vector2(320, 320))
	await tree.process_frame
	var wings: Sprite2D = skater._addon_sprites[0]
	var frames: Array = ThemeManager.get_addon_facing_textures("anti-ice") if ThemeManager.has_method("get_addon_facing_textures") else []
	check(frames.size() == 4, "the theme has the original's 4 anti-ice frames")
	for i in range(4):
		await _face(skater, FACINGS[i], true)
		check(frames.size() == 4 and wings.texture == frames[i] and is_zero_approx(wings.rotation),
			"facing %s: its own frame, not a turned one (rotation %.2f)" % [FACINGS[i], wings.rotation])
		check(wings.position.is_equal_approx(FACINGS[i] * -4.0), "facing %s, driving: 4 px behind (got %s)" % [FACINGS[i], wings.position])
		await _face(skater, FACINGS[i], false)
		check(wings.position.is_equal_approx(FACINGS[i] * -2.0), "facing %s, still: 2 px behind (got %s)" % [FACINGS[i], wings.position])
	# Ice under the tank's 2x2 block: back to 2 px even while driving.
	var block := Vector2i(9, 9)   # the tank centred on the corner (320, 320)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_lm._place_bg_tile(block + d, ICE)
	await _face(skater, Vector2.RIGHT, true)
	check(wings.position.is_equal_approx(Vector2.RIGHT * -2.0), "driving on ice: 2 px behind (got %s)" % wings.position)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_lm._remove_bg_tile(block + d)

	print("\n[B] Moon shield: a drawn frame per facing, 8 px ahead")
	var shielded := _spawn_enemy(4, Vector2(640, 320))
	await tree.process_frame
	var shield: Sprite2D = shielded._shield_sprite
	var shield_frames: Array = ThemeManager.get_addon_facing_textures("moon-shield") if ThemeManager.has_method("get_addon_facing_textures") else []
	for i in range(4):
		await _face(shielded, FACINGS[i], i % 2 == 0)
		check(shield_frames.size() == 4 and shield.texture == shield_frames[i] and is_zero_approx(shield.rotation),
			"facing %s: its own frame" % FACINGS[i])
		check(shield.position.is_equal_approx(FACINGS[i] * 8.0), "facing %s: 8 px ahead (got %s)" % [FACINGS[i], shield.position])

	print("\n[C] Rings stay upright; memory-save 4 px back, anti-water 4 / 2 px back")
	var memory := _spawn_enemy(8, Vector2(960, 320))
	var boat := _spawn_enemy(2, Vector2(320, 640))
	await tree.process_frame
	var ring: Sprite2D = memory._addon_sprites[0]
	var float_ring: Sprite2D = boat._addon_sprites[0]
	for i in range(4):
		await _face(memory, FACINGS[i], false)
		await _face(boat, FACINGS[i], true)
		check(is_zero_approx(ring.rotation) and ring.position.is_equal_approx(FACINGS[i] * -4.0),
			"memory-save facing %s: upright, 4 px behind (got %.2f rad, %s)" % [FACINGS[i], ring.rotation, ring.position])
		check(is_zero_approx(float_ring.rotation) and float_ring.position.is_equal_approx(FACINGS[i] * -4.0),
			"anti-water facing %s, driving: upright, 4 px behind" % FACINGS[i])
	await _face(boat, Vector2.LEFT, false)
	check(float_ring.position.is_equal_approx(Vector2.LEFT * -2.0), "anti-water still: 2 px behind")
	var ring_frames: Array = ThemeManager.get_addon_frames("memory-save")
	var seen: Array = []
	for i in range(12):
		var idx := ring_frames.find(ring.texture)
		if seen.is_empty() or seen[-1] != idx:
			seen.append(idx)
		await tree.create_timer(0.1).timeout
	check(seen.size() >= 4, "the ring cycles a frame about every 0.25 s (%d frames in 1.2 s)" % seen.size())

	print("\n[D] A player's add-ons follow the same rules")
	var player: PlayerTank = tree.get_nodes_in_group("players")[0]
	player.set_physics_process(false)
	player.apply_addon("anti-ice")
	player.apply_addon("moon-shield")
	await _face(player, Vector2.LEFT, true)
	var p_wings: Sprite2D = player._addon_sprites["anti-ice"]
	var p_shield: Sprite2D = player._addon_sprites["moon-shield"]
	check(frames.size() == 4 and p_wings.texture == frames[3] and is_zero_approx(p_wings.rotation)
		and p_wings.position.is_equal_approx(Vector2.LEFT * -4.0), "player anti-ice facing left: its frame, 4 px behind")
	check(shield_frames.size() == 4 and p_shield.texture == shield_frames[3] and p_shield.position.is_equal_approx(Vector2.LEFT * 8.0),
		"player moon shield facing left: its frame, 8 px ahead")

	print("\n[E] A tank thrown by a mine shows no add-on until it lands")
	skater.max_health = 99
	skater.health = 99   # its own landing blast must not finish it,
	skater._hits_taken = 5   # nor knock the add-on off (the second-hit drop)
	skater.launch_mine_fly(2, skater.global_position + Vector2(-40, 0))
	await tree.process_frame
	await tree.process_frame
	check(not wings.visible, "wings hidden in the air")
	while skater.is_flying:
		skater._update_flying(1.0 / 60.0)
	await tree.process_frame
	await tree.process_frame
	check(wings.visible, "wings back on landing")

	await tree.create_timer(1.0).timeout  # let the landing blast's sound finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
