extends Node
## Headless test for the title menu's order, the maps it offers, and the Load
## Game screen's save actions: LOAD GAME comes before NEW GAME; only Tank.exe
## .dat maps are offered or imported; each save has a MORE button that pops up
## a window of options to change the map it plays on, duplicate it, export it
## to a file (and import it back) and delete it, by mouse or keyboard; a loaded
## save plays on its own map without changing the MAP setting. A test run keeps its own saves (and
## settings), so the player's are never touched.
## Run as an override main scene:
##   Godot --headless res://scenes/test/load_screen_test.tscn

const EXPORT_DIR := "user://test_export/"

var _fail := 0
var _screen    # the screen under test (untyped: the test reads its private state)


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
	await get_tree().process_frame


## Types [param text] into whatever has the keys.
func _type(text: String) -> void:
	for i in text.length():
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.unicode = text.unicode_at(i)
			ev.pressed = pressed
			Input.parse_input_event(ev)
			Input.flush_buffered_events()
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _open(scene_path: String) -> void:
	if _screen != null:
		get_tree().root.remove_child(_screen)
		_screen.free()
	_screen = load(scene_path).instantiate()
	get_tree().root.add_child(_screen)
	await get_tree().process_frame
	await get_tree().process_frame


## A save as SaveManager writes one.
func _save_data(save_name: String, saved_iso: String, stage: int, score: int) -> Dictionary:
	return {
		"meta": {"save_name": save_name},
		"header": {"saved_iso": saved_iso, "created_iso": saved_iso, "current_stage": stage,
			"counter": stage - 1, "difficulty": 2, "map_pool": "v1_2_2"},
		"players": {"player1": {"score": score, "lives": 3, "hp": 4}, "player2": null},
	}


func _names() -> Array:
	var names: Array = []
	for info: Dictionary in _screen._saves:
		names.append(info.get("save_name", ""))
	return names


## The buttons beside save [param index]'s row.
func _beside(index: int) -> Array:
	var texts: Array = []
	for child in _screen._rows[index].get_parent().get_children():
		if child is Button and child != _screen._rows[index]:
			texts.append(child.text)
	return texts


## True while the options window is up for save [param index].
func _window_for(index: int) -> bool:
	return _screen._popup_layer.visible \
		and _screen._popup_info.get("filepath", "") == _screen._saves[index]["filepath"]


func _window_texts() -> Array:
	var texts: Array = []
	for button: Button in _screen._popup_buttons:
		texts.append(button.text)
	return texts


