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
## drive the host's tank as they come, as before, until it's on again.
##
## The client's checks come back in its results file and count here. The parts
## on their own are net_follow_test's.
## Run as an override main scene:
##   Godot --headless res://scenes/test/online_lag_test.tscn

const SCENE := "res://scenes/test/online_lag_test.tscn"
## The client's line to the host, each way.
const LAG_MS := 75
const CLIENT_RESULTS := "user://test_online_lag_client.txt"
## The client has driven and fired: the host's turn to correct it.
const DRIVEN := "user://test_online_lag_driven.txt"
## The host corrected the client's tank: where it put it.
const CORRECTED := "user://test_online_lag_corrected.txt"
## The client gives up well before the host does.
const CLIENT_TIME_LIMIT := 100.0

var _fail := 0
var _lines: PackedStringArray = []
var _is_client := false
var _port := 0
var _client_pid := -1
var _done := false


func check(cond: bool, msg: String) -> void:
	var line := ("  PASS: " if cond else "  FAIL: ") + msg
	if _is_client:
		_lines.append(line)  # online_lag_test prints them, in its report
	else:
		print(line)
	if not cond:
		_fail += 1


func _ready() -> void:
	# The scene changes the test drives would free this node as the current scene.
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	(func() -> void: get_tree().current_scene = stand_in).call_deferred()
	for arg in OS.get_cmdline_user_args():
		if arg == "--online-lag-client":
			_is_client = true
		elif arg.begins_with("--online-test-port="):
			_port = int(arg.get_slice("=", 1))
	if _is_client:
		get_tree().create_timer(CLIENT_TIME_LIMIT).timeout.connect(_finish_client)
		_run_client.call_deferred()
	else:
		_run_host.call_deferred()


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
	for path in [CLIENT_RESULTS, DRIVEN, CORRECTED]:
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
			"--net-lag-ms=%d" % LAG_MS]))
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
	check(await _wait(func() -> bool: return copy.global_position.distance_to(start) > 40.0, 20.0),
		"the client drives it, and the copy here follows")
	check(await _wait(func() -> bool: return FileAccess.file_exists(DRIVEN), 30.0), "the client drove and fired")
	check(copy.net_override == override, "never once held up in open ground: no corrections")
	var ping := Net.peer_ping(client)
	check(ping >= 2 * LAG_MS and ping < 2 * LAG_MS + 80, "the client's ping: %d ms" % ping)
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

	await _finish_host()


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
	check(Net.ping_ms >= 2 * LAG_MS and Net.ping_ms < 2 * LAG_MS + 80, "ping %.0f ms" % Net.ping_ms)
	var world := _world()
	check(await _wait(func() -> bool: return world.render_delay() < 75.0, 10.0),
		"AUTO smoothing settles low on this steady line: %.0f ms behind the host, aiming at %.0f" % [
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
	Input.action_release("p1_up")
	await _drive("p1_right", 0.5)
	await _drive("p1_up", 0.3)
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
	var worst := INF
	if real:
		worst = 0.0
		var prev := real.global_position
		var prev_t := Time.get_ticks_usec()
		for i in 30:
			await tree.process_frame
			if not is_instance_valid(real) or not real.visible:
				break
			var t := Time.get_ticks_usec()
			worst = maxf(worst, absf(prev.distance_to(real.global_position) - real.speed * (t - prev_t) / 1000000.0))
			prev = real.global_position
			prev_t = t
	check(worst < 4.0, "and flies on as smoothly as the ghost: at most %.1f px off its speed from frame to frame" % worst)
	check(SoundManager._predicted.is_empty(), "and the host's sound of it is left out: heard once")
	await tree.create_timer(0.25).timeout
	if is_instance_valid(real) and real.visible:
		var lead := (real.global_position - _host_has_node(real)).dot(direction)
		check(lead > 0.8 * real.speed * (Net.ping_ms + world.render_delay()) / 1000.0,
			"drawn ahead of where the host's word of it has it, as my tank is: %.0f px" % lead)

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
