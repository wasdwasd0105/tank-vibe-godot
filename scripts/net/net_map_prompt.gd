class_name NetMapPrompt
extends CanvasLayer
## The question a client gets when the host plays on a map set this computer
## doesn't have (Net._take_host_map): DOWNLOAD it and keep it with the maps, as
## Counter-Strike 1.6 kept the maps of the servers it joined, or NOT NOW. The
## game goes on either way: the host sends every stage's map with its world.
## After DOWNLOAD the window shows how far it has got, and closes when the map
## is saved (or didn't come); Net says which over the screen.
##
## It floats over whatever screen the client is on, the host's lobby or stage,
## and has the keys while it's open: left / right (or up / down) pick, fire /
## Enter / A press, Esc / B / Start are NOT NOW. The client's players hold still
## meanwhile (Net.map_prompt_open).

const LAYER := 96
const WINDOW_WIDTH := 760.0
const DIM := Color(0, 0, 0, 0.55)

var _map: Dictionary
var _nav: MenuFocus
var _text: Label
var _buttons: HBoxContainer
var _download_button: Button
var _not_now_button: Button
## After DOWNLOAD: the keys do nothing more, and it waits for the map.
var _fetching := false


func _init(map: Dictionary) -> void:
	_map = map
	name = "NetMapPrompt"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS  # over the host's pause too


func _ready() -> void:
	var screen := Control.new()
	screen.theme = preload("res://assets/ui/menu_theme.tres")
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing under it takes a click
	add_child(screen)
	var shade := ColorRect.new()
	shade.color = DIM
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)

	var window := PanelContainer.new()
	window.theme_type_variation = &"MenuPanel"
	var style := (screen.get_theme_stylebox(&"panel", &"MenuPanel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.set_content_margin_all(26.0)
	style.bg_color.a = 0.98
	style.border_color = Color(0.98, 0.78, 0.22)
	window.add_theme_stylebox_override(&"panel", style)
	window.custom_minimum_size = Vector2(WINDOW_WIDTH, 0)
	center.add_child(window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	window.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"RowNameLabel"
	title.text = "THE HOST'S MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_text = Label.new()
	_text.theme_type_variation = &"ValueLabel"
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WINDOW_WIDTH - 52.0, 0)
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # composed below, the name as it is
	_text.text = tr("The host plays on the map set {name} ({size}), which this computer doesn't have. Download it and keep it with your maps?") \
			.format({"name": _map["name"], "size": Net.map_size_text(_map["size"])})
	column.add_child(_text)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override(&"separation", 40)
	column.add_child(_buttons)
	_download_button = _button("DOWNLOAD", _download)
	_not_now_button = _button("NOT NOW", _close)

	_nav = MenuFocus.new(get_viewport())
	_nav.items = [_download_button, _not_now_button]
	Net.map_progress.connect(_on_progress)
	Net.map_download_finished.connect(func(_name: String, _error: String) -> void: _close())
	Net.session_ended.connect(func(_reason: String) -> void: _close())
	Net.map_prompt_open = true
	SoundManager.attach_ui_sounds(self)
	_download_button.grab_focus()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"MenuItemButton"
	button.custom_minimum_size = Vector2(260, 64)
	button.pressed.connect(action)
	button.mouse_entered.connect(button.grab_focus)
	_buttons.add_child(button)
	return button


## In front of the screen under it, which a scene change puts after it, so
## the keys come here first.
func _process(_delta: float) -> void:
	var parent := get_parent()
	if parent and get_index() != parent.get_child_count() - 1:
		parent.move_child(self, -1)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	var viewport := get_viewport()
	viewport.set_input_as_handled()  # none of it reaches the screen underneath
	if _fetching:
		return
	if MenuFocus.is_pressed(event, MenuFocus.LEFT_ACTIONS) or MenuFocus.is_pressed(event, MenuFocus.UP_ACTIONS):
		_nav.move(-1)
	elif MenuFocus.is_pressed(event, MenuFocus.RIGHT_ACTIONS) or MenuFocus.is_pressed(event, MenuFocus.DOWN_ACTIONS):
		_nav.move(1)
	elif MenuFocus.is_pressed(event, MenuFocus.ACCEPT_ACTIONS):
		_nav.activate()
	elif MenuFocus.is_pressed(event, MenuFocus.BACK_ACTIONS):
		_close()


## DOWNLOAD: the buttons give way to how far it has got. (With nobody to fetch
## it from any more, it just closes.)
func _download() -> void:
	if not Net.download_map():
		_close()
		return
	_fetching = true
	_buttons.visible = false
	_on_progress(0, int(_map["size"]))


func _on_progress(received: int, total: int) -> void:
	_text.text = tr("Downloading {name}...  {percent}%").format(
			{"name": _map["name"], "percent": floori(100.0 * received / maxi(total, 1))})


func _close() -> void:
	if is_queued_for_deletion():
		return
	Net.map_prompt_open = false
	queue_free()
