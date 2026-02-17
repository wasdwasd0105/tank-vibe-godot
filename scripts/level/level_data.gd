class_name LevelData
extends RefCounted

# Grid dimensions: 40 columns x 30 rows
const GRID_WIDTH: int = 40
const GRID_HEIGHT: int = 30

# Eagle occupies 2x2 tiles at bottom center: columns 19-20, rows 28-29
const EAGLE_COL: int = 19
const EAGLE_ROW: int = 28

# Which enemies (0-indexed) carry power-ups
const POWERUP_CARRIERS: Array[int] = [3, 10, 17]

# Default enemy wave fallback
const DEFAULT_ENEMY_WAVE: Array = [18, 2, 0, 0]

# Path to map files directory
const MAP_DIR: String = "res://maps/"

# --- Tile Category Classification ---
enum TileCategory {
	EMPTY,
	ICE,
	WATER,
	GRASS,
	BURNED_GRASS,
	SOFT_BRICK_FULL,
	SOFT_BRICK_PARTIAL,
	HARD_BRICK,
	IRON_BLOCK,
	SUPER_BLOCK,
}

# --- Parsed Stage Data ---
class StageData:
	var caption: String = ""
	var bg_grid: Array = []   # 30 rows of 40 ints (hex codes)
	var fg_grid: Array = []   # 30 rows of 40 ints (hex codes)
	var enemy_count: Array = []  # parsed from EnemyCount line
	var max_count: int = 4

# --- Cached stages ---
static var _loaded_stages: Array = []

# =====================================================================
# Tile Classification Functions
# =====================================================================

## Classify a hex tile code (0x00-0xFF) into its TileCategory
static func get_tile_category(code: int) -> TileCategory:
	if code == 0x00:
		return TileCategory.EMPTY
	elif code >= 0x01 and code <= 0x04:
		return TileCategory.ICE
	elif code >= 0x05 and code <= 0x08:
		return TileCategory.WATER
	elif code >= 0x09 and code <= 0x0C:
		return TileCategory.GRASS
	elif code >= 0x0D and code <= 0x10:
		return TileCategory.BURNED_GRASS
	elif code >= 0x19 and code <= 0x1C:
		return TileCategory.SOFT_BRICK_FULL
	elif code >= 0x1D and code <= 0x28:
		return TileCategory.SOFT_BRICK_PARTIAL
	elif code >= 0x29 and code <= 0x38:
		return TileCategory.HARD_BRICK
	elif code >= 0x39 and code <= 0x3C:
		return TileCategory.IRON_BLOCK
	elif code >= 0x3D and code <= 0x40:
		return TileCategory.SUPER_BLOCK
	# Codes A1, AB, AC are also soft brick full variants
	elif code == 0xA1 or code == 0xAB or code == 0xAC:
		return TileCategory.SOFT_BRICK_FULL
	return TileCategory.EMPTY

## Is this tile code a background-layer tile?
static func is_bg_tile(code: int) -> bool:
	var cat := get_tile_category(code)
	return cat == TileCategory.ICE or cat == TileCategory.WATER

## Is this tile code a foreground-layer tile?
static func is_fg_tile(code: int) -> bool:
	var cat := get_tile_category(code)
	return cat != TileCategory.EMPTY and not is_bg_tile(code)

## Does this tile category block bullets (solid wall)?
static func is_solid_tile(cat: TileCategory) -> bool:
	return cat == TileCategory.SOFT_BRICK_FULL \
		or cat == TileCategory.SOFT_BRICK_PARTIAL \
		or cat == TileCategory.HARD_BRICK \
		or cat == TileCategory.IRON_BLOCK \
		or cat == TileCategory.SUPER_BLOCK

## Get hard brick HP from its code (4, 3, 2, or 1)
static func get_hard_brick_hp(code: int) -> int:
	if code >= 0x29 and code <= 0x2C:
		return 4
	elif code >= 0x2D and code <= 0x30:
		return 3
	elif code >= 0x31 and code <= 0x34:
		return 2
	elif code >= 0x35 and code <= 0x38:
		return 1
	return 0

## Get initial sub-tile damage bitmask for soft brick codes
## Bitmask: TL=8, TR=4, BL=2, BR=1
static func get_soft_brick_damage_mask(code: int) -> int:
	# Full bricks
	if code >= 0x19 and code <= 0x1C:
		return 0b1111
	if code == 0xA1 or code == 0xAB or code == 0xAC:
		return 0b1111
	# Partial damage states
	match code:
		0x1D, 0x1E:  # TL+TR remaining
			return 0b1100
		0x1F, 0x20:  # TR+BR remaining
			return 0b0101
		0x21, 0x22:  # BL+BR remaining
			return 0b0011
		0x23, 0x24:  # TL+BL remaining
			return 0b1010
		0x25:         # TL only
			return 0b1000
		0x26:         # TR only
			return 0b0100
		0x27:         # BR only
			return 0b0001
		0x28:         # BL only
			return 0b0010
	return 0b1111

