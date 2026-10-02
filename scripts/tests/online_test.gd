extends Node
## Headless test for online play (docs/network_design.md). First the parts on
## their own: the snapshot encoding, names, seats and remote presses. Then a
## real session over one TCP port on this machine: this process hosts, and a
## second Godot process (online_client_test) joins as a player on a client.
##
## Together they go through:
## - an offline game opened to others from its pause menu (SETTINGS, ONLINE),
##   with a password;
## - the client's ONLINE BATTLE screen giving a wrong password and turned away,
##   EDIT putting it right, and a click on the connection joining the running stage;
## - the client taking tank 2 with its own P1 fire, mid-stage, and driving it;
## - newcomers turned away when the host locks the game or it's full;
## - a busy field frozen and compared, entity for entity, with what the client shows;
## - the next stage;
## - the host taking P2 away and giving it back;
## - game over: the lobby, each machine taking its tank again, another game;
## - a kick.
##
## The client's checks come back in its results file and count here.
## Run as an override main scene:
##   Godot --headless res://scenes/test/online_test.tscn

const CLIENT_SCENE := "res://scenes/test/online_client_test.tscn"
const CLIENT_RESULTS := "user://test_online_client.txt"
const HOST_DUMP := "user://test_online_world.txt"
const CLIENT_VERDICT := "user://test_online_client_compared.txt"
## The game's password (online_client_test knows it too).
const PASSWORD := "Tank 1.22"

var _fail := 0
var _port := 0
var _client_pid := -1


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	# The scene changes the test drives would free this node as the current scene.
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	(func() -> void: get_tree().current_scene = stand_in).call_deferred()
	_run.call_deferred()


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