## Opens save [param index]'s options with its MORE button, as a click does.
func _open_more(index: int) -> void:
	_screen._more_buttons[index].pressed.emit()
	await get_tree().process_frame


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return
	check(SaveManager.get_save_dir() == SaveManager.TEST_SAVE_DIR and SaveManager.get_save_list().is_empty(),
		"a test run keeps its own, empty save folder (the player's saves are never touched)")

	print("\n[A] The title menu: LOAD GAME first, NEW GAME second")
	await _open("res://scenes/main.tscn")
	var order: Array = []
	for button: Button in _screen._page_items(_screen.Page.MAIN):
		order.append(button.text)
	check(order == ["LOAD GAME", "NEW GAME", "ONLINE BATTLE", "SETTINGS", "QUIT"], "keyboard order: %s" % str(order))
	var shown: Array = []
	for child in _screen._load_game_button.get_parent().get_children():
		shown.append(child.text)
	check(shown == order, "and the panel shows them so")
	check(_focus() == _screen._load_game_button, "LOAD GAME has the focus")
	await _key(KEY_DOWN)
	check(_focus() == _screen._new_game_button, "down: NEW GAME")

	print("\n[B] Maps: Tank.exe .dat only")
	var pool_ids: Array = []
	var only_dat := true
	for pool in LevelData.get_available_pools():
		pool_ids.append(pool.id)
		only_dat = only_dat and pool.type == "dat" and pool.path.get_extension().to_lower() == "dat"
	check(only_dat and not pool_ids.has("test_map_pool_1") and pool_ids.has("v1_2_2"),
		"the MAP setting offers .dat pools only, without the test pool: %s" % str(pool_ids))
	check(Array(_screen.MAP_IMPORT_FILTERS) == ["*.dat, *.DAT ; Tank.exe map files (Stage.dat)"],
		"IMPORT MAP picks .dat files only")
	var txt := "user://test_export_map.txt"
	var f := FileAccess.open(txt, FileAccess.WRITE)
	f.store_string("[Stage 1]\n[End]\n")
	f.close()
	var refused: Dictionary = LevelData.import_map_file(ProjectSettings.globalize_path(txt))
	check(not refused.get("ok", true) and str(refused.get("error", "")).begins_with("unsupported file type .txt"),
		"and a .txt map is refused: %s" % refused.get("error", ""))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(txt))

	print("\n[C] Each save: one MORE button, its options in a pop-up window")
	for data: Dictionary in [_save_data("Alpha", "2026-09-20 10:00:00", 5, 12000),
			_save_data("Beta", "2026-09-21 10:00:00", 9, 30500)]:
		SaveManager._write_as_new(data, data["meta"]["save_name"])
	await _open("res://scenes/load_screen.tscn")
	check(_names() == ["Beta", "Alpha"], "two saves, newest first: %s" % str(_names()))
	check(_beside(0) == ["MORE"] and _beside(1) == ["MORE"], "beside each row, MORE alone: %s" % str(_beside(0)))
	check(_screen._popup_buttons[0] == _screen._map_button
		and _window_texts().slice(1) == ["RENAME", "DUPLICATE", "EXPORT", "DELETE"]
		and not _screen._popup_layer.visible, "its options, MAP then %s, wait in a hidden window" % str(_window_texts().slice(1)))
	check(_screen._import_button.text == "IMPORT", "the footer's IMPORT takes any save")
	var row: Button = _screen._rows[1]
	var more: Button = _screen._more_buttons[1]
	var rows_before: Array = [_screen._rows[0].get_global_rect(), row.get_global_rect()]
	row.grab_focus()
	await _key(KEY_RIGHT)
	check(_focus() == more, "right: from Alpha's row to its MORE")
	await _key(KEY_LEFT)
	check(_focus() == row, "left: back to the row")
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	check(_window_for(1) and more.button_pressed and _focus().text == "RENAME"
		and _screen._popup_title.text == "Alpha" and _screen._hint.text == _screen.OPTIONS_HINT,
		"Enter on MORE: Alpha's window pops up, on RENAME")
	check(_screen._map_button.text == "MAP: v1_2_2" and _screen._map_button.disabled,
		"MAP on top shows its map, greyed: no other map here (%s)" % _screen._map_button.text)
	var window: Rect2 = _screen._popup.get_global_rect()
	var more_rect := more.get_global_rect()
	check(absf(window.end.x - more_rect.end.x) < 1.0 and window.position.y >= more_rect.end.y
		and get_viewport().get_visible_rect().encloses(window),
		"under MORE, lined up with its right edge, on the screen (%s)" % str(window))
	check([_screen._rows[0].get_global_rect(), row.get_global_rect()] == rows_before,
		"floating over the list: no row moves")
	var walked: Array = []
	for i in 4:
		await _key(KEY_DOWN)
		walked.append(_focus().text)
	check(walked == ["DUPLICATE", "EXPORT", "DELETE", "RENAME"], "down walks the options, round again: %s" % str(walked))
	await _key(KEY_UP)
	check(_focus().text == "DELETE", "up too")
	await _key(KEY_ESCAPE)
	check(not _screen._popup_layer.visible and not more.button_pressed and _focus() == more,
		"Esc closes it, back on MORE")
	await _key(KEY_ENTER)
	await _key(KEY_LEFT)
	check(not _screen._popup_layer.visible and _focus() == more, "and so does left")
	await _key(KEY_UP)
	check(_focus() == _screen._rows[0], "closed, up and down move between the saves")
	await _open_more(1)
	await _open_more(0)
	check(_window_for(0) and not _screen._more_buttons[1].button_pressed, "another save's MORE moves the window to it")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(40, 40)
	_screen._popup_layer.gui_input.emit(click)
	check(not _screen._popup_layer.visible and _focus() == _screen._more_buttons[0], "a click outside the window closes it")
	await _open_more(1)
	await _open_more(1)
	check(not _screen._popup_layer.visible, "and so does MORE again")

	print("\n[D] DUPLICATE")
	await _open_more(1)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	check(_names() == ["Beta", "Alpha", "Alpha_copy"], "Enter on DUPLICATE: a copy right after it %s" % str(_names()))
	var copy_path: String = SaveManager.get_save_dir() + "Alpha_copy.tsave"
	var copy: Dictionary = SaveManager._read_save_data(copy_path)
	var alpha: Dictionary = SaveManager._read_save_data(SaveManager.get_save_dir() + "Alpha.tsave")
	check(copy.get("meta", {}).get("save_name") == "Alpha_copy" and copy["header"] == alpha["header"]
		and copy["players"] == alpha["players"], "the same game under its own name")
	check(_focus() == _screen._rows[2] and _screen._hint.text.contains("Alpha_copy"), "focus and hint on the copy")
	await _open_more(1)
	_screen._popup_buttons[2].pressed.emit()
	check(_names().has("Alpha_copy_2") and not _screen._popup_layer.visible, "a second copy: Alpha_copy_2, the window closed")

	print("\n[E] EXPORT to a file, IMPORT it back")
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	await _open_more(1)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	var dialog: FileDialog = _screen._export_picker._dialog
	check(dialog != null and dialog.visible and dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE
		and dialog.current_file == "Alpha.tsave", "EXPORT asks where to write Alpha.tsave (a save dialog)")
	check(not _screen._popup_layer.visible and _focus() == _screen._more_buttons[1], "the window closes, MORE keeps the focus")
	var dest := ProjectSettings.globalize_path(EXPORT_DIR + "Alpha.tsave")
	dialog.file_selected.emit(dest)
	dialog.hide()
	check(FileAccess.get_file_as_bytes(dest) == FileAccess.get_file_as_bytes(SaveManager.get_save_dir() + "Alpha.tsave"),
		"the file written is the save, byte for byte")
	check(_screen._hint.text.begins_with("Exported \"Alpha\""), "the hint says so: %s" % _screen._hint.text)
	var bare := ProjectSettings.globalize_path(EXPORT_DIR + "backup")
	check(SaveManager.export_save(SaveManager.get_save_dir() + "Beta.tsave", bare).get("path") == bare + ".tsave",
		"a name without an extension gets .tsave")
	_screen._import_file(dest)
	check(_names().has("Alpha_2") and _focus() == _screen._rows[_names().find("Alpha_2")],
		"importing it back adds \"Alpha_2\" (the name was taken), focused")
	var imported: Dictionary = SaveManager._read_save_data(SaveManager.get_save_dir() + "Alpha_2.tsave")
	check(imported["header"] == alpha["header"] and imported["players"] == alpha["players"]
		and imported["meta"]["save_name"] == "Alpha_2", "the same game")
	var bogus := ProjectSettings.globalize_path(EXPORT_DIR + "broken.tsave")
	f = FileAccess.open(bogus, FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	var count := _names().size()
	_screen._import_file(bogus)
	check(_names().size() == count and _screen._hint.text.begins_with("Import failed"), "a broken .tsave is refused")
	_screen._import_file(ProjectSettings.globalize_path(EXPORT_DIR + "notes.txt"))
	check(_names().size() == count and _screen._hint.text.contains("unsupported"), "so is anything but .sav / .tsave")

	print("\n[F] DELETE still asks first")
	var index := _names().find("Alpha_copy_2")
	var delete_button: Button = _screen._delete_button
	await _open_more(index)
	await _key(KEY_UP)
	check(_focus() == delete_button, "MORE, up: DELETE")
	await _key(KEY_ENTER)
	check(delete_button.text == "CONFIRM?" and _names().has("Alpha_copy_2")
		and _screen._hint.text == _screen.CONFIRM_HINT, "first press: CONFIRM?")
	await _key(KEY_ESCAPE)
	check(delete_button.text == "DELETE" and _window_for(index), "Esc cancels that, the window stays up")
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	check(not _names().has("Alpha_copy_2") and not FileAccess.file_exists(SaveManager.get_save_dir() + "Alpha_copy_2.tsave"),
		"second press: gone")

	print("\n[G] A save plays on its own map; the MAP setting stays the player's pick")
	var other := LevelData.MapPool.new()  # a second map, as an imported one would be
	other.id = "user:test_other_map"
	other.display_name = "test_other_map"
	other.type = "dat"
	other.path = "res://maps/v1_2_2.dat"
	LevelData.get_available_pools().append(other)
	GameManager.set_map_pool(other.id)
	InputSettings.save_map_pool(other.id)  # picked on MAP, as an import does
	SaveManager._restore_from_data(_save_data("Beta", "2026-09-25T14:00:00", 43, 100))  # LOAD GAME
	check(GameManager.current_map_pool_id == "v1_2_2", "the save plays on its own map, v1_2_2")
	check(InputSettings.get_saved_map_pool() == other.id,
		"and the MAP setting keeps the player's pick (%s)" % InputSettings.get_saved_map_pool())
	await _open("res://scenes/main.tscn")  # back to the title
	check(GameManager.current_map_pool_id == other.id
		and MenuRows.value_label(_screen._map_row).text.begins_with("test_other_map"),
		"back on the title, the MAP row and new games have it again: %s" % MenuRows.value_label(_screen._map_row).text)
	LevelData.scan_map_pools()
	GameManager.set_map_pool("v1_2_2")
	InputSettings.save_map_pool("v1_2_2")

	print("\n[H] MAP: the map a save plays on, any that reaches its stage, kept in the save")
	# A two-stage map beside the bundled one, in the test run's own maps folder.
	var tiny_path := LevelData.user_map_dir() + "tiny.dat"
	DirAccess.make_dir_recursive_absolute(LevelData.user_map_dir())
	var tiny := FileAccess.open(tiny_path, FileAccess.WRITE)
	tiny.store_buffer(FileAccess.get_file_as_bytes("res://maps/v1_2_2.dat").slice(0, 3 * LevelData.DAT_STAGE_SIZE))
	tiny.close()
	LevelData.scan_map_pools()
	for data: Dictionary in [_save_data("Early", "2026-09-22 10:00:00", 2, 100),
			_save_data("Late", "2026-09-22 11:00:00", 3, 100)]:
		SaveManager._write_as_new(data, data["meta"]["save_name"])
	await _open("res://scenes/load_screen.tscn")
	var early := _names().find("Early")
	var early_path := SaveManager.get_save_dir() + "Early.tsave"
	check(_screen._map_labels[early].text == "v1_2_2" and _screen._map_labels.size() == _names().size(),
		"each row shows its map under the date: %s" % _screen._map_labels[early].text)
	await _open_more(early)
	check(_screen._map_button.text == "MAP: v1_2_2" and not _screen._map_button.disabled
		and _focus() == _screen._map_button, "Early, at stage 2: MAP shows v1_2_2, focused (%s)" % _screen._map_button.text)
	await _key(KEY_ENTER)
	check(_screen._map_button.text == "MAP: tiny"
		and SaveManager._read_save_data(early_path)["header"]["map_pool"] == "user:tiny",
		"Enter: the next map, tiny, written into the save (%s)" % _screen._map_button.text)
	check(_screen._map_labels[early].text == "tiny", "and its row shows it at once")
	check(_window_for(early) and _focus() == _screen._map_button, "the window stays up, on MAP")
	await _key(KEY_ENTER)
	check(SaveManager._read_save_data(early_path)["header"]["map_pool"] == "v1_2_2", "again: round to v1_2_2")
	await _key(KEY_ENTER)
	await _key(KEY_ESCAPE)
	var late := _names().find("Late")
	await _open_more(late)
	check(_screen._map_button.disabled and _screen._map_button.text == "MAP: v1_2_2" and _focus().text == "RENAME",
		"Late, at stage 3: tiny's two stages don't reach it, so MAP is greyed and RENAME has the focus")
	await _key(KEY_ESCAPE)
	var early_saved: Dictionary = SaveManager._read_save_data(early_path)
	check(early_saved["header"]["current_stage"] == 2 and early_saved["header"]["saved_iso"] == "2026-09-22 10:00:00"
		and early_saved["players"]["player1"]["score"] == 100, "the rest of the save as it was, its date too")
	SaveManager._restore_from_data(early_saved)  # LOAD GAME
	check(GameManager.current_map_pool_id == "user:tiny", "loaded, it plays on tiny")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tiny_path))
	LevelData.scan_map_pools()
	GameManager.set_map_pool("v1_2_2")

	await _check_rename()

	# Clean up what the test wrote outside its save folder.
	for name in DirAccess.get_files_at(EXPORT_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(EXPORT_DIR + name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EXPORT_DIR))
	get_tree().root.remove_child(_screen)
	_screen.free()
	await tree.create_timer(0.3).timeout
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


