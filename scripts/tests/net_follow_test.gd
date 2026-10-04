extends Node
## Headless test for online lag compensation's parts (docs/network_design.md,
## section 7), in one offline process: the host's copy of a client's tank
## following where that client drives it (at up to twice its speed, the long
## way round a turn, stopped by walls and enemies), the corrections it sends
## when held up and when the host drives the tank itself (a mine's flight, a
## hold), its shots, and what it tells the clients; then the client's side: its
## own tank driven at once and reported, put back by a correction, and its own
## shells drawn ahead. The two machines together are online_lag_test's.
## Run as an override main scene:
##   Godot --headless res://scenes/test/net_follow_test.tscn

## The client driving tank 1 here: a peer id no real one has.
const PEER := 9

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


func _at(local: Vector2) -> Vector2:
	return _lm.global_position + local


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## The client says its tank is at [param local], facing [param facing], having
## taken correction [param override] (the host's latest unless given).
func _report(local: Vector2, facing: Vector2, moving: bool = true, override: int = -1) -> void:
	PlayerInput.set_remote_report(PEER, 0, true, _at(local), BaseTank.FACINGS.find(facing), moving,
			_player.net_override if override < 0 else override)


func _place(local: Vector2, facing: Vector2) -> void:
	_player.global_position = _at(local)
	_player.current_direction = facing
	_player._update_sprite_direction()


func _iron(local: Vector2) -> void:
	var cell := _lm.world_to_tile(_at(local))
	_lm._place_fg_tile(cell, 0x39)


