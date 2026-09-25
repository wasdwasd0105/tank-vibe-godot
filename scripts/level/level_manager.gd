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

# Animated tiles (ice/water/iron/super): sprites that cycle a 4-frame loop in sync.
const TILE_ANIM_FRAME_DUR: float = 1.0
const TILE_ANIM_DIR: String = "res://assets/sprites/tiles_anim/"
var _animated_tile_frames: Dictionary = {}   # TileCategory -> Array[Texture2D]
var _animated_tiles: Array = []              # Array of { "sprite": Sprite2D, "cat": int }
var _tile_anim_time: float = 0.0
var _tile_anim_frame: int = 0

# Static grass variants (green + burned) from the tileset, picked by map code.
var _grass_variants: Dictionary = {}         # TileCategory -> Array[Texture2D]

var _ground_fire_scene := preload("res://scripts/effects/ground_fire.gd")

# Background image
var _bg_image_sprite: Sprite2D
var _bg_color_rect: ColorRect

# Base wall fortification. Key: wall tile (Vector2i) -> its initial tile code, so
# reverting the shovel restores the map's original base walls (not a fixed brick).
var _original_base_walls: Dictionary = {}
var _fortify_timer: float = -1.0
var _is_fortified: bool = false

# The 2x2 tiles the eagle occupies — reserved so tanks never spawn on the base.
var _eagle_tiles: Array[Vector2i] = []

const BG_ASSETS_DIR: String = "res://assets/background/"

func _ready() -> void:
	terrain_node = $TerrainLayer
	tree_node = $TreeLayer
	_bg_image_sprite = $BackgroundImage
	_bg_color_rect = $BackgroundColor

	# Get textures from ThemeManager (procedural or image-based)
	_tile_textures = ThemeManager.get_all_tile_textures()
	ThemeManager.theme_changed.connect(_on_theme_changed)

	_load_animated_tile_frames()
	_load_grass_variants()
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
		# The eagle occupies a 2x2 block; reserve it so nothing spawns on the base.
		var etl: Vector2i = world_to_tile(eagle.global_position) - Vector2i(1, 1)
		_eagle_tiles.clear()
		for oy in range(2):
			for ox in range(2):
				_eagle_tiles.append(etl + Vector2i(ox, oy))

func _process(delta: float) -> void:
	if _is_fortified:
		_fortify_timer -= delta
		if _fortify_timer <= 0:
			_revert_fortification()
	_tick_fire(delta)
	_tick_grass_fire(delta)
	_tick_ice_melt(delta)
	_tick_tile_anim(delta)

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
	_clear_fire()
	_clear_mines()
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

	# The stage's flat colour sits behind the image; stages with no image (and
	# any whose image is missing) show it instead of a black void.
	if _bg_color_rect:
		_bg_color_rect.color = stage_data.bg_color
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
		_bg_image_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
	_animated_tiles.clear()  # sprites are freed above; drop the stale references

# =====================================================================
# Tile Placement
# =====================================================================

## Load the 4-frame animation strips for ice/water/iron/super from tiles_anim/.
func _load_animated_tile_frames() -> void:
	var by_cat := {
		LevelData.TileCategory.ICE: "ice",
		LevelData.TileCategory.WATER: "water",
		LevelData.TileCategory.IRON_BLOCK: "iron",
		LevelData.TileCategory.SUPER_BLOCK: "super",
	}
	for cat in by_cat:
		var frames: Array = []
		for f in range(1, 5):
			var img := Image.new()
			if img.load(ProjectSettings.globalize_path(TILE_ANIM_DIR + "%s_%d.png" % [by_cat[cat], f])) == OK:
				img.convert(Image.FORMAT_RGBA8)
				frames.append(ImageTexture.create_from_image(img))
		if frames.size() == 4:
			_animated_tile_frames[cat] = frames

## Load the 4 static grass variants (green + burned) from the tileset.
func _load_grass_variants() -> void:
	var by_cat := {
		LevelData.TileCategory.GRASS: "grass",
		LevelData.TileCategory.BURNED_GRASS: "burned_grass",
	}
	for cat in by_cat:
		var frames: Array = []
		for f in range(1, 5):
			var img := Image.new()
			if img.load(ProjectSettings.globalize_path(TILE_ANIM_DIR + "%s_%d.png" % [by_cat[cat], f])) == OK:
				img.convert(Image.FORMAT_RGBA8)
				frames.append(ImageTexture.create_from_image(img))
		if frames.size() == 4:
			_grass_variants[cat] = frames

