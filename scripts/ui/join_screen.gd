extends Control
## New game: each player joins with their own fire button and fire again
## starts the game, as in the arcade. A card per player shows its
## tank, the button to press (the key, and the controller's when one is
## plugged in) and READY once joined.
##
## Mouse: click a player's card to join (and again to start), or START. Esc (B
## on a controller) or BACK returns to the title screen; a controller's Start
## starts once someone has joined.
##
## Online it is the lobby (docs/network_design.md): anyone on any machine takes a
## free tank with their own fire button (or a click on its card), the cards show
## who drives each, and the host starts the game. A loaded game's players are
## already in. BACK leaves: a host's ends the online game for everyone.

const TITLE_SCENE := "res://scenes/main.tscn"
const ONLINE_SCENE := "res://scenes/online_screen.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const CARD_SIZE := Vector2(520, 460)
const TANK_SIZE := 128.0
## Each player's colour, as on the HUD: P1 gold, P2 green.
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.75, 0.15), Color(0.3, 0.85, 0.35)]
const IDLE_BORDER := Color(0.25, 0.26, 0.31)
const DIM := Color(1, 1, 1, 0.35)
## A card's line when it isn't READY: a tank waiting for its driver.
const WAITING_COLOR := Color(0.55, 0.55, 0.58)

@onready var _cards: HBoxContainer = %Cards
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton

## Who is in: [P1, P2] (see _is_ready).
var _joined: Array[bool]:
	get:
		return [_is_ready(0), _is_ready(1)]
var _card_buttons: Array[Button] = []
var _tank_images: Array[TextureRect] = []
var _prompts: Array[HBoxContainer] = []   # "PRESS [T] TO JOIN"
var _status_labels: Array[Label] = []
var _driver_labels: Array[Label] = []     # online: who drives the tank

## Online (see the class notes), and as the host.
var _online := false
var _is_host := false
var _players_label: Label = null


func _ready() -> void:
	WindowManager.leave_game()  # the menus stay in the window
	_online = Net.is_online()
	_is_host = Net.is_host()
	for pid in 2:
		_cards.add_child(_make_card(pid))
	_start_button.pressed.connect(_start_game)
	_back_button.pressed.connect(_go_back)
	for button: Button in [_start_button, _back_button]:
		button.mouse_entered.connect(button.grab_focus)
	# The prompts show a controller's button only while one is plugged in.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if _online:
		_setup_online()
	SoundManager.attach_ui_sounds(self)
	_refresh()


func _process(_delta: float) -> void:
	if _online and not _is_host:
		return  # a client's presses reach the host with its inputs
	for press: Dictionary in PlayerInput.fire_presses():
		_on_fire_press(press["key"], press["seat"])
	if _is_host:
		Net.set_lobby(GameManager.player_active, not GameManager.current_save_file.is_empty())


func _input(event: InputEvent) -> void:
	if not MenuFocus.is_navigation_event(event):
		return
	# Leaving changes scene, which removes this node from the tree at once
	# (get_viewport() then returns null), so keep the viewport.
	var viewport := get_viewport()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if not _anyone_ready():
			return
		_start_game()
	elif MenuFocus.is_pressed(event, ["ui_cancel"]):
		_go_back()
	else:
		return
	viewport.set_input_as_handled()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh()


# =====================================================================
# Joining
# =====================================================================

## Fire from controller [param key], which drives tank [param seat] (or
## PlayerInput.NO_SEAT). A player in already starts the game (online, only the
## host's own players); one not in yet joins. Online, a player with no tank
## takes a free one (net_claim).
func _on_fire_press(key: int, seat: int) -> void:
	if seat >= 0:
		if GameManager.player_active[seat]:
			if not _online or PlayerInput.is_local(key):
				_start_game()
		else:
			GameManager.join_player(seat)
			_joined_sound()
			_refresh()
		return
	var tank := Net.free_seat_for(key)
	if tank >= 0:
		net_claim(key, tank)


## A player's fire, or a click on their card (offline: that player's).
func _on_player_fire(player: int) -> void:
	if not _online:
		_on_fire_press(PlayerInput.LOCAL_P1 + player, player)
	elif _is_host:
		if Net.is_my_seat(player):
			_start_game()
		else:
			for key: int in [PlayerInput.LOCAL_P1, PlayerInput.LOCAL_P2]:
				if not PlayerInput.seats.has(key):
					net_claim(key, player)
					return
	else:
		Net.request_seat(player)


