extends Node
## Headless test for online lag compensation (docs/network_design.md, section 7)
## between two machines with a long line between them: this process hosts a
## game, and starts itself again as a client ("--online-lag-client") whose line
## to the host is LAG_MS long each way ("--net-lag-ms"), 150 ms there and back.
## The client's own tank still answers its keys at once; the host's copy follows
## it and ends where it is, never corrected in open ground; the client's own
## shot shows and is heard at once, out of its tank's barrel, and the host's
## shell takes over from it where it is; AUTO smoothing settles low on the
## steady line; both sides know the ping, and the host's list of players shows
## it; a correction from the host puts the client's tank where the host has it,
## to drive on from there; and with LAG COMPENSATION off, the client's keys
## drive the host's tank as they come, as before, until it's on again. Last,
## each machine stands still a while in turn, as when its window goes
## fullscreen or out of sight: its frames slip against the other's for good, and
## the host's copy keeps up with the client's tank all the same, as smoothly as
## before within a second or two.
##
## online_lag_jitter_test.tscn does it all again with the line jittering too
## ("--net-jitter-ms": each message up to jitter_ms later still, never
## overtaking the one before, as TCP bunches them up), as a busy LAN or the
## internet would.
##
## The client's checks come back in its results file and count here. The parts
## on their own are net_follow_test's.
## Run as an override main scene:
##   Godot --headless res://scenes/test/online_lag_test.tscn
##   Godot --headless res://scenes/test/online_lag_jitter_test.tscn

const SCENE := "res://scenes/test/online_lag_test.tscn"
## The client's line to the host, each way.
const LAG_MS := 75
const CLIENT_RESULTS := "user://test_online_lag_client.txt"
## The client has driven and fired: the host's turn to correct it.
const DRIVEN := "user://test_online_lag_driven.txt"
## The host corrected the client's tank: where it put it.
const CORRECTED := "user://test_online_lag_corrected.txt"
## The client drives up and down without a break: the host's turn to stand
## still; the host has, and seen how its copy went: the client's turn; done.
const SLIPPING := "user://test_online_lag_slipping.txt"
const HOST_SLIPPED := "user://test_online_lag_host_slipped.txt"
const CLIENT_SLIPPED := "user://test_online_lag_client_slipped.txt"
## How long a machine stands still, ms: about what a window going out of sight
## costs on a Mac (some 30 physics frames never run).
const STAND_STILL_MS := 700
## The client gives up well before the host does.
const CLIENT_TIME_LIMIT := 130.0

## The client's line jitters by up to this many ms each way, too.
@export var jitter_ms := 0
## Frames a second, as a window's display paces them (0: as fast as they go,
## headless): the host's, and the client's ("--max-fps").
@export var host_fps := 0
@export var client_fps := 0

var _fail := 0
var _lines: PackedStringArray = []
var _is_client := false
var _port := 0
var _client_pid := -1
var _done := false
## A node whose place is noted every frame once everything else has run its
## frame (_process, last in line): [where it is, when (usec)] each.
var _watched: Node2D = null
var _watch: Array = []
## The host's copy of the client's tank, its playback looked at every physics
## frame just after it has run (_physics_process, last in line): the furthest
## behind the client's newest report it has played, in frames.
var _copy_watched: PlayerTank = null
var _behind_most := 0.0
## Client: while watching its own shots, every ghost number seen, and each
## host shell for one: nid -> [its number, how far it jumped from the ghost
## (px), whether it flies on the ghost's own line, how far it flies a frame].
var _shots_world: NetClientWorld = null
var _ghosts_seen := {}
var _shells_seen := {}


func check(cond: bool, msg: String) -> void:
	var line := ("  PASS: " if cond else "  FAIL: ") + msg
	if _is_client:
		_lines.append(line)  # online_lag_test prints them, in its report
	else:
		print(line)
	if not cond:
		_fail += 1