## The grass texture for a map code — the tileset variant its id selects
## (green 0x09-0x0C -> 0-3, burned 0x0D-0x10 -> 0-3), or the theme texture if the
## tileset isn't loaded.
func _grass_texture(code: int) -> Texture2D:
	var cat := LevelData.get_tile_category(code)
	if _grass_variants.has(cat):
		var base := 0x09 if cat == LevelData.TileCategory.GRASS else 0x0D
		return _grass_variants[cat][clampi(code - base, 0, 3)]
	return _tile_textures.get(code, null)

## If [param cat] is an animated tile type, swap the sprite to the animation and
## register it so it cycles with the others.
func _maybe_animate_tile(spr: Sprite2D, code: int, pos: Vector2i) -> void:
	var cat := LevelData.get_tile_category(code)
	if not _animated_tile_frames.has(cat):
		return
	var frames: Array = _animated_tile_frames[cat]
	# Per-tile start frame so a field animates with variety instead of in unison:
	# ice/water use their map code; iron/super use their board position (x+y).
	var offset := _anim_start_offset(cat, code, pos)
	var tex := frames[(_tile_anim_frame + offset) % frames.size()] as Texture2D
	spr.texture = tex
	# Frames are native 16px; scale to the 32px tile.
	var tw := tex.get_size().x
	if tw > 0:
		spr.scale = Vector2(TILE_SIZE / tw, TILE_SIZE / tw)
	_animated_tiles.append({ "sprite": spr, "cat": cat, "offset": offset })

## Per-tile animation start frame. Ice/water use their code's variant index
## (0-3); iron/super use their board position (x+y) so a wall shimmers in a wave.
func _anim_start_offset(cat: int, code: int, pos: Vector2i) -> int:
	match cat:
		LevelData.TileCategory.ICE:
			return clampi(code - 0x01, 0, 3)
		LevelData.TileCategory.WATER:
			return clampi(code - 0x05, 0, 3)
		LevelData.TileCategory.IRON_BLOCK, LevelData.TileCategory.SUPER_BLOCK:
			return (pos.x + pos.y) % 4
	return 0

func _tick_tile_anim(delta: float) -> void:
	if _animated_tiles.is_empty():
		return
	_tile_anim_time += delta
	var f := int(_tile_anim_time / TILE_ANIM_FRAME_DUR) % 4
	if f == _tile_anim_frame:
		return  # only touch sprites when the frame actually changes
	_tile_anim_frame = f
	var alive: Array = []
	for a in _animated_tiles:
		var spr = a["sprite"]
		if is_instance_valid(spr):
			var frames: Array = _animated_tile_frames[a["cat"]]
			(spr as Sprite2D).texture = frames[(f + int(a["offset"])) % frames.size()]
			alive.append(a)
	_animated_tiles = alive

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

	_maybe_animate_tile(spr, code, pos)
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
			var gtex := _grass_texture(code)  # variant picked by the map code
			spr.texture = gtex
			if gtex:
				var gw := gtex.get_size().x
				if gw > 0:
					spr.scale = Vector2(TILE_SIZE / gw, TILE_SIZE / gw)  # 16px tile -> 32px
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

	_maybe_animate_tile(spr, code, pos)
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
			_place_fg_tile(pos, 0x19)  # Soft brick variant 0 (fill an empty base tile)
		# Remember the exact initial tile here so the shovel can restore it later.
		_original_base_walls[pos] = _fg_tile_data[pos].get("code", 0x19)

func fortify_base(duration: float) -> void:
	_is_fortified = true
	_fortify_timer = duration
	_set_flag_invincible(true)
	for pos in _original_base_walls:
		# A super block is already stronger than iron — never downgrade it.
		if LevelData.get_tile_category(_original_base_walls[pos]) == LevelData.TileCategory.SUPER_BLOCK:
			continue
		_remove_fg_tile(pos)
		_brick_damage.erase(pos)
		_hard_brick_hp.erase(pos)
		_place_fg_tile(pos, 0x39)  # Iron block (fortified)

func _revert_fortification() -> void:
	_is_fortified = false
	_set_flag_invincible(false)
	for pos in _original_base_walls:
		# Super blocks were left untouched by fortify — nothing to revert.
		if LevelData.get_tile_category(_original_base_walls[pos]) == LevelData.TileCategory.SUPER_BLOCK:
			continue
		_remove_fg_tile(pos)
		_brick_damage.erase(pos)
		_hard_brick_hp.erase(pos)
		_place_fg_tile(pos, _original_base_walls[pos])  # restore the map's initial tile

