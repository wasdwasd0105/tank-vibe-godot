class_name Bullet
extends Area2D

@export var speed: float = 256.0
var direction: Vector2 = Vector2.UP
var owner_tank: BaseTank = null
var is_player_bullet: bool = true
var can_destroy_steel: bool = false
var visual_style: String = "regular"
var visual_lane_offsets: Array[float] = [-16.0, 16.0]
var collision_lane_offsets: Array[float] = [-16.0, 16.0]
var _destroyed: bool = false
var _visual_sprites: Array[Sprite2D] = []
var _animation_timer: float = 0.0
var _current_frame: int = 0

var _level_manager: LevelManager = null
static var _bullet_texture_cache: Dictionary = {}

const BULLET_LENGTH: float = 10.0
const BULLET_THICKNESS: float = 10.0
const LINE_WIDTH: float = 2.0
const FRAME_DURATION: float = 0.5
const BULLET_VISUAL_SCALE: float = 2.0
const BULLET_TEXTURE_PATHS: Dictionary = {
	"regular": [
		"res://assets/sprites/bullets/regular/regular_1.png",
		"res://assets/sprites/bullets/regular/regular_2.png",
	],
	"rapid": [
		"res://assets/sprites/bullets/rapid/rapid_1.png",
		"res://assets/sprites/bullets/rapid/rapid_2.png",
	],
}
const BG_KEY_R: float = 248.0 / 255.0
const BG_KEY_G: float = 0.0
const BG_KEY_B: float = 248.0 / 255.0
const BG_KEY_THRESHOLD: float = 0.05

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = true

	var old_sprite = get_node_or_null("Sprite2D")
	if old_sprite:
		old_sprite.queue_free()

	if visual_lane_offsets.is_empty():
		visual_lane_offsets = [0.0]
	if collision_lane_offsets.is_empty():
		collision_lane_offsets = visual_lane_offsets.duplicate()

	_load_bullet_textures(visual_style)

	var col_shape = get_node_or_null("CollisionShape2D")
	if col_shape and col_shape.shape is RectangleShape2D:
		var rect := col_shape.shape as RectangleShape2D
		var lane_span := _get_lane_span(collision_lane_offsets)
		var cross_size := maxf(BULLET_THICKNESS, lane_span + BULLET_THICKNESS)
		if direction == Vector2.UP or direction == Vector2.DOWN:
			rect.size = Vector2(cross_size, BULLET_LENGTH)
		else:
			rect.size = Vector2(BULLET_LENGTH, cross_size)

	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("get_level_manager"):
		_level_manager = game.get_level_manager()

	_create_visual_sprites()
	queue_redraw()

func _get_lane_span(offsets: Array[float]) -> float:
	if offsets.size() <= 1:
		return 0.0

	var min_offset: float = offsets[0]
	var max_offset: float = offsets[0]
	for lane_offset in offsets:
		min_offset = minf(min_offset, lane_offset)
		max_offset = maxf(max_offset, lane_offset)
	return max_offset - min_offset

func _draw() -> void:
	if not _visual_sprites.is_empty():
		return
	var color := Color.WHITE
	var half_len := BULLET_LENGTH / 2.0

	if direction == Vector2.UP or direction == Vector2.DOWN:
		for lane_offset in visual_lane_offsets:
			draw_line(Vector2(lane_offset, -half_len), Vector2(lane_offset, half_len), color, LINE_WIDTH)
	else:
		for lane_offset in visual_lane_offsets:
			draw_line(Vector2(-half_len, lane_offset), Vector2(half_len, lane_offset), color, LINE_WIDTH)

func _physics_process(delta: float) -> void:
	if _destroyed:
		return

	_animation_timer += delta
	var active_textures := _get_active_bullet_textures()
	if active_textures.size() > 1 and _animation_timer >= FRAME_DURATION:
		_animation_timer -= FRAME_DURATION
		_current_frame = (_current_frame + 1) % active_textures.size()
		_update_visual_frame()

	var movement: Vector2 = direction * speed * delta
	position += movement

	if position.x < 144 or position.x > 1456 or position.y < 0 or position.y > 992:
		_destroy()
		return

	_check_tile_collision()