func _ready() -> void:
	process_priority = 1000
	process_physics_priority = 1000
	# The scene changes the test drives would free this node as the current scene.
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	(func() -> void: get_tree().current_scene = stand_in).call_deferred()
	for arg in OS.get_cmdline_user_args():
		if arg == "--online-lag-client":
			_is_client = true
		elif arg.begins_with("--online-test-port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--max-fps="):
			Engine.max_fps = int(arg.get_slice("=", 1))
	if not _is_client:
		Engine.max_fps = host_fps
	if _is_client:
		get_tree().create_timer(CLIENT_TIME_LIMIT).timeout.connect(_finish_client)
		_run_client.call_deferred()
	else:
		_run_host.call_deferred()


func _process(_delta: float) -> void:
	if _watched != null and is_instance_valid(_watched) and _watched.visible:
		_watch.append([_watched.global_position, Time.get_ticks_usec()])
	if _shots_world != null:
		for ghost: Dictionary in _shots_world._ghosts:
			if is_instance_valid(ghost["node"]):
				_ghosts_seen[int(ghost["node"].net_shot)] = true
		for nid: int in _shots_world._own_shells:
			var shell := _shots_world.node_for(nid) as Bullet
			var info: Dictionary = _shots_world._own_shells[nid]
			if shell and not _shells_seen.has(nid):
				_shells_seen[nid] = [shell.net_shot, (info.get("offset", Vector2.INF) as Vector2).length(), info.has("born"),
						shell.speed / Engine.physics_ticks_per_second]


func _physics_process(_delta: float) -> void:
	if _copy_watched != null and is_instance_valid(_copy_watched) and _copy_watched._play_seen == Engine.get_physics_frames():
		_behind_most = maxf(_behind_most, PlayerInput.remote_report_frame(_copy_watched.player_id) - _copy_watched._play_at)


func _wait(cond: Callable, limit: float) -> bool:
	var waited := 0.0
	while not cond.call() and waited < limit:
		await get_tree().create_timer(0.05, true).timeout
		waited += 0.05
	return cond.call()


func _scene_is(path: String) -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == path


## A fire press as a key's comes: at the start of a frame.
func _tap(action: String) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	await get_tree().create_timer(0.15).timeout
	Input.action_release(action)
	await get_tree().create_timer(0.1).timeout


func _tanks(pid: int) -> Array:
	var out: Array = []
	for tank in get_tree().get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == pid and not tank.is_queued_for_deletion():
			out.append(tank)
	return out


func _tank(pid: int) -> PlayerTank:
	var tanks := _tanks(pid)
	return tanks[0] if tanks.size() == 1 else null


func _remove_files() -> void:
	for path in [CLIENT_RESULTS, DRIVEN, CORRECTED, SLIPPING, HOST_SLIPPED, CLIENT_SLIPPED]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# =====================================================================
# The host
# =====================================================================

