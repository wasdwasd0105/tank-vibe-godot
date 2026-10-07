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

## Online, on a client: the map is the host's (net_load_map, net_set_cell) and
## none of its rules run here: no fires, no fortification clock, no melting ice.
var net_mirror := false
## The stage's background picture's file name, for net_map().
var _bg_bitmap := ""
## The enemies' way to the base (the host's).
var routes: EnemyRoutes = null

func _ready() -> void:
	terrain_node = $TerrainLayer
	tree_node = $TreeLayer
	_bg_image_sprite = $BackgroundImage
	_bg_color_rect = $BackgroundColor

	# Get textures from ThemeManager (procedural or image-based)
	_tile_textures = ThemeManager.get_all_tile_textures()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	InputSettings.enemy_mines_changed.connect(_on_enemy_mines_changed)
	InputSettings.base_invincible_changed.connect(_on_base_invincible_changed)

	_load_animated_tile_frames()
	_load_grass_variants()
	_create_boundaries()
	routes = EnemyRoutes.new()
	routes.name = "EnemyRoutes"
	routes.level_manager = self
	add_child(routes)

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
	if net_mirror:
		_tick_tile_anim(delta)
		return
	if _is_fortified:
		_fortify_timer -= delta
		if _fortify_timer <= 0:
			_revert_fortification()
	_tick_tile_anim(delta)

func _physics_process(_delta: float) -> void:
	if not net_mirror:
		_burn_tanks()

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
	_bg_bitmap = stage_data.bg_bitmap
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
	_set_flag_invincible(false)   # no guard yet, unless BASE INVINCIBLE is on
	if not net_mirror:
		routes.restart()

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
	NetHostWorld.mark_tile(pos)

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
	NetHostWorld.mark_tile(pos)

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

## The flag's guard look: while the base is fortified, and for as long as the
## BASE INVINCIBLE setting is on.
func _set_flag_invincible(value: bool) -> void:
	var flag := get_node_or_null("Eagle")
	if flag is BaseFlag:
		flag.invincible = value or InputSettings.get_base_invincible()

## BASE INVINCIBLE switched mid-stage (the pause menu): the flag shows it at once.
## (Online, a client's flag follows the host's.)
func _on_base_invincible_changed() -> void:
	if not net_mirror:
		_set_flag_invincible(_is_fortified)

# =====================================================================
# Online: the map as data (NetHostWorld sends it, NetClientWorld builds it)
# =====================================================================

## The whole map for a client new to this stage: [background colour, background
## picture, then the cells row by row as bytes: bg codes, fg codes and each
## brick's standing quarters]. 0 is an empty cell.
func net_map() -> Array:
	var count := GRID_WIDTH * GRID_HEIGHT
	var bg := PackedByteArray()
	var fg := PackedByteArray()
	var masks := PackedByteArray()
	bg.resize(count)
	fg.resize(count)
	masks.resize(count)
	for y in GRID_HEIGHT:
		for x in GRID_WIDTH:
			var cell: Array = net_cell(Vector2i(x, y))
			var i := y * GRID_WIDTH + x
			bg[i] = cell[0]
			fg[i] = cell[1]
			masks[i] = cell[2]
	var colour := _bg_color_rect.color if _bg_color_rect else Color.BLACK
	return [colour, _bg_bitmap, bg, fg, masks]

## One cell's [bg code, fg code, standing brick quarters], 0 for none.
func net_cell(cell: Vector2i) -> Array:
	var bg: int = _bg_tile_data[cell].get("code", 0) if _bg_tile_data.has(cell) else 0
	var fg: int = _fg_tile_data[cell].get("code", 0) if _fg_tile_data.has(cell) else 0
	return [bg & 0xff, fg & 0xff, int(_brick_damage.get(cell, 0)) & 0xff]

## A client builds the host's map from net_map()'s [param map].
func net_load_map(map: Array) -> void:
	_clear_tiles()
	_clear_fire()
	_clear_mines()
	_brick_damage.clear()
	_hard_brick_hp.clear()
	if map.size() < 5:
		return
	if _bg_color_rect and map[0] is Color:
		_bg_color_rect.color = map[0]
	_bg_bitmap = str(map[1])
	_load_background_image(_bg_bitmap)
	var bg: PackedByteArray = map[2]
	var fg: PackedByteArray = map[3]
	var masks: PackedByteArray = map[4]
	var count := GRID_WIDTH * GRID_HEIGHT
	if bg.size() != count or fg.size() != count or masks.size() != count:
		return
	for i in count:
		var cell := Vector2i(i % GRID_WIDTH, i / GRID_WIDTH)
		if bg[i] != 0:
			_place_bg_tile(cell, bg[i])
		if fg[i] != 0:
			_place_fg_tile(cell, fg[i])
			_net_set_mask(cell, masks[i])

