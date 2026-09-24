extends Control
## Title screen: the main menu, its settings page, and each player's controls
## page (the ControlsPage the pause menu shows too).
##
## Mouse: hovering a button focuses it, clicking activates it; the < > arrows
## change a setting. Keyboard: P1/P2 movement keys or the arrow keys move the
## focus, fire / Enter / Space activate, left/right change a setting and Esc
## goes back one page. Controller: the same with the D-pad or stick, A and B.

enum Page { MAIN, SETTINGS, KEYBIND }

const LOAD_SCREEN_SCENE := "res://scenes/load_screen.tscn"
const PAGE_FADE_TIME := 0.15
const DIFFICULTY_NAMES: Array[String] = ["EASY", "NORMAL", "HARD", "EXPERT", "INSANE"]
const MIN_CREDITS := 1
const MAX_CREDITS := 50
const MIN_DIFFICULTY := 1
const MAX_DIFFICULTY := 5
const MAP_IMPORT_TITLE := "Import a Tank.exe map"
const MAP_IMPORT_HINT := "a Tank.exe Stage.dat"
const MAP_IMPORT_FILTERS: PackedStringArray = ["*.dat, *.DAT ; Tank.exe map files (Stage.dat)"]
const ERROR_COLOR := Color(1.0, 0.5, 0.45)

# --- Main page ---
@onready var _main_page: Control = %MainPanel
@onready var _new_game_button: Button = %NewGameButton
@onready var _load_game_button: Button = %LoadGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton

# --- Settings page ---
@onready var _settings_page: Control = %SettingsPanel
@onready var _settings_rows: VBoxContainer = %SettingsRows
@onready var _settings_back_button: Button = %SettingsBackButton

# --- Controls page ---
@onready var _keybind_page: ControlsPage = %KeybindPanel

# --- Footer ---
@onready var _footer: Control = $Footer
@onready var _footer_p1: Label = %FooterP1
@onready var _footer_p2: Label = %FooterP2

var _page: Page = Page.MAIN
var _nav: MenuFocus

# Settings rows, built in _ready(): the title's own, then the ones the pause
# menu shares (sound, vibration, each player's controls).
var _map_row: Button
var _import_map_row: Button
var _theme_row: Button
var _credits_row: Button
var _difficulty_row: Button
var _common: CommonSettings

var _available_themes: Array[String] = []
var _theme_index: int = 0
var _available_pools: Array = []  # Array of LevelData.MapPool
var _pool_index: int = 0
var _map_picker: MenuFilePicker

# Controls page state
var _keybind_player: String = "p1"
## True while the menus are driven with a controller, so the controls page opens
## on its GAMEPAD tab.
var _using_pad: bool = false


func _ready() -> void:
	_nav = MenuFocus.new(get_viewport())
	_map_picker = MenuFilePicker.new(self, MAP_IMPORT_TITLE, MAP_IMPORT_FILTERS, "map")
	_map_picker.file_picked.connect(_import_map_file)
	_load_saved_settings()
	_build_settings_rows()
	_connect_buttons()
	_refresh_settings_values()
	_refresh_footer()
	_show_page(Page.MAIN, _load_game_button, false)
	SoundManager.attach_ui_sounds(self)


func _input(event: InputEvent) -> void:
	var device := MenuFocus.device_of(event)
	if device >= 0:
		_using_pad = device == 1
	# The controls page handles its own input (it gets each event first).
	if _page == Page.KEYBIND or not MenuFocus.is_navigation_event(event):
		return
	# Activating a button can change scene, which removes this node from the
	# tree at once (get_viewport() then returns null), so keep the viewport.
	var viewport := get_viewport()
	if MenuFocus.is_pressed(event, MenuFocus.UP_ACTIONS):
		_nav.move(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.DOWN_ACTIONS):
		_nav.move(1)
	elif MenuFocus.is_pressed(event, MenuFocus.LEFT_ACTIONS):
		_adjust_focused_value(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.RIGHT_ACTIONS):
		_adjust_focused_value(1)
	elif MenuFocus.is_pressed(event, MenuFocus.ACCEPT_ACTIONS):
		_nav.activate()
	elif MenuFocus.is_pressed(event, MenuFocus.BACK_ACTIONS):
		_go_back()
	else:
		return
	viewport.set_input_as_handled()


# =====================================================================
# Setup
# =====================================================================

