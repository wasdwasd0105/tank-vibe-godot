extends Control
## Title screen: the main menu, its settings page, and each player's controls
## page (the ControlsPage the pause menu shows too). The settings have two tabs:
## GENERAL (the CommonSettings rows) and GAME (the map, and the GameSettings rows
## the pause menu shows too).
##
## Mouse: hovering a button focuses it, clicking activates it; the < > arrows
## change a setting, and a click on a tab picks it. Keyboard: P1/P2 movement keys
## or the arrow keys move the focus, fire / Enter / Space activate, left/right
## change a setting (or the tab, on the tab strip) and Esc goes back one page.
## Controller: the same with the D-pad or stick, A and B, and LB / RB switch tabs.

enum Page { MAIN, SETTINGS, KEYBIND }
enum SettingsTab { GENERAL, GAME }

const LOAD_SCREEN_SCENE := "res://scenes/load_screen.tscn"
const ONLINE_SCENE := "res://scenes/online_screen.tscn"
const PAGE_FADE_TIME := 0.15
const SETTINGS_TAB_TITLES: Array[String] = ["GENERAL", "GAME"]
const MAP_IMPORT_TITLE := "Import a Tank.exe map"
const MAP_IMPORT_HINT := "a Tank.exe Stage.dat"
const MAP_IMPORT_FILTERS: PackedStringArray = ["*.dat, *.DAT ; Tank.exe map files (Stage.dat)"]
const ERROR_COLOR := Color(1.0, 0.5, 0.45)

# --- Main page ---
@onready var _main_page: Control = %MainPanel
@onready var _new_game_button: Button = %NewGameButton
@onready var _online_button: Button = %OnlineButton
@onready var _load_game_button: Button = %LoadGameButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton

# --- Settings page ---
@onready var _settings_page: Control = %SettingsPanel
@onready var _game_rows: VBoxContainer = %GameRows
@onready var _settings_rows: VBoxContainer = %SettingsRows
@onready var _settings_back_button: Button = %SettingsBackButton

# --- Controls page ---
@onready var _keybind_page: ControlsPage = %KeybindPanel

# --- Footer ---
@onready var _footer: Control = $Footer
@onready var _footer_p1: Label = %FooterP1
@onready var _footer_p2: Label = %FooterP2
@onready var _version_label: Label = %VersionLabel

var _page: Page = Page.MAIN
var _nav: MenuFocus

# Settings rows, built in _ready(): the GENERAL tab's (sound, screen, language,
# each player's controls), and the GAME tab's map rows (the title's own) over
# the game's rules; the pause menu shares all but the map rows.
var _map_row: Button
var _import_map_row: Button
var _game: GameSettings
var _common: CommonSettings
var _tabs: SettingsTabs

var _available_pools: Array = []  # Array of LevelData.MapPool
var _pool_index: int = 0
var _map_picker: MenuFilePicker

# Controls page state
var _keybind_player: String = "p1"
## True while the menus are driven with a controller, so the controls page opens
## on its GAMEPAD tab.
var _using_pad: bool = false


func _ready() -> void:
	WindowManager.leave_game()  # the menus stay in the window
	_nav = MenuFocus.new(get_viewport())
	_map_picker = MenuFilePicker.new(self, MAP_IMPORT_TITLE, MAP_IMPORT_FILTERS, "map")
	_map_picker.file_picked.connect(_import_map_file)
	_load_saved_settings()
	_build_settings_rows()
	_connect_buttons()
	_refresh_settings_values()
	_refresh_footer()
	# The game's version, from the project settings (application/config/version).
	_version_label.text = "Ver. %s" % ProjectSettings.get_setting("application/config/version", "")
	_show_page(Page.MAIN, _load_game_button, false)
	SoundManager.attach_ui_sounds(self)


## The menus' language changed (the LANGUAGE row): the texts built from parts
## are rebuilt; the rest translate themselves.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_set_import_hint(MAP_IMPORT_HINT)
		_refresh_settings_values()


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
	if _page == Page.SETTINGS and _tabs.handle_shortcut(event):
		pass   # LB / RB: another tab
	elif MenuFocus.is_pressed(event, MenuFocus.UP_ACTIONS):
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

	GameManager.difficulty = InputSettings.get_saved_difficulty()