## [I] RENAME: a window to type a save's new name in. The file follows the
## name, and so does a game running on it.
func _check_rename() -> void:
	print("\n[I] RENAME: a save's new name, typed in a window")
	var dir := SaveManager.get_save_dir()
	await _open("res://scenes/load_screen.tscn")
	var beta_before: Dictionary = SaveManager._read_save_data(dir + "Beta.tsave")
	var beta := _names().find("Beta")
	await _open_more(beta)
	check(_window_texts()[1] == "RENAME" and _focus().text == "RENAME", "RENAME, under MAP")
	await _key(KEY_ENTER)
	var field: LineEdit = _screen._rename_field
	check(_screen._rename_layer.visible and not _screen._popup_layer.visible and field.has_focus()
		and field.text == "Beta" and _screen._rename_note.text == _screen.RENAME_NOTE,
		"Enter: the RENAME window, Beta in its field, typing, the rules under it")
	check(field.get_selected_text() == "Beta", "all of the name picked, so typing replaces it")
	await _type("Final Run")
	await _key(KEY_ENTER)
	var renamed := dir + "Final Run.tsave"
	check(not _screen._rename_layer.visible and _names().has("Final Run") and not _names().has("Beta")
		and FileAccess.file_exists(renamed) and not FileAccess.file_exists(dir + "Beta.tsave"),
		"typed Final Run, Enter: the save and its file renamed %s" % str(_names()))
	var saved: Dictionary = SaveManager._read_save_data(renamed)
	check(saved["meta"]["save_name"] == "Final Run" and saved["header"] == beta_before["header"]
		and saved["players"] == beta_before["players"], "the name kept in it, the game as it was")
	var index := _names().find("Final Run")
	check(_focus() == _screen._rows[index] and _screen._hint.text == "Renamed \"Beta\" to \"Final Run\"",
		"its row focused, and the hint says so")

	await _open_more(index)
	await _key(KEY_ENTER)
	await _type("alpha")
	await _key(KEY_ENTER)
	check(_screen._rename_layer.visible and field.has_focus()
		and _screen._rename_note.text == "A save called Alpha already exists."
		and _screen._rename_note.has_theme_color_override("font_color"),
		"another save's name, in any case, is refused in red, still typing")
	field.select_all()
	await _type("Bad/Name")
	await _key(KEY_ENTER)
	check(_screen._rename_note.text == "A name can only use letters, digits, spaces, - and _.", "so is a / in it")
	field.select_all()
	await _type("   ")
	await _key(KEY_ENTER)
	check(_screen._rename_note.text == "Type a name first.", "and a name of spaces")
	await _key(KEY_ESCAPE)
	check(not _screen._rename_layer.visible and _names().has("Final Run") and _focus() == _screen._more_buttons[index],
		"Esc: nothing renamed, back on MORE")
	await _open_more(index)
	await _key(KEY_ENTER)
	_screen._rename_cancel_button.pressed.emit()
	check(not _screen._rename_layer.visible and _names().has("Final Run"), "CANCEL too")

	await _open_more(index)
	await _key(KEY_ENTER)
	await _type("FINAL RUN")
	_screen._rename_save_button.pressed.emit()
	check(_names().has("FINAL RUN") and DirAccess.get_files_at(dir).has("FINAL RUN.tsave")
		and not DirAccess.get_files_at(dir).has("Final Run.tsave"), "SAVE: only the case changed, the file's too")
	index = _names().find("FINAL RUN")
	await _open_more(index)
	await _key(KEY_ENTER)
	await _type("  Last   Stand  ")
	await _key(KEY_ENTER)
	check(_names().has("Last Stand"), "spaces at the ends dropped, and runs of them made one: %s" % str(_names()))
	var names_before: Array = _names()
	index = _names().find("Last Stand")
	await _open_more(index)
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	check(not _screen._rename_layer.visible and not _screen._hint.text.begins_with("Renamed")
		and _names() == names_before and _focus() == _screen._more_buttons[index],
		"Enter on the same name just closes the window, back on MORE")

	var path := dir + "Last Stand.tsave"
	GameManager.current_save_file = path   # the game being played is this save
	var result: Dictionary = SaveManager.rename_save(path, "Next Stage")
	check(result.get("ok", false) and GameManager.current_save_file == dir + "Next Stage.tsave",
		"renaming the save of the game being played: the game saves under the new name")
	SaveManager.save_game()
	check(SaveManager._read_save_data(dir + "Next Stage.tsave")["meta"]["save_name"] == "Next Stage"
		and not FileAccess.file_exists(path), "and its autosave keeps it")
	GameManager.current_save_file = ""
	check(SaveManager.rename_save(dir + "Next Stage.tsave", "x".repeat(41)).get("error", "")
		== "A name can be up to 40 characters.", "a name over 40 characters is refused")
	check(SaveManager._sanitize_save_name("  my  save!!  ") == "my save_",
		"an imported file's name keeps its spaces, the rest made safe")
