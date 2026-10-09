extends Control
## The pause screen, in the menus' style: RESUME, RESTART STAGE, SETTINGS, MAIN
## MENU and QUIT GAME over the dimmed stage, and beside them OPTIONS, switches
## flipped at once (Sean, 2026-10-10): PLAYER 2 (in a two-player game, one
## person plays on while player 2 sits out, their tank off the field and
## everything they had kept), SOUND (all of it, kept for next time), ONLINE
## (the game open to remote players, as ALLOW REMOTE PLAYERS; once on, every
## stage started after opens again, till it's switched off or the game closes:
## Net.keep_hosting) and FULLSCREEN. SETTINGS has three tabs. GENERAL changes the
## sound, fullscreen, the menus' language and each player's controls and
## vibration (the same controls page as the title screen). GAME changes the
## difficulty, the game's speed, whether the base can fall and the enemies'
## mines (GameSettings, as on the title screen). Both apply at once, without
## leaving the stage. ONLINE opens the game to remote players
## (docs/network_design.md):
## ALLOW REMOTE PLAYERS, the PORT and its type (TCP or UDP), a PASSWORD
## (optional), MAX PLAYERS (1 to 3, besides this machine's), the address to give
## them, and who is connected.
##
## Esc or Start opens it. Esc, B or Start go back a page, and from the first page
## resume. Mouse, keys and controller work as in the other menus; on the first
## page left / right go between the menu and the options, and fire flips an
## option; on the settings page left / right on the tab strip (or LB / RB)
## switch tabs, and a field is typed in after a click, or fire or Enter on its
## row, until Enter or Esc. It runs while the tree is paused (process mode
## ALWAYS).
##
## Once someone has joined, a host's menu has HOST: which tank each player may
## drive, and KICK. A host's menu pauses everyone's game. A client's menu
## (set_online_client) pauses nothing and has no GAME tab (the game is the
## host's); its ONLINE tab is how the host's game shows there: LAG COMPENSATION,
## SMOOTHING and the ping. It holds the client's players still while it's open,
## and MAIN MENU becomes LEAVE GAME, and no ONLINE option (hosting is the host's).
## PLAYER 2 is offline only: online, the seats do that.

signal resume_requested
## PLAYER 2 ON / OFF: [param player_id] in play ([param enabled]) or sitting out.
signal player_enabled_requested(player_id: int, enabled: bool)
signal restart_requested
signal main_menu_requested
signal exit_requested

enum Page { MAIN, SETTINGS, CONTROLS, HOST }
enum SettingsTab { GENERAL, GAME, ONLINE }

const PAGE_FADE_TIME := 0.12
const TAB_TITLES: Array[String] = ["GENERAL", "GAME", "ONLINE"]
## The ONLINE tab's names are longer than the GENERAL tab's (ALLOW REMOTE PLAYERS).
const ONLINE_NAME_WIDTH := 350.0
const PASSWORD_MAX := 32
const PLAYER_LINE_HEIGHT := 34.0
const ERROR_COLOR := Color(1.0, 0.5, 0.45)
## Who may drive what, as the HOST page's rows cycle it: both, P1 only, P2 only, neither.
const DRIVE_CHOICES: Array = [[true, true], [true, false], [false, true], [false, false]]
const DRIVE_NAMES: Array[String] = ["P1 + P2", "P1 ONLY", "P2 ONLY", "WATCH ONLY"]

@onready var _main_page: Control = %MainPage
@onready var _main_panel: Control = %MainPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _restart_button: Button = %RestartButton
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _quit_button: Button = %QuitButton
# The OPTIONS beside the menu.
@onready var _options_panel: Control = %OptionsPanel
@onready var _p2_button: Button = %PlayerTwoButton
@onready var _sound_button: Button = %SoundButton
@onready var _online_button: Button = %OnlineButton
@onready var _fullscreen_button: Button = %FullscreenButton
@onready var _options_note: Label = %OptionsNote
@onready var _settings_panel: Control = %SettingsPanel
@onready var _settings_rows: VBoxContainer = %SettingsRows
@onready var _settings_back_button: Button = %SettingsBackButton
@onready var _controls: ControlsPage = %ControlsPage

var _page: Page = Page.MAIN
var _nav: MenuFocus
var _game: GameSettings
var _common: CommonSettings
var _can_open: bool = true  # off during game over / stage clear
## True while a controller drives the menu, so the controls page opens on its
## GAMEPAD tab.
var _using_pad: bool = false
## A client's menu: nothing pauses, and leaving leaves the host's game.
var _online_client := false

# The settings page's tabs: GAME (the GameSettings rows), GENERAL (the
# CommonSettings rows) and ONLINE.
var _tabs: SettingsTabs
var _game_rows: VBoxContainer
var _online_tab: VBoxContainer
var _allow_row: Button
var _port_row: Button
var _port_type_row: Button
var _password_row: Button
var _max_row: Button
var _address_row: Button
var _players_box: VBoxContainer
var _players_caption: Label
var _player_lines: Array[Label] = []   # who is connected, one line each
# A client's ONLINE tab instead: how the host's game shows here.
var _lag_row: Button
var _smoothing_row: Button
var _ping_line: Label
var _client_refresh := 0.0             # till the ping and AUTO's figure are shown afresh
var _online_note: Label
## The field being typed in, or null.
var _typing: LineEdit = null

