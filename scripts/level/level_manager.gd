class_name LevelManager
extends Node2D

const TILE_SIZE: int = 32
const GRID_WIDTH: int = LevelData.GRID_WIDTH   # 40
const GRID_HEIGHT: int = LevelData.GRID_HEIGHT  # 30

# Texture references for tiles
var brick_texture: Texture2D
var steel_texture: Texture2D
var water_texture: Texture2D
var ice_texture: Texture2D
var tree_texture: Texture2D
var eagle_texture: Texture2D

# Containers
var terrain_node: Node2D
var tree_node: Node2D
var boundary_node: Node2D

# Tile grid: stores references to tile sprites and StaticBody2D for collision
# Key: Vector2i, Value: { "sprite": Sprite2D, "body": StaticBody2D, "type": int }
var _tile_data: Dictionary = {}

# Brick sub-tile damage: Key: Vector2i, Value: bitmask
var _brick_damage: Dictionary = {}

# Base wall fortification
var _original_base_walls: Array[Vector2i] = []
var _fortify_timer: float = -1.0
var _is_fortified: bool = false

func _ready() -> void:
	terrain_node = $TerrainLayer
	tree_node = $TreeLayer

	# Load textures - we'll generate them procedurally
	_generate_textures()

	# Create boundary walls around the playfield
	_create_boundaries()

	# Set up eagle (2x2 tiles)
	var eagle = $Eagle
	if eagle:
		eagle.add_to_group("eagle")
		var shape := RectangleShape2D.new()
		shape.size = Vector2(60, 60)  # 2x2 tiles with 4px border (64-4=60)
		var col_shape := eagle.get_node_or_null("CollisionShape2D")
		if col_shape:
			col_shape.shape = shape

func _process(delta: float) -> void:
	if _is_fortified:
		_fortify_timer -= delta
		if _fortify_timer <= 0:
			_revert_fortification()

func _generate_textures() -> void:
	# Generate tile textures procedurally using Image
	brick_texture = _create_brick_texture()
	steel_texture = _create_steel_texture()
	water_texture = _create_water_texture()
	ice_texture = _create_ice_texture()
	tree_texture = _create_tree_texture()

func _create_brick_texture() -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var brick_color := Color(0.7, 0.13, 0.13)
	var mortar := Color(0.55, 0.35, 0.17)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y % 8 == 0 or y % 8 == 7:
				img.set_pixel(x, y, mortar)
			elif (y < 8 or (16 <= y and y < 24)) and x % 16 == 0:
				img.set_pixel(x, y, mortar)
			elif ((8 <= y and y < 16) or 24 <= y) and (x + 8) % 16 == 0:
				img.set_pixel(x, y, mortar)
			else:
				img.set_pixel(x, y, brick_color)
	return ImageTexture.create_from_image(img)

func _create_steel_texture() -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var steel := Color(0.75, 0.75, 0.75)
	var highlight := Color(0.88, 0.88, 0.88)
	var shadow := Color(0.5, 0.5, 0.5)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x < 2 or y < 2:
				img.set_pixel(x, y, highlight)
			elif x >= TILE_SIZE - 2 or y >= TILE_SIZE - 2:
				img.set_pixel(x, y, shadow)
			else:
				img.set_pixel(x, y, steel)
	return ImageTexture.create_from_image(img)

func _create_water_texture() -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var wave := absi(((x + y) % 8) - 4)
			var b := (150 + wave * 20) / 255.0
			img.set_pixel(x, y, Color(0, 0.2, minf(b, 1.0)))
	return ImageTexture.create_from_image(img)

func _create_ice_texture() -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var v := (200 + ((x + y) % 4) * 10) / 255.0
			img.set_pixel(x, y, Color(minf(v, 1.0), minf(v, 1.0), 1.0))
	return ImageTexture.create_from_image(img)

func _create_tree_texture() -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if ((x + y * 3) * 7) % 5 < 3:
				img.set_pixel(x, y, Color(0, (100 + (x * y) % 56) / 255.0, 0))
			else:
				img.set_pixel(x, y, Color(0, (80 + (x * y) % 40) / 255.0, 0))
	return ImageTexture.create_from_image(img)

func _create_boundaries() -> void:
	# Create invisible walls around the playfield
	var boundary_positions := []
	# Top and bottom rows
	for x in range(-1, GRID_WIDTH + 1):
		boundary_positions.append(Vector2i(x, -1))
		boundary_positions.append(Vector2i(x, GRID_HEIGHT))
	# Left and right columns
	for y in range(GRID_HEIGHT):
		boundary_positions.append(Vector2i(-1, y))
		boundary_positions.append(Vector2i(GRID_WIDTH, y))

	for pos in boundary_positions:
		var body := StaticBody2D.new()
		body.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
		body.collision_layer = 1  # walls layer
		body.collision_mask = 0
		body.add_to_group("boundary")
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		shape.shape = rect
		body.add_child(shape)
		add_child(body)

