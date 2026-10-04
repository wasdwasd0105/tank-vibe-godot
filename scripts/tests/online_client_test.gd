extends Node
## The client half of online_test (which starts it as a second process): joins
## the host's game from the ONLINE BATTLE screen (a wrong password first, put
## right with EDIT) and checks what a player on a client sees. Writes its checks
## to RESULTS, which online_test prints and counts. Not run on its own.

const RESULTS := "user://test_online_client.txt"
const HOST_DUMP := "user://test_online_world.txt"
const VERDICT := "user://test_online_client_compared.txt"
## Gives up well before online_test does.
const TIME_LIMIT := 200.0
## The game's password (online_test's).
const PASSWORD := "Tank 1.22"
const ONLINE_SCENE := "res://scenes/online_screen.tscn"
## The host's own map set (online_test's HOST_MAP), which this computer lacks.
const HOST_MAP := "Online_Test_Map"
## The map set of the host's next game, which this client turns down.
const HOST_MAP_B := "Online_Test_Map_B"

var _fail := 0
var _lines: PackedStringArray = []
var _port := 0
## The transport the host takes ("TCP" or "UDP"), for checking this machine found it.
var _transport := ""
var _done := false
## Rumbles this machine's controllers got, as [slot, strong motor].
var _rumbles: Array = []
## The stage screens seen, by StageOverlay.Mode.
var _screens := {}


## Kept for RESULTS, not printed: online_test's output is this process's too,
## and it prints them once, in its report.
func check(cond: bool, msg: String) -> void:
	var line := ("  PASS: " if cond else "  FAIL: ") + msg
	_lines.append(line)
	if not cond:
		_fail += 1


func _ready() -> void:
	# The scene changes the test drives would free this node as the current scene.
	var stand_in := Node.new()
	get_tree().root.add_child.call_deferred(stand_in)
	(func() -> void: get_tree().current_scene = stand_in).call_deferred()
	InputSettings.rumbled.connect(func(slot: int, _weak: float, strong: float, _duration: float) -> void:
		_rumbles.append([slot, strong]))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online-test-port="):
			_port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--online-test-transport="):
			_transport = arg.get_slice("=", 1)
	get_tree().create_timer(TIME_LIMIT).timeout.connect(_finish)
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


## What a row of the ONLINE BATTLE list shows, its labels in order.
func _row_labels(screen: Node, index: int) -> Array:
	var out: Array = []
	var pending: Array = [MenuRows.layout_of(screen._rows[index])]
	while not pending.is_empty():
		var node: Node = pending.pop_front()
		if node is Label:
			out.append(node.text)
		pending = node.get_children() + pending
	return out


