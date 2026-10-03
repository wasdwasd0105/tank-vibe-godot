extends Node
## Headless test for the menus' languages (Localization): the system's language
## (Chinese or else English) until the player picks one on the settings' LANGUAGE
## row, which is kept in the settings file;
## the translation file sound (every key translated, its placeholders kept, every
## character baked into both fonts); the menus in Chinese, texts built from parts
## included, rebuilt when the language changes; the in-game HUD in English; and
## the results box's header and total, the one in-game text translated.
## Run as an override main scene:
##   Godot --headless res://scenes/test/localization_test.tscn

const CSV_PATH := "res://localization/translations.csv"

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


func _open(scene_path: String) -> void:
	await _close()
	_screen = load(scene_path).instantiate()
	get_tree().root.add_child(_screen)
	for i in 3:
		await get_tree().process_frame


func _close() -> void:
	if _screen != null:
		get_tree().root.remove_child(_screen)
		_screen.free()
		_screen = null
	await get_tree().process_frame


## What a label or button shows: its text through the translation, as drawn.
func _shown(control: Control) -> String:
	return control.atr(control.text) if control.can_auto_translate() else control.text


## The translation file's rows: [key, Chinese], escapes undone.
func _rows() -> Array:
	var rows: Array = []
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	file.get_csv_line()  # keys,zh_CN
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() >= 2:
			rows.append([line[0].c_unescape(), line[1].c_unescape()])
	return rows


## The % fields of [param text], in order ("%s", "%d"...), "%%" left out.
func _percent_fields(text: String) -> Array:
	var fields: Array = []
	for m in RegEx.create_from_string("%[-+0-9.]*[sdfxXc%]").search_all(text):
		if m.get_string() != "%%":
			fields.append(m.get_string())
	return fields