func load_stage(stage_num: int) -> void:
	# Clear existing tiles
	_clear_tiles()
	_brick_damage.clear()

	var stage_index := stage_num - 1
	if stage_index < 0 or stage_index >= LevelData.STAGES.size():
		stage_index = 0

	var layout: Array = LevelData.STAGES[stage_index]
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var tile_type: int = layout[y][x]
			if tile_type != LevelData.Tile.EMPTY:
				_place_tile(Vector2i(x, y), tile_type)

	_place_base_walls()

func _clear_tiles() -> void:
	for pos in _tile_data.keys():
		var data: Dictionary = _tile_data[pos]
		if data.has("sprite") and is_instance_valid(data["sprite"]):
			data["sprite"].queue_free()
		if data.has("body") and is_instance_valid(data["body"]):
			data["body"].queue_free()
	_tile_data.clear()

func _place_tile(pos: Vector2i, tile_type: int) -> void:
	var world_pos := Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)

	var spr := Sprite2D.new()
	spr.position = world_pos
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var body: StaticBody2D = null

	match tile_type:
		LevelData.Tile.BRICK:
			spr.texture = brick_texture
			body = _create_tile_body(world_pos, 1)  # walls layer
			_brick_damage[pos] = 0b1111
			terrain_node.add_child(spr)
		LevelData.Tile.STEEL:
			spr.texture = steel_texture
			body = _create_tile_body(world_pos, 1)  # walls layer
			terrain_node.add_child(spr)
		LevelData.Tile.WATER:
			spr.texture = water_texture
			body = _create_tile_body(world_pos, 2)  # water layer
			terrain_node.add_child(spr)
		LevelData.Tile.ICE:
			spr.texture = ice_texture
			# Ice has no collision - tanks slide on it
			terrain_node.add_child(spr)
		LevelData.Tile.TREE:
			spr.texture = tree_texture
			spr.z_index = 10  # draw above tanks
			tree_node.add_child(spr)

	_tile_data[pos] = { "sprite": spr, "body": body, "type": tile_type }

