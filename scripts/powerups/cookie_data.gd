class_name CookieData
extends RefCounted

## All 25 cookie types matching the cookie_system Excel sheet
enum CookieType {
	# utility_power_up (5)
	SPEED_UP,
	HP_UP,
	WEAPONS_UP,
	STAR_UP,
	MAX_UP,
	# addon (4)
	ANTI_WATER_COOKIE,
	ANTI_ICE_COOKIE,
	MOON_SHIELD_COOKIE,
	MEMORY_SAVE_COOKIE,
	# utility_score_up (6)
	SCORE_200,
	SCORE_500,
	SCORE_1000,
	SCORE_2000,
	BULLETS_MAX,
	BULLET_REFILL,
	# utility_special (5)
	INVINCIBLE_HELMET,
	FLAG_PROTECTION,
	TANK_WEB,
	TANK_BOMB,
	TANK_LIFE,
	# weapon (5)
	RAPID_COOKIE,
	FIRE_COOKIE,
	AP_COOKIE,
	EXPLOSION_COOKIE,
	MINE_COOKIE,
}

## Cookie metadata: category string, despawn time, texture filename
const COOKIE_INFO: Dictionary = {
	CookieType.SPEED_UP:           { "despawn_time": 40.0, "texture": "speed_up.png" },
	CookieType.HP_UP:              { "despawn_time": 40.0, "texture": "hp_up.png" },
	CookieType.WEAPONS_UP:         { "despawn_time": 40.0, "texture": "weapons_up.png" },
	CookieType.STAR_UP:            { "despawn_time": 40.0, "texture": "star_up.png" },
	CookieType.MAX_UP:             { "despawn_time": 40.0, "texture": "max_up.png" },
	CookieType.ANTI_WATER_COOKIE:  { "despawn_time": 15.0, "texture": "anti_water_cookie.png" },
	CookieType.ANTI_ICE_COOKIE:    { "despawn_time": 15.0, "texture": "anti_ice_cookie.png" },
	CookieType.MOON_SHIELD_COOKIE: { "despawn_time": 15.0, "texture": "moon_shield_cookie.png" },
	CookieType.MEMORY_SAVE_COOKIE: { "despawn_time": 15.0, "texture": "memory_save_cookie.png" },
	CookieType.SCORE_200:          { "despawn_time": 40.0, "texture": "score_200.png" },
	CookieType.SCORE_500:          { "despawn_time": 40.0, "texture": "score_500.png" },
	CookieType.SCORE_1000:         { "despawn_time": 40.0, "texture": "score_1000.png" },
	CookieType.SCORE_2000:         { "despawn_time": 40.0, "texture": "score_2000.png" },
	CookieType.BULLETS_MAX:        { "despawn_time": 40.0, "texture": "bullets_max.png" },
	CookieType.BULLET_REFILL:      { "despawn_time": 40.0, "texture": "bullet_refill.png" },
	CookieType.INVINCIBLE_HELMET:  { "despawn_time": 40.0, "texture": "invincible_helmet.png" },
	CookieType.FLAG_PROTECTION:    { "despawn_time": 40.0, "texture": "flag_protection.png" },
	CookieType.TANK_WEB:           { "despawn_time": 40.0, "texture": "tank_web.png" },
	CookieType.TANK_BOMB:          { "despawn_time": 40.0, "texture": "tank_bomb.png" },
	CookieType.TANK_LIFE:          { "despawn_time": 40.0, "texture": "tank_life.png" },
	CookieType.RAPID_COOKIE:       { "despawn_time": 40.0, "texture": "rapid_cookie.png" },
	CookieType.FIRE_COOKIE:        { "despawn_time": 40.0, "texture": "fire_cookie.png" },
	CookieType.AP_COOKIE:          { "despawn_time": 40.0, "texture": "ap_cookie.png" },
	CookieType.EXPLOSION_COOKIE:   { "despawn_time": 40.0, "texture": "explosion_cookie.png" },
	CookieType.MINE_COOKIE:        { "despawn_time": 40.0, "texture": "mine_cookie.png" },
}

# --- Category pools for random selection on death drop ---
const POOL_UTILITY_POWER_UP: Array = [
	CookieType.SPEED_UP, CookieType.HP_UP, CookieType.WEAPONS_UP,
	CookieType.STAR_UP, CookieType.MAX_UP,
]
const POOL_UTILITY_SCORE_UP: Array = [
	CookieType.SCORE_200, CookieType.SCORE_500, CookieType.SCORE_1000,
	CookieType.SCORE_2000, CookieType.BULLETS_MAX, CookieType.BULLET_REFILL,
]
const POOL_UTILITY_SPECIAL: Array = [
	CookieType.INVINCIBLE_HELMET, CookieType.FLAG_PROTECTION,
	CookieType.TANK_WEB, CookieType.TANK_BOMB, CookieType.TANK_LIFE,
]
const POOL_WEAPON: Array = [
	CookieType.RAPID_COOKIE, CookieType.FIRE_COOKIE, CookieType.AP_COOKIE,
	CookieType.EXPLOSION_COOKIE, CookieType.MINE_COOKIE,
]