func _brace_fields(text: String) -> Array:
	var fields: Array = []
	for m in RegEx.create_from_string("\\{[a-z_]+\\}").search_all(text):
		fields.append(m.get_string())
	fields.sort()
	return fields


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return

	print("\n[A] The system's language until the player picks one")
	check(Localization.pick_language("", "zh") == "zh_CN", "nothing picked, a Chinese system: 简体中文")
	check(Localization.pick_language("", "en") == "en" and Localization.pick_language("", "ja") == "en"
		and Localization.pick_language("", "") == "en", "any other system (or none): English")
	check(Localization.pick_language("en", "zh") == "en" and Localization.pick_language("zh_CN", "en") == "zh_CN",
		"the player's pick wins either way")
	check(Localization.pick_language("fr", "zh") == "zh_CN", "a pick that isn't a language is ignored")
	check(Localization.get_language() == "en" and TranslationServer.get_locale() == "en",
		"a test run: English, whatever this machine speaks (%s)" % OS.get_locale())
	check(Localization.get_language_name("zh_CN") == "简体中文" and Localization.get_language_name("en") == "English",
		"each language named in itself")

	print("\n[B] The translation file")
	var rows := _rows()
	var untranslated: Array = []
	var bad_fields: Array = []
	var wrong_import: Array = []
	TranslationServer.set_locale("zh_CN")
	for row: Array in rows:
		if row[1].strip_edges().is_empty():
			untranslated.append(row[0])
		if _percent_fields(row[0]) != _percent_fields(row[1]) or _brace_fields(row[0]) != _brace_fields(row[1]):
			bad_fields.append(row[0])
		if TranslationServer.translate(row[0]) != row[1]:
			wrong_import.append(row[0])
	TranslationServer.set_locale("en")
	check(rows.size() > 100 and untranslated.is_empty(), "%d keys, every one translated %s" % [rows.size(), str(untranslated)])
	check(bad_fields.is_empty(), "each translation keeps its key's %%s / %%d fields, in order, and its {names} %s"
		% [str(bad_fields)])
	check(wrong_import.is_empty(), "and the game reads them all back, line breaks included %s" % [str(wrong_import)])
	var gold: FontFile = load("res://assets/ui/fonts/gold_font.fnt")
	var cjk: FontFile = load("res://assets/ui/fonts/cjk_font.fnt")
	var missing := ""
	var text := "简体中文"
	for row: Array in rows:
		text += row[1]
	for c in text:
		if c.unicode_at(0) >= 0x2E80 and not (gold.has_char(c.unicode_at(0)) and cjk.has_char(c.unicode_at(0))):
			if not missing.contains(c):
				missing += c
	check(missing.is_empty(), "every Chinese character is baked into gold_font and cjk_font (rerun tools/make_fonts.py) %s" % missing)
	check(ThemeDB.fallback_font.fallbacks.has(cjk), "the default font falls back on cjk_font")
	var sizes: Array = []
	for size in [18, 20, 22, 24, 26]:
		sizes.append(cjk.get_string_size("中", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	check(sizes == [24.0, 24.0, 24.0, 24.0, 24.0], "the menus' 18-26 px text gets it at exactly 2x %s" % str(sizes))

	print("\n[C] The title screen: the LANGUAGE row")
	await _open("res://scenes/main.tscn")
	check(_shown(_screen._new_game_button) == "NEW GAME", "English: NEW GAME")
	_screen._open_settings()
	_screen._tabs.select(_screen.SettingsTab.GENERAL)
	await tree.process_frame
	var language_row: Button = _screen._common.language_row
	check(_screen._nav.items.has(language_row) and MenuRows.value_label(language_row).text == "English",
		"the settings' GENERAL tab lists a LANGUAGE row: English")
	language_row.grab_focus()
	await _key(KEY_RIGHT)
	check(Localization.get_language() == "zh_CN" and TranslationServer.get_locale() == "zh_CN",
		"right: Chinese")
	check(InputSettings.get_saved_language() == "zh_CN", "kept in the settings file")
	check(MenuRows.value_label(language_row).text == "简体中文"
		and _shown(MenuRows.layout_of(language_row).get_node("Name")) == "语言",
		"the row reads 语言 / 简体中文")
	check(_shown(_screen._new_game_button) == "新游戏" and _shown(_screen._load_game_button) == "读取存档"
		and _shown(_screen._settings_back_button) == "返回",
		"the buttons translate themselves: 新游戏, 读取存档, 返回")
	check(_shown(_screen.get_node("TitleBlock/Title")) == "坦克决战" and tree.root.title == "坦克决战",
		"the game's name, on the title screen and the window: 坦克决战")
	var version: Label = _screen.get_node("VersionLabel")
	var corner := version.get_global_rect().end
	var screen := get_viewport().get_visible_rect().size
	check(version.text == "Ver. %s" % ProjectSettings.get_setting("application/config/version")
		and _shown(version) == "Ver. 1.1.0" and corner.x > screen.x - 40 and corner.y > screen.y - 40,
		"Ver. 1.1.0, the project's version, in the bottom-right corner, the same in Chinese (%s)" % str(corner))
	check(_shown(MenuRows.tab(_screen._tabs.strip, 0)) == "常规" and _shown(MenuRows.tab(_screen._tabs.strip, 1)) == "游戏",
		"the settings' tabs: 常规, 游戏")
	var difficulty_row: Button = _screen._game.difficulty_row
	check(MenuRows.value_label(difficulty_row).text == "%d   %s" % [GameManager.difficulty,
		["容易", "中等", "困难", "极困难", "疯狂"][GameManager.difficulty - 1]],
		"the difficulty, built from parts, is rebuilt: %s" % MenuRows.value_label(difficulty_row).text)
	check(MenuRows.value_label(_screen._map_row).text.ends_with("64 关"),
		"and the map's stage count: %s" % MenuRows.value_label(_screen._map_row).text)
	await _key(KEY_LEFT)
	check(Localization.get_language() == "en" and MenuRows.value_label(difficulty_row).text.ends_with("EASY")
		and _shown(_screen._new_game_button) == "NEW GAME", "left: English again, everything back")
	check(_shown(_screen.get_node("TitleBlock/Title")) == "BATTLE TANK" and tree.root.title == "Battle Tank",
		"BATTLE TANK on the title screen, Battle Tank on the window")
	var box := VBoxContainer.new()
	add_child(box)
	var bare := CommonSettings.new(box, false)
	bare.adjust(bare.language_row, 1)
	check(MenuRows.value_label(bare.language_row).text == "简体中文",
		"a settings list keeps its own LANGUAGE row up to date, whatever its host")
	bare.adjust(bare.language_row, -1)
	box.free()
	Localization.set_language("zh_CN")

	print("\n[D] The controls page, its prompts built from parts")
	_screen._open_keybinds("p1")
	await tree.process_frame
	var cp = _screen._keybind_page
	check(cp._title.text == "P1 按键" and _shown(MenuRows.tab(cp._tab_row, 0)) == "键盘",
		"P1 按键, the 键盘 tab")
	check(cp._prompt.text == "点击某一行，或在该行按开火键，即可更改该按键。", "its prompt: %s" % cp._prompt.text)
	cp._begin_capture(0)
	check(cp._prompt.text == "请为「上」按下按键   （Esc 或 B 取消）", "waiting for UP's key: %s" % cp._prompt.text)
	cp._cancel_capture()
	cp._select_tab(1)
	await tree.process_frame
	check(cp._prompt.text.ends_with("手柄 1 未连接。") and cp._prompt.text.begins_with("A / 点击：更改"),
		"the GAMEPAD tab: %s" % cp._prompt.text.replace("\n", " | "))
	check(MenuRows.slot(cp._pad_rows[0], 0).text == "十字键", "the D-pad's slot: 十字键")
	check(InputSettings.get_pad_name("b0") == "A" and InputSettings.get_pad_name("b6") == "Start",
		"letters and the names on the pads stay")
	cp._close()

	print("\n[E] The load screen and the import errors")
	await _open("res://scenes/load_screen.tscn")
	check(_screen._format_details({"stage": 3, "difficulty": 2, "counter": 1}) == "第 3 关   ·   难度 2   ·   已通过 1 关",
		"a save's details: %s" % _screen._format_details({"stage": 3, "difficulty": 2, "counter": 1}))
	var result: Dictionary = SaveManager.import_save_file("/tmp/not_a_save.txt")
	check(result.get("error", "") == "不支持的文件类型 .txt（应为 .sav 或 .tsave）", "an import error: %s" % result.get("error"))
	check(_shown(_screen._empty_label).begins_with("还没有存档。\n"), "the empty list's two lines")
	await _close()

	print("\n[F] In a stage: the pause menu translated, the HUD not")
	GameManager.current_stage = 1
	GameManager.player_active = [true, true]
	GameManager.player_disabled = [false, true]
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_intro = false
	tree.root.add_child(game)
	for i in 3:
		await tree.process_frame
	game.enemy_spawner.halt()
	var menu = game.get_node("PauseLayer/PauseMenu")
	menu._open()
	await tree.process_frame
	check(menu._p2_button.text == "玩家 2：关" and _shown(menu._resume_button) == "继续", "the pause menu: 继续, 玩家 2：关")
	check(Array(game.stage_overlay.box_words()) == ["战斗成绩", "总计"],
		"the results box, the one in-game text translated: 战斗成绩 over it, 总计 at its foot")
	menu._open_settings()
	menu._tabs.select(menu.SettingsTab.GENERAL)
	await tree.process_frame
	menu._common.language_row.grab_focus()
	await _key(KEY_RIGHT)
	check(Localization.get_language() == "en" and menu._p2_button.text == "PLAYER 2: OFF",
		"English from its settings: PLAYER 2: OFF rebuilt at once")
	check(Array(game.stage_overlay.box_words()) == ["RESULTS", "TOTAL"], "and the results box's RESULTS / TOTAL")
	Localization.set_language("zh_CN")
	menu._close()
	await tree.process_frame
	var hud = game.hud
	check(hud.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED
		and not hud.p2_lives_label.can_auto_translate() and hud.p2_lives_label.text == "OFF",
		"the HUD stays English: player 2 sitting out reads OFF, not 关")
	tree.root.remove_child(game)
	game.free()
	GameManager.player_disabled = [false, false]

	Localization.set_language("en")
	await tree.create_timer(0.5).timeout
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