func _run_host() -> void:
	var tree := get_tree()
	await tree.process_frame
	_remove_files()
	_port = 41000 + randi() % 8000
	GameManager.set_map_pool("v1_2_2")  # the built-in map set: the client has it too
	GameManager.start_game()
	check(await _wait(func() -> bool: return _scene_is("res://scenes/join_screen.tscn"), 5.0), "NEW GAME: the join screen")
	await _tap("p1_shoot")
	await tree.create_timer(0.5).timeout
	await _tap("p1_shoot")
	check(await _wait(func() -> bool: return _scene_is("res://scenes/game.tscn"), 5.0), "fire again: a game")
	check(await _wait(func() -> bool: return tree.current_scene.get_phase() == "play", 12.0), "in play")
	var game := tree.current_scene
	# No enemies, and open ground over the base's right-hand side for the client.
	game.get_node("EnemySpawner").spawn_timer.stop()
	_clear_enemies()
	var lm: LevelManager = game.level_manager
	for tile: Vector2i in lm._fg_tile_data.keys():
		if tile.x >= 21 and tile.x <= 36 and tile.y >= 14:
			lm._remove_fg_tile(tile)
			lm._brick_damage.erase(tile)
			lm._hard_brick_hp.erase(tile)
	for tile: Vector2i in lm._bg_tile_data.keys():
		if tile.x >= 21 and tile.x <= 36 and tile.y >= 14:
			lm._remove_bg_tile(tile)
	InputSettings.save_host_settings(_port, "", 3)
	InputSettings.save_host_port_type(Net.TRANSPORT_NAMES[Net.Transport.TCP])
	var menu = game.pause_menu
	menu._toggle_hosting()
	check(Net.is_host() and Net.port == _port, "open to others on %d" % _port)

	_client_pid = OS.create_process(OS.get_executable_path(), PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"), SCENE,
			"--", "--test-profile=online_lag_client", "--online-lag-client", "--online-test-port=%d" % _port,
			"--net-lag-ms=%d" % LAG_MS, "--net-jitter-ms=%d" % jitter_ms, "--max-fps=%d" % client_fps]))
	check(_client_pid > 0, "a client started, %d ms from here each way" % LAG_MS)
	check(await _wait(func() -> bool: return Net.client_ids().size() == 1, 40.0), "it joined")
	check(await _wait(func() -> bool: return PlayerInput.seats[1] != PlayerInput.NO_SEAT, 30.0), "and took tank 2")
	check(await _wait(func() -> bool: return _tank(1) != null and not _tank(1).is_materializing, 10.0), "its tank is out")
	var client: int = Net.client_ids()[0] if not Net.client_ids().is_empty() else 0
	var copy := _tank(1)
	if copy == null:
		await _finish_host()
		return
	copy.is_invincible = true
	copy.invincible_timer = 999.0
	_clear_enemies()  # any that were on their way in
	var start := copy.global_position
	var override := copy.net_override
	# Its drive, frame by frame here: the copy should move every frame at the
	# tank's speed, as the client's tank did, not by fits and starts.
	var steps: Array[float] = []
	var last := copy.global_position
	var still := 0
	for i in 60 * 20:
		await tree.physics_frame
		var step := copy.global_position.distance_to(last)
		last = copy.global_position
		if step > 0.0 or not steps.is_empty():
			steps.append(step)
		still = still + 1 if step == 0.0 else 0
		if not steps.is_empty() and still > 20:
			break  # stood a third of a second: that drive is over
	check(start.distance_to(copy.global_position) > 40.0, "the client drives it, and the copy here follows")
	while not steps.is_empty() and steps[-1] == 0.0:
		steps.pop_back()
	var stride := copy.move_speed * get_physics_process_delta_time()
	var stalls := steps.filter(func(step: float) -> bool: return step < stride * 0.5).size()
	var lurches := steps.filter(func(step: float) -> bool: return step > stride * 1.6).size()
	check(stalls <= 4 and lurches <= 3,
		"the copy here moves as smoothly as the client drives: %d of %d frames stalled, %d lurched (a turn's snap is one)" % [
			stalls, steps.size(), lurches])
	check(await _wait(func() -> bool: return FileAccess.file_exists(DRIVEN), 30.0), "the client drove and fired")
	check(copy.net_override == override, "never once held up in open ground: no corrections")
	var ping := Net.peer_ping(client)
	check(ping >= 2 * LAG_MS and ping < 2 * LAG_MS + 80 + 2 * jitter_ms, "the client's ping: %d ms" % ping)
	var line: String = menu._player_line(client)
	check(line == "LAGGY   ·   DRIVING P2   ·   %d ms" % ping, "and my list of players says so: %s" % line)

	# A correction: the copy put elsewhere, as if blocked; the client is told.
	var put := copy.global_position + Vector2(-48, 0)
	copy.global_position = put
	copy._correct_client()
	var file := FileAccess.open(CORRECTED, FileAccess.WRITE)
	file.store_string(var_to_str(put))
	file.close()
	check(await _wait(func() -> bool: return copy.global_position.distance_to(put) > 20.0, 15.0),
		"the client took the correction and drives on: followed again")

	# The client turns LAG COMPENSATION off, and on again.
	check(await _wait(func() -> bool: return not PlayerInput.remote_predicts(1), 20.0), "the client turns lag compensation off")
	var by_keys := copy.global_position
	check(await _wait(func() -> bool: return copy.global_position.distance_to(by_keys) > 20.0, 10.0),
		"its keys drive the copy here as they come, as before")
	var before_on := copy.net_override
	check(await _wait(func() -> bool: return PlayerInput.remote_predicts(1), 20.0), "and turns it on again")
	check(await _wait(func() -> bool: return copy.net_override != before_on, 5.0),
		"a correction first: its keys moved the copy here meanwhile")

	# Either machine stands still a while (its window going fullscreen or out
	# of sight, a stage loading): the physics frames it missed never run, so its
	# frames slip against the other's for good. The client drives up and down
	# meanwhile, a second each way; the copy here keeps up all the same.
	check(await _wait(func() -> bool: return FileAccess.file_exists(SLIPPING), 30.0), "the client drives up and down without a break")
	await tree.create_timer(1.0).timeout
	override = copy.net_override
	var before: Array[int] = await _evenness(copy, 2.0)
	_behind_most = 0.0
	_copy_watched = copy
	for i in 4:
		await tree.create_timer(1.2).timeout
		OS.delay_msec(STAND_STILL_MS)
	await tree.create_timer(0.3).timeout
	_copy_watched = null
	check(_behind_most > 10.0 and _behind_most <= PlayerTank.PLAY_BEHIND_MAX + 0.001,
		"I stood still four times, %d ms each: my copy never played more than %.1f frames behind the client's newest word" % [
			STAND_STILL_MS, _behind_most])
	await tree.create_timer(1.7).timeout
	var after: Array[int] = await _evenness(copy, 2.0)
	check(after[0] <= before[0] + 2 and after[1] <= before[1] + 2,
		"and two seconds on it goes as smoothly as before: %d frames stalled and %d lurched in two seconds, %d and %d before" % [
			after[0], after[1], before[0], before[1]])
	var said := FileAccess.open(HOST_SLIPPED, FileAccess.WRITE)
	said.store_string("slipped")
	said.close()
	check(await _wait(func() -> bool: return FileAccess.file_exists(CLIENT_SLIPPED), 20.0), "the client stood still %d ms" % STAND_STILL_MS)
	await tree.create_timer(1.0).timeout
	after = await _evenness(copy, 2.0)
	var behind := PlayerInput.remote_report_frame(1) - copy._play_at
	check(after[0] <= before[0] + 2 and after[1] <= before[1] + 2 and behind > 0.5 and behind < PlayerTank.PLAY_DELAY_MAX,
		"a second on, my copy goes as smoothly as before: %d frames stalled and %d lurched in two seconds, playing %.1f frames behind" % [
			after[0], after[1], behind])
	check(copy.net_override == override, "no corrections through any of it")

	await _finish_host()