# The host's HOST page, once someone has joined.
var _host_button: Button
var _host_panel: PanelContainer
var _host_rows: VBoxContainer
var _host_back_button: Button
var _drive_rows: Dictionary = {}   # peer id -> row
var _kick_rows: Dictionary = {}    # peer id -> row


func _ready() -> void:
	visible = false
	_nav = MenuFocus.new(get_viewport())
	_common = CommonSettings.new(_settings_rows, true)
	_common.controls_requested.connect(_open_controls)
	for button: Button in [_resume_button, _settings_button, _restart_button, _main_menu_button, _quit_button,
			_p2_button, _sound_button, _online_button, _fullscreen_button]:
		button.mouse_entered.connect(button.grab_focus)   # hover focuses, as in every menu
	_focus_on_hover(_settings_back_button)
	_resume_button.pressed.connect(_resume)
	_p2_button.pressed.connect(_toggle_p2)
	_sound_button.pressed.connect(_toggle_sound)
	_online_button.pressed.connect(_toggle_online)
	_fullscreen_button.pressed.connect(_toggle_fullscreen)
	WindowManager.fullscreen_changed.connect(_refresh_fullscreen)
	_settings_button.pressed.connect(_open_settings)
	_restart_button.pressed.connect(_leave.bind(restart_requested))
	_main_menu_button.pressed.connect(_leave.bind(main_menu_requested))
	_quit_button.pressed.connect(_leave.bind(exit_requested))
	_settings_back_button.pressed.connect(_close_settings)
	_controls.closed.connect(_close_controls)
	_build_settings_tabs()
	_build_host_page()
	Net.session_changed.connect(_on_session_changed)
	Net.peer_ping_changed.connect(func(_peer: int) -> void:
		if visible and _page == Page.SETTINGS and _tabs.current == SettingsTab.ONLINE:
			_refresh_player_lines())
	SoundManager.attach_ui_sounds(self)


func set_can_open(value: bool) -> void:
	_can_open = value


## The menus' language changed (its settings page): the options' lines, the
## difficulty's name and the ONLINE tab's are built from parts, so they are
## rebuilt; the rest translate themselves.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_options()
		_game.refresh()
		_common.refresh()
		_refresh_online_tab()


func _input(event: InputEvent) -> void:
	var device := MenuFocus.device_of(event)
	if device >= 0:
		_using_pad = device == 1
	if not visible:
		if _can_open and event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_open()
		return
	if _typing != null:
		# The field has the keys; only Esc (or the pad's B) hands them back.
		if event.is_action_pressed(&"ui_cancel") or (event is InputEventJoypadButton and event.pressed):
			_end_typing()
			get_viewport().set_input_as_handled()
		return
	# The controls page handles its own input (it gets each event first).
	if _page == Page.CONTROLS or not MenuFocus.is_navigation_event(event):
		return
	# Leaving can change scene and take this node out of the tree; keep the viewport.
	var viewport := get_viewport()
	if _page == Page.MAIN:
		_nav.items = _page_items(Page.MAIN)  # (the column the focus is in: the mouse may have moved it)
	if _page == Page.SETTINGS and _tabs.handle_shortcut(event):
		pass   # LB / RB: another tab
	elif MenuFocus.is_pressed(event, MenuFocus.UP_ACTIONS):
		_nav.move(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.DOWN_ACTIONS):
		_nav.move(1)
	elif MenuFocus.is_pressed(event, MenuFocus.LEFT_ACTIONS):
		_adjust(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.RIGHT_ACTIONS):
		_adjust(1)
	elif MenuFocus.is_pressed(event, MenuFocus.ACCEPT_ACTIONS):
		_nav.activate()
	elif MenuFocus.is_pressed(event, MenuFocus.BACK_ACTIONS):
		_go_back()
	else:
		return
	viewport.set_input_as_handled()


## Hovering takes the focus, as in every menu, unless a field is being typed
## in: that would take the keys away from it.
func _focus_on_hover(control: Control) -> void:
	control.mouse_entered.connect(func() -> void:
		if _typing == null:
			control.grab_focus())


## A client's menu (Net), or the usual one.
func set_online_client(on: bool) -> void:
	_online_client = on
	_restart_button.visible = not on
	_online_button.visible = not on
	_main_menu_button.text = "LEAVE GAME" if on else "MAIN MENU"
	(_main_panel.get_node("Items/Header") as Label).text = "MENU" if on else "PAUSED"
	# The game's rules are the host's own machine's, and so is hosting: a
	# client's ONLINE tab is how the host's game shows there instead.
	_tabs.offer(SettingsTab.GAME, not on)
	for control: Control in _host_online_controls():
		control.visible = not on
	for control: Control in [_lag_row, _smoothing_row, _ping_line]:
		control.visible = on
	_refresh_online_tab()


