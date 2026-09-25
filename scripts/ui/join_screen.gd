extends Control
## New game: each player joins with their own fire button (a credit each) and
## fire again starts the game, as in the arcade. A card per player shows its
## tank, the button to press (the key, and the controller's when one is
## plugged in) and READY once joined.
##
## Mouse: click a player's card to join (and again to start), or START. Esc (B
## on a controller) or BACK returns to the title screen; a controller's Start
## starts once someone has joined.

const TITLE_SCENE := "res://scenes/main.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const CARD_SIZE := Vector2(520, 460)
const TANK_SIZE := 128.0
## Each player's colour, as on the HUD: P1 gold, P2 green.
const PLAYER_COLORS: Array[Color] = [Color(0.95, 0.75, 0.15), Color(0.3, 0.85, 0.35)]
const IDLE_BORDER := Color(0.25, 0.26, 0.31)
const DIM := Color(1, 1, 1, 0.35)
const NO_CREDITS_COLOR := Color(0.55, 0.55, 0.58)

@onready var _cards: HBoxContainer = %Cards
@onready var _credits_label: Label = %CreditsLabel
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton

var _joined: Array[bool] = [false, false]
var _card_buttons: Array[Button] = []
var _tank_images: Array[TextureRect] = []
var _prompts: Array[HBoxContainer] = []   # "PRESS [T] TO JOIN"
var _status_labels: Array[Label] = []


func _ready() -> void:
	for pid in 2:
		_cards.add_child(_make_card(pid))
	_start_button.pressed.connect(_start_game)
	_back_button.pressed.connect(_go_back)
	for button: Button in [_start_button, _back_button]:
		button.mouse_entered.connect(button.grab_focus)
	# The prompts show a controller's button only while one is plugged in.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	SoundManager.attach_ui_sounds(self)
	_refresh()


func _process(_delta: float) -> void:
	for pid in 2:
		var prefix := "p1_" if pid == 0 else "p2_"
		if Input.is_action_just_pressed(prefix + "shoot") or Input.is_action_just_pressed(prefix + "shoot2"):
			_on_player_fire(pid)


func _input(event: InputEvent) -> void:
	if not MenuFocus.is_navigation_event(event):
		return
	# Leaving changes scene, which removes this node from the tree at once
	# (get_viewport() then returns null), so keep the viewport.
	var viewport := get_viewport()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if not _joined.has(true):
			return
		_start_game()
	elif MenuFocus.is_pressed(event, ["ui_cancel"]):
		_go_back()
	else:
		return
	viewport.set_input_as_handled()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh()


## A player's fire, or a click on their card: join, or once joined, start.
func _on_player_fire(player: int) -> void:
	if _joined[player]:
		_start_game()
	elif GameManager.join_player(player):
		_joined[player] = true
		SoundManager.play(&"player_join")
		_refresh()


func _start_game() -> void:
	if not _joined.has(true):
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _go_back() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


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

	_card_buttons.append(card)
	_tank_images.append(tank)
	_prompts.append(prompt)
	_status_labels.append(status)
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


## Shows who has joined, what each player can press and the credits left.
func _refresh() -> void:
	_credits_label.text = tr("CREDITS   %d") % GameManager.credits
	for player in 2:
		var joined := _joined[player]
		var can_join := joined or GameManager.credits > 0
		var card := _card_buttons[player]
		card.disabled = not can_join
		card.add_theme_stylebox_override(&"normal", _card_style(player, joined, false))
		card.add_theme_stylebox_override(&"hover", _card_style(player, joined, true))
		card.add_theme_stylebox_override(&"pressed", _card_style(player, joined, true))
		card.add_theme_stylebox_override(&"disabled", _card_style(player, false, false))
		_tank_images[player].modulate = Color.WHITE if joined else DIM
		var pad_in := Input.get_connected_joypads().has(InputSettings.get_pad_device("p%d" % (player + 1)))
		_fill_prompt(player, "TO START" if joined else "TO JOIN", pad_in)
		# Hidden but still holding its place, so both cards line up.
		_prompts[player].modulate.a = 1.0 if can_join else 0.0
		var status := _status_labels[player]
		if joined:
			status.text = "READY"
			status.add_theme_color_override(&"font_color", PLAYER_COLORS[player])
		elif not can_join:
			status.text = "NO CREDITS"
			status.add_theme_color_override(&"font_color", NO_CREDITS_COLOR)
		else:
			status.text = ""
	_start_button.disabled = not _joined.has(true)


## "PRESS [key] TO ..." for [param player], and "OR PAD [button]" when their
## controller is plugged in ([param pad_in]): labelled, since a pad's A would
## otherwise read as the keyboard's A key.
func _fill_prompt(player: int, ending: String, pad_in: bool) -> void:
	var prompt := _prompts[player]
	for child in prompt.get_children():
		prompt.remove_child(child)
		child.queue_free()
	var prefix := "p%d" % (player + 1)
	prompt.add_child(_make_label("PRESS", &"ValueLabel"))
	prompt.add_child(MenuRows._make_keycap("Key", InputSettings.get_key_name(prefix + "_shoot")))
	if pad_in:
		var button := InputSettings.get_pad_slot(prefix, "shoot", 0)
		if not button.is_empty():
			prompt.add_child(_make_label("OR PAD", &"HintLabel"))
			prompt.add_child(MenuRows._make_keycap("Pad", InputSettings.get_pad_name(button)))
	prompt.add_child(_make_label(ending, &"ValueLabel"))
