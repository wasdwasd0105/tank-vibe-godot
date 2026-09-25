class_name EnemyTank
extends BaseTank

# Tank type ID (1-24) matching tank_<id>.png sprites and Stage.dat EnemyCount values
@export var tank_type_id: int = 1
@export var points_value: int = 100

var special_weapon_type: String = "none"
var special_weapon_level: int = 0
var _direction_change_timer: float = 0.0
var _shoot_cooldown: float = 0.0
var _hits_taken: int = 0
## The player credited with destroying this tank: the owner of the weapon that
## dealt its last point (-1: an enemy's weapon, grass fire, or nobody).
var killed_by: int = -1
var _alive_time: float = 0.0  # Time since spawn (for initial downward push)
var _collision_cooldown: float = 0.0  # Prevents eagle bias right after a collision
var _near_eagle: bool = false  # True when within attack range of eagle
var _water_avoid_dir: Vector2 = Vector2.ZERO  # Direction blocked by water (avoid it)
var _water_avoid_timer: float = 0.0  # How long to avoid the water-blocked direction
var _attack_wall_dir: Vector2 = Vector2.ZERO  # Direction of wall we're shooting to break
var _attack_wall_timer: float = 0.0  # Time left to keep attacking a wall
var _turn_cooldown: float = 0.0  # Prevents rapid direction changes after collision
var _rapid_special_fire_step: int = 0
const TURN_COOLDOWN_DURATION: float = 0.6  # Minimum seconds between collision-triggered turns
const INITIAL_DOWN_DURATION: float = 2.0  # Move DOWN for first 2 seconds after spawn
const COLLISION_COOLDOWN_DURATION: float = 1.0  # Seconds to suppress eagle bias after collision
const EAGLE_ATTACK_RANGE: float = 192.0  # ~6 tiles — enter attack mode
const WATER_AVOID_DURATION: float = 4.0  # Seconds to commit to going around water
const ATTACK_WALL_DURATION: float = 3.0  # Seconds to commit to shooting a wall
const SPECIAL_FIRE_CHANCE: float = 0.5
const ENEMY_REGULAR_FIRE_COOLDOWN: float = 0.3
# Fire is persistent area-denial, so enemies use it sparingly: a lower pick
# chance and a long gap between fire shots (the player's fast fire cadence would
# blanket the map). Tune these if enemy fire feels too weak/strong.
const ENEMY_FIRE_CHANCE: float = 0.3
const ENEMY_FIRE_COOLDOWN_MIN: float = 2.2
const ENEMY_FIRE_COOLDOWN_MAX: float = 3.5
# Explosion is powerful area-denial + terrain damage — enemies use it sparingly.
const ENEMY_EXPLOSION_CHANCE: float = 0.35
const ENEMY_EXPLOSION_COOLDOWN_MIN: float = 2.0
const ENEMY_EXPLOSION_COOLDOWN_MAX: float = 3.5

const ENEMY_MINE_CHANCE: float = 0.25
const ENEMY_MINE_COOLDOWN_MIN: float = 2.5
const ENEMY_MINE_COOLDOWN_MAX: float = 4.5
## Enemy mines stop at level 2. The original let the toughest mine tank lay
## ringed level-3 mines on EXPERT and INSANE; the remake leaves those out.
const ENEMY_MINE_MAX_LEVEL: int = 2

const ENEMY_AP_CHANCE: float = 0.4
const ENEMY_AP_COOLDOWN_MIN: float = 1.5
const ENEMY_AP_COOLDOWN_MAX: float = 2.8

# --- Addon system ---
const ADDON_MOON_SHIELD := "moon-shield"
const ADDON_ANTI_WATER := "anti-water"
const ADDON_ANTI_ICE := "anti-ice"
const ADDON_MEMORY_SAVE := "memory-save"

# Which tank types have which addons (type_id -> array of addon names)
const TYPE_ADDONS: Dictionary = {
	2:  [ADDON_ANTI_WATER],
	4:  [ADDON_MOON_SHIELD],
	6:  [ADDON_ANTI_ICE],
	8:  [ADDON_MEMORY_SAVE],
	12: [ADDON_MOON_SHIELD],
	16: [ADDON_ANTI_WATER],
	18: [ADDON_ANTI_WATER],
	20: [ADDON_ANTI_ICE],
	22: [ADDON_ANTI_ICE],
	24: [ADDON_MEMORY_SAVE],
}

# --- Bonus items. An enemy that drives over an item it may take gets it, as a
# player would; one it may not, it drives over and leaves lying there (Tank.exe's
# pickup filter, 0x0049595b). Nothing makes an enemy seek items out. ---

