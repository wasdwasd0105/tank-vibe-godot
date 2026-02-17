class_name LevelManager
extends Node2D

const TILE_SIZE: int = 32
const GRID_WIDTH: int = LevelData.GRID_WIDTH   # 40
const GRID_HEIGHT: int = LevelData.GRID_HEIGHT  # 30

# Tile texture lookup: code (int) -> Texture2D
var _tile_textures: Dictionary = {}

# Containers
var terrain_node: Node2D
var tree_node: Node2D

# Two-layer tile data
# Key: Vector2i, Value: { "sprite": Sprite2D, "body": StaticBody2D or null, "code": int }
var _bg_tile_data: Dictionary = {}
var _fg_tile_data: Dictionary = {}

# Brick sub-tile damage: Key: Vector2i, Value: bitmask (TL=8, TR=4, BL=2, BR=1)
var _brick_damage: Dictionary = {}

# Hard brick HP tracking: Key: Vector2i, Value: int (remaining HP 1-4)
var _hard_brick_hp: Dictionary = {}

# Base wall fortification
var _original_base_walls: Array[Vector2i] = []
var _fortify_timer: float = -1.0
var _is_fortified: bool = false

# Brick color palettes for variants
const SOFT_BRICK_COLORS: Array = [
	Color(0.7, 0.13, 0.13),    # variant 0 - classic red
	Color(0.65, 0.18, 0.10),   # variant 1 - orange-red
	Color(0.72, 0.10, 0.15),   # variant 2 - deep red
	Color(0.68, 0.15, 0.12),   # variant 3 - brown-red
]

const HARD_BRICK_COLORS: Array = [
	Color(0.55, 0.40, 0.35),   # variant 0 - dark brown
	Color(0.50, 0.38, 0.30),   # variant 1
	Color(0.58, 0.42, 0.32),   # variant 2
	Color(0.52, 0.36, 0.33),   # variant 3
]

const IRON_COLORS: Array = [
	Color(0.75, 0.75, 0.75),   # variant 0
	Color(0.70, 0.72, 0.74),   # variant 1
	Color(0.78, 0.76, 0.74),   # variant 2
	Color(0.72, 0.74, 0.76),   # variant 3
]

const SUPER_BLOCK_COLORS: Array = [
	Color(0.80, 0.70, 0.30),   # variant 0 - gold
	Color(0.75, 0.65, 0.25),   # variant 1
	Color(0.85, 0.72, 0.28),   # variant 2
	Color(0.78, 0.68, 0.32),   # variant 3
]

const ICE_COLORS: Array = [
	Color(0.78, 0.85, 1.0),
	Color(0.70, 0.82, 0.95),
	Color(0.85, 0.90, 1.0),
	Color(0.75, 0.80, 0.95),
]

const WATER_COLORS: Array = [
	Color(0.0, 0.2, 0.59),
	Color(0.0, 0.25, 0.65),
	Color(0.05, 0.2, 0.55),
	Color(0.0, 0.18, 0.62),
]

const GRASS_COLORS: Array = [
	Color(0.0, 0.40, 0.0),
	Color(0.0, 0.36, 0.05),
	Color(0.05, 0.43, 0.0),
	Color(0.0, 0.38, 0.02),
]

const BURNED_GRASS_COLORS: Array = [
	Color(0.35, 0.28, 0.10),
	Color(0.32, 0.25, 0.12),
	Color(0.38, 0.30, 0.08),
	Color(0.34, 0.26, 0.14),
]

func _ready() -> void:
	terrain_node = $TerrainLayer
	tree_node = $TreeLayer

	_generate_textures()
	_create_boundaries()

	# Set up eagle (2x2 tiles)
	var eagle = $Eagle
	if eagle:
		eagle.add_to_group("eagle")
		var shape := RectangleShape2D.new()
		shape.size = Vector2(60, 60)
		var col_shape := eagle.get_node_or_null("CollisionShape2D")
		if col_shape:
			col_shape.shape = shape

func _process(delta: float) -> void:
	if _is_fortified:
		_fortify_timer -= delta
		if _fortify_timer <= 0:
			_revert_fortification()

# =====================================================================
# Texture Generation
# =====================================================================