func _build_settings_rows() -> void:
	_map_row = _add_value_row("MAP", _cycle_pool)
	_import_map_row = _add_action_row("IMPORT MAP", MAP_IMPORT_HINT, _map_picker.open)
	_game = GameSettings.new(_game_rows)
	_common = CommonSettings.new(_settings_rows, false)
	_common.controls_requested.connect(_open_keybinds)
	_tabs = SettingsTabs.new(_settings_rows, SETTINGS_TAB_TITLES, [_settings_rows, _game_rows])
	_tabs.selected.connect(_on_settings_tab_selected)
	_tabs.fit_height()


## A GAME tab row of the title's own.
func _add_value_row(title: String, cycle: Callable) -> Button:
	var row := MenuRows.make_value_row(title)
	_game_rows.add_child(row)
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
	_game_rows.add_child(row)
	_focus_on_hover(row)
	row.pressed.connect(action)
	return row


func _connect_buttons() -> void:
	for button: Button in [_load_game_button, _new_game_button, _online_button, _settings_button,
			_quit_button, _settings_back_button]:
		_focus_on_hover(button)
	_new_game_button.pressed.connect(GameManager.start_game)
	_online_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(ONLINE_SCENE))
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
			items.assign([_load_game_button, _new_game_button, _online_button, _settings_button, _quit_button])
		Page.SETTINGS:
			if _tabs.strip.visible:
				items.append(_tabs.strip)
			if _tabs.current == SettingsTab.GAME:
				items.append_array([_map_row, _import_map_row])
				items.append_array(_game.rows())
			else:
				items.append_array(_common.rows())
			items.append(_settings_back_button)
		# Page.KEYBIND: the controls page runs its own navigation.
	return items


func _go_back() -> void:
	if _page == Page.SETTINGS:
		_close_settings()


## The settings open on their first tab, GENERAL, on its first row.
func _open_settings() -> void:
	_tabs.select(SettingsTab.GENERAL)
	_show_page(Page.SETTINGS, _common.sfx_row)


## Another tab: the focus stays on the strip if it was there, else goes to the
## tab's first row.
func _on_settings_tab_selected(tab: int) -> void:
	if _page != Page.SETTINGS:
		return
	_nav.items = _page_items(Page.SETTINGS)
	if _nav.focus_owner() != _tabs.strip:
		(_map_row if tab == SettingsTab.GAME else _common.sfx_row).grab_focus()


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
	if focused == _tabs.strip:
		_tabs.step(direction)
	elif _game.adjust(focused, direction) or _common.adjust(focused, direction):
		return
	elif focused == _map_row:
		_cycle_pool(direction)


func _cycle_pool(direction: int) -> void:
	if _available_pools.is_empty():
		return
	_pool_index = wrapi(_pool_index + direction, 0, _available_pools.size())
	var pool_id: String = _available_pools[_pool_index].id
	GameManager.set_map_pool(pool_id)
	InputSettings.save_map_pool(pool_id)
	_refresh_settings_values()


func _refresh_settings_values() -> void:
	var map_text := "(no maps found)"
	if not _available_pools.is_empty():
		var pool: LevelData.MapPool = _available_pools[_pool_index]
		var stage_count := LevelData.get_stage_count()
		var template := "%s   ·   %d stage" if stage_count == 1 else "%s   ·   %d stages"
		map_text = tr(template) % [pool.display_name, stage_count]
	MenuRows.value_label(_map_row).text = map_text
	_game.refresh()
	_common.refresh()


## Called with the file chosen in the IMPORT MAP picker.
func _import_map_file(path: String) -> void:
	var result: Dictionary = LevelData.import_map_file(path)
	if not result.get("ok", false):
		_set_import_hint(tr("Import failed: %s") % result.get("error", tr("unknown error")), true)
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
	var template := "Imported %s   ·   %d stage   ·   selected" if count == 1 \
			else "Imported %s   ·   %d stages   ·   selected"
	_set_import_hint(tr(template) % [path.get_file(), count])


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