## An enemy took "Flag On Guard": the players' fortification, if the base has
## one, ends at once. The original ran every guard timer 30000 ticks on, all
## that one pickup gives the wall ring, so only a ring stacked from several
## pickups outlasted it; the remake's fortification never stacks.
func break_base_guard() -> void:
	if _is_fortified:
		_revert_fortification()

func _set_flag_invincible(value: bool) -> void:
	var flag := get_node_or_null("Eagle")
	if flag is BaseFlag:
		flag.invincible = value

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

## True if the foreground tile at [param tile] is a solid wall
## (soft/hard brick, iron or super).
func is_tile_solid(tile: Vector2i) -> bool:
	if not _fg_tile_data.has(tile):
		return false
	return LevelData.is_solid_tile(LevelData.get_tile_category(_fg_tile_data[tile].get("code", 0)))

## True if the foreground tile at [param world_pos] is a solid wall. Used e.g. by
## the explosion wave to know a sprayed cell landed on a wall.
func is_solid_at_world(world_pos: Vector2) -> bool:
	return is_tile_solid(world_to_tile(world_pos))

## True if the background tile at [param world_pos] is water (used to sink a tank
## that loses its water-resist while afloat).
func is_water_at_world(world_pos: Vector2) -> bool:
	var tile := world_to_tile(world_pos)
	if not _bg_tile_data.has(tile):
		return false
	return LevelData.get_tile_category(_bg_tile_data[tile].get("code", 0)) == LevelData.TileCategory.WATER

## The bodies of the water tiles a tank centred at [param world_pos] sits on.
func water_bodies_under(world_pos: Vector2) -> Array:
	var found: Array = []
	var edge := Vector2(BaseTank.BODY_EDGE, BaseTank.BODY_EDGE)
	var from := world_to_tile(world_pos - edge)
	var to := world_to_tile(world_pos + edge)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var tile := Vector2i(x, y)
			if _is_water_tile(tile) and is_instance_valid(_bg_tile_data[tile].get("body")):
				found.append(_bg_tile_data[tile]["body"])
	return found

## True if every tile in the [param size] block whose top-left is [param top_left]
## is in-bounds and free of solid walls.
func is_area_clear(top_left: Vector2i, size: Vector2i) -> bool:
	for oy in range(size.y):
		for ox in range(size.x):
			var t := top_left + Vector2i(ox, oy)
			if not _is_in_bounds(t) or is_tile_solid(t) or t in _eagle_tiles:
				return false
	return true

## True if an enemy may come in on the [param size] block whose top-left is
## [param top_left]: clear (see is_area_clear) and with no water either, as the
## original's spawn required (0x4981f7); grass and ice are fine.
func is_open_ground(top_left: Vector2i, size: Vector2i) -> bool:
	if not is_area_clear(top_left, size):
		return false
	for oy in range(size.y):
		for ox in range(size.x):
			if _is_water_tile(top_left + Vector2i(ox, oy)):
				return false
	return true

## The nearest [param size] block to [param ideal_top_left] whose tiles are all
## clear — the ideal itself if free, otherwise a ring search outward (used to
## revive a tank beside the base, falling back to the closest open spot when the
## base is walled in). Returns the ideal if nothing clear is found in range.
func find_clear_area(ideal_top_left: Vector2i, size: Vector2i, max_radius: int = 16) -> Vector2i:
	if is_area_clear(ideal_top_left, size):
		return ideal_top_left
	for r in range(1, max_radius + 1):
		var best := Vector2i(-9999, -9999)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue  # only the ring at radius r
				var cand := ideal_top_left + Vector2i(dx, dy)
				if is_area_clear(cand, size):
					var d := Vector2(dx, dy).length()
					if d < best_d:
						best_d = d
						best = cand
		if best.x != -9999:
			return best
	return ideal_top_left

## Clear all foreground tiles in a 2x2 area for tank spawning.
## [param global_center] is the global position of the tank center (64x64 tank).
func clear_spawn_area(global_center: Vector2) -> void:
	# Tank is 2x2 tiles; find top-left tile from the tank's top-left corner
	var top_left_world := global_center - Vector2(TILE_SIZE, TILE_SIZE)  # -32, -32
	var tl_tile := world_to_tile(top_left_world + Vector2(1, 1))  # small offset to avoid edge rounding
	for dy in range(2):
		for dx in range(2):
			var tile_pos := Vector2i(tl_tile.x + dx, tl_tile.y + dy)
			if _fg_tile_data.has(tile_pos):
				_remove_fg_tile(tile_pos)
				_brick_damage.erase(tile_pos)
				_hard_brick_hp.erase(tile_pos)

