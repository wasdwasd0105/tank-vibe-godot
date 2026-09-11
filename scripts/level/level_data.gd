class_name LevelData
extends RefCounted

# Grid dimensions: 40 columns x 30 rows
const GRID_WIDTH: int = 40
const GRID_HEIGHT: int = 30

# Eagle occupies 2x2 tiles at bottom center: columns 19-20, rows 28-29
const EAGLE_COL: int = 19
const EAGLE_ROW: int = 28

# Default enemy wave fallback (legacy: [basic, fast, power, armor])
const DEFAULT_ENEMY_WAVE: Array = [18, 2, 0, 0]
# Default spawn queue fallback (20 type-1 enemies)
const DEFAULT_SPAWN_QUEUE: Array = [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1]

# Path to map files directory
const MAP_DIR: String = "res://maps/"
## Imported map files (see import_map_file) live here and count as extra pools.
const USER_MAP_DIR: String = "user://maps/"
const USER_POOL_PREFIX: String = "user:"
const IMPORTED_SUFFIX: String = " (imported)"

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
	var bg_bitmap: String = ""  # background image filename (e.g. "BG02.jpg")
	var bg_grid: Array = []   # 30 rows of 40 ints (hex codes)
	var fg_grid: Array = []   # 30 rows of 40 ints (hex codes)
	var enemy_count: Array = []  # parsed from EnemyCount line
	var max_count: int = 4

# --- Map Pool ---
class MapPool:
	var id: String = ""            # unique identifier (filename or folder name)
	var display_name: String = ""  # user-facing name
	var type: String = ""          # "dat" or "folder"
	var path: String = ""          # full res:// path to .dat file or folder

# --- Cached stages & pools ---
static var _loaded_stages: Array = []
static var _available_pools: Array = []  # Array of MapPool
static var _current_pool_id: String = ""

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
# Stage.dat Binary Parser
# =====================================================================

## Binary format constants
const DAT_STAGE_SIZE: int = 6000
const DAT_BG_OFFSET: int = 1200
const DAT_FG_OFFSET: int = 3600
const DAT_COL_STRIDE: int = 60  # 30 rows * 2 bytes per cell
const DAT_BGBITMAP_OFFSET: int = 64
const DAT_ENEMY_OFFSET: int = 144
const DAT_MAXCOUNT_OFFSET: int = 208

## Load all stages from a Stage.dat binary file
static func load_stages_from_dat(path: String) -> Array:
	var stages: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("LevelData: Failed to open dat file: " + path)
		return stages

	var all_data := file.get_buffer(file.get_length())
	file.close()

	var stage_count := all_data.size() / DAT_STAGE_SIZE
	# Skip stage 0 (Splash Stage / title screen)
	for stage_idx in range(1, stage_count):
		var base := stage_idx * DAT_STAGE_SIZE
		var sd := StageData.new()

		# Parse stage name (length-prefixed string at offset 0)
		# 0xFF is used as separator between caption and subtitle, e.g. "Name\xFF(Easy)"
		var name_len: int = all_data[base]
		if name_len > 0 and name_len < 64:
			# Find 0xFF separator and only take the part before it
			var actual_len := name_len
			for i in range(name_len):
				if all_data[base + 1 + i] == 0xFF:
					actual_len = i
					break
			var name_bytes := all_data.slice(base + 1, base + 1 + actual_len)
			sd.caption = name_bytes.get_string_from_ascii()

		# Parse BG_Bitmap (length-prefixed string at offset 64)
		var bg_len: int = all_data[base + DAT_BGBITMAP_OFFSET]
		if bg_len > 0 and bg_len < 64:
			var bg_bytes := all_data.slice(base + DAT_BGBITMAP_OFFSET + 1, base + DAT_BGBITMAP_OFFSET + 1 + bg_len)
			sd.bg_bitmap = bg_bytes.get_string_from_ascii()

		# Parse enemy count (24 x LE16 at offset 144, we use first 4)
		for i in range(24):
			var off := base + DAT_ENEMY_OFFSET + i * 2
			var val: int = all_data[off] | (all_data[off + 1] << 8)
			sd.enemy_count.append(val)

		# Parse max concurrent enemies (LE16 at offset 208)
		var mc_off := base + DAT_MAXCOUNT_OFFSET
		sd.max_count = all_data[mc_off] | (all_data[mc_off + 1] << 8)
		if sd.max_count <= 0:
			sd.max_count = 4

		# Parse BG and FG grids (column-major, 2 bytes per cell)
		for row in range(GRID_HEIGHT):
			var bg_row: Array = []
			var fg_row: Array = []
			for col in range(GRID_WIDTH):
				# BG tile (binary values are game codes - 1, same as FG)
				var bg_off := base + DAT_BG_OFFSET + col * DAT_COL_STRIDE + row * 2
				var bg_val: int = all_data[bg_off]
				if bg_val == 0xFF:
					bg_row.append(0x00)
				else:
					bg_row.append((bg_val + 1) & 0xFF)

				# FG tile (binary values are game codes - 1)
				var fg_off := base + DAT_FG_OFFSET + col * DAT_COL_STRIDE + row * 2
				var fg_val: int = all_data[fg_off]
				if fg_val == 0xFF:
					fg_row.append(0x00)
				else:
					fg_row.append((fg_val + 1) & 0xFF)

			sd.bg_grid.append(bg_row)
			sd.fg_grid.append(fg_row)

		stages.append(sd)

	print("LevelData: Loaded %d stages from %s" % [stages.size(), path])
	return stages

