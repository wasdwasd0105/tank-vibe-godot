class_name EnemyTank
extends BaseTank

# Tank type ID (1-24) matching tank_<id>.png sprites and Stage.dat EnemyCount values
@export var tank_type_id: int = 1
@export var points_value: int = 100

var _direction_change_timer: float = 0.0
var _shoot_cooldown: float = 0.0
var _hits_taken: int = 0
var _damage_flash_timer: float = 0.0
var _alive_time: float = 0.0  # Time since spawn (for initial downward push)
var _collision_cooldown: float = 0.0  # Prevents eagle bias right after a collision
var _near_eagle: bool = false  # True when within attack range of eagle
var _water_avoid_dir: Vector2 = Vector2.ZERO  # Direction blocked by water (avoid it)
var _water_avoid_timer: float = 0.0  # How long to avoid the water-blocked direction
var _attack_wall_dir: Vector2 = Vector2.ZERO  # Direction of wall we're shooting to break
var _attack_wall_timer: float = 0.0  # Time left to keep attacking a wall
var _turn_cooldown: float = 0.0  # Prevents rapid direction changes after collision
const DAMAGE_FLASH_DURATION: float = 0.15
const TURN_COOLDOWN_DURATION: float = 0.6  # Minimum seconds between collision-triggered turns
const INITIAL_DOWN_DURATION: float = 2.0  # Move DOWN for first 2 seconds after spawn
const COLLISION_COOLDOWN_DURATION: float = 1.0  # Seconds to suppress eagle bias after collision
const EAGLE_ATTACK_RANGE: float = 192.0  # ~6 tiles — enter attack mode
const WATER_AVOID_DURATION: float = 4.0  # Seconds to commit to going around water
const ATTACK_WALL_DURATION: float = 3.0  # Seconds to commit to shooting a wall

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

var addons: Array = []
var has_moon_shield: bool = false
var has_anti_ice: bool = false
var _shield_sprite: Sprite2D = null  # Reference for front-positioned shield
var _addon_sprites: Array = []  # All addon Sprite2D nodes for rotation
const SHIELD_FRONT_OFFSET: float = 5.0  # Pixels from center toward front