## A client sets one cell as the host has it now (see net_cell).
func net_set_cell(cell: Vector2i, bg: int, fg: int, mask: int) -> void:
	if not _is_in_bounds(cell):
		return
	var now: Array = net_cell(cell)
	if now[0] != bg:
		_remove_bg_tile(cell)
		if bg != 0:
			_place_bg_tile(cell, bg)
	if now[1] != fg:
		_remove_fg_tile(cell)
		_brick_damage.erase(cell)
		_hard_brick_hp.erase(cell)
		if fg != 0:
			_place_fg_tile(cell, fg)
	_net_set_mask(cell, mask)

## A brick with only some quarters standing: those, as the host's.
func _net_set_mask(cell: Vector2i, mask: int) -> void:
	if mask == 0 or not _brick_damage.has(cell) or _brick_damage[cell] == mask:
		return
	_brick_damage[cell] = mask
	_update_brick_visual(cell, mask)

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
	NetHostWorld.mark_tile(tile_pos)

func _remove_bg_tile(tile_pos: Vector2i) -> void:
	if not _bg_tile_data.has(tile_pos):
		return
	var data: Dictionary = _bg_tile_data[tile_pos]
	if data.has("sprite") and is_instance_valid(data["sprite"]):
		data["sprite"].queue_free()
	if data.has("body") and is_instance_valid(data["body"]):
		data["body"].queue_free()
	_bg_tile_data.erase(tile_pos)
	NetHostWorld.mark_tile(tile_pos)

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
	NetHostWorld.mark_tile(tile_pos)

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
	NetHostWorld.mark_tile(tile_pos)
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
# Ground Fire (fire weapon): Tank.exe's, rule for rule
# (docs/fire_weapon_original_spec.md; the tiles are GroundFire)
# =====================================================================

## Safety: the most burning tiles at once (the original had no limit; fuel is
## what stops a fire).
const FIRE_CAP: int = 2000
## A tank burned is burned again no sooner than this, s: 750 ticks after a
## side's fire (a player's or the enemies'), 1500 after burning grass, which is
## nobody's (the original's tank collision, 0x00491d34).
const FIRE_WINDOW := 0.5625
const GRASS_FIRE_WINDOW := 1.125
## How far round a tank's centre fire burns it, px: its picture less 6 px a
## side; while it blinks, its picture and 12 px more a side (the original's
## collision boxes, 0x00492272 and 0x0049305c).
const FIRE_REACH := 26.0
const BLINKING_FIRE_REACH := 44.0
## Up, right, down, left (the original's table 0x004d2970).
const FIRE_DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Each side's fires, as the original kept them (its grids, 0x00490a3c):
## [the enemies', the players'], tile -> the fire there. Only a shell's patch
## goes in: a shell landing on its own side's fire feeds it; the other side's
## burns beside it.
var _fire_grid: Array[Dictionary] = [{}, {}]
## Every fire on a tile, in the order they were lit: tile -> [GroundFire].
var _fires_at: Dictionary = {}
var _fire_count := 0
var _fire_serial := 0


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


## A player's bomb (Sean, 2026-09-27): every enemy mine on the field goes off,
## those still being laid too, each with its own blast, which breaks walls as
## usual but spares the players: their tanks, shells and mines. The players'
## own mines stay (Sean, 2026-10-08).
func set_off_enemy_mines() -> void:
	for mine in get_mines():
		if not mine.from_player:
			mine.set_off(true)


## ENEMY MINES switched off mid-stage (the pause menu): the enemies' mines
## already laid go with it, quietly. The players' stay.
func _on_enemy_mines_changed() -> void:
	if net_mirror or InputSettings.get_enemy_mines():
		return
	for mine in get_mines():
		if not mine.from_player:
			unregister_mine(mine)
			mine.queue_free()


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