func _spawn_enemy(local: Vector2) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = 1
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _at(local)
	return e


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
	for p in tree.get_nodes_in_group("players"):
		_player = p
	while _player.is_materializing:
		await tree.process_frame
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	# Open ground in the middle of the field.
	for tile in _lm._fg_tile_data.keys():
		if tile.x >= 4 and tile.x <= 36 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		if tile.x >= 4 and tile.x <= 36 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_bg_tile(tile)
	_player.is_invincible = true
	_player.invincible_timer = 999.0
	await tree.process_frame
	var speed := _player.move_speed
	var step_most := speed * PlayerTank.FOLLOW_SPEED * get_physics_process_delta_time() + 0.01
	var home := Vector2(320, 384)

	print("\n[A] A client's tank: the host's copy goes after it")
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [0, 0])
	PlayerInput.set_seat(0, PlayerInput.controller_key(PEER, 0))
	check(PlayerInput.is_remote_seat(0) and PlayerInput.remote_report(0) == null, "a client's seat, nothing heard of its tank yet")
	_place(home, Vector2.RIGHT)
	Input.action_press("p1_right")
	await _wait_frames(10)
	Input.action_release("p1_right")
	check(_player.global_position == _at(home) and not _player.is_moving,
		"it waits for word: the host's own keys don't drive it")
	var override := _player.net_override
	var target := home + Vector2(160, 0)
	_report(target, Vector2.RIGHT)
	var biggest := 0.0
	var last := _player.global_position
	for i in 45:
		await tree.physics_frame
		biggest = maxf(biggest, last.distance_to(_player.global_position))
		last = _player.global_position
	check(_player.global_position.distance_to(_at(target)) < 0.01, "it gets to where the client's tank is, 160 px on")
	check(biggest <= step_most and biggest > speed * get_physics_process_delta_time() * 1.5,
		"catching up at up to twice its speed: %.2f px a frame (most %.2f)" % [biggest, step_most])
	check(_player.net_override == override, "catching up, far behind for a while, is no correction")
	_report(target + Vector2(100, 0), Vector2.RIGHT, true, (override + 255) % 256)
	await _wait_frames(10)
	check(_player.global_position.distance_to(_at(target)) < 0.01 and not _player.is_moving,
		"a report that hasn't taken the latest correction is left alone")

	# The client went on 48 px, turned up and went 64 px: the copy goes round the
	# corner the same way, not across it.
	var corner := target + Vector2(48, 0)
	var turned := corner + Vector2(0, -64)
	_report(turned, Vector2.UP)
	var on_the_way := true
	for i in 45:
		await tree.physics_frame
		var at := _player.global_position - _lm.global_position
		var along_first := absf(at.y - target.y) < 0.01 and _player.current_direction == Vector2.RIGHT
		var then_up := absf(at.x - corner.x) < 0.01 and _player.current_direction == Vector2.UP
		on_the_way = on_the_way and (along_first or then_up)
	check(_player.global_position.distance_to(_at(turned)) < 0.01, "round a turn to it")
	check(on_the_way, "on to the corner first, then up: the way it went, facing the way it goes")
	# A turn's own snap to the half-tile grid comes at once.
	var snapped := turned + Vector2(20, -6)
	_report(snapped, Vector2.RIGHT)
	await _wait_frames(1)
	var now := _player.global_position - _lm.global_position
	check(absf(now.y - snapped.y) < 0.01 and _player.current_direction == Vector2.RIGHT,
		"a turn's snap across its way comes at once, as the client's did")
	await _wait_frames(10)
	check(_player.global_position.distance_to(_at(snapped)) < 0.01, "and on to it")
	var stand := snapped
	_report(stand, Vector2.RIGHT, false)
	await _wait_frames(2)
	check(not _player.is_moving and _player.velocity == Vector2.ZERO and _player.net_state()[3] & BaseTank.NET_MOVING == 0,
		"the client's tank stands still: so does the copy, for everyone to see")

	print("\n[B] Held up by what the client didn't see in time: the client starts again")
	_place(home, Vector2.RIGHT)
	_report(home, Vector2.RIGHT, false)
	await _wait_frames(2)
	# Iron two tiles past the tank's front, two tiles high: x 416..448.
	for y in [-16, 16]:
		_iron(home + Vector2(112, y))
	override = _player.net_override
	_report(home + Vector2(200, 0), Vector2.RIGHT)
	await tree.create_timer(0.25).timeout
	check(_player.net_override == override, "on its way to the client's tank: no correction")
	await tree.create_timer(0.45).timeout
	var stopped := _player.global_position - _lm.global_position
	check(absf(stopped.x + BaseTank.HITBOX_SIZE * 0.5 - (home.x + 96.0)) < 1.0,
		"a wall here stops the copy short of it, against the wall: %.1f" % stopped.x)
	check(_player.net_override == (override + 1) % 256, "held up too long: a correction")
	_report(home + Vector2(200, 0), Vector2.RIGHT, true, override)
	await _wait_frames(10)
	check(_player.global_position.distance_to(_at(stopped)) < 0.5, "until the client takes it, the copy waits")
	_report(stopped, Vector2.RIGHT, false)
	await _wait_frames(2)
	check(_player.global_position.distance_to(_at(stopped)) < 0.5 and _player.net_override == (override + 1) % 256,
		"the client starts again from there: followed again")
	for y in [-16, 16]:
		_lm._remove_fg_tile(_lm.world_to_tile(_at(home + Vector2(112, y))))

	_place(home, Vector2.RIGHT)
	_report(home, Vector2.RIGHT, false)
	await _wait_frames(2)
	var bot := _spawn_enemy(home + Vector2(130, 0))
	override = _player.net_override
	_report(home + Vector2(200, 0), Vector2.RIGHT)
	await tree.create_timer(0.9).timeout
	var gap: float = bot.global_position.x - _player.global_position.x - BaseTank.HITBOX_SIZE
	check(gap >= 0.0 and gap < 8.0, "an enemy in the way stops it, as it stops any player (gap %.1f px)" % gap)
	check(_player.net_override == (override + 1) % 256, "and the client is told to start again from there")
	bot.queue_free()
	await tree.process_frame

	print("\n[C] The host drives it itself: the client starts again from where that ends")
	_place(home, Vector2.RIGHT)
	_report(home, Vector2.RIGHT, false)
	await _wait_frames(2)
	override = _player.net_override
	_player.launch_mine_fly(2, _player.global_position + Vector2(-20, 0))
	await _wait_frames(2)
	check(_player.is_flying and _player.net_override == (override + 1) % 256, "a mine throws it: a correction at once")
	_report(home, Vector2.RIGHT, false, override)  # the client's word from before it knew
	while _player.is_flying:
		await tree.physics_frame
	var landed := _player.global_position - _lm.global_position
	check(landed.distance_to(home) > 100.0, "the flight carried it %.0f px, the client's word notwithstanding" % landed.distance_to(home))
	await _wait_frames(3)
	check(_player.net_override == (override + 1) % 256 and _player.global_position.distance_to(_at(landed)) < 0.01,
		"landed: no more corrections, and the old word is left alone")
	var facing_now := _player.current_direction
	_report(landed + facing_now * 30.0, facing_now)
	await _wait_frames(10)
	check(_player.global_position.distance_to(_at(landed + facing_now * 30.0)) < 0.01,
		"the client drives on from where it landed: followed")
	override = _player.net_override
	GameManager.players_frozen = true
	GameManager.players_freeze_timer = 0.3
	await _wait_frames(2)
	check(_player.net_override == (override + 1) % 256, "an enemy's hold: a correction at once")
	while GameManager.players_frozen:
		await tree.physics_frame
	await _wait_frames(2)
	check(_player.net_override == (override + 1) % 256, "and none when it ends")

	print("\n[D] Its shots and what the clients get")
	_place(home, Vector2.RIGHT)
	_report(home, Vector2.RIGHT, false)
	await _wait_frames(2)
	PlayerInput.set_remote(PEER, 0, -1, [true, false], [1, 0])
	await _wait_frames(3)
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [1, 0])
	var shell: Bullet = null
	for node in tree.get_nodes_in_group(NetWorld.GROUP):
		if node is Bullet and node.owner_player == 0:
			shell = node
	check(shell != null and shell.direction == Vector2.RIGHT and (shell.global_position - _player.global_position).x > 20.0
		and absf((shell.global_position - _player.global_position).y) < 20.0,
		"the client's fire: a shell out of the copy's barrel, where the copy is")
	var args := shell.net_spawn_args() if shell else []
	check(args.size() == 7 and args[3] == 0 and is_equal_approx(float(args[4]), shell.speed),
		"the clients learn whose shell it is and how fast it set out: %s" % str(args))
	var state := _player.net_state()
	check(state.size() == PlayerTank.NET_OVERRIDE_AT + 1 and state[PlayerTank.NET_OVERRIDE_AT] == _player.net_override,
		"the copy's state carries the latest correction")
	_player.apply_mine_slow()
	check(_player.net_state()[3] & PlayerTank.NET_SLOWED != 0, "and a mine's slowing, so the client drives slow too")
	_player.clear_mine_slow()
	if shell:
		shell.queue_free()

	print("\n[E] The client's side: its own tank, driven at once")
	PlayerInput.reset_to_local()
	_player.set_physics_process(false)
	_place(home, Vector2.UP)
	_player.set_net_predicted(true, 0)
	check(_player.is_net_driving() and _player.collision_layer == 4 and _player.collision_mask == 1 | 2 | 128,
		"a client's own tank: it bumps into walls, water and the base here")
	_player.set_net_predicted(false, 0)
	check(not _player.is_net_driving() and _player.collision_layer == 0 and _player.collision_mask == 0,
		"anyone else's touches nothing")
	_player.has_boat = true
	_player.set_net_predicted(true, 0)
	check(_player.collision_mask == 1 | 128, "with a boat, water doesn't stop it")
	_player.set_net_predicted(false, 0)
	_player.has_boat = false
	_player.set_net_predicted(true, 0)
	# A client's tanks touch nothing (the host's world shows there): an enemy
	# stops its own tank all the same, unless it's still materializing.
	_place(home, Vector2.LEFT)
	var shown := _spawn_enemy(home + Vector2(-61, 0))
	NetClientWorld._strip_physics(shown)
	Net.role = Net.Role.CLIENT
	var solid_shown := shown.is_solid() and _player._is_enemy_ahead()
	shown.is_materializing = true
	var solid_coming := shown.is_solid() or _player._is_enemy_ahead()
	Net.role = Net.Role.OFFLINE
	check(solid_shown and not solid_coming,
		"on a client, an enemy (touching nothing there) stops the client's own tank; one materializing doesn't")
	shown.queue_free()
	await tree.process_frame
	_place(home, Vector2.UP)
	var level: int = GameManager.player_speed_levels[0]
	GameManager.player_speed_levels[0] = 3
	_player._predict()
	check(_player.move_speed == PlayerTank.SPEED_MAP[3], "it drives at the speed the host says it has")
	GameManager.player_speed_levels[0] = level
	_player._predict()
	_place(home, Vector2.UP)
	Input.action_press("p1_left")
	for i in 10:
		await tree.physics_frame
		_player._predict()
	Input.action_release("p1_left")
	var went := _at(home) - _player.global_position
	check(absf(went.x - speed * 10.0 * get_physics_process_delta_time()) < 0.5 and absf(went.y) < 0.01,
		"the keys drive it at once, at its speed: %.1f px in 10 frames" % went.x)
	var report: Dictionary = Net._tank_reports[0]
	check(report.get("position") == _player.global_position and report.get("facing") == 3 and report.get("moving") == true
		and report.get("override") == _player._override_seen, "where it is goes to the host: %s" % str(report))
	var bytes := Net._input_message()
	var where := Net.REPORT_AT
	check(bytes.size() == Net.INPUT_SIZE and bytes[where] == 3 and bytes[where + 1] == 3
		and bytes[where + 2] == _player._override_seen % 256
		and Vector2(bytes.decode_float(where + 4), bytes.decode_float(where + 8)).distance_to(_player.global_position) < 0.01,
		"with its next input message: there, facing left, driving, the corrections taken")
	Net.input_blocked = true
	Input.action_press("p1_left")
	var before := _player.global_position
	for i in 3:
		await tree.physics_frame
		_player._predict()
	Input.action_release("p1_left")
	Net.input_blocked = false
	check(_player.global_position == before, "not while its own menu has the keys")
	for i in 4:
		await tree.physics_frame
	check(Net._input_message()[where] == 0, "a report gone stale (it stopped driving here) isn't sent")

	# The host's correction, in a snapshot: back to where the host has it.
	var host_state := _player.net_state()
	host_state[0] = _at(home).x
	host_state[1] = _at(home).y
	host_state[2] = BaseTank.FACINGS.find(Vector2.DOWN)
	host_state[3] = 0
	host_state[PlayerTank.NET_OVERRIDE_AT] = (_player._override_seen + 1) % 256
	_player.net_apply(host_state)
	check(_player.global_position == _at(home) and _player.current_direction == Vector2.DOWN
		and _player._override_seen == host_state[PlayerTank.NET_OVERRIDE_AT],
		"a correction puts it where the host has it, facing the host's way")
	_player.global_position = _at(home + Vector2(40, 0))
	host_state[2] = BaseTank.FACINGS.find(Vector2.UP)
	host_state[3] = PlayerTank.NET_SLOWED
	_player.net_apply(host_state)
	check(_player.global_position == _at(home + Vector2(40, 0)) and _player.current_direction == Vector2.DOWN,
		"any other snapshot leaves it be: its place and facing are its own")
	check(_player.is_mine_slowed, "but a mine's slowing comes from the host")
	host_state[3] = 0
	_player.net_apply(host_state)
	_player.set_net_predicted(false, 0)
	host_state[PlayerTank.NET_OVERRIDE_AT] = (_player._override_seen + 1) % 256
	_player.net_apply(host_state)
	check(_player.global_position == _at(home + Vector2(40, 0)) and _player._override_seen == host_state[PlayerTank.NET_OVERRIDE_AT],
		"another's tank only takes note of a correction (NetClientWorld places it)")

	print("\n[F] Its own shells, drawn ahead by the trip")
	var world := NetClientWorld.new()
	world.setup(_game, _lm, null, {}, null)
	add_child(world)
	var own: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	own.net_setup([BaseTank.FACINGS.find(Vector2.RIGHT), "regular", [0.0], 0, 384.0, -1.0, false])
	_game.get_node("Entities/Bullets").add_child(own)
	own.set_physics_process(false)  # (after it's in: entering turns it on)
	NetClientWorld._strip_physics(own)
	Net.ping_ms = 150.0
	var lead := 384.0 * (150.0 + NetClientWorld.DELAY_MS) / 1000.0
	var shot_from := home + Vector2(0, -200)
	world._own_shells[77] = {"velocity": Vector2(384, 0), "start": _at(shot_from), "range": -1.0, "pierces": false}
	world._place(77, own, _at(shot_from))
	check(own.visible and own.global_position.distance_to(_at(shot_from + Vector2(lead, 0))) < 0.01,
		"drawn %.0f px ahead: 384 px/s for the 150 ms trip and the %d ms the world is shown behind" % [lead, NetClientWorld.DELAY_MS])
	world._place(78, own, _at(shot_from))
	check(own.global_position == _at(shot_from), "anyone else's: where the host has it")
	for y in [-16, 16]:
		_iron(shot_from + Vector2(64, y))
	world._place(77, own, _at(shot_from))
	check(not own.visible and own.global_position == _at(shot_from), "a wall before it gets there: hidden, its hit's on its way")
	world._own_shells[77]["pierces"] = true
	world._place(77, own, _at(shot_from))
	check(own.visible, "an AP shell drills on through")
	world._own_shells[77]["pierces"] = false
	for y in [-16, 16]:
		_lm._remove_fg_tile(_lm.world_to_tile(_at(shot_from + Vector2(64, y))))
	world._place(77, own, _at(shot_from))
	check(own.visible, "the wall gone: drawn again")
	var ahead_bot := _spawn_enemy(shot_from + Vector2(70, 10))
	await tree.process_frame
	world._place(77, own, _at(shot_from))
	check(not own.visible, "an enemy before it gets there: hidden")
	ahead_bot.queue_free()
	await tree.process_frame
	world._own_shells[77]["range"] = 60.0
	world._place(77, own, _at(shot_from))
	check(not own.visible, "past the end of a flame's range: hidden")
	Net.ping_ms = 0.0
	own.queue_free()
	world.queue_free()

	print("\n[G] The host's list of players: each one's ping")
	Net.peers[5] = {"name": "CLIENTA", "allow": [true, true]}
	var menu = _game.pause_menu
	check(menu._player_line(5) == "CLIENTA   ·   WATCHING", "not timed yet: no ping")
	Net.peers[5]["ping"] = 84
	PlayerInput.set_seat(1, PlayerInput.controller_key(5, 0))
	check(menu._player_line(5) == "CLIENTA   ·   DRIVING P2   ·   84 ms", "then the trip there and back: %s" % menu._player_line(5))
	Net.peers.erase(5)
	PlayerInput.reset_to_local()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