func _load_saved_settings() -> void:
	var saved_theme := InputSettings.get_saved_theme()
	if saved_theme != "":
		ThemeManager.load_theme(saved_theme)
	_available_themes = ThemeManager.get_available_themes()
	_theme_index = maxi(_available_themes.find(ThemeManager.current_theme), 0)

	var saved_pool := InputSettings.get_saved_map_pool()
	if saved_pool != "":
		GameManager.set_map_pool(saved_pool)
	_available_pools = LevelData.get_available_pools()
	_pool_index = -1
	for i in _available_pools.size():
		if _available_pools[i].id == GameManager.current_map_pool_id:
			_pool_index = i
			break
	if _pool_index == -1 and not _available_pools.is_empty():
		_pool_index = 0
		GameManager.set_map_pool(_available_pools[0].id)
	_pool_index = maxi(_pool_index, 0)

	GameManager.max_credits = InputSettings.get_saved_max_credits()
	GameManager.difficulty = InputSettings.get_saved_difficulty()


func _build_settings_rows() -> void:
	_map_row = _add_value_row("MAP", _cycle_pool)
	_import_map_row = _add_action_row("IMPORT MAP", MAP_IMPORT_HINT, _map_picker.open)
	_theme_row = _add_value_row("THEME", _cycle_theme)
	_credits_row = _add_value_row("CREDITS", _cycle_credits)
	_difficulty_row = _add_value_row("DIFFICULTY", _cycle_difficulty)
	_common = CommonSettings.new(_settings_rows, false)
	_common.controls_requested.connect(_open_keybinds)


func _add_value_row(title: String, cycle: Callable) -> Button:
	var row := MenuRows.make_value_row(title)
	_settings_rows.add_child(row)
	_focus_on_hover(row)
	row.pressed.connect(cycle.bind(1))
	var left := MenuRows.arrow(row, "Left")
	left.pressed.connect(cycle.bind(-1))
	left.mouse_entered.connect(row.grab_focus)
	var right := MenuRows.arrow(row, "Right")
	right.pressed.connect(cycle.bind(1))
	right.mouse_entered.connect(row.grab_focus)
	return row


func _add_action_row(title: String, hint: String, action: Callable) -> Button:
	var row := MenuRows.make_action_row(title, hint)
	_settings_rows.add_child(row)
	_focus_on_hover(row)
	row.pressed.connect(action)
	return row


func _connect_buttons() -> void:
	for button: Button in [_load_game_button, _new_game_button, _settings_button, _quit_button,
			_settings_back_button]:
		_focus_on_hover(button)
	_new_game_button.pressed.connect(GameManager.start_game)
	_load_game_button.pressed.connect(_open_load_screen)
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(get_tree().quit)
	_settings_back_button.pressed.connect(_close_settings)
	_keybind_page.closed.connect(_close_keybinds)


## Hovering a button focuses it, so mouse and keyboard share one highlight.
func _focus_on_hover(button: Button) -> void:
	button.mouse_entered.connect(button.grab_focus)


# =====================================================================
# Pages
# =====================================================================

func _show_page(page: Page, focus_target: Control, animate: bool = true) -> void:
	_set_import_hint(MAP_IMPORT_HINT)
	_page = page
	_main_page.visible = page == Page.MAIN
	_settings_page.visible = page == Page.SETTINGS
	_keybind_page.visible = page == Page.KEYBIND
	# The sub-pages are taller than the main panel and would run into the
	# footer, which only repeats what those pages already show.
	_footer.visible = page == Page.MAIN
	_nav.items = _page_items(page)
	if animate:
		var shown := _page_control(page)
		shown.modulate.a = 0.0
		create_tween().tween_property(shown, "modulate:a", 1.0, PAGE_FADE_TIME)
	if focus_target:
		focus_target.grab_focus()
	elif not _nav.items.is_empty():
		_nav.focus_first()


func _page_control(page: Page) -> Control:
	match page:
		Page.SETTINGS:
			return _settings_page
		Page.KEYBIND:
			return _keybind_page
	return _main_page


func _page_items(page: Page) -> Array[Control]:
	var items: Array[Control] = []
	match page:
		Page.MAIN:
			items.assign([_load_game_button, _new_game_button, _settings_button, _quit_button])
		Page.SETTINGS:
			items.assign([_map_row, _import_map_row, _theme_row, _credits_row, _difficulty_row])
			items.append_array(_common.rows())
			items.append(_settings_back_button)
		# Page.KEYBIND: the controls page runs its own navigation.
	return items


func _go_back() -> void:
	if _page == Page.SETTINGS:
		_close_settings()


func _open_settings() -> void:
	_show_page(Page.SETTINGS, _map_row)


func _close_settings() -> void:
	_show_page(Page.MAIN, _settings_button)


func _open_load_screen() -> void:
	get_tree().change_scene_to_file(LOAD_SCREEN_SCENE)


# =====================================================================
# Settings values
# =====================================================================