func _generate_textures() -> void:
	# Ice variants (0x01-0x04)
	for i in range(4):
		_tile_textures[0x01 + i] = _create_ice_texture(ICE_COLORS[i])

	# Water variants (0x05-0x08)
	for i in range(4):
		_tile_textures[0x05 + i] = _create_water_texture(WATER_COLORS[i])

	# Grass variants (0x09-0x0C)
	for i in range(4):
		_tile_textures[0x09 + i] = _create_grass_texture(GRASS_COLORS[i])

	# Burned grass variants (0x0D-0x10)
	for i in range(4):
		_tile_textures[0x0D + i] = _create_burned_grass_texture(BURNED_GRASS_COLORS[i])

	# Soft brick full variants (0x19-0x1C)
	for i in range(4):
		_tile_textures[0x19 + i] = _create_brick_texture(SOFT_BRICK_COLORS[i])
	# Extra soft brick codes: A1, AB, AC
	_tile_textures[0xA1] = _create_brick_texture(SOFT_BRICK_COLORS[1])
	_tile_textures[0xAB] = _create_brick_texture(SOFT_BRICK_COLORS[2])
	_tile_textures[0xAC] = _create_brick_texture(SOFT_BRICK_COLORS[3])

	# Hard brick: 4 HP levels x 4 variants
	for hp in range(4, 0, -1):
		for v in range(4):
			var code := LevelData.get_hard_brick_code(hp, v)
			_tile_textures[code] = _create_hard_brick_texture(HARD_BRICK_COLORS[v], hp)

	# Iron block variants (0x39-0x3C)
	for i in range(4):
		_tile_textures[0x39 + i] = _create_iron_texture(IRON_COLORS[i])

	# Super block variants (0x3D-0x40)
	for i in range(4):
		_tile_textures[0x3D + i] = _create_super_block_texture(SUPER_BLOCK_COLORS[i])

