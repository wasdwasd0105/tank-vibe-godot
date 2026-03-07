class_name PlayerTank
extends BaseTank

@export var player_id: int = 0  # 0 or 1

# --- HP system ---
const MAX_HP: int = 8
const DEFAULT_HP: int = 4

# --- Speed & weapon levels (0-3, default 1) ---
var speed_level: int = 1
var weapon_level: int = 1

# --- Secondary weapon ---
var secondary_weapon_type: String = "rapid"
var secondary_weapon_count: int = 50

var has_boat: bool = false
var is_invincible: bool = false
var invincible_timer: float = 0.0
var is_spawning: bool = false
var spawn_timer: float = 0.0
var _damage_flash_timer: float = 0.0
const DAMAGE_FLASH_DURATION: float = 0.15

# --- Addon system ---
var has_moon_shield: bool = false
var has_anti_ice: bool = false
var has_memory_save: bool = false
var _addon_sprites: Dictionary = {}  # addon_name -> Sprite2D
var _shield_sprite: Sprite2D = null
# anti-water, anti-ice, memory-save are mutually exclusive (only one active at a time)
const UTILITY_ADDONS: Array = ["anti-water", "anti-ice", "memory-save"]
var _current_utility_addon: String = ""
const ADDON_CONFIG: Dictionary = {
	"moon-shield":  { "scale": 0.9, "offset": 5.0 },
	"anti-water":   { "scale": 1.0, "offset": 0.0 },
	"anti-ice":     { "scale": 1.0, "offset": 10.0 },
	"memory-save":  { "scale": 1.0, "offset": 0.0 },
}

const SPAWN_INVINCIBILITY: float = 3.0
const POWERUP_INVINCIBILITY: float = 10.0

var _input_prefix: String = "p1_"

# Player colors
const PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.0),   # Player 1: Yellow/Gold
	Color(0.3, 0.85, 0.3),   # Player 2: Green
]

# Speed mapping: speed_level -> pixels/sec
const SPEED_MAP: Dictionary = {
	0: 96.0,
	1: 128.0,
	2: 160.0,
	3: 192.0,
}

func _ready() -> void:
	super._ready()
	_input_prefix = "p%d_" % (player_id + 1)
	add_to_group("players")

	# Load persisted stats from GameManager
	speed_level = GameManager.get_speed_level(player_id)
	weapon_level = GameManager.get_weapon_level(player_id)
	secondary_weapon_type = GameManager.get_secondary_weapon_type(player_id)
	secondary_weapon_count = GameManager.get_secondary_weapon_count(player_id)

	# Apply HP: max is always MAX_HP, load persisted HP from GameManager
	max_health = MAX_HP
	health = clampi(GameManager.player_hp[player_id], 1, MAX_HP)

	_apply_speed_upgrade()
	_apply_weapon_upgrade()
	_activate_invincibility(SPAWN_INVINCIBILITY)

	# Set collision layers (before addon restore, so addons can override)
	set_collision_layer_value(1, false)
	set_collision_layer_value(3, true)  # player_tanks
	set_collision_mask_value(1, true)   # walls
	set_collision_mask_value(2, true)   # water
	set_collision_mask_value(4, true)   # enemy_tanks
	set_collision_mask_value(6, true)   # enemy_bullets
	set_collision_mask_value(7, true)   # powerups

	# Restore persisted addons from GameManager (after collision setup so addons like anti-water can override)
	var saved_addons: Array = GameManager.player_addons[player_id]
	for addon_name in saved_addons:
		apply_addon(addon_name)
	# Apply theme sprite and color
	if sprite:
		var tank_key := "p1" if player_id == 0 else "p2"
		var theme_tex := ThemeManager.get_tank_texture(tank_key)
		if theme_tex:
			sprite.texture = theme_tex
		# Dynamically scale sprite to fit 64x64 (2x2 tile) tank size
		var tex_size := sprite.texture.get_size()
		sprite.scale = Vector2(TANK_SIZE / tex_size.x, TANK_SIZE / tex_size.y)
		sprite.modulate = Color.WHITE

