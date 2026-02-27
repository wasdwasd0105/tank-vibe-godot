extends Node

## ThemeManager — autoload singleton providing all visual textures.
## Supports "procedural" themes (generated at runtime) and "image" themes (loaded from files).

signal theme_changed(theme_name: String)

const THEMES_DIR: String = "res://themes/"
const DEFAULT_TANK_SPRITE: String = "res://assets/sprites/tanks/tank.png"
const TANK_SPRITES_DIR: String = "res://assets/tank_sprites/"
const TILE_SIZE: int = 32

var current_theme: String = "default"
var _theme_type: String = "procedural"   # "procedural" or "image"
var _tile_scale: int = 1
var _tank_mode: String = "modulate"      # "modulate" or "sprite"
var _config: ConfigFile = null

# Cached textures
var _tile_textures: Dictionary = {}           # code (int) -> Texture2D
var _partial_brick_cache: Dictionary = {}     # mask (int) or "mask_variant" (String) -> Texture2D
var _tank_textures: Dictionary = {}           # "p1","p2","e1"-"e24" -> Texture2D
var _addon_textures: Dictionary = {}         # "moon-shield","anti-water",etc -> Texture2D

# =====================================================================
# Procedural color palettes (moved from level_manager.gd)
# =====================================================================

const SOFT_BRICK_COLORS: Array = [
	Color(0.7, 0.13, 0.13),
	Color(0.65, 0.18, 0.10),
	Color(0.72, 0.10, 0.15),
	Color(0.68, 0.15, 0.12),
]

const HARD_BRICK_COLORS: Array = [
	Color(0.55, 0.40, 0.35),
	Color(0.50, 0.38, 0.30),
	Color(0.58, 0.42, 0.32),
	Color(0.52, 0.36, 0.33),
]

const IRON_COLORS: Array = [
	Color(0.75, 0.75, 0.75),
	Color(0.70, 0.72, 0.74),
	Color(0.78, 0.76, 0.74),
	Color(0.72, 0.74, 0.76),
]

