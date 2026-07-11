class_name PlayerTank
extends BaseTank

@export var player_id: int = 0  # 0 or 1

# --- HP system ---
const MAX_HP: int = 8
const DEFAULT_HP: int = 4

# --- Speed & weapon levels (0-3, default 0) ---
var speed_level: int = 1
var weapon_level: int = 0

# --- Secondary weapon ---
var secondary_weapon_type: String = "rapid"
var secondary_weapon_count: int = 50

var has_boat: bool = false
var is_invincible: bool = false
var invincible_timer: float = 0.0
var is_spawning: bool = false
var spawn_timer: float = 0.0
var _hits_taken: int = 0

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
	"moon-shield":  { "scale": 1.0, "offset": 9.0 },  # hood arc over the front, like the original
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

const REGULAR_WEAPON_COOLDOWN_MAP: Dictionary = {
	0: 0.7,
	1: 0.4,
	2: 0.3,
	3: 0.25,
}

const PLAYER_MAX_ACTIVE_BULLETS: int = 12

var _regular_fire_step: int = 0
var _rapid_special_fire_step: int = 0
var _rapid_special_ammo_progress: int = 0

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
	set_collision_mask_value(4, false)  # enemy_tanks (no mutual push; enemy stops via test_move detection)
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
	if is_materializing:
		velocity = Vector2.ZERO
		return
	if is_flying:
		_update_flying(delta)
		return
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

	# Stop movement when an enemy is immediately ahead, but don't let physics contact push the player.
	var enemy_blocking := velocity != Vector2.ZERO and _is_enemy_ahead()
	if enemy_blocking:
		velocity = Vector2.ZERO
	move_and_slide()
	clamp_to_playfield()

	# (Damage flash is handled centrally in BaseTank._process.)

	if Input.is_action_pressed(_input_prefix + "shoot"):
		shoot_regular()
	var auto_secondary_held := secondary_weapon_type in ["rapid", "fire", "explosion", "ap"] and Input.is_action_pressed(_input_prefix + "shoot2")
	if auto_secondary_held or Input.is_action_just_pressed(_input_prefix + "shoot2"):
		shoot_secondary()

func _update_sprite_direction() -> void:
	super._update_sprite_direction()
	_update_addon_directions()

# --- Speed & weapon upgrade application ---

func _apply_speed_upgrade() -> void:
	move_speed = SPEED_MAP.get(speed_level, 128.0)

func _apply_weapon_upgrade() -> void:
	weapon_level = clampi(weapon_level, 0, 3)
	match weapon_level:
		0:
			bullet_speed = 256.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
		1:
			bullet_speed = 384.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
		2:
			bullet_speed = 384.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
		3:
			bullet_speed = 384.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
	_regular_fire_step = 0
	if shoot_cooldown:
		shoot_cooldown.wait_time = REGULAR_WEAPON_COOLDOWN_MAP.get(weapon_level, 0.4)

func _get_regular_fire_rows() -> Array[float]:
	match weapon_level:
		2:
			return [FIRE_ROW_LEFT, FIRE_ROW_RIGHT]
		3:
			return [FIRE_ROW_LEFT, FIRE_ROW_MID, FIRE_ROW_RIGHT, FIRE_ROW_MID]
		_:
			return [FIRE_ROW_MID]