func _physics_process(delta: float) -> void:
	if is_invincible:
		invincible_timer -= delta
		if invincible_timer <= 0:
			is_invincible = false
			_update_shield_visual(false)

	var input_dir := Vector2.ZERO
	if Input.is_action_pressed(_input_prefix + "up"):
		input_dir = Vector2.UP
	elif Input.is_action_pressed(_input_prefix + "down"):
		input_dir = Vector2.DOWN
	elif Input.is_action_pressed(_input_prefix + "left"):
		input_dir = Vector2.LEFT
	elif Input.is_action_pressed(_input_prefix + "right"):
		input_dir = Vector2.RIGHT

	# Check for ice under tank
	_check_ice()
	if has_anti_ice:
		is_on_ice = false

	if input_dir != Vector2.ZERO:
		try_move(input_dir)
	else:
		if not is_on_ice:
			stop_moving()

	move_and_slide()
	clamp_to_playfield()

	# Damage flash effect
	if _damage_flash_timer > 0:
		_damage_flash_timer -= delta
		if sprite:
			if fmod(_damage_flash_timer, 0.1) < 0.05:
				sprite.modulate = Color.RED
			else:
				sprite.modulate = Color.WHITE
		if _damage_flash_timer <= 0 and sprite:
			sprite.modulate = Color.WHITE

	if Input.is_action_just_pressed(_input_prefix + "shoot"):
		shoot()
	if Input.is_action_just_pressed(_input_prefix + "shoot2"):
		shoot_secondary()

func _update_sprite_direction() -> void:
	super._update_sprite_direction()
	_update_addon_directions()

# --- Speed & weapon upgrade application ---

func _apply_speed_upgrade() -> void:
	move_speed = SPEED_MAP.get(speed_level, 128.0)

func _apply_weapon_upgrade() -> void:
	match weapon_level:
		0:
			bullet_speed = 256.0
			max_bullets = 1
		1:
			bullet_speed = 384.0
			max_bullets = 1
		2:
			bullet_speed = 384.0
			max_bullets = 2
		3:
			bullet_speed = 384.0
			max_bullets = 2

# --- Cookie effect methods ---

const COOKIE_PICKUP_INVINCIBILITY: float = 1.0

func activate_pickup_invincibility() -> void:
	_activate_invincibility(COOKIE_PICKUP_INVINCIBILITY)

func apply_cookie_speed_up() -> void:
	speed_level = mini(speed_level + 1, 3)
	GameManager.set_speed_level(player_id, speed_level)
	_apply_speed_upgrade()

func apply_cookie_hp_up() -> void:
	health = mini(health + 1, MAX_HP)

func apply_cookie_weapons_up() -> void:
	weapon_level = mini(weapon_level + 1, 3)
	GameManager.set_weapon_level(player_id, weapon_level)
	_apply_weapon_upgrade()

func apply_cookie_star_up() -> void:
	apply_cookie_speed_up()
	apply_cookie_hp_up()
	apply_cookie_weapons_up()

func apply_cookie_max_up() -> void:
	speed_level = 3
	weapon_level = 3
	health = MAX_HP
	GameManager.set_speed_level(player_id, speed_level)
	GameManager.set_weapon_level(player_id, weapon_level)
	_apply_speed_upgrade()
	_apply_weapon_upgrade()

func apply_addon(addon_name: String) -> void:
	# If it's a utility addon (anti-water/anti-ice/memory-save), remove the old one first
	if addon_name in UTILITY_ADDONS:
		_remove_utility_addon()
		_current_utility_addon = addon_name
	# Apply gameplay effect
	match addon_name:
		"anti-water":
			has_boat = true
			set_collision_mask_value(2, false)
		"anti-ice":
			has_anti_ice = true
		"moon-shield":
			has_moon_shield = true
		"memory-save":
			has_memory_save = true
	# Add visual overlay sprite
	_add_addon_sprite(addon_name)

func _remove_utility_addon() -> void:
	if _current_utility_addon.is_empty():
		return
	# Undo gameplay effect of old addon
	match _current_utility_addon:
		"anti-water":
			has_boat = false
			set_collision_mask_value(2, true)
		"anti-ice":
			has_anti_ice = false
		"memory-save":
			has_memory_save = false
	# Remove old sprite
	if _addon_sprites.has(_current_utility_addon):
		var old_spr: Sprite2D = _addon_sprites[_current_utility_addon]
		if old_spr and is_instance_valid(old_spr):
			old_spr.queue_free()
		_addon_sprites.erase(_current_utility_addon)
	_current_utility_addon = ""