## The upgrades and add-ons: the original's items 0-8.
const UPGRADE_ITEMS: Array = [
	CookieData.CookieType.SPEED_UP, CookieData.CookieType.HP_UP,
	CookieData.CookieType.WEAPONS_UP, CookieData.CookieType.STAR_UP,
	CookieData.CookieType.MAX_UP, CookieData.CookieType.ANTI_WATER_COOKIE,
	CookieData.CookieType.ANTI_ICE_COOKIE, CookieData.CookieType.MOON_SHIELD_COOKIE,
	CookieData.CookieType.MEMORY_SAVE_COOKIE,
]
## The specials and the two ammo items: the original's items 13-19.
const SPECIAL_ITEMS: Array = [
	CookieData.CookieType.INVINCIBLE_HELMET, CookieData.CookieType.FLAG_PROTECTION,
	CookieData.CookieType.TANK_WEB, CookieData.CookieType.TANK_BOMB,
	CookieData.CookieType.TANK_LIFE, CookieData.CookieType.BULLETS_MAX,
	CookieData.CookieType.BULLET_REFILL,
]
## Taking an item leaves the tank untouchable for 1000 ticks, blinking.
const PICKUP_INVULNERABILITY: float = 0.75
## The most HP items can build an enemy up to.
const MAX_ITEM_HP: int = 8
## The best gun level items can build an enemy up to.
const MAX_ITEM_GUN: int = 3
## A speed item's step, and the most speed items can build an enemy up to.
const ITEM_SPEED_STEP: float = 32.0
const ITEM_MAX_SPEED: float = 192.0
var _invulnerable_timer: float = 0.0

var addons: Array = []
var has_moon_shield: bool = false
var has_anti_ice: bool = false
var _shield_sprite: Sprite2D = null  # Reference for front-positioned shield
var _addon_sprites: Array = []  # All addon Sprite2D nodes
var _frost_shown: bool = false  # freeze-frost overlay currently on (tracks GameManager.enemies_frozen)
## The water tiles under the tank when it lost anti-water. The original tested
## only the tiles a tank drove into, so these let it be until it has left them:
## stranded mid-lake it stays put, near the shore it can drive out, and new
## water stops it as ever. (Godot would otherwise shove it out of the water.)
var _afloat_on: Array = []

## Add-on size relative to TANK_SIZE. Where each one sits is BaseTank's
## _layout_addons, as the original placed them.
const ADDON_CONFIG: Dictionary = {
	"moon-shield":  { "scale": 1.0 },
	"anti-water":   { "scale": 1.0 },
	"anti-ice":     { "scale": 1.0 },
	"memory-save":  { "scale": 1.0 },
}

# Stats for each of the 24 tank types from tank_table.xlsx
# Speed mapping: 1->64, 2->96, 3->128 pixels/sec
# Points scale with HP tier
const SPEED_MAP: Dictionary = { 1: 64.0, 2: 96.0, 3: 128.0 }
const TYPE_STATS: Dictionary = {
	1:  { "speed": 1, "health": 1, "bullet_speed": 192.0, "points": 100 },
	2:  { "speed": 1, "health": 2, "bullet_speed": 192.0, "points": 100 },
	3:  { "speed": 1, "health": 1, "bullet_speed": 192.0, "points": 100 },
	4:  { "speed": 1, "health": 2, "bullet_speed": 192.0, "points": 100 },
	5:  { "speed": 3, "health": 2, "bullet_speed": 224.0, "points": 200 },
	6:  { "speed": 2, "health": 3, "bullet_speed": 224.0, "points": 200 },
	7:  { "speed": 3, "health": 2, "bullet_speed": 224.0, "points": 200 },
	8:  { "speed": 2, "health": 3, "bullet_speed": 224.0, "points": 200 },
	9:  { "speed": 2, "health": 3, "bullet_speed": 256.0, "points": 300 },
	10: { "speed": 2, "health": 3, "bullet_speed": 256.0, "points": 300 },
	11: { "speed": 2, "health": 3, "bullet_speed": 256.0, "points": 300 },
	12: { "speed": 2, "health": 4, "bullet_speed": 256.0, "points": 300 },
	13: { "speed": 1, "health": 6, "bullet_speed": 288.0, "points": 400 },
	14: { "speed": 1, "health": 6, "bullet_speed": 288.0, "points": 400 },
	15: { "speed": 1, "health": 6, "bullet_speed": 288.0, "points": 400 },
	16: { "speed": 1, "health": 7, "bullet_speed": 288.0, "points": 400 },
	17: { "speed": 2, "health": 3, "bullet_speed": 320.0, "points": 500 },
	18: { "speed": 2, "health": 4, "bullet_speed": 320.0, "points": 500 },
	19: { "speed": 2, "health": 3, "bullet_speed": 320.0, "points": 500 },
	20: { "speed": 2, "health": 4, "bullet_speed": 320.0, "points": 500 },
	21: { "speed": 2, "health": 2, "bullet_speed": 352.0, "points": 600 },
	22: { "speed": 2, "health": 3, "bullet_speed": 352.0, "points": 600 },
	23: { "speed": 2, "health": 2, "bullet_speed": 352.0, "points": 600 },
	24: { "speed": 2, "health": 3, "bullet_speed": 352.0, "points": 600 },
}

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	# Clamp type ID and apply stats
	tank_type_id = clampi(tank_type_id, 1, 24)
	var stats: Dictionary = TYPE_STATS.get(tank_type_id, TYPE_STATS[1])
	move_speed = SPEED_MAP.get(stats["speed"], 96.0)
	max_health = stats["health"]
	health = max_health
	bullet_speed = stats["bullet_speed"]
	points_value = stats["points"]
	special_weapon_type = CookieData.TYPE_WEAPON_MAP.get(tank_type_id, "none")
	special_weapon_level = CookieData.get_enemy_weapon_level(tank_type_id, GameManager.difficulty)
	if special_weapon_type == "rapid" or special_weapon_type == "fire" or special_weapon_type == "explosion" or special_weapon_type == "ap":
		max_bullets = 12
	current_direction = Vector2.DOWN
	_direction_change_timer = randf_range(1.0, 3.0)
	_shoot_cooldown = randf_range(0.5, 2.0)
	# Set collision layers
	set_collision_layer_value(1, false)
	set_collision_layer_value(4, true)  # enemy_tanks
	set_collision_mask_value(1, true)   # walls
	set_collision_mask_value(2, true)   # water
	set_collision_mask_value(3, false)  # player_tanks (one-directional: player blocks on enemy, not vice versa)
	set_collision_mask_value(5, true)   # player_bullets
	# Apply tank sprite by type ID
	_apply_type_look()
	if sprite:
		sprite.modulate = Color.WHITE
	# Apply addons for this tank type
	_apply_addons()
	_update_sprite_direction()