func _create_tile_body(world_pos: Vector2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = world_pos
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	body.add_child(shape)
	terrain_node.add_child(body)
	return body

func _place_base_walls() -> void:
	_original_base_walls.clear()
	# Eagle occupies 2x2 tiles at (EAGLE_COL, EAGLE_ROW) to (EAGLE_COL+1, EAGLE_ROW+1)
	# Surround with bricks
	var ec: int = LevelData.EAGLE_COL   # 19
	var er: int = LevelData.EAGLE_ROW   # 28
	var wall_positions := [
		# Top row above eagle
		Vector2i(ec - 1, er - 1), Vector2i(ec, er - 1), Vector2i(ec + 1, er - 1), Vector2i(ec + 2, er - 1),
		# Left side
		Vector2i(ec - 1, er), Vector2i(ec - 1, er + 1),
		# Right side
		Vector2i(ec + 2, er), Vector2i(ec + 2, er + 1),
	]
	for pos in wall_positions:
		if not _tile_data.has(pos):
			_place_tile(pos, LevelData.Tile.BRICK)
		_original_base_walls.append(pos)

func handle_bullet_hit_body(bullet: Bullet, body: StaticBody2D) -> void:
	# Find which tile this body belongs to
	for pos in _tile_data.keys():
		var data: Dictionary = _tile_data[pos]
		if data.get("body") == body:
			var tile_type: int = data["type"]
			match tile_type:
				LevelData.Tile.BRICK:
					_damage_brick(pos, bullet.direction)
					bullet._destroy()
					return
				LevelData.Tile.STEEL:
					if bullet.can_destroy_steel:
						_remove_tile(pos)
					bullet._destroy()
					return
				LevelData.Tile.WATER:
					return  # should not happen, water bodies don't block bullets
			break
	# If we didn't find the tile, just destroy the bullet (boundary wall)
	bullet._destroy()

func _damage_brick(tile_pos: Vector2i, from_direction: Vector2) -> void:
	if not _brick_damage.has(tile_pos):
		return

	var damage: int = _brick_damage[tile_pos]

	# Bitmask: 0b1000=TL, 0b0100=TR, 0b0010=BL, 0b0001=BR
	# The bullet destroys the 2 sub-tiles on the side it enters from.
	# "destroy_mask" has 1s for the sub-tiles the bullet would destroy.
	var destroy_mask: int = 0
	if from_direction == Vector2.UP:
		# Bullet going up -> enters from bottom -> destroys bottom sub-tiles
		destroy_mask = 0b0011  # BL + BR
	elif from_direction == Vector2.DOWN:
		# Bullet going down -> enters from top -> destroys top sub-tiles
		destroy_mask = 0b1100  # TL + TR
	elif from_direction == Vector2.LEFT:
		# Bullet going left -> enters from right -> destroys right sub-tiles
		destroy_mask = 0b0101  # TR + BR
	elif from_direction == Vector2.RIGHT:
		# Bullet going right -> enters from left -> destroys left sub-tiles
		destroy_mask = 0b1010  # TL + BL

	# Check if there are any sub-tiles to destroy on this side
	if (damage & destroy_mask) != 0:
		# Remove those sub-tiles
		damage = damage & ~destroy_mask
	else:
		# The entry side is already empty — bullet passes through and
		# hits the remaining sub-tiles on the far side, destroying them
		damage = 0

	if damage == 0:
		_remove_tile(tile_pos)
		_brick_damage.erase(tile_pos)
		Events.brick_destroyed.emit(tile_pos)
	else:
		_brick_damage[tile_pos] = damage
		_update_brick_visual(tile_pos, damage)

func _update_brick_visual(tile_pos: Vector2i, damage: int) -> void:
	if not _tile_data.has(tile_pos):
		return
	var data: Dictionary = _tile_data[tile_pos]
	var spr: Sprite2D = data["sprite"]
	if not is_instance_valid(spr):
		return

	# Create a partial brick texture based on damage
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var brick_color := Color(0.7, 0.13, 0.13)
	var mortar := Color(0.55, 0.35, 0.17)
	var transparent := Color(0, 0, 0, 0)

	var half := TILE_SIZE / 2

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var in_top_left := x < half and y < half
			var in_top_right := x >= half and y < half
			var in_bottom_left := x < half and y >= half
			var in_bottom_right := x >= half and y >= half

			var show := false
			if in_top_left and (damage & 0b1000) != 0:
				show = true
			elif in_top_right and (damage & 0b0100) != 0:
				show = true
			elif in_bottom_left and (damage & 0b0010) != 0:
				show = true
			elif in_bottom_right and (damage & 0b0001) != 0:
				show = true

			if show:
				if y % 8 == 0 or y % 8 == 7:
					img.set_pixel(x, y, mortar)
				else:
					img.set_pixel(x, y, brick_color)
			else:
				img.set_pixel(x, y, transparent)

	spr.texture = ImageTexture.create_from_image(img)

	# Update collision shape to match remaining bricks
	var body: StaticBody2D = data.get("body")
	if body and is_instance_valid(body):
		# Adjust collision to cover remaining area
		var col_shape := body.get_child(0) as CollisionShape2D
		if col_shape:
			var rect := col_shape.shape as RectangleShape2D
			# Bitmask: TL=8, TR=4, BL=2, BR=1
			var spr_pos: Vector2 = _tile_data[tile_pos]["sprite"].position
			match damage:
				0b1100:  # top half remaining (TL+TR)
					rect.size = Vector2(TILE_SIZE, TILE_SIZE / 2)
					body.position = Vector2(spr_pos.x, spr_pos.y - TILE_SIZE / 4)
				0b0011:  # bottom half remaining (BL+BR)
					rect.size = Vector2(TILE_SIZE, TILE_SIZE / 2)
					body.position = Vector2(spr_pos.x, spr_pos.y + TILE_SIZE / 4)
				0b1010:  # left half remaining (TL+BL)
					rect.size = Vector2(TILE_SIZE / 2, TILE_SIZE)
					body.position = Vector2(spr_pos.x - TILE_SIZE / 4, spr_pos.y)
				0b0101:  # right half remaining (TR+BR)
					rect.size = Vector2(TILE_SIZE / 2, TILE_SIZE)
					body.position = Vector2(spr_pos.x + TILE_SIZE / 4, spr_pos.y)

func _remove_tile(tile_pos: Vector2i) -> void:
	if not _tile_data.has(tile_pos):
		return
	var data: Dictionary = _tile_data[tile_pos]
	if data.has("sprite") and is_instance_valid(data["sprite"]):
		data["sprite"].queue_free()
	if data.has("body") and is_instance_valid(data["body"]):
		data["body"].queue_free()
	_tile_data.erase(tile_pos)

func fortify_base(duration: float) -> void:
	_is_fortified = true
	_fortify_timer = duration
	for pos in _original_base_walls:
		_remove_tile(pos)
		_place_tile(pos, LevelData.Tile.STEEL)

func _revert_fortification() -> void:
	_is_fortified = false
	for pos in _original_base_walls:
		_remove_tile(pos)
		_place_tile(pos, LevelData.Tile.BRICK)

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2(tile_pos.x * TILE_SIZE + TILE_SIZE / 2, tile_pos.y * TILE_SIZE + TILE_SIZE / 2) + global_position

func world_to_tile(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos - global_position
	var tx: int = floori(local.x / TILE_SIZE)
	var ty: int = floori(local.y / TILE_SIZE)
	return Vector2i(tx, ty)