func _run() -> void:
	await get_tree().process_frame
	for path in [CLIENT_RESULTS, HOST_DUMP, CLIENT_VERDICT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("-- the parts")
	_test_encoding()
	_test_names()
	_test_seats()
	await _test_remote_presses()
	await _test_port_in_use()
	print("-- a session")
	await _test_session()
	await _collect_client()
	for path in [CLIENT_RESULTS, HOST_DUMP, CLIENT_VERDICT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Net.leave()
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	get_tree().quit(_fail)


# =====================================================================
# The parts
# =====================================================================

func _test_encoding() -> void:
	var before := [100.0, 200.0, 2, 0, 0.0, -7]
	var after := [100.0, 216.5, 3, 5, 0.25, -300]
	var buf := StreamPeerBuffer.new()
	check(not NetWorld.put_update(buf, 7, before, before), "an unchanged state writes nothing")
	check(NetWorld.put_update(buf, 7, after, before), "a changed one writes its changes")
	var read := NetWorld.read_updates(buf.data_array, {7: before})
	check(read.has(7) and read[7].size() == 5 and not read[7].has(0), "only the changed values come back: %s" % str(read))
	var ok := true
	for i: int in read.get(7, {}):
		ok = ok and is_equal_approx(float(read[7][i]), float(after[i])) and typeof(read[7][i]) == typeof(before[i])
	check(ok, "each as it was, typed as the spawn said (negatives too)")
	var big := StreamPeerBuffer.new()
	NetWorld.put_zigzag(big, -123456789)
	NetWorld.put_varint(big, 1 << 40)
	big.seek(0)
	check(NetWorld.get_zigzag(big) == -123456789 and NetWorld.get_varint(big) == 1 << 40, "big numbers survive")
	check(NetWorld.read_updates(PackedByteArray([1, 0, 3, 9]), {}).is_empty(), "updates for an unknown entity are dropped")


func _test_names() -> void:
	check(Net.clean_name("  sean\t") == "SEAN", "names are trimmed and upper case")
	check(Net.clean_name("A Very Long Player Name") == "A VERY LONG PL", "and 14 letters at most")
	check(Net.clean_name("\u0001\u0002") == "", "control characters are dropped")


func _test_seats() -> void:
	PlayerInput.reset_to_local()
	check(PlayerInput.seats == [PlayerInput.LOCAL_P1, PlayerInput.LOCAL_P2], "offline: P1's controls drive tank 1, P2's tank 2")
	PlayerInput.reset_to_empty()
	var anyone := func(_key: int, _tank: int) -> bool: return true
	var p1_of_5 := PlayerInput.controller_key(5, 0)
	check(PlayerInput.free_seat_for(p1_of_5, anyone) == 0, "online: a P1 fire takes tank 1 when it's free")
	PlayerInput.set_seat(0, PlayerInput.LOCAL_P1)
	check(PlayerInput.free_seat_for(p1_of_5, anyone) == 1, "else tank 2: a lone player uses their own P1 controls")
	var only_p1 := func(_key: int, tank: int) -> bool: return tank == 0
	check(PlayerInput.free_seat_for(p1_of_5, only_p1) == PlayerInput.NO_SEAT, "never a tank they may not drive")
	PlayerInput.set_seat(1, p1_of_5)
	PlayerInput.set_seat(0, p1_of_5)
	check(PlayerInput.seats == [p1_of_5, PlayerInput.NO_SEAT], "one controller drives one tank at a time")
	PlayerInput.reset_to_local()


func _test_remote_presses() -> void:
	PlayerInput.reset_to_empty()
	PlayerInput.set_remote(9, 0, 3, [false, false], [4, 0])
	PlayerInput.set_seat(1, PlayerInput.controller_key(9, 0))
	await get_tree().physics_frame
	check(PlayerInput.move_direction(1) == Vector2.RIGHT, "a client's push drives its tank")
	check(not PlayerInput.is_just_pressed(1, 0), "presses before it was first heard don't count")
	# A tap so quick its press and release land between two frames.
	PlayerInput.set_remote(9, 0, -1, [false, false], [5, 0])
	await get_tree().physics_frame
	var presses := 0
	for i in 3:
		if PlayerInput.is_just_pressed(1, 0):
			presses += 1
		await get_tree().physics_frame
	check(presses == 1, "a quick tap counts once, however short (%d)" % presses)
	check(PlayerInput.remove_peer(9) == [1], "a client leaving frees its tank")
	PlayerInput.reset_to_local()


func _test_port_in_use() -> void:
	var blocker := TCPServer.new()
	var port := 40000 + randi() % 9000
	if blocker.listen(port) != OK:
		return
	check(Net.host(port, "SEAN") != OK and not Net.is_online(), "hosting on a port in use fails, and says so")
	blocker.stop()


# =====================================================================
# A session
# =====================================================================

func _test_session() -> void:
	var tree := get_tree()
	_port = 41000 + randi() % 8000
	# The host has played under a name in ONLINE BATTLE before: it goes by it.
	var used: Array[Dictionary] = [{"name": "SEAN", "address": "10.0.0.9", "password": "", "used": 1.0, "joined": ""}]
	InputSettings.save_online_connections(used)

	# --- An offline game, opened to others from its pause menu ---
	GameManager.start_game()
	check(await _wait(func() -> bool: return _scene_is("res://scenes/join_screen.tscn"), 5.0), "NEW GAME: the join screen")
	await _tap("p1_shoot")
	await tree.create_timer(0.5).timeout
	await _tap("p1_shoot")
	check(await _wait(func() -> bool: return _scene_is("res://scenes/game.tscn"), 5.0) and not Net.is_online(),
		"P1 in, fire again: an offline game")
	check(await _wait(func() -> bool: return tree.current_scene.get_phase() == "play", 12.0), "in play")
	var game := tree.current_scene
	var menu = game.pause_menu
	InputSettings.save_host_settings(_port, PASSWORD, 3)
	menu._toggle_hosting()  # SETTINGS, ONLINE: ALLOW REMOTE PLAYERS
	check(Net.is_host() and Net.port == _port and Net.has_password() and Net.max_clients == 3 and Net.local_name == "SEAN",
		"ALLOW REMOTE PLAYERS: open on %d, with a password, as SEAN" % _port)
	check(Net.host_screen == Net.SCREEN_GAME and game.has_node("NetHostWorld"), "the clients told: the game")
	check(PlayerInput.seats == [PlayerInput.LOCAL_P1, PlayerInput.NO_SEAT], "my tank stays mine; tank 2 is free")
	# A newcomer past its handshake whose connection hasn't opened yet: the world
	# waits for it (sent then, its whole world would be lost).
	Net.peers[99] = {"name": "SOON", "allow": [true, true]}
	for i in 4:
		await tree.physics_frame
	check(not game.get_node("NetHostWorld")._views.has(99), "a newcomer gets the world once its connection is open")
	Net.peers.erase(99)
	check(await _knock({"protocol": Net.PROTOCOL + 1, "name": "OLDER"}, PASSWORD) == Net.END_VERSION,
			"a client of another version is turned away, and told why")
	check(await _knock({"protocol": Net.PROTOCOL, "name": "   "}, PASSWORD) == Net.END_BAD_NAME, "so is one with no name")
	var challenges: Array = []
	check(await _knock({"protocol": Net.PROTOCOL, "name": "GUEST"}, "", challenges) == Net.END_NEED_PASSWORD,
			"one without the password: this game needs one")
	check(await _knock({"protocol": Net.PROTOCOL, "name": "GUEST"}, PASSWORD.to_lower(), challenges) == Net.END_WRONG_PASSWORD,
			"one with a wrong password (case counts): wrong password")
	check(challenges.size() == 2 and challenges[0].size() == Net.NONCE_SIZE and challenges[0] != challenges[1],
			"each was challenged afresh, so an answer overheard is no use later")
	check(await _wait(func() -> bool: return Net.client_ids().is_empty(), 3.0) and Net._knocking.is_empty(),
			"none of them got in, and none is left half in")
	_client_pid = OS.create_process(OS.get_executable_path(), PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"), CLIENT_SCENE,
			"--", "--test-profile=online_client", "--online-test-port=%d" % _port]))
	check(_client_pid > 0, "a client process started")
	check(await _wait(func() -> bool: return Net.client_ids().size() == 1, 40.0), "the client joined: %s" % str(Net.peers.values()))

	# --- The client in the running stage ---
	check(await _wait(func() -> bool: return PlayerInput.seats[1] != PlayerInput.NO_SEAT, 40.0),
		"the client takes tank 2 with its fire, mid-stage")
	check(PlayerInput.controller_slot(PlayerInput.seats[1]) == 0 and not PlayerInput.is_local(PlayerInput.seats[1]),
			"with its own P1 controls")
	check(GameManager.player_active[1] and GameManager.player_lives[1] == 3, "as a player joining mid-game, with fresh lives")
	check(await _wait(func() -> bool: return _tanks(1).size() == 1 and not _tanks(1)[0].is_materializing, 6.0),
		"its tank drives out")
	var start: Vector2 = _tanks(1)[0].global_position if not _tanks(1).is_empty() else Vector2.INF
	check(await _wait(func() -> bool: return _tanks(1).size() == 1 and _tanks(1)[0].global_position.distance_to(start) > 40.0, 20.0),
			"the client drives tank 2")
	PlayerTank.rumble_player(1, PlayerTank.KILL_RUMBLE)  # the client's pad should feel it
	check(menu._host_button.visible, "someone joined: HOST is on my pause menu")
	menu._toggle_hosting()
	check(Net.is_host() and Net.lock_new, "ALLOW REMOTE PLAYERS off, with a player here: still open to them, locked to newcomers")
	check(await _knock({"protocol": Net.PROTOCOL, "name": "LATE"}, PASSWORD) == Net.END_LOCKED, "so a newcomer is turned away")
	menu._toggle_hosting()
	menu._cycle_max_players(-2)
	check(Net.max_clients == 1 and not Net.lock_new, "on again, MAX PLAYERS 1")
	check(await _knock({"protocol": Net.PROTOCOL, "name": "FULL"}, PASSWORD) == Net.END_FULL, "the game is full")
	Net.set_password("")
	check(await _knock({"protocol": Net.PROTOCOL, "name": "FULL"}, "") == Net.END_FULL, "without a password too")
	Net.set_password(PASSWORD)
	menu._cycle_max_players(1)
	check(await _knock({"protocol": Net.PROTOCOL, "name": "LAST"}, PASSWORD, [], menu._cycle_max_players.bind(-1)) \
			== Net.END_FULL, "full by the time a newcomer answered its challenge: turned away all the same")
	menu._cycle_max_players(1)
	check(await _knock({"protocol": Net.PROTOCOL, "name": "LAST"}, PASSWORD, [], menu._toggle_hosting) == Net.END_LOCKED,
			"so is one the host locked out while it answered")
	menu._toggle_hosting()
	menu._cycle_max_players(1)
	check(Net.client_ids().size() == 1 and Net.max_clients == 3, "the player here stayed throughout")

	# --- A busy field, frozen, written down for the client to compare ---
	var lm: LevelManager = game.level_manager
	var cookie: Cookie = preload("res://scenes/powerups/powerup.tscn").instantiate()
	cookie.setup(CookieData.CookieType.SPEED_UP, 0.0)
	cookie.global_position = Vector2(480, 400)
	game.powerups_container.add_child(cookie)
	lm._spawn_mine(Vector2i(10, 12), 2, true, 0)
	lm._spawn_mine(Vector2i(28, 12), 3, false, -1)
	lm.ignite_fire_patch(Vector2i(20, 14), true, 0)
	lm.spawn_explosion_blast(Vector2(900, 500), 1, true)
	Input.action_press("p1_shoot")
	await tree.create_timer(1.0).timeout
	tree.paused = true
	Input.action_release("p1_shoot")
	await tree.create_timer(1.5, true).timeout
	var world: NetHostWorld = game.get_node("NetHostWorld")
	var dump := {"entities": world._gather(), "map": lm.net_map(), "game": world._game_state()}
	var file := FileAccess.open(HOST_DUMP, FileAccess.WRITE)
	file.store_string(var_to_str(dump))
	file.close()
	check(await _wait(func() -> bool: return FileAccess.file_exists(CLIENT_VERDICT), 20.0), "frozen: the client compared its world")
	tree.paused = false

	# --- The next stage ---
	await tree.create_timer(1.0).timeout
	game._start_mission(true)
	check(await _wait(func() -> bool: return GameManager.current_stage == 2 and tree.current_scene is Node2D \
			and tree.current_scene.has_method("get_phase") and tree.current_scene.get_phase() == "play", 40.0), "stage 2")
	check(await _wait(func() -> bool: return _tanks(0).size() == 1 and _tanks(1).size() == 1, 6.0), "both tanks out again")
	await tree.create_timer(1.5).timeout

	# --- P2 taken away, and given back ---
	var client: int = Net.client_ids()[0]
	GameManager.player_lives[1] = 2   # so a rejoin's fresh lives would show
	Net.set_allow(client, 1, false)
	check(PlayerInput.seats[1] == PlayerInput.NO_SEAT and GameManager.player_disabled[1],
			"no longer allowed P2: its seat is free and the tank sits out")
	check(await _wait(func() -> bool: return _tanks(1).is_empty(), 2.0), "the tank has left the field")
	await tree.create_timer(1.5).timeout
	Net.set_allow(client, 1, true)
	check(await _wait(func() -> bool: return PlayerInput.seats[1] != PlayerInput.NO_SEAT \
			and not GameManager.player_disabled[1], 15.0), "allowed again: the client took it back")
	check(GameManager.player_lives[1] == 2, "no rejoin: it was waiting for a driver, and kept its 2 lives")
	check(await _wait(func() -> bool: return _tanks(1).size() == 1, 3.0), "its tank is back out")
	await tree.create_timer(1.5).timeout

	# --- Game over: everyone to the lobby, and another game ---
	tree.current_scene._on_game_over_finished()
	check(await _wait(func() -> bool: return _scene_is("res://scenes/join_screen.tscn"), 5.0) and Net.is_host() \
			and Net.host_screen == Net.SCREEN_LOBBY, "game over: the online lobby, the client still here")
	check(tree.current_scene.get_node("Header").text == "ONLINE GAME", "the lobby is the online one")
	check(PlayerInput.seats[0] == PlayerInput.LOCAL_P1 and PlayerInput.seats[1] != PlayerInput.NO_SEAT,
		"each keeps their tank")
	await tree.create_timer(0.5).timeout
	await _tap("p1_shoot")
	check(GameManager.player_active[0], "my fire: in")
	check(await _wait(func() -> bool: return GameManager.player_active[1], 20.0), "the client's fire: in")
	check(await _wait(func() -> bool: return tree.current_scene._driver_labels[1].text == "CLIENTA", 2.0),
			"the card says who drives it")
	await tree.create_timer(0.8).timeout
	await _tap("p1_shoot")
	check(await _wait(func() -> bool: return _scene_is("res://scenes/game.tscn"), 5.0), "fire again: the game starts")
	check(await _wait(func() -> bool: return _tanks(0).size() == 1 and _tanks(1).size() == 1, 15.0), "both tanks out")
	await tree.create_timer(1.0).timeout

	# --- Kicked ---
	Net.kick(client)
	check(await _wait(func() -> bool: return Net.client_ids().is_empty(), 5.0), "kicked: gone from the session")
	check(await _wait(func() -> bool: return PlayerInput.seats[1] == PlayerInput.NO_SEAT \
			and GameManager.player_disabled[1], 3.0), "and its tank sits out")
	check(not tree.current_scene.pause_menu._host_button.visible, "nobody left: no HOST on the pause menu")