## Online, on the host: controller [param key] takes tank [param tank] if it's
## free and they may drive it, joining that tank's player if the game doesn't
## have them yet. A click on a client's card comes here too.
func net_claim(key: int, tank: int) -> void:
	if PlayerInput.seats[tank] != PlayerInput.NO_SEAT or PlayerInput.seats.has(key) \
			or not Net.may_drive(key, tank):
		return
	if not GameManager.player_active[tank]:
		GameManager.join_player(tank)
	PlayerInput.set_seat(tank, key)
	_joined_sound()
	_refresh()


func _joined_sound() -> void:
	SoundManager.play(&"player_join")


func _start_game() -> void:
	if not _anyone_ready() or (_online and not _is_host):
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _go_back() -> void:
	var tree := get_tree()
	if _online:
		# A host's BACK ends the game for everyone; a client's leaves it, back
		# to ONLINE BATTLE.
		Net.leave()
		tree.change_scene_to_file(TITLE_SCENE if _is_host else ONLINE_SCENE)
		return
	tree.change_scene_to_file(TITLE_SCENE)


# =====================================================================
# Online
# =====================================================================

func _setup_online() -> void:
	($Header as Label).text = "ONLINE GAME"
	var subtitle := $Subtitle as Label
	if _is_host:
		subtitle.text = tr("SHARE YOUR ADDRESS:   %s") % Net.share_address()
		($Hint as Label).text = "Press fire to take a tank   ·   fire again or START to begin   ·   Esc ends the online game"
		Net.set_host_screen(Net.SCREEN_LOBBY)
	else:
		subtitle.text = tr("HOSTED BY %s") % Net.host_name
		($Hint as Label).text = "Press fire to take a tank   ·   the host starts the game   ·   Esc leaves"
		_start_button.visible = false
		($Footer as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER  # BACK alone, centred
	# Who is here, under the address (or the host's name).
	_players_label = Label.new()
	_players_label.theme_type_variation = &"HintLabel"
	_players_label.add_theme_font_size_override(&"font_size", 22)
	_players_label.add_theme_color_override(&"font_color", Color(0.86, 0.86, 0.88))
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_players_label.offset_top = 184
	_players_label.offset_bottom = 214
	_players_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_players_label)
	Net.session_changed.connect(_refresh)


## Is [param player] in (and, online, driven by someone)?
func _is_ready(player: int) -> bool:
	if not _online:
		return GameManager.player_active[player]
	return _active(player) and PlayerInput.seats[player] != PlayerInput.NO_SEAT


func _anyone_ready() -> bool:
	return _is_ready(0) or _is_ready(1)


## The game's joined players: a client's are the host's lobby's.
func _active(player: int) -> bool:
	if _online and not _is_host:
		return bool(Net.lobby.get("active", [false, false])[player])
	return GameManager.player_active[player]


## Which of this machine's controls (0 P1's, 1 P2's) would take [param player]'s
## tank by pressing fire now, or -1: offline always that player's own.
func _local_taker(player: int) -> int:
	if not _online:
		return player
	# Still seated from the last game (after a game over): it joins its own tank.
	if Net.is_my_seat(player):
		return PlayerInput.controller_slot(PlayerInput.seats[player])
	for slot in 2:
		var key := PlayerInput.controller_key(Net.my_id(), slot)
		if PlayerInput.seats.has(key):
			continue
		if Net.free_seat_for(key) == player:
			return slot
	return -1


# =====================================================================
# The player cards
# =====================================================================

## Player [param player]'s card: a button the size of a panel holding the
## player's name, tank, prompt and status.
func _make_card(player: int) -> Button:
	var card := Button.new()
	card.name = "P%dCard" % (player + 1)
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(_on_player_fire.bind(player))
	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	card.add_child(column)

	var title := _make_label(tr("PLAYER %d") % (player + 1), &"RowNameLabel")
	title.name = "Title"
	column.add_child(title)
	var tank := TextureRect.new()
	tank.texture = ThemeManager.get_tank_texture("p%d" % (player + 1))
	tank.custom_minimum_size = Vector2(TANK_SIZE, TANK_SIZE)
	tank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tank.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tank.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tank)
	var prompt := HBoxContainer.new()
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt.add_theme_constant_override("separation", 12)
	column.add_child(prompt)
	var status := _make_label("", &"ValueLabel")
	status.custom_minimum_size = Vector2(0, 36)
	column.add_child(status)
	var driver := _make_label("", &"PromptLabel")
	driver.name = "Driver"
	driver.visible = _online
	column.add_child(driver)

	_card_buttons.append(card)
	_tank_images.append(tank)
	_prompts.append(prompt)
	_status_labels.append(status)
	_driver_labels.append(driver)
	return card