func _process(delta: float) -> void:
	super(delta)  # base: addons, damage flash, state-overlay frame tick
	_sync_frost_overlay()
	_tick_invulnerability(delta)

## Counts down the invulnerability an item gave, blinking the tank meanwhile:
## drawn one frame, gone the next, as the original drew a tank with under 3000
## ticks of it left (its DoDraw, 0x0049208c).
func _tick_invulnerability(delta: float) -> void:
	if _invulnerable_timer > 0.0:
		_invulnerable_timer -= delta
	if is_materializing:
		return  # still hidden behind its spawn burst
	if _invulnerable_timer > 0.0:
		visible = not visible
	elif not visible:
		visible = true

func is_invulnerable() -> bool:
	return _invulnerable_timer > 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and not is_materializing:
		visible = true  # never sit out a pause on a blank blink frame

## Show the frost wreath (Tank_T row 2) while the global freeze is active, hide
## it otherwise. Frame advance is handled by the base state-overlay tick.
func _sync_frost_overlay() -> void:
	if GameManager.enemies_frozen and not _frost_shown:
		show_state_overlay(BaseTank.get_freeze_frames())
		_frost_shown = true
	elif not GameManager.enemies_frozen and _frost_shown:
		hide_state_overlay()
		_frost_shown = false

func _physics_process(delta: float) -> void:
	_tick_afloat()
	if is_materializing:
		velocity = Vector2.ZERO
		return
	if is_flying:
		_update_flying(delta)
		return
	if GameManager.enemies_frozen:
		glide_while_held("players")
		return

	_ai_update(delta)
	if has_anti_ice:
		is_on_ice = false

	# Check if player tank is blocking the path ahead
	var player_blocking := _is_player_ahead()
	if player_blocking:
		# Attack the player: shoot rapidly
		if _shoot_cooldown <= 0:
			_fire_weapon(0.3, 0.6)
	var speed_factor := MINE_SLOW_FACTOR if is_mine_slowed else 1.0
	velocity = Vector2.ZERO if player_blocking else current_direction * move_speed * speed_factor

	# Players should block enemies logically, but enemies should not physically push players.
	var collided := move_and_slide()
	clamp_to_playfield()
	if collided and _turn_cooldown <= 0:
		if _attack_wall_timer > 0:
			pass  # Stay committed — keep shooting the wall
		else:
			_collision_cooldown = COLLISION_COOLDOWN_DURATION
			_turn_cooldown = TURN_COOLDOWN_DURATION
			_change_direction()

	# (Damage flash is handled centrally in BaseTank._process.)

func _is_player_ahead() -> bool:
	## Check if a player tank is blocking movement in the current direction.
	var lookahead := maxf(move_speed / float(Engine.physics_ticks_per_second), 2.0)
	return _opponent_ahead("players", current_direction, lookahead)

func _is_water_ahead(dir: Vector2) -> bool:
	## Check if water specifically blocks movement in the given direction.
	if not get_collision_mask_value(2):
		return false  # Has anti-water addon, water is passable
	if not test_move(global_transform, dir * HALF_TILE * 2):
		return false  # Not blocked at all
	# Temporarily disable water collision to check if water is the blocker
	set_collision_mask_value(2, false)
	var still_blocked := test_move(global_transform, dir * HALF_TILE * 2)
	set_collision_mask_value(2, true)
	return not still_blocked  # True = water was the only thing blocking

func _has_indestructible_ahead(dir: Vector2) -> bool:
	## Check if indestructible tiles (iron/steel, super block) are ahead in the given direction.
	## These can't be destroyed by enemy bullets, so we must go around.
	var game = get_tree().get_first_node_in_group("game")
	if not game or not game.has_method("get_level_manager"):
		return false
	var lm = game.get_level_manager()
	if not lm:
		return false
	# Check every tile directly ahead across the tank's body: 2 columns when it
	# sits on a tile corner, 3 when it is snapped to a half-tile.
	var ahead_center: Vector2 = global_position + dir * (HALF_TANK + HALF_TILE)
	var perp := Vector2(dir.y, dir.x)  # perpendicular direction
	for offset in BODY_LANE_OFFSETS:
		var check_pos: Vector2 = ahead_center + perp * offset
		var tile_pos: Vector2i = lm.world_to_tile(check_pos)
		if lm._fg_tile_data.has(tile_pos):
			var code: int = lm._fg_tile_data[tile_pos].get("code", 0)
			var cat := LevelData.get_tile_category(code)
			if cat == LevelData.TileCategory.IRON_BLOCK or cat == LevelData.TileCategory.SUPER_BLOCK:
				return true
	return false

func _is_impassable_ahead(dir: Vector2) -> bool:
	## Check if a direction is blocked by something the tank can never get through
	## (water without addon, iron block, super block).
	if _is_water_ahead(dir):
		return true
	if _has_indestructible_ahead(dir):
		return true
	return false

