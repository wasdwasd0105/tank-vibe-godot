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
## The moment of the host's world its screen shows, as its reports say (0 none).
var _client_view := 0.0
## Its tank in the air there (a mine threw it), as its reports say.
var _client_flying := false
## The client's own shots as it counts them, per fire button, and the row of
## the latest of each (_client_fires).
var _client_shots := [0, 0]
var _client_rows := [1, 1]


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
			moving, override, _client_frame & 0xff, _client_view, _client_flying)


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


## The client fired a shot there itself with fire button [param button] from
## row [param row] (0 left, 1 middle, 2 right), its tank at [param local]
## facing [param facing]: its input message brings that report and its count
## up by one, as one message does.
func _client_fires(local: Vector2, facing: Vector2, button: int = 0, row: int = 1) -> void:
	_send_report(local, facing, true, _player.net_override)
	_client_shots[button] = (_client_shots[button] + 1) & 0xff
	_client_rows[button] = row
	PlayerInput.set_remote_shots(PEER, 0, _client_shots, _client_rows)


## The client's own shells here (owner player 0), oldest first.
func _client_shells() -> Array:
	return get_tree().get_nodes_in_group(NetWorld.GROUP).filter(
			func(node: Node) -> bool: return node is Bullet and node.owner_player == 0 and not node.is_queued_for_deletion())


## Its own shot fired here at once with [param action], flown on frame by
## frame till it ends: its ghost (null if none).
func _fly_shot(world: NetClientWorld, action: String = "p1_shoot") -> Bullet:
	_player.can_shoot = true
	Input.action_press(action)
	_fire_here()
	Input.action_release(action)
	var shot: Bullet = world._ghosts[-1]["node"] if not world._ghosts.is_empty() else null
	if shot:
		shot.set_physics_process(false)
		for i in 120:
			shot._fly_ghost(1.0 / 60.0)
			if not shot.visible:
				break
	return shot


## An enemy tank shown here as the host's entity [param nid], with
## [param hp] health, at [param local].
func _shown_enemy(world: NetClientWorld, nid: int, local: Vector2, hp: int) -> EnemyTank:
	var enemy := _spawn_enemy(local)
	enemy.health = hp
	enemy.current_direction = Vector2.UP
	world._nodes[nid] = enemy
	world._states[nid] = enemy.net_state()
	world._types[nid] = NetWorld.T_ENEMY
	return enemy


## A shell of the enemies' shown here as the host's entity [param nid], at
## [param local], going [param way].
func _shown_enemy_shell(world: NetClientWorld, nid: int, local: Vector2, way: Vector2) -> Bullet:
	var theirs: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	theirs.net_setup([BaseTank.FACINGS.find(way), "regular", [0.0], -1, 256.0, -1.0, false, 0.0, 0.0, -1, 1])
	_game.get_node("Entities/Bullets").add_child(theirs)
	theirs.set_physics_process(false)
	NetClientWorld._strip_physics(theirs)
	theirs.global_position = _at(local)
	world._nodes[nid] = theirs
	world._states[nid] = [theirs.global_position.x, theirs.global_position.y]
	world._types[nid] = NetWorld.T_BULLET
	return theirs


## An item shown here as the host's entity [param nid], at [param local].
func _shown_item(world: NetClientWorld, nid: int, local: Vector2) -> Cookie:
	var item: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	item.net_setup([CookieData.CookieType.SCORE_1000])
	_game.get_node("Entities/PowerUps").add_child(item)
	NetClientWorld._strip_physics(item)
	item.set_process(false)
	item.global_position = _at(local)
	world._nodes[nid] = item
	world._states[nid] = item.net_state()
	world._types[nid] = NetWorld.T_COOKIE
	return item


## The host's snapshot comes to [param world] with map cells [param cells]
## changed ([x, y, bg, fg, standing quarters] each), its time far off, and is
## shown (a guess its word catches up with goes once it is).
func _host_says_tiles(world: NetClientWorld, cells: PackedInt32Array) -> void:
	var packet := []
	packet.resize(NetWorld.SNAP_SIZE)
	packet[NetWorld.SNAP_SEQ] = 1
	packet[NetWorld.SNAP_EPOCH] = 1
	packet[NetWorld.SNAP_TIME] = Time.get_ticks_msec() + 100000
	packet[NetWorld.SNAP_FLAGS] = 0
	packet[NetWorld.SNAP_MAP] = []
	packet[NetWorld.SNAP_SPAWNS] = []
	packet[NetWorld.SNAP_UPDATES] = PackedByteArray()
	packet[NetWorld.SNAP_REMOVED] = PackedInt32Array()
	packet[NetWorld.SNAP_TILES] = cells
	packet[NetWorld.SNAP_GAME] = {}
	packet[NetWorld.SNAP_EVENTS] = []
	var was := [world._started, world._epoch, world._clock_offset, world._have_clock, world._late.duplicate(),
			world._shown_time]
	world._started = true
	world._epoch = 1
	world._on_packet(var_to_bytes(packet))
	if not world._buffer.is_empty():
		world._apply(world._buffer.pop_back())
	world._buffer.clear()
	world._started = was[0]
	world._epoch = was[1]
	world._clock_offset = was[2]
	world._have_clock = was[3]
	world._late = was[4]
	world._shown_time = was[5]


## What [param seen] (NetHostWorld.seen_at) keeps of [param node], or [].
func _seen_of(seen: Array, node: Object) -> Array:
	for each: Array in seen:
		if int(each[0]) == node.get_instance_id():
			return each[1]
	return []


## The host's snapshot comes to [param world], saying [param removed] have
## gone, with [param events], and entities [param moved] (nid -> [x, y]) are
## there; its time far off, so only what's shown at once shows. (The made-up
## time is no clock to go by: the world's is kept.)
func _host_says(world: NetClientWorld, removed: Array, events: Array, moved: Dictionary = {}) -> Dictionary:
	var packet := []
	packet.resize(NetWorld.SNAP_SIZE)
	packet[NetWorld.SNAP_SEQ] = 1
	packet[NetWorld.SNAP_EPOCH] = 1
	packet[NetWorld.SNAP_TIME] = Time.get_ticks_msec() + 100000
	packet[NetWorld.SNAP_FLAGS] = 0
	packet[NetWorld.SNAP_MAP] = []
	packet[NetWorld.SNAP_SPAWNS] = []
	var updates := StreamPeerBuffer.new()
	for nid: int in moved:
		world._templates[nid] = world._states[nid].duplicate()
		NetWorld.put_update(updates, nid, moved[nid], world._states[nid])
	packet[NetWorld.SNAP_UPDATES] = updates.data_array
	packet[NetWorld.SNAP_REMOVED] = PackedInt32Array(removed)
	packet[NetWorld.SNAP_TILES] = PackedInt32Array()
	packet[NetWorld.SNAP_GAME] = {}
	packet[NetWorld.SNAP_EVENTS] = events
	var was := [world._started, world._epoch, world._clock_offset, world._have_clock, world._late.duplicate()]
	world._started = true
	world._epoch = 1
	world._on_packet(var_to_bytes(packet))
	var kept: Dictionary = world._buffer[-1] if not world._buffer.is_empty() else {}
	world._buffer.clear()
	world._started = was[0]
	world._epoch = was[1]
	world._clock_offset = was[2]
	world._have_clock = was[3]
	world._late = was[4]
	return kept


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


## A shell of the enemies' here at [param local] going [param way], touching the
## players' tanks, their shells and the walls; flying on by itself if
## [param flies].
func _enemy_shell(local: Vector2, way: Vector2, flies: bool = false) -> Bullet:
	var shell: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	shell.direction = way
	shell.is_player_bullet = false
	shell.owner_player = -1
	shell.collision_lane_offsets = [0.0]
	shell.visual_lane_offsets = [0.0]
	shell.set_collision_layer_value(6, true)
	for layer: int in [1, 3, 5, 8]:
		shell.set_collision_mask_value(layer, true)
	_game.get_node("Entities/Bullets").add_child(shell)
	shell.set_physics_process(flies)
	shell.global_position = _at(local)
	return shell


## The client's report of its next frame, its tank at [param local] facing
## [param facing], its screen showing the moment [param view] of the host's
## world; then the host looks at it for what hits its tank.
func _judge_report(local: Vector2, facing: Vector2, view: float) -> void:
	_client_view = view
	_send_report(local, facing, false, _player.net_override)
	_player._judge_reported_hits()


