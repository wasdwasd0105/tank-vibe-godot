extends Node
## Headless test for the special weapon's button while the regular gun's is
## held down (Sean, 2026-10-11: "when hold the regular weapon, plz do not
## block the special weapon's fire. Apply on both keyboard and gamepad"): on
## the keys, a controller's buttons and its triggers, fire 2 pressed fires the
## special weapon at once, the regular gun's reload never holding it; held with
## fire 1, it fires on at its own rate in the regular gun's place, and let go,
## the regular gun fires on. A mine is laid at once too, and the regular gun's
## shells in flight never hold it either. An empty special weapon, or one with
## all the shells of its kind it may have in flight, leaves the regular gun
## firing as ever (and makes no sound); a special shot's own reload still holds
## both guns.
## Run as an override main scene:
##   Godot --headless res://scenes/test/fire_buttons_test.tscn

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank
## Player 1's shells as they're fired: [physics frame, style ("regular", "rapid"...)].
var _shots: Array = []


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## [param way]'s fire button [param button] pressed as a player's is: between
## two frames, so the next physics step sees it pressed just then. Returns
## the number of the physics frames run before it.
func _press(way: String, button: int) -> int:
	await get_tree().process_frame
	_fire(way, button, true)
	return Engine.get_physics_frames()


## Holds or lets go player 1's fire button [param button] (0 the regular gun,
## 1 the special weapon) on [param way]: "keys" (its bound keys), "pad" (A and
## X on its controller) or "triggers" (RT and LT).
func _fire(way: String, button: int, down: bool) -> void:
	var ev: InputEvent
	match way:
		"keys":
			var key := InputSettings.get_binding(["p1_shoot", "p1_shoot2"][button]) as Key
			var press := InputEventKey.new()
			press.keycode = key
			press.physical_keycode = key
			press.pressed = down
			ev = press
		"pad":
			var press := InputEventJoypadButton.new()
			press.device = 0
			press.button_index = [JOY_BUTTON_A, JOY_BUTTON_X][button]
			press.pressed = down
			ev = press
		"triggers":
			var pull := InputEventJoypadMotion.new()
			pull.device = 0
			pull.axis = [JOY_AXIS_TRIGGER_RIGHT, JOY_AXIS_TRIGGER_LEFT][button]
			pull.axis_value = 1.0 if down else 0.0
			ev = pull
	Input.parse_input_event(ev)
	Input.flush_buffered_events()   # parsed events otherwise wait for the next frame


## Every button let go on every way, and both guns' reloads run out.
func _settle() -> void:
	for way: String in ["keys", "pad", "triggers"]:
		for button in 2:
			_fire(way, button, false)
	await get_tree().create_timer(0.9).timeout


func _arm(special: String, count: int, level: int = 1) -> void:
	_player.weapon_level = level
	_player._apply_weapon_upgrade()
	GameManager.set_weapon_level(0, level)
	_player.secondary_weapon_type = special
	_player.secondary_weapon_count = count
	GameManager.set_secondary_weapon(0, special, count)


## The shots of [param style] logged from index [param from] on.
func _count(style: String, from: int = 0) -> int:
	var n := 0
	for i in range(from, _shots.size()):
		if _shots[i][1] == style:
			n += 1
	return n