# =====================================================================
# Ground Fire (fire weapon) — growing/shrinking fire fields
# =====================================================================

const FIRE_FIELD_CAP: int = 40  # safety: max simultaneous fire fields

var _fire_fields: Array = []          # Array[FireField]
## Enemy-lit fires paused by the debug freeze (see DebugFreeze). Fires lit while
## frozen are not in here: only a player can have lit them.
var _frozen_fire_fields: Array = []   # Array[FireField]
var _frozen_grass_tiles: Dictionary = {}  # Vector2i -> true
var _fire_index: Dictionary = {}      # world tile (Vector2i) -> FireField burning it

# Grass fire: a neutral wildfire that burns green grass to grey and creeps to
# adjacent green grass one generation at a time. Hurts both sides (row 1).
const GRASS_BURN_TIME: float = 3.0    # how long a burning grass tile stays lit
const GRASS_SPREAD_DELAY: float = 0.5 # gap between spreading to the next ring of grass
const GRASS_FIRE_CAP: int = 150       # safety cap on simultaneous grass fires

var _grass_fires: Array = []          # Array of {tile, node, from_player, burn, spread, spread_done}
var _grass_index: Dictionary = {}     # tile (Vector2i) -> GroundFire node

# Fire melts ice (Tank.exe's fire terrain step, 0x497a4e: a fire whose owner is
# a player erases ice, ids 0..3 of the ice/water layer, from under itself, once,
# Rnd(500)+500 ticks after it lands; enemy and grass fires, owner -1, never do).
const ICE_MELT_DELAY_MIN: float = 0.375
const ICE_MELT_DELAY_MAX: float = 0.75
var _ice_melts: Dictionary = {}       # ice tile (Vector2i) -> seconds until it melts


# =====================================================================
# AP Weapon — wall drilling
# =====================================================================

## An AP shell drills through the [param tiles] it overlaps, spending its damage
## [param pool]. The shell is 2 tiles wide, so tiles side-by-side across its path
## form one "strip" that it carves through at once, paying only the MOST expensive
## tile in the strip — so a 2-wide channel costs the same pool as a 1-wide one.
## Returns the remaining pool (0 if fully spent).
## Costs: full brick 2, partial 1, hard brick = remaining stages, iron 4,
## super-steel 8 (and only pierceable with pool >= 6).
func ap_drill_tiles(tiles: Array[Vector2i], pool: int, from_direction: Vector2) -> int:
	if tiles.is_empty():
		return pool
	# Group tiles by their coordinate along the travel axis — each group is one
	# perpendicular strip (the tiles the shell straddles at that step).
	var vertical := absf(from_direction.y) > absf(from_direction.x)
	var groups: Dictionary = {}
	for tile in tiles:
		if not _fg_tile_data.has(tile):
			continue
		var key: int = tile.y if vertical else tile.x
		if not groups.has(key):
			groups[key] = []
		groups[key].append(tile)

	for key in groups.keys():
		if pool <= 0:
			break
		var strip: Array = groups[key]
		var has_super := false
		var max_cost := 0
		for tile in strip:
			if LevelData.get_tile_category(_fg_tile_data[tile].get("code", 0)) == LevelData.TileCategory.SUPER_BLOCK:
				has_super = true
			else:
				max_cost = maxi(max_cost, _ap_tile_cost(tile))
		if has_super:
			# Super-steel is indestructible: the shell stops here, breaks nothing.
			pool = 0
		elif pool >= max_cost:
			for tile in strip:
				_ap_break_tile(tile)
			pool -= max_cost
		else:
			for tile in strip:
				_ap_chip_tile(tile, pool, from_direction)
			pool = 0
	return maxi(pool, 0)


func _ap_tile_cost(tile: Vector2i) -> int:
	match LevelData.get_tile_category(_fg_tile_data[tile].get("code", 0)):
		LevelData.TileCategory.SOFT_BRICK_FULL: return 2
		LevelData.TileCategory.SOFT_BRICK_PARTIAL: return 1
		LevelData.TileCategory.HARD_BRICK: return _hard_brick_hp.get(tile, 1)
		LevelData.TileCategory.IRON_BLOCK: return 4
		LevelData.TileCategory.SUPER_BLOCK: return 8
	return 0


func _ap_break_tile(tile: Vector2i) -> void:
	if not _fg_tile_data.has(tile):
		return
	_remove_fg_tile(tile)
	_brick_damage.erase(tile)
	_hard_brick_hp.erase(tile)