## Knocks on the game as a client saying [param hello] would, from this very
## process (a second SceneMultiplayer on a subtree of its own), answering a
## challenge with [param password] (none if empty), and returns the reason the
## host gives for turning it away ("" if it let it in, "?" for no answer). The
## challenges it got go into [param challenges]; [param before_answer] runs
## between a challenge and its answer.
func _knock(hello: Dictionary, password: String, challenges: Array = [], before_answer: Callable = Callable()) -> String:
	var home := Node.new()
	home.name = "Knocker"
	get_tree().root.add_child(home)
	var multiplayer_api := SceneMultiplayer.new()
	var answer := {"reason": "?"}
	multiplayer_api.auth_callback = func(peer: int, data: PackedByteArray) -> void:
		var reply: Variant = bytes_to_var(data)
		if reply is Dictionary and reply.has("challenge"):
			challenges.append(reply["challenge"])
			if before_answer.is_valid():
				before_answer.call()  # the host changes its mind while the newcomer answers
			var proof := PackedByteArray() if password.is_empty() else Net.password_proof(password, reply["challenge"])
			multiplayer_api.send_auth(peer, var_to_bytes({"proof": proof}))
		elif reply is Dictionary:
			answer["reason"] = "" if reply.get("ok", false) else str(reply.get("reason", "?"))
	multiplayer_api.peer_authenticating.connect(func(peer: int) -> void:
		multiplayer_api.send_auth(peer, var_to_bytes(hello)))
	get_tree().set_multiplayer(multiplayer_api, home.get_path())
	var peer := WebSocketMultiplayerPeer.new()
	peer.create_client("ws://127.0.0.1:%d" % _port)
	multiplayer_api.multiplayer_peer = peer
	await _wait(func() -> bool: return answer["reason"] != "?", 5.0)
	peer.close()
	get_tree().set_multiplayer(null, home.get_path())
	home.queue_free()
	await get_tree().create_timer(0.8, true).timeout  # the host lets the refused go
	return answer["reason"]


## The client's own checks, from its results file.
func _collect_client() -> void:
	if _client_pid > 0:
		await _wait(func() -> bool: return not OS.is_process_running(_client_pid), 30.0)
		if OS.is_process_running(_client_pid):
			OS.kill(_client_pid)
	print("-- the client's side")
	if not FileAccess.file_exists(CLIENT_RESULTS):
		check(false, "the client wrote its results")
		return
	for line in FileAccess.get_file_as_string(CLIENT_RESULTS).split("\n"):
		print(line)
		if line.begins_with("  FAIL:"):
			_fail += 1