## Empties this process's maps folder: it starts without the host's map set.
func _clear_maps(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	LevelData.scan_map_pools()


func _world() -> NetClientWorld:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("NetClientWorld") as NetClientWorld if scene else null


func _tanks(pid: int) -> Array:
	var out: Array = []
	for tank in get_tree().get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == pid and not tank.is_queued_for_deletion():
			out.append(tank)
	return out


static func _same(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return absf(float(a) - float(b)) < 0.01
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	return a == b


func _run() -> void:
	await get_tree().process_frame
	check(_port > 0, "given the host's port (%d)" % _port)
	var tree := get_tree()
	var map_dir := LevelData.user_map_dir()
	check(map_dir == "user://test_maps_online_client/", "maps of my own, apart from the host's: %s" % map_dir)
	_clear_maps(map_dir)
	var progress: Array = []
	Net.map_progress.connect(func(received: int, _total: int) -> void: progress.append(received))
	var downloads: Array = []
	Net.map_download_finished.connect(func(name: String, error: String) -> void: downloads.append([name, error]))
	tree.change_scene_to_file(ONLINE_SCENE)
	await _wait(func() -> bool: return _scene_is(ONLINE_SCENE), 5.0)
	await tree.process_frame
	var screen := tree.current_scene
	check(screen._connections.is_empty(), "ONLINE BATTLE: no connections yet")
	screen._create_button.pressed.emit()
	screen._field(screen._name_row).text = "Clienta"
	screen._field(screen._address_row).text = "127.0.0.1:%d" % _port
	screen._field(screen._password_row).text = PASSWORD.to_lower()
	screen._submit_button.pressed.emit()
	check(screen._hint.text == "Connecting to 127.0.0.1 : %d ..." % _port, "CREATE, then JOIN: %s" % screen._hint.text)
	check(await _wait(func() -> bool: return not screen._busy(), 15.0) and screen._hint.text == "Wrong password.",
			"a wrong password: turned away, and told so: %s" % screen._hint.text)
	check(screen._connections.size() == 1 and screen._connections[0]["joined"] == "" and _scene_is(ONLINE_SCENE),
			"the connection is kept anyway, never joined")
	screen._more_buttons[0].pressed.emit()
	screen._popup_buttons[1].pressed.emit()  # EDIT
	check(screen._form_layer.visible and screen._field(screen._password_row).text == PASSWORD.to_lower(),
			"EDIT: the window, with the password given")
	screen._field(screen._password_row).text = PASSWORD
	screen._submit_button.pressed.emit()  # SAVE
	check(not screen._form_layer.visible and screen._connections[0]["password"] == PASSWORD and not Net.is_online(),
			"SAVE puts it right, without joining")
	screen._rows[0].pressed.emit()
	check(screen._hint.text == "Connecting to 127.0.0.1 : %d ..." % _port, "a click on the connection joins: %s" % screen._hint.text)

	# --- The host's running stage ---
	check(await _wait(func() -> bool: return _scene_is("res://scenes/game.tscn"), 20.0), "joined: straight into the host's stage")
	check(Net.TRANSPORT_NAMES[Net.transport] == _transport, "over %s, found out by itself" % Net.TRANSPORT_NAMES[Net.transport])

	# --- The host's map set: this computer lacks it, so it's offered ---
	check(await _wait(func() -> bool: return tree.root.get_node_or_null("NetMapPrompt") != null, 10.0),
		"the host's map set isn't here: I'm asked")
	var prompt = tree.root.get_node_or_null("NetMapPrompt")
	var asked := ""
	if prompt:
		asked = prompt._text.text
		check(asked.contains(HOST_MAP) and asked.contains("381 KB") and Net.map_prompt_open, "about it: %s" % asked)
		prompt._download_button.pressed.emit()
	check(await _wait(func() -> bool: return not downloads.is_empty(), 15.0) and downloads[0] == [HOST_MAP, ""],
		"DOWNLOAD: it came, and was kept as %s" % str(downloads))
	check(progress.size() >= 10 and progress[-1] == 390000 and progress == progress.duplicate().slice(0, progress.size()),
		"in pieces, as far as it had got each time: %d pieces" % progress.size())
	var kept := LevelData.pool_with_hash(Net.host_map.get("hash", "-"))
	check(kept != null and kept.id == "user:" + HOST_MAP and kept.path == map_dir + HOST_MAP + ".dat",
		"with my maps now, the very same map: %s" % (kept.path if kept else "none"))
	check(await _wait(func() -> bool: return not Net.map_prompt_open and tree.root.get_node_or_null("NetMapPrompt") == null, 3.0),
		"the question gone, my players free")
	check(await _wait(func() -> bool: return _world() != null and _world().is_started(), 10.0), "showing it")
	check(tree.current_scene.get_phase() == "mirror", "running none of it")
	check(await _wait(func() -> bool: return _tanks(0).size() == 1, 12.0) and _tanks(1).is_empty(),
		"the host's tank is out; tank 2 waits for a driver")
	await _tap("p1_shoot")
	check(await _wait(func() -> bool: return Net.is_my_seat(1), 10.0), "my P1 fire takes tank 2, mid-stage")
	check(await _wait(func() -> bool: return _tanks(1).size() == 1 and not _tanks(1)[0].is_materializing, 12.0),
		"its tank drives out")
	var moved := 0.0
	if not _tanks(1).is_empty():  # (else the checks above failed; go on to the rest)
		var start: Vector2 = _tanks(1)[0].global_position
		for way: String in ["p1_up", "p1_left", "p1_right", "p1_down"]:
			Input.action_press(way)
			await tree.create_timer(0.8).timeout
			Input.action_release(way)
			await tree.create_timer(0.4).timeout
			if _tanks(1).is_empty():
				break
			moved = _tanks(1)[0].global_position.distance_to(start)
			if moved > 40.0:
				break
	check(moved > 40.0, "my P1 keys drive tank 2: moved %.0f px" % moved)
	check(await _wait(func() -> bool: return _rumbles.has([0, PlayerTank.KILL_RUMBLE[1]]), 20.0),
			"tank 2's rumble comes to my P1 controller: %s" % str(_rumbles))
	var played: Dictionary = _world().played
	check(played.get(NetWorld.EV_SOUND, 0) > 0 and played.get(NetWorld.EV_SPAWN_BURST, 0) > 0,
			"the host's sounds and effects play here: %s" % str(played))

	# --- The whole world, checked against the host's while it holds still ---
	var banner: Label = tree.current_scene._host_paused_banner
	check(await _wait(func() -> bool: return FileAccess.file_exists(HOST_DUMP), 40.0), "the host froze it and wrote it down")
	check(banner.visible and tree.paused, "PAUSED BY THE HOST, and the world here holds still too")
	await tree.create_timer(1.0, true).timeout
	_compare_world(str_to_var(FileAccess.get_file_as_string(HOST_DUMP)))
	var done := FileAccess.open(VERDICT, FileAccess.WRITE)
	done.store_string("done")
	done.close()
	check(await _wait(func() -> bool: return not banner.visible and not tree.paused, 10.0), "resumed")

	# --- The next stage ---
	var watching := func() -> bool:
		var overlay: StageOverlay = tree.current_scene.stage_overlay if tree.current_scene is Node2D else null
		if overlay and overlay.visible:
			_screens[overlay.get_screen()] = true
		return GameManager.current_stage == 2 and _screens.has("intro")
	check(await _wait(watching, 40.0), "stage 2 comes")
	check(_screens.has("mission") and _screens.has("results") and _screens.has("intro"),
			"through the host's stage screens: %s" % str(_screens.keys()))
	check(await _wait(func() -> bool: return _world().is_started() and _tanks(1).size() == 1, 15.0),
			"its world, my tank in it")

	# --- The host takes P2 away, then gives it back ---
	check(await _wait(func() -> bool: return not Net.is_my_seat(1), 30.0), "the host took P2 away from me")
	check(await _wait(func() -> bool: return _tanks(1).is_empty(), 3.0), "and its tank left the field")
	check(await _wait(func() -> bool: return Net.may_drive_peer(Net.my_id(), 1), 15.0), "allowed again")
	await _tap("p1_shoot")
	check(await _wait(func() -> bool: return Net.is_my_seat(1), 5.0), "my fire takes it back")
	check(await _wait(func() -> bool: return _tanks(1).size() == 1, 5.0), "its tank is out again")

	# --- The host's game over: its lobby, and another game ---
	check(await _wait(func() -> bool: return _scene_is("res://scenes/join_screen.tscn"), 30.0), "game over: the host's lobby")
	var lobby := tree.current_scene
	check(lobby.get_node("Subtitle").text == "HOSTED BY SEAN", "hosted by the host: %s" % lobby.get_node("Subtitle").text)
	check(await _wait(func() -> bool: return tree.root.get_node_or_null("NetMapPrompt") != null, 10.0),
		"the host's next game is on another map set I lack: asked about that one")
	var again = tree.root.get_node_or_null("NetMapPrompt")
	if again:
		check(again._text.text.contains(HOST_MAP_B), "about it: %s" % again._text.text)
		again._not_now_button.pressed.emit()
	check(await _wait(func() -> bool: return tree.root.get_node_or_null("NetMapPrompt") == null and not Net.map_prompt_open, 3.0)
		and downloads.size() == 1 and LevelData.find_pool("user:" + HOST_MAP_B) == null, "NOT NOW: nothing fetched, nothing kept")
	check(not lobby._start_button.visible, "no START on a client: the host starts")
	check(await _wait(func() -> bool: return bool(Net.lobby["active"][0]), 20.0), "the host took tank 1")
	check(lobby._driver_labels[0].text == "SEAN", "its card says who: %s" % lobby._driver_labels[0].text)
	check(Net.is_my_seat(1) and lobby._prompts[1].modulate.a == 1.0 and lobby._prompts[0].modulate.a == 0.0,
			"tank 2 is still mine: my prompt is on its card only")
	await _tap("p1_shoot")
	check(await _wait(func() -> bool: return lobby._status_labels[1].text == "READY", 5.0), "my P1 fire: READY")
	check(await _wait(func() -> bool: return _scene_is("res://scenes/game.tscn"), 20.0), "the host started: the game")
	check(await _wait(func() -> bool: return _world() != null and _world().is_started() and _tanks(1).size() == 1, 15.0),
			"my tank in it")

	# --- Kicked ---
	check(await _wait(func() -> bool: return _scene_is(ONLINE_SCENE), 25.0), "kicked: back on ONLINE BATTLE")
	await tree.process_frame
	var back := tree.current_scene
	check(back._hint.text == "The host removed you from the game.", "saying why: %s" % back._hint.text)
	var shown := _row_labels(back, 0)
	check(back._connections.size() == 1 and str(back._connections[0]["joined"]).begins_with(Time.get_date_string_from_system())
			and shown[-1].begins_with("JOINED " + Time.get_date_string_from_system()),
			"its connection says when it last got in: %s" % str(shown))
	check(not Net.is_online(), "offline again")
	_clear_maps(map_dir)
	_done = true
	_finish()


## Every entity the host dumped shows here, exactly as the host has it, and
## nothing else; the map and the HUD's numbers are the host's.
func _compare_world(dump: Dictionary) -> void:
	var world := _world()
	var host_entities: Dictionary = dump["entities"]
	var missing: Array = []
	var wrong: Array = []
	for nid: int in host_entities:
		if not world._states.has(nid):
			missing.append(nid)
		elif world._types[nid] != host_entities[nid][0] or not _same(world._states[nid], host_entities[nid][2]):
			wrong.append([nid, host_entities[nid][2], world._states[nid]])
	var extra: Array = []
	for nid: int in world._states:
		if not host_entities.has(nid):
			extra.append(nid)
	var kinds := {}
	for nid: int in host_entities:
		kinds[host_entities[nid][0]] = true
	check(kinds.size() >= 5, "a busy field: %d kinds of entity" % kinds.size())
	check(missing.is_empty(), "each of the host's %d entities shows here: missing %s" % [host_entities.size(), str(missing)])
	check(extra.is_empty(), "and nothing else: %s" % str(extra))
	check(wrong.is_empty(), "each exactly as the host has it: %s" % str(wrong.slice(0, 2)))
	# My own tank drives here, ahead of the host (lag compensation), and my own
	# shells are drawn ahead with it: standing still a while, it's where the
	# host has it all the same.
	var placed := true
	var own_placed := true
	var own := 0
	for nid: int in world._nodes:
		var state: Array = world._states[nid]
		var node := world._nodes[nid] as Node2D
		var off := node.global_position.distance_to(Vector2(state[0], state[1]))
		if node is PlayerTank and (node as PlayerTank).net_predicted:
			own += 1
			own_placed = own_placed and off < 0.5
		elif not world._own_shells.has(nid) and off > 0.01:
			placed = false
	check(placed, "and drawn where it is")
	check(own == 1 and own_placed, "my own tank too, standing still: driven here, followed there")
	var lm: LevelManager = get_tree().current_scene.get_node("Playfield")
	check(_same(lm.net_map(), dump["map"]), "the map is the host's, cell for cell")
	var host_game: Dictionary = dump["game"]
	for key: String in ["stage", "enemies", "lives", "scores", "hp", "ammo"]:
		check(_same(world._game.get(key), host_game.get(key)), "%s as the host's: %s" % [key, str(host_game.get(key))])


func _finish() -> void:
	if not _lines.is_empty() and _lines[-1].begins_with("===="):
		return  # already written
	if not _done:
		check(false, "finished in time (%d s)" % TIME_LIMIT)
	_lines.append("==== CLIENT %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	var file := FileAccess.open(RESULTS, FileAccess.WRITE)
	file.store_string("\n".join(_lines))
	file.close()
	Net.leave()
	get_tree().quit(_fail)