func _try_direct_eagle_attack() -> bool:
	## When very close to the eagle, check if we're aligned on an axis.
	## If so, face the eagle directly and shoot — highest priority action.
	var eagle = get_tree().get_first_node_in_group("eagle")
	if not eagle:
		return false
	var diff: Vector2 = eagle.global_position - global_position
	var dist: float = diff.length()
	if dist > TANK_SIZE * 3:  # Only within ~3 tank-widths (~192px)
		return false

	# Determine which axis we're aligned on (within half-tank tolerance)
	var face_dir := Vector2.ZERO
	if absf(diff.x) < HALF_TANK:
		# Vertically aligned — eagle is above or below
		face_dir = Vector2.DOWN if diff.y > 0 else Vector2.UP
	elif absf(diff.y) < HALF_TANK:
		# Horizontally aligned — eagle is left or right
		face_dir = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT

	if face_dir == Vector2.ZERO:
		return false  # Not aligned on either axis

	# Face the eagle and shoot
	if current_direction != face_dir:
		current_direction = face_dir
		_snap_and_update()
	# Rapid fire at the eagle
	if _shoot_cooldown <= 0:
		_fire_weapon(0.1, 0.25)
	return true

func _ai_update(delta: float) -> void:
	_alive_time += delta
	_direction_change_timer -= delta
	_shoot_cooldown -= delta
	_collision_cooldown = maxf(_collision_cooldown - delta, 0.0)
	_turn_cooldown = maxf(_turn_cooldown - delta, 0.0)
	_water_avoid_timer = maxf(_water_avoid_timer - delta, 0.0)
	if _water_avoid_timer <= 0:
		_water_avoid_dir = Vector2.ZERO

	# Check proximity to eagle
	_near_eagle = _check_near_eagle()

	# --- HIGHEST PRIORITY: Direct eagle attack when aligned ---
	if _near_eagle and _try_direct_eagle_attack():
		_attack_wall_timer = 0.0  # Cancel wall attack if we can hit the eagle
		return

	# --- Wall attack mode: keep shooting until the wall breaks or timer expires ---
	if _attack_wall_timer > 0:
		_attack_wall_timer -= delta
		# Check if the wall is now cleared — if so, advance through it
		if not test_move(global_transform, _attack_wall_dir * HALF_TILE * 2):
			_attack_wall_timer = 0.0
			current_direction = _attack_wall_dir
			_snap_and_update()
			_attack_wall_dir = Vector2.ZERO
			return
		# Timer expired but wall still there — give up, try another way
		if _attack_wall_timer <= 0:
			_attack_wall_dir = Vector2.ZERO
			_change_direction()
			return
		# Keep shooting rapidly at the wall
		if _shoot_cooldown <= 0:
			_fire_weapon(0.15, 0.3)
		return  # Skip normal AI while attacking wall

	# Periodically reconsider direction
	if _direction_change_timer <= 0:
		# Near eagle: re-evaluate faster to stay locked on target
		_direction_change_timer = randf_range(0.5, 1.5) if _near_eagle else randf_range(2.0, 4.0)
		_change_direction()

	if _shoot_cooldown <= 0:
		# Near eagle: shoot much faster to break through protective walls
		if _near_eagle:
			_fire_weapon(0.15, 0.4)
		else:
			_fire_weapon(0.5, 2.0)

	# Near eagle: aggressively face toward it every frame (high chance)
	if _near_eagle and _collision_cooldown <= 0:
		if randf() < 0.05:  # ~3 times/sec at 60fps
			_bias_toward_eagle()
	elif _collision_cooldown <= 0:
		# Normal eagle correction
		var eagle_bias: float = 0.02 if _alive_time < INITIAL_DOWN_DURATION else 0.01
		if randf() < eagle_bias:
			_bias_toward_eagle()

func _check_near_eagle() -> bool:
	var eagle = get_tree().get_first_node_in_group("eagle")
	if not eagle:
		return false
	return global_position.distance_to(eagle.global_position) < EAGLE_ATTACK_RANGE

func _get_clear_dirs(exclude: Vector2 = Vector2.ZERO) -> Array[Vector2]:
	## Return all 4 directions that are physically passable (1 tile ahead).
	## Optionally exclude one direction (typically the current blocked one).
	var result: Array[Vector2] = []
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		if d == exclude:
			continue
		if not test_move(global_transform, d * HALF_TILE * 2):
			result.append(d)
	return result

func _get_shootable_dirs(exclude: Vector2 = Vector2.ZERO) -> Array[Vector2]:
	## Return directions blocked by a BREAKABLE wall (not water, iron, or super block).
	var result: Array[Vector2] = []
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		if d == exclude:
			continue
		# Must be blocked, and NOT by something impassable
		if test_move(global_transform, d * HALF_TILE * 2) and not _is_impassable_ahead(d):
			result.append(d)
	return result

func _start_wall_attack(dir: Vector2) -> void:
	## Face a wall and shoot it to break through.
	_attack_wall_dir = dir
	_attack_wall_timer = ATTACK_WALL_DURATION
	current_direction = dir
	_snap_and_update()