# Per-addon size multiplier (relative to TANK_SIZE) and front offset override
const ADDON_CONFIG: Dictionary = {
	"moon-shield":  { "scale": 0.9, "offset": 5.0 },
	"anti-water":   { "scale": 1.0, "offset": 5.0 },
	"anti-ice":     { "scale": 1.0, "offset": 5.0 },
	"memory-save":  { "scale": 1.0, "offset": 5.0 },
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
	if sprite:
		var enemy_key := "e%d" % tank_type_id
		var theme_tex := ThemeManager.get_tank_texture(enemy_key)
		if theme_tex:
			sprite.texture = theme_tex
		# Dynamically scale sprite to fit 64x64 (2x2 tile) tank size
		var tex_size := sprite.texture.get_size()
		sprite.scale = Vector2(TANK_SIZE / tex_size.x, TANK_SIZE / tex_size.y)
		sprite.modulate = Color.WHITE
	# Apply addons for this tank type
	_apply_addons()
	_update_sprite_direction()

func _physics_process(delta: float) -> void:
	if GameManager.enemies_frozen:
		velocity = Vector2.ZERO
		return

	_ai_update(delta)
	if has_anti_ice:
		is_on_ice = false

	# Check if player tank is blocking the path ahead
	var player_blocking := _is_player_ahead()
	if player_blocking:
		# Attack the player: shoot rapidly
		if _shoot_cooldown <= 0:
			_shoot_cooldown = randf_range(0.3, 0.6)
			shoot()
	velocity = current_direction * move_speed

	# Temporarily enable player mask so move_and_slide finds exact contact point
	if player_blocking:
		set_collision_mask_value(3, true)
	var collided := move_and_slide()
	if player_blocking:
		set_collision_mask_value(3, false)
	clamp_to_playfield()
	if collided and _turn_cooldown <= 0:
		if _attack_wall_timer > 0:
			pass  # Stay committed — keep shooting the wall
		else:
			_collision_cooldown = COLLISION_COOLDOWN_DURATION
			_turn_cooldown = TURN_COOLDOWN_DURATION
			_change_direction()

	# Damage flash effect (any tank that was recently hit)
	if _damage_flash_timer > 0:
		_damage_flash_timer -= delta
		if sprite:
			if fmod(_damage_flash_timer, 0.1) < 0.05:
				sprite.modulate = Color.RED
			else:
				sprite.modulate = Color.WHITE
		if _damage_flash_timer <= 0 and sprite:
			sprite.modulate = Color.WHITE

func _is_player_ahead() -> bool:
	## Check if a player tank is blocking movement in the current direction.
	## Temporarily enables the player mask for test_move, then disables it.
	set_collision_mask_value(3, true)
	var blocked := test_move(global_transform, current_direction * HALF_TILE * 2)
	set_collision_mask_value(3, false)
	if not blocked:
		return false
	# Check if the blockage is specifically a player (not a wall)
	var still_blocked := test_move(global_transform, current_direction * HALF_TILE * 2)
	return not still_blocked  # True = player was the only thing blocking

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
	# Check the 2 tiles directly ahead of the tank (tank is 2x2, so 2 tiles wide)
	var ahead_center: Vector2 = global_position + dir * (HALF_TANK + HALF_TILE)
	var perp := Vector2(dir.y, dir.x)  # perpendicular direction
	for offset in [-0.5, 0.5]:  # Check both lanes of the 2-tile-wide tank
		var check_pos: Vector2 = ahead_center + perp * (HALF_TILE * offset * 2)
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
		_shoot_cooldown = randf_range(0.1, 0.25)
		shoot()
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
			_shoot_cooldown = randf_range(0.15, 0.3)
			shoot()
		return  # Skip normal AI while attacking wall

	# Periodically reconsider direction
	if _direction_change_timer <= 0:
		# Near eagle: re-evaluate faster to stay locked on target
		_direction_change_timer = randf_range(0.5, 1.5) if _near_eagle else randf_range(2.0, 4.0)
		_change_direction()

	if _shoot_cooldown <= 0:
		# Near eagle: shoot much faster to break through protective walls
		_shoot_cooldown = randf_range(0.15, 0.4) if _near_eagle else randf_range(0.5, 2.0)
		shoot()

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

func _update_sprite_direction() -> void:
	super._update_sprite_direction()
	_update_addon_directions()

func _update_addon_directions() -> void:
	# Compute rotation from facing direction
	var rot := 0.0
	if current_direction == Vector2.DOWN:
		rot = PI
	elif current_direction == Vector2.LEFT:
		rot = -PI / 2
	elif current_direction == Vector2.RIGHT:
		rot = PI / 2
	# Rotate all addon sprites to match tank direction
	for addon_sprite in _addon_sprites:
		if addon_sprite and is_instance_valid(addon_sprite):
			addon_sprite.rotation = rot
	# Moon-shield also has a front offset
	if _shield_sprite and is_instance_valid(_shield_sprite):
		var offset: float = ADDON_CONFIG.get(ADDON_MOON_SHIELD, {}).get("offset", SHIELD_FRONT_OFFSET)
		_shield_sprite.position = current_direction * offset

func _apply_addons() -> void:
	if not TYPE_ADDONS.has(tank_type_id):
		return
	addons = TYPE_ADDONS[tank_type_id].duplicate()
	for addon_name in addons:
		# Add visual overlay
		var tex := ThemeManager.get_addon_texture(addon_name)
		if tex:
			var cfg: Dictionary = ADDON_CONFIG.get(addon_name, { "scale": 1.0, "offset": 0.0 })
			var addon_sprite := Sprite2D.new()
			addon_sprite.texture = tex
			var tex_size := tex.get_size()
			var addon_size: float = TANK_SIZE * cfg["scale"]
			addon_sprite.scale = Vector2(addon_size / tex_size.x, addon_size / tex_size.y)
			add_child(addon_sprite)
			move_child(addon_sprite, 0)  # Insert before Sprite2D so addon draws behind tank body
			_addon_sprites.append(addon_sprite)
			if addon_name == ADDON_MOON_SHIELD:
				_shield_sprite = addon_sprite
		# Apply gameplay effects
		match addon_name:
			ADDON_MOON_SHIELD:
				has_moon_shield = true
			ADDON_ANTI_WATER:
				set_collision_mask_value(2, false)  # Can cross water
			ADDON_ANTI_ICE:
				has_anti_ice = true

## Check if a bullet from the given direction is blocked by moon-shield.
## Returns true if the bullet hits the tank's FRONT and the shield blocks it.
func is_bullet_blocked(bullet_direction: Vector2) -> bool:
	if not has_moon_shield:
		return false
	# Bullet hits front when it travels opposite to tank's facing direction
	# dot < 0 means bullet is coming toward the front half of the tank
	return bullet_direction.dot(current_direction) < 0

func take_damage(bullet_direction: Vector2 = Vector2.ZERO) -> void:
	health -= 1
	_hits_taken += 1
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	# Turn to face the attacker and retaliate (skip if frozen)
	if bullet_direction != Vector2.ZERO and health > 0 and not GameManager.enemies_frozen:
		var face_dir := -bullet_direction  # face toward the shooter
		current_direction = face_dir
		_snap_and_update()
		_shoot_cooldown = 0.0  # shoot immediately next frame
	# Addon drop on 2nd hit: only if tank started with hp>2 and has addon(s)
	if _hits_taken == 2 and max_health > 2 and not addons.is_empty():
		_drop_addon_cookie()
	if health <= 0:
		destroy()

func destroy() -> void:
	Events.enemy_destroyed.emit(self, points_value)
	# Death drop: any tank with max_health>1 has 60% chance to drop a cookie
	if max_health > 1:
		var cookie_type: int = CookieData.roll_death_drop(tank_type_id)
		if cookie_type >= 0:
			_spawn_cookie_at_position(cookie_type)
	_spawn_explosion()
	queue_free()

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
			if _shield_sprite and is_instance_valid(_shield_sprite):
				_shield_sprite.queue_free()
				_addon_sprites.erase(_shield_sprite)
				_shield_sprite = null
		ADDON_ANTI_WATER:
			set_collision_mask_value(2, true)  # Re-enable water collision
		ADDON_ANTI_ICE:
			has_anti_ice = false
	# Remove the addon sprite
	if not _addon_sprites.is_empty():
		var spr: Sprite2D = _addon_sprites.pop_back()
		if spr and is_instance_valid(spr):
			spr.queue_free()

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