## The tanks on burning ground (the original's tank collision with a fire,
## 0x00491cf0), each off its fire window and not materializing, dying or
## thrown: burned by the first armed fire under it that isn't its side's (a
## player's fire burns enemies, the enemies' fire players, burning grass
## everyone).
func _burn_tanks() -> void:
	if _fires_at.is_empty():
		return
	for node in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies"):
		var tank := node as BaseTank
		if tank == null or not is_instance_valid(tank) or tank.is_queued_for_deletion() or tank.health <= 0:
			continue
		if tank.is_materializing or tank.is_flying or tank.fire_immunity_timer > 0.0:
			continue
		var fire := _fire_under(tank)
		if fire:
			tank.burn(fire.is_grass_fire, fire.owner_id)


## The first armed fire under [param tank] (strictly overlapping its box) that
## burns its side, or null.
func _fire_under(tank: BaseTank) -> GroundFire:
	var reach := BLINKING_FIRE_REACH if tank.is_invulnerable() else FIRE_REACH
	var at := tank.global_position - global_position
	var tank_side := 1 if tank.is_in_group("players") else 0
	var first: GroundFire = null
	for tx in range(floori((at.x - reach) / TILE_SIZE), floori((at.x + reach) / TILE_SIZE) + 1):
		if tx * TILE_SIZE >= at.x + reach or (tx + 1) * TILE_SIZE <= at.x - reach:
			continue
		for ty in range(floori((at.y - reach) / TILE_SIZE), floori((at.y + reach) / TILE_SIZE) + 1):
			if ty * TILE_SIZE >= at.y + reach or (ty + 1) * TILE_SIZE <= at.y - reach:
				continue
			for f in _fires_at.get(Vector2i(tx, ty), []):
				var fire := f as GroundFire
				if fire == null or not fire.is_armed() or same_side(tank_side, fire.side):
					continue
				if first == null or fire.serial < first.serial:
					first = fire
	return first


## The original's SameSide (0x004690d0): both players', or both the enemies'.
## Burning grass is nobody's side.
static func same_side(a: int, b: int) -> bool:
	return (a > 0 and b > 0) or (a == 0 and b == 0)


## Fresh fuel for a fire of [param strength], ticks: 1750-2249, 1500 more a
## level (the original's 0x00493c48).
static func fresh_fire_fuel(strength: int) -> int:
	return randi_range(0, 499) + 1750 + 1500 * strength


## The cell a fire shell's patch is laid round, dropping at [param at] (world
## px): the one under its top-left corner, as the original truncated it
## (0x00493b5a), so the patch's middle is the tile corner nearest the shell.
func fire_anchor(at: Vector2) -> Vector2i:
	return world_to_tile(at - Vector2(16, 16))


## A fire shell of [param strength] (its gun level) drops: the original's
## patch (0x00493b44), 12 tiles round [param anchor] (a 4x4 less its corners,
## from one up-left of it), a fire of the shell's side on each that fire can
## lie on; the inner 2x2 arms first. Where its side burns already, the shell
## feeds that fire instead (GroundFire.restack).
func ignite_fire_patch(anchor: Vector2i, from_player: bool, owner_id: int = -1, strength: int = 0) -> void:
	var side := 1 if from_player else 0
	for dy in range(-1, 3):
		for dx in range(-1, 3):
			if dx + dy < -1 or dx + dy > 3 or dy - dx < -2 or dy - dx > 2:
				continue  # the 4 corners
			var cell := anchor + Vector2i(dx, dy)
			if not fire_can_lie(cell):
				continue
			var there := _registered_fire(side, cell)
			if there:
				there.restack(strength, owner_id)
				continue
			var inner := dx >= 0 and dx <= 1 and dy >= 0 and dy <= 1
			var fire := _new_fire(cell, side, owner_id, strength, float(fresh_fire_fuel(strength)),
					GroundFire.ARM_INNER if inner else GroundFire.ARM, dx + dy + 2)
			if fire:
				fire.registered = true
				_fire_grid[side][cell] = fire


## Ground a fire shell's patch can lie on (0x00493bb8): open ground, grass,
## burned grass, water and ice, and half a brick; not a whole brick, a quarter
## of one, a hard brick, iron or super steel.
func fire_can_lie(cell: Vector2i) -> bool:
	var wall := _fire_wall(cell)
	return _is_in_bounds(cell) and (wall == 0 or wall == 2)