func _adjust_focused_value(direction: int) -> void:
	if _page != Page.SETTINGS:
		return
	var focused := _nav.focus_owner()
	if _common.adjust(focused, direction):
		return
	if focused == _map_row:
		_cycle_pool(direction)
	elif focused == _theme_row:
		_cycle_theme(direction)
	elif focused == _credits_row:
		_cycle_credits(direction)
	elif focused == _difficulty_row:
		_cycle_difficulty(direction)


func _cycle_pool(direction: int) -> void:
	if _available_pools.is_empty():
		return
	_pool_index = wrapi(_pool_index + direction, 0, _available_pools.size())
	var pool_id: String = _available_pools[_pool_index].id
	GameManager.set_map_pool(pool_id)
	InputSettings.save_map_pool(pool_id)
	_refresh_settings_values()


func _cycle_theme(direction: int) -> void:
	if _available_themes.is_empty():
		return
	_theme_index = wrapi(_theme_index + direction, 0, _available_themes.size())
	ThemeManager.load_theme(_available_themes[_theme_index])
	InputSettings.save_theme(_available_themes[_theme_index])
	_refresh_settings_values()


func _cycle_credits(direction: int) -> void:
	GameManager.max_credits = clampi(GameManager.max_credits + direction, MIN_CREDITS, MAX_CREDITS)
	InputSettings.save_max_credits(GameManager.max_credits)
	_refresh_settings_values()


func _cycle_difficulty(direction: int) -> void:
	GameManager.difficulty = clampi(GameManager.difficulty + direction, MIN_DIFFICULTY, MAX_DIFFICULTY)
	InputSettings.save_difficulty(GameManager.difficulty)
	_refresh_settings_values()


func _refresh_settings_values() -> void:
	var map_text := "(no maps found)"
	if not _available_pools.is_empty():
		var pool: LevelData.MapPool = _available_pools[_pool_index]
		var stage_count := LevelData.get_stage_count()
		map_text = "%s   ·   %d %s" % [pool.display_name, stage_count, "stage" if stage_count == 1 else "stages"]
	MenuRows.value_label(_map_row).text = map_text
	MenuRows.value_label(_theme_row).text = ThemeManager.get_theme_display_name()
	MenuRows.value_label(_credits_row).text = str(GameManager.max_credits)
	var difficulty := clampi(GameManager.difficulty, MIN_DIFFICULTY, MAX_DIFFICULTY)
	MenuRows.value_label(_difficulty_row).text = "%d   %s" % [difficulty, DIFFICULTY_NAMES[difficulty - 1]]
	MenuRows.arrow(_credits_row, "Left").disabled = GameManager.max_credits <= MIN_CREDITS
	MenuRows.arrow(_credits_row, "Right").disabled = GameManager.max_credits >= MAX_CREDITS
	MenuRows.arrow(_difficulty_row, "Left").disabled = difficulty <= MIN_DIFFICULTY
	MenuRows.arrow(_difficulty_row, "Right").disabled = difficulty >= MAX_DIFFICULTY
	_common.refresh()


## Called with the file chosen in the IMPORT MAP picker.
func _import_map_file(path: String) -> void:
	var result: Dictionary = LevelData.import_map_file(path)
	if not result.get("ok", false):
		_set_import_hint("Import failed: %s" % result.get("error", "unknown error"), true)
		return
	_available_pools = LevelData.get_available_pools()
	_pool_index = 0
	for i in _available_pools.size():
		if _available_pools[i].id == result["pool_id"]:
			_pool_index = i
			break
	GameManager.set_map_pool(result["pool_id"])
	InputSettings.save_map_pool(result["pool_id"])
	_refresh_settings_values()
	_map_row.grab_focus()
	var count: int = result["stage_count"]
	_set_import_hint("Imported %s   ·   %d %s   ·   selected" % [path.get_file(), count, "stage" if count == 1 else "stages"])


## Right-hand text of the IMPORT MAP row: the default hint, or the last result.
func _set_import_hint(text: String, is_error: bool = false) -> void:
	var hint := MenuRows.value_label(_import_map_row)
	hint.text = text
	if is_error:
		hint.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		hint.remove_theme_color_override("font_color")


func _refresh_footer() -> void:
	_footer_p1.text = "P1   %s" % InputSettings.get_player_controls_text("p1")
	_footer_p2.text = "P2   %s" % InputSettings.get_player_controls_text("p2")


# =====================================================================
# Controls page
# =====================================================================

## Opens [param player]'s controls page, on the GAMEPAD tab when a controller
## is driving the menus.
func _open_keybinds(player: String) -> void:
	_keybind_player = player
	_show_page(Page.KEYBIND, null)
	_keybind_page.open(player, _using_pad)


func _close_keybinds() -> void:
	_refresh_settings_values()
	_refresh_footer()
	_show_page(Page.SETTINGS, _common.controls_row(_keybind_player))