func _check_tile_collision() -> void:
	if not _level_manager or _destroyed:
		return

	var perp: Vector2 = Vector2.ZERO
	if direction == Vector2.UP or direction == Vector2.DOWN:
		perp = Vector2.RIGHT
	else:
		perp = Vector2.DOWN

	var base_positions: Array[Vector2] = [
		global_position,
		global_position + direction * 6.0,
	]

	var tiles_to_check: Array[Vector2i] = []
	for base_pos in base_positions:
		for lane_offset in collision_lane_offsets:
			var lane_pos: Vector2 = base_pos + perp * lane_offset
			var tile_pos: Vector2i = _level_manager.world_to_tile(lane_pos)
			if tile_pos not in tiles_to_check:
				tiles_to_check.append(tile_pos)

	var should_destroy: bool = false
	var solid_tiles: Array[Vector2i] = []
	for tile_pos in tiles_to_check:
		if not _level_manager._fg_tile_data.has(tile_pos):
			continue
		var data: Dictionary = _level_manager._fg_tile_data[tile_pos]
		var code: int = data.get("code", 0)
		var cat := LevelData.get_tile_category(code)
		if LevelData.is_solid_tile(cat):
			should_destroy = true
			solid_tiles.append(tile_pos)

	if should_destroy:
		for tile_pos in solid_tiles:
			if not _level_manager._fg_tile_data.has(tile_pos):
				continue
			var data: Dictionary = _level_manager._fg_tile_data[tile_pos]
			var code: int = data.get("code", 0)
			var cat := LevelData.get_tile_category(code)
			match cat:
				LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
					_level_manager._damage_brick(tile_pos, direction)
				LevelData.TileCategory.HARD_BRICK:
					_level_manager._damage_hard_brick(tile_pos)
				LevelData.TileCategory.IRON_BLOCK:
					if can_destroy_steel:
						_level_manager._remove_fg_tile(tile_pos)
				LevelData.TileCategory.SUPER_BLOCK:
					pass
		_destroy()

func _on_body_entered(body: Node2D) -> void:
	if _destroyed:
		return
	if body == owner_tank:
		return

	if is_player_bullet and body is EnemyTank:
		if body.is_bullet_blocked(direction):
			_destroy()
			return
		body.take_damage(direction)
		_destroy()
	elif not is_player_bullet and body is PlayerTank:
		if body.is_bullet_blocked(direction):
			_destroy()
			return
		if not body.is_invincible:
			body.take_damage()
		_destroy()
	elif body.is_in_group("eagle"):
		Events.base_destroyed.emit()
		_destroy()
	elif body.is_in_group("boundary"):
		_destroy()

func _on_area_entered(area: Area2D) -> void:
	if _destroyed:
		return
	if area is Bullet:
		var other_bullet := area as Bullet
		if is_player_bullet != other_bullet.is_player_bullet:
			other_bullet._destroy()
			_destroy()

func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if owner_tank and is_instance_valid(owner_tank):
		owner_tank.on_bullet_destroyed()

	var explosion_scene := preload("res://scenes/effects/explosion.tscn")
	var effects_container = get_tree().get_first_node_in_group("effects_container")
	var parent_node = effects_container if effects_container else get_tree().current_scene

	var perp: Vector2 = Vector2.ZERO
	if direction == Vector2.UP or direction == Vector2.DOWN:
		perp = Vector2.RIGHT
	else:
		perp = Vector2.DOWN

	for lane_offset in collision_lane_offsets:
		var explosion := explosion_scene.instantiate()
		explosion.global_position = global_position + perp * lane_offset
		explosion.scale = Vector2(1.0, 1.0)
		parent_node.add_child(explosion)

	queue_free()

func _create_visual_sprites() -> void:
	var active_textures := _get_active_bullet_textures()
	if active_textures.is_empty():
		return

	var sprite_rotation := _get_sprite_rotation()
	for lane_offset in visual_lane_offsets:
		var sprite := Sprite2D.new()
		sprite.texture = active_textures[_current_frame]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * BULLET_VISUAL_SCALE
		sprite.rotation = sprite_rotation
		sprite.position = _get_visual_lane_position(lane_offset)
		add_child(sprite)
		_visual_sprites.append(sprite)

func _update_visual_frame() -> void:
	var active_textures := _get_active_bullet_textures()
	if active_textures.is_empty():
		return
	for sprite in _visual_sprites:
		if sprite and is_instance_valid(sprite):
			sprite.texture = active_textures[_current_frame]

func _load_bullet_textures(style: String) -> void:
	if _bullet_texture_cache.has(style):
		return

	var textures: Array[Texture2D] = []
	for texture_path in BULLET_TEXTURE_PATHS.get(style, []):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(texture_path)) != OK:
			continue
		img.convert(Image.FORMAT_RGBA8)

		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if absf(c.r - BG_KEY_R) < BG_KEY_THRESHOLD \
					and absf(c.g - BG_KEY_G) < BG_KEY_THRESHOLD \
					and absf(c.b - BG_KEY_B) < BG_KEY_THRESHOLD:
					img.set_pixel(x, y, Color(0, 0, 0, 0))

		textures.append(ImageTexture.create_from_image(img))

	_bullet_texture_cache[style] = textures

func _get_active_bullet_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = _bullet_texture_cache.get(visual_style, [])
	if textures.is_empty() and visual_style != "regular":
		_load_bullet_textures("regular")
		textures = _bullet_texture_cache.get("regular", [])
	return textures

func _get_visual_lane_position(lane_offset: float) -> Vector2:
	if direction == Vector2.UP or direction == Vector2.DOWN:
		return Vector2(lane_offset, 0.0)
	return Vector2(0.0, lane_offset)

func _get_sprite_rotation() -> float:
	if direction == Vector2.DOWN:
		return PI
	if direction == Vector2.LEFT:
		return -PI / 2
	if direction == Vector2.RIGHT:
		return PI / 2
	return 0.0