func _open() -> void:
	visible = true
	if _online_client:
		Net.input_blocked = true  # the keys drive this menu, not the tank
	else:
		get_tree().paused = true
	_refresh_host_button()
	_game.refresh()
	_common.refresh()
	_options_note.text = ""
	_refresh_options()
	_show_page(Page.MAIN, _resume_button)


## The OPTIONS as things are.
func _refresh_options() -> void:
	_refresh_p2()
	_refresh_sound()
	_refresh_online_option()
	_refresh_fullscreen(WindowManager.is_fullscreen())


## "NAME: ON" or "NAME: OFF".
static func _switch_text(name_template: String, on: bool) -> String:
	return TranslationServer.translate(name_template) % TranslationServer.translate("ON" if on else "OFF")


## PLAYER 2 shows only when the game has both players, and says whether player 2
## is in play. It can't be switched off while player 1 is out of lives: nobody
## would be left on the field.
func _refresh_p2() -> void:
	_p2_button.visible = GameManager.player_active[0] and GameManager.player_active[1] \
			and not Net.is_online()
	var off: bool = GameManager.player_disabled[1]
	_p2_button.text = tr("PLAYER 2: %s") % tr("OFF" if off else "ON")
	_p2_button.disabled = not off and GameManager.player_lives[0] < 0


## FULLSCREEN, for the window as it is ([param on]: fullscreen), however it
## was switched (here, the settings' row, F11).
func _refresh_fullscreen(on: bool) -> void:
	_fullscreen_button.text = _switch_text("FULLSCREEN: %s", on)


## Switches fullscreen and stays on the page, the stage still paused.
func _toggle_fullscreen() -> void:
	WindowManager.set_fullscreen(not WindowManager.is_fullscreen())


func _refresh_sound() -> void:
	_sound_button.text = _switch_text("SOUND: %s", SoundManager.is_sound_on())


## All the sound on or off, kept for next time (SoundManager.set_sound_on).
func _toggle_sound() -> void:
	SoundManager.set_sound_on(not SoundManager.is_sound_on())
	_refresh_sound()


## ONLINE: the game open to remote players, as the ONLINE tab's ALLOW REMOTE
## PLAYERS says (a client's menu has none).
func _refresh_online_option() -> void:
	_online_button.text = _switch_text("ONLINE: %s", _hosting_open())


## Opens the game to remote players, or closes it to newcomers, as ALLOW
## REMOTE PLAYERS does; a reason it couldn't open shows under the options.
func _toggle_online() -> void:
	_options_note.text = _switch_hosting()
	_refresh_online_option()


func _hosting_open() -> bool:
	return Net.is_host() and not Net.lock_new


## Takes player 2 out of the stage, or brings them back, and stays on the page.
func _toggle_p2() -> void:
	if _p2_button.disabled:
		return
	player_enabled_requested.emit(1, GameManager.player_disabled[1])
	_refresh_p2()


func _resume() -> void:
	_close()
	resume_requested.emit()


## Closes the menu, unpauses, and hands [param request] to the game.
func _leave(request: Signal) -> void:
	_close()
	request.emit()


func _close() -> void:
	visible = false
	_page = Page.MAIN
	if _online_client:
		Net.input_blocked = false  # (the host's pause, if any, is the host's to end)
	else:
		get_tree().paused = false


func _go_back() -> void:
	match _page:
		Page.MAIN:
			_resume()
		Page.SETTINGS:
			_close_settings()
		Page.HOST:
			_close_host()


func _show_page(page: Page, focus_target: Control) -> void:
	_page = page
	_main_page.visible = page == Page.MAIN
	_settings_panel.visible = page == Page.SETTINGS
	_controls.visible = page == Page.CONTROLS
	_host_panel.visible = page == Page.HOST
	if focus_target:
		focus_target.grab_focus()  # (first: the first page's column goes by it)
	_nav.items = _page_items(page)
	var shown: Control = [_main_page, _settings_panel, _controls, _host_panel][page]
	shown.modulate.a = 0.0
	create_tween().tween_property(shown, "modulate:a", 1.0, PAGE_FADE_TIME)


func _page_items(page: Page) -> Array[Control]:
	var items: Array[Control] = []
	match page:
		Page.MAIN:
			# The column the focus is in: the menu, or the options beside it.
			var options := _option_items()
			return options if options.has(_nav.focus_owner()) else _menu_items()
		Page.SETTINGS:
			if _tabs.strip.visible:
				items.append(_tabs.strip)
			match _tabs.current:
				SettingsTab.GAME:
					items.append_array(_game.rows())
				SettingsTab.GENERAL:
					items.append_array(_common.rows())
				SettingsTab.ONLINE:
					if _online_client:
						items.append_array([_lag_row, _smoothing_row])
					else:
						items.append_array([_allow_row, _port_row, _port_type_row, _password_row, _max_row, _address_row])
			items.append(_settings_back_button)
		Page.HOST:
			for peer: int in _drive_rows:
				items.append(_drive_rows[peer])
			for peer: int in _kick_rows:
				items.append(_kick_rows[peer])
			items.append(_host_back_button)
		# Page.CONTROLS: the controls page runs its own navigation.
	return items