const SUPER_BLOCK_COLORS: Array = [
	Color(0.80, 0.70, 0.30),
	Color(0.75, 0.65, 0.25),
	Color(0.85, 0.72, 0.28),
	Color(0.78, 0.68, 0.32),
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

# =====================================================================
# Lifecycle
# =====================================================================

func _ready() -> void:
	load_theme(current_theme)

# =====================================================================
# Public API
# =====================================================================

## List all valid theme folder names
func get_available_themes() -> Array[String]:
	var themes: Array[String] = []
	var dir := DirAccess.open(THEMES_DIR)
	if not dir:
		themes.append("default")
		return themes
	dir.list_dir_begin()
	var folder := dir.get_next()
	while not folder.is_empty():
		if dir.current_is_dir() and not folder.begins_with("."):
			if FileAccess.file_exists(THEMES_DIR + folder + "/theme.cfg"):
				themes.append(folder)
		folder = dir.get_next()
	dir.list_dir_end()
	themes.sort()
	# Ensure "default" is first
	if themes.has("default"):
		themes.erase("default")
		themes.push_front("default")
	elif themes.is_empty():
		themes.append("default")
	return themes

## Load and activate a theme by folder name
func load_theme(theme_name: String) -> void:
	var cfg_path := THEMES_DIR + theme_name + "/theme.cfg"
	_config = ConfigFile.new()
	if _config.load(cfg_path) != OK:
		push_warning("ThemeManager: Could not load %s, falling back to procedural" % cfg_path)
		_theme_type = "procedural"
		_tank_mode = "modulate"
	else:
		_theme_type = _config.get_value("theme", "type", "procedural")
		_tile_scale = _config.get_value("theme", "tile_scale", 1)
		_tank_mode = _config.get_value("tanks", "mode", "modulate")

	current_theme = theme_name
	_tile_textures.clear()
	_partial_brick_cache.clear()
	_tank_textures.clear()
	_addon_textures.clear()

	if _theme_type == "procedural":
		_generate_procedural_textures()
	else:
		_load_image_textures()

	_load_tank_textures()
	_load_addon_textures()
	theme_changed.emit(theme_name)

## Full code→Texture2D dictionary (for level_manager)
func get_all_tile_textures() -> Dictionary:
	return _tile_textures

## Single tile texture lookup
func get_tile_texture(code: int) -> Texture2D:
	return _tile_textures.get(code, null)

## Partial (damaged) brick texture
func get_partial_brick_texture(damage_mask: int, variant: int) -> Texture2D:
	if _theme_type == "image":
		# Image themes: only damage mask matters (no color variants)
		if _partial_brick_cache.has(damage_mask):
			return _partial_brick_cache[damage_mask]
		# Fallback: if this exact mask isn't provided, return full brick
		return _partial_brick_cache.get(0b1111, null)
	else:
		# Procedural: cache by mask + variant
		var cache_key := "%d_%d" % [damage_mask, variant]
		if not _partial_brick_cache.has(cache_key):
			var brick_color: Color = SOFT_BRICK_COLORS[clampi(variant, 0, 3)]
			_partial_brick_cache[cache_key] = _create_partial_brick_texture(damage_mask, brick_color)
		return _partial_brick_cache[cache_key]

## Tank sprite texture
func get_tank_texture(tank_key: String) -> Texture2D:
	return _tank_textures.get(tank_key, null)

## Addon sprite texture (e.g. "moon-shield", "anti-water")
func get_addon_texture(addon_name: String) -> Texture2D:
	return _addon_textures.get(addon_name, null)

## Whether tanks should use color modulation (true) or dedicated sprites (false)
func is_tank_modulate_mode() -> bool:
	return _tank_mode == "modulate"

## Get the display name from theme.cfg
func get_theme_display_name() -> String:
	if _config:
		return _config.get_value("theme", "name", current_theme)
	return current_theme

# =====================================================================
# Image-based theme loading
# =====================================================================

func _load_image_textures() -> void:
	var theme_dir := THEMES_DIR + current_theme + "/"

	# Ice: 0x01-0x04
	_set_tile_from_config(theme_dir, [0x01, 0x02, 0x03, 0x04], "ice")
	# Water: 0x05-0x08
	_set_tile_from_config(theme_dir, [0x05, 0x06, 0x07, 0x08], "water")
	# Grass: 0x09-0x0C
	_set_tile_from_config(theme_dir, [0x09, 0x0A, 0x0B, 0x0C], "grass")
	# Burned grass: 0x0D-0x10
	_set_tile_from_config(theme_dir, [0x0D, 0x0E, 0x0F, 0x10], "burned_grass")
	# Soft brick full: 0x19-0x1C, 0xA1, 0xAB, 0xAC
	_set_tile_from_config(theme_dir, [0x19, 0x1A, 0x1B, 0x1C, 0xA1, 0xAB, 0xAC], "soft_brick_full")

	# Hard brick: 4 HP levels
	for hp in [4, 3, 2, 1]:
		var cfg_key := "hard_brick_%d" % hp
		var path: String = _config.get_value("tiles", cfg_key, "")
		if path.is_empty():
			continue
		var tex := _load_and_scale_image(theme_dir + path)
		if tex:
			for v in range(4):
				var code := LevelData.get_hard_brick_code(hp, v)
				_tile_textures[code] = tex

	# Iron: 0x39-0x3C
	_set_tile_from_config(theme_dir, [0x39, 0x3A, 0x3B, 0x3C], "iron_brick")
	# Super block: 0x3D-0x40
	_set_tile_from_config(theme_dir, [0x3D, 0x3E, 0x3F, 0x40], "super_brick")

	# Partial brick images
	_load_partial_brick_images(theme_dir)

func _set_tile_from_config(theme_dir: String, codes: Array, cfg_key: String) -> void:
	var path: String = _config.get_value("tiles", cfg_key, "")
	if path.is_empty():
		return
	var tex := _load_and_scale_image(theme_dir + path)
	if tex:
		for code in codes:
			_tile_textures[code] = tex

func _load_partial_brick_images(theme_dir: String) -> void:
	var mask_to_key: Dictionary = {
		0b1111: "soft_brick_full",
		0b1100: "soft_brick_tl_tr",
		0b0101: "soft_brick_tr_br",
		0b0011: "soft_brick_bl_br",
		0b1010: "soft_brick_tl_bl",
		0b1000: "soft_brick_tl",
		0b0100: "soft_brick_tr",
		0b0010: "soft_brick_bl",
		0b0001: "soft_brick_br",
	}
	for mask in mask_to_key:
		var key: String = mask_to_key[mask]
		var path: String = _config.get_value("tiles", key, "")
		if not path.is_empty():
			# Full brick uses normal load; partial bricks treat black as transparent
			if mask == 0b1111:
				var tex := _load_and_scale_image(theme_dir + path)
				if tex:
					_partial_brick_cache[mask] = tex
			else:
				var tex := _load_image_with_black_transparent(theme_dir + path)
				if tex:
					_partial_brick_cache[mask] = tex

## Load an image where black (R=0,G=0,B=0) pixels become transparent.
## Used for partial brick BMP sprites where empty areas are solid black.
func _load_image_with_black_transparent(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var img: Image = null
	# Try Godot resource loader first
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	# Fallback: raw file load
	if not img:
		var fs_path := ProjectSettings.globalize_path(path)
		img = Image.new()
		if img.load(fs_path) != OK:
			return null
	# Convert to RGBA8 so we can set alpha per-pixel
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Make black pixels transparent, all others fully opaque
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.r < 0.02 and c.g < 0.02 and c.b < 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				c.a = 1.0
				img.set_pixel(x, y, c)
	if _tile_scale > 1:
		img.resize(img.get_width() * _tile_scale, img.get_height() * _tile_scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

func _load_and_scale_image(path: String) -> Texture2D:
	if path.is_empty():
		return null
	# First try Godot's resource loader (works with imported assets)
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			var img := tex.get_image()
			if img:
				# Fix BMP files with zero alpha (32-bit BMPs often have alpha=0)
				_fix_zero_alpha(img)
				if _tile_scale > 1:
					img.resize(img.get_width() * _tile_scale, img.get_height() * _tile_scale, Image.INTERPOLATE_NEAREST)
				return ImageTexture.create_from_image(img)
			# If get_image() fails but we don't need scaling, return as-is
			if _tile_scale <= 1:
				return tex
	# Fallback: try Image.load() with filesystem path
	var fs_path := ProjectSettings.globalize_path(path)
	var img := Image.new()
	var err := img.load(fs_path)
	if err != OK:
		push_warning("ThemeManager: Failed to load image: %s (error %d)" % [fs_path, err])
		return null
	_fix_zero_alpha(img)
	if _tile_scale > 1:
		img.resize(img.get_width() * _tile_scale, img.get_height() * _tile_scale, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)

## Fix 32-bit BMP images that have alpha channel set to 0 (fully transparent).
## Many BMP exporters write BGRA with A=0x00 even though the image should be opaque.
func _fix_zero_alpha(img: Image) -> void:
	# Convert to RGBA8 if needed so we can inspect and modify pixels
	if not img.has_method("get_format"):
		return
	var fmt := img.get_format()
	# Only fix formats that have alpha; skip RGB-only formats
	if fmt != Image.FORMAT_RGBA8 and fmt != Image.FORMAT_RGBA4444 and fmt != Image.FORMAT_RGBAF:
		# No alpha channel — nothing to fix
		return
	if fmt != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Check if all alpha values are zero by sampling a few pixels
	var all_zero := true
	for y in range(mini(img.get_height(), 4)):
		for x in range(mini(img.get_width(), 4)):
			if img.get_pixel(x, y).a > 0.0:
				all_zero = false
				break
		if not all_zero:
			break
	if not all_zero:
		return
	# All sampled alpha values are zero — fix by setting all alpha to 1.0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			c.a = 1.0
			img.set_pixel(x, y, c)

# =====================================================================
# Tank texture loading
# =====================================================================

func _load_tank_textures() -> void:
	# Always load the 24 enemy + 2 player sprites from tank_sprites/
	_load_tank_sprites_from_assets()
	# If theme has sprite overrides, apply those on top
	if _tank_mode == "sprite" and _config:
		var theme_dir := THEMES_DIR + current_theme + "/"
		# Theme can override specific tanks via [tanks] section
		var tank_keys: Dictionary = {
			"p1": "tank_p1", "p2": "tank_p2",
		}
		# Also support theme overrides for e1-e24
		for i in range(1, 25):
			tank_keys["e%d" % i] = "tank_e%d" % i
		for key in tank_keys:
			var cfg_key: String = tank_keys[key]
			var path: String = _config.get_value("tanks", cfg_key, "")
			if not path.is_empty():
				var old_scale := _tile_scale
				_tile_scale = 1
				var tex := _load_image_with_black_transparent(theme_dir + path)
				_tile_scale = old_scale
				if tex:
					_tank_textures[key] = tex
	elif _tank_mode == "modulate":
		# Modulate mode: if no tank_sprites loaded, fall back to default shared sprite
		if _tank_textures.is_empty():
			var tex := load(DEFAULT_TANK_SPRITE) as Texture2D
			if tex:
				for key in ["p1", "p2"]:
					_tank_textures[key] = tex
				for i in range(1, 25):
					_tank_textures["e%d" % i] = tex

## Load all tank sprites from assets/tank_sprites/ with blue edge as transparent
func _load_tank_sprites_from_assets() -> void:
	# Load player tanks
	for p in ["p1", "p2"]:
		var path := TANK_SPRITES_DIR + "tank_%s.png" % p
		var tex := _load_image_with_blue_transparent(path)
		if tex:
			_tank_textures[p] = tex
	# Load 24 enemy tank types
	for i in range(1, 25):
		var path := TANK_SPRITES_DIR + "tank_%d.png" % i
		var tex := _load_image_with_blue_transparent(path)
		if tex:
			_tank_textures["e%d" % i] = tex

## Load an image where the blue edge color (R<0.05, G<0.05, B>0.9) becomes transparent.
## Used for tank sprites from assets/tank_sprites/.
func _load_image_with_blue_transparent(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	if not img:
		var fs_path := ProjectSettings.globalize_path(path)
		img = Image.new()
		if img.load(fs_path) != OK:
			return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Sample corner pixel to detect the background color
	var bg_color := img.get_pixel(0, 0)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			# Treat pixels matching the background color as transparent
			if _is_same_color(c, bg_color):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				c.a = 1.0
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _is_same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03

# =====================================================================
# Addon texture loading
# =====================================================================

const ADDONS_DIR: String = "res://assets/sprites/addons/"

## Load all addon sprites from assets/sprites/addons/ with corner-color-as-transparent
const ADDON_NAMES: Array = ["moon-shield", "anti-water", "anti-ice", "memory-save"]

func _load_addon_textures() -> void:
	for addon_name in ADDON_NAMES:
		var path: String = ADDONS_DIR + addon_name + ".png"
		var tex := _load_image_with_blue_transparent(path)
		if tex:
			_addon_textures[addon_name] = tex
		else:
			push_warning("ThemeManager: Failed to load addon texture: %s" % path)

# =====================================================================
# Procedural texture generation (moved from level_manager.gd)
# =====================================================================

func _generate_procedural_textures() -> void:
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

# =====================================================================
# Procedural texture generators
# =====================================================================

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
	var mortar := Color(0.3, 0.25, 0.2)
	var color_mult := 0.7 + hp * 0.075
	var brick_col := Color(base_color.r * color_mult, base_color.g * color_mult, base_color.b * color_mult)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
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