func _ap_chip_tile(tile: Vector2i, pool: int, from_direction: Vector2) -> void:
	if not _fg_tile_data.has(tile):
		return
	match LevelData.get_tile_category(_fg_tile_data[tile].get("code", 0)):
		LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
			_damage_brick(tile, from_direction)
		LevelData.TileCategory.HARD_BRICK:
			for i in range(pool):
				_damage_hard_brick(tile)


# =====================================================================
# Mine Weapon
# =====================================================================

# Laid mines: Key: top-left tile of the mine's 2x2 block, Value: Mine.
# One mine per key, the original's mine grid (0x004db404).
var _mine_tiles: Dictionary = {}

## The 12 spots a mine may go, as offsets of the mine's 2x2 block from the
## tank's own block (both by top-left tile) that are SUBTRACTED from the tank's:
## the original's ring table at 0x004d29d0. Each is 2 tiles out, so a mine sits
## 64 px from the tank centre on a tile corner. Index 0 is straight behind a tank
## facing up, then the ring runs round the tank.
const MINE_RING: Array[Vector2i] = [
	Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -1), Vector2i(2, 0),
	Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 2), Vector2i(-1, 2),
	Vector2i(-2, 1), Vector2i(-2, 0), Vector2i(-2, -1), Vector2i(-1, -2),
]
## The order the ring is tried in, relative to the tank's facing (0x004d2d64):
## straight behind first, then the neighbours either side of that, working
## round both sides and ending straight ahead. Each facing turns the ring by 3.
const MINE_RING_ORDER: Array[int] = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6]
## A spot is refused while anything collidable has its reference point this
## close to the mine centre on both axes: the original's 48 px box, doubled.
const MINE_CLEARANCE: float = 48.0
## An armed mine's reference point: its 16 px image's corner + 16 px lands half
## a tile past its centre.
const MINE_POINT_OFFSET: Vector2 = Vector2(16, 16)


## Lay a level-[param level] mine for [param tank] on the first free spot of the
## ring around it. Returns false, spending nothing, when all 12 are blocked.
func try_place_mine(tank: BaseTank, level: int) -> bool:
	var turn := 3 * _facing_index(tank.current_direction)
	var local: Vector2 = tank.global_position - global_position
	# The tank's own 2x2 block by its top-left tile, rounded as Delphi does.
	var origin := Vector2i(
		Mine.round_half_even(local.x / TILE_SIZE - 1.0),
		Mine.round_half_even(local.y / TILE_SIZE - 1.0))
	var floats: bool = "anti-water" in tank.get_addon_names()
	for step in MINE_RING_ORDER:
		var cell: Vector2i = origin - MINE_RING[posmod(turn + step, MINE_RING.size())]
		if _mine_spot_free(cell, floats):
			_spawn_mine(cell, level, tank.is_in_group("players"), tank.get_player_index())
			return true
	return false


## True if a mine may go on the 2x2 block whose top-left tile is [param cell]:
## all four tiles on the field and wall-free (grass is fine), no water unless
## the layer floats (anti-water), no mine already keyed there, and nothing
## standing close to its centre.
func _mine_spot_free(cell: Vector2i, floats: bool) -> bool:
	# The original read off-field tiles as open ground and could drop a mine
	# where no tank ever reaches; the remake keeps every mine on the field.
	if cell.x < 0 or cell.y < 0 or cell.x > GRID_WIDTH - 2 or cell.y > GRID_HEIGHT - 2:
		return false
	if _mine_tiles.has(cell):
		return false
	for dy in range(2):
		for dx in range(2):
			var tile := cell + Vector2i(dx, dy)
			if is_tile_solid(tile):
				return false
			if not floats and _is_water_tile(tile):
				return false
	return not _mine_spot_crowded(mine_center(cell))


## The original refused a spot when any collidable sprite's reference point (its
## top-left corner + 16 px: the centre of a tank, the base or a bonus) fell in a
## box around the mine centre. That includes the layer itself, which can block
## its own side spots while it sits between tiles, and armed mines, whose point
## lies off-centre (their image is half a tank wide).
func _mine_spot_crowded(center: Vector2) -> bool:
	var points: Array[Vector2] = []
	for node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as BaseTank
		if tank and is_instance_valid(tank) and tank.collision_layer != 0:
			points.append(tank.global_position)
	var eagle := get_tree().get_first_node_in_group("eagle") as Node2D
	if eagle:
		points.append(eagle.global_position)
	for group in ["powerups_container", "bullets_container"]:
		var container := get_tree().get_first_node_in_group(group)
		if container:
			for child in container.get_children():
				if child is Node2D:
					points.append((child as Node2D).global_position)
	for mine in get_mines():
		if mine.is_armed():
			points.append(mine.global_position + MINE_POINT_OFFSET)
	for p in points:
		var d: Vector2 = p - center
		if d.x >= -MINE_CLEARANCE and d.x < MINE_CLEARANCE \
				and d.y >= -MINE_CLEARANCE and d.y < MINE_CLEARANCE:
			return true
	return false


