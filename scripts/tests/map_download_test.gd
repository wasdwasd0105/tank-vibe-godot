extends Node
## Headless test for fetching an online host's map set: a map set is known by
## the SHA-256 of its file, whatever it's called; one that came from a host is
## saved with the imported maps under the host's name (name_2 beside another
## map of that name); a client is asked about a host's map set it doesn't
## have, once a session, never about one it has or about nonsense; and the
## question itself (DOWNLOAD / NOT NOW, by keys and mouse, keeping the keys from
## the screen under it, then how far a download has got). The transfer itself
## is online_test's. A test run keeps its own maps folder.
## Run as an override main scene:
##   Godot --headless res://scenes/test/map_download_test.tscn

const SAVED_NAMES: Array[String] = ["Desert_Fort", "Desert_Fort_2", "Offered_Map", "Piece_Map"]

var _fail := 0
## Keys that got past the question to the screen under it.
var _leaked: Array = []


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run.call_deferred()


## Records the keys that reach it: it stands for the screen under the question.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_leaked.append(event.keycode)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _prompt() -> NetMapPrompt:
	return get_tree().root.get_node_or_null("NetMapPrompt") as NetMapPrompt


## Removes every map this test may have saved, by any name it could get.
func _remove_saved() -> void:
	var dir := DirAccess.open(LevelData.user_map_dir())
	if dir:
		for file_name in dir.get_files():
			if SAVED_NAMES.any(func(saved: String) -> bool: return file_name.begins_with(saved.left(6))):
				dir.remove(file_name)
	LevelData.scan_map_pools()