# =====================================================================
# Text Map File Parser
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
			elif line.begins_with("BG_Bitmap="):
				current_stage.bg_bitmap = line.substr(10).strip_edges()
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

# =====================================================================
# Map Pool Scanning & Loading
# =====================================================================

## Scan the bundled maps/ directory and the user's imported maps for pools.
## A .dat file = one pool. A subfolder with .txt files = one pool.
static func scan_map_pools() -> Array:
	_available_pools.clear()
	_scan_pool_dir(MAP_DIR, "", "", true)
	_scan_pool_dir(USER_MAP_DIR, USER_POOL_PREFIX, IMPORTED_SUFFIX, false)
	_available_pools.sort_custom(func(a, b): return a.id.naturalcasecmp_to(b.id) < 0)
	print("LevelData: Found %d map pools" % _available_pools.size())
	return _available_pools

static func _scan_pool_dir(dir_path: String, id_prefix: String, name_suffix: String, required: bool) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		if required:
			push_error("LevelData: Failed to open maps directory: " + dir_path)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			if not entry.begins_with(".") and _folder_has_txt(dir_path + entry):
				var pool := MapPool.new()
				pool.id = id_prefix + entry
				pool.display_name = entry + name_suffix
				pool.type = "folder"
				pool.path = dir_path + entry + "/"
				_available_pools.append(pool)
		elif entry.ends_with(".dat"):
			var pool := MapPool.new()
			pool.id = id_prefix + entry.get_basename()
			pool.display_name = entry.get_basename() + name_suffix
			pool.type = "dat"
			pool.path = dir_path + entry
			_available_pools.append(pool)
		entry = dir.get_next()
	dir.list_dir_end()

static func _folder_has_txt(folder_path: String) -> bool:
	var sub_dir := DirAccess.open(folder_path)
	if not sub_dir:
		return false
	var has_txt := false
	sub_dir.list_dir_begin()
	var sub_entry := sub_dir.get_next()
	while not sub_entry.is_empty():
		if not sub_dir.current_is_dir() and sub_entry.ends_with(".txt"):
			has_txt = true
			break
		sub_entry = sub_dir.get_next()
	sub_dir.list_dir_end()
	return has_txt

## Copies a map file into the user's maps folder so it shows up as a pool.
## Accepts a Tank.exe stage file (.dat, a multiple of 6000 bytes) or one of the
## remake's .txt map files (stored as a one-file folder pool). Returns
## {"ok": true, "pool_id": ..., "name": ..., "stage_count": ...} or {"ok": false, "error": ...}.
static func import_map_file(source_path: String) -> Dictionary:
	var file_name := source_path.get_file()
	var extension := source_path.get_extension().to_lower()
	if extension != "dat" and extension != "txt":
		return {"ok": false, "error": "unsupported file type .%s (expected .dat or .txt)" % extension}
	var source := FileAccess.open(source_path, FileAccess.READ)
	if not source:
		return {"ok": false, "error": "could not read %s" % file_name}
	var size := source.get_length()
	source.close()

	var stages: Array
	if extension == "dat":
		if size == 0 or size % DAT_STAGE_SIZE != 0:
			return {"ok": false, "error": "%s is not a Tank.exe map file (size must be a multiple of %d bytes)" % [file_name, DAT_STAGE_SIZE]}
		stages = load_stages_from_dat(source_path)
	else:
		stages = load_stages_from_file(source_path)
	if stages.is_empty():
		return {"ok": false, "error": "no stages found in %s" % file_name}

	DirAccess.make_dir_recursive_absolute(USER_MAP_DIR)
	var base := _sanitize_pool_name(file_name.get_basename())
	var pool_name: String
	var err: Error
	if extension == "dat":
		pool_name = _unique_pool_name(base, func(n: String) -> bool: return FileAccess.file_exists(USER_MAP_DIR + n + ".dat"))
		err = DirAccess.copy_absolute(source_path, USER_MAP_DIR + pool_name + ".dat")
	else:
		pool_name = _unique_pool_name(base, func(n: String) -> bool: return DirAccess.dir_exists_absolute(USER_MAP_DIR + n))
		err = DirAccess.make_dir_recursive_absolute(USER_MAP_DIR + pool_name)
		if err == OK:
			err = DirAccess.copy_absolute(source_path, USER_MAP_DIR + pool_name + "/" + file_name)
	if err != OK:
		return {"ok": false, "error": "could not copy %s into %s (%s)" % [file_name, USER_MAP_DIR, error_string(err)]}

	scan_map_pools()
	return {"ok": true, "pool_id": USER_POOL_PREFIX + pool_name, "name": pool_name, "stage_count": stages.size()}