## World position of the centre of the mine block keyed by [param cell]: the
## corner its four tiles share.
func mine_center(cell: Vector2i) -> Vector2:
	return global_position + Vector2((cell.x + 1) * TILE_SIZE, (cell.y + 1) * TILE_SIZE)


## How many of the four tiles under a tank centred at [param world_center] are
## ice: its 2x2 block, found the original's way (as for laying mines).
func ice_tiles_under(world_center: Vector2) -> int:
	var local: Vector2 = world_center - global_position
	var origin := Vector2i(
		Mine.round_half_even(local.x / TILE_SIZE - 1.0),
		Mine.round_half_even(local.y / TILE_SIZE - 1.0))
	var count := 0
	for dy in range(2):
		for dx in range(2):
			var tile := origin + Vector2i(dx, dy)
			if _bg_tile_data.has(tile) and LevelData.get_tile_category(
					_bg_tile_data[tile].get("code", 0)) == LevelData.TileCategory.ICE:
				count += 1
	return count


func has_mine(cell: Vector2i) -> bool:
	return _mine_tiles.has(cell)


## Every mine still on the field.
func get_mines() -> Array[Mine]:
	var mines: Array[Mine] = []
	for cell in _mine_tiles:
		var mine = _mine_tiles[cell]
		if is_instance_valid(mine):
			mines.append(mine)
	return mines


func unregister_mine(mine: Mine) -> void:
	if _mine_tiles.get(mine.cell) == mine:
		_mine_tiles.erase(mine.cell)


func _spawn_mine(cell: Vector2i, level: int, from_player: bool, owner_id: int = -1) -> Mine:
	var mine_script := preload("res://scripts/effects/mine.gd")
	var mine: Mine = mine_script.new()
	mine.setup(cell, level, from_player, self)
	mine.owner_id = owner_id
	mine.position = mine_center(cell) - global_position
	# Deferred: mines can be laid from inside a physics step (enemy AI move).
	_add_deferred(terrain_node, mine)
	_mine_tiles[cell] = mine
	return mine


func _is_water_tile(tile: Vector2i) -> bool:
	if not _bg_tile_data.has(tile):
		return false
	return LevelData.get_tile_category(_bg_tile_data[tile].get("code", 0)) == LevelData.TileCategory.WATER


## The original's facing numbers: 0 up, 1 right, 2 down, 3 left.
static func _facing_index(direction: Vector2) -> int:
	if direction == Vector2.RIGHT:
		return 1
	if direction == Vector2.DOWN:
		return 2
	if direction == Vector2.LEFT:
		return 3
	return 0


## Adds [param node] under [param parent] at the end of the frame: fires, mines
## and blasts are spawned from inside physics callbacks. One cleared away before
## then (a fire lit and put out in the same frame) is dropped instead: added
## after being queued for deletion, it crashed the engine a few frames later.
func _add_deferred(parent: Node, node: Node) -> void:
	_add_if_kept.call_deferred(parent, node)


func _add_if_kept(parent: Node, node: Variant) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	parent.add_child(node)


func _clear_mines() -> void:
	for cell in _mine_tiles.keys():
		var mine = _mine_tiles[cell]
		if is_instance_valid(mine):
			mine.queue_free()
	_mine_tiles.clear()


func _tick_fire(delta: float) -> void:
	if _fire_fields.is_empty():
		return
	for field in _fire_fields:
		if field not in _frozen_fire_fields:
			field.update(delta)
	var alive: Array = []
	for field in _fire_fields:
		if not field.is_dead():
			alive.append(field)
	_fire_fields = alive


## Debug freeze: pause the fires the enemy side has already lit, or resume them.
func freeze_enemy_fire(frozen: bool) -> void:
	_frozen_fire_fields.clear()
	_frozen_grass_tiles.clear()
	if not frozen:
		return
	for field in _fire_fields:
		if not field.from_player:
			_frozen_fire_fields.append(field)
	for rec in _grass_fires:
		if not rec["from_player"]:
			_frozen_grass_tiles[rec["tile"]] = true