func _add_addon_sprite(addon_name: String) -> void:
	var tex := ThemeManager.get_addon_texture(addon_name)
	if tex:
		var cfg: Dictionary = ADDON_CONFIG.get(addon_name, { "scale": 1.0, "offset": 0.0 })
		var addon_sprite := Sprite2D.new()
		addon_sprite.texture = tex
		var tex_size := tex.get_size()
		var addon_size: float = TANK_SIZE * cfg["scale"]
		addon_sprite.scale = Vector2(addon_size / tex_size.x, addon_size / tex_size.y)
		add_child(addon_sprite)
		if addon_name == "moon-shield":
			# Moon-shield renders above utility addons but below tank body:
			# insert just before the Sprite2D child
			var sprite_idx := sprite.get_index() if sprite else get_child_count() - 1
			move_child(addon_sprite, sprite_idx)
			_shield_sprite = addon_sprite
		else:
			# Utility addons render at the bottom (behind everything)
			move_child(addon_sprite, 0)
		_addon_sprites[addon_name] = addon_sprite
		_update_addon_directions()

func is_bullet_blocked(bullet_direction: Vector2) -> bool:
	if not has_moon_shield:
		return false
	return bullet_direction.dot(current_direction) < 0

func _update_addon_directions() -> void:
	var rot := 0.0
	if current_direction == Vector2.DOWN:
		rot = PI
	elif current_direction == Vector2.LEFT:
		rot = -PI / 2
	elif current_direction == Vector2.RIGHT:
		rot = PI / 2
	for addon_name in _addon_sprites:
		var addon_sprite: Sprite2D = _addon_sprites[addon_name]
		if addon_sprite and is_instance_valid(addon_sprite):
			addon_sprite.rotation = rot
	if _shield_sprite and is_instance_valid(_shield_sprite):
		var offset: float = ADDON_CONFIG.get("moon-shield", {}).get("offset", 5.0)
		_shield_sprite.position = current_direction * offset

# --- Secondary weapon system ---

func set_secondary_weapon(weapon_type: String) -> void:
	var weapon_data: Dictionary = CookieData.WEAPON_DATA.get(weapon_type, {})
	if weapon_data.is_empty():
		return
	if weapon_type == secondary_weapon_type:
		# Same weapon: refill by reload_count (capped at max)
		secondary_weapon_count = mini(
			secondary_weapon_count + weapon_data["reload_count"],
			weapon_data["max_count"]
		)
	else:
		# Different weapon: switch and set to reload_count
		secondary_weapon_type = weapon_type
		secondary_weapon_count = weapon_data["reload_count"]
	# Persist to GameManager
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func apply_cookie_bullets_max() -> void:
	var weapon_data: Dictionary = CookieData.WEAPON_DATA.get(secondary_weapon_type, {})
	if weapon_data.is_empty():
		return
	secondary_weapon_count = weapon_data["max_count"]
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func apply_cookie_bullet_refill() -> void:
	var weapon_data: Dictionary = CookieData.WEAPON_DATA.get(secondary_weapon_type, {})
	if weapon_data.is_empty():
		return
	secondary_weapon_count = mini(
		secondary_weapon_count + weapon_data["reload_count"],
		weapon_data["max_count"]
	)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func shoot_secondary() -> void:
	if secondary_weapon_count <= 0:
		return
	secondary_weapon_count -= 1
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)
	shoot()

func _check_ice() -> void:
	var game = get_tree().get_first_node_in_group("game")
	if not game or not game.has_method("get_level_manager"):
		is_on_ice = false
		return
	var level_manager = game.get_level_manager()
	if not level_manager:
		is_on_ice = false
		return
	var tile_pos: Vector2i = level_manager.world_to_tile(global_position)
	if level_manager._bg_tile_data.has(tile_pos):
		var data: Dictionary = level_manager._bg_tile_data[tile_pos]
		is_on_ice = LevelData.get_tile_category(data.get("code", 0)) == LevelData.TileCategory.ICE
	else:
		is_on_ice = false

func _activate_invincibility(duration: float) -> void:
	is_invincible = true
	invincible_timer = maxf(invincible_timer, duration)
	_update_shield_visual(true)

func _update_shield_visual(active: bool) -> void:
	var shield = get_node_or_null("ShieldEffect")
	if shield:
		shield.visible = active

func take_damage() -> void:
	if is_invincible:
		return
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	super.take_damage()

func destroy() -> void:
	Events.player_died.emit(player_id)
	GameManager.lose_life(player_id)
	_spawn_explosion()
	queue_free()