## Get color variant index (0-3) from a tile code
static func get_variant_index(code: int) -> int:
	# Special soft brick codes
	if code == 0xA1:
		return 1
	if code == 0xAB:
		return 2
	if code == 0xAC:
		return 3

	var cat := get_tile_category(code)
	match cat:
		TileCategory.ICE:
			return code - 0x01
		TileCategory.WATER:
			return code - 0x05
		TileCategory.GRASS:
			return code - 0x09
		TileCategory.BURNED_GRASS:
			return code - 0x0D
		TileCategory.SOFT_BRICK_FULL:
			return code - 0x19
		TileCategory.SOFT_BRICK_PARTIAL:
			# Paired variants: even offset = variant 0, odd = variant 1
			if code >= 0x1D and code <= 0x24:
				return (code - 0x1D) % 2
			return 0  # single-variant codes 0x25-0x28
		TileCategory.HARD_BRICK:
			if code >= 0x29 and code <= 0x2C:
				return code - 0x29
			elif code >= 0x2D and code <= 0x30:
				return code - 0x2D
			elif code >= 0x31 and code <= 0x34:
				return code - 0x31
			elif code >= 0x35 and code <= 0x38:
				return code - 0x35
		TileCategory.IRON_BLOCK:
			return code - 0x39
		TileCategory.SUPER_BLOCK:
			return code - 0x3D
	return 0

## Get the hard brick code for a given HP level and variant index
static func get_hard_brick_code(hp: int, variant: int) -> int:
	variant = clampi(variant, 0, 3)
	match hp:
		4: return 0x29 + variant
		3: return 0x2D + variant
		2: return 0x31 + variant
		1: return 0x35 + variant
	return 0x29 + variant

# =====================================================================
# Map File Parser
# =====================================================================

## Load all stages from a .txt map file
static func load_stages_from_file(path: String) -> Array:
	var stages: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("LevelData: Failed to open map file: " + path)
		return stages

	var current_stage: StageData = null

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("[Stage"):
			current_stage = StageData.new()
			# Initialize grids with empty rows
			for i in range(GRID_HEIGHT):
				current_stage.bg_grid.append([])
				current_stage.fg_grid.append([])
		elif line == "[End]":
			if current_stage:
				stages.append(current_stage)
			current_stage = null
		elif current_stage:
			if line.begins_with("Caption="):
				current_stage.caption = line.substr(8)
			elif line.begins_with("EnemyCount="):
				var parts := line.substr(11).split(",")
				for p in parts:
					var val := p.strip_edges()
					if not val.is_empty():
						current_stage.enemy_count.append(val.to_int())
			elif line.begins_with("MaxCount="):
				current_stage.max_count = line.substr(9).strip_edges().to_int()
			elif line.begins_with("BG") and "=" in line:
				var eq_pos := line.find("=")
				var row_str := line.substr(2, eq_pos - 2)
				var row_idx := row_str.to_int()
				if row_idx >= 0 and row_idx < GRID_HEIGHT:
					var hex_values := line.substr(eq_pos + 1).strip_edges().split(" ")
					for hex_str in hex_values:
						var trimmed := hex_str.strip_edges()
						if not trimmed.is_empty():
							current_stage.bg_grid[row_idx].append(trimmed.hex_to_int())
			elif line.begins_with("FG") and "=" in line:
				var eq_pos := line.find("=")
				var row_str := line.substr(2, eq_pos - 2)
				var row_idx := row_str.to_int()
				if row_idx >= 0 and row_idx < GRID_HEIGHT:
					var hex_values := line.substr(eq_pos + 1).strip_edges().split(" ")
					for hex_str in hex_values:
						var trimmed := hex_str.strip_edges()
						if not trimmed.is_empty():
							current_stage.fg_grid[row_idx].append(trimmed.hex_to_int())
			# Skip other metadata lines (BG_Bitmap, BG_Color, etc.)

	file.close()
	return stages

## Load all map files from the maps directory
static func _load_all_maps() -> Array:
	var all_stages: Array = []
	var dir := DirAccess.open(MAP_DIR)
	if not dir:
		push_error("LevelData: Failed to open maps directory: " + MAP_DIR)
		return all_stages

	# Collect all .txt files
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".txt"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()

	# Parse each file
	for f in files:
		var stages := load_stages_from_file(MAP_DIR + f)
		all_stages.append_array(stages)

	return all_stages

## Get all loaded stages (lazy load on first call)
static func get_stages() -> Array:
	if _loaded_stages.is_empty():
		_loaded_stages = _load_all_maps()
	return _loaded_stages

## Get the total number of stages
static func get_stage_count() -> int:
	return get_stages().size()

## Get enemy wave data for a stage (1-indexed)
## Returns [basic, fast, power, armor]
static func get_enemy_wave(stage_num: int) -> Array:
	var stages := get_stages()
	var idx := stage_num - 1
	if idx < 0 or idx >= stages.size():
		return DEFAULT_ENEMY_WAVE.duplicate()

	var stage: StageData = stages[idx]
	if stage.enemy_count.size() >= 4:
		return [stage.enemy_count[0], stage.enemy_count[1],
				stage.enemy_count[2], stage.enemy_count[3]]
	return DEFAULT_ENEMY_WAVE.duplicate()

## Get max concurrent enemies for a stage
static func get_max_concurrent(stage_num: int) -> int:
	var stages := get_stages()
	var idx := stage_num - 1
	if idx < 0 or idx >= stages.size():
		return 4
	var stage: StageData = stages[idx]
	return stage.max_count