## Ignite the ground where a fire bullet died. If the impact tile is already
## burning, grow that field by one ring (rule 3); otherwise start a new size-4
## field (rules 1/4/5/6). [param from_player] decides which side it can burn;
## [param owner_id] is the player whose shell it was (-1: an enemy's).
func ignite_fire_patch(center: Vector2i, from_player: bool, owner_id: int = -1) -> void:
	if _fire_index.has(center):
		var field = _fire_index[center]
		if field != null and not field.is_dead():
			field.feed(from_player, owner_id)
			return
	if _fire_fields.size() >= FIRE_FIELD_CAP:
		return
	var new_field := FireField.new(center, from_player, self, owner_id)
	_fire_fields.append(new_field)


## Spawn one GroundFire tile node at [param world] (deferred; ignition often
## fires from inside a physics callback). Returns null if the tile can't burn.
## A player's fire landing on ice starts melting it.
func _spawn_fire_tile(world: Vector2i, from_player: bool, arm_delay: float, owner_id: int = -1) -> GroundFire:
	if not _fire_tile_ignitable(world):
		return null
	var fire: GroundFire = _ground_fire_scene.new()
	fire.setup(world, from_player, arm_delay)
	fire.owner_id = owner_id
	fire.position = Vector2(world.x * TILE_SIZE + TILE_SIZE / 2, world.y * TILE_SIZE + TILE_SIZE / 2)
	_add_deferred(terrain_node, fire)
	if from_player and _is_ice(world) and not _ice_melts.has(world):
		_ice_melts[world] = randf_range(ICE_MELT_DELAY_MIN, ICE_MELT_DELAY_MAX)
	return fire


func _fire_tile_ignitable(tile: Vector2i) -> bool:
	if not _is_in_bounds(tile):
		return false
	# No fire on solid walls (brick/steel/super). Burned grass DOES burn — it's
	# scorched ground now, no different from regular open dirt. Water and ice
	# burn like ground too (as in the original, whose placement never looks at
	# that layer); a player's fire then melts the ice under it.
	if _fg_tile_data.has(tile):
		var cat := LevelData.get_tile_category(_fg_tile_data[tile].get("code", 0))
		if LevelData.is_solid_tile(cat):
			return false
	return true


func _is_ice(tile: Vector2i) -> bool:
	return _bg_tile_data.has(tile) and LevelData.get_tile_category(
			_bg_tile_data[tile].get("code", 0)) == LevelData.TileCategory.ICE


## Melts the ice tiles whose fire has burned long enough: bare ground is left,
## and tanks no longer slide there.
func _tick_ice_melt(delta: float) -> void:
	if _ice_melts.is_empty():
		return
	for tile: Vector2i in _ice_melts.keys():
		_ice_melts[tile] -= delta
		if _ice_melts[tile] <= 0.0:
			_ice_melts.erase(tile)
			if _is_ice(tile):
				_remove_bg_tile(tile)


func _is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < GRID_WIDTH and tile.y >= 0 and tile.y < GRID_HEIGHT


func _clear_fire() -> void:
	for field in _fire_fields:
		field.force_clear()
	_fire_fields.clear()
	_fire_index.clear()
	for rec in _grass_fires:
		if is_instance_valid(rec["node"]):
			rec["node"].queue_free()
	_grass_fires.clear()
	_grass_index.clear()
	_ice_melts.clear()


## Set a green grass tile alight: scorch it to grey immediately, spawn a neutral
## grass fire that hurts both sides, and schedule it to creep to its neighbours.
## Called by a fire field when it reaches grass, and by the spread step.
func ignite_grass(tile: Vector2i, from_player: bool) -> void:
	if not _is_green_grass(tile):
		return
	if _grass_index.has(tile):
		return
	if _grass_fires.size() >= GRASS_FIRE_CAP:
		return
	_convert_grass_to_burned(tile)  # green -> grey (permanent)
	var fire: GroundFire = _ground_fire_scene.new()
	fire.is_grass_fire = true
	fire.setup(tile, from_player, GroundFire.ARM_DELAY)
	fire.position = Vector2(tile.x * TILE_SIZE + TILE_SIZE / 2, tile.y * TILE_SIZE + TILE_SIZE / 2)
	_add_deferred(terrain_node, fire)
	_grass_index[tile] = fire
	_grass_fires.append({
		"tile": tile, "node": fire, "from_player": from_player,
		"burn": GRASS_BURN_TIME, "spread": GRASS_SPREAD_DELAY, "spread_done": false,
	})