## The first page's menu, top to bottom.
func _menu_items() -> Array[Control]:
	var items: Array[Control] = []
	for button: Button in [_resume_button, _restart_button, _settings_button, _host_button,
			_main_menu_button, _quit_button]:
		if button.visible:
			items.append(button)
	return items


## The OPTIONS beside it, top to bottom.
func _option_items() -> Array[Control]:
	var items: Array[Control] = []
	for button: Button in [_p2_button, _sound_button, _online_button, _fullscreen_button]:
		if button.visible:
			items.append(button)
	return items


## Left / right on the first page: from the menu over to the options
## ([param direction] 1), or back (-1), to the one level with the one focused.
func _switch_column(direction: int) -> void:
	var focused := _nav.focus_owner()
	var to := _option_items() if direction > 0 else _menu_items()
	if to.is_empty() or to.has(focused):
		return
	var level := focused.get_global_rect().get_center().y if focused else 0.0
	var nearest: Control = to[0]
	for item: Control in to:
		if absf(item.get_global_rect().get_center().y - level) < absf(nearest.get_global_rect().get_center().y - level):
			nearest = item
	nearest.grab_focus()
	_nav.items = to


func _adjust(direction: int) -> void:
	var focused := _nav.focus_owner()
	match _page:
		Page.HOST:
			_adjust_host(focused, direction)
		Page.SETTINGS:
			if focused == _tabs.strip:
				_tabs.step(direction)
			elif focused == _allow_row:
				_toggle_hosting(direction)
			elif focused == _port_type_row:
				_cycle_port_type(direction)
			elif focused == _max_row:
				_cycle_max_players(direction)
			elif focused == _lag_row:
				_toggle_lag_compensation(direction)
			elif focused == _smoothing_row:
				_cycle_smoothing(direction)
			elif not _game.adjust(focused, direction):
				_common.adjust(focused, direction)
		Page.MAIN:
			_switch_column(direction)


## The settings open on their first tab, GENERAL (a client's menu has only
## that one), on its first row.
func _open_settings() -> void:
	_tabs.select(SettingsTab.GENERAL)
	_game.refresh()
	_common.refresh()
	_show_page(Page.SETTINGS, _first_settings_row())


func _close_settings() -> void:
	_show_page(Page.MAIN, _settings_button)


func _open_controls(player: String) -> void:
	_show_page(Page.CONTROLS, null)
	_controls.open(player, _using_pad)


func _close_controls() -> void:
	_common.refresh()
	_show_page(Page.SETTINGS, _common.controls_row(_controls.get_player()))


# =====================================================================
# The settings page's tabs
# =====================================================================

## The GAME tab's rows under the GENERAL tab's, the ONLINE tab's under them,
## and the tab strip over all three (SettingsTabs: only the picked tab's show,
## all at the height of the tallest, so the page keeps its size).
func _build_settings_tabs() -> void:
	var layout := _settings_rows.get_parent()
	_game_rows = VBoxContainer.new()
	_game_rows.name = "GameRows"
	_game_rows.add_theme_constant_override(&"separation", 3)
	layout.add_child(_game_rows)
	layout.move_child(_game_rows, _settings_rows.get_index() + 1)
	_game = GameSettings.new(_game_rows)
	_build_online_tab()
	_tabs = SettingsTabs.new(_settings_rows, TAB_TITLES, [_settings_rows, _game_rows, _online_tab],
			func() -> bool: return _typing == null)
	_tabs.selected.connect(_on_settings_tab_selected)
	_tabs.fit_height()


## The ONLINE tab's rows, under the GAME tab's.
func _build_online_tab() -> void:
	var layout := _settings_rows.get_parent()
	_online_tab = VBoxContainer.new()
	_online_tab.name = "OnlineTab"
	_online_tab.visible = false
	_online_tab.add_theme_constant_override(&"separation", 3)
	layout.add_child(_online_tab)
	layout.move_child(_online_tab, _game_rows.get_index() + 1)
	_allow_row = _add_online_value_row("ALLOW REMOTE PLAYERS", _toggle_hosting)
	_port_row = _add_online_field_row("PORT", 5, str(Net.DEFAULT_PORT))
	_port_type_row = _add_online_value_row("PORT TYPE", _cycle_port_type)
	_password_row = _add_online_field_row("PASSWORD", PASSWORD_MAX, "OPTIONAL")
	MenuRows.field(_password_row).secret = true
	_max_row = _add_online_value_row("MAX PLAYERS", _cycle_max_players)
	_address_row = MenuRows.make_action_row("YOUR ADDRESS", "")
	_address_row.pressed.connect(_copy_address)
	_add_online_row(_address_row)
	# A client's, in their place (set_online_client).
	_lag_row = _add_online_value_row("LAG COMPENSATION", _toggle_lag_compensation)
	_smoothing_row = _add_online_value_row("SMOOTHING", _cycle_smoothing)
	for row: Button in [_lag_row, _smoothing_row]:
		row.visible = false
		row.focus_entered.connect(_set_online_note.bind(""))  # what it does

	# Who is connected: a caption and a line a player, room for all three.
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override(&"separation", 0)
	_online_tab.add_child(_players_box)
	_players_caption = _online_label(&"HintLabel")
	_players_box.add_child(_players_caption)
	for i in Net.MAX_CLIENTS:
		var line := _online_label(&"ValueLabel")
		line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # names, as typed
		line.custom_minimum_size.y = PLAYER_LINE_HEIGHT
		_players_box.add_child(line)
		_player_lines.append(line)
	# A client's: the trip to the host and back.
	_ping_line = _online_label(&"ValueLabel")
	_ping_line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # composed from parts
	_ping_line.custom_minimum_size.y = PLAYER_LINE_HEIGHT
	_ping_line.visible = false
	_online_tab.add_child(_ping_line)
	_online_note = _online_label(&"HintLabel")
	_online_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_online_tab.add_child(_online_note)
	_refresh_online_tab()