func _change_direction() -> void:
	# During initial spawn phase, prefer DOWN if clear
	if _alive_time < INITIAL_DOWN_DURATION and current_direction != Vector2.DOWN:
		if not test_move(global_transform, Vector2.DOWN * HALF_TILE * 2):
			current_direction = Vector2.DOWN
			_snap_and_update()
			return

	# Get clear directions excluding current (we want to change)
	var clear_dirs := _get_clear_dirs(current_direction)
	if clear_dirs.is_empty():
		clear_dirs = _get_clear_dirs()

	# Remove the water-avoided direction while the timer is active
	if _water_avoid_timer > 0 and _water_avoid_dir != Vector2.ZERO:
		clear_dirs.erase(_water_avoid_dir)

	# Get primary & secondary eagle directions
	var eagle_dirs := _get_eagle_directions()
	var eagle_primary: Vector2 = eagle_dirs[0]
	var eagle_secondary: Vector2 = eagle_dirs[1]

	# Check if eagle directions are blocked by impassable obstacles (water, iron, super block)
	var primary_impassable := _is_impassable_ahead(eagle_primary)
	var secondary_impassable := eagle_secondary != Vector2.ZERO and _is_impassable_ahead(eagle_secondary)

	# If impassable obstacle blocks the eagle path, remember it and commit to going around
	if primary_impassable and _water_avoid_timer <= 0:
		_water_avoid_dir = eagle_primary
		_water_avoid_timer = WATER_AVOID_DURATION

	# Near eagle: 95% seek eagle aggressively; Normal: 75%
	var seek_chance: float = 0.95 if _near_eagle else 0.75
	if randf() < seek_chance:
		# Try primary eagle direction if clear (skip if impassable)
		if not primary_impassable and eagle_primary in clear_dirs:
			current_direction = eagle_primary
			_snap_and_update()
			return
		# Try secondary eagle direction if clear (skip if impassable)
		if not secondary_impassable and eagle_secondary != Vector2.ZERO and eagle_secondary in clear_dirs:
			current_direction = eagle_secondary
			_snap_and_update()
			return

		# Eagle directions not clear — check if we can SHOOT through a breakable wall
		var shootable := _get_shootable_dirs()
		# Prefer shooting toward eagle direction, then perpendicular toward eagle
		if not primary_impassable and eagle_primary in shootable:
			_start_wall_attack(eagle_primary)
			return
		if not secondary_impassable and eagle_secondary != Vector2.ZERO and eagle_secondary in shootable:
			_start_wall_attack(eagle_secondary)
			return
		# Shoot any perpendicular wall (not away from eagle)
		for d in shootable:
			if d != -eagle_primary:
				_start_wall_attack(d)
				return

		# No shootable walls — go perpendicular if any clear direction exists
		var perpendicular: Array[Vector2] = []
		for d in clear_dirs:
			if d != -eagle_primary:  # Avoid going directly away from eagle
				perpendicular.append(d)
		if not perpendicular.is_empty():
			current_direction = perpendicular[randi() % perpendicular.size()]
			_snap_and_update()
			return

	# Fallback: pick any clear direction, or if completely stuck try shooting any wall
	if not clear_dirs.is_empty():
		clear_dirs.shuffle()
		current_direction = clear_dirs[0]
		_snap_and_update()
	else:
		# Completely boxed in by walls — shoot one to escape
		var shootable := _get_shootable_dirs()
		if not shootable.is_empty():
			_start_wall_attack(shootable[randi() % shootable.size()])
		# else: truly stuck (surrounded by water/steel) — do nothing

func _snap_and_update() -> void:
	# Snap to grid when changing direction
	if current_direction.x != 0:
		position.y = round(position.y / HALF_TILE) * HALF_TILE
	else:
		position.x = round(position.x / HALF_TILE) * HALF_TILE
	_update_sprite_direction()

func _get_eagle_directions() -> Array:
	## Returns [primary, secondary] directions toward the eagle.
	## Primary = axis with larger distance, Secondary = other axis.
	var eagle = get_tree().get_first_node_in_group("eagle")
	if not eagle:
		return [Vector2.DOWN, Vector2.ZERO]
	var diff: Vector2 = eagle.global_position - global_position
	var primary: Vector2
	var secondary: Vector2
	if absf(diff.y) > absf(diff.x):
		primary = Vector2.DOWN if diff.y > 0 else Vector2.UP
		if absf(diff.x) > TILE_SIZE:  # Only suggest secondary if meaningful distance
			secondary = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
		else:
			secondary = Vector2.ZERO
	else:
		primary = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
		if absf(diff.y) > TILE_SIZE:
			secondary = Vector2.DOWN if diff.y > 0 else Vector2.UP
		else:
			secondary = Vector2.ZERO
	return [primary, secondary]

func _get_eagle_direction() -> Vector2:
	return _get_eagle_directions()[0]

func _bias_toward_eagle() -> void:
	var eagle_dirs := _get_eagle_directions()
	# Try primary, then secondary — skip impassable directions (water, iron, super)
	for dir in eagle_dirs:
		if dir == Vector2.ZERO or dir == current_direction:
			continue
		if _water_avoid_timer > 0 and dir == _water_avoid_dir:
			continue  # Don't bias into obstacle we're trying to go around
		if _is_impassable_ahead(dir):
			continue  # Don't turn toward impassable obstacles
		if not test_move(global_transform, dir * HALF_TILE * 2):
			current_direction = dir
			_snap_and_update()
			return

