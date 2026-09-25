extends Node

## ThemeManager — autoload singleton providing all visual textures.
## Supports "procedural" themes (generated at runtime) and "image" themes (loaded from files).

signal theme_changed(theme_name: String)

const THEMES_DIR: String = "res://themes/"
## The game's own stage pictures, shown where a theme brings none.
const GAME_SCREENS_DIR := "res://assets/screens/"
const DEFAULT_TANK_SPRITE: String = "res://assets/sprites/tanks/tank.png"
const TANK_SPRITES_DIR: String = "res://assets/tank_sprites/"
const TILE_SIZE: int = 32

## The game's one theme (Sean, 2026-09-25): no setting picks another.
const GAME_THEME := "juezhuantanke"

var current_theme: String = GAME_THEME
var _theme_type: String = "procedural"   # "procedural" or "image"
var _tile_scale: int = 1
var _tank_mode: String = "modulate"      # "modulate" or "sprite"
var _config: ConfigFile = null

# Cached textures
var _tile_textures: Dictionary = {}           # code (int) -> Texture2D
var _partial_brick_cache: Dictionary = {}     # mask (int) or "mask_variant" (String) -> Texture2D
var _tank_textures: Dictionary = {}           # "p1","p2","e1"-"e24" -> Texture2D
var _addon_textures: Dictionary = {}         # "moon-shield","anti-water",etc -> Texture2D
var _addon_frames: Dictionary = {}           # "anti-water","memory-save" -> Array[Texture2D] (4-frame anim)
var _addon_facing_textures: Dictionary = {}  # "anti-ice","moon-shield" -> [up, right, down, left]
var _flag_frames: Dictionary = {}            # "healthy","dead","invincible" -> Array[Texture2D] (base flag anim)
var _hit_frames: Dictionary = {}             # bullet visual style -> Array[Texture2D] (hit anim)
var _hit_duration: float = 0.2
var _tank_explode_frames: Array = []         # a destroyed tank's explosion (empty: built-in burst)
var _tank_explode_duration: float = 0.4

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
	_addon_frames.clear()
	_addon_facing_textures.clear()
	_flag_frames.clear()
	_hit_frames.clear()
	_tank_explode_frames = []

	if _theme_type == "procedural":
		_generate_procedural_textures()
	else:
		_load_image_textures()

	_load_tank_textures()
	_load_addon_textures()
	_load_addon_frames()
	_load_addon_facing_textures()
	_load_flag_frames()
	_load_hit_frames()
	_load_tank_explode_frames()
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

## Animation frames of the base flag for [param state] ("healthy", "dead" or
## "invincible"). Empty when the theme has no flag strip (the default eagle is used).
func get_flag_frames(state: String) -> Array:
	return _flag_frames.get(state, [])

## Hit animation for a bullet visual style ("regular", "rapid", "fire", "ap",
## "explosion"), or empty when the theme has none (the built-in flash is used).
func get_hit_frames(style: String) -> Array:
	return _hit_frames.get(style, [])

## Seconds a hit animation takes to play through once.
func get_hit_duration() -> float:
	return _hit_duration

## A destroyed tank's explosion, or empty when the theme has none (the built-in
## burst is used).
func get_tank_explode_frames() -> Array:
	return _tank_explode_frames

## Seconds the tank explosion takes to play through once.
func get_tank_explode_duration() -> float:
	return _tank_explode_duration

## Addon sprite texture (e.g. "moon-shield", "anti-water")
func get_addon_texture(addon_name: String) -> Texture2D:
	return _addon_textures.get(addon_name, null)

## Whether tanks should use color modulation (true) or dedicated sprites (false)
func is_tank_modulate_mode() -> bool:
	return _tank_mode == "modulate"

## Read any value out of the current theme.cfg, for systems that keep their own
## theme-specific assets (see SoundManager and the [sounds] section).
func get_theme_setting(section: String, key: String, fallback: Variant) -> Variant:
	if _config == null:
		return fallback
	return _config.get_value(section, key, fallback)

## Absolute res:// folder of the current theme, with a trailing slash.
func get_theme_dir() -> String:
	return THEMES_DIR + current_theme + "/"

## The stage intro picture a stage names ([param file_name], e.g. "SI01.JPG"),
## found in the theme's [screens] dir whatever its case; null when the theme
## has no screens or no such picture.
func get_stage_picture(file_name: String) -> Texture2D:
	if file_name.is_empty():
		return null
	var wanted := file_name.get_file().to_lower()
	var rel_dir: String = get_theme_setting("screens", "dir", "")
	if not rel_dir.is_empty():
		var dir := get_theme_dir() + rel_dir
		for listed in DirAccess.get_files_at(dir):
			# An exported game lists the import stubs ("SI01.jpg.import") instead.
			var name := listed.trim_suffix(".import") if listed.ends_with(".import") else listed
			if name.to_lower() == wanted:
				return load(dir + name) as Texture2D
	# The game's own: one for each of the original's names, SI00 to SI09.
	var digit := wanted.trim_prefix("si0").get_basename()
	if wanted.begins_with("si0") and digit.length() == 1 and digit.is_valid_int():
		return _game_picture("stage_intro_" + digit)
	return null

## A picture from the theme's [screens] section ("stage_win", "stage_lose",
## "results_panel"), else the game's own if it has one (tools/make_screens.py
## draws them), else null.
func get_screen_texture(key: String) -> Texture2D:
	var rel_path: String = get_theme_setting("screens", key, "")
	if not rel_path.is_empty() and ResourceLoader.exists(get_theme_dir() + rel_path):
		return load(get_theme_dir() + rel_path) as Texture2D
	return _game_picture(key)