## The physics frame of the first shot of [param style] from index [param from] on, or -1.
func _first(style: String, from: int = 0) -> int:
	for i in range(from, _shots.size()):
		if _shots[i][1] == style:
			return int(_shots[i][0])
	return -1


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	AudioServer.set_bus_mute(0, true)
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
	_player = tree.get_nodes_in_group("players")[0]
	while _player.is_materializing:
		await tree.process_frame
	_player.is_invincible = true
	_player.invincible_timer = 999.0
	# Open ground all round, the tank in the middle facing up.
	for tile in _lm._fg_tile_data.keys():
		if tile.y < 22:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(tile)
	_player.global_position = _lm.global_position + Vector2(640, 576)
	_player.current_direction = Vector2.UP
	_player._update_sprite_direction()
	_game.get_node("Entities/Bullets").child_entered_tree.connect(func(node: Node) -> void:
		var shell := node as Bullet
		if shell and shell.owner_player == 0:
			_shots.append([Engine.get_physics_frames(), shell.visual_style]))
	await tree.physics_frame

	for way: String in ["keys", "pad", "triggers"]:
		print("\n[%s] Fire 2 while fire 1 is held: the special weapon at once, and on in the regular gun's place" % way)
		_arm("rapid", 50)
		await _settle()
		_shots.clear()
		await _press(way, 0)
		await _frames(8)   # its first shot, and 0.13 s into its reload (0.4 s at gun level 1)
		check(_count("regular") == 1 and _count("rapid") == 0, "%s: fire 1 held, the regular gun fires" % way)
		var pressed_at := await _press(way, 1)
		await _frames(3)
		var special_at := _first("rapid")
		check(special_at > pressed_at and special_at - pressed_at <= 2,
			"%s: fire 2 pressed mid the regular gun's reload: the special weapon fires at once (%s)"
			% [way, "frame %d after" % (special_at - pressed_at) if special_at >= 0 else "not at all"])
		var from := _shots.size()
		await tree.create_timer(1.0).timeout
		check(_count("rapid", from) >= 3 and _count("regular", from) == 0,
			"%s: both held: the special weapon fires on at its own rate, in the regular gun's place (%d in 1 s, %d regular)"
			% [way, _count("rapid", from), _count("regular", from)])
		_fire(way, 1, false)
		from = _shots.size()
		await tree.create_timer(0.6).timeout
		check(_count("regular", from) >= 1 and _count("rapid", from) == 0,
			"%s: fire 2 let go: the regular gun fires on (%d)" % [way, _count("regular", from)])
		_fire(way, 0, false)

	print("\n[M] A mine laid at once with fire 1 held")
	_arm("mine", 10)
	await _settle()
	_shots.clear()
	var mines := _lm.get_mines().size()
	await _press("keys", 0)
	await _frames(8)
	await _press("keys", 1)
	await _frames(2)
	check(_lm.get_mines().size() == mines + 1 and _player.secondary_weapon_count == 9 and _count("regular") == 1,
		"fire 2 pressed mid the regular gun's reload: a mine laid at once")
	_fire("keys", 1, false)
	await _frames(3)
	await _press("keys", 1)
	await _frames(2)
	check(_lm.get_mines().size() == mines + 1 and _player.secondary_weapon_count == 9 and _count("regular") == 1,
		"pressed again straight after: nothing through the mine's own reload")
	_fire("keys", 1, false)
	_fire("keys", 0, false)

	print("\n[E] An empty special weapon leaves the regular gun firing")
	_arm("rapid", 0)
	await _settle()
	_shots.clear()
	await _press("keys", 0)
	_fire("keys", 1, true)
	await tree.create_timer(1.0).timeout
	check(_count("regular") >= 2 and _count("rapid") == 0,
		"both held, no special ammo: the regular gun fires as ever (%d in 1 s)" % _count("regular"))
	_fire("keys", 1, false)
	_fire("keys", 0, false)

	print("\n[L] A special weapon with all its shells in flight: the regular gun fires, and no sound of it")
	_arm("explosion", 20)
	await _settle()
	_shots.clear()
	var limit := int(CookieData.get_weapon_fire_config("explosion", 1)["max_in_flight"])
	_player.active_explosion_bullets = limit
	var heard: int = SoundManager._last_played.get(&"fire_explosion", -1)
	await _press("keys", 0)
	_fire("keys", 1, true)
	await tree.create_timer(1.0).timeout
	check(_count("regular") >= 2 and _count("explosion") == 0 and _player.secondary_weapon_count == 20,
		"both held, %d explosion shells flying: the regular gun fires as ever (%d in 1 s)" % [limit, _count("regular")])
	check(SoundManager._last_played.get(&"fire_explosion", -1) == heard,
		"and the explosion gun makes no sound when no shell leaves it")
	_fire("keys", 1, false)
	_fire("keys", 0, false)
	_player.active_explosion_bullets = 0

	print("\n[C] The regular gun's shells in flight don't hold it either")
	_arm("rapid", 50)
	await _settle()
	_shots.clear()
	_player.active_bullets = PlayerTank.PLAYER_MAX_ACTIVE_BULLETS   # as if a dozen regular shells flew
	await _press("keys", 1)
	await _frames(2)
	_fire("keys", 1, false)
	check(_count("rapid") == 1, "a dozen shells of the regular gun flying: fire 2 still fires")
	_player.active_bullets = 0

	print("\n[R] A special shot's own reload holds both guns")
	_arm("rapid", 50)
	await _settle()
	_shots.clear()
	await _press("keys", 1)
	await _frames(2)
	_fire("keys", 1, false)
	var shot_at := _first("rapid")
	await _frames(5)
	await _press("keys", 0)   # pressed mid the special shot's reload (0.3 s at gun level 1)
	_fire("keys", 1, true)
	await _frames(2)
	_fire("keys", 1, false)
	await tree.create_timer(0.1).timeout
	check(shot_at >= 0 and _shots.size() == 1,
		"fire 1 and fire 2 pressed 0.1 s after a special shot: neither fires through its reload (%d shots)" % _shots.size())
	await tree.create_timer(0.35).timeout
	var regular_at := _first("regular")
	check(regular_at >= 0 and regular_at - shot_at >= 16,
		"the regular gun, held, fires once that reload is over (%d frames after it)" % (regular_at - shot_at))
	_fire("keys", 0, false)

	await tree.create_timer(0.5).timeout
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