## Keep only letters, digits, "_" and "-" so the name is safe as a file name.
static func _sanitize_pool_name(name: String) -> String:
	var clean := RegEx.create_from_string("[^A-Za-z0-9_-]+").sub(name, "_", true).left(40)
	return clean if not clean.is_empty() else "map"

## Append _2, _3, ... until [param taken] reports the name as free.
static func _unique_pool_name(base: String, taken: Callable) -> String:
	var candidate := base
	var suffix := 2
	while taken.call(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate

## Get available pools (lazy-scan on first call)
static func get_available_pools() -> Array:
	if _available_pools.is_empty():
		scan_map_pools()
	return _available_pools

## Load stages from a specific map pool
static func load_pool(pool: MapPool) -> void:
	_loaded_stages.clear()
	_current_pool_id = pool.id
	if pool.type == "dat":
		_loaded_stages = load_stages_from_dat(pool.path)
	elif pool.type == "folder":
		_loaded_stages = _load_folder_pool(pool.path)
	print("LevelData: Pool '%s' loaded with %d stages" % [pool.id, _loaded_stages.size()])

## Load all .txt stages from a folder pool (sorted alphabetically)
static func _load_folder_pool(folder_path: String) -> Array:
	var all_stages: Array = []
	var dir := DirAccess.open(folder_path)
	if not dir:
		push_error("LevelData: Failed to open pool folder: " + folder_path)
		return all_stages

	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".txt"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for f in files:
		var stages := load_stages_from_file(folder_path + f)
		all_stages.append_array(stages)
	return all_stages

## Get all loaded stages (lazy load — auto-loads first pool if none loaded)
static func get_stages() -> Array:
	if _loaded_stages.is_empty():
		var pools := get_available_pools()
		if not pools.is_empty():
			load_pool(pools[0])
	return _loaded_stages

## Get the total number of stages
static func get_stage_count() -> int:
	return get_stages().size()

## Get enemy wave data for a stage (1-indexed) - LEGACY
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

## Get enemy spawn queue for a stage (1-indexed)
## Returns a shuffled array of tank type IDs (1-24) ready to spawn.
## EnemyCount format: index = type (0→type1, 1→type2, ..., 23→type24),
## value = how many of that type to spawn.
static func get_enemy_spawn_queue(stage_num: int) -> Array:
	var stages := get_stages()
	var idx := stage_num - 1
	if idx < 0 or idx >= stages.size():
		return DEFAULT_SPAWN_QUEUE.duplicate()

	var stage: StageData = stages[idx]
	var queue: Array = []
	for i in range(mini(stage.enemy_count.size(), 24)):
		var count: int = stage.enemy_count[i]
		var type_id: int = i + 1  # index 0 = type 1, index 1 = type 2, etc.
		for _j in range(count):
			queue.append(type_id)
	if queue.is_empty():
		return DEFAULT_SPAWN_QUEUE.duplicate()
	queue.shuffle()
	return queue

## Get caption (name) for a stage (1-indexed)
static func get_stage_caption(stage_num: int) -> String:
	var stages := get_stages()
	var idx := stage_num - 1
	if idx < 0 or idx >= stages.size():
		return ""
	var stage: StageData = stages[idx]
	return stage.caption

## Get background bitmap filename for a stage (1-indexed)
static func get_stage_bg_bitmap(stage_num: int) -> String:
	var stages := get_stages()
	var idx := stage_num - 1
	if idx < 0 or idx >= stages.size():
		return ""
	var stage: StageData = stages[idx]
	return stage.bg_bitmap

## Get max concurrent enemies for a stage
static func get_max_concurrent(stage_num: int) -> int:
	var stages := get_stages()
	var idx := stage_num - 1
	if idx < 0 or idx >= stages.size():
		return 4
	var stage: StageData = stages[idx]
	return stage.max_count