func _add_online_row(row: Button) -> void:
	MenuRows.name_label(row).custom_minimum_size.x = ONLINE_NAME_WIDTH
	_online_tab.add_child(row)
	_focus_on_hover(row)


## "NAME   <   value   >": [param cycle] takes the step, -1 or 1, as on the
## GENERAL tab.
func _add_online_value_row(title: String, cycle: Callable) -> Button:
	var row := MenuRows.make_value_row(title)
	_add_online_row(row)
	row.pressed.connect(cycle.bind(1))
	for side: String in ["Left", "Right"]:
		var arrow := MenuRows.arrow(row, side)
		arrow.pressed.connect(cycle.bind(-1 if side == "Left" else 1))
		arrow.mouse_entered.connect(func() -> void:
			if _typing == null:
				row.grab_focus())
	return row


## "TITLE   [ text field ]": pressing the row (fire, Enter, a click) types in it.
func _add_online_field_row(title: String, max_length: int, placeholder: String) -> Button:
	var row := MenuRows.make_field_row(title, max_length, placeholder)
	_add_online_row(row)
	var field := MenuRows.field(row)
	field.focus_entered.connect(func() -> void:
		_typing = field
		field.caret_column = field.text.length())
	field.focus_exited.connect(_on_field_left.bind(row))
	field.text_submitted.connect(func(_text: String) -> void: _end_typing())
	row.pressed.connect(_begin_typing.bind(row))
	return row


func _online_label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Another tab shows: the focus stays on the strip if it was there, else goes
## to the tab's first row.
func _on_settings_tab_selected(tab: int) -> void:
	if tab == SettingsTab.ONLINE:
		_set_online_note("")
		_refresh_online_tab()
	if _page != Page.SETTINGS:
		return
	_nav.items = _page_items(Page.SETTINGS)
	if _nav.focus_owner() != _tabs.strip:
		_first_settings_row().grab_focus()


## The first row of the tab showing.
func _first_settings_row() -> Button:
	match _tabs.current:
		SettingsTab.GAME:
			return _game.difficulty_row
		SettingsTab.ONLINE:
			return _lag_row if _online_client else _allow_row
	return _common.sfx_row


## The host's ONLINE tab, all but its note (a client's has its own rows).
func _host_online_controls() -> Array[Control]:
	return [_allow_row, _port_row, _port_type_row, _password_row, _max_row, _address_row, _players_box]


# =====================================================================
# The ONLINE tab
# =====================================================================

## The rows as things are: open or not, the port (fixed while open), the
## password, the most players, this machine's address, and who is here.
func _refresh_online_tab() -> void:
	if _online_tab == null:
		return
	if _online_client:
		_refresh_client_tab()
		return
	var hosting := Net.is_host()
	MenuRows.value_label(_allow_row).text = "ON" if hosting and not Net.lock_new else "OFF"
	var port_field := MenuRows.field(_port_row)
	if _typing != port_field:
		port_field.text = str(Net.port if hosting else InputSettings.get_online_port())
	port_field.editable = not hosting
	MenuRows.value_label(_port_type_row).text = _port_type()
	for side: String in ["Left", "Right"]:
		MenuRows.arrow(_port_type_row, side).disabled = hosting
	var password_field := MenuRows.field(_password_row)
	if _typing != password_field:
		password_field.text = InputSettings.get_host_password()
	var most := _max_players()
	MenuRows.value_label(_max_row).text = tr("%d + YOU") % most
	MenuRows.arrow(_max_row, "Left").disabled = most <= 1
	MenuRows.arrow(_max_row, "Right").disabled = most >= Net.MAX_CLIENTS
	MenuRows.value_label(_address_row).text = _address()
	_players_caption.text = tr("CONNECTED PLAYERS   %d / %d") % [Net.client_ids().size(), most]
	_refresh_player_lines()
	if _online_note.text.is_empty() or not _online_note.has_theme_color_override(&"font_color"):
		_set_online_note("")