func _fire_weapon(regular_min: float, regular_max: float) -> void:
	if _has_rapid_special() and randf() < SPECIAL_FIRE_CHANCE:
		if _shoot_special_rapid():
			var config: Dictionary = CookieData.get_weapon_fire_config("rapid", special_weapon_level)
			_shoot_cooldown = config.get("cooldown", regular_min)
			return

	if _has_fire_special() and randf() < ENEMY_FIRE_CHANCE:
		if _shoot_special_fire():
			# Long, self-paced gap — NOT the player's rapid fire cooldown.
			_shoot_cooldown = randf_range(ENEMY_FIRE_COOLDOWN_MIN, ENEMY_FIRE_COOLDOWN_MAX)
			return

	if _has_explosion_special() and randf() < ENEMY_EXPLOSION_CHANCE:
		if _shoot_special_explosion():
			_shoot_cooldown = randf_range(ENEMY_EXPLOSION_COOLDOWN_MIN, ENEMY_EXPLOSION_COOLDOWN_MAX)
			return

	if _has_mine_special() and randf() < ENEMY_MINE_CHANCE:
		if _lay_mine_special():
			_shoot_cooldown = randf_range(ENEMY_MINE_COOLDOWN_MIN, ENEMY_MINE_COOLDOWN_MAX)
			return

	if _has_ap_special() and randf() < ENEMY_AP_CHANCE:
		if _shoot_special_ap():
			_shoot_cooldown = randf_range(ENEMY_AP_COOLDOWN_MIN, ENEMY_AP_COOLDOWN_MAX)
			return

	if not can_shoot or active_bullets >= max_bullets:
		return

	_set_shoot_cooldown_wait_time(ENEMY_REGULAR_FIRE_COOLDOWN)
	super.shoot()
	_shoot_cooldown = randf_range(regular_min, regular_max)

func _has_rapid_special() -> bool:
	return special_weapon_type == "rapid"

func _has_fire_special() -> bool:
	return special_weapon_type == "fire"

func _has_explosion_special() -> bool:
	return special_weapon_type == "explosion"

func _has_mine_special() -> bool:
	return special_weapon_type == "mine"

func _lay_mine_special() -> bool:
	if not _place_mine(mini(special_weapon_level, ENEMY_MINE_MAX_LEVEL)):
		return false
	# The original sounded every special weapon, enemies' included; only the
	# plain gun was silent for them.
	SoundManager.play(&"lay_mine")
	return true

func _has_ap_special() -> bool:
	return special_weapon_type == "ap"

func _shoot_special_ap() -> bool:
	if not _has_ap_special() or not can_shoot:
		return false
	var config: Dictionary = CookieData.get_weapon_fire_config("ap", special_weapon_level)
	if config.is_empty():
		return false
	if active_ap_bullets >= int(config.get("max_in_flight", 2)):
		return false
	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.6))
	_begin_shot()
	SoundManager.play(&"fire_ap")
	_spawn_ap_bullet(config)
	return true

## AP shell stripped this enemy's moon shield: remove it (no invuln grace for enemies).
func break_moon_shield_grace() -> void:
	if has_moon_shield:
		_remove_addon(ADDON_MOON_SHIELD)

func _shoot_special_explosion() -> bool:
	if not _has_explosion_special() or not can_shoot:
		return false
	var config: Dictionary = CookieData.get_weapon_fire_config("explosion", special_weapon_level)
	if config.is_empty():
		return false
	if active_explosion_bullets >= int(config.get("max_in_flight", 2)):
		return false
	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.45))
	_begin_shot()
	SoundManager.play(&"fire_explosion")
	_spawn_explosion_bullet(config)
	return true

func _shoot_special_fire() -> bool:
	if not _has_fire_special() or not can_shoot:
		return false
	var config: Dictionary = CookieData.get_weapon_fire_config("fire", special_weapon_level)
	if config.is_empty():
		return false
	if active_fire_bullets >= int(config.get("max_in_flight", 3)):
		return false
	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.27))
	_begin_shot()
	SoundManager.play(&"fire_fire")
	_spawn_fire_bullet(config)
	return true

func _shoot_special_rapid() -> bool:
	if not _has_rapid_special() or not can_shoot or active_bullets >= max_bullets:
		return false

	var config: Dictionary = CookieData.get_weapon_fire_config("rapid", special_weapon_level)
	if config.is_empty():
		return false

	var fire_rows: Array = config.get("rows", [FIRE_ROW_MID])
	var speed_multiplier: float = config.get("speed_multiplier", 1.0)
	var row_offset: float = fire_rows[_rapid_special_fire_step % fire_rows.size()]
	_rapid_special_fire_step = (_rapid_special_fire_step + 1) % fire_rows.size()

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.4))
	_begin_shot()
	SoundManager.play(&"fire_rapid")
	_spawn_single_row_bullet(row_offset, bullet_speed * speed_multiplier, "rapid")
	return true

func _apply_addons() -> void:
	for addon_name in TYPE_ADDONS.get(tank_type_id, []):
		_add_addon(addon_name)

