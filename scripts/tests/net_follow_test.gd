extends Node
## Headless test for online lag compensation's parts (docs/network_design.md,
## section 7), in one offline process: the host's copy of a client's tank
## following where that client drives it (at up to twice its speed, the long
## way round a turn, stopped by walls and enemies), the corrections it sends
## when held up and when the host drives the tank itself (a mine's flight, a
## hold), its shots, what it tells the clients, and a client with lag
## compensation off driving it with its keys as before. Then the client's side:
## its own tank driven at once and reported, put back by a correction, its own
## shots fired at once as ghosts the host's shells take over, their sounds heard
## once, its own shells drawn ahead, and how far behind the host the world is
## shown (SMOOTHING). The two machines together are online_lag_test's.
## Run as an override main scene:
##   Godot --headless res://scenes/test/net_follow_test.tscn

## The client driving tank 1 here: a peer id no real one has.
const PEER := 9

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank
## The client as the host hears of it: a report each of its frames while
## _feeding (_physics_process), of its tank as _report last put it, or that it
## doesn't drive one there (_client_has off); _client_frame counts its frames.
var _feeding := false
var _client_frame := 0
var _client_has := true
var _client_predicts := true
var _client_at := Vector2.ZERO
var _client_facing := Vector2.UP
var _client_moving := false
var _client_override := 0


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


## From now the client says its tank is at [param local], facing
## [param facing], having taken correction [param override] (the host's latest
## unless given): its report every frame (_physics_process), as a client sends.
func _report(local: Vector2, facing: Vector2, moving: bool = true, override: int = -1) -> void:
	_feeding = true
	_client_has = true
	_client_predicts = true
	_client_at = local
	_client_facing = facing
	_client_moving = moving
	_client_override = _player.net_override if override < 0 else override


## One report from the client, its next frame's, as it comes in.
func _send_report(local: Vector2, facing: Vector2, moving: bool, override: int) -> void:
	_client_frame += 1
	PlayerInput.set_remote_report(PEER, 0, _client_has, _client_predicts, _at(local), BaseTank.FACINGS.find(facing),
			moving, override, _client_frame & 0xff)


## The client's report each frame, ahead of the tanks' (this node comes first).
func _physics_process(_delta: float) -> void:
	if _feeding:
		_send_report(_client_at, _client_facing, _client_moving, _client_override)


## The client stops driving its tank and starts again at [param local], facing
## [param facing], the copy put there too: a fresh run of reports, to be sent
## by hand (_drive_a_frame).
func _start_run(local: Vector2, facing: Vector2) -> void:
	_feeding = false
	_client_has = false
	_send_report(local, facing, false, 0)
	_client_has = true
	_client_predicts = true
	_place(local, facing)
	_client_at = local
	_client_facing = facing


## The client's tank goes on [param stride] the way it faces, a frame of its
## own, and its report of that comes in.
func _drive_a_frame(stride: float) -> void:
	_client_at += _client_facing * stride
	_send_report(_client_at, _client_facing, true, _player.net_override)


## The playback as on a steady line so far: every report on time, so a frame
## behind them is enough; [param settled], it's there already.
func _steady_so_far(settled: bool = false) -> void:
	var pad := PlayerInput.remote_pad(0)
	pad.report_late.clear()
	for i in 40:
		pad.report_late.append(0.0)
	if settled:
		_player._play_seen = -1


## How many of the client's frames behind its newest report the copy is shown.
func _frames_behind() -> float:
	return PlayerInput.remote_report_frame(0) - _player._play_at


