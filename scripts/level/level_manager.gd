class_name LevelManager
extends Node2D

const TILE_SIZE: int = 32
const GRID_WIDTH: int = LevelData.GRID_WIDTH   # 40
const GRID_HEIGHT: int = LevelData.GRID_HEIGHT  # 30

# Tile texture lookup: code (int) -> Texture2D  (populated from ThemeManager)
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

# Background image
var _bg_image_sprite: Sprite2D

# Base wall fortification
var _original_base_walls: Array[Vector2i] = []
var _fortify_timer: float = -1.0
var _is_fortified: bool = false

const BG_ASSETS_DIR: String = "res://assets/background/"

func _ready() -> void:
	terrain_node = $TerrainLayer
	tree_node = $TreeLayer
	_bg_image_sprite = $BackgroundImage

	# Get textures from ThemeManager (procedural or image-based)
	_tile_textures = ThemeManager.get_all_tile_textures()
	ThemeManager.theme_changed.connect(_on_theme_changed)

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

func _on_theme_changed(_theme_name: String) -> void:
	_tile_textures = ThemeManager.get_all_tile_textures()

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

	# Load background image if available
	_load_background_image(stage_data.bg_bitmap)

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

func _load_background_image(bg_bitmap: String) -> void:
	if not _bg_image_sprite:
		return
	_bg_image_sprite.texture = null

	if bg_bitmap.is_empty():
		return

	# Try multiple case variations since .dat files may have "BG01.JPG"
	# but actual files are "BG01.jpg"
	var name_no_ext := bg_bitmap.get_basename()
	var ext := bg_bitmap.get_extension()
	var candidates: Array[String] = [
		bg_bitmap,                                  # original: "BG02.jpg" or "BG01.JPG"
		name_no_ext + "." + ext.to_lower(),         # lowercase ext: "BG01.jpg"
		bg_bitmap.to_lower(),                       # all lowercase: "bg01.jpg"
		name_no_ext.to_upper() + "." + ext.to_lower(),  # upper name + lower ext: "BG01.jpg"
	]

	var tex: Texture2D = null
	for filename in candidates:
		var res_path := BG_ASSETS_DIR + filename
		if ResourceLoader.exists(res_path):
			tex = load(res_path) as Texture2D
			break

	if not tex:
		# Fall back to runtime image loading from filesystem
		for filename in candidates:
			var res_path := BG_ASSETS_DIR + filename
			var abs_path := ProjectSettings.globalize_path(res_path)
			var img := Image.new()
			if img.load(abs_path) == OK:
				tex = ImageTexture.create_from_image(img)
				break

	if tex:
		_bg_image_sprite.texture = tex
		var game_width: float = GRID_WIDTH * TILE_SIZE   # 1280
		var game_height: float = GRID_HEIGHT * TILE_SIZE  # 960
		var tex_size := tex.get_size()
		_bg_image_sprite.scale = Vector2(game_width / tex_size.x, game_height / tex_size.y)

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
			spr.texture = ThemeManager.get_partial_brick_texture(damage_mask, variant)
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

	# Get variant from the stored code
	var code: int = data.get("code", 0x19)
	var variant := LevelData.get_variant_index(code)

	spr.texture = ThemeManager.get_partial_brick_texture(damage, variant)

	# Update collision shape
	var body: StaticBody2D = data.get("body")
	if body and is_instance_valid(body):
		var spr_pos: Vector2 = spr.position
		_adjust_collision_for_damage(body, spr_pos, damage)

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