## Where a big fire can spread to (0x004977ba): as fire_can_lie, a quarter
## brick too, but not water.
func _fire_can_spread_to(cell: Vector2i) -> bool:
	return _is_in_bounds(cell) and _fire_wall(cell) < 4 and not _is_water_tile(cell)


## The wall on [param cell] as fire sees it: 0 none (open ground, grass), else
## a brick's quarters standing, 4 for a whole one and anything harder.
func _fire_wall(cell: Vector2i) -> int:
	if not _fg_tile_data.has(cell):
		return 0
	var code: int = _fg_tile_data[cell].get("code", 0)
	match LevelData.get_tile_category(code):
		LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
			if code == 0xA1 or code == 0xAB or code == 0xAC:
				return 4  # a brick hiding an item
			var mask := int(_brick_damage.get(cell, 0b1111))
			var quarters := (mask & 1) + (mask >> 1 & 1) + (mask >> 2 & 1) + (mask >> 3 & 1)
			return 4 if quarters >= 3 else quarters
		LevelData.TileCategory.HARD_BRICK, LevelData.TileCategory.IRON_BLOCK, LevelData.TileCategory.SUPER_BLOCK:
			return 4
	return 0


## [param side]'s fire registered on [param cell], or null.
func _registered_fire(side: int, cell: Vector2i) -> GroundFire:
	var fire = _fire_grid[side].get(cell)
	if fire == null or not is_instance_valid(fire) or fire.is_queued_for_deletion():
		return null
	return fire


## A new fire on [param cell] (deferred: shells drop inside the physics'
## callbacks); null past FIRE_CAP.
func _new_fire(cell: Vector2i, side: int, owner_id: int, strength: int, fuel: float, arm: float, frame: int,
		shown: bool = false) -> GroundFire:
	if _fire_count >= FIRE_CAP:
		return null
	var fire: GroundFire = _ground_fire_scene.new()
	fire.setup(self, cell, side, owner_id, strength, fuel, arm, frame, shown)
	_fire_serial += 1
	fire.serial = _fire_serial
	fire.position = Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2, cell.y * TILE_SIZE + TILE_SIZE / 2)
	_add_deferred(terrain_node, fire)
	if not _fires_at.has(cell):
		_fires_at[cell] = []
	_fires_at[cell].append(fire)
	_fire_count += 1
	return fire


## A big fire spreads (0x0049775e): to each side of it fire can spread to, it
## gives a quarter of what it had above the fire of its side there, a new one
## if none is registered there (which never is, so it may be given another).
## So a stack levels out over its patch and pushes a ring of fire out of it.
func spread_fire(fire: GroundFire) -> void:
	var had := fire.fuel
	for d in FIRE_DIRS:
		var cell := fire.tile_pos + d
		if not _fire_can_spread_to(cell):
			continue
		var there := _registered_fire(fire.side, cell)
		if there == null:
			there = _new_fire(cell, fire.side, fire.owner_id, fire.strength, 0.0, GroundFire.ARM,
					cell.x + cell.y + fire.anim_frame())
			if there == null:
				continue
		var more := had - there.fuel
		if more > 0.0:
			there.strength = fire.strength
			there.owner_id = fire.owner_id
			var give := floorf(more / 4.0)
			there.fuel += give
			fire.fuel -= give


## A fire's terrain step, once (0x00497925): green grass beside it (not under
## it) burns to grey, with a fire of nobody's on it, which burns everyone and
## goes on along the grass the same way; and a side's fire melts the ice under
## itself to bare ground.
func fire_terrain_step(fire: GroundFire) -> void:
	for d in FIRE_DIRS:
		var cell := fire.tile_pos + d
		if _is_green_grass(cell):
			_convert_grass_to_burned(cell)
			_new_fire(cell, -1, -1, 0, float(randi_range(0, 499) + 3750), GroundFire.ARM, cell.x + cell.y, true)
	if fire.side >= 0 and _is_ice(fire.tile_pos):
		_remove_bg_tile(fire.tile_pos)


## A fire has burned out: off its tile, and off its side's grid while it's the
## one there.
func fire_out(fire: GroundFire) -> void:
	if fire.registered and _fire_grid[fire.side].get(fire.tile_pos) == fire:
		_fire_grid[fire.side].erase(fire.tile_pos)
	var list: Array = _fires_at.get(fire.tile_pos, [])
	list.erase(fire)
	if list.is_empty():
		_fires_at.erase(fire.tile_pos)
	_fire_count -= 1