func _add_addon(addon_name: String) -> void:
	addons.append(addon_name)
	# Add visual overlay (prefer a 4-frame animation for anti-water / memory-save).
	var frames: Array = ThemeManager.get_addon_frames(addon_name)
	var tex: Texture2D = frames[0] if not frames.is_empty() else ThemeManager.get_addon_texture(addon_name)
	if tex:
		var cfg: Dictionary = ADDON_CONFIG.get(addon_name, { "scale": 1.0 })
		var addon_sprite := Sprite2D.new()
		tag_addon_sprite(addon_sprite, addon_name)
		addon_sprite.texture = tex
		addon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp, no magenta-key blur
		var tex_size := tex.get_size()
		var addon_size: float = TANK_SIZE * cfg["scale"]
		addon_sprite.scale = Vector2(addon_size / tex_size.x, addon_size / tex_size.y)
		add_child(addon_sprite)
		if not frames.is_empty():
			register_animated_addon(addon_sprite, frames)
		# Draw order via sibling order (all at z 0), back -> front:
		# other addons -> moon shield -> tank body (on top, fully visible).
		var sprite_idx := sprite.get_index() if sprite else get_child_count() - 1
		if addon_name == ADDON_MOON_SHIELD:
			move_child(addon_sprite, sprite_idx)  # just behind the tank body
			_shield_sprite = addon_sprite
		else:
			move_child(addon_sprite, 0)  # behind everything
		_addon_sprites.append(addon_sprite)
		_layout_addons()
	# Apply gameplay effects
	match addon_name:
		ADDON_MOON_SHIELD:
			has_moon_shield = true
		ADDON_ANTI_WATER:
			set_collision_mask_value(2, false)  # Can cross water
		ADDON_ANTI_ICE:
			has_anti_ice = true

## Puts [param addon_name] on in place of whatever add-on the tank wore: the
## original gave a tank one add-on slot.
func set_addon(addon_name: String) -> void:
	for old in addons.duplicate():
		_remove_addon(old)
	_add_addon(addon_name)

## Check if a bullet from the given direction is blocked by moon-shield.
## Returns true if the bullet hits the tank's FRONT and the shield blocks it.
func is_bullet_blocked(bullet_direction: Vector2) -> bool:
	if not has_moon_shield:
		return false
	# Bullet hits front when it travels opposite to tank's facing direction
	# dot < 0 means bullet is coming toward the front half of the tank
	return bullet_direction.dot(current_direction) < 0

## An enemy's gun level is its special-weapon level.
func get_gun_level() -> int:
	return special_weapon_level

func get_addon_names() -> Array:
	return addons.duplicate()

func lose_addon(addon_name: String) -> void:
	if addon_name in addons:
		_remove_addon(addon_name)

## True if this tank may take a [param cookie_type] item: its own gun's
## ("Caisson" for the plain gun); an upgrade or add-on if it is the stronger
## tank of its pair (the even ids, the original's odd types); and those and the
## specials while it wears memory-save. Never another gun's, nor a score item.
func can_take_cookie(cookie_type: int) -> bool:
	if is_materializing or is_flying or health <= 0 or is_queued_for_deletion():
		return false
	var own_gun: int = CookieData.WEAPON_TO_COOKIE.get(special_weapon_type, CookieData.CookieType.BULLET_REFILL)
	if cookie_type == own_gun:
		return true
	var memory := ADDON_MEMORY_SAVE in addons
	if cookie_type in UPGRADE_ITEMS:
		return memory or tank_type_id % 2 == 0
	return memory and cookie_type in SPECIAL_ITEMS

## Each item adds its 1000 ticks to whatever is left.
func activate_pickup_invulnerability() -> void:
	_invulnerable_timer += PICKUP_INVULNERABILITY

## "Armor Up": one more HP, up to 8 ([param points] at once for "MAX Caisson
## Armor"). max_health stays the HP it started with: the drop rules go by that.
func item_hp_up(points: int = 1) -> void:
	health = mini(health + points, maxi(MAX_ITEM_HP, health))

## "Power Up": the special weapon one level up, to 3.
func item_gun_up() -> void:
	special_weapon_level = mini(special_weapon_level + 1, maxi(MAX_ITEM_GUN, special_weapon_level))

## "Speed Up": one speed step faster.
func item_speed_up() -> void:
	move_speed = minf(move_speed + ITEM_SPEED_STEP, maxf(ITEM_MAX_SPEED, move_speed))

## MAX, taken by any enemy, for each on the field: the stronger type of its
## pair, a speed step, a gun level, and memory-save if it wore no add-on. Its
## HP stays as it is.
func item_max_up() -> void:
	promote_type()
	clear_mine_slow()
	item_speed_up()
	item_gun_up()
	if addons.is_empty():
		_add_addon(ADDON_MEMORY_SAVE)

## "MAX Caisson Armor", taken by any enemy, for each on the field: the stronger
## type of its pair and two more HP (and, in the original, a pack of ammo).
func item_caisson_max() -> void:
	promote_type()
	clear_mine_slow()
	item_hp_up(2)

## MAX and "MAX Caisson Armor" make the weaker tank of each pair (the odd ids,
## the original's even types) the stronger one: its look, and the items it may
## take from then on.
func promote_type() -> void:
	if tank_type_id % 2 == 0:
		return
	tank_type_id += 1
	_apply_type_look()

## The tank's picture for its type, from the theme.
func _apply_type_look() -> void:
	if not sprite:
		return
	var theme_tex := ThemeManager.get_tank_texture("e%d" % tank_type_id)
	if theme_tex:
		sprite.texture = theme_tex
	# Dynamically scale sprite to fit 64x64 (2x2 tile) tank size
	var tex_size := sprite.texture.get_size()
	sprite.scale = Vector2(TANK_SIZE / tex_size.x, TANK_SIZE / tex_size.y)