func shoot_regular() -> void:
	if not can_shoot:
		return

	var fire_rows := _get_regular_fire_rows()
	var row_offset: float = fire_rows[_regular_fire_step % fire_rows.size()]
	_regular_fire_step = (_regular_fire_step + 1) % fire_rows.size()

	_set_shoot_cooldown_wait_time(REGULAR_WEAPON_COOLDOWN_MAP.get(weapon_level, 0.4))
	_begin_shot()
	_spawn_single_row_bullet(row_offset)

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
			# Losing the boat while afloat: the tank sinks. Deferred so it runs
			# after the current add/remove-addon logic finishes.
			_sink_if_stranded_on_water.call_deferred()
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
	# Prefer a 4-frame animation (anti-water / memory-save) over the single sprite.
	var frames: Array = ThemeManager.get_addon_frames(addon_name)
	var tex: Texture2D = frames[0] if not frames.is_empty() else ThemeManager.get_addon_texture(addon_name)
	if tex:
		var cfg: Dictionary = ADDON_CONFIG.get(addon_name, { "scale": 1.0, "offset": 0.0 })
		var addon_sprite := Sprite2D.new()
		addon_sprite.texture = tex
		addon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp, no magenta-key blur
		var tex_size := tex.get_size()
		var addon_size: float = TANK_SIZE * cfg["scale"]
		addon_sprite.scale = Vector2(addon_size / tex_size.x, addon_size / tex_size.y)
		add_child(addon_sprite)
		if not frames.is_empty():
			register_animated_addon(addon_sprite, frames)
		# Draw order via sibling order (all at z 0 so nothing sinks below the world),
		# back -> front: other addons -> moon shield -> tank body (on top, fully visible).
		var sprite_idx := sprite.get_index() if sprite else get_child_count() - 1
		if addon_name == "moon-shield":
			move_child(addon_sprite, sprite_idx)  # just behind the tank body
			_shield_sprite = addon_sprite
		else:
			move_child(addon_sprite, 0)  # behind everything
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
	if weapon_type != secondary_weapon_type:
		_rapid_special_fire_step = 0
		_rapid_special_ammo_progress = 0
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
	if secondary_weapon_count <= 0 or not can_shoot or active_bullets >= max_bullets:
		return
	if secondary_weapon_type == "rapid":
		_shoot_secondary_rapid()
		return
	if secondary_weapon_type == "fire":
		_shoot_secondary_fire()
		return
	if secondary_weapon_type == "explosion":
		_shoot_secondary_explosion()
		return
	if secondary_weapon_type == "mine":
		_shoot_secondary_mine()
		return
	if secondary_weapon_type == "ap":
		_shoot_secondary_ap()
		return
	secondary_weapon_count -= 1
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)
	super.shoot()

func _shoot_secondary_ap() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("ap", weapon_level)
	if config.is_empty():
		return
	if active_ap_bullets >= int(config.get("max_in_flight", 2)):
		return

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.6))
	_begin_shot()
	_spawn_ap_bullet(config)

	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

## AP shell stripped this player's moon shield: remove it and grant a brief grace.
func break_moon_shield_grace() -> void:
	if has_moon_shield:
		_remove_moon_shield()
	_activate_invincibility(AP_SHIELD_GRACE)

const AP_SHIELD_GRACE: float = 1.125

func _shoot_secondary_mine() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("mine", weapon_level)
	if config.is_empty():
		return
	# Lay the mine first; if there's no free tile, spend neither ammo nor cooldown.
	if not _place_mine(int(config.get("mine_level", 1))):
		return
	can_shoot = false
	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.6))
	if shoot_cooldown:
		shoot_cooldown.start()
	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func _shoot_secondary_rapid() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("rapid", weapon_level)
	if config.is_empty():
		return

	var fire_rows: Array = config.get("rows", [FIRE_ROW_MID])
	var ammo_per_count: int = config.get("ammo_per_count", 1)
	var speed_multiplier: float = config.get("speed_multiplier", 1.0)
	var row_offset: float = fire_rows[_rapid_special_fire_step % fire_rows.size()]
	_rapid_special_fire_step = (_rapid_special_fire_step + 1) % fire_rows.size()

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.4))
	_begin_shot()
	_spawn_single_row_bullet(row_offset, bullet_speed * speed_multiplier, "rapid")

	_rapid_special_ammo_progress += 1
	if _rapid_special_ammo_progress >= ammo_per_count:
		_rapid_special_ammo_progress = 0
		secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
		GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func _shoot_secondary_fire() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("fire", weapon_level)
	if config.is_empty():
		return
	if active_fire_bullets >= int(config.get("max_in_flight", 3)):
		return

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.27))
	_begin_shot()
	_spawn_fire_bullet(config)

	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func _shoot_secondary_explosion() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("explosion", weapon_level)
	if config.is_empty():
		return
	if active_explosion_bullets >= int(config.get("max_in_flight", 2)):
		return

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.45))
	_begin_shot()
	_spawn_explosion_bullet(config)

	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

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

## If this tank is sitting on water without a boat, it sinks. Called when the
## anti-water addon is lost (e.g. shot off) while afloat.
func _sink_if_stranded_on_water() -> void:
	if has_boat or is_flying or not is_instance_valid(self):
		return
	var game = get_tree().get_first_node_in_group("game")
	if not game or not game.has_method("get_level_manager"):
		return
	var lm = game.get_level_manager()
	if lm and lm.is_water_at_world(global_position):
		destroy()  # sank — no boat on water