func _make_label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## The card's frame: grey while waiting, the player's colour once joined.
func _card_style(player: int, joined: bool, hover: bool) -> StyleBoxFlat:
	var color: Color = PLAYER_COLORS[player]
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.88) if joined else Color(0.06, 0.07, 0.09, 0.92)
	style.bg_color.a = 0.94
	style.border_color = color if joined else (color.darkened(0.3) if hover else IDLE_BORDER)
	style.set_border_width_all(3 if joined else 2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 6)
	return style


## Shows who has joined and what each player can press.
func _refresh() -> void:
	if not is_inside_tree():
		return
	for player in 2:
		var joined := _is_ready(player)
		var taker := _local_taker(player)
		var card := _card_buttons[player]
		card.add_theme_stylebox_override(&"normal", _card_style(player, joined, false))
		card.add_theme_stylebox_override(&"hover", _card_style(player, joined, true))
		card.add_theme_stylebox_override(&"pressed", _card_style(player, joined, true))
		card.add_theme_stylebox_override(&"disabled", _card_style(player, false, false))
		_tank_images[player].modulate = Color.WHITE if joined else DIM
		# The prompt is for this machine: its key that joins, or starts.
		var ending := ""
		var slot := taker
		if joined and (not _online or Net.is_my_seat(player)):
			ending = "TO START" if (not _online or _is_host) else ""
			slot = player if not _online else PlayerInput.controller_slot(PlayerInput.seats[player])
		elif not joined and taker >= 0:
			ending = "TO TAKE IT" if _active(player) else "TO JOIN"
		var shown := not ending.is_empty() and slot >= 0
		if not shown:
			slot = player if slot < 0 else slot
			ending = "TO JOIN"
		var pad_in := Input.get_connected_joypads().has(InputSettings.get_pad_device("p%d" % (slot + 1)))
		_fill_prompt(player, ending, pad_in, slot)
		# Hidden but still holding its place, so both cards line up.
		_prompts[player].modulate.a = 1.0 if shown else 0.0
		var status := _status_labels[player]
		if joined:
			status.text = "READY"
			status.add_theme_color_override(&"font_color", PLAYER_COLORS[player])
		elif _online and _active(player):
			status.text = "WAITING FOR A DRIVER"
			status.add_theme_color_override(&"font_color", WAITING_COLOR)
		else:
			status.text = ""
		_driver_labels[player].text = Net.seat_label(player) if _online else ""
	_start_button.disabled = not _anyone_ready()
	if _players_label:
		var names: PackedStringArray = []
		for peer: int in Net.peers:
			names.append(Net.peer_name(peer))
		_players_label.text = tr("PLAYERS   %s") % "   ·   ".join(names)


## "PRESS [key] TO ..." on [param player]'s card, and "OR PAD [button]" when
## that controller is plugged in ([param pad_in]): labelled, since a pad's A
## would otherwise read as the keyboard's A key. The keys are local controls
## [param slot]'s (-1: the player's own, as offline).
func _fill_prompt(player: int, ending: String, pad_in: bool, slot: int = -1) -> void:
	var prompt := _prompts[player]
	for child in prompt.get_children():
		prompt.remove_child(child)
		child.queue_free()
	var prefix := "p%d" % ((player if slot < 0 else slot) + 1)
	prompt.add_child(_make_label("PRESS", &"ValueLabel"))
	prompt.add_child(MenuRows._make_keycap("Key", InputSettings.get_key_name(prefix + "_shoot")))
	if pad_in:
		var button := InputSettings.get_pad_slot(prefix, "shoot", 0)
		if not button.is_empty():
			prompt.add_child(_make_label("OR PAD", &"HintLabel"))
			prompt.add_child(MenuRows._make_keycap("Pad", InputSettings.get_pad_name(button)))
	prompt.add_child(_make_label(ending, &"ValueLabel"))