func take_damage(bullet_direction: Vector2 = Vector2.ZERO) -> void:
	var attacker := hit_by
	hit_by = -1
	if health <= 0:
		return  # already destroyed this frame: nothing more to take
	if is_invulnerable():
		return  # the original's Damage ignored an invulnerable tank
	health -= 1
	_hits_taken += 1
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	# Turn to face the attacker and retaliate (skip if frozen, including the debug
	# freeze, which stops this tank from processing)
	if bullet_direction != Vector2.ZERO and health > 0 and not GameManager.enemies_frozen and can_process():
		var face_dir := -bullet_direction  # face toward the shooter
		current_direction = face_dir
		_snap_and_update()
		_shoot_cooldown = 0.0  # shoot immediately next frame
	# Addon drop on 2nd hit: only if tank started with hp>2 and has addon(s)
	if _hits_taken == 2 and max_health > 2 and not addons.is_empty():
		_drop_addon_cookie()
	elif health > 0 and not is_flying:
		_lose_an_upgrade()
	if attacker >= 0:
		GameManager.note_hit(attacker)
	if health <= 0:
		killed_by = attacker
		destroy()
	else:
		SoundManager.play(&"tank_hit")

func destroy() -> void:
	if is_queued_for_deletion():
		return  # a bomb reaching a tank a shell has just finished: one kill
	Events.enemy_destroyed.emit(self, points_value)
	# Death drop: any tank with max_health>1 has 60% chance to drop a cookie
	if max_health > 1:
		var cookie_type: int = CookieData.roll_death_drop(tank_type_id)
		if cookie_type >= 0:
			_spawn_cookie_at_position(cookie_type)
	_spawn_explosion()
	queue_free()

## A hit it survives, on the ground, knocks one upgrade the tank has above its
## type's own back out, flung across the field: a gun level first ("Power Up"),
## else a speed step ("Speed Up"). So what an enemy took can be won back
## (Tank.exe's Damage, 0x00492763).
func _lose_an_upgrade() -> void:
	if special_weapon_level > CookieData.get_enemy_weapon_level(tank_type_id, GameManager.difficulty):
		special_weapon_level -= 1
		_spawn_cookie_at_position(CookieData.CookieType.WEAPONS_UP)
	elif move_speed > _type_speed():
		move_speed = maxf(move_speed - ITEM_SPEED_STEP, _type_speed())
		_spawn_cookie_at_position(CookieData.CookieType.SPEED_UP)

## Its type's own speed.
func _type_speed() -> float:
	return SPEED_MAP.get(TYPE_STATS.get(tank_type_id, TYPE_STATS[1])["speed"], 96.0)

func _drop_addon_cookie() -> void:
	if addons.is_empty():
		return
	var addon_name: String = addons[0]
	var cookie_type: int = CookieData.ADDON_TO_COOKIE.get(addon_name, -1)
	if cookie_type == -1:
		return
	_remove_addon(addon_name)
	_spawn_cookie_at_position(cookie_type)

func _remove_addon(addon_name: String) -> void:
	addons.erase(addon_name)
	match addon_name:
		ADDON_MOON_SHIELD:
			has_moon_shield = false
			_shield_sprite = null
		ADDON_ANTI_WATER:
			set_collision_mask_value(2, true)  # Re-enable water collision
			_stay_afloat()
		ADDON_ANTI_ICE:
			has_anti_ice = false
	# Remove that add-on's own sprite (tagged by tag_addon_sprite).
	for spr in _addon_sprites.duplicate():
		if is_instance_valid(spr) and spr.get_meta(&"addon", "") == addon_name:
			_addon_sprites.erase(spr)
			spr.queue_free()
			break

func _stay_afloat() -> void:
	var lm := _get_level_manager()
	if lm == null:
		return
	for body in lm.water_bodies_under(global_position):
		if body not in _afloat_on:
			add_collision_exception_with(body)
			_afloat_on.append(body)

## Lets the water the tank has driven off block it again.
func _tick_afloat() -> void:
	if _afloat_on.is_empty():
		return
	var lm := _get_level_manager()
	var under: Array = lm.water_bodies_under(global_position) if lm else []
	for body in _afloat_on.duplicate():
		if is_instance_valid(body) and body in under:
			continue
		if is_instance_valid(body):
			remove_collision_exception_with(body)
		_afloat_on.erase(body)

func _spawn_cookie_at_position(cookie_type: int) -> void:
	var cookie_scene := preload("res://scenes/powerups/powerup.tscn")
	var cookie: Node2D = cookie_scene.instantiate()
	# Random position on the playfield (40x30 grid, offset 160,16)
	# Inset by 32px (half cookie size) so the 64px cookie stays fully inside
	var spawn_pos := Vector2(
		randf_range(160 + 32, 160 + 40 * 32 - 32),
		randf_range(16 + 32, 16 + 30 * 32 - 32)
	).snapped(Vector2(32, 32))
	# Check if any player is at the spawn position (overlapping)
	var delay: float = 0.0
	var players := get_tree().get_nodes_in_group("players")
	for player in players:
		if player is PlayerTank and is_instance_valid(player):
			if spawn_pos.distance_to(player.global_position) < 48.0:
				delay = 1.0
				break
	cookie.setup(cookie_type, delay, global_position)
	cookie.global_position = spawn_pos
	var container = get_tree().get_first_node_in_group("powerups_container")
	if container:
		container.add_child(cookie)
	else:
		get_tree().current_scene.add_child(cookie)