## A line for each player connected (none unless hosting).
func _refresh_player_lines() -> void:
	var clients := Net.client_ids()
	for i in _player_lines.size():
		var line := _player_lines[i]
		line.remove_theme_color_override(&"font_color")
		if i < clients.size():
			line.text = _player_line(clients[i])
		elif i == 0 and clients.is_empty():
			line.text = tr("NO ONE YET")
			line.add_theme_color_override(&"font_color", Color(0.62, 0.62, 0.65))
		else:
			line.text = ""


## "NAME   ·   DRIVING P2   ·   84 ms", or WATCHING; the trip to them and back
## once they have timed it.
func _player_line(peer: int) -> String:
	var doing := tr("WATCHING")
	for tank in 2:
		var key: int = PlayerInput.seats[tank]
		if key != PlayerInput.NO_SEAT and PlayerInput.controller_peer(key) == peer:
			doing = tr("DRIVING P%d") % (tank + 1)
			break
	var line := "%s   ·   %s" % [Net.peer_name(peer), doing]
	var ping := Net.peer_ping(peer)
	if ping > 0:
		line += "   ·   %d ms" % ping
	return line


## What others type to join: this machine's LAN address and the port.
func _address() -> String:
	var addresses := Net.local_addresses()
	var port_number: int = Net.port if Net.is_host() else InputSettings.get_online_port()
	return "%s : %d" % [addresses[0] if not addresses.is_empty() else "127.0.0.1", port_number]


func _max_players() -> int:
	return Net.max_clients if Net.is_host() else InputSettings.get_host_max_players()


## The line under the tab: [param text] (red when [param is_error]), or, given
## "", what the tab is doing now.
func _set_online_note(text: String, is_error: bool = false) -> void:
	if is_error:
		_online_note.add_theme_color_override(&"font_color", ERROR_COLOR)
	else:
		_online_note.remove_theme_color_override(&"font_color")
	if text.is_empty():
		if _online_client:
			text = _client_note()
		elif not Net.is_host():
			text = tr("Turn ALLOW REMOTE PLAYERS on to open this game to others.")
		elif Net.lock_new:
			text = tr("Nobody new can join. The players here stay.")
		else:
			text = tr("Open: others join from ONLINE BATTLE at YOUR ADDRESS.")
	_online_note.text = text


# =====================================================================
# A client's ONLINE tab: how the host's game shows here
# =====================================================================

## LAG COMPENSATION, SMOOTHING (AUTO with how far behind the host that comes
## to now) and the ping, as things are.
func _refresh_client_tab() -> void:
	MenuRows.value_label(_lag_row).text = "ON" if InputSettings.get_lag_compensation() else "OFF"
	var chosen := InputSettings.get_smoothing()
	var choices := InputSettings.SMOOTHING_CHOICES
	if chosen == 0:
		var world := NetClientWorld.of(get_tree())
		var shown := world.render_delay() if world else NetClientWorld.DELAY_MS
		MenuRows.value_label(_smoothing_row).text = tr("AUTO (%d ms)") % roundi(shown)
	else:
		MenuRows.value_label(_smoothing_row).text = "%d ms" % chosen
	MenuRows.arrow(_smoothing_row, "Left").disabled = chosen == choices[0]
	MenuRows.arrow(_smoothing_row, "Right").disabled = chosen == choices[-1]
	var ping := roundi(Net.ping_ms)
	_ping_line.text = tr("PING   %s") % ("%d ms" % ping if ping > 0 else "—")
	if not _online_note.has_theme_color_override(&"font_color"):
		_set_online_note("")


## What the client's row with the focus does (LAG COMPENSATION's, off it).
func _client_note() -> String:
	if _nav.focus_owner() == _smoothing_row:
		return tr("How far behind the host the game is shown, to keep it smooth.") + "\n" \
				+ tr("Less: quicker, but jerky on a poor connection.")
	return tr("ON: your tank and its shots answer your keys at once.") + "\n" \
			+ tr("OFF: you see exactly what the host does, a little late.")


## LAG COMPENSATION: on, this machine's own tanks and their shots answer its
## keys at once; off, it shows the host's game as it is (NetClientWorld).
func _toggle_lag_compensation(_direction: int = 1) -> void:
	InputSettings.set_lag_compensation(not InputSettings.get_lag_compensation())
	_refresh_client_tab()


## SMOOTHING: AUTO, or how far behind the host's clock the game is shown, a
## step at a time.
func _cycle_smoothing(direction: int) -> void:
	var choices := InputSettings.SMOOTHING_CHOICES
	var at := choices.find(InputSettings.get_smoothing())
	InputSettings.set_smoothing(choices[clampi(at + direction, 0, choices.size() - 1)])
	_refresh_client_tab()