## The built-in map set with one tile changed: another map, the same size.
func _another_map(change: int) -> PackedByteArray:
	var bytes := FileAccess.get_file_as_bytes(LevelData.MAP_DIR + "v1_2_2.dat")
	var at := LevelData.DAT_STAGE_SIZE + LevelData.DAT_FG_OFFSET + 5 * LevelData.DAT_COL_STRIDE + 10 * 2
	bytes[at] = (bytes[at] + change) % 256
	return bytes


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	var dir := LevelData.user_map_dir()
	if not dir.begins_with("user://test_maps"):
		print("  FAIL: not a test run's maps folder (%s): stopping before touching the player's maps" % dir)
		tree.quit(1)
		return
	_remove_saved()

	print("\n[A] A map set is known by its file's hash")
	var built_in := LevelData.find_pool("v1_2_2")
	var bytes := FileAccess.get_file_as_bytes(built_in.path)
	var digest := LevelData.pool_hash(built_in)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	check(digest == context.finish().hex_encode() and digest.length() == 64 and Net.is_map_hash(digest),
		"the built-in map's hash is its file's SHA-256: %s..." % digest.left(12))
	check(LevelData.pool_hash(built_in) == digest and LevelData.pool_with_hash(digest) == built_in,
		"the same each time, and it finds the map")
	check(LevelData.pool_with_hash(LevelData.bytes_hash(_another_map(1))) == null, "a map with one tile changed is another map")
	check(not Net.is_map_hash(digest.to_upper()) and not Net.is_map_hash(digest.left(63)) and not Net.is_map_hash(""),
		"a hash is 64 lower-case hex digits")
	check(Net.map_size_text(390000) == "381 KB", "its size, for the question: %s" % Net.map_size_text(390000))

	print("\n[B] A map set from a host is kept with the imported maps")
	var fort := _another_map(1)
	var saved := LevelData.save_map_bytes("Desert Fort", fort)
	check(saved.get("ok", false) and saved["name"] == "Desert_Fort" and saved["pool_id"] == "user:Desert_Fort",
		"saved as a map file's name may be: %s" % str(saved))
	var pool := LevelData.find_pool("user:Desert_Fort")
	check(pool != null and pool.path == dir + "Desert_Fort.dat" and LevelData.pool_hash(pool) == LevelData.bytes_hash(fort),
		"in this run's maps folder, a pool now, its hash the bytes'")
	check(LevelData.get_pool_stage_count(pool) == LevelData.get_pool_stage_count(built_in), "with all its stages")
	var other := LevelData.save_map_bytes("Desert Fort", _another_map(2))
	check(other.get("name", "") == "Desert_Fort_2" and LevelData.find_pool("user:Desert_Fort") != null,
		"another map of that name goes beside it: %s" % other.get("name", ""))
	var refused := LevelData.save_map_bytes("Desert Broken", fort.slice(0, 12001))
	check(not refused.get("ok", true) and not FileAccess.file_exists(dir + "Desert_Broken.dat"),
		"bytes that aren't a map file (not whole 6000-byte stages) are refused")

	print("\n[C] Asked about a host's map set this computer doesn't have, once")
	var offers: Array = []
	Net.map_offered.connect(func(map: Dictionary) -> void: offers.append(map))
	Net._take_host_map({"name": "v1_2_2", "hash": digest, "size": bytes.size()})
	await tree.process_frame
	check(offers.is_empty() and _prompt() == null and Net.host_map["hash"] == digest, "one it has: not asked")
	var offered_map := _another_map(3)
	var offered := {"name": "Offered Map", "hash": LevelData.bytes_hash(offered_map), "size": offered_map.size()}
	for bad: Dictionary in [{"name": "X", "hash": "abc", "size": 390000},
			{"name": "X", "hash": offered["hash"], "size": 5999},
			{"name": "X", "hash": offered["hash"], "size": (Net.MAX_MAP_SIZE / 6000 + 1) * 6000}]:
		Net._take_host_map(bad)
	await tree.process_frame
	check(offers.is_empty() and _prompt() == null and Net.host_map.is_empty(), "nonsense from a host: not asked, nothing taken")
	Net._take_host_map(offered)
	await tree.process_frame
	await tree.process_frame
	var prompt := _prompt()
	check(offers.size() == 1 and offers[0]["name"] == "Offered_Map" and prompt != null and Net.map_prompt_open,
		"one it lacks: asked, the name made a map file's: %s" % str(offers))
	Net._take_host_map(offered)
	await tree.process_frame
	check(offers.size() == 1 and tree.root.get_children().filter(func(n: Node) -> bool: return n is NetMapPrompt).size() == 1,
		"and only once")

	print("\n[D] The question")
	check(prompt._text.text == "The host plays on the map set Offered_Map (381 KB), which this computer doesn't have. Download it and keep it with your maps?",
		"it says what and how big: %s" % prompt._text.text)
	check(prompt._download_button.text == "DOWNLOAD" and prompt._not_now_button.text == "NOT NOW"
		and get_viewport().gui_get_focus_owner() == prompt._download_button, "DOWNLOAD or NOT NOW, on DOWNLOAD")
	check(prompt.get_index() == tree.root.get_child_count() - 1, "in front of the screen")
	var next_screen := Node.new()  # as a scene change adds the next screen after it
	tree.root.add_child(next_screen)
	await tree.process_frame
	await tree.process_frame
	check(prompt.get_index() == tree.root.get_child_count() - 1, "and back in front of a screen that comes after it")
	next_screen.queue_free()
	Input.action_press("p1_up")
	check(Net._input_message()[4] == 0, "while it's up, this machine's players send nothing: idle")
	Input.action_release("p1_up")
	_leaked.clear()
	await _key(KEY_RIGHT)
	check(get_viewport().gui_get_focus_owner() == prompt._not_now_button, "right: NOT NOW")
	await _key(KEY_LEFT)
	check(get_viewport().gui_get_focus_owner() == prompt._download_button, "left: DOWNLOAD")
	await _key(KEY_A)
	await _key(KEY_SPACE)
	check(_leaked.is_empty(), "no key gets past it to the screen under it: %s" % str(_leaked))
	await _key(KEY_ESCAPE)
	await tree.process_frame
	check(not is_instance_valid(prompt) and not Net.map_prompt_open, "Esc: NOT NOW, it's gone, and the players are free again")
	_leaked.clear()
	await _key(KEY_A)
	check(_leaked == [KEY_A], "the keys reach the screen again")

	Net._maps_asked.clear()
	Net._take_host_map(offered)
	await tree.process_frame
	await tree.process_frame
	prompt = _prompt()
	prompt._not_now_button.mouse_entered.emit()
	check(get_viewport().gui_get_focus_owner() == prompt._not_now_button, "the mouse over NOT NOW focuses it")
	prompt._download_button.pressed.emit()  # as a click does
	await tree.process_frame
	check(not is_instance_valid(prompt) and not Net.map_prompt_open,
		"DOWNLOAD with no host to fetch it from (this test's offline): it just closes")
	check(not FileAccess.file_exists(dir + "Offered_Map.dat"), "and nothing was saved")

	print("\n[E] A map set coming in pieces")
	var finished: Array = []
	Net.map_download_finished.connect(func(name: String, error: String) -> void: finished.append([name, error]))
	var said: Array = []
	Net.notice_posted.connect(func(text: String) -> void: said.append(text))
	var piece_map := _another_map(4)
	var piece_hash := LevelData.bytes_hash(piece_map)
	var start_download := func() -> void:
		Net._map_download = {"name": "Piece_Map", "hash": piece_hash, "size": piece_map.size(), "bytes": PackedByteArray()}
	start_download.call()
	Net._take_map_piece(piece_hash, 0, piece_map.size(), piece_map.slice(0, 1000))
	Net._take_map_piece(piece_hash, 5000, piece_map.size(), piece_map.slice(5000, 6000))
	check(finished.back() == ["", "it came in out of order"] and not Net.is_downloading_map(), "a piece out of place: it stops")
	start_download.call()
	var wrong := _another_map(5)
	for at in range(0, wrong.size(), Net.MAP_CHUNK):
		Net._take_map_piece(piece_hash, at, wrong.size(), wrong.slice(at, at + Net.MAP_CHUNK))
	check(finished.back() == ["", "it isn't the map the host named"] and not FileAccess.file_exists(dir + "Piece_Map.dat"),
		"whole, but not the map it was said to be: not kept")
	check(said.back() == "The host's map didn't come through: it isn't the map the host named", "and it says so: %s" % said.back())
	start_download.call()
	Net._take_map_piece(piece_hash, 0, 0, PackedByteArray())
	check(finished.back() == ["", "the host no longer plays on it"], "the host can't send it: it says so")
	start_download.call()
	var seen: Array = []
	Net.map_progress.connect(func(received: int, _total: int) -> void: seen.append(received))
	for at in range(0, piece_map.size(), Net.MAP_CHUNK):
		Net._take_map_piece("0".repeat(64), at, piece_map.size(), piece_map.slice(at, at + Net.MAP_CHUNK))
	check(seen.is_empty() and Net.is_downloading_map(), "pieces of another map are no part of it")
	for at in range(0, piece_map.size(), Net.MAP_CHUNK):
		Net._take_map_piece(piece_hash, at, piece_map.size(), piece_map.slice(at, at + Net.MAP_CHUNK))
	check(finished.back() == ["Piece_Map", ""] and FileAccess.file_exists(dir + "Piece_Map.dat")
		and LevelData.pool_with_hash(piece_hash) != null, "all of it, in order: kept, a pool")
	check(seen.size() == ceili(piece_map.size() / float(Net.MAP_CHUNK)) and seen.back() == piece_map.size(),
		"how far it had got, after each piece: %d" % seen.size())
	check(said.back() == "Saved the map Piece_Map with your maps.", "and it says so: %s" % said.back())

	Net._take_host_map({})
	_remove_saved()
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