## Maps addon name string to corresponding addon cookie type
const ADDON_TO_COOKIE: Dictionary = {
	"anti-water":   CookieType.ANTI_WATER_COOKIE,
	"anti-ice":     CookieType.ANTI_ICE_COOKIE,
	"moon-shield":  CookieType.MOON_SHIELD_COOKIE,
	"memory-save":  CookieType.MEMORY_SAVE_COOKIE,
}

## Maps tank_type_id (1-24) to weapon type string from tank_table.xlsx
const TYPE_WEAPON_MAP: Dictionary = {
	1: "none", 2: "none", 3: "none", 4: "none",
	5: "rapid", 6: "rapid", 7: "rapid", 8: "rapid",
	9: "fire", 10: "fire", 11: "fire", 12: "fire",
	13: "ap", 14: "ap", 15: "ap", 16: "ap",
	17: "explosion", 18: "explosion", 19: "explosion", 20: "explosion",
	21: "mine", 22: "mine", 23: "mine", 24: "mine",
}

## Maps weapon type string to specific cookie type
const WEAPON_TO_COOKIE: Dictionary = {
	"rapid":     CookieType.RAPID_COOKIE,
	"fire":      CookieType.FIRE_COOKIE,
	"ap":        CookieType.AP_COOKIE,
	"explosion": CookieType.EXPLOSION_COOKIE,
	"mine":      CookieType.MINE_COOKIE,
}

## Secondary weapon data: reload_count (given on pickup/refill), max_count (bullets_max cap)
const WEAPON_DATA: Dictionary = {
	"rapid":     { "reload_count": 50, "max_count": 200 },
	"fire":      { "reload_count": 30, "max_count": 150 },
	"ap":        { "reload_count": 10, "max_count": 50 },
	"explosion": { "reload_count": 20, "max_count": 60 },
	"mine":      { "reload_count": 25, "max_count": 75 },
}

const COOKIE_TEXTURES_DIR: String = "res://assets/sprites/cookies/"

# Magenta background key color used in cookie PNGs (RGB 248,0,248)
const BG_KEY_R: float = 248.0 / 255.0
const BG_KEY_G: float = 0.0
const BG_KEY_B: float = 248.0 / 255.0
const BG_KEY_THRESHOLD: float = 0.05

# Static texture cache
static var _cookie_textures: Dictionary = {}

static func get_cookie_texture(cookie_type: int) -> Texture2D:
	if _cookie_textures.has(cookie_type):
		return _cookie_textures[cookie_type]
	var info: Dictionary = COOKIE_INFO.get(cookie_type, {})
	if info.is_empty():
		return null
	var path: String = COOKIE_TEXTURES_DIR + info["texture"]
	var abs_path: String = ProjectSettings.globalize_path(path)
	var img := Image.new()
	if img.load(abs_path) != OK:
		return null
	# Convert to RGBA8 so we can set alpha
	img.convert(Image.FORMAT_RGBA8)
	# Replace magenta background with transparency
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			if absf(c.r - BG_KEY_R) < BG_KEY_THRESHOLD \
				and absf(c.g - BG_KEY_G) < BG_KEY_THRESHOLD \
				and absf(c.b - BG_KEY_B) < BG_KEY_THRESHOLD:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	_cookie_textures[cookie_type] = tex
	return tex

## Roll a death-drop cookie type for a dying enemy tank.
## Returns -1 if no drop (40% chance), otherwise a CookieType value.
static func roll_death_drop(tank_type_id: int) -> int:
	# 60% chance to drop
	if randf() > 0.60:
		return -1

	var weapon_type: String = TYPE_WEAPON_MAP.get(tank_type_id, "none")
	var has_weapon := weapon_type != "none"

	# 25% each category; if no weapon, redistribute to other 3 (~33.3% each)
	var roll := randf()
	var category: int
	if has_weapon:
		if roll < 0.25:
			category = 0  # utility_power_up
		elif roll < 0.50:
			category = 1  # utility_score_up
		elif roll < 0.75:
			category = 2  # utility_special
		else:
			category = 3  # weapon
	else:
		if roll < 0.333:
			category = 0
		elif roll < 0.666:
			category = 1
		else:
			category = 2

	match category:
		0: return POOL_UTILITY_POWER_UP[randi() % POOL_UTILITY_POWER_UP.size()]
		1: return POOL_UTILITY_SCORE_UP[randi() % POOL_UTILITY_SCORE_UP.size()]
		2: return POOL_UTILITY_SPECIAL[randi() % POOL_UTILITY_SPECIAL.size()]
		3: return WEAPON_TO_COOKIE[weapon_type]

	return -1