## The ping and AUTO's figure change as the game goes: a client's ONLINE tab
## shows them afresh a few times a second.
func _process(delta: float) -> void:
	if not (_online_client and visible and _page == Page.SETTINGS and _tabs.current == SettingsTab.ONLINE):
		return
	_client_refresh -= delta
	if _client_refresh <= 0.0:
		_client_refresh = 0.25
		_refresh_client_tab()


## ALLOW REMOTE PLAYERS (and the ONLINE option, _toggle_online).
func _toggle_hosting(_direction: int = 1) -> void:
	var why_not := _switch_hosting()
	_set_online_note(why_not, not why_not.is_empty())


## On opens the game to others (on the port, with the password and the most
## players set on the ONLINE tab), or lets newcomers in again; and every stage
## started after opens again, till it's switched off or the game closes (Sean,
## 2026-10-10: "keep it on until user turn off the game"; Net.keep_hosting).
## Off turns newcomers away; with nobody connected, it also closes the game to
## the network and play goes on offline. Returns why it couldn't open, or "".
func _switch_hosting() -> String:
	if Net.is_host():
		if Net.lock_new:
			Net.set_lock_new(false)
			Net.keep_hosting = true
		else:
			Net.keep_hosting = false
			if Net.client_ids().is_empty():
				Net.leave()
			else:
				Net.set_lock_new(true)
	elif Net.host_from_settings() != OK:
		_refresh_online_tab()
		_refresh_online_option()
		return Net.end_text(Net.END_PORT)
	else:
		Net.keep_hosting = true
	_refresh_online_tab()
	_refresh_online_option()
	return ""


## PORT TYPE: TCP or UDP, kept for next time. Players joining find out which by
## themselves. Fixed while the game is open, as the port is.
func _cycle_port_type(_direction: int) -> void:
	if Net.is_host():
		_set_online_note(tr("The port type can't change while the game is open."), true)
		return
	InputSettings.save_host_port_type("TCP" if InputSettings.get_host_port_type() == "UDP" else "UDP")
	_set_online_note("")
	_refresh_online_tab()


## The open game's transport, else the one it would open with.
func _port_type() -> String:
	return Net.TRANSPORT_NAMES[Net.transport] if Net.is_host() else InputSettings.get_host_port_type()


## MAX PLAYERS: 1 to 3 others besides this machine's players, kept for next time.
func _cycle_max_players(direction: int) -> void:
	var most := clampi(_max_players() + direction, 1, Net.MAX_CLIENTS)
	InputSettings.save_host_settings(InputSettings.get_online_port(), InputSettings.get_host_password(), most)
	if Net.is_host():
		Net.set_max_clients(most)
	_refresh_online_tab()


func _copy_address() -> void:
	DisplayServer.clipboard_set(_address().replace(" ", ""))
	MenuRows.value_label(_address_row).text = tr("COPIED: %s") % _address()


# --- Typing in the fields ---

## Pressing a field's row types in it; the port is fixed while the game is open.
func _begin_typing(row: Button) -> void:
	if row == _port_row and Net.is_host():
		_set_online_note(tr("The port can't change while the game is open."), true)
		return
	MenuRows.field(row).grab_focus()


## Enter, Esc or the pad's B: the menu has the keys again.
func _end_typing() -> void:
	if _typing == null:
		return
	var row := _typing.get_parent().get_parent() as Button
	_typing.release_focus()
	row.grab_focus()


## A field was left: a port from 1 to 65535 is kept (another goes back to what
## it was), and the password exactly as typed, for this game too if it's open.
func _on_field_left(row: Button) -> void:
	var field := MenuRows.field(row)
	if _typing == field:
		_typing = null
	if row == _port_row:
		var value := field.text.strip_edges()
		if value.is_valid_int() and int(value) >= 1 and int(value) <= 65535:
			InputSettings.save_host_settings(int(value), InputSettings.get_host_password(), _max_players())
			_set_online_note("")
		else:
			_set_online_note(tr("That port isn't a number from 1 to 65535."), true)
	elif row == _password_row:
		InputSettings.save_host_settings(InputSettings.get_online_port(), field.text, _max_players())
		if Net.is_host():
			Net.set_password(field.text)
	_refresh_online_tab()


# =====================================================================
# The host's HOST page
# =====================================================================

## HOST on the first page (shown once someone has joined), and its page, built
## like the settings page: a panel, its header, the rows and BACK.
func _build_host_page() -> void:
	_host_button = Button.new()
	_host_button.name = "HostButton"
	_host_button.theme_type_variation = &"MenuItemButton"
	_host_button.text = "HOST"
	_host_button.visible = false
	_host_button.mouse_entered.connect(_host_button.grab_focus)
	_host_button.pressed.connect(_open_host)
	var items := _main_panel.get_node("Items")
	items.add_child(_host_button)
	items.move_child(_host_button, _main_menu_button.get_index())

	_host_panel = PanelContainer.new()
	_host_panel.name = "HostPanel"
	_host_panel.visible = false
	_host_panel.custom_minimum_size = Vector2(880, 0)
	_host_panel.theme_type_variation = &"MenuPanel"
	_settings_panel.get_parent().add_child(_host_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 10)
	_host_panel.add_child(layout)
	var header := Label.new()
	header.theme_type_variation = &"HeaderLabel"
	header.text = "HOST"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(header)
	_host_rows = VBoxContainer.new()
	_host_rows.add_theme_constant_override(&"separation", 3)
	layout.add_child(_host_rows)
	_host_back_button = Button.new()
	_host_back_button.theme_type_variation = &"MenuItemButton"
	_host_back_button.text = "BACK"
	_host_back_button.mouse_entered.connect(_host_back_button.grab_focus)
	_host_back_button.pressed.connect(_close_host)
	layout.add_child(_host_back_button)