## The game's own stage picture [param name] (assets/screens), or null.
func _game_picture(name: String) -> Texture2D:
	var path := GAME_SCREENS_DIR + name + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

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
# Base flag strip loading
# =====================================================================

const FLAG_STATES: Array = ["healthy", "dead", "invincible"]

## [base] flag="..." in theme.cfg: a strip with one row per FLAG_STATES entry and
## `frames` square frames of `frame_size` px per row, keyed on the corner colour.
func _load_flag_frames() -> void:
	if not _config:
		return
	var rel_path: String = _config.get_value("base", "flag", "")
	if rel_path.is_empty():
		return
	var frame_size: int = _config.get_value("base", "frame_size", 32)
	var frame_count: int = _config.get_value("base", "frames", 8)
	var strip := _load_image_with_blue_transparent(THEMES_DIR + current_theme + "/" + rel_path)
	if strip == null:
		push_warning("ThemeManager: could not load flag strip " + rel_path)
		return
	var img := strip.get_image()
	if img.get_width() < frame_size * frame_count or img.get_height() < frame_size * FLAG_STATES.size():
		push_warning("ThemeManager: flag strip %s is too small for %dx%d frames" % [rel_path, frame_count, FLAG_STATES.size()])
		return
	for row in FLAG_STATES.size():
		var frames: Array = []
		for column in frame_count:
			var region := img.get_region(Rect2i(column * frame_size, row * frame_size, frame_size, frame_size))
			frames.append(ImageTexture.create_from_image(region))
		_flag_frames[FLAG_STATES[row]] = frames

# =====================================================================
# Bullet hit effects
# =====================================================================

const HIT_STYLES: Array = ["regular", "rapid", "fire", "explosion", "ap"]

## [effects] hit_<style>="strip.png" in theme.cfg: a horizontal strip of square
## frames, keyed on its corner colour and scaled by tile_scale like the tiles.
func _load_hit_frames() -> void:
	if not _config:
		return
	_hit_duration = _config.get_value("effects", "hit_duration", 0.2)
	var by_path: Dictionary = {}  # several styles may share one strip
	for style in HIT_STYLES:
		var rel_path: String = _config.get_value("effects", "hit_" + style, "")
		if rel_path.is_empty():
			continue
		if not by_path.has(rel_path):
			by_path[rel_path] = _slice_strip(THEMES_DIR + current_theme + "/" + rel_path)
		if not by_path[rel_path].is_empty():
			_hit_frames[style] = by_path[rel_path]

## [effects] tank_explode="strip.png" in theme.cfg: what a destroyed tank turns
## into, a strip like the hit ones.
func _load_tank_explode_frames() -> void:
	if not _config:
		return
	_tank_explode_duration = _config.get_value("effects", "tank_explode_duration", 0.4)
	var rel_path: String = _config.get_value("effects", "tank_explode", "")
	if not rel_path.is_empty():
		_tank_explode_frames = _slice_strip(THEMES_DIR + current_theme + "/" + rel_path)

func _slice_strip(path: String) -> Array:
	var strip := _load_image_with_blue_transparent(path)
	if strip == null:
		push_warning("ThemeManager: could not load effect strip " + path)
		return []
	var img := strip.get_image()
	var size := img.get_height()
	var frames: Array = []
	for i in img.get_width() / size:
		var frame := img.get_region(Rect2i(i * size, 0, size, size))
		if _tile_scale > 1:
			frame.resize(size * _tile_scale, size * _tile_scale, Image.INTERPOLATE_NEAREST)
		frames.append(ImageTexture.create_from_image(frame))
	return frames

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

## Addon animations from Tank_L (anti-water row 1, memory-save row 4): 4 frames each,
## already keyed to transparent, so load them preserving their alpha.
const ADDON_ANIM_NAMES: Array = ["anti-water", "memory-save"]
const ADDON_ANIM_FRAME_COUNT: int = 4

func _load_addon_frames() -> void:
	for addon_name in ADDON_ANIM_NAMES:
		var frames: Array = []
		for f in range(1, ADDON_ANIM_FRAME_COUNT + 1):
			var tex := _load_texture_keep_alpha(ADDONS_DIR + "%s_%d.png" % [addon_name, f])
			if tex:
				frames.append(tex)
		if frames.size() == ADDON_ANIM_FRAME_COUNT:
			_addon_frames[addon_name] = frames

func _load_texture_keep_alpha(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(img)
	return null

## Returns the 4-frame animation for an addon (anti-water / memory-save), or [].
func get_addon_frames(addon_name: String) -> Array:
	return _addon_frames.get(addon_name, [])

## Add-ons Tank.exe drew with a separate frame for each facing rather than one
## frame turned (Tank_L rows 2 and 3; the shading stays lit from the same side).
const ADDON_FACING_NAMES: Array = ["anti-ice", "moon-shield"]
const ADDON_FACING_SUFFIXES: Array = ["up", "right", "down", "left"]

func _load_addon_facing_textures() -> void:
	for addon_name in ADDON_FACING_NAMES:
		var frames: Array = []
		for suffix in ADDON_FACING_SUFFIXES:
			var tex := _load_image_with_blue_transparent(ADDONS_DIR + "%s_%s.png" % [addon_name, suffix])
			if tex:
				frames.append(tex)
		if frames.size() == ADDON_FACING_SUFFIXES.size():
			_addon_facing_textures[addon_name] = frames

## The frames for [param addon_name] facing up, right, down and left, or [] when
## it has just the one (the tank turns that one instead).
func get_addon_facing_textures(addon_name: String) -> Array:
	return _addon_facing_textures.get(addon_name, [])

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