func _activate_invincibility(duration: float) -> void:
	is_invincible = true
	invincible_timer = maxf(invincible_timer, duration)
	_update_shield_visual(true)

func _update_shield_visual(active: bool) -> void:
	# The old procedural arc is replaced by the animated shield wreath (Tank_T row 1).
	var old = get_node_or_null("ShieldEffect")
	if old:
		old.visible = false
	if active:
		show_state_overlay(BaseTank.get_shield_frames())
	else:
		hide_state_overlay()

func _is_enemy_ahead() -> bool:
	## Check if an enemy tank is blocking movement in the current direction.
	## Temporarily enables the enemy mask for test_move, then disables it.
	var lookahead := maxf(move_speed / float(Engine.physics_ticks_per_second), 2.0)
	set_collision_mask_value(4, true)
	var blocked := test_move(global_transform, current_direction * lookahead)
	set_collision_mask_value(4, false)
	if not blocked:
		return false
	# Check if the blockage is specifically an enemy (not a wall)
	var still_blocked := test_move(global_transform, current_direction * lookahead)
	return not still_blocked  # True = enemy was the only thing blocking

# --- Hit punishment system ---

func _remove_moon_shield() -> void:
	has_moon_shield = false
	if _shield_sprite and is_instance_valid(_shield_sprite):
		_shield_sprite.queue_free()
		_shield_sprite = null
	if _addon_sprites.has("moon-shield"):
		_addon_sprites.erase("moon-shield")

func _drop_player_addon_cookie(addon_name: String) -> void:
	var cookie_type: int = CookieData.ADDON_TO_COOKIE.get(addon_name, -1)
	if cookie_type == -1:
		return
	# Remove the addon from the tank
	if addon_name == "moon-shield":
		_remove_moon_shield()
	elif addon_name in UTILITY_ADDONS:
		_remove_utility_addon()
	# Spawn the addon cookie on the playfield
	_spawn_cookie_at_position(cookie_type)

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

func _apply_hit_punishment() -> void:
	# Priority 1: drop moon-shield if have it
	if has_moon_shield:
		_drop_player_addon_cookie("moon-shield")
		return
	# Priority 2: drop utility addon (anti-water/anti-ice) if have one
	if _current_utility_addon != "" and _current_utility_addon != "memory-save":
		_drop_player_addon_cookie(_current_utility_addon)
		return
	# Priority 3: alternate -1 speed / -1 weapon
	_hits_taken += 1
	if (_hits_taken % 2) == 1:
		# Odd (1, 3, 5, ...): -1 speed
		if speed_level > 0:
			speed_level -= 1
			GameManager.set_speed_level(player_id, speed_level)
			_apply_speed_upgrade()
	else:
		# Even (2, 4, 6, ...): -1 weapon
		if weapon_level > 0:
			weapon_level -= 1
			GameManager.set_weapon_level(player_id, weapon_level)
			_apply_weapon_upgrade()

func take_damage() -> void:
	if is_invincible:
		return
	if not has_memory_save:
		_apply_hit_punishment()
	super.take_damage()  # reduces health + triggers the shared damage flash

func destroy() -> void:
	if has_memory_save:
		# Spray the memory-save addon cookie
		var mem_cookie_type: int = CookieData.ADDON_TO_COOKIE.get("memory-save", -1)
		if mem_cookie_type >= 0:
			_spawn_cookie_at_position(mem_cookie_type)
		# Save current stats before lose_life() resets them
		var saved_speed: int = speed_level
		var saved_weapon: int = weapon_level
		var saved_secondary_type: String = secondary_weapon_type
		var saved_secondary_count: int = secondary_weapon_count
		var saved_addons: Array = []
		if has_moon_shield:
			saved_addons.append("moon-shield")
		# Normal death flow
		Events.player_died.emit(player_id)
		GameManager.lose_life(player_id)
		# Restore saved stats into GameManager so the respawned tank loads them
		GameManager.player_speed_levels[player_id] = saved_speed
		GameManager.player_weapon_levels[player_id] = saved_weapon
		GameManager.player_secondary_weapon_types[player_id] = saved_secondary_type
		GameManager.player_secondary_weapon_counts[player_id] = saved_secondary_count
		GameManager.player_addons[player_id] = saved_addons
		_spawn_explosion()
		queue_free()
	else:
		Events.player_died.emit(player_id)
		GameManager.lose_life(player_id)
		_spawn_explosion()
		queue_free()
