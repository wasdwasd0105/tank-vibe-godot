class_name EnemyTank
extends BaseTank

# Tank type ID (1-24) matching tank_<id>.png sprites and Stage.dat EnemyCount values
@export var tank_type_id: int = 1
@export var points_value: int = 100

var _direction_change_timer: float = 0.0
var _shoot_cooldown: float = 0.0
var _hits_taken: int = 0
var _damage_flash_timer: float = 0.0
const DAMAGE_FLASH_DURATION: float = 0.15

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
	set_collision_mask_value(3, true)   # player_tanks
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
	velocity = current_direction * move_speed

	var collided := move_and_slide()
	if collided:
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

func _ai_update(delta: float) -> void:
	_direction_change_timer -= delta
	_shoot_cooldown -= delta

	if _direction_change_timer <= 0:
		_direction_change_timer = randf_range(1.0, 3.0)
		if randf() < 0.4:
			_change_direction()

	if _shoot_cooldown <= 0:
		_shoot_cooldown = randf_range(0.5, 2.0)
		shoot()

	# Occasional bias toward eagle
	if randf() < 0.003:
		_bias_toward_eagle()

func _change_direction() -> void:
	var dirs := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	dirs.erase(current_direction)
	current_direction = dirs[randi() % dirs.size()]
	# Snap to grid when changing direction
	if current_direction.x != 0:
		position.y = round(position.y / HALF_TILE) * HALF_TILE
	else:
		position.x = round(position.x / HALF_TILE) * HALF_TILE
	_update_sprite_direction()

func _bias_toward_eagle() -> void:
	var eagle = get_tree().get_first_node_in_group("eagle")
	if not eagle:
		return
	var diff: Vector2 = eagle.global_position - global_position
	if absf(diff.y) > absf(diff.x):
		current_direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
	else:
		current_direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
	_update_sprite_direction()

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

func take_damage() -> void:
	health -= 1
	_hits_taken += 1
	_damage_flash_timer = DAMAGE_FLASH_DURATION
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
	var spawn_pos := Vector2(
		randf_range(160, 160 + 40 * 32),
		randf_range(16, 16 + 30 * 32)
	).snapped(Vector2(32, 32))
	# Check if any player is at the spawn position (overlapping)
	var delay: float = 0.0
	var players := get_tree().get_nodes_in_group("players")
	for player in players:
		if player is PlayerTank and is_instance_valid(player):
			if spawn_pos.distance_to(player.global_position) < 48.0:
				delay = 1.0
				break
	cookie.setup(cookie_type, delay)
	cookie.global_position = spawn_pos
	var container = get_tree().get_first_node_in_group("powerups_container")
	if container:
		container.add_child(cookie)
	else:
		get_tree().current_scene.add_child(cookie)