func _tick_grass_fire(delta: float) -> void:
	if _grass_fires.is_empty():
		return
	# Tick a snapshot so fires spawned by this frame's spread wait until next frame.
	for rec in _grass_fires.duplicate():
		if _frozen_grass_tiles.has(rec["tile"]):
			continue
		rec["burn"] -= delta
		if not rec["spread_done"]:
			rec["spread"] -= delta
			if rec["spread"] <= 0.0:
				rec["spread_done"] = true
				var t: Vector2i = rec["tile"]
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					ignite_grass(t + d, rec["from_player"])
	var alive: Array = []
	for rec in _grass_fires:
		if rec["burn"] > 0.0:
			alive.append(rec)
		else:
			_grass_index.erase(rec["tile"])
			if is_instance_valid(rec["node"]):
				rec["node"].start_decay(randf() * 0.5)
	_grass_fires = alive


func _is_green_grass(tile: Vector2i) -> bool:
	if not _fg_tile_data.has(tile):
		return false
	return LevelData.get_tile_category(_fg_tile_data[tile].get("code", 0)) == LevelData.TileCategory.GRASS


## Convert a green grass tile to its grey burned variant (code + 4), permanently.
func _convert_grass_to_burned(tile: Vector2i) -> void:
	if not _fg_tile_data.has(tile):
		return
	var data: Dictionary = _fg_tile_data[tile]
	var new_code: int = data.get("code", 0) + 4  # GRASS 0x09-0x0C -> BURNED 0x0D-0x10
	data["code"] = new_code
	if data.has("sprite") and is_instance_valid(data["sprite"]):
		# Burned variant keeps the same index as the green tile it replaces.
		var btex := _grass_texture(new_code)
		if btex:
			data["sprite"].texture = btex


# =====================================================================
# Explosion Weapon — shockwave blast
# =====================================================================

## Detonate a shockwave at [param world_pos]. Called from an explosion bullet's
## death (and, later, mines). Deferred add_child because detonation usually fires
## from inside a physics callback (a bullet's collision).
func spawn_explosion_blast(world_pos: Vector2, level: int, from_player: bool, neutral: bool = false, exclude: Node = null, owner_id: int = -1) -> void:
	var blast := ExplosionBlast.new()
	blast.setup(level, from_player, self, neutral, exclude, owner_id)
	blast.global_position = world_pos
	var container: Node = get_tree().get_first_node_in_group("effects_container")
	if container == null:
		container = terrain_node
	_add_deferred(container, blast)


## Break destructible terrain within [param radius_half_tiles] of the blast center,
## skipping wall-shadowed tiles. Soft bricks are destroyed; hard bricks step down
## one HP; steel (iron/super), water and the base are left untouched.
func explosion_destroy_terrain(center: Vector2i, radius_half_tiles: float) -> void:
	var reach := int(ceil(radius_half_tiles / 2.0))
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := Vector2i(center.x + dx, center.y + dy)
			if not _is_in_bounds(tile) or not _fg_tile_data.has(tile):
				continue
			var dist_half_tiles := sqrt(float(dx * dx + dy * dy)) * 2.0
			if dist_half_tiles > radius_half_tiles:
				continue
			if not _tile_line_of_sight(center, tile):
				continue
			var cat := LevelData.get_tile_category(_fg_tile_data[tile].get("code", 0))
			match cat:
				LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
					_remove_fg_tile(tile)
					_brick_damage.erase(tile)
				LevelData.TileCategory.HARD_BRICK:
					_damage_hard_brick(tile)
				_:
					pass  # iron/super/other: fireproof to the blast


## True if no solid foreground tile sits strictly between the two world points
## (a straight-line grid raycast). Used for blast falloff shadowing.
func has_line_of_sight(from_world: Vector2, to_world: Vector2) -> bool:
	return _tile_line_of_sight(world_to_tile(from_world), world_to_tile(to_world))


func _tile_line_of_sight(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var x0: int = from_tile.x
	var y0: int = from_tile.y
	var dx: int = absi(to_tile.x - x0)
	var dy: int = -absi(to_tile.y - y0)
	var sx: int = 1 if x0 < to_tile.x else -1
	var sy: int = 1 if y0 < to_tile.y else -1
	var err: int = dx + dy
	while true:
		if Vector2i(x0, y0) == to_tile:
			return true
		if Vector2i(x0, y0) != from_tile and _fg_tile_data.has(Vector2i(x0, y0)):
			var cat := LevelData.get_tile_category(_fg_tile_data[Vector2i(x0, y0)].get("code", 0))
			if LevelData.is_solid_tile(cat):
				return false
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return true