## The host world [param world] keeps the shells and tanks as they are now, at
## [param time] (its clock, ms), as it does with each snapshot it sends.
func _keep_at(world: NetHostWorld, time: float) -> void:
	world._keep_seen(int(time))


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
	PlayerInput.set_remote_shots(PEER, 0, _client_shots, _client_rows)  # (its counts, first heard)
	_client_fires(landed, facing_now)  # fired there before it knew of the hold
	var held_shells := _client_shells().size()
	while GameManager.players_frozen:
		await tree.physics_frame
	await _wait_frames(2)
	check(_player.net_override == (override + 1) % 256, "and none when it ends")
	check(_client_shells().size() == held_shells, "a shot it fired there before it knew of the hold isn't fired here after it")

	print("\n[D] Its shots: the very ones it fired there itself, and what the clients get")
	_place(home, Vector2.RIGHT)
	_report(home, Vector2.RIGHT, false)
	await _wait_frames(2)
	_feeding = false  # (its reports come as the shots below say)
	PlayerInput.set_remote_shots(PEER, 0, _client_shots, _client_rows)  # its counts, first heard
	for shell: Node in _client_shells():
		shell.queue_free()
	await tree.physics_frame
	# Its fire button alone fires nothing here: the shots it fired itself do.
	PlayerInput.set_remote(PEER, 0, -1, [true, false], [1, 0])
	await _wait_frames(30)
	check(_client_shells().is_empty(), "its fire held for half a second: no shell here, as it fired none there")
	# It fires: its report of that frame comes with the count of it, its tank
	# there ahead of this copy (played back behind it), from the left row.
	var fired_at := home + Vector2(24, 0)
	_client_fires(fired_at, Vector2.RIGHT, 0, 0)
	await tree.physics_frame
	var shells := _client_shells()
	var shell: Bullet = shells[0] if shells.size() == 1 else null
	var barrel := _at(fired_at) + Vector2.RIGHT * BaseTank.TANK_SIZE * 0.5
	check(shell != null and shell.direction == Vector2.RIGHT and absf(shell.global_position.y - (barrel.y + BaseTank.FIRE_ROW_LEFT)) < 0.01
		and shell.global_position.x - barrel.x >= 0.0 and shell.global_position.x - barrel.x < shell.speed / 30.0
		and _player.global_position.distance_to(_at(fired_at)) > 10.0,
		"the shot it fired: one shell, out of its tank's barrel where it fired, from its row, not from this copy behind it")
	check(shell != null and shell.net_shot == _client_shots[0], "numbered as it numbered it: %d" % (shell.net_shot if shell else -1))
	await _wait_frames(30)
	check(_client_shells().size() == 1, "its fire still held: no more, however long")
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [1, 0])
	# Two shots come in one bunch (the network held the first back): both fire
	# at once, the cooldown being its own; each from its own report and row.
	var first_at := home + Vector2(28, 0)
	var then_at := home + Vector2(30, 0)
	_client_fires(first_at, Vector2.RIGHT, 0, 2)
	_client_fires(then_at, Vector2.RIGHT, 0, 1)
	await tree.physics_frame
	shells = _client_shells()
	var both := shells.slice(1)
	check(both.size() == 2 and absf(both[0].global_position.y - (_at(first_at).y + BaseTank.FIRE_ROW_RIGHT)) < 0.01
		and absf(both[1].global_position.y - _at(then_at).y) < 0.01 and both[1].net_shot == (both[0].net_shot + 1),
		"two shots in one bunch: both fire at once, each from its own row, in order")
	# Turned and fired at once: its new way, from its barrel that way.
	_client_fires(then_at, Vector2.UP)
	await tree.physics_frame
	shells = _client_shells()
	var up_barrel := _at(then_at) + Vector2.UP * BaseTank.TANK_SIZE * 0.5
	check(shells.size() == 4 and shells[3].direction == Vector2.UP and absf(shells[3].global_position.x - up_barrel.x) < 0.01
		and shells[3].global_position.y <= up_barrel.y and shells[3].global_position.y > up_barrel.y - shells[3].speed / 30.0,
		"turned and fired at once: the shell goes its new way, out of its barrel that way")
	var args := shell.net_spawn_args() if shell else []
	check(args.size() == 13 and args[3] == 0 and is_equal_approx(float(args[4]), shell.speed) and args[9] == shell.net_shot
		and args[10] == shell.damage and args[11] == Array(shell.collision_lane_offsets) and args[12] == [1, -1, -1],
		"the clients learn whose shell it is, how it flies, its number, its damage, the lanes it hits on, its side and that it drops no fire and sets off no blast: %s" % str(args))
	for each: Node in _client_shells():
		each.queue_free()
	# A shot of a kind with its shells in flight here at their limit waits; then
	# goes, once one has landed; one that can't go for too long is let go.
	var kind_was: String = _player.secondary_weapon_type
	var ammo_was := _player.secondary_weapon_count
	_player.secondary_weapon_type = "ap"
	_player.secondary_weapon_count = 9
	_player.active_ap_bullets = 2
	_client_fires(home, Vector2.RIGHT, 1)
	await _wait_frames(5)
	check(_client_shells().is_empty(), "an AP shot with two AP shells flying here already: it waits")
	_player.active_ap_bullets = 1
	await tree.physics_frame
	shells = _client_shells()
	check(shells.size() == 1 and shells[0].visual_style == "ap" and _player.secondary_weapon_count == 8,
		"one lands: it goes, spending the host's AP ammo")
	for each: Node in _client_shells():
		each.queue_free()
	_player.active_ap_bullets = 2
	_client_fires(home, Vector2.RIGHT, 1)
	await tree.create_timer((PlayerTank.CLIENT_SHOT_WAIT_MS + 100) / 1000.0).timeout
	_player.active_ap_bullets = 0
	await _wait_frames(3)
	check(_client_shells().is_empty() and PlayerInput.remote_pad(0).shots_due.is_empty(),
		"one that can't go for half a second is let go: its ghost there goes too")
	# A mine is laid there at once too: here, where it laid it there, numbered as
	# its shots are; its press alone lays none.
	_player.secondary_weapon_type = "mine"
	_player.can_shoot = true
	var mines_was := _lm.get_mines().size()
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [1, 1])
	await _wait_frames(2)
	await tree.process_frame  # (a mine goes in deferred)
	check(_lm.get_mines().size() == mines_was, "its press alone lays no mine here: its mine comes as one it laid")
	var copy_at := _player.global_position
	var laid_from := copy_at + Vector2(32, 0)
	_client_fires(laid_from - _lm.global_position, Vector2.RIGHT, 1)
	await _wait_frames(2)
	await tree.process_frame
	var laid_mines := _lm.get_mines()
	var origin := Vector2i(Mine.round_half_even((laid_from - _lm.global_position).x / 32.0 - 1.0),
			Mine.round_half_even((laid_from - _lm.global_position).y / 32.0 - 1.0))
	check(laid_mines.size() == mines_was + 1 and laid_mines[-1].cell == origin - Vector2i(2, 0)
		and laid_mines[-1].net_shot == 256 + _client_shots[1] and laid_mines[-1].net_spawn_args()[3] == laid_mines[-1].net_shot,
		"its mine shot: laid straight behind where it had the tank there (not its copy here, a tile behind), its number on it for the clients")
	for mine in _lm.get_mines():
		_lm.unregister_mine(mine)
		mine.queue_free()
	_player.secondary_weapon_type = kind_was
	_player.secondary_weapon_count = ammo_was
	_player.active_ap_bullets = 0
	_report(home, Vector2.RIGHT, false)  # (its reports every frame again)
	var state := _player.net_state()
	check(state.size() == PlayerTank.NET_OVERRIDE_AT + 1 and state[PlayerTank.NET_OVERRIDE_AT] == _player.net_override,
		"the copy's state carries the latest correction")
	_player.apply_mine_slow()
	check(_player.net_state()[3] & PlayerTank.NET_SLOWED != 0, "and a mine's slowing, so the client drives slow too")
	_player.clear_mine_slow()

	print("\n[D2] Its shots judged by what its screen showed (lag compensation: favor the shooter)")
	# Each shell has its own box, as Bullet.touches_tank and shells_touch work it
	# out (the scene's one shape resource would be every shell's).
	var tall: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	tall.direction = Vector2.UP
	tall.collision_lane_offsets = [-16.0, 16.0]
	var flat: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	flat.direction = Vector2.RIGHT
	flat.collision_lane_offsets = [0.0]
	for each: Bullet in [tall, flat]:
		_game.get_node("Entities/Bullets").add_child(each)
		each.set_physics_process(false)
	var tall_box: Vector2 = (tall.get_node("CollisionShape2D").shape as RectangleShape2D).size
	var flat_box: Vector2 = (flat.get_node("CollisionShape2D").shape as RectangleShape2D).size
	check(tall_box == Bullet.box_half(Vector2.UP, tall.collision_lane_offsets) * 2.0 and tall_box == Vector2(42, 10)
		and flat_box == Vector2(10, 10), "each shell's box is its own: %s for a two-lane one going up, %s for a one-lane one" % [tall_box, flat_box])
	tall.queue_free()
	flat.queue_free()
	var copied: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	copied.net_setup([0, "regular", [0.0], 1, 256.0, -1.0, false, 0.0, 0.0, 5, 1, [-16.0, 16.0]])
	check(Array(copied.collision_lane_offsets) == [-16.0, 16.0] and Array(copied.visual_lane_offsets) == [0.0]
		and copied.tile_lane_offsets == BaseTank.BODY_LANE_OFFSETS,
		"a client's copy of a shot drawn as one shell meets things on its two lanes, as the host's shell does")
	copied.free()
	Net.client_view_time = 123456.0
	var message := Net._input_message()
	check(message.size() == Net.INPUT_SIZE and message.decode_u32(Net.VIEW_AT) == 123456,
		"a client's input message says the moment of the host's world its screen shows")
	Net.client_view_time = 0.0
	var pad := PlayerInput.remote_pad(0)
	var seat: int = PlayerInput.seats[0]
	_client_view = 5000.0
	_send_report(home, Vector2.UP, false, _player.net_override)
	var said := PlayerInput.remote_report_frame(0)
	check(is_equal_approx(PlayerInput.view_time(seat, pad.report_run, said), 5000.0)
		and is_equal_approx(PlayerInput.view_time(seat, pad.report_run, said + 3), 5000.0 + 3000.0 / Engine.physics_ticks_per_second)
		and PlayerInput.view_time(seat, pad.report_run + 1, said) < 0.0,
		"the host keeps the moment each of its frames showed: as said, a frame on for each frame past the nearest; none from another run")
	# What the host sent it, kept: a tank as it was then, and as it is now.
	var host_world := NetHostWorld.new()
	host_world.setup(_game, _lm, null)
	_game.add_child(host_world)
	var seen_there := _at(home + Vector2(0, -220))
	var drove_off := _spawn_enemy(home + Vector2(0, -220))
	await _wait_frames(2)
	host_world._keep_seen(10000)
	drove_off.global_position = seen_there + Vector2(200, 0)  # it drove off since, here
	host_world._keep_seen(10034)
	var seen := _seen_of(host_world.seen_at(10017.0, PEER), drove_off)
	check(not seen.is_empty() and (seen[1] as Vector2).distance_to(seen_there + Vector2(100, 0)) < 0.01 and bool(seen[3]) and bool(seen[6]),
		"what its screen showed between two snapshots: the tank midway, as that client glides it")
	check((_seen_of(host_world.seen_at(9000.0, PEER), drove_off)[1] as Vector2).distance_to(seen_there) < 0.01
		and (_seen_of(host_world.seen_at(0.0, PEER), drove_off)[1] as Vector2).distance_to(seen_there + Vector2(200, 0)) < 0.01,
		"before the oldest kept: as the oldest had it; no moment said: as the newest has it")
	# Its screen shows that tank where it was; it fires straight up at it. Here
	# the tank has driven off, and another (not on its screen) is in the way.
	var unseen := _spawn_enemy(home + Vector2(0, -120))
	var unseen_hp := unseen.health
	await _wait_frames(2)
	_client_view = 10000.0
	_place(home, Vector2.UP)
	_report(home, Vector2.UP, false)
	await _wait_frames(2)
	for old: Node in _client_shells():
		old.queue_free()
	_client_fires(home, Vector2.UP)
	await tree.physics_frame
	var judged: Bullet = _client_shells()[0] if _client_shells().size() == 1 else null
	check(judged != null and judged.net_view.size() == 3 and int(judged.net_view[0]) == seat,
		"the host's shell for a client's own shot knows whose screen it's judged by")
	var ended := [Vector2.INF]
	var judged_step := judged.speed / Engine.physics_ticks_per_second if judged else 0.0
	if judged:
		judged.tree_exiting.connect(func() -> void: ended[0] = judged.global_position)
	await _wait_frames(70)
	check(not is_instance_valid(drove_off) or drove_off.is_queued_for_deletion(),
		"it hits the tank where that client's screen had it: the tank is killed, %.0f px off its way here" % 200.0)
	check(absf(ended[0].y - (seen_there.y + BaseTank.HITBOX_SIZE * 0.5 + Bullet.BULLET_LENGTH * 0.5)) <= judged_step,
		"its shell ends where it met that tank on that screen (%s)" % str(ended[0] - _lm.global_position))
	check(is_instance_valid(unseen) and unseen.health == unseen_hp,
		"and passes the one here that wasn't on that screen, untouched")
	# The tank it killed shows gone on its screen at once: its next shot that way
	# flies on where the tank was.
	var past_shot_at := [Vector2.INF]
	_client_fires(home, Vector2.UP)
	await tree.physics_frame
	var second: Bullet = _client_shells()[0] if _client_shells().size() == 1 else null
	if second:
		second.tree_exiting.connect(func() -> void: past_shot_at[0] = second.global_position)
	await _wait_frames(70)
	check(past_shot_at[0].y < ended[0].y - BaseTank.HITBOX_SIZE,
		"the next shot that way flies on where that tank was: gone for that client (%s)" % str(past_shot_at[0] - _lm.global_position))
	unseen.queue_free()
	# A shell of the enemies' on its way as that screen had it, gone off
	# elsewhere here since: the two meet there, as that screen showed.
	var enemy_shell: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	enemy_shell.direction = Vector2.DOWN
	enemy_shell.is_player_bullet = false
	enemy_shell.owner_player = -1
	enemy_shell.collision_lane_offsets = [0.0]
	enemy_shell.visual_lane_offsets = [0.0]
	enemy_shell.set_collision_layer_value(6, true)
	for layer: int in [1, 3, 5, 8]:
		enemy_shell.set_collision_mask_value(layer, true)
	_game.get_node("Entities/Bullets").add_child(enemy_shell)
	enemy_shell.set_physics_process(false)
	var meet_at := _at(home + Vector2(0, -200))
	enemy_shell.global_position = meet_at
	host_world._keep_seen(20000)
	enemy_shell.global_position = meet_at + Vector2(300, 0)
	host_world._keep_seen(20034)
	_client_view = 20000.0
	await _wait_frames(2)
	var clash_end := [Vector2.INF]
	var enemy_shell_id := enemy_shell.get_instance_id()
	enemy_shell.tree_exiting.connect(func() -> void: clash_end[0] = enemy_shell.global_position)
	_client_fires(home, Vector2.UP)
	await tree.physics_frame
	var third: Bullet = _client_shells()[0] if _client_shells().size() == 1 else null
	var third_end := [Vector2.INF]
	if third:
		third.tree_exiting.connect(func() -> void: third_end[0] = third.global_position)
	await _wait_frames(50)
	check(clash_end[0].distance_to(meet_at) < 0.01 and absf(third_end[0].y - meet_at.y) < Bullet.BULLET_LENGTH,
		"an enemies' shell on its way as that screen had it: the two meet there, both gone, theirs where that screen had it")
	check(host_world._gone_for.get(PEER, {}).has(enemy_shell_id), "and gone for that client")
	_client_view = 0.0
	_report(home, Vector2.RIGHT, false)  # (its reports every frame, as [D] left them)
	for old: Node in _client_shells():
		old.queue_free()
	host_world.queue_free()
	await tree.physics_frame

	print("\n[D3] What hits its tank: what its screen showed hitting it")
	var judge_world := NetHostWorld.new()
	judge_world.setup(_game, _lm, null)
	_game.add_child(judge_world)
	_feeding = false
	_player.set_physics_process(false)  # (the copy stays put: the judging alone)
	var hp_was := _player.health
	var memory_was := _player.has_memory_save
	_player.has_memory_save = true  # (a hit costs it no level: the tests after drive at its speed)
	_place(home, Vector2.UP)
	_judge_report(home, Vector2.UP, Time.get_ticks_msec() - 200.0)
	check(_player.hits_judged_there(), "its screen's moment said with each of its frames: its screen says what hits its tank")
	# One on its tank where its screen had it: a hit, wherever it is here; once.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_player.health = 4
	var t_a := Time.get_ticks_msec() - 150.0
	var struck := _enemy_shell(home + Vector2(0, -30), Vector2.DOWN)
	var struck_id := struck.get_instance_id()
	_keep_at(judge_world, t_a)
	struck.global_position = _at(home + Vector2(0, -24))
	_keep_at(judge_world, t_a + 34.0)
	struck.global_position = _at(home + Vector2(0, -330))  # gone on elsewhere here since
	_place(home + Vector2(40, 0), Vector2.UP)  # the copy, behind its tank there
	var struck_end := [Vector2.INF]
	struck.tree_exiting.connect(func() -> void: struck_end[0] = struck.global_position)
	_judge_report(home, Vector2.UP, t_a)
	var grace_flag := int(_player.net_state()[3]) & PlayerTank.NET_HIT_GRACE != 0
	_player.is_invincible = false  # (its grace aside: it's the shell that's judged)
	_judge_report(home, Vector2.UP, t_a + 17.0)
	await tree.process_frame
	check(_player.health == 3,
		"an enemies' shell on its tank where its screen had it: a hit, the copy here 40 px off, once (%d HP left)" % _player.health)
	check(struck_end[0].distance_to(_at(home + Vector2(0, -30))) < 0.01,
		"the shell ends where its screen had them meet (%s)" % str(struck_end[0] - _lm.global_position))
	check(is_equal_approx(float(judge_world._gone_for.get(PEER, {}).get(struck_id, -1.0)), t_a),
		"and it's gone for that client from that moment on")
	check(grace_flag, "its state says it's invincible only for that hit's grace (its client counts that in its own frames)")
	# One on the copy here, its tank clear of it there: no hit.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_place(home, Vector2.UP)
	var dodged := _enemy_shell(home + Vector2(0, -20), Vector2.DOWN)
	await _wait_frames(3)
	check(is_instance_valid(dodged) and not dodged._destroyed and _player.health == 3,
		"an enemies' shell on the copy here touches nothing: the copy is behind its tank")
	judge_world._seen.clear()
	var t_b := float(Time.get_ticks_msec())
	_keep_at(judge_world, t_b)
	_judge_report(home + Vector2(50, 0), Vector2.RIGHT, t_b)
	check(is_instance_valid(dodged) and not dodged._destroyed and _player.health == 3,
		"its tank had driven clear of it there: it misses")
	dodged.queue_free()
	# Its moon shield, by the way its screen had it facing.
	_player.apply_addon("moon-shield")
	var facing_tests := [[Vector2.LEFT, Vector2.UP, 3, "its moon shield's front to the shell as its screen had it facing (the copy here faces left): the shell ends, no damage"],
		[Vector2.UP, Vector2.LEFT, 2, "its side to it there, though the copy here faces it: a hit"]]
	for each: Array in facing_tests:
		_player.is_invincible = false
		_player._screen_grace_run = -1
		judge_world._seen.clear()
		var t_s := Time.get_ticks_msec() - 100.0
		var at_shield := _enemy_shell(home + Vector2(0, -30), Vector2.DOWN)
		_keep_at(judge_world, t_s)
		at_shield.global_position = _at(home + Vector2(0, -330))
		_keep_at(judge_world, t_s + 34.0)
		_place(home, each[0])
		_judge_report(home, each[1], t_s)
		await tree.process_frame
		check(_player.health == each[2] and not is_instance_valid(at_shield), each[3])
	_player._remove_moon_shield()
	# One gone here already (it ended elsewhere) still hits it, as its screen had
	# it; and its hit's sound goes out as its tank's, for that client to leave out.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_player.health = 4
	judge_world._seen.clear()
	var listener := NetHostWorld.ClientView.new()
	judge_world._views[PEER] = listener
	var t_g := Time.get_ticks_msec() - 100.0
	var vanished := _enemy_shell(home + Vector2(0, -30), Vector2.DOWN)
	_keep_at(judge_world, t_g)
	_keep_at(judge_world, t_g + 34.0)
	vanished.free()
	_judge_report(home, Vector2.UP, t_g + 10.0)
	check(_player.health == 3, "one gone here already still hits it, as its screen showed")
	check(listener.events.has([NetWorld.EV_SOUND, "tank_hit", 0]), "its hit's sound goes out as its tank's")
	judge_world._views.erase(PEER)
	# The grace after a hit goes by its screen's frames: a shell its screen shows
	# on its tank within HIT_GRACE of a hit there is in that grace, though the
	# grace here has run out (its reports came unevenly); one after it lands,
	# though the grace here runs on.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_player.health = 4
	judge_world._seen.clear()
	var t_r := Time.get_ticks_msec() - 300.0
	var graced_shells: Array[Bullet] = []
	for i in 3:
		graced_shells.append(_enemy_shell(home + Vector2(0, -330), Vector2.DOWN))
	for i in 3:
		for each_shell: Bullet in graced_shells:
			each_shell.global_position = _at(home + Vector2(0, -330))
		graced_shells[i].global_position = _at(home + Vector2(0, -30))
		_keep_at(judge_world, t_r + 34.0 * i)
	_judge_report(home, Vector2.UP, t_r)
	var hp_first := _player.health
	_player.is_invincible = false  # (the grace here over already)
	_client_frame += 9
	_judge_report(home, Vector2.UP, t_r + 34.0)
	var hp_graced := _player.health
	_player.is_invincible = true  # (the grace here still running)
	_player.invincible_timer = PlayerTank.HIT_GRACE
	_player._hit_grace_only = true
	_client_frame += 30
	_judge_report(home, Vector2.UP, t_r + 68.0)
	check(hp_first == 3 and hp_graced == 3 and _player.health == 2,
		"a hit, then another 10 of its frames later in that grace (none), then one 40 frames on (a hit): %d, %d, %d" % [hp_first, hp_graced, _player.health])
	for each_shell: Bullet in graced_shells:
		if is_instance_valid(each_shell):
			each_shell.queue_free()
	# One its own shot met on its screen a moment later still hit its tank the
	# moment before, as that screen showed.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_player.health = 4
	judge_world._seen.clear()
	var t_m := Time.get_ticks_msec() - 100.0
	var met_later := _enemy_shell(home + Vector2(0, -30), Vector2.DOWN)
	_keep_at(judge_world, t_m)
	met_later.global_position = _at(home + Vector2(0, -330))
	_keep_at(judge_world, t_m + 34.0)
	judge_world.mark_gone(PEER, met_later.get_instance_id(), t_m + 30.0)
	_judge_report(home, Vector2.UP, t_m)
	check(_player.health == 3, "one its own shot met there a moment later still hit it the moment before")
	# A report from somewhere this copy couldn't be following: nothing hits it
	# there. Its screen further behind than the host keeps: the copy here is
	# what's hit.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	judge_world._seen.clear()
	var t_far := Time.get_ticks_msec() - 100.0
	var out_there := _enemy_shell(home + Vector2(200, -30), Vector2.DOWN)
	_keep_at(judge_world, t_far)
	_keep_at(judge_world, t_far + 34.0)
	_judge_report(home + Vector2(200, 0), Vector2.UP, t_far)
	check(_player.health == 3 and is_instance_valid(out_there) and not out_there._destroyed,
		"a report from somewhere this copy couldn't be following: nothing hits it there")
	out_there.queue_free()
	_judge_report(home, Vector2.UP, Time.get_ticks_msec() - NetHostWorld.SEEN_KEEP_MS)
	check(not _player.hits_judged_there(), "its screen further behind than the host keeps: the copy here is what's hit")
	_judge_report(home, Vector2.UP, Time.get_ticks_msec() - 100.0)
	# One going on through the copy here to a brick behind, before its screen
	# has shown that moment: the brick waits for that screen.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_player.health = 4
	judge_world._seen.clear()
	_place(home, Vector2.UP)
	var wall_behind := _lm.world_to_tile(_at(home + Vector2(0, 64)))
	var far_cell := _lm.world_to_tile(_at(home + Vector2(320, 64)))
	var in_front := _lm.world_to_tile(_at(home + Vector2(0, -64)))
	var lag := 600.0
	var effects_box := tree.get_first_node_in_group("effects_container")
	var from_above := home + Vector2(0, -100)
	var flights := [
		[home + Vector2(50, 0), wall_behind, 0b0011, 3, "its tank clear of it there: the brick waits for its screen, then breaks", from_above],
		[home, wall_behind, 0b1111, 3, "its screen showed it hitting its tank first: a hit, and the brick never breaks", from_above],
		[home, far_cell, 0b0011, 0, "one nowhere near its tank: its brick breaks at once", home + Vector2(320, -100)],
		[home, in_front, 0b0011, 0, "one at the brick in front of its tank, the tank behind it: the brick breaks at once", home + Vector2(0, -200)],
		[home + Vector2(64, 0), in_front, 0b0011, 3, "one at a brick beside its tank's column (it could come round in front): the brick waits, then breaks",
			home + Vector2(0, -200), home + Vector2(64, 0)],
		[home + Vector2(50, 0), wall_behind, 0b0011, 1, "its client quiet too long: the brick breaks all the same", from_above]]
	for each: Array in flights:
		var cell: Vector2i = each[1]
		_lm._remove_fg_tile(cell)
		_lm._brick_damage.erase(cell)
		_lm._place_fg_tile(cell, 0x19)
		_player.is_invincible = false
		_player._screen_grace_run = -1
		var hp_before := _player.health
		_place(each[6] if each.size() > 6 else home, Vector2.UP)
		var flier := _enemy_shell(each[5], Vector2.DOWN, true)
		var shooter := _spawn_enemy(home + Vector2(-320, -320))
		shooter.active_bullets = 1
		flier.owner_tank = shooter
		var flier_end := [Vector2.INF]
		flier.tree_exiting.connect(func() -> void: flier_end[0] = flier.global_position)
		var pictures := [0]
		var count_pictures := func(_node: Node) -> void: pictures[0] += 1
		effects_box.child_entered_tree.connect(count_pictures)
		var waited := -1
		var frames_waited := 0
		var shot_back := false
		var pictured := 0
		for i in 150:
			await tree.physics_frame
			var clock := float(Time.get_ticks_msec())
			_keep_at(judge_world, clock)
			_judge_report(each[0], Vector2.UP, clock - lag)
			if not is_instance_valid(flier):
				break
			if flier._parked_end.is_valid():
				frames_waited += 1
				if waited < 0:
					waited = int(_lm._brick_damage.get(cell, -1))
					shot_back = shooter.active_bullets == 0
					pictured = pictures[0]
					if int(each[3]) == 1:
						flier._parked_since -= Bullet.PARK_MAX_MS + 1  # as if no word came for that long
		effects_box.child_entered_tree.disconnect(count_pictures)
		shooter.queue_free()
		var brick := int(_lm._brick_damage.get(cell, -1))
		var hit := _player.health < hp_before
		match int(each[3]):
			3:
				check(waited == 0b1111 and brick == each[2] and hit == (each[0] == home), each[4])
				if each[0] != home:
					check(shot_back and pictured == 1 and pictures[0] == 1,
						"gone from sight at once, its end's picture shown then (once), its tank's shot back")
					check(frames_waited <= int((lag + 150.0) / 1000.0 * Engine.physics_ticks_per_second),
						"its end came as soon as its screen had shown that moment (%d frames on)" % frames_waited)
			0:
				check(waited < 0 and brick == each[2] and not hit, each[4])
			1:
				check(waited == 0b1111 and frames_waited <= 2 and brick == each[2], each[4] + " (%d frames on)" % frames_waited)
		if each[0] == home and cell == wall_behind:
			check(absf(flier_end[0].y - (_at(home).y - 35.0)) < 6.0,
				"and it ends where its screen had them meet (%s)" % str(flier_end[0] - _lm.global_position))
		_lm._remove_fg_tile(cell)  # (what's left of it isn't in the next one's way)
		_lm._brick_damage.erase(cell)
	# No reports of its tank there (it doesn't drive one just now): the copy here
	# is what's hit, as before.
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_player.health = 4
	_client_has = false
	_send_report(home, Vector2.UP, false, 0)
	_client_has = true
	check(not _player.hits_judged_there(), "no reports of its tank there just now: the copy here is what's hit")
	var plain := _enemy_shell(home + Vector2(0, -20), Vector2.DOWN)
	await _wait_frames(3)
	check(_player.health == 3 and (not is_instance_valid(plain) or plain._destroyed), "a shell on the copy: a hit, as before")
	for cell: Vector2i in [wall_behind, far_cell, in_front]:
		_lm._remove_fg_tile(cell)
		_lm._brick_damage.erase(cell)
	# What finishes its tank, so that it goes up where its screen had it: as
	# much damage as it has health, not on its moon shield's front nor in a blink.
	var plain_kept := [NetHostWorld.SEEN_SHELL, Vector2.ZERO, Vector2.DOWN, [0.0], false, 1, false, "regular", false]
	var blast_kept := plain_kept.duplicate()
	blast_kept[5] = 2
	blast_kept[7] = "explosion"
	_player.is_invincible = false
	_player._screen_grace_run = -1
	_player.health = 1
	var finished := _player._finished_by(plain_kept, Vector2.UP)
	_player.health = 2
	var spared := not _player._finished_by(plain_kept, Vector2.UP)
	var by_blast := _player._finished_by(blast_kept, Vector2.UP)
	_player.health = 1
	_player.has_moon_shield = true
	var by_shield := not _player._finished_by(plain_kept, Vector2.UP) and _player._finished_by(plain_kept, Vector2.LEFT)
	_player.has_moon_shield = false
	_player.is_invincible = true
	var by_blink := not _player._finished_by(plain_kept, Vector2.UP)
	check(finished and spared and by_blast and by_shield and by_blink,
		"what finishes its tank: a point at 1 HP, not at 2, an explosion's direct hit of 2 at 2; not on its moon shield's front, nor in a blink")
	_player.health = hp_was
	_player.has_memory_save = memory_was
	_player.is_invincible = true
	_player.invincible_timer = 999.0
	_player.set_physics_process(true)
	judge_world.queue_free()
	_client_view = 0.0
	_report(home, Vector2.RIGHT, false)
	await tree.physics_frame

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
	# Its fire too, as its keys come: a tap between two frames here (its press
	# and release in one bunch) fires all the same, by its press counter.
	for each: Node in _client_shells():
		each.queue_free()
	_player.can_shoot = true
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [2, 0])
	await _wait_frames(2)
	check(_client_shells().size() == 1, "its fire as its keys come: a tap between two frames fires here")
	for each: Node in _client_shells():
		each.queue_free()
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
	check(Net.process_physics_priority > _player.process_physics_priority,
		"its input goes out after its tank's step: a shot comes with where it was fired from")
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
	var fx := Node2D.new()
	_game.add_child(fx)
	world.setup(_game, _lm, null, {"bullets": bullets, "terrain": _lm.terrain_node}, fx)
	_game.add_child(world)
	check(NetClientWorld.of(tree) == world, "the game's client world")
	world._shown_time = 5000.0
	world._buffer = [{"time": 5033.0}]
	check(is_equal_approx(world._view_time(5016.0), 5016.0) and is_equal_approx(world._view_time(5100.0), 5033.0)
		and is_equal_approx(world._view_time(4990.0), 5000.0),
		"the moment of the host's world shown (the host judges its shots by it): on from the snapshot shown towards the next")
	world._buffer.clear()
	check(is_equal_approx(world._view_time(5016.0), 5000.0), "no next one come yet: the one shown")
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
	for y in [-16, 16]:
		_lm._remove_fg_tile(_lm.world_to_tile(_at(shot_from + Vector2(64, y))))
	world._place(77, own, _at(shot_from))
	check(not own.visible, "it stays ended at that wall though it's gone here since (its own shot may have broken it)")
	world._place(77, own, _at(shot_from + Vector2(80, 0)))
	check(own.visible, "the host's shell seen on past it: on it flies")
	for y in [-16, 16]:
		_iron(shot_from + Vector2(64, y))
	world._own_shells[79] = {"start": _at(shot_from), "host_time": Time.get_ticks_msec() - world.render_delay(),
			"range": -1.0, "pierces": true}
	world._place(79, own, _at(shot_from))
	check(own.visible, "an AP shell drills on through")
	world._own_shells.erase(79)
	for y in [-16, 16]:
		_lm._remove_fg_tile(_lm.world_to_tile(_at(shot_from + Vector2(64, y))))
	world._guessed_walls.clear()
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
	var told := Net._input_message()
	check(ghost.net_shot == int(Net._shots[0][0]) and told[Net.SHOTS_AT] == Net._shots[0][0]
		and told[Net.SHOTS_AT + 2] & 3 == 1,
		"numbered, and the host told with its next input message: shot %d, from the middle row" % ghost.net_shot)
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
		"the host's shell for it comes, with its number: it takes over, where the ghost was")
	world._own_shells[90]["offset_at"] -= int(NetClientWorld.HANDOFF_MS) + 1
	world._own_shells[90]["born"] -= 500
	world._place(90, real, host_has)
	var on_its_way := muzzle + Vector2.UP * real.speed * 0.5 * Engine.time_scale
	check(real.global_position.distance_to(on_its_way) < 1.0,
		"on the ghost's own line, it flies on as the ghost did, by this machine's clock: no jump at all")
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
	# One the host fired from its copy of the tank, off the ghost's line: it
	# eases from the ghost to its own place, ahead of the host's.
	_player.can_shoot = true
	Input.action_press("p1_shoot")
	_fire_here()
	Input.action_release("p1_shoot")
	ghost = world._ghosts[0]["node"]
	ghost.set_physics_process(false)
	ghost_at = ghost.global_position
	host_has = muzzle + Vector2(16, -12)
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(90, NetWorld.T_BULLET, ghost.net_spawn_args(), [host_has.x, host_has.y])
	real = world.node_for(90) as Bullet
	real.set_physics_process(false)
	check(world._ghosts.is_empty() and real.global_position.distance_to(ghost_at) < 1.0
		and not world._own_shells[90].has("born"), "off its line: it takes over where the ghost was")
	world._own_shells[90]["offset_at"] -= int(NetClientWorld.HANDOFF_MS) + 1
	world._place(90, real, host_has)
	var its_own := host_has + Vector2.UP * real.speed * (150.0 + world.render_delay()) / 1000.0
	check(real.global_position.distance_to(its_own) < 1.0, "and eases to its own place, ahead of the host's")
	real.queue_free()
	world._despawn(90)
	# Two in flight the same way, the host's shell for the second here first (the
	# first's held up on its way): the ghost with its number gives way, not the older.
	for i in 2:
		_player.can_shoot = true
		Input.action_press("p1_shoot")
		_fire_here()
		Input.action_release("p1_shoot")
	var older: Bullet = world._ghosts[0]["node"] if world._ghosts.size() == 2 else null
	var newer: Bullet = world._ghosts[1]["node"] if world._ghosts.size() == 2 else null
	if older and newer:
		older.set_physics_process(false)
		newer.set_physics_process(false)
		world._spawn(92, NetWorld.T_BULLET, newer.net_spawn_args(), [newer.global_position.x, newer.global_position.y])
		(world.node_for(92) as Bullet).set_physics_process(false)
	check(older != null and world._ghosts.size() == 1 and world._ghosts[0]["node"] == older and newer.is_queued_for_deletion(),
		"two in flight, the second's shell here first: the ghost with its number gives way, not the older")
	world._despawn(92)
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	SoundManager._predicted.clear()

	# One that hits a wall: hidden there, and the host's shell for it too.
	for x in [-16, 16]:
		_iron(home + Vector2(x, -160))
	_player.can_shoot = true
	Input.action_press("p1_shoot")
	_fire_here()
	Input.action_release("p1_shoot")
	ghost = world._ghosts[0]["node"]
	ghost.set_physics_process(false)
	world._predicted_hits.clear()
	var effects_shown := fx.get_child_count()
	for i in 40:
		ghost._fly_ghost(1.0 / 60.0)
	check(not ghost.visible and ghost.global_position.y > _at(home).y - 160.0, "a ghost at a wall hides there")
	var end_at := ghost.global_position
	check(fx.get_child_count() > effects_shown and world._predicted_hits.size() == 1,
		"and its end shows there at once, as the host will show it, not a trip later")
	effects_shown = fx.get_child_count()
	var themed := not ThemeManager.get_hit_frames("regular").is_empty()
	for at: Vector2 in [end_at + Vector2(0, -6), end_at + Vector2(300, 0)]:
		world._play([NetWorld.EV_HIT, "regular", at.x, at.y] if themed else [NetWorld.EV_EXPLOSION, at.x, at.y, 1.0])
	check(fx.get_child_count() == effects_shown + 1,
		"the host's picture of that end, when it comes, isn't shown again; one elsewhere is")
	world._spawn(91, NetWorld.T_BULLET, ghost.net_spawn_args(), [muzzle.x, muzzle.y])
	(world.node_for(91) as Bullet).set_physics_process(false)
	check(not world.node_for(91).visible and world._predicted_hits.size() == 1,
		"and the host's shell for it stays hidden till its hit, its end shown once")
	world.node_for(91).queue_free()
	world._despawn(91)
	# One drawn ahead of the host's (no ghost of it here) that reaches the wall
	# here first: its end shows at once where it stops, and only once.
	var short_of := muzzle + Vector2.UP * 60.0
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(93, NetWorld.T_BULLET, [BaseTank.FACINGS.find(Vector2.UP), "regular", [0.0], 0, 384.0, -1.0, false, 0.0, 0.0, -1],
			[short_of.x, short_of.y])
	var ahead_shell := world.node_for(93) as Bullet
	ahead_shell.set_physics_process(false)
	world._place(93, ahead_shell, short_of)
	world._place(93, ahead_shell, short_of)
	var wall_cell := _lm.world_to_tile(_at(home + Vector2(16, -160)))
	var wall_face := _lm.tile_to_world(wall_cell).y + LevelManager.TILE_SIZE * 0.5
	check(not ahead_shell.visible and world._predicted_hits.size() == 2
		and absf((world._predicted_hits[1][1] as Vector2).y - wall_face) <= 8.0,
		"one drawn ahead reaching a wall here first: hidden there, its end shown at once at the wall, once (%.0f, the wall's face at %.0f)" % [
			(world._predicted_hits[1][1] as Vector2).y if world._predicted_hits.size() == 2 else INF, wall_face])
	world._despawn(93)
	world._predicted_hits.clear()
	for x in [-16, 16]:
		_lm._remove_fg_tile(_lm.world_to_tile(_at(home + Vector2(x, -160))))

	# A brick wall its own shell reaches: broken here at once, as the host's
	# shell will break it; the host's word of those cells settles it.
	var brick_cells: Array[Vector2i] = []
	for x in [-16, 16]:
		var cell := _lm.world_to_tile(_at(home + Vector2(x, -160)))
		_lm._place_fg_tile(cell, 0x19)
		brick_cells.append(cell)
	var broke := _fly_shot(world)
	var standing_now := brick_cells.map(func(cell: Vector2i) -> int: return int(_lm._brick_damage.get(cell, -1)))
	check(broke != null and not broke.visible and standing_now == [0b1100, 0b1100] and world._guessed_walls.size() == 1,
		"a brick wall its shot reaches: its near half broken here at once, as on the host: %s" % str(standing_now))
	var said_cells := PackedInt32Array()
	for cell: Vector2i in brick_cells:
		said_cells.append_array([cell.x, cell.y, 0, 0x19, 0b1100])
	_host_says_tiles(world, said_cells)
	check(world._guessed_walls.is_empty() and brick_cells.all(func(cell: Vector2i) -> bool: return _lm._brick_damage.get(cell, -1) == 0b1100),
		"the host's word of those cells: settled")
	# The host's word that its shell went without them: put back as they were.
	broke = _fly_shot(world)
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(120, NetWorld.T_BULLET, broke.net_spawn_args(), [muzzle.x, muzzle.y])
	(world.node_for(120) as Bullet).set_physics_process(false)
	var broken_here := brick_cells.all(func(cell: Vector2i) -> bool: return not _lm._fg_tile_data.has(cell))
	var undone := world.guesses_undone
	_host_says(world, [120], [])
	check(broken_here and brick_cells.all(func(cell: Vector2i) -> bool: return _lm._brick_damage.get(cell, -1) == 0b1100)
		and world._guessed_walls.is_empty() and world.guesses_undone == undone + 1,
		"its shell gone on the host without them: the bricks it broke here put back as they were")
	world._despawn(120)
	# One drawn ahead (its ghost gone) reaching bricks: broken at once, and it
	# stays ended there.
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(121, NetWorld.T_BULLET, [BaseTank.FACINGS.find(Vector2.UP), "regular", [0.0], 0, 384.0, -1.0, false, 0.0, 0.0, 996, 1, [-16.0, 16.0]],
			[short_of.x, short_of.y])
	var through_bricks := world.node_for(121) as Bullet
	through_bricks.set_physics_process(false)
	world._place(121, through_bricks, short_of)
	world._place(121, through_bricks, short_of)
	check(not through_bricks.visible and brick_cells.all(func(cell: Vector2i) -> bool: return not _lm._fg_tile_data.has(cell))
		and world._guessed_walls.size() == 1,
		"one drawn ahead reaching them: what was left of them broken here at once, it ended there")
	world._despawn(121)
	world._guessed_walls.clear()
	world._predicted_hits.clear()
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	for cell: Vector2i in brick_cells:
		_lm._remove_fg_tile(cell)
		_lm._brick_damage.erase(cell)
	# An item its own tank drives onto: taken here at once, its name shown and
	# its sound heard; the host's word of it leaves those out.
	var item := _shown_item(world, 122, _player.global_position - _lm.global_position + Vector2(40, 0))
	var names_before := fx.get_child_count()
	var pickup_heard := int(SoundManager._last_played.get(&"powerup_pickup", 0))
	await tree.create_timer(0.1).timeout  # (past the sound's repeat guard)
	world.predict_pickups(_player)
	check(not item.visible and world._guessed_pickups.has(item.get_instance_id()) and fx.get_child_count() == names_before + 1
		and int(SoundManager._last_played.get(&"powerup_pickup", 0)) > pickup_heard,
		"an item its tank drives onto: taken here at once, its name shown and its sound heard")
	var word := _host_says(world, [122], [[NetWorld.EV_SOUND, "powerup_pickup"],
			[NetWorld.EV_PICKUP_TEXT, item.cookie_type, item.global_position.x, item.global_position.y]])
	check(not world._nodes.has(122) and world._guessed_pickups.is_empty() and Array(word.get("removed", [0])).is_empty()
		and word.get("events", [0]).is_empty(),
		"the host's word of it: gone for good, its name and sound left out of that snapshot (shown and heard already)")
	var far_item := _shown_item(world, 123, _player.global_position - _lm.global_position + Vector2(40, 0))
	world.predict_pickups(_player)
	world._guessed_pickups[far_item.get_instance_id()]["msec"] -= int(NetClientWorld.GUESS_MAX_MS) + 1
	undone = world.guesses_undone
	_host_says(world, [], [])
	check(far_item.visible and world._guessed_pickups.is_empty() and world.guesses_undone == undone + 1,
		"no word of it for %.1f s: it shows again" % (NetClientWorld.GUESS_MAX_MS / 1000.0))
	world._despawn(123)
	var flying_item := _shown_item(world, 124, _player.global_position - _lm.global_position + Vector2(40, 0))
	flying_item.scale = Vector2.ONE * 0.5  # (still flying out of a tank)
	world.predict_pickups(_player)
	check(flying_item.visible and world._guessed_pickups.is_empty(), "one still flying out of a tank: left to the host")
	world._despawn(124)
	var under := _shown_item(world, 125, _player.global_position - _lm.global_position + Vector2(20, 0))
	Net.role = Net.Role.CLIENT
	_player._predict()
	Net.role = Net.Role.OFFLINE
	check(not under.visible and world._guessed_pickups.has(under.get_instance_id()),
		"its own tank's step here takes them (PlayerTank._predict)")
	world._guessed_pickups.clear()
	world._despawn(125)

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
	check(SoundManager._predicted.size() == 2,
		"and its sound for each that leaves, as the host plays it (none for the third, held back)")
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	# An AP shell drills on through a line of tanks while its pool lasts, as the
	# host's does: through one with 1 HP and one with 2, it stops in one with 9
	# (its pool of 8 spent), its end shown there at once.
	var line: Array[EnemyTank] = []
	for at: float in [80.0, 150.0, 220.0]:
		line.append(_spawn_enemy(home + Vector2.UP * (BaseTank.TANK_SIZE * 0.5 + at)))
	line[0].health = 1
	line[1].health = 2
	line[2].health = 9
	world._predicted_hits.clear()
	var heard_before := SoundManager._predicted.duplicate()
	_player.active_ap_bullets = 0
	_player.can_shoot = true
	Input.action_press("p1_shoot2")
	_fire_here()
	Input.action_release("p1_shoot2")
	var drill: Bullet = world._ghosts[0]["node"] if world._ghosts.size() == 1 else null
	var seen_past: Array[bool] = [false, false]
	if drill:
		drill.set_physics_process(false)
		for i in 120:
			drill._fly_ghost(1.0 / 60.0)
			if not drill.visible:
				break
			for t in 2:
				seen_past[t] = seen_past[t] or drill.global_position.y < line[t].global_position.y
	var near_edge := line[2].global_position.y + BaseTank.HITBOX_SIZE * 0.5 + Bullet.BULLET_LENGTH * 0.5  # (where their shapes meet)
	check(drill != null and drill.pierces and seen_past == [true, true] and not drill.visible
		and drill.global_position.y <= near_edge and drill.global_position.y > near_edge - 8.0,
		"an AP shell drills on through tanks of 1 and 2 HP, seen past them, and stops in one of 9 (its pool of 8): %s" % str(
			drill.global_position - _lm.global_position if drill else "none"))
	check(world._predicted_hits.size() == 1 and (world._predicted_hits[0][1] as Vector2).distance_to(drill.global_position) < 0.01,
		"its end shown there at once")
	check(line.all(func(enemy: EnemyTank) -> bool: return world._own_hits.has(enemy.get_instance_id())),
		"and each tank it drilled through or stopped in noted as one its shells reached")
	# The host's shell for it takes over its drilling as far as the ghost had got.
	world._spawn(94, NetWorld.T_BULLET, drill.net_spawn_args(), [muzzle.x, muzzle.y])
	var drilled := world.node_for(94) as Bullet
	drilled.set_physics_process(false)
	world._own_shells[94]["born"] -= 2000
	world._place(94, drilled, muzzle)
	check(not drilled.visible and world._own_shells[94].get("walk", {}).get("stop", -1.0) > 0.0 and world._predicted_hits.size() == 1,
		"the host's shell for it takes over its drilling: hidden where it stopped, its end not shown twice")
	world._despawn(94)
	# A kill by its own shell: the host's word of it is shown as it comes (the
	# tank gone, its explosion, score and sound), not a smoothing later; the
	# snapshot leaves them out when its time comes. Another tank's death, one
	# its shells didn't reach, waits for its time as before.
	var shot_dead := line[0]
	var other_dead := _spawn_enemy(home + Vector2(200, 0))  # none of its shells came near this one
	world._own_hits.clear()
	_player.can_shoot = true
	Input.action_press("p1_shoot")
	_fire_here()
	Input.action_release("p1_shoot")
	var at_tank: Bullet = world._ghosts[-1]["node"] if not world._ghosts.is_empty() else null
	if at_tank:
		at_tank.set_physics_process(false)
		for i in 60:
			at_tank._fly_ghost(1.0 / 60.0)
			if not at_tank.visible:
				break
	check(at_tank != null and not at_tank.visible and world._own_hits.has(shot_dead.get_instance_id())
		and not world._own_hits.has(other_dead.get_instance_id()),
		"its ghost reaching a tank: that tank noted as one its shells reached")
	world._nodes[95] = shot_dead
	world._states[95] = shot_dead.net_state()
	world._types[95] = NetWorld.T_ENEMY
	world._nodes[96] = other_dead
	world._states[96] = other_dead.net_state()
	world._types[96] = NetWorld.T_ENEMY
	var dead_at := shot_dead.global_position
	var far_at := other_dead.global_position
	var kill_frames := not ThemeManager.get_tank_explode_frames().is_empty()
	var boom := func(where: Vector2) -> Array:
		return [NetWorld.EV_HIT, "tank", where.x, where.y] if kill_frames else [NetWorld.EV_EXPLOSION, where.x, where.y, 2.0]
	var packet := []
	packet.resize(NetWorld.SNAP_SIZE)
	packet[NetWorld.SNAP_SEQ] = 1
	packet[NetWorld.SNAP_EPOCH] = 1
	packet[NetWorld.SNAP_TIME] = Time.get_ticks_msec() + 100000  # its time far off: only what's shown at once shows
	packet[NetWorld.SNAP_FLAGS] = 0
	packet[NetWorld.SNAP_MAP] = []
	packet[NetWorld.SNAP_SPAWNS] = []
	packet[NetWorld.SNAP_UPDATES] = PackedByteArray()
	packet[NetWorld.SNAP_REMOVED] = PackedInt32Array([95, 96])
	packet[NetWorld.SNAP_TILES] = PackedInt32Array()
	packet[NetWorld.SNAP_GAME] = {}
	packet[NetWorld.SNAP_EVENTS] = [[NetWorld.EV_SOUND, "tank_destroyed"], [NetWorld.EV_KILL_TEXT, 100, 1, dead_at.x, dead_at.y - 4.0],
			boom.call(dead_at + Vector2(3, -5)), [NetWorld.EV_SOUND, "tank_destroyed"], boom.call(far_at)]
	world._started = true
	world._epoch = 1
	world._buffer.clear()
	var clock_was := [world._clock_offset, world._have_clock, world._late.duplicate()]
	var shown_before := fx.get_child_count()
	world._on_packet(var_to_bytes(packet))
	world._clock_offset = clock_was[0]  # (the made-up snapshot's time is no clock to go by)
	world._have_clock = clock_was[1]
	world._late = clock_was[2]
	check(shot_dead.is_queued_for_deletion() and not world._nodes.has(95) and fx.get_child_count() == shown_before + 2
		and not world._own_hits.has(shot_dead.get_instance_id()),
		"that tank gone in the host's snapshot just come: gone at once, its explosion and score with it")
	var waiting: Dictionary = world._buffer[-1] if not world._buffer.is_empty() else {}
	check(Array(waiting.get("removed", [])) == [96] and waiting.get("events", []).size() == 2
		and waiting["events"][1] == boom.call(far_at) and world._nodes.has(96) and not other_dead.is_queued_for_deletion(),
		"another tank's death in it waits for its time, with its own explosion and sound")
	world._buffer.clear()
	world._started = false
	world._nodes.erase(96)
	world._states.erase(96)
	world._types.erase(96)
	other_dead.queue_free()
	line.remove_at(0)
	for i in 2:
		await tree.physics_frame  # (the tanks gone from the tree; its fire's press no longer "just" pressed)
	# One drawn ahead of the host's (its ghost gone) that its lead takes onto a
	# tank notes it too.
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	world._own_hits.clear()
	var below := line[0].global_position + Vector2.DOWN * 120.0
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(97, NetWorld.T_BULLET, [BaseTank.FACINGS.find(Vector2.UP), "regular", [0.0], 0, 384.0, -1.0, false, 0.0, 0.0, 999],
			[below.x, below.y])
	(world.node_for(97) as Bullet).set_physics_process(false)
	world._place(97, world.node_for(97), below)
	check(not world.node_for(97).visible and world._own_hits.has(line[0].get_instance_id()),
		"one drawn ahead reaching a tank here first: that tank noted too")
	world._despawn(97)
	# One drawn ahead meeting a shell of the enemies' here: the two meet at once,
	# as the host will have them.
	var aside := _at(home + Vector2(240, 0))
	var oncoming := _shown_enemy_shell(world, 116, home + Vector2(240, -60), Vector2.DOWN)
	world._spawn(117, NetWorld.T_BULLET, [BaseTank.FACINGS.find(Vector2.UP), "regular", [0.0], 0, 384.0, -1.0, false, 0.0, 0.0, 998, 1],
			[aside.x, aside.y])
	(world.node_for(117) as Bullet).set_physics_process(false)
	world._place(117, world.node_for(117), aside)
	var drawn_end: Vector2 = world._own_shells[117].get("ended_at", Vector2.INF)
	check(not world.node_for(117).visible and not oncoming.visible and world._guessed_clashes.has(oncoming.get_instance_id())
		and absf(drawn_end.y - (oncoming.global_position.y + Bullet.BULLET_LENGTH)) < 0.01,
		"one drawn ahead meeting a shell of the enemies' here: both gone at once, it ending where they touch")
	world._despawn(117)
	world._despawn(116)
	world._guessed_clashes.clear()
	# What comes onto the way it has flown already doesn't stop it: it got past.
	world._spawn(118, NetWorld.T_BULLET, [BaseTank.FACINGS.find(Vector2.UP), "regular", [0.0], 0, 384.0, -1.0, false, 0.0, 0.0, 997, 1],
			[aside.x, aside.y])
	var clear_shot := world.node_for(118) as Bullet
	clear_shot.set_physics_process(false)
	world._place(118, clear_shot, aside)
	var behind_it := _spawn_enemy(home + Vector2(240, -20))
	world._place(118, clear_shot, aside)
	check(clear_shot.visible and not world._own_hits.has(behind_it.get_instance_id()),
		"a tank coming onto the way it has flown already, behind it: it flies on")
	behind_it.queue_free()
	world._despawn(118)
	world._predicted_hits.clear()
	# A moon shield's front stops it, as on the host.
	line[0].has_moon_shield = true
	line[0].current_direction = Vector2.DOWN
	_player.active_ap_bullets = 0
	_player.can_shoot = true
	Input.action_press("p1_shoot2")
	_fire_here()
	Input.action_release("p1_shoot2")
	drill = world._ghosts[-1]["node"] if not world._ghosts.is_empty() else null
	if drill:
		drill.set_physics_process(false)
		for i in 120:
			drill._fly_ghost(1.0 / 60.0)
			if not drill.visible:
				break
	check(drill != null and drill.pierces and not drill.visible and drill.global_position.y > line[0].global_position.y,
		"a tank's moon shield, facing it, stops it at once")
	for enemy in line:
		enemy.queue_free()
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	world._predicted_hits.clear()
	# The bricks it drills through break here at once too.
	for i in 2:
		await tree.physics_frame  # (the tanks gone)
	var ap_bricks: Array[Vector2i] = []
	for x in [-16, 16]:
		var cell := _lm.world_to_tile(_at(home + Vector2(x, -128)))
		_lm._place_fg_tile(cell, 0x19)
		ap_bricks.append(cell)
	_player.active_ap_bullets = 0
	_player.can_shoot = true
	Input.action_press("p1_shoot2")
	_fire_here()
	Input.action_release("p1_shoot2")
	var through_wall: Bullet = world._ghosts[-1]["node"] if not world._ghosts.is_empty() else null
	if through_wall:
		through_wall.set_physics_process(false)
		for i in 30:
			through_wall._fly_ghost(1.0 / 60.0)
	check(through_wall != null and through_wall.visible and not world._guessed_walls.is_empty()
		and ap_bricks.all(func(cell: Vector2i) -> bool: return not _lm._fg_tile_data.has(cell)),
		"an AP shell's drilling breaks the bricks here at once, and on it flies")
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	world._guessed_walls.clear()
	world._predicted_hits.clear()
	SoundManager._predicted = heard_before
	_player.active_ap_bullets = 0
	Net.role = Net.Role.CLIENT
	GameManager.set_secondary_weapon(0, "rapid", 1)
	Net.role = Net.Role.OFFLINE
	check(GameManager.player_secondary_weapon_types[0] == "ap" and GameManager.player_secondary_weapon_counts[0] == 9,
		"a client's own shots spend none of the host's numbers")
	GameManager.player_secondary_weapon_types[0] = "mine"
	var mines := _lm.get_mines().size()
	await _wait_frames(2)  # (a press of its own, not in the frame of the last,
	await tree.process_frame  # and in an idle frame, where it's just pressed at once)
	Input.action_press("p1_shoot2")
	_player.can_shoot = true
	_fire_here()
	Input.action_release("p1_shoot2")
	await tree.process_frame  # (a mine goes in deferred)
	var laid_here: Mine = world._ghost_mines[-1]["node"] if world._ghost_mines.size() == 1 else null
	check(world._ghosts.is_empty() and SoundManager._predicted.size() == 3 and SoundManager._predicted[-1][1] == &"lay_mine"
		and _lm.get_mines().size() == mines and laid_here != null and laid_here.net_shot == 256 + int(Net._shots[0][1])
		and laid_here.collision_mask == 0,
		"a mine: laid here at once, heard, numbered for the host (no mine of the host's world laid here)")
	if laid_here:
		laid_here.queue_free()
	world._ghost_mines.clear()
	# An explosion shell of the gun's top level breaks the iron it hits here at
	# once, as the host's will (Sean's rule): the two tiles in its way.
	var level_was: int = GameManager.player_weapon_levels[0]
	GameManager.player_secondary_weapon_types[0] = "explosion"
	GameManager.player_weapon_levels[0] = 3
	var iron_cells: Array[Vector2i] = []
	for x in [-16, 16]:
		var cell := _lm.world_to_tile(_at(home + Vector2(x, -160)))
		_lm._place_fg_tile(cell, 0x39)
		iron_cells.append(cell)
	for i in 2:
		await tree.physics_frame  # (a press between two physics frames counts in the next one)
	_player.active_explosion_bullets = 0
	var iron_shot := _fly_shot(world, "p1_shoot2")
	check(iron_shot != null and iron_shot.explodes and not iron_shot.visible and world._guessed_walls.size() == 1
		and iron_cells.all(func(cell: Vector2i) -> bool: return not _lm._fg_tile_data.has(cell)),
		"a top-level explosion shell at iron: the two tiles in its way broken here at once, as on the host")
	for cell: Vector2i in iron_cells:
		_lm._remove_fg_tile(cell)
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	world._guessed_walls.clear()
	world._predicted_hits.clear()
	_player.active_explosion_bullets = 0
	GameManager.player_weapon_levels[0] = level_was
	_player._take_host_weapons()
	GameManager.player_secondary_weapon_types[0] = kind
	GameManager.player_secondary_weapon_counts[0] = count
	SoundManager._predicted.clear()

	# Its own kills reacted to here first (Sean: "react locally first"): a shot
	# taking a tank's last health shows it dying at once, its explosion and
	# sound; the host's word settles it.
	for i in 2:
		await tree.physics_frame
	var above := home + Vector2.UP * (BaseTank.TANK_SIZE * 0.5 + 80.0)
	var victim := _shown_enemy(world, 98, above, 1)
	var effects_before := fx.get_child_count()
	var heard_at := Time.get_ticks_msec()
	var my_shot := _fly_shot(world)
	check(my_shot != null and not my_shot.visible and victim.net_gone and not victim.visible and not victim.is_solid()
		and world._guessed_kills.has(victim.get_instance_id()) and fx.get_child_count() >= effects_before + 2
		and int(SoundManager._last_played.get(&"tank_destroyed", 0)) >= heard_at,
		"a shot taking a tank's last health: shown dying here at once, its explosion and sound, not a trip later")
	var victim_at := victim.global_position
	var big_boom: Array = [NetWorld.EV_HIT, "tank", victim_at.x, victim_at.y] if not ThemeManager.get_tank_explode_frames().is_empty() \
			else [NetWorld.EV_EXPLOSION, victim_at.x, victim_at.y, 2.0]
	await tree.create_timer(0.1).timeout  # (past the sound's repeat guard)
	effects_before = fx.get_child_count()
	var boom_heard := int(SoundManager._last_played.get(&"tank_destroyed", 0))
	_host_says(world, [98], [[NetWorld.EV_SOUND, "tank_destroyed"], [NetWorld.EV_KILL_TEXT, 100, 1, victim_at.x, victim_at.y], big_boom])
	check(not world._nodes.has(98) and world._guessed_kills.is_empty() and fx.get_child_count() == effects_before + 1
		and int(SoundManager._last_played.get(&"tank_destroyed", 0)) == boom_heard,
		"the host's word of it comes: its score shows, its explosion and sound not again")
	for i in 2:
		await tree.physics_frame
	# More health left than the my_shot takes: no guess.
	var tough := _shown_enemy(world, 99, above, 2)
	my_shot = _fly_shot(world)
	check(my_shot != null and not my_shot.visible and not tough.net_gone and tough.visible and world._guessed_kills.is_empty(),
		"a tank with more health left than the shot takes: no guess, the host's word will say")
	world._despawn(99)
	for i in 2:
		await tree.physics_frame
	# A shell of the enemies' head-on on the way: the two meet here as the host
	# will have them meet (it judges this machine's shots by what this machine
	# shows), both gone at once, their ends shown; the tank behind lives.
	var dueller := _shown_enemy(world, 100, above, 1)
	var theirs := _shown_enemy_shell(world, 110, home + Vector2.UP * 70.0, Vector2.DOWN)
	world._predicted_hits.clear()
	my_shot = _fly_shot(world)
	check(my_shot != null and not my_shot.visible and absf(my_shot.global_position.y - theirs.global_position.y) < Bullet.BULLET_LENGTH
		and not theirs.visible and world._guessed_clashes.has(theirs.get_instance_id()) and world._predicted_hits.size() == 2,
		"a shell of the enemies' head-on on the way: the two meet here at once, both gone, both ends shown")
	check(not dueller.net_gone and dueller.visible, "and the tank behind it lives: no kill")
	_host_says(world, [110], [])
	check(world._guessed_clashes.is_empty() and not theirs.visible, "the host's word of theirs gone: settled")
	world._despawn(110)
	world._despawn(100)
	# The host's word that they didn't meet: its shell gone, theirs still there.
	var stray := _shown_enemy_shell(world, 111, home + Vector2.UP * 70.0, Vector2.DOWN)
	my_shot = _fly_shot(world)
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(112, NetWorld.T_BULLET, my_shot.net_spawn_args(), [muzzle.x, muzzle.y])
	(world.node_for(112) as Bullet).set_physics_process(false)
	undone = world.guesses_undone
	_host_says(world, [112], [])
	check(stray.visible and world._guessed_clashes.is_empty() and world.guesses_undone == undone + 1,
		"its shell gone on the host and theirs still there: theirs shows again")
	world._despawn(112)
	world._despawn(111)
	world._predicted_hits.clear()
	# An AP shell meeting one: theirs goes, it flies on a point the poorer.
	GameManager.player_secondary_weapon_types[0] = "ap"
	GameManager.player_secondary_weapon_counts[0] = 9
	_player.active_ap_bullets = 0
	for i in 2:
		await tree.physics_frame
	var met_by_ap := _shown_enemy_shell(world, 113, home + Vector2.UP * 90.0, Vector2.DOWN)
	_player.can_shoot = true
	Input.action_press("p1_shoot2")
	_fire_here()
	Input.action_release("p1_shoot2")
	var through: Bullet = world._ghosts[-1]["node"] if not world._ghosts.is_empty() else null
	if through:
		through.set_physics_process(false)
		for i in 20:
			through._fly_ghost(1.0 / 60.0)
	check(through != null and through.pierces and through.visible and through.global_position.y < met_by_ap.global_position.y - 20.0
		and not met_by_ap.visible and int(through.net_walk.get("pool", 0)) == through.damage - 1,
		"an AP shell meeting one: theirs gone, it flies on with a point less (%s of %d)" % [
			str(through.net_walk.get("pool", -1)) if through else "none", through.damage if through else -1])
	world._despawn(113)
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	world._guessed_clashes.clear()
	world._predicted_hits.clear()
	GameManager.player_secondary_weapon_types[0] = kind
	GameManager.player_secondary_weapon_counts[0] = count
	for i in 2:
		await tree.physics_frame
	# One driving across the shot, or facing it: where it's shown is where the
	# host judges the shot to hit it: guessed.
	var leaving := _shown_enemy(world, 101, above + Vector2(20, 0), 1)
	leaving.move_speed = 200.0
	world._states[101][2] = BaseTank.FACINGS.find(Vector2.RIGHT)
	world._states[101][3] = int(world._states[101][3]) | BaseTank.NET_MOVING
	my_shot = _fly_shot(world)
	check(my_shot != null and not my_shot.visible and leaving.net_gone,
		"one driving across the shot, hit where it's shown: guessed (the host judges by what's shown here)")
	world._despawn(101)
	world._guessed_kills.clear()
	for i in 2:
		await tree.physics_frame
	var facing_me := _shown_enemy(world, 107, above, 1)
	facing_me.current_direction = Vector2.DOWN
	world._states[107][2] = BaseTank.FACINGS.find(Vector2.DOWN)
	my_shot = _fly_shot(world)
	check(my_shot != null and not my_shot.visible and facing_me.net_gone, "one facing the shot: guessed too")
	world._despawn(107)
	world._guessed_kills.clear()
	for i in 2:
		await tree.physics_frame
	# Not sure enough to guess: a tank the shot only grazes (the host's look at
	# this screen may be a frame off), or this machine shown further behind the
	# host than the host looks back.
	var grazing := Bullet.box_half(Vector2.UP, BaseTank.MID_ROW_COLLISION_OFFSETS).x + BaseTank.HITBOX_SIZE * 0.5 - 2.0
	var grazed := _shown_enemy(world, 108, above + Vector2(grazing, 0), 1)
	grazed.current_direction = Vector2.RIGHT
	grazed.velocity = Vector2.RIGHT  # (driving across the shot's way)
	my_shot = _fly_shot(world)
	check(my_shot != null and not my_shot.visible and world._own_hits.has(grazed.get_instance_id()) and not grazed.net_gone,
		"one driving across the shot's way that the shot only grazes: it ends there, but no guess")
	world._despawn(108)
	for i in 2:
		await tree.physics_frame
	var standing := _shown_enemy(world, 119, above + Vector2(grazing, 0), 1)
	my_shot = _fly_shot(world)
	check(my_shot != null and not my_shot.visible and standing.net_gone,
		"one standing there (just where it's shown, on both machines): guessed")
	world._despawn(119)
	world._guessed_kills.clear()
	for i in 2:
		await tree.physics_frame
	var ping_was := Net.ping_ms
	Net.ping_ms = NetClientWorld.GUESS_MAX_LAG_MS
	var far_behind := _shown_enemy(world, 109, above, 1)
	my_shot = _fly_shot(world)
	check(my_shot != null and not my_shot.visible and not far_behind.net_gone,
		"shown further behind the host than it looks back: no guess")
	Net.ping_ms = ping_was
	world._despawn(109)
	for i in 2:
		await tree.physics_frame
	# A wrong guess: the host's shell for that shot gone, the tank still there.
	var lucky := _shown_enemy(world, 102, above, 1)
	my_shot = _fly_shot(world)
	check(lucky.net_gone, "(guessed)")
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(103, NetWorld.T_BULLET, my_shot.net_spawn_args(), [muzzle.x, muzzle.y])
	(world.node_for(103) as Bullet).set_physics_process(false)
	undone = world.guesses_undone
	_host_says(world, [103], [])
	check(not lucky.net_gone and lucky.visible and lucky.is_solid() and world._guessed_kills.is_empty()
		and world.guesses_undone == undone + 1,
		"its shell gone on the host and the tank still there: it shows again")
	world._despawn(103)
	world._despawn(102)
	for i in 2:
		await tree.physics_frame
	# The host's shell for it seen on past where it ended here: it shows again.
	var missed := _shown_enemy(world, 114, above, 1)
	my_shot = _fly_shot(world)
	var ended_here := my_shot.global_position if my_shot else Vector2.ZERO
	check(missed.net_gone, "(guessed)")
	world._shown_time = Time.get_ticks_msec() - world.render_delay()
	world._spawn(115, NetWorld.T_BULLET, my_shot.net_spawn_args(), [muzzle.x, muzzle.y])
	(world.node_for(115) as Bullet).set_physics_process(false)
	var on_past := ended_here + Vector2.DOWN * 20.0
	_host_says(world, [], [], {115: [on_past.x, on_past.y]})
	check(missed.net_gone, "the host's shell for it short of where it ended here: still guessed")
	on_past = ended_here + Vector2.UP * (NetClientWorld.GUESS_PAST + 8.0)
	undone = world.guesses_undone
	_host_says(world, [], [], {115: [on_past.x, on_past.y]})
	check(not missed.net_gone and missed.visible and world.guesses_undone == undone + 1,
		"the host's shell for it seen past where it ended here: it shows again")
	world._despawn(115)
	world._despawn(114)
	for i in 2:
		await tree.physics_frame
	# No word either way for long: it shows again.
	var silent := _shown_enemy(world, 104, above, 1)
	my_shot = _fly_shot(world)
	world._guessed_kills[silent.get_instance_id()]["msec"] -= int(NetClientWorld.GUESS_MAX_MS) + 1
	_host_says(world, [], [])
	check(not silent.net_gone and silent.visible, "no word either way for %.1f s: it shows again" % (NetClientWorld.GUESS_MAX_MS / 1000.0))
	world._despawn(104)
	for i in 2:
		await tree.physics_frame
	# An AP shell guesses each tank its pool would kill on the way.
	var pair: Array[EnemyTank] = [_shown_enemy(world, 105, above, 1), _shown_enemy(world, 106, above + Vector2.UP * 70.0, 1)]
	GameManager.player_secondary_weapon_types[0] = "ap"
	GameManager.player_secondary_weapon_counts[0] = 9
	_player.active_ap_bullets = 0
	my_shot = _fly_shot(world, "p1_shoot2")
	check(my_shot != null and my_shot.pierces and pair.all(func(enemy: EnemyTank) -> bool: return enemy.net_gone),
		"an AP shell guesses each tank its pool kills on the way")
	world._despawn(105)
	world._despawn(106)
	GameManager.player_secondary_weapon_types[0] = kind
	GameManager.player_secondary_weapon_counts[0] = count
	for entry: Dictionary in world._ghosts:
		entry["node"].queue_free()
	world._ghosts.clear()
	world._guessed_kills.clear()
	world._guessed_clashes.clear()
	world._own_hits.clear()
	world._predicted_hits.clear()
	SoundManager._predicted.clear()

	print("\n[H2] What hits its own tank: shown at once, as the host judges it")
	world._nodes[5] = _player
	_player.set_net_predicted(true, 0)
	_place(home, Vector2.UP)
	var hp_kept := _player.health
	var shield_kept := _player.has_moon_shield
	_player.health = 4
	_player.is_invincible = false
	_player.has_moon_shield = false
	Net.ping_ms = 30.0
	var end_event := func(at: Vector2) -> Array:
		return [NetWorld.EV_HIT, "regular", at.x, at.y] if themed else [NetWorld.EV_EXPLOSION, at.x, at.y, 1.0]
	var fx_before := fx.get_child_count()
	var incoming := _shown_enemy_shell(world, 130, home + Vector2(0, -30), Vector2.DOWN)
	world._show_own_hits()
	check(not incoming.visible and world._guessed_hits.has(incoming.get_instance_id()) and world._predicted_hits.size() == 1
		and fx.get_child_count() > fx_before,
		"an enemies' shell on its own tank as shown here: it ends there at once, its end's picture shown")
	check(SoundManager._predicted.size() == 1 and SoundManager._predicted[0][0] == 0 and SoundManager._predicted[0][1] == &"tank_hit"
		and _player._damage_flash_timer > 0.3, "a hit it survives: its red flash and its sound at once")
	var before_word := _player.net_state()
	before_word[4] = 0.0
	_player.net_apply(before_word)
	check(_player._damage_flash_timer > 0.3, "the host's state from before its word of the hit doesn't stop the flash")
	# The host's word of that hit brings its flash again, after the one here has
	# ended (a long line): left out, it's the same hit's. A later one of the
	# host's own flashes.
	_player._flash_guessed_until = Time.get_ticks_msec()
	var flashing := _player.net_state()
	flashing[4] = BaseTank.DAMAGE_FLASH_DURATION
	_player.net_apply(flashing)
	check(_player._damage_flash_timer <= 0.0, "the host's flash of that same hit, come after it ended here: left out")
	flashing[4] = 0.0
	_player.net_apply(flashing)
	flashing[4] = BaseTank.DAMAGE_FLASH_DURATION
	_player.net_apply(flashing)
	check(_player._damage_flash_timer > 0.3, "the host's flash of a later hit of its own: shown")
	flashing[4] = 0.0
	_player.net_apply(flashing)
	# The host's word: the shell gone, with its end's picture there and its hit's
	# sound, shown and heard here already; and the picture of its end further on,
	# where the host had it wait for this screen's word (Bullet._end_with), which
	# never came here.
	var at_hit := incoming.global_position
	var further := at_hit + Vector2.DOWN * 90.0
	var hit_word := _host_says(world, [130], [end_event.call(at_hit), end_event.call(further), [NetWorld.EV_SOUND, "tank_hit", 0]])
	var events_left: Array = hit_word.get("events", [])
	check(world._guessed_hits.is_empty() and events_left.size() == 2 and not events_left.has(end_event.call(further)),
		"the host's word, the shell gone: settled, and the picture of its end further on left out")
	var fx_now := fx.get_child_count()
	for event: Array in events_left:
		world._play(event)
	check(fx.get_child_count() == fx_now and SoundManager._predicted.is_empty(),
		"its end's picture there and its sound, shown and heard already, aren't again")
	world._despawn(130)
	# Within its grace after that, another: it ends there, no second sound.
	var another := _shown_enemy_shell(world, 131, home + Vector2(0, -28), Vector2.DOWN)
	world._show_own_hits()
	check(not another.visible and SoundManager._predicted.is_empty(), "another within its grace: it ends there, no sound again")
	# The host's word not come yet by a moment it would have: still ended here.
	# A moment past that, the shell still there: it missed, and flies on here.
	world._guessed_hits[another.get_instance_id()]["until"] = Time.get_ticks_msec() + 1.0e9
	_host_says(world, [], [])
	check(not another.visible and world._guessed_hits.size() == 1, "no word yet: still ended here")
	world._guessed_hits[another.get_instance_id()]["until"] = 0.0
	var undone_hits := world.guesses_undone
	_host_says(world, [], [])
	check(another.visible and world._guessed_hits.is_empty() and world.guesses_undone == undone_hits + 1,
		"the host's world past when its word would have come, the shell still in it: it missed, on it flies here")
	world._despawn(131)
	# The host's invincibility only a hit's grace, over on this machine's frames:
	# a hit shown at once (the host judges it so too).
	_player.is_invincible = true
	_player.net_hit_grace_only = true
	_player._grace_guessed_frame = Net.reported_frame(0) - 40
	SoundManager._predicted.clear()
	var past_grace := _shown_enemy_shell(world, 136, home + Vector2(0, -30), Vector2.DOWN)
	world._show_own_hits()
	check(not past_grace.visible and SoundManager._predicted.size() == 1,
		"its grace over by this machine's frames, the host's flag only that grace's: a hit, shown at once")
	world._despawn(136)
	world._guessed_hits.clear()
	SoundManager._predicted.clear()
	_player.is_invincible = false
	_player.net_hit_grace_only = false
	_player._grace_guessed_frame = -100000
	_player._flash_guessed_until = 0
	# Not shown at once: a shell meeting it by a hair (left to the host's word);
	# and while shown further behind the host than it looks back.
	var reach_y := Bullet.box_half(Vector2.DOWN, [0.0]).y + BaseTank.HITBOX_SIZE * 0.5
	var hair := _shown_enemy_shell(world, 132, home + Vector2(0, -(reach_y - 0.3)), Vector2.DOWN)
	world._show_own_hits()
	check(hair.visible and world._guessed_hits.is_empty(), "one meeting it by a hair: the host's word to say")
	world._despawn(132)
	Net.ping_ms = NetClientWorld.HIT_GUESS_MAX_LAG_MS
	var far_behind_hit := _shown_enemy_shell(world, 133, home + Vector2(0, -30), Vector2.DOWN)
	world._show_own_hits()
	check(far_behind_hit.visible and world._guessed_hits.is_empty(), "shown further behind the host than it looks back: its word to say")
	Net.ping_ms = 30.0
	world._despawn(133)
	# Ended here, without a flash or sound: on its moon shield's front; and a
	# fatal hit shows the tank's end at once (Sean, 2026-10-09: "let guest
	# process all the thing locally").
	_player.has_moon_shield = true
	var on_shield := _shown_enemy_shell(world, 134, home + Vector2(0, -30), Vector2.DOWN)
	world._show_own_hits()
	check(not on_shield.visible and SoundManager._predicted.is_empty() and _player._flash_guessed_until <= Time.get_ticks_msec(),
		"on its moon shield's front: it ends there, no flash, no sound")
	_player.has_moon_shield = false
	world._despawn(134)
	_player.health = 1
	var fatal := _shown_enemy_shell(world, 135, home + Vector2(0, -30), Vector2.DOWN)
	world._show_own_hits()
	var death_heard: Array = SoundManager._predicted.map(func(entry: Array) -> StringName: return entry[1])
	check(not fatal.visible and _player.net_gone and not _player.visible and not _player.is_net_driving()
		and world._guessed_deaths.has(_player.get_instance_id()) and death_heard == [&"tank_destroyed"],
		"a fatal one: it ends there, and the tank with it at once, its sound heard (%s)" % str(death_heard))
	world._guessed_deaths.clear()
	_player.net_gone = false
	_player.visible = true
	world._despawn(135)
	world._guessed_hits.clear()
	world._predicted_hits.clear()
	SoundManager._predicted.clear()
	_player._flash_guessed_until = 0
	_player.health = hp_kept
	_player.has_moon_shield = shield_kept
	_player.is_invincible = true
	world._nodes.erase(5)

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

	print("\n[L] What happens to its tank there its client decides: its word does it here (Sean, 2026-10-09: \"let guest process all the thing locally\")")
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [0, 0])
	PlayerInput.set_seat(0, PlayerInput.controller_key(PEER, 0))
	var own_world := NetHostWorld.new()
	own_world.setup(_game, _lm, null)
	_game.add_child(own_world)
	_feeding = false
	_player.set_physics_process(false)
	_player._host_drives = false
	_player.is_invincible = false
	_player._hit_grace_only = false
	_player.has_moon_shield = false
	_player.health = 4
	_player.clear_mine_slow()
	_place(home, Vector2.UP)
	_client_has = true
	_client_predicts = true
	_client_view = Time.get_ticks_msec()
	_send_report(home, Vector2.UP, false, _player.net_override)
	var own_pad := PlayerInput.remote_pad(0)
	check(_player.processed_there(), "its client drives it there and says what its screen shows: what happens to it is that client's")
	# This machine's fire, blasts and mines leave it be.
	_lm.ignite_fire_patch(_lm.fire_anchor(_at(home)), false)
	await tree.process_frame
	for node in _lm.terrain_node.get_children():
		if node is GroundFire:
			node._armed = true
	_lm._burn_tanks()
	check(_player.health == 4, "the enemies' fire under it here: it burns there, not here")
	_lm._clear_fire()
	var their_blast := ExplosionBlast.new()
	their_blast.setup(2, false, _lm)
	their_blast.origin = ExplosionBlast.grid_origin(_at(home) - _lm.global_position, ExplosionBlast.SHELL_SIZE)
	tree.get_first_node_in_group("effects_container").add_child(their_blast)
	their_blast.set_process(false)
	their_blast._frame = 6
	their_blast._hurt_tanks()
	check(_player.health == 4 and _player.blast_immunity <= 0.0, "an enemies' blast on it here: its heat there, not here")
	their_blast.queue_free()
	var mine_under := _lm._spawn_mine(_lm.world_to_tile(_at(home)) - Vector2i.ONE, 2, false)
	mine_under._age = 1.0
	for i in 4:
		await tree.physics_frame
	check(is_instance_valid(mine_under) and mine_under.is_armed() and not _player.is_mine_slowed and not _player.is_flying,
		"an armed mine of the enemies' under it here: set off there, not here")
	if not is_instance_valid(mine_under):
		mine_under = _lm._spawn_mine(_lm.world_to_tile(_at(home + Vector2(0, -200))) - Vector2i.ONE, 2, false)
		await tree.process_frame
	# Its words, done here.
	_send_report(home, Vector2.UP, false, _player.net_override)
	PlayerInput.add_remote_event(PEER, 0, Net.OWN_HIT, _client_frame & 0xff, 1, Net.OWN_FIRE, -1, 0, _at(home), Vector2.ZERO)
	var said_frame := own_pad.report_frame  # (its frame as the reports with it count them)
	_player._take_reported_events()
	check(_player.health == 3 and _player._screen_grace_frame == said_frame and own_pad.events.is_empty()
		and _player.fire_immunity_timer > 0.0, "its word of a burn there: a point off here at once, its grace from that frame")
	_send_report(home, Vector2.UP, false, _player.net_override)
	PlayerInput.add_remote_event(PEER, 0, Net.OWN_HIT, _client_frame & 0xff, 2, 0, -1, 0, _at(home), Vector2.ZERO)
	_player._take_reported_events()
	check(_player.health == 1, "a blast's word, 2 more, within this copy's grace here: done all the same (its screen's grace was over)")
	_player.health = 4
	mine_under.set_meta(&"nid", 4242)
	var override_was := _player.net_override
	var on_mine := home + Vector2(8, 0)
	PlayerInput.add_remote_event(PEER, 0, Net.OWN_MINE, _client_frame & 0xff, 2,
			Net.OWN_SLOWED | Net.OWN_THROWN | Net.OWN_SPIN_BACK, -1, 4242, _at(on_mine), mine_under.global_position)
	_player._take_reported_events()
	check(mine_under._triggered and _player.is_flying and _player._flight_there and _player.fly_way == -1 and _player.is_mine_slowed
		and _player.global_position.distance_to(_at(on_mine)) < 0.01,
		"its word of a mine it set off there: off here, this copy slowed and thrown from where its screen had it, its way round")
	check(int(_player.net_state()[3]) & PlayerTank.NET_FLIGHT_THERE != 0 and _player.processed_there(),
		"its state says the flight is its client's, as is what happens to it meanwhile")
	for i in 240:
		if not _player.is_flying:
			break
		_player._physics_process(1.0 / 60.0)
	check(not _player.is_flying and _player.net_override == override_was and _player.health == 4,
		"its flight here: no correction, landing included, and down with no hit here (its word brings the landing's)")
	_player.apply_addon("moon-shield")
	var levels_were := [GameManager.player_speed_levels[0], GameManager.player_weapon_levels[0]]
	_send_report(_player.global_position - _lm.global_position, Vector2.UP, false, _player.net_override)
	PlayerInput.add_remote_event(PEER, 0, Net.OWN_HIT, _client_frame & 0xff, 1, Net.OWN_LANDING, -1, 0,
			_player.global_position, Vector2.ZERO)
	_player._take_reported_events()
	check(not _player.has_moon_shield and _player.health == 3
		and [GameManager.player_speed_levels[0], GameManager.player_weapon_levels[0]] == levels_were,
		"its word of the landing's hit: its moon shield, then the point, as an airborne tank takes them (no level)")
	# With nothing on: still no level, and no grace after (it was in the air).
	_player.speed_level = 2
	_player.weapon_level = 2
	GameManager.set_speed_level(0, 2)
	GameManager.set_weapon_level(0, 2)
	PlayerInput.add_remote_event(PEER, 0, Net.OWN_HIT, _client_frame & 0xff, 1, Net.OWN_LANDING, -1, 0,
			_player.global_position, Vector2.ZERO)
	_player._take_reported_events()
	check(_player.health == 2 and _player.speed_level == 2 and _player.weapon_level == 2 and not _player.is_invincible,
		"another, with nothing on: the point alone, no level lost and no grace after")
	# Its frames in the air there: no shell of the enemies' its screen had on it
	# hits it, no air_item it was over is taken.
	_player.health = 4
	_player.lift_hit_grace()
	var t_air := Time.get_ticks_msec() - 100.0
	var over_it := _enemy_shell(home + Vector2(0, -20), Vector2.DOWN)
	_keep_at(own_world, t_air)
	_place(home, Vector2.UP)
	for i in 40:
		_send_report(home, Vector2.UP, false, _player.net_override)  # (its grace from the hits above over there)
	own_pad.judge.clear()  # (this section's earlier frames: judged already)
	_client_flying = true
	_judge_report(home, Vector2.UP, t_air)
	var after_flying := _player.health
	_client_flying = false
	_judge_report(home, Vector2.UP, t_air)
	check(after_flying == 4 and _player.health == 3, "a shell its screen had on it: no hit in a frame it was in the air there, a hit in one it wasn't")
	over_it.queue_free()
	var air_item: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	air_item.setup(CookieData.CookieType.SCORE_500, 0.0)
	tree.get_first_node_in_group("powerups_container").add_child(air_item)
	air_item.global_position = _at(home + Vector2(40, 0))
	_player.global_position = _at(home)
	own_pad.reach.clear()  # (this section's earlier frames: looked at already)
	_client_flying = true
	_send_report(home + Vector2(40, 0), Vector2.RIGHT, false, _player.net_override)
	_player._take_items_where_reported()
	var kept_in_air := not air_item.is_queued_for_deletion()
	_client_flying = false
	_send_report(home + Vector2(40, 0), Vector2.RIGHT, false, _player.net_override)
	_player._take_items_where_reported()
	check(kept_in_air and air_item.is_queued_for_deletion(), "an item it flew over there: not taken; one it drove onto: taken")
	# The blasts the clients are told of say whose they are.
	var blast_view := NetHostWorld.ClientView.new()
	blast_view.full = false
	own_world._views[PEER] = blast_view
	_lm.spawn_explosion_blast(_at(home + Vector2(300, 0)), 1, true, true)
	var blast_told: Array = blast_view.events.filter(func(e: Array) -> bool: return int(e[0]) == NetWorld.EV_BLAST)
	check(blast_told.size() == 1 and (blast_told[0] as Array).size() == 5 and int(blast_told[0][4]) == NetWorld.blast_kind(true, true, false),
		"a blast told the clients says whose it is: a landing's, everyone's (%s)" % str(blast_told))
	own_world._views.erase(PEER)
	# A record as it comes: its frame counted as its reports are (past 255).
	for i in 300:
		_send_report(home, Vector2.UP, false, _player.net_override)
	var record := PackedByteArray()
	record.resize(Net.OWN_SIZE)
	record[0] = 0
	record[1] = Net.OWN_HIT
	record[2] = _client_frame & 0xff
	record[3] = 1
	record[4] = Net.OWN_FIRE
	record.encode_float(12, _player.global_position.x)
	record.encode_float(16, _player.global_position.y)
	Net.take_own_events(PEER, record)
	Net.take_own_events(PEER, record.slice(0, Net.OWN_SIZE - 1))
	var taken: Array = own_pad.events[0] if own_pad.events.size() == 1 else []
	check(not taken.is_empty() and int(taken[0]) == Net.OWN_HIT and int(taken[1]) == own_pad.report_frame
		and int(taken[2]) == 1 and int(taken[3]) == Net.OWN_FIRE and int(taken[4]) == -1
		and (taken[6] as Vector2).distance_to(_player.global_position) < 0.01,
		"its word as it comes: queued for this copy, its frame counted as its reports are; a broken one not")
	own_pad.events.clear()
	_client_has = false
	_send_report(home, Vector2.UP, false, _player.net_override)
	check(not _player.processed_there(), "its client not driving it there: what happens to it is this machine's again")
	_client_has = true
	_player.clear_mine_slow()
	_player.health = 4
	for node in tree.get_first_node_in_group("effects_container").get_children():
		if node is ExplosionBlast:
			node.queue_free()
	own_world.queue_free()
	await tree.process_frame

	print("\n[K] A hit its screen showed finishing its tank: it goes up where that screen had it")
	# (Last: the tank is gone after it.)
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [0, 0])
	PlayerInput.set_seat(0, PlayerInput.controller_key(PEER, 0))
	var last_world := NetHostWorld.new()
	last_world.setup(_game, _lm, null)
	_game.add_child(last_world)
	_feeding = false
	_player.set_physics_process(false)
	_player._host_drives = false
	_player.is_invincible = false
	_player.has_moon_shield = false
	_player.health = 1
	_place(home, Vector2.UP)
	var t_k := Time.get_ticks_msec() - 100.0
	var fatal_shell := _enemy_shell(home + Vector2(40, -30), Vector2.DOWN)
	_keep_at(last_world, t_k)
	fatal_shell.global_position = _at(home + Vector2(40, -330))
	_keep_at(last_world, t_k + 34.0)
	var went_up := [Vector2.INF]
	_player.tree_exiting.connect(func() -> void: went_up[0] = _player.global_position)
	_judge_report(home + Vector2(40, 0), Vector2.UP, t_k)
	await tree.process_frame
	check(went_up[0].distance_to(_at(home + Vector2(40, 0))) < 0.01,
		"finished where its screen had it, 40 px from the copy here (%s)" % str(went_up[0] - _lm.global_position))

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
