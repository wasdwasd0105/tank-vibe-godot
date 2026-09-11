extends Control
## Animated backdrop shared by the menu screens: a faint brick pattern, a wall
## with the eagle base along the bottom edge and a convoy of tanks patrolling
## above it. Textures come from ThemeManager so the backdrop follows the
## selected theme.

const TILE_SIZE := 64.0          # game tiles are 32 px; the backdrop draws them at 2x
const TANK_SIZE := 64.0
const TANK_SPEED := 55.0         # px per second
const CONVOY_GAP := 230.0
const CONVOY_KEYS: Array[String] = ["p1", "p2", "e1", "e2", "e3", "e4"]
const SOFT_BRICK_CODE := 0x19
const IRON_CODE := 0x39
const EAGLE_TEXTURE := "res://assets/sprites/tiles/eagle.png"
const BASE_COLOR := Color(0.043, 0.047, 0.063)
const PATTERN_ALPHA := 0.07

@onready var _diorama: Control = $Diorama

var _brick: Texture2D
var _iron: Texture2D
var _eagle: Texture2D
var _tank_textures: Array[Texture2D] = []
var _scroll := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_eagle = load(EAGLE_TEXTURE)
	_refresh_theme_textures()
	ThemeManager.theme_changed.connect(func(_theme_name: String) -> void: _refresh_theme_textures())
	_diorama.draw.connect(_draw_diorama)


func _process(delta: float) -> void:
	_scroll += TANK_SPEED * delta
	_diorama.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BASE_COLOR)
	if _brick:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(2.0, 2.0))
		draw_texture_rect(_brick, Rect2(Vector2.ZERO, size / 2.0), true, Color(1, 1, 1, PATTERN_ALPHA))
		draw_set_transform(Vector2.ZERO)


func _draw_diorama() -> void:
	var wall_y := size.y - TILE_SIZE
	var columns := ceili(size.x / TILE_SIZE)
	var center := columns / 2
	for column in columns:
		var rect := Rect2(column * TILE_SIZE, wall_y, TILE_SIZE, TILE_SIZE)
		var texture := _brick
		if column == center:
			texture = _eagle
		elif absi(column - center) == 1:
			texture = _iron
		if texture:
			_diorama.draw_texture_rect(texture, rect, false)

	var lane_center_y := wall_y - TANK_SIZE / 2.0
	for i in _tank_textures.size():
		var texture := _tank_textures[i]
		if texture == null:
			continue
		var scale := Vector2(TANK_SIZE / texture.get_width(), TANK_SIZE / texture.get_height())
		# Sprites face up; rotating a quarter turn clockwise makes them drive right.
		_diorama.draw_set_transform(Vector2(_tank_x(i) + TANK_SIZE / 2.0, lane_center_y), PI / 2.0, scale)
		_diorama.draw_texture(texture, -texture.get_size() / 2.0)
	_diorama.draw_set_transform(Vector2.ZERO)


func _tank_x(index: int) -> float:
	var loop_length := maxf(size.x + TANK_SIZE * 2.0, CONVOY_GAP * CONVOY_KEYS.size())
	return fposmod(_scroll + index * CONVOY_GAP, loop_length) - TANK_SIZE


func _refresh_theme_textures() -> void:
	var flag_frames := ThemeManager.get_flag_frames("healthy")
	_eagle = flag_frames[0] if not flag_frames.is_empty() else load(EAGLE_TEXTURE)
	_brick = ThemeManager.get_tile_texture(SOFT_BRICK_CODE)
	_iron = ThemeManager.get_tile_texture(IRON_CODE)
	_tank_textures.clear()
	for key in CONVOY_KEYS:
		_tank_textures.append(ThemeManager.get_tank_texture(key))
	queue_redraw()
	if _diorama:
		_diorama.queue_redraw()
