extends Node
## Headless test for the hit grace, against Tank.exe's Damage (0x00492640): a
## player who survives a hit is untouchable for 0.5625 s and blinks; a blast's
## several points of damage still land as one hit; bots get no grace; and a
## mine's hit, paid as the thrown tank lands, costs no level and starts no grace.
## Run as an override main scene:
##   Godot --headless res://scenes/test/hit_grace_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _wait_vulnerable() -> void:
	while _player.is_invincible:
		await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_lm = _game.get_level_manager()
	_game.get_node("EnemySpawner").spawn_timer.stop()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	for tile in _lm._fg_tile_data.keys():
		if tile.y < 22:
			_lm._remove_fg_tile(tile)
	for tile in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(tile)
	_player = tree.get_nodes_in_group("players")[0]
	while _player.is_materializing:
		await tree.process_frame
	_player.global_position = _lm.global_position + Vector2(640, 384)
	await _wait_vulnerable()

	print("\n[A] A hit the player survives: 0.56 s untouchable, blinking")
	_player.health = 6
	_player.take_damage()
	check(_player.health == 5 and _player.is_invincible and is_equal_approx(_player.invincible_timer, 0.5625),
		"hit: -1 HP, then %.4f s of grace" % _player.invincible_timer)
	var shown: Array = []
	for i in range(4):
		await tree.process_frame
		shown.append(_player.visible)
	var wreath: Sprite2D = _player._state_fx_sprite   # never made unless a wreath was shown
	check(shown.has(true) and shown.has(false) and (wreath == null or not wreath.visible),
		"the grace blinks, no wreath (%s)" % str(shown))
	_player.take_damage()
	check(_player.health == 5, "a second hit during the grace is ignored")
	await _wait_vulnerable()
	_player.take_damage()
	check(_player.health == 4, "once the grace is over, hits land again")

	print("\n[B] A blast's several points land together as one hit")
	await _wait_vulnerable()
	_player.health = 6
	_lm.spawn_explosion_blast(_player.global_position, 2, false)   # an enemy blast: 3 points
	await tree.process_frame
	await tree.process_frame
	check(_player.health == 3 and _player.is_invincible, "all 3 points landed, then the grace (hp %d)" % _player.health)

	print("\n[C] Bots get no grace")
	var bot: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	_game.get_node("Entities/Enemies").add_child(bot)
	bot.set_physics_process(false)
	bot.global_position = _lm.global_position + Vector2(320, 320)
	bot.max_health = 10
	bot.health = 10
	await tree.process_frame
	bot.take_damage()
	await tree.process_frame
	bot.take_damage()
	check(bot.health == 8, "two hits a frame apart both land on a bot (hp %d)" % bot.health)
	bot.queue_free()

	print("\n[D] Thrown by a mine: its landing hit costs no level and starts no grace")
	await _wait_vulnerable()
	_player.health = 6
	_player.speed_level = 2
	_player.weapon_level = 2
	var cell := Vector2i(24, 10)
	var mine := _lm._spawn_mine(cell, 2, false)   # an enemy level-2 mine
	await tree.process_frame
	mine._age = Mine.ARM_TIME + 0.001
	_player.global_position = _lm.mine_center(cell)
	await tree.create_timer(0.25).timeout
	check(_player.is_flying and _player.health == 6, "thrown, and nothing lost in the air (hp %d)" % _player.health)
	while _player.is_flying:
		_player._update_flying(1.0 / 60.0)
	check(_player.health == 5, "the level-2 mine's hit lands with it: 1 HP (hp %d)" % _player.health)
	check(_player.speed_level == 2 and _player.weapon_level == 2, "landing hit: no speed or gun level lost")
	check(not _player.is_invincible, "landing hit: no grace")
	await tree.process_frame
	await tree.process_frame
	check(_player.health < 5 and _player.is_invincible, "the landing blast hits on the ground, and that starts the grace")

	await tree.create_timer(2.0).timeout  # let the mine's 1.6 s blast sound finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)