## How evenly [param copy] goes for [param seconds]: how many frames it stood
## (less than half a frame's way) and how many it lurched (over 1.6 frames' way).
func _evenness(copy: PlayerTank, seconds: float) -> Array[int]:
	var stride := copy.move_speed * get_physics_process_delta_time()
	var stalls := 0
	var lurches := 0
	var last := copy.global_position
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		var step := copy.global_position.distance_to(last)
		last = copy.global_position
		if step < stride * 0.5:
			stalls += 1
		elif step > stride * 1.6:
			lurches += 1
	return [stalls, lurches]


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()


func _finish_host() -> void:
	if _client_pid > 0:
		await _wait(func() -> bool: return not OS.is_process_running(_client_pid), 40.0)
		if OS.is_process_running(_client_pid):
			OS.kill(_client_pid)
	print("-- the client's side")
	if not FileAccess.file_exists(CLIENT_RESULTS):
		check(false, "the client wrote its results")
	else:
		for result in FileAccess.get_file_as_string(CLIENT_RESULTS).split("\n"):
			print(result)
			if result.begins_with("  FAIL:"):
				_fail += 1
	_remove_files()
	Net.leave()
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	get_tree().quit(_fail)


# =====================================================================
# The client
# =====================================================================

func _world() -> NetClientWorld:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("NetClientWorld") as NetClientWorld if scene else null


## Where the host has [param tank], as this machine last heard.
func _host_has(tank: PlayerTank) -> Vector2:
	var world := _world()
	if world == null:
		return Vector2.INF
	for nid: int in world._nodes:
		if world._nodes[nid] == tank:
			return Vector2(world._states[nid][0], world._states[nid][1])
	return Vector2.INF


## Drives the way [param action] says for [param seconds], from the very frame
## the last way's key goes up: no frame without one.
func _drive_on(action: String, seconds: float) -> void:
	for way: String in ["p1_up", "p1_down", "p1_left", "p1_right"]:
		if way != action:
			Input.action_release(way)
	Input.action_press(action)
	await get_tree().create_timer(seconds).timeout