## The fires on [param cell], in the order they were lit.
func fires_at(cell: Vector2i) -> Array:
	return _fires_at.get(cell, [])


func _is_ice(tile: Vector2i) -> bool:
	return _bg_tile_data.has(tile) and LevelData.get_tile_category(
			_bg_tile_data[tile].get("code", 0)) == LevelData.TileCategory.ICE


func _is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < GRID_WIDTH and tile.y >= 0 and tile.y < GRID_HEIGHT


func _clear_fire() -> void:
	for list in _fires_at.values():
		for f in list:
			if is_instance_valid(f):
				f.queue_free()
	_fires_at.clear()
	for grid in _fire_grid:
		grid.clear()
	_fire_count = 0


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
	NetHostWorld.mark_tile(tile)
	if data.has("sprite") and is_instance_valid(data["sprite"]):
		# Burned variant keeps the same index as the green tile it replaces.
		var btex := _grass_texture(new_code)
		if btex:
			data["sprite"].texture = btex


# =====================================================================
# Explosion Weapon — shockwave blast
# =====================================================================

## A blast goes off for something of [param size] (the original's px:
## ExplosionBlast.SHELL_SIZE, MINE_SIZE, TANK_SIZE) centred at
## [param world_pos], of level [param level], a player's or the enemies'
## ([param from_player]), or neither ([param neutral]: a landing), player
## [param owner_id]'s; [param spare_players] for a mine a player's bomb set
## off. Its clients draw it from where its 8x8 goes (NetWorld.EV_BLAST).
## Deferred add_child: shells go off inside the physics' callbacks.
func spawn_explosion_blast(world_pos: Vector2, level: int, from_player: bool, neutral: bool = false, owner_id: int = -1,
		spare_players: bool = false, size: float = ExplosionBlast.SHELL_SIZE) -> void:
	var blast := ExplosionBlast.new()
	blast.setup(level, from_player, self, neutral, owner_id, spare_players)
	blast.origin = ExplosionBlast.grid_origin(world_pos - global_position, size)
	NetHostWorld.record(NetWorld.EV_BLAST, [blast.origin.x, blast.origin.y, blast.level])
	var container: Node = get_tree().get_first_node_in_group("effects_container")
	if container == null:
		container = terrain_node
	_add_deferred(container, blast)


## The quarters of [param cell] that stop a blast (ExplosionBlast): a brick's
## standing ones, all of a hard brick's or of iron or super steel; none of
## grass or anything else. As the original's mask (0x00496859), a brick's left
## and right halves count the wrong way round: a left half stops the right
## quarters, and the other way. Quarters as a brick's: TL 8, TR 4, BL 2, BR 1.
func blast_shadow_quarters(cell: Vector2i) -> int:
	if not _fg_tile_data.has(cell):
		return 0
	match LevelData.get_tile_category(_fg_tile_data[cell].get("code", 0)):
		LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
			var standing := int(_brick_damage.get(cell, 0b1111))
			if standing == 0b1010:
				return 0b0101
			if standing == 0b0101:
				return 0b1010
			return standing
		LevelData.TileCategory.HARD_BRICK, LevelData.TileCategory.IRON_BLOCK, LevelData.TileCategory.SUPER_BLOCK:
			return 0b1111
	return 0


## A blast reaches [param cell] hot enough to change its wall (the original's
## terrain pass, 0x00497000): burned grass goes; a whole brick keeps the half
## [param half] (TL 8, TR 4, BL 2, BR 1); what's left of a brick goes; a hard
## brick loses a point; nothing else changes, iron included (only an explosion
## shell's own hit breaks it: Bullet.breaks_iron).
func blast_wall(cell: Vector2i, half: int) -> void:
	if not _fg_tile_data.has(cell):
		return
	match LevelData.get_tile_category(_fg_tile_data[cell].get("code", 0)):
		LevelData.TileCategory.BURNED_GRASS:
			_remove_fg_tile(cell)
		LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
			if int(_brick_damage.get(cell, 0b1111)) == 0b1111:
				_brick_damage[cell] = half
				_update_brick_visual(cell, half)
			else:
				_remove_fg_tile(cell)
				_brick_damage.erase(cell)
		LevelData.TileCategory.HARD_BRICK:
			_damage_hard_brick(cell)
