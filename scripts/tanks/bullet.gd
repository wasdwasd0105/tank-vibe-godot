class_name Bullet
extends Area2D

@export var speed: float = 256.0
var direction: Vector2 = Vector2.UP
var owner_tank: BaseTank = null
var is_player_bullet: bool = true
var can_destroy_steel: bool = false
var _destroyed: bool = false

var _level_manager: LevelManager = null

# Bullet visual: 2 parallel lines (one per tile lane)
const LINE_LENGTH: float = 10.0   # length of each line
const LINE_SPACING: float = 32.0  # gap between the two lines = 1 tile width
const LINE_WIDTH: float = 2.0     # thickness of each line

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = true
	# Remove sprite child if it exists (we draw manually now)
	var old_sprite = get_node_or_null("Sprite2D")
	if old_sprite:
		old_sprite.queue_free()
	# Adjust collision shape to match 2-tile-wide bullet
	var col_shape = get_node_or_null("CollisionShape2D")
	if col_shape and col_shape.shape is RectangleShape2D:
		var rect := col_shape.shape as RectangleShape2D
		if direction == Vector2.UP or direction == Vector2.DOWN:
			rect.size = Vector2(48, 10)  # wide horizontally for vertical bullets
		else:
			rect.size = Vector2(10, 48)  # tall vertically for horizontal bullets
	# Cache level manager reference
	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("get_level_manager"):
		_level_manager = game.get_level_manager()
	queue_redraw()

func _draw() -> void:
	var color := Color.WHITE
	# Draw 2 parallel lines based on travel direction, spaced one tile apart
	if direction == Vector2.UP or direction == Vector2.DOWN:
		# Vertical bullet: two vertical lines side by side (one per tile column)
		var half_len := LINE_LENGTH / 2.0
		var offset := LINE_SPACING / 2.0
		# Left line
		draw_line(Vector2(-offset, -half_len), Vector2(-offset, half_len), color, LINE_WIDTH)
		# Right line
		draw_line(Vector2(offset, -half_len), Vector2(offset, half_len), color, LINE_WIDTH)
	else:
		# Horizontal bullet: two horizontal lines stacked (one per tile row)
		var half_len := LINE_LENGTH / 2.0
		var offset := LINE_SPACING / 2.0
		# Top line
		draw_line(Vector2(-half_len, -offset), Vector2(half_len, -offset), color, LINE_WIDTH)
		# Bottom line
		draw_line(Vector2(-half_len, offset), Vector2(half_len, offset), color, LINE_WIDTH)

func _physics_process(delta: float) -> void:
	if _destroyed:
		return

	var movement: Vector2 = direction * speed * delta
	position += movement

	# Check bounds (playfield boundaries: 40x30 tiles of 32px)
	if position.x < 32 or position.x > 1344 or position.y < 0 or position.y > 992:
		_destroy()
		return

	# Proactively check tile collision every frame using grid lookup
	_check_tile_collision()

func _check_tile_collision() -> void:
	if not _level_manager or _destroyed:
		return

	# Bullets are 2-tiles wide (matching 2x2 tanks).
	# The bullet position sits at the border between two tile lanes.
	# We offset by half a tile in each perpendicular direction to find both lanes.
	var perp: Vector2 = Vector2.ZERO
	if direction == Vector2.UP or direction == Vector2.DOWN:
		perp = Vector2.RIGHT
	else:
		perp = Vector2.DOWN

	var half_tile: float = 16.0  # half of TILE_SIZE (32)

	# Base positions along the travel direction (center + tip for anti-tunneling)
	var base_positions: Array[Vector2] = [
		global_position,
		global_position + direction * 6.0,  # tip of bullet
	]

	# Collect all unique tile positions to check across both lanes
	var tiles_to_check: Array[Vector2i] = []

	for base_pos in base_positions:
		# Left/top lane
		var lane1_pos: Vector2 = base_pos - perp * half_tile
		var tile1: Vector2i = _level_manager.world_to_tile(lane1_pos)
		if tile1 not in tiles_to_check:
			tiles_to_check.append(tile1)
		# Right/bottom lane
		var lane2_pos: Vector2 = base_pos + perp * half_tile
		var tile2: Vector2i = _level_manager.world_to_tile(lane2_pos)
		if tile2 not in tiles_to_check:
			tiles_to_check.append(tile2)

	# First pass: check if any FG tile is solid (would stop the bullet)
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

	# Second pass: damage all solid tiles simultaneously, then destroy bullet
	if should_destroy:
		for tile_pos in solid_tiles:
			if not _level_manager._fg_tile_data.has(tile_pos):
				continue  # tile may have been removed by a previous hit in this loop
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
					pass  # indestructible — bullet just stops
		_destroy()

func _on_body_entered(body: Node2D) -> void:
	if _destroyed:
		return
	if body == owner_tank:
		return

	# Tank hits
	if is_player_bullet and body is EnemyTank:
		body.take_damage()
		_destroy()
	elif not is_player_bullet and body is PlayerTank:
		if not body.is_invincible:
			body.take_damage()
		_destroy()
	elif body.is_in_group("eagle"):
		Events.base_destroyed.emit()
		_destroy()
	# Note: boundary walls and tile walls are now handled by _check_tile_collision()
	# but we still catch boundaries here as backup
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
	# Spawn two small explosions — one for each lane of the 2-wide bullet
	var explosion_scene := preload("res://scenes/effects/explosion.tscn")
	var effects_container = get_tree().get_first_node_in_group("effects_container")
	var parent_node = effects_container if effects_container else get_tree().current_scene

	var perp: Vector2 = Vector2.ZERO
	if direction == Vector2.UP or direction == Vector2.DOWN:
		perp = Vector2.RIGHT
	else:
		perp = Vector2.DOWN

	for offset in [-16.0, 16.0]:
		var explosion := explosion_scene.instantiate()
		explosion.global_position = global_position + perp * offset
		explosion.scale = Vector2(1.0, 1.0)
		parent_node.add_child(explosion)
	queue_free()
