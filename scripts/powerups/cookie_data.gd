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

## The original game's enemy gun levels (its enemy spawn, 0x00499f30): a base
## per tank type plus a bonus for the difficulty, clamped to 0-3. Mine tanks use
## it (see get_enemy_weapon_level); the table covers every type.
const ORIGINAL_TYPE_GUN_LEVEL: Array[int] = [
	0, 1, 1, 2,   # 1-4   plain gun
	0, 1, 2, 3,   # 5-8   rapid
	0, 1, 2, 3,   # 9-12  fire
	0, 1, 1, 2,   # 13-16 AP
	0, 1, 2, 3,   # 17-20 explosion
	0, 1, 1, 2,   # 21-24 mine
]
## Gun-level bonus by difficulty 0-5, from the original's difficulty records
## (0x004d2860). The remake's EASY..INSANE (1-5) are the original's 1-5, as the
## save importer already assumes; the original's easiest level 0 is not offered.
const ORIGINAL_DIFFICULTY_GUN_BONUS: Array[int] = [-1, 0, 0, 0, 1, 1]

## Special weapon levels by tank type and game difficulty (1-5) from tank_table.xlsx.
## Only rapid is wired up for now.
const TYPE_WEAPON_LEVELS: Dictionary = {
	5: [0, 0, 0, 1, 1],
	6: [0, 0, 1, 1, 2],
	7: [0, 0, 1, 2, 2],
	8: [0, 0, 0, 0, 1],
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
## AP holds 100 (Sean, 2026-09-25); the original stopped at 50.
const WEAPON_DATA: Dictionary = {
	"rapid":     { "reload_count": 50, "max_count": 200 },
	"fire":      { "reload_count": 30, "max_count": 150 },
	"ap":        { "reload_count": 10, "max_count": 100 },
	"explosion": { "reload_count": 20, "max_count": 100 },
	"mine":      { "reload_count": 25, "max_count": 75 },
}

const RAPID_FIRE_CONFIG: Dictionary = {
	0: { "cooldown": 0.4, "rows": [0.0], "ammo_per_count": 1, "speed_multiplier": 1.5 },
	1: { "cooldown": 0.3, "rows": [-16.0, 16.0], "ammo_per_count": 1, "speed_multiplier": 1.5 },
	2: {
		"cooldown": 0.25,
		"rows": [-16.0, 0.0, 16.0, 0.0],
		"ammo_per_count": 3,
		"speed_multiplier": 1.5,
	},
	3: {
		"cooldown": 0.2,
		"rows": [-16.0, 0.0, 16.0, 0.0],
		"ammo_per_count": 5,
		"speed_multiplier": 1.5,
	},
}

## Fire gun config by weapon level (0-3). A fire bullet flies straight and, on
## death, ignites (or grows) a ground-fire field. Growth/shape/burn-time are the
## field's job; weapon level only affects fire rate, in-flight cap, and `damage`
## (how much the fire bullet subtracts from a crossed enemy bullet — rule 6).
const FIRE_FIRE_CONFIG: Dictionary = {
	0: { "cooldown": 0.27,  "speed": 520.0, "range_px": 480.0, "max_in_flight": 3, "damage": 1 },
	1: { "cooldown": 0.225, "speed": 520.0, "range_px": 480.0, "max_in_flight": 4, "damage": 1 },
	2: { "cooldown": 0.18,  "speed": 520.0, "range_px": 480.0, "max_in_flight": 5, "damage": 2 },
	3: { "cooldown": 0.135, "speed": 520.0, "range_px": 480.0, "max_in_flight": 6, "damage": 2 },
}

## Explosion gun config by weapon level (0-3). The bullet flies straight and fast,
## detonating a shockwave wherever it dies; "level" scales the blast (power/radius)
## and "damage" is the direct-hit / bullet-vs-bullet value. See explosion_blast.gd.
## "level" drives the wave (radius + spray damage, see ExplosionBlast); "damage"
## is the DIRECT hit dealt to a tank the bullet strikes (3/4/5/6 by level).
const EXPLOSION_FIRE_CONFIG: Dictionary = {
	0: { "cooldown": 0.45,  "speed": 650.0, "max_in_flight": 2, "level": 0, "damage": 3 },
	1: { "cooldown": 0.375, "speed": 650.0, "max_in_flight": 2, "level": 1, "damage": 4 },
	2: { "cooldown": 0.30,  "speed": 650.0, "max_in_flight": 3, "level": 2, "damage": 5 },
	3: { "cooldown": 0.225, "speed": 650.0, "max_in_flight": 4, "level": 3, "damage": 6 },
}

## Mine config by weapon level (0-3). The mine's own level is the weapon level:
##   L0 blast · L1 + slow · L2 + hit and fly · L3 harder. See mine.gd.
const MINE_FIRE_CONFIG: Dictionary = {
	0: { "cooldown": 0.6 },
	1: { "cooldown": 0.55 },
	2: { "cooldown": 0.5 },
	3: { "cooldown": 0.45 },
}

## AP gun config by weapon level (0-3). A slow-launch, accelerating shell whose
## "damage" is a pool it spends piercing through tanks and walls. See bullet.gd.
const AP_FIRE_CONFIG: Dictionary = {
	0: { "cooldown": 0.6, "speed": 222.0, "accel": 889.0, "max_speed": 667.0, "damage": 8,  "max_in_flight": 2 },
	1: { "cooldown": 0.5, "speed": 222.0, "accel": 889.0, "max_speed": 667.0, "damage": 10, "max_in_flight": 2 },
	2: { "cooldown": 0.4, "speed": 222.0, "accel": 889.0, "max_speed": 667.0, "damage": 12, "max_in_flight": 3 },
	3: { "cooldown": 0.3, "speed": 222.0, "accel": 889.0, "max_speed": 667.0, "damage": 14, "max_in_flight": 3 },
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

static func get_weapon_fire_config(weapon_type: String, level: int) -> Dictionary:
	match weapon_type:
		"rapid":
			return RAPID_FIRE_CONFIG.get(clampi(level, 0, 3), RAPID_FIRE_CONFIG[0])
		"fire":
			return FIRE_FIRE_CONFIG.get(clampi(level, 0, 3), FIRE_FIRE_CONFIG[0])
		"explosion":
			return EXPLOSION_FIRE_CONFIG.get(clampi(level, 0, 3), EXPLOSION_FIRE_CONFIG[0])
		"mine":
			return MINE_FIRE_CONFIG.get(clampi(level, 0, 3), MINE_FIRE_CONFIG[0])
		"ap":
			return AP_FIRE_CONFIG.get(clampi(level, 0, 3), AP_FIRE_CONFIG[0])
	return {}

static func get_enemy_weapon_level(tank_type_id: int, difficulty: int) -> int:
	if TYPE_WEAPON_MAP.get(tank_type_id, "none") == "mine":
		return original_enemy_gun_level(tank_type_id, difficulty)
	var levels: Array = TYPE_WEAPON_LEVELS.get(tank_type_id, [])
	if levels.is_empty():
		return 0
	var idx := clampi(difficulty, 1, levels.size()) - 1
	return levels[idx]

## The original's gun level for an enemy of [param tank_type_id] (1-24). The
## difficulty keeps climbing on map loops; the original capped it at 5.
static func original_enemy_gun_level(tank_type_id: int, difficulty: int) -> int:
	var base: int = ORIGINAL_TYPE_GUN_LEVEL[clampi(tank_type_id, 1, 24) - 1]
	var bonus: int = ORIGINAL_DIFFICULTY_GUN_BONUS[clampi(difficulty, 0, 5)]
	return clampi(base + bonus, 0, 3)

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