## Fires as the client's own tank would on a client: its shot predicted here.
## (The role is a client's only for the call: Net's own frames would try to join.)
func _fire_here() -> void:
	Net.role = Net.Role.CLIENT
	_player._predict_fire()
	Net.role = Net.Role.OFFLINE


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
	check(PlayerInput.is_remote_seat(0) and PlayerInput.remote_report_frame(0) == -1, "a client's seat, nothing heard of its tank yet")
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
	for i in 55:
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
	for i in 20:
		await tree.physics_frame
		if _player.current_direction == Vector2.RIGHT:
			break
	var now := _player.global_position - _lm.global_position
	check(absf(now.y - snapped.y) < 0.01 and _player.current_direction == Vector2.RIGHT,
		"a turn's snap across its way comes at once, as the client's did")
	await _wait_frames(10)
	check(_player.global_position.distance_to(_at(snapped)) < 0.01, "and on to it")
	var stand := snapped
	_report(stand, Vector2.RIGHT, false)
	await _wait_frames(int(PlayerTank.PLAY_DELAY_START) + 3)
	check(not _player.is_moving and _player.velocity == Vector2.ZERO and _player.net_state()[3] & BaseTank.NET_MOVING == 0,
		"the client's tank stands still: so does the copy, for everyone to see")
	# The client drives on at its speed, a report every frame of its own, but
	# they come in unevenly, as a network brings them: two at once, then none.
	var stride := speed * get_physics_process_delta_time()
	var arrivals: Array[int] = [0, 2, 0, 1, 1, 3, 0, 0, 2, 1, 0, 2, 1, 1, 0, 2]
	var driving := stand
	var last_at := _player.global_position
	var steps: Array[float] = []
	_feeding = false  # (the reports come here as these patterns say)
	for pass_number in 3:
		for count: int in arrivals:
			for i in count:
				driving += Vector2.RIGHT * stride
				_send_report(driving, Vector2.RIGHT, true, _player.net_override)
			await tree.physics_frame
			steps.append(_player.global_position.distance_to(last_at))
			last_at = _player.global_position
	var settled := steps.slice(arrivals.size())
	var worst: float = settled.map(func(step: float) -> float: return absf(step - stride)).max()
	check(worst < stride * 0.25, "they come unevenly: the copy goes on a frame's way every frame, %.2f px (%.2f px off at most)" % [
		stride, worst])
	# A connection that stalls 80 ms now and then and makes up for it: from
	# the shortest wait, the playback learns to sit far enough behind. (Back
	# the other way, to stay on the open ground.)
	var stalling: Array[int] = [0, 0, 0, 0, 0, 6, 1, 1, 1, 1, 1, 1]
	_steady_so_far()
	steps.clear()
	for pass_number in 8:
		for count: int in stalling:
			for i in count:
				driving += Vector2.LEFT * stride
				_send_report(driving, Vector2.LEFT, true, _player.net_override)
			await tree.physics_frame
			steps.append(_player.global_position.distance_to(last_at))
			last_at = _player.global_position
	worst = steps.slice(steps.size() - stalling.size()).map(func(step: float) -> float: return absf(step - stride)).max()
	check(worst < stride * 0.25 and _frames_behind() > 5.0,
		"they stall and catch up: it learns to wait far enough behind, steady again (%.2f px off, %.1f frames behind)" % [
			worst, _frames_behind()])
	# The client's line gets quicker by three frames: its reports come three
	# frames sooner from then on. That moves the reports' clock on, but what's
	# shown goes on evenly, a little faster, without a jump.
	steps.clear()
	for i in 60:
		var count := 4 if i == 30 else 1
		for c in count:
			driving += Vector2.RIGHT * stride
			_send_report(driving, Vector2.RIGHT, true, _player.net_override)
		await tree.physics_frame
		if i >= 15:  # (turned round and going again)
			steps.append(_player.global_position.distance_to(last_at))
		last_at = _player.global_position
	worst = steps.map(func(step: float) -> float: return absf(step - stride)).max()
	check(worst < stride * 0.25, "its reports come three frames sooner from then on: no jump (%.2f px off at most)" % worst)
	# Settled on a steady line a frame behind, then its reports start coming
	# later: while the delay grows (towards six frames), what's shown goes on a
	# little slower, evenly, the way between reports.
	var late_seen := PlayerInput.remote_pad(0).report_late
	_steady_so_far(true)
	steps.clear()
	for i in 50:
		if i == 20:
			for j in 40:
				late_seen.append(5.0)
		driving += Vector2.LEFT * stride
		_send_report(driving, Vector2.LEFT, true, _player.net_override)
		await tree.physics_frame
		if i >= 22:
			steps.append(_player.global_position.distance_to(last_at))
		last_at = _player.global_position
	var slowest: float = steps.min()
	var fastest: float = steps.max()
	check(fastest - slowest < stride * 0.05 and fastest < stride and _frames_behind() > PlayerTank.PLAY_DELAY_MIN + 2.0,
		"the delay growing: it goes on evenly, a little slower, %.2f to %.2f px a frame, %.1f frames behind by now" % [
			slowest, fastest, _frames_behind()])
	# On a steady line it plays only a frame behind; then three reports come
	# late at once. Past the newest meanwhile, the copy carries on its way
	# rather than stopping, and goes on evenly when they come.
	_steady_so_far(true)
	steps.clear()
	var held_back: Array[Vector2] = []
	var past := 0.0
	for i in 70:
		driving += Vector2.RIGHT * stride
		if i >= 50 and i < 53:
			held_back.append(driving)
		else:
			for late: Vector2 in held_back:
				_send_report(late, Vector2.RIGHT, true, _player.net_override)
			held_back.clear()
			_send_report(driving, Vector2.RIGHT, true, _player.net_override)
		await tree.physics_frame
		past = maxf(past, -_frames_behind())
		if i >= 40:
			steps.append(_player.global_position.distance_to(last_at))
		last_at = _player.global_position
	var stalled := steps.filter(func(step: float) -> bool: return step < stride * 0.5).size()
	check(stalled == 0 and past > 1.0,
		"three reports late at once: it carries on its way meanwhile (%.1f frames past the newest), no stall (%d)" % [past, stalled])
	_report(driving, Vector2.RIGHT, false)
	await _wait_frames(int(PlayerTank.PLAY_DELAY_MAX) + 2)

	print("\n[A2] Either machine's frames slip: the copy keeps up all the same")
	# This machine stands still for two thirds of a second, four times over (its
	# window going fullscreen or out of sight, a stage loading): each time, the
	# frames the client drove meanwhile come at once. The copy is never left
	# behind for it: it makes up the way at its catching-up speed, then goes on
	# evenly, a little faster until it's back in its place.
	_start_run(Vector2(176, 448), Vector2.RIGHT)
	for i in 20:
		_drive_a_frame(stride)
		await tree.physics_frame
	check(_frames_behind() > 0.5 and _frames_behind() < 5.0,
		"a fresh run of reports is played by its own clock, not the last run's: %.1f frames behind its newest" % _frames_behind())
	for stall in 4:
		for i in 40:
			_drive_a_frame(stride)
		for i in 40:
			await tree.physics_frame
			_drive_a_frame(stride)
	steps.clear()
	last_at = _player.global_position
	for i in 80:
		await tree.physics_frame
		_drive_a_frame(stride)
		if i >= 40:
			steps.append(_player.global_position.distance_to(last_at))
		last_at = _player.global_position
	await tree.physics_frame
	var behind := _player.global_position.distance_to(_at(_client_at)) / stride
	check(behind < 20.0, "this machine stood still four times, two thirds of a second each: the copy is %.1f frames' way behind the client's tank, no more" % behind)
	slowest = steps.min()
	fastest = steps.max()
	check(slowest > stride * 0.95 and fastest < stride * 1.15,
		"and goes on evenly, a little faster to make it up: %.2f to %.2f px a frame (the client's %.2f)" % [slowest, fastest, stride])
	# The client's machine stands still for half a second: its frames fall
	# behind for good, so its reports seem to come that much later from then on.
	# The copy goes on with it all the same, and within a second and a half as
	# evenly as before, however unevenly they come, and no further behind than
	# that unevenness needs.
	_start_run(Vector2(176, 512), Vector2.RIGHT)
	for i in 60:
		_drive_a_frame(stride)
		await tree.physics_frame
	var stood_at := _player.global_position.x
	await _wait_frames(30)  # (nothing from it meanwhile)
	var from_x := _player.global_position.x
	check((from_x - stood_at) / stride < 6.0,
		"nothing from the client for half a second: the copy carries on %.1f frames' way, then waits" % ((from_x - stood_at) / stride))
	steps.clear()
	last_at = _player.global_position
	for pass_number in 8:
		for count: int in arrivals:
			for i in count:
				_drive_a_frame(stride)
			await tree.physics_frame
			steps.append(_player.global_position.distance_to(last_at))
			last_at = _player.global_position
		if pass_number == 1:
			var went := (_player.global_position.x - from_x) / stride
			check(went > 24.0, "the client's machine stood still half a second: the copy goes on with it at once (%.1f frames' way in 32)" % went)
	worst = steps.slice(steps.size() - 2 * arrivals.size()).map(func(step: float) -> float: return absf(step - stride)).max()
	check(worst < stride * 0.25 and _frames_behind() > 1.0 and _frames_behind() < 6.0,
		"and two seconds on, as evenly as before: %.2f px off at most, %.1f frames behind" % [worst, _frames_behind()])
	# The client's frames run a twentieth faster than this machine's (a display
	# that isn't quite the 60 Hz it says), then a twentieth slower: the copy
	# stays with it, evenly.
	_start_run(Vector2(176, 576), Vector2.RIGHT)
	for i in 40:
		_drive_a_frame(stride)
		await tree.physics_frame
	steps.clear()
	last_at = _player.global_position
	for i in 240:
		_drive_a_frame(stride)
		if i % 20 == 0:
			_drive_a_frame(stride)
		await tree.physics_frame
		if i >= 180:
			steps.append(_player.global_position.distance_to(last_at))
		last_at = _player.global_position
	behind = _player.global_position.distance_to(_at(_client_at)) / stride
	slowest = steps.min()
	fastest = steps.max()
	check(behind < 8.0 and slowest > stride * 0.95 and fastest < stride * 1.15,
		"the client's frames run a twentieth fast: the copy stays with it, %.1f frames' way behind, %.2f to %.2f px a frame" % [
			behind, slowest, fastest])
	_start_run(Vector2(176, 640), Vector2.RIGHT)
	for i in 40:
		_drive_a_frame(stride)
		await tree.physics_frame
	steps.clear()
	last_at = _player.global_position
	for i in 240:
		if i % 20 != 0:
			_drive_a_frame(stride)
		await tree.physics_frame
		if i >= 180:
			steps.append(_player.global_position.distance_to(last_at))
		last_at = _player.global_position
	behind = _player.global_position.distance_to(_at(_client_at)) / stride
	slowest = steps.min()
	fastest = steps.max()
	check(behind < 8.0 and slowest > stride * 0.85 and fastest < stride * 1.05,
		"a twentieth slow: the same, %.1f frames' way behind, %.2f to %.2f px a frame" % [behind, slowest, fastest])
	_start_run(home, Vector2.RIGHT)

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
	await _wait_frames(14)
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
	# A tap that came and went between two frames here (its press and release in
	# one bunch): its press counter says it, and the copy fires all the same.
	var shells_before := tree.get_nodes_in_group(NetWorld.GROUP).filter(
			func(node: Node) -> bool: return node is Bullet and node.owner_player == 0).size()
	_player.can_shoot = true
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [2, 0])
	await _wait_frames(2)
	var shells_after := tree.get_nodes_in_group(NetWorld.GROUP).filter(
			func(node: Node) -> bool: return node is Bullet and node.owner_player == 0).size()
	check(shells_after == shells_before + 1, "a tap between two frames fires too: %d shell(s) more" % (shells_after - shells_before))
	var args := shell.net_spawn_args() if shell else []
	check(args.size() == 9 and args[3] == 0 and is_equal_approx(float(args[4]), shell.speed),
		"the clients learn whose shell it is and how it flies: %s" % str(args))
	var state := _player.net_state()
	check(state.size() == PlayerTank.NET_OVERRIDE_AT + 1 and state[PlayerTank.NET_OVERRIDE_AT] == _player.net_override,
		"the copy's state carries the latest correction")
	_player.apply_mine_slow()
	check(_player.net_state()[3] & PlayerTank.NET_SLOWED != 0, "and a mine's slowing, so the client drives slow too")
	_player.clear_mine_slow()
	if shell:
		shell.queue_free()

	print("\n[E] A client with its lag compensation off: its keys drive the copy, as before")
	_place(home, Vector2.RIGHT)
	_client_has = false  # it tells the host it doesn't run its tank itself
	_client_predicts = false
	PlayerInput.set_remote(PEER, 0, PlayerInput.DIRECTIONS.find(Vector2.RIGHT), [false, false], [1, 0])
	override = _player.net_override
	await _wait_frames(10)
	var pushed := (_player.global_position - _at(home)).x
	check(absf(pushed - speed * 10.0 * get_physics_process_delta_time()) <= speed * get_physics_process_delta_time() + 0.01,
		"its keys drive it here as they come, at its speed: %.1f px in 10 frames" % pushed)
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [1, 0])
	await _wait_frames(2)
	var held_at := _player.global_position - _lm.global_position
	check(_player.net_override == override, "no corrections meanwhile")
	# It turns lag compensation on, and drives on from where it saw its tank.
	_report(held_at - Vector2(20, 0), Vector2.RIGHT, true, override)
	await _wait_frames(3)
	check(_player.net_override == (override + 1) % 256 and _player.global_position.distance_to(_at(held_at)) < 0.01,
		"it turns lag compensation on: its keys moved the copy, so a correction first, and the copy waits")
	_report(held_at + Vector2(30, 0), Vector2.RIGHT)
	await _wait_frames(int(PlayerTank.PLAY_DELAY_MAX) + 10)
	check(_player.global_position.distance_to(_at(held_at + Vector2(30, 0))) < 0.01, "taken: followed")

	print("\n[F] The client's side: its own tank, driven at once")
	_feeding = false
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
	check(bytes.size() == Net.INPUT_SIZE and bytes[where] == Net.REPORT_HAS | Net.REPORT_MOVING | Net.REPORT_PREDICTS
		and bytes[where + 1] == 3 and bytes[where + 2] == _player._override_seen % 256
		and Vector2(bytes.decode_float(where + 4), bytes.decode_float(where + 8)).distance_to(_player.global_position) < 0.01,
		"with its next input message: it runs its own tank, there, facing left, driving, the corrections taken")
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
	check(Net._input_message()[where] == Net.REPORT_PREDICTS, "a report gone stale (it stopped driving here) isn't sent")
	InputSettings.set_lag_compensation(false)
	check(Net._input_message()[where] == 0, "with lag compensation off, it says it doesn't run its own tank")
	InputSettings.set_lag_compensation(true)

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

	print("\n[G] Its own shells, drawn ahead by the trip")
	var bullets: Node = _game.get_node("Entities/Bullets")
	var world := NetClientWorld.new()
	world.setup(_game, _lm, null, {"bullets": bullets}, null)
	_game.add_child(world)
	check(NetClientWorld.of(tree) == world, "the game's client world")
	var own: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	own.net_setup([BaseTank.FACINGS.find(Vector2.RIGHT), "regular", [0.0], 0, 384.0, -1.0, false, 0.0, 0.0])
	_game.get_node("Entities/Bullets").add_child(own)
	own.set_physics_process(false)  # (after it's in: entering turns it on)
	NetClientWorld._strip_physics(own)
	Net.ping_ms = 150.0
	var lead := 384.0 * (150.0 + world.render_delay()) / 1000.0
	var shot_from := home + Vector2(0, -200)
	# Its snapshot is being shown now: render_delay behind the host's clock.
	world._clock_offset = 0.0
	world._own_shells[77] = {"start": _at(shot_from), "host_time": Time.get_ticks_msec() - world.render_delay(),
			"range": -1.0, "pierces": false}
	world._place(77, own, _at(shot_from))
	check(own.visible and own.global_position.distance_to(_at(shot_from + Vector2(lead, 0))) < 1.0,
		"drawn %.0f px ahead: 384 px/s for the 150 ms trip and the %d ms the world is shown behind" % [lead, world.render_delay()])
	InputSettings.set_lag_compensation(false)
	world._place(77, own, _at(shot_from))
	check(own.global_position == _at(shot_from), "with lag compensation off: where the host has it")
	InputSettings.set_lag_compensation(true)
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
	own.queue_free()
	world._own_shells.erase(77)

	print("\n[H] Its own shots, fired here at once")
	_player.set_net_predicted(true, 0)
	_place(home, Vector2.UP)
	_player.can_shoot = true
	SoundManager._predicted.clear()
	Input.action_press("p1_shoot")
	_fire_here()
	_fire_here()
	Input.action_release("p1_shoot")
	var ghost: Bullet = world._ghosts[0]["node"] if world._ghosts.size() == 1 else null
	var muzzle := _player.global_position + Vector2.UP * BaseTank.TANK_SIZE * 0.5
	check(ghost != null and ghost.net_ghost and ghost.get_parent() == bullets and ghost.direction == Vector2.UP
		and ghost.owner_player == 0 and ghost.collision_layer == 0 and ghost.collision_mask == 0
		and ghost.global_position.distance_to(muzzle) < 0.01,
		"fire: at once, a ghost of the host's shell to come, out of the barrel, touching nothing (and the cooldown holds the next)")
	if ghost == null:
		print("\n==== %d FAILURE(S) ====" % _fail)
		tree.quit(_fail)
		return
	ghost.set_physics_process(false)  # (offline it would fly as a real shell)
	check(SoundManager._predicted.size() == 1 and SoundManager._predicted[0][0] == 0
		and SoundManager._predicted[0][1] == &"fire_primary", "and heard at once")
	check(world.own_shells_in_flight(0) == 1 and world.own_shells_in_flight(0, "ap") == 0 and world.own_shells_in_flight(1) == 0,
		"one of its shells in flight, none of them AP")
	for i in 10:
		ghost._fly_ghost(1.0 / 60.0)
	check(absf((muzzle - ghost.global_position).y - ghost.speed * 10.0 / 60.0) < 0.01 and ghost.visible,
		"it flies as the host's shell will")
	var ghost_at := ghost.global_position
	var host_has := muzzle + Vector2.UP * 12.0
	world._shown_time = Time.get_ticks_msec() - world.render_delay()  # the snapshot bringing it, shown now
	world._spawn(90, NetWorld.T_BULLET, ghost.net_spawn_args(), [host_has.x, host_has.y])
	var real := world.node_for(90) as Bullet
	real.set_physics_process(false)
	check(world._ghosts.is_empty() and ghost.is_queued_for_deletion() and real.visible
		and real.global_position.distance_to(ghost_at) < 1.0,
		"the host's shell for it comes: it takes over, where the ghost was")
	world._own_shells[90]["offset_at"] -= int(NetClientWorld.HANDOFF_MS) + 1
	world._place(90, real, host_has)
	var its_own := host_has + Vector2.UP * real.speed * (150.0 + world.render_delay()) / 1000.0
	check(real.global_position.distance_to(its_own) < 1.0, "and eases to its own place, ahead of the host's")
	check(is_equal_approx(real.distance_in(0.5), real.speed * 0.5), "a shell flies on at its speed")
	var ap := Bullet.new()
	ap.speed = 222.0
	ap.accel = 889.0
	ap.max_speed = 667.0
	var to_top := (667.0 - 222.0) / 889.0
	check(is_equal_approx(ap.distance_in(to_top + 1.0), 222.0 * to_top + 0.5 * 889.0 * to_top * to_top + 667.0),
		"an AP shell speeds up to its top speed, then flies on at that")
	ap.free()
	var heard: int = SoundManager._last_played.get(&"fire_primary", 0)
	SoundManager.play_from_host(&"fire_primary", 0)
	check(SoundManager._predicted.is_empty() and SoundManager._last_played.get(&"fire_primary", 0) == heard,
		"the host's sound of that shot is left out: heard already")
	await tree.create_timer(0.05).timeout
	SoundManager.play_from_host(&"fire_primary", 0)
	check(SoundManager._last_played.get(&"fire_primary", 0) > heard, "a shot it didn't fire here itself is heard as it comes")
	real.queue_free()
	world._despawn(90)

	# One that hits a wall: hidden there, and the host's shell for it too.
	for x in [-16, 16]:
		_iron(home + Vector2(x, -160))
	_player.can_shoot = true
	Input.action_press("p1_shoot")
	_fire_here()
	Input.action_release("p1_shoot")
	ghost = world._ghosts[0]["node"]
	ghost.set_physics_process(false)
	for i in 40:
		ghost._fly_ghost(1.0 / 60.0)
	check(not ghost.visible and ghost.global_position.y > _at(home).y - 160.0, "a ghost at a wall hides there")
	world._spawn(91, NetWorld.T_BULLET, ghost.net_spawn_args(), [muzzle.x, muzzle.y])
	(world.node_for(91) as Bullet).set_physics_process(false)
	check(not world.node_for(91).visible, "and the host's shell for it stays hidden till its hit")
	world.node_for(91).queue_free()
	world._despawn(91)
	for x in [-16, 16]:
		_lm._remove_fg_tile(_lm.world_to_tile(_at(home + Vector2(x, -160))))

	# A ghost the host never takes over: a shot the host didn't fire.
	_player.can_shoot = true
	Input.action_press("p1_shoot")
	_fire_here()
	Input.action_release("p1_shoot")
	ghost = world._ghosts[0]["node"]
	ghost.set_physics_process(false)
	world._expire_ghosts()
	check(world._ghosts.size() == 1 and not ghost.is_queued_for_deletion(), "a ghost waits for the host's shell a while")
	world._ghosts[0]["born"] -= 100000
	world._expire_ghosts()
	check(world._ghosts.is_empty() and ghost.is_queued_for_deletion(), "then goes: a shot the host didn't fire")

	# Its secondary weapon as the host has it; mines left to the host.
	for i in 2:
		await tree.physics_frame  # (a press between two physics frames counts in the next one)
	var kind: String = GameManager.player_secondary_weapon_types[0]
	var count: int = GameManager.player_secondary_weapon_counts[0]
	GameManager.player_secondary_weapon_types[0] = "ap"
	GameManager.player_secondary_weapon_counts[0] = 9
	SoundManager._predicted.clear()
	Input.action_press("p1_shoot2")
	for i in 3:
		_player.can_shoot = true
		_fire_here()
	Input.action_release("p1_shoot2")
	var ap_ghosts := world._ghosts.filter(func(entry: Dictionary) -> bool: return entry["node"].visual_style == "ap")
	check(ap_ghosts.size() == 2 and world.own_shells_in_flight(0, "ap") == 2 and _player.secondary_weapon_count == 9,
		"the host's AP and its ammo: two shells in flight, as many as the host allows")
	check(SoundManager._predicted.size() == 3, "and its sound each time, as the host plays it")
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	Net.role = Net.Role.CLIENT
	GameManager.set_secondary_weapon(0, "rapid", 1)
	Net.role = Net.Role.OFFLINE
	check(GameManager.player_secondary_weapon_types[0] == "ap" and GameManager.player_secondary_weapon_counts[0] == 9,
		"a client's own shots spend none of the host's numbers")
	GameManager.player_secondary_weapon_types[0] = "mine"
	var mines := _lm.get_mines().size()
	Input.action_press("p1_shoot2")
	_player.can_shoot = true
	_fire_here()
	Input.action_release("p1_shoot2")
	await tree.process_frame  # (a mine goes in deferred)
	check(world._ghosts.is_empty() and SoundManager._predicted.size() == 3 and _lm.get_mines().size() == mines,
		"mines are left to the host: none laid here")
	GameManager.player_secondary_weapon_types[0] = kind
	GameManager.player_secondary_weapon_counts[0] = count
	SoundManager._predicted.clear()

	print("\n[I] How far behind the host the world is shown (SMOOTHING)")
	var spacing := 1000.0 * NetHostWorld.SEND_EVERY / Engine.physics_ticks_per_second
	var calm: Array[float] = []
	calm.resize(NetClientWorld.LATE_SAMPLES)
	calm.fill(0.0)
	var on_time := NetClientWorld.auto_delay(calm, spacing)
	check(is_equal_approx(on_time, spacing + NetClientWorld.AUTO_SPARE_MS),
		"AUTO, the snapshots on time: their spacing and a frame, %.0f ms" % on_time)
	var rough := calm.duplicate()
	for i in 7:
		rough[i] = 80.0
	check(is_equal_approx(NetClientWorld.auto_delay(rough, spacing), on_time + 80.0), "one in ten 80 ms late: 80 ms more")
	var stall := calm.duplicate()
	stall[0] = 500.0
	check(is_equal_approx(NetClientWorld.auto_delay(stall, spacing), on_time), "one stall alone changes nothing")
	var awful := calm.duplicate()
	awful.fill(900.0)
	check(NetClientWorld.auto_delay(awful, spacing) == NetClientWorld.AUTO_MAX_MS, "and never more than %d ms" % NetClientWorld.AUTO_MAX_MS)
	check(world._aimed_delay() == NetClientWorld.DELAY_MS, "not measured yet: %d ms" % NetClientWorld.DELAY_MS)
	world._late.assign(calm)
	check(is_equal_approx(world._aimed_delay(), on_time), "measured: AUTO's figure")
	InputSettings.set_smoothing(150)
	check(world._aimed_delay() == 150.0 and InputSettings.get_smoothing() == 150, "SMOOTHING 150 ms picked: 150 ms")
	InputSettings.set_smoothing(123)
	check(InputSettings.get_smoothing() == 0, "only its choices: else AUTO")
	world._nodes[5] = _player
	InputSettings.set_lag_compensation(false)
	world._take_own_tanks()
	check(not _player.net_predicted, "LAG COMPENSATION off: its own tank shows the host's")
	InputSettings.set_lag_compensation(true)
	world._take_own_tanks()
	check(_player.net_predicted, "on again: it drives here")
	world._nodes.erase(5)
	Net.ping_ms = 0.0
	world.queue_free()

	print("\n[J] The host's list of players: each one's ping")
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