## HOST shows on a host's first page while anyone is connected.
func _refresh_host_button() -> void:
	_host_button.visible = Net.is_host() and not Net.client_ids().is_empty()


func _open_host() -> void:
	_rebuild_host_rows()
	_show_page(Page.HOST, _page_items(Page.HOST)[0])


func _close_host() -> void:
	_show_page(Page.MAIN, _host_button if _host_button.visible else _settings_button)


## Players came or went, or a setting changed: the pages showing it follow.
func _on_session_changed() -> void:
	var host_was_shown := _host_button.visible
	_refresh_host_button()
	_refresh_online_option()
	if not visible:
		return
	match _page:
		Page.MAIN:
			if host_was_shown != _host_button.visible:
				var focused := _nav.focus_owner()
				_nav.items = _page_items(Page.MAIN)
				if focused == _host_button or focused == null:
					_settings_button.grab_focus()
		Page.SETTINGS:
			if _tabs.current == SettingsTab.ONLINE:
				_refresh_online_tab()
		Page.HOST:
			if not _host_button.visible:
				_close_host()  # the last one left
				return
			var focused := _nav.focus_owner()
			var at := _nav.items.find(focused)
			_rebuild_host_rows()
			_nav.items = _page_items(Page.HOST)
			_nav.items[clampi(at, 0, _nav.items.size() - 1)].grab_focus()


## A row per player for what they may drive (the host's own too, so it can hand
## a tank over) and a KICK per client.
func _rebuild_host_rows() -> void:
	for child in _host_rows.get_children():
		_host_rows.remove_child(child)
		child.queue_free()
	_drive_rows.clear()
	_kick_rows.clear()
	var caption := Label.new()
	caption.theme_type_variation = &"HintLabel"
	caption.text = "WHO MAY DRIVE WHICH TANK"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_rows.add_child(caption)
	for peer: int in Net.peers:
		var row := MenuRows.make_value_row(Net.peer_name(peer))
		MenuRows.name_label(row).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # a name
		_add_host_row(row)
		row.pressed.connect(_cycle_drive.bind(peer, 1))
		MenuRows.arrow(row, "Left").pressed.connect(_cycle_drive.bind(peer, -1))
		MenuRows.arrow(row, "Right").pressed.connect(_cycle_drive.bind(peer, 1))
		_drive_rows[peer] = row
	for peer: int in Net.peers:
		if peer == 1:
			continue
		var kick := MenuRows.make_action_row("KICK", Net.peer_name(peer))
		MenuRows.value_label(kick).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		kick.pressed.connect(Net.kick.bind(peer))
		_add_host_row(kick)
		_kick_rows[peer] = kick
	SoundManager.attach_ui_sounds(_host_rows)
	_refresh_host_values()


func _add_host_row(row: Button) -> void:
	_host_rows.add_child(row)
	row.mouse_entered.connect(row.grab_focus)
	for side in ["Left", "Right"]:
		var arrow := MenuRows.layout_of(row).get_node_or_null(side) as Button
		if arrow:
			arrow.mouse_entered.connect(row.grab_focus)


func _refresh_host_values() -> void:
	for peer: int in _drive_rows:
		var allow: Array = Net.peers.get(peer, {}).get("allow", [false, false])
		var choice := DRIVE_CHOICES.find([bool(allow[0]), bool(allow[1])])
		var text: String = tr(DRIVE_NAMES[maxi(choice, 0)])
		for tank in 2:
			var key: int = PlayerInput.seats[tank]
			if key != PlayerInput.NO_SEAT and PlayerInput.controller_peer(key) == peer:
				text += "   ·   " + tr("DRIVING P%d") % (tank + 1)
		MenuRows.value_label(_drive_rows[peer]).text = text


func _adjust_host(focused: Control, direction: int) -> void:
	for peer: int in _drive_rows:
		if _drive_rows[peer] == focused:
			_cycle_drive(peer, direction)
			return


## Steps [param peer] through DRIVE_CHOICES by [param direction].
func _cycle_drive(peer: int, direction: int) -> void:
	var allow: Array = Net.peers.get(peer, {}).get("allow", [false, false])
	var at := DRIVE_CHOICES.find([bool(allow[0]), bool(allow[1])])
	var next: Array = DRIVE_CHOICES[wrapi(at + direction, 0, DRIVE_CHOICES.size())]
	for tank in 2:
		Net.set_allow(peer, tank, next[tank])
	_refresh_host_values()