func _create_brick_texture(base_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var mortar := Color(base_color.r * 0.6, base_color.g + 0.15, base_color.b + 0.05)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y % 8 == 0 or y % 8 == 7:
				img.set_pixel(x, y, mortar)
			elif (y < 8 or (16 <= y and y < 24)) and x % 16 == 0:
				img.set_pixel(x, y, mortar)
			elif ((8 <= y and y < 16) or 24 <= y) and (x + 8) % 16 == 0:
				img.set_pixel(x, y, mortar)
			else:
				img.set_pixel(x, y, base_color)
	return ImageTexture.create_from_image(img)

func _create_hard_brick_texture(base_color: Color, hp: int) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# Hard brick has thicker mortar lines and a slightly metallic look
	var mortar := Color(0.3, 0.25, 0.2)
	# Darken based on HP (lower HP = lighter/more cracked)
	var color_mult := 0.7 + hp * 0.075  # HP4=1.0, HP3=0.925, HP2=0.85, HP1=0.775
	var brick_col := Color(base_color.r * color_mult, base_color.g * color_mult, base_color.b * color_mult)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Thicker mortar lines for hard brick
			if y % 8 <= 1 or y % 8 >= 6:
				img.set_pixel(x, y, mortar)
			elif (y < 8 or (16 <= y and y < 24)) and x % 16 <= 1:
				img.set_pixel(x, y, mortar)
			elif ((8 <= y and y < 16) or 24 <= y) and (x + 8) % 16 <= 1:
				img.set_pixel(x, y, mortar)
			else:
				img.set_pixel(x, y, brick_col)
	return ImageTexture.create_from_image(img)

func _create_iron_texture(base_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var highlight := Color(base_color.r + 0.13, base_color.g + 0.13, base_color.b + 0.13)
	var shadow := Color(base_color.r - 0.25, base_color.g - 0.25, base_color.b - 0.25)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x < 2 or y < 2:
				img.set_pixel(x, y, highlight)
			elif x >= TILE_SIZE - 2 or y >= TILE_SIZE - 2:
				img.set_pixel(x, y, shadow)
			else:
				img.set_pixel(x, y, base_color)
	return ImageTexture.create_from_image(img)

func _create_super_block_texture(base_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var highlight := Color(minf(base_color.r + 0.15, 1.0), minf(base_color.g + 0.15, 1.0), minf(base_color.b + 0.10, 1.0))
	var shadow := Color(base_color.r * 0.6, base_color.g * 0.6, base_color.b * 0.6)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if x < 3 or y < 3:
				img.set_pixel(x, y, highlight)
			elif x >= TILE_SIZE - 3 or y >= TILE_SIZE - 3:
				img.set_pixel(x, y, shadow)
			else:
				# Diamond pattern for super block
				var cx := absi(x - TILE_SIZE / 2)
				var cy := absi(y - TILE_SIZE / 2)
				if (cx + cy) % 6 < 2:
					img.set_pixel(x, y, highlight)
				else:
					img.set_pixel(x, y, base_color)
	return ImageTexture.create_from_image(img)

func _create_ice_texture(base_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var v := ((x + y) % 4) * 0.03
			img.set_pixel(x, y, Color(
				minf(base_color.r + v, 1.0),
				minf(base_color.g + v, 1.0),
				minf(base_color.b, 1.0)
			))
	return ImageTexture.create_from_image(img)

func _create_water_texture(base_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var wave := absi(((x + y) % 8) - 4)
			var b_offset := wave * 0.06
			img.set_pixel(x, y, Color(
				base_color.r,
				base_color.g + b_offset * 0.5,
				minf(base_color.b + b_offset, 1.0)
			))
	return ImageTexture.create_from_image(img)

func _create_grass_texture(base_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if ((x + y * 3) * 7) % 5 < 3:
				img.set_pixel(x, y, Color(base_color.r, minf(base_color.g + 0.1, 1.0), base_color.b))
			else:
				img.set_pixel(x, y, base_color)
	return ImageTexture.create_from_image(img)

func _create_burned_grass_texture(base_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if ((x + y * 3) * 7) % 5 < 3:
				img.set_pixel(x, y, Color(base_color.r + 0.05, base_color.g + 0.03, base_color.b))
			else:
				img.set_pixel(x, y, Color(base_color.r - 0.05, base_color.g - 0.03, base_color.b))
	return ImageTexture.create_from_image(img)

# =====================================================================
# Boundaries
# =====================================================================

func _create_boundaries() -> void:
	var boundary_positions := []
	for x in range(-1, GRID_WIDTH + 1):
		boundary_positions.append(Vector2i(x, -1))
		boundary_positions.append(Vector2i(x, GRID_HEIGHT))
	for y in range(GRID_HEIGHT):
		boundary_positions.append(Vector2i(-1, y))
		boundary_positions.append(Vector2i(GRID_WIDTH, y))

	for pos in boundary_positions:
		var body := StaticBody2D.new()
		body.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("boundary")
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		shape.shape = rect
		body.add_child(shape)
		add_child(body)

# =====================================================================
# Stage Loading
# =====================================================================

func load_stage(stage_num: int) -> void:
	_clear_tiles()
	_brick_damage.clear()
	_hard_brick_hp.clear()

	var stages := LevelData.get_stages()
	var stage_index := stage_num - 1
	if stage_index < 0 or stage_index >= stages.size():
		stage_index = 0

	if stages.is_empty():
		push_error("LevelManager: No stages loaded!")
		return

	var stage_data: LevelData.StageData = stages[stage_index]

	for y in range(LevelData.GRID_HEIGHT):
		for x in range(LevelData.GRID_WIDTH):
			# BG layer
			if y < stage_data.bg_grid.size() and x < stage_data.bg_grid[y].size():
				var bg_code: int = stage_data.bg_grid[y][x]
				if bg_code != 0x00:
					_place_bg_tile(Vector2i(x, y), bg_code)
			# FG layer
			if y < stage_data.fg_grid.size() and x < stage_data.fg_grid[y].size():
				var fg_code: int = stage_data.fg_grid[y][x]
				if fg_code != 0x00:
					_place_fg_tile(Vector2i(x, y), fg_code)

	_place_base_walls()

func _clear_tiles() -> void:
	for pos in _bg_tile_data.keys():
		var data: Dictionary = _bg_tile_data[pos]
		if data.has("sprite") and is_instance_valid(data["sprite"]):
			data["sprite"].queue_free()
		if data.has("body") and is_instance_valid(data["body"]):
			data["body"].queue_free()
	_bg_tile_data.clear()

	for pos in _fg_tile_data.keys():
		var data: Dictionary = _fg_tile_data[pos]
		if data.has("sprite") and is_instance_valid(data["sprite"]):
			data["sprite"].queue_free()
		if data.has("body") and is_instance_valid(data["body"]):
			data["body"].queue_free()
	_fg_tile_data.clear()

# =====================================================================
# Tile Placement
# =====================================================================

func _place_bg_tile(pos: Vector2i, code: int) -> void:
	var world_pos := Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	var cat := LevelData.get_tile_category(code)

	var spr := Sprite2D.new()
	spr.position = world_pos
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.texture = _tile_textures.get(code, null)

	var body: StaticBody2D = null

	match cat:
		LevelData.TileCategory.ICE:
			terrain_node.add_child(spr)
		LevelData.TileCategory.WATER:
			body = _create_tile_body(world_pos, 2)  # water layer
			terrain_node.add_child(spr)
		_:
			terrain_node.add_child(spr)

	_bg_tile_data[pos] = { "sprite": spr, "body": body, "code": code }

func _place_fg_tile(pos: Vector2i, code: int) -> void:
	var world_pos := Vector2(pos.x * TILE_SIZE + TILE_SIZE / 2, pos.y * TILE_SIZE + TILE_SIZE / 2)
	var cat := LevelData.get_tile_category(code)

	var spr := Sprite2D.new()
	spr.position = world_pos
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var body: StaticBody2D = null

	match cat:
		LevelData.TileCategory.GRASS, LevelData.TileCategory.BURNED_GRASS:
			spr.texture = _tile_textures.get(code, null)
			spr.z_index = 10  # draw above tanks
			spr.modulate.a = 0.55  # semi-transparent so tanks are visible underneath
			tree_node.add_child(spr)

		LevelData.TileCategory.SOFT_BRICK_FULL:
			spr.texture = _tile_textures.get(code, null)
			body = _create_tile_body(world_pos, 1)
			_brick_damage[pos] = 0b1111
			terrain_node.add_child(spr)

		LevelData.TileCategory.SOFT_BRICK_PARTIAL:
			var damage_mask := LevelData.get_soft_brick_damage_mask(code)
			_brick_damage[pos] = damage_mask
			var variant := LevelData.get_variant_index(code)
			var brick_color: Color = SOFT_BRICK_COLORS[clampi(variant, 0, 3)]
			spr.texture = _create_partial_brick_texture(damage_mask, brick_color)
			body = _create_tile_body(world_pos, 1)
			_adjust_collision_for_damage(body, world_pos, damage_mask)
			terrain_node.add_child(spr)

		LevelData.TileCategory.HARD_BRICK:
			var hp := LevelData.get_hard_brick_hp(code)
			_hard_brick_hp[pos] = hp
			spr.texture = _tile_textures.get(code, null)
			body = _create_tile_body(world_pos, 1)
			terrain_node.add_child(spr)

		LevelData.TileCategory.IRON_BLOCK:
			spr.texture = _tile_textures.get(code, null)
			body = _create_tile_body(world_pos, 1)
			terrain_node.add_child(spr)

		LevelData.TileCategory.SUPER_BLOCK:
			spr.texture = _tile_textures.get(code, null)
			body = _create_tile_body(world_pos, 1)
			terrain_node.add_child(spr)

		_:
			# Unknown FG code, just place as decoration
			spr.texture = _tile_textures.get(code, null)
			terrain_node.add_child(spr)

	_fg_tile_data[pos] = { "sprite": spr, "body": body, "code": code }

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

# =====================================================================
# Base Walls & Fortification
# =====================================================================

func _place_base_walls() -> void:
	_original_base_walls.clear()
	var ec: int = LevelData.EAGLE_COL
	var er: int = LevelData.EAGLE_ROW
	var wall_positions := [
		Vector2i(ec - 1, er - 1), Vector2i(ec, er - 1), Vector2i(ec + 1, er - 1), Vector2i(ec + 2, er - 1),
		Vector2i(ec - 1, er), Vector2i(ec - 1, er + 1),
		Vector2i(ec + 2, er), Vector2i(ec + 2, er + 1),
	]
	for pos in wall_positions:
		if not _fg_tile_data.has(pos):
			_place_fg_tile(pos, 0x19)  # Soft brick variant 0
		_original_base_walls.append(pos)

func fortify_base(duration: float) -> void:
	_is_fortified = true
	_fortify_timer = duration
	for pos in _original_base_walls:
		_remove_fg_tile(pos)
		_brick_damage.erase(pos)
		_place_fg_tile(pos, 0x39)  # Iron block

func _revert_fortification() -> void:
	_is_fortified = false
	for pos in _original_base_walls:
		_remove_fg_tile(pos)
		_place_fg_tile(pos, 0x19)  # Soft brick

# =====================================================================
# Tile Removal
# =====================================================================

func _remove_fg_tile(tile_pos: Vector2i) -> void:
	if not _fg_tile_data.has(tile_pos):
		return
	var data: Dictionary = _fg_tile_data[tile_pos]
	if data.has("sprite") and is_instance_valid(data["sprite"]):
		data["sprite"].queue_free()
	if data.has("body") and is_instance_valid(data["body"]):
		data["body"].queue_free()
	_fg_tile_data.erase(tile_pos)

func _remove_bg_tile(tile_pos: Vector2i) -> void:
	if not _bg_tile_data.has(tile_pos):
		return
	var data: Dictionary = _bg_tile_data[tile_pos]
	if data.has("sprite") and is_instance_valid(data["sprite"]):
		data["sprite"].queue_free()
	if data.has("body") and is_instance_valid(data["body"]):
		data["body"].queue_free()
	_bg_tile_data.erase(tile_pos)

# =====================================================================
# Soft Brick Damage
# =====================================================================

func _damage_brick(tile_pos: Vector2i, from_direction: Vector2) -> void:
	if not _brick_damage.has(tile_pos):
		return

	var damage: int = _brick_damage[tile_pos]

	var destroy_mask: int = 0
	if from_direction == Vector2.UP:
		destroy_mask = 0b0011  # BL + BR
	elif from_direction == Vector2.DOWN:
		destroy_mask = 0b1100  # TL + TR
	elif from_direction == Vector2.LEFT:
		destroy_mask = 0b0101  # TR + BR
	elif from_direction == Vector2.RIGHT:
		destroy_mask = 0b1010  # TL + BL

	if (damage & destroy_mask) != 0:
		damage = damage & ~destroy_mask
	else:
		damage = 0

	if damage == 0:
		_remove_fg_tile(tile_pos)
		_brick_damage.erase(tile_pos)
		Events.brick_destroyed.emit(tile_pos)
	else:
		_brick_damage[tile_pos] = damage
		_update_brick_visual(tile_pos, damage)

func _update_brick_visual(tile_pos: Vector2i, damage: int) -> void:
	if not _fg_tile_data.has(tile_pos):
		return
	var data: Dictionary = _fg_tile_data[tile_pos]
	var spr: Sprite2D = data["sprite"]
	if not is_instance_valid(spr):
		return

	# Get brick color from the stored code's variant
	var code: int = data.get("code", 0x19)
	var variant := LevelData.get_variant_index(code)
	var brick_color: Color = SOFT_BRICK_COLORS[clampi(variant, 0, 3)]

	spr.texture = _create_partial_brick_texture(damage, brick_color)

	# Update collision shape
	var body: StaticBody2D = data.get("body")
	if body and is_instance_valid(body):
		var spr_pos: Vector2 = spr.position
		_adjust_collision_for_damage(body, spr_pos, damage)

func _create_partial_brick_texture(damage: int, brick_color: Color) -> Texture2D:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var mortar := Color(brick_color.r * 0.6, brick_color.g + 0.15, brick_color.b + 0.05)
	var transparent := Color(0, 0, 0, 0)
	var half := TILE_SIZE / 2

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var in_tl := x < half and y < half
			var in_tr := x >= half and y < half
			var in_bl := x < half and y >= half
			var in_br := x >= half and y >= half

			var show := false
			if in_tl and (damage & 0b1000) != 0:
				show = true
			elif in_tr and (damage & 0b0100) != 0:
				show = true
			elif in_bl and (damage & 0b0010) != 0:
				show = true
			elif in_br and (damage & 0b0001) != 0:
				show = true

			if show:
				if y % 8 == 0 or y % 8 == 7:
					img.set_pixel(x, y, mortar)
				else:
					img.set_pixel(x, y, brick_color)
			else:
				img.set_pixel(x, y, transparent)

	return ImageTexture.create_from_image(img)

func _adjust_collision_for_damage(body: StaticBody2D, sprite_pos: Vector2, damage: int) -> void:
	if not body or not is_instance_valid(body):
		return
	var col_shape := body.get_child(0) as CollisionShape2D
	if not col_shape:
		return
	var rect := col_shape.shape as RectangleShape2D
	if not rect:
		return

	match damage:
		0b1100:  # top half (TL+TR)
			rect.size = Vector2(TILE_SIZE, TILE_SIZE / 2)
			body.position = Vector2(sprite_pos.x, sprite_pos.y - TILE_SIZE / 4)
		0b0011:  # bottom half (BL+BR)
			rect.size = Vector2(TILE_SIZE, TILE_SIZE / 2)
			body.position = Vector2(sprite_pos.x, sprite_pos.y + TILE_SIZE / 4)
		0b1010:  # left half (TL+BL)
			rect.size = Vector2(TILE_SIZE / 2, TILE_SIZE)
			body.position = Vector2(sprite_pos.x - TILE_SIZE / 4, sprite_pos.y)
		0b0101:  # right half (TR+BR)
			rect.size = Vector2(TILE_SIZE / 2, TILE_SIZE)
			body.position = Vector2(sprite_pos.x + TILE_SIZE / 4, sprite_pos.y)
		_:
			# For single quadrant or non-standard combos, use full size
			rect.size = Vector2(TILE_SIZE, TILE_SIZE)
			body.position = sprite_pos

# =====================================================================
# Hard Brick Damage
# =====================================================================

func _damage_hard_brick(tile_pos: Vector2i) -> void:
	if not _hard_brick_hp.has(tile_pos):
		return
	_hard_brick_hp[tile_pos] -= 1
	if _hard_brick_hp[tile_pos] <= 0:
		_remove_fg_tile(tile_pos)
		_hard_brick_hp.erase(tile_pos)
	else:
		_update_hard_brick_visual(tile_pos)

func _update_hard_brick_visual(tile_pos: Vector2i) -> void:
	if not _fg_tile_data.has(tile_pos):
		return
	var data: Dictionary = _fg_tile_data[tile_pos]
	var old_code: int = data["code"]
	var variant := LevelData.get_variant_index(old_code)
	var hp: int = _hard_brick_hp[tile_pos]
	var new_code := LevelData.get_hard_brick_code(hp, variant)
	data["code"] = new_code
	var spr: Sprite2D = data["sprite"]
	if is_instance_valid(spr):
		spr.texture = _tile_textures.get(new_code, spr.texture)

# =====================================================================
# Bullet Hit Handler (backup for physics-based detection)
# =====================================================================

func handle_bullet_hit_body(bullet: Bullet, body: StaticBody2D) -> void:
	for pos in _fg_tile_data.keys():
		var data: Dictionary = _fg_tile_data[pos]
		if data.get("body") == body:
			var code: int = data["code"]
			var cat := LevelData.get_tile_category(code)
			match cat:
				LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
					_damage_brick(pos, bullet.direction)
					bullet._destroy()
					return
				LevelData.TileCategory.HARD_BRICK:
					_damage_hard_brick(pos)
					bullet._destroy()
					return
				LevelData.TileCategory.IRON_BLOCK:
					if bullet.can_destroy_steel:
						_remove_fg_tile(pos)
					bullet._destroy()
					return
				LevelData.TileCategory.SUPER_BLOCK:
					bullet._destroy()
					return
			break
	bullet._destroy()

# =====================================================================
# Utility
# =====================================================================

func tile_to_world(tile_pos: Vector2i) -> Vector2:
	return Vector2(tile_pos.x * TILE_SIZE + TILE_SIZE / 2, tile_pos.y * TILE_SIZE + TILE_SIZE / 2) + global_position

func world_to_tile(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos - global_position
	var tx: int = floori(local.x / TILE_SIZE)
	var ty: int = floori(local.y / TILE_SIZE)
	return Vector2i(tx, ty)