## Holds [param action] for [param seconds].
func _drive(action: String, seconds: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(seconds).timeout
	Input.action_release(action)


func _run_client() -> void:
	var tree := get_tree()
	await tree.process_frame
	check(Net.sim_lag_ms == LAG_MS, "my line to the host is %d ms long each way" % Net.sim_lag_ms)
	check(Net.join("127.0.0.1", _port, "Laggy") == OK, "joining")
	check(await _wait(func() -> bool: return _world() != null and _world().is_started(), 30.0), "joined: the host's game shows")
	await _tap("p1_shoot")
	check(await _wait(func() -> bool: return Net.is_my_seat(1), 10.0), "my fire takes tank 2")
	check(await _wait(func() -> bool: return _tank(1) != null and _tank(1).is_net_driving(), 15.0),
		"its tank is out, and drives here")
	var tank := _tank(1)
	if tank == null:
		_finish_client()
		return
	check(await _wait(func() -> bool: return Net._ping_samples.size() >= 2, 6.0), "timed the trip to the host and back")
	check(Net.ping_ms >= 2 * LAG_MS and Net.ping_ms < 2 * LAG_MS + 80 + 2 * Net.sim_jitter_ms, "ping %.0f ms" % Net.ping_ms)
	var world := _world()
	var settled := 75.0 + 1.5 * Net.sim_jitter_ms
	check(await _wait(func() -> bool: return world.render_delay() < settled, 10.0),
		"AUTO smoothing settles as low as this line lets it: %.0f ms behind the host, aiming at %.0f" % [
			world.render_delay(), world._aimed_delay()])

	# The keys move the tank at once, however far the host is.
	var override := tank._override_seen
	var from := tank.global_position
	Input.action_press("p1_up")
	for i in 3:
		await tree.physics_frame
	var moved := from.distance_to(tank.global_position)
	check(moved >= 2.0, "it answers my keys at once: %.1f px in 3 frames, %d ms from the host" % [moved, 2 * LAG_MS])
	await tree.create_timer(0.4).timeout
	# On without a break for five seconds, turning and turning back, so the host
	# can see how evenly its copy goes.
	await _drive_on("p1_right", 0.5)
	await _drive_on("p1_up", 1.8)
	await _drive_on("p1_down", 1.5)
	await _drive_on("p1_up", 1.0)
	Input.action_release("p1_up")
	await tree.create_timer(0.8).timeout
	var host_has := _host_has(tank)
	check(host_has.distance_to(tank.global_position) < 0.5,
		"the host has it where I have it: %s, here %s" % [host_has, tank.global_position])
	check(tank._override_seen == override, "and never had to correct it")

	# My shot shows at once, out of my tank's barrel, and is heard once; the
	# host's shell takes over from it where it is.
	var direction := tank.current_direction
	var muzzle := tank.global_position + direction * (BaseTank.TANK_SIZE * 0.5)
	SoundManager._predicted.clear()
	await tree.process_frame
	Input.action_press("p1_shoot")
	var ghost: Bullet = null
	for i in 3:
		await tree.physics_frame
		if ghost == null and not world._ghosts.is_empty():
			ghost = world._ghosts[0]["node"]
	Input.action_release("p1_shoot")
	check(ghost != null and ghost.visible and ghost.global_position.distance_to(muzzle) <= ghost.speed * 3.0 / 60.0 + 1.0,
		"my shot shows within 3 frames, out of my tank's barrel, %d ms from the host" % (2 * LAG_MS))
	check(SoundManager._predicted.size() == 1, "and is heard at once")
	var last_ghost := Vector2.INF
	var real: Bullet = null
	var both := false
	for i in 600:  # frames
		await tree.process_frame
		var ghost_shown := is_instance_valid(ghost) and not ghost.is_queued_for_deletion() and ghost.visible
		for nid: int in world._own_shells:
			var node := world.node_for(nid) as Bullet
			if node and node.direction == direction and node.visible:
				real = node
		both = both or (ghost_shown and real != null)
		if real == null and ghost_shown:
			last_ghost = ghost.global_position
			continue
		break
	var jump := real.global_position.distance_to(last_ghost) if real else INF
	check(real != null and jump < 10.0,
		"the host's shell takes over from it where it was: %.1f px from the ghost's last place" % jump)
	check(not both, "one shot, one shell: never the ghost and the host's shell at once")
	# (Its place and the time, each frame, both taken once the world has moved
	# it that frame: a frame that runs long is no jump of the shell's.)
	var worst := INF
	if real:
		var shell_speed := real.speed
		_watch.clear()
		_watched = real
		for i in 30:
			await tree.process_frame
			if not is_instance_valid(real) or not real.visible:
				break
		_watched = null
		worst = 0.0
		for i in range(1, _watch.size()):
			var went: float = (_watch[i - 1][0] as Vector2).distance_to(_watch[i][0])
			worst = maxf(worst, absf(went - shell_speed * (int(_watch[i][1]) - int(_watch[i - 1][1])) / 1000000.0))
	check(worst < 4.0 and _watch.size() >= 10,
		"and flies on as smoothly as the ghost: at most %.1f px off its speed from frame to frame, %d frames" % [worst, _watch.size()])
	check(SoundManager._predicted.is_empty(), "and the host's sound of it is left out: heard once")
	await tree.create_timer(0.25).timeout
	if is_instance_valid(real) and real.visible:
		var lead := (real.global_position - _host_has_node(real)).dot(direction)
		check(lead > 0.8 * real.speed * (Net.ping_ms + world.render_delay()) / 1000.0,
			"drawn ahead of where the host's word of it has it, as my tank is: %.0f px" % lead)

	# Fired while driving, and at once after turning: the host fires each of
	# those very shots, from where this tank was, so each host shell takes over
	# its ghost by its number, on the ghost's own line, without a jump; no
	# ghost waits in vain, and no shell comes that wasn't fired here.
	var before := int(Net._shots[tank.net_slot][0])
	_ghosts_seen.clear()
	_shells_seen.clear()
	_shots_world = world
	await tree.create_timer(0.8).timeout  # (the cooldown after the last shot)
	for way: String in ["p1_up", "p1_left", "p1_down", "p1_right"]:
		_drive_on(way, 0.0)  # it turns, and drives on that way
		await tree.physics_frame
		Input.action_press("p1_shoot")
		await tree.physics_frame
		await tree.physics_frame
		Input.action_release("p1_shoot")
		await tree.create_timer(0.8).timeout  # (more than the cooldown)
	Input.action_release("p1_right")
	await tree.create_timer(1.0 + (Net.ping_ms + world.render_delay()) / 1000.0).timeout
	_shots_world = null
	for nid: int in _shells_seen.keys():
		if int(_shells_seen[nid][0]) <= before:
			_shells_seen.erase(nid)  # a shell of an earlier shot
	var numbers := _shells_seen.values().map(func(seen: Array) -> int: return seen[0])
	var fired := _ghosts_seen.keys()
	fired.sort()
	numbers.sort()
	# (The ghost goes a physics frame at a time, sometimes two in one go, the
	# shell on by the clock: they can be up to two frames' flight apart as it
	# takes over, eased out over HANDOFF_MS.)
	var jumps: Array = _shells_seen.values().map(func(seen: Array) -> float: return seen[1] / seen[3])
	var on_line := _shells_seen.values().all(func(seen: Array) -> bool: return seen[2])
	check(fired.size() == 4 and numbers == fired, "four shots fired driving and turning, and the host's shell for each: %s, %s" % [
		str(fired), str(numbers)])
	check(on_line and not jumps.is_empty() and jumps.max() <= 2.0,
		"each takes over its ghost on the ghost's own line, at most %.2f of a frame's flight from it" % (
			jumps.max() if not jumps.is_empty() else INF))
	check(world._ghosts.is_empty(), "no ghost left waiting")

	# The host corrects it: it goes where the host has it, and on from there.
	var file := FileAccess.open(DRIVEN, FileAccess.WRITE)
	file.store_string("driven")
	file.close()
	check(await _wait(func() -> bool: return tank._override_seen != override, 10.0), "a correction from the host comes")
	check(await _wait(func() -> bool: return FileAccess.file_exists(CORRECTED), 2.0), "with where it put my tank")
	var put: Variant = str_to_var(FileAccess.get_file_as_string(CORRECTED))
	check(put is Vector2 and tank.global_position.distance_to(put) < 0.5,
		"my tank is where the host put it: %s, here %s" % [put, tank.global_position])
	await _drive("p1_up", 0.3)
	await tree.create_timer(0.8).timeout
	host_has = _host_has(tank)
	check(put is Vector2 and tank.global_position.distance_to(put) > 20.0 and host_has.distance_to(tank.global_position) < 0.5,
		"I drive on from there, and the host follows: %s, here %s" % [host_has, tank.global_position])

	# LAG COMPENSATION off: the host's game as it is, my keys a trip late.
	InputSettings.set_lag_compensation(false)
	await tree.create_timer(0.5).timeout
	check(not tank.net_predicted and _host_has(tank).distance_to(tank.global_position) < 0.5,
		"LAG COMPENSATION off: my tank shows where the host has it")
	var from_off := tank.global_position
	await tree.process_frame
	Input.action_press("p1_up")
	for i in 3:
		await tree.physics_frame
	var early := from_off.distance_to(tank.global_position)
	await tree.create_timer(0.6).timeout
	Input.action_release("p1_up")
	var later := from_off.distance_to(tank.global_position)
	check(early < 0.5 and later > 20.0,
		"my keys move it once the host has: %.1f px in 3 frames, %.0f px later" % [early, later])
	await tree.create_timer(0.5).timeout
	var seen := tank._override_seen
	InputSettings.set_lag_compensation(true)
	check(await _wait(func() -> bool: return tank._override_seen != seen, 5.0),
		"on again: the host corrects it first, its keys having moved it there")
	await tree.create_timer(0.3).timeout
	var from_on := tank.global_position
	await tree.process_frame
	Input.action_press("p1_up")
	for i in 3:
		await tree.physics_frame
	Input.action_release("p1_up")
	check(from_on.distance_to(tank.global_position) >= 2.0, "and it answers my keys at once again")

	# Either machine stands still a while: up and down without a break
	# meanwhile, a second each way. The host first (it says when it has), then
	# this one, and on for five seconds more.
	await tree.create_timer(0.5).timeout
	seen = tank._override_seen
	var driving := FileAccess.open(SLIPPING, FileAccess.WRITE)
	driving.store_string("driving")
	driving.close()
	var legs_since := -1
	for leg in 45:
		await _drive_on("p1_down" if leg % 2 == 0 else "p1_up", 1.0)
		if legs_since >= 0:
			legs_since += 1
			if legs_since >= 5:
				break
		elif FileAccess.file_exists(HOST_SLIPPED):
			OS.delay_msec(STAND_STILL_MS)
			var stood := FileAccess.open(CLIENT_SLIPPED, FileAccess.WRITE)
			stood.store_string("slipped")
			stood.close()
			legs_since = 0
	Input.action_release("p1_down")
	Input.action_release("p1_up")
	check(legs_since >= 5, "up and down while the host stood still, then I did (%d ms), and on" % STAND_STILL_MS)
	await tree.create_timer(0.8).timeout
	host_has = _host_has(tank)
	check(host_has.distance_to(tank.global_position) < 0.5 and tank._override_seen == seen,
		"the host has my tank where I have it after all that, never corrected: %s, here %s" % [host_has, tank.global_position])
	_done = true
	_finish_client()


## Where the host has [param node], as this machine last heard.
func _host_has_node(node: Node) -> Vector2:
	var world := _world()
	for nid: int in world._nodes:
		if world._nodes[nid] == node:
			return Vector2(world._states[nid][0], world._states[nid][1])
	return Vector2.INF


func _finish_client() -> void:
	if not _lines.is_empty() and _lines[-1].begins_with("===="):
		return  # already written
	if not _done:
		check(false, "finished in time (%d s)" % CLIENT_TIME_LIMIT)
	_lines.append("==== CLIENT %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	var file := FileAccess.open(CLIENT_RESULTS, FileAccess.WRITE)
	file.store_string("\n".join(_lines))
	file.close()
	Net.leave()
	get_tree().quit(_fail)
