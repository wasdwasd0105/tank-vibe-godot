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
## Add-on size relative to TANK_SIZE. Where each one sits is BaseTank's
## _layout_addons, as the original placed them.
const ADDON_CONFIG: Dictionary = {
	"moon-shield":  { "scale": 1.0 },
	"anti-water":   { "scale": 1.0 },
	"anti-ice":     { "scale": 1.0 },
	"memory-save":  { "scale": 1.0 },
}

const SPAWN_INVINCIBILITY: float = 3.0
## Tank.exe showed the shield wreath only while at least 3000 ticks (2.25 s) of
## invulnerability were left, which in practice means the helmet cookie. Any
## shorter invulnerability, and the helmet's last 2.25 s, blinked instead: the
## tank drawn on every other frame (its DoDraw, 0x0049208c).
const WREATH_MIN_LEFT: float = 2.25
var _helmet_invincible: bool = false
var _wreath_shown: bool = false
## A player held by an enemy's "Hold Enemy" is wrapped in frost: the ringed web
## while more than 5000 ticks of the hold are left, the bare web down to 1000,
## then none (Tank.exe 0x0049495a). The frost covers the helmet's wreath.
const HOLD_RING_LEFT: float = 3.75
const HOLD_WEB_LEFT: float = 0.75
var _hold_shown: int = 0  # 2 ringed web, 1 bare web, 0 none
## A player who survives a hit is untouchable for 750 ticks (0.5625 s), blinking
## like any short invincibility (Tank.exe's Damage, 0x00492640). Bots get none,
## and neither does a tank hit while airborne.
const HIT_GRACE: float = 0.5625
## The frame whose hit started the grace. The original dealt a blast's or a
## shell's damage in one go before the grace began, so the rest of that same
## hit still lands.
var _hit_grace_frame: int = -1

# Controller rumble [weak motor, strong motor, seconds]: a jolt per hit that
# costs HP, a big one when the tank is destroyed or a mine throws it; and
# (Sean, 2026-09-25) a lighter thump for each enemy the player destroys, and
# the big one again for a bomb taken, which covers the bomb's own kills.
const HIT_RUMBLE: Array[float] = [0.45, 0.6, 0.2]
const DEATH_RUMBLE: Array[float] = [0.9, 1.0, 0.55]
const MINE_THROW_RUMBLE: Array[float] = [0.6, 0.9, 0.35]
const KILL_RUMBLE: Array[float] = [0.3, 0.5, 0.15]
const BOMB_RUMBLE: Array[float] = DEATH_RUMBLE

const POWERUP_INVINCIBILITY: float = 10.0

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
## Secondary weapons that keep firing while their button is held (the others
## fire once a press).
const AUTO_SECONDARY: Array[String] = ["rapid", "fire", "explosion", "ap"]

var _regular_fire_step: int = 0
var _rapid_special_fire_step: int = 0
var _rapid_special_ammo_progress: int = 0

# --- Online: lag compensation (docs/network_design.md section 7) ---

## Host: a client's tank's copy here catches up at up to this many times its own
## speed. Held up this far behind it for this long (by what the client didn't
## see in time), the client is told to start again from the host's position.
const FOLLOW_SPEED := 2.0
const APART_DISTANCE := 24.0
const APART_TIME := 0.3

## Host: changes whenever the host, not the client driving this tank, says
## where it is: a correction, or a spell the host drives (materializing, a
## mine's flight, a hold). The client starts again from the host's position,
## and only reports that have taken the change are followed.
var net_override := 0
var _host_drives := false
## Host: the client driving this tank, its lag compensation off, had its keys
## move it here: should it turn it on, it starts again from here.
var _host_moved_it := false
var _apart_time := 0.0
## Client: this machine drives this tank (its own seat), with local slot
## [member net_slot]'s controls. It moves here at once (_predict), ahead of the
## host by the trip there, and the host's copy follows it.
var net_predicted := false
var net_slot := 0
var _override_seen := 0

func _ready() -> void:
	super._ready()
	add_to_group("players")
	net_override = randi() % 256  # no report about an earlier tank can match it

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
	set_collision_mask_value(4, false)  # enemy_tanks (no mutual push; each stops for the other via _opponent_ahead)
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
	if Net.is_client():
		if is_net_driving():
			_predict()
		return  # the host drives every other tank; this one only shows it
	if is_materializing:
		velocity = Vector2.ZERO
		_take_over()
		return
	if is_flying:
		_update_flying(delta)
		_take_over()
		return
	if is_invincible:
		invincible_timer -= delta
		if invincible_timer <= 0:
			is_invincible = false
			_helmet_invincible = false
			_sync_wreath()
	if GameManager.players_frozen:
		glide_while_held("enemies")  # an enemy took "Hold Enemy"
		_take_over()
		return

	if not PlayerInput.is_remote_seat(player_id):
		_drive(_read_move_direction())
	elif PlayerInput.remote_predicts(player_id):
		_follow_client(delta)
	else:
		_drive_for_client()

	# (Damage flash is handled centrally in BaseTank._process.)

	if PlayerInput.is_held(player_id, 0):
		shoot_regular()
	var auto_secondary_held := secondary_weapon_type in AUTO_SECONDARY and PlayerInput.is_held(player_id, 1)
	if auto_secondary_held or PlayerInput.is_just_pressed(player_id, 1):
		shoot_secondary()

## One step of driving with [param input_dir] pushed: the turn, ice, an enemy
## in the way, the walls. The host's own players drive this way, and so does
## a client's own tank on the client (_predict).
func _drive(input_dir: Vector2) -> void:
	_check_ice()
	if has_anti_ice:
		is_on_ice = false
	if input_dir != Vector2.ZERO:
		try_move(input_dir)
	elif not is_on_ice:
		stop_moving()
	# Stop movement when an enemy is immediately ahead, but don't let physics contact push the player.
	if velocity != Vector2.ZERO and _is_enemy_ahead():
		velocity = Vector2.ZERO
	move_and_slide()
	clamp_to_playfield()

## Host: this tank's driver is on a client, which drives its own copy at once
## and reports where it is (lag compensation). This copy goes after it, at up
## to FOLLOW_SPEED times its speed, stopped by the walls, water and enemies
## this machine has. Held up for too long, it tells the client to start again
## from here (net_override); until the client has, this copy waits.
func _follow_client(delta: float) -> void:
	_host_drives = false
	if _host_moved_it:
		_host_moved_it = false
		_correct_client()  # its keys moved it here meanwhile (_drive_for_client)
	var report := PlayerInput.remote_report(player_id)
	if report == null or report.report_override != net_override:
		stop_moving()
		_apart_time = 0.0
		return
	var speed := move_speed * (MINE_SLOW_FACTOR if is_mine_slowed else 1.0)
	var way: Vector2 = report.report_position - global_position
	# Across the way it faces now first: the rest of the way it went before
	# it turned. Within half a tile, that's the turn's own snap to the grid
	# (try_move), taken at once as the client did.
	var facing: Vector2 = FACINGS[report.report_facing]
	var across := way * Vector2(absf(facing.y), absf(facing.x))
	if across.length() > HALF_TILE:
		way = across
	else:
		position += across
		way -= across
	var step := way.limit_length(speed * FOLLOW_SPEED * delta)
	var moved := 0.0
	if step != Vector2.ZERO:
		facing = step.normalized()
		if not _opponent_ahead("enemies", facing, maxf(step.length(), 2.0)):
			var before := global_position
			move_and_collide(step)
			clamp_to_playfield()
			moved = global_position.distance_to(before)
	if facing != current_direction:
		current_direction = facing
		_update_sprite_direction()
	is_moving = report.report_moving or moved > 0.0
	velocity = current_direction * speed if is_moving else Vector2.ZERO
	if global_position.distance_to(report.report_position) > APART_DISTANCE and moved < step.length() * 0.5:
		_apart_time += delta
		if _apart_time >= APART_TIME:
			_correct_client()
	else:
		_apart_time = 0.0

## Host: the client driving this tank doesn't run it ahead (its lag
## compensation is off): its keys drive it here as they come, as they did
## before lag compensation.
func _drive_for_client() -> void:
	var before := global_position
	_drive(_read_move_direction())
	if global_position != before:
		_host_moved_it = true

## Host: the host drives this tank itself just now (a spell): the client
## driving it starts again from wherever it ends up.
func _take_over() -> void:
	if not _host_drives:
		_host_drives = true
		_correct_client()

## Host: the client driving this tank is to start again from where it is here.
func _correct_client() -> void:
	net_override = (net_override + 1) % 256
	_apart_time = 0.0

## Client: this machine drives this tank here (see net_predicted), unless the
## host moves it itself just now: materializing, a mine's flight, a hold.
func is_net_driving() -> bool:
	return net_predicted and not is_materializing and not is_flying and not GameManager.players_frozen

func _net_drives_itself() -> bool:
	return is_net_driving()

## Client: this machine takes over this tank, with local slot [param slot]'s
## controls ([param on]), or stops. Driving it, it bumps into the walls, water
## and the base here as it would on the host.
func set_net_predicted(on: bool, slot: int) -> void:
	net_slot = slot
	if on == net_predicted:
		return
	net_predicted = on
	collision_layer = 0
	collision_mask = 0
	if on:
		set_collision_layer_value(3, true)  # player_tanks
		for layer: int in [1, 2, 8]:        # walls, water, the base
			set_collision_mask_value(layer, true)
		if has_boat:
			set_collision_mask_value(2, false)
	else:
		velocity = Vector2.ZERO

## Client: one step of this machine's own tank, as the host would drive it, at
## once: the keys don't wait for the trip to the host and back. Where it is goes
## to the host with the next input message, and the host's copy follows.
func _predict() -> void:
	speed_level = int(GameManager.player_speed_levels[player_id])
	_apply_speed_upgrade()
	var blocked := Net.input_blocked or Net.map_prompt_open
	_drive(Vector2.ZERO if blocked else PlayerInput.local_direction(net_slot))
	Net.report_tank(net_slot, global_position, maxi(FACINGS.find(current_direction), 0),
			velocity != Vector2.ZERO, _override_seen)
	if not blocked:
		_predict_fire()

## Client: this tank's shots, fired here at once as the host will fire them when
## the keys reach it: each is seen and heard now, a ghost of the host's shell
## to come (BaseTank._spawn_bullet, NetClientWorld.add_ghost). Mines are left
## to the host.
func _predict_fire() -> void:
	_take_host_weapons()
	var prefix := PlayerInput.action_prefix(net_slot)
	if Input.is_action_pressed(prefix + PlayerInput.BUTTONS[0]):
		shoot_regular()
	if secondary_weapon_type == "mine":
		return
	var held := Input.is_action_pressed(prefix + PlayerInput.BUTTONS[1])
	if (held and secondary_weapon_type in AUTO_SECONDARY) or Input.is_action_just_pressed(prefix + PlayerInput.BUTTONS[1]):
		shoot_secondary()

## Client: this tank's weapons as the host has them (GameManager's numbers come
## from the host), and its shells in flight as shown here, so its shots go as
## the host's will.
func _take_host_weapons() -> void:
	var level := int(GameManager.player_weapon_levels[player_id])
	if level != weapon_level:
		weapon_level = level
		_apply_weapon_upgrade()
	var kind := str(GameManager.player_secondary_weapon_types[player_id])
	if kind != secondary_weapon_type:
		secondary_weapon_type = kind
		_rapid_special_fire_step = 0
		_rapid_special_ammo_progress = 0
	secondary_weapon_count = int(GameManager.player_secondary_weapon_counts[player_id])
	var world := NetClientWorld.of(get_tree())
	if world:
		active_bullets = world.own_shells_in_flight(player_id)
		active_fire_bullets = world.own_shells_in_flight(player_id, "fire")
		active_explosion_bullets = world.own_shells_in_flight(player_id, "explosion")
		active_ap_bullets = world.own_shells_in_flight(player_id, "ap")

## A shot's sound. The host's goes to its clients marked as this tank's, so the
## client driving it, which heard it as it fired (_predict_fire), doesn't again.
func _shot_sound(key: StringName) -> void:
	if Net.is_client():
		SoundManager.play_predicted(key, player_id)
	else:
		SoundManager.play(key, player_id)

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
	_shot_sound(&"fire_primary")
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
		# Draw order via sibling order (all at z 0 so nothing sinks below the world),
		# back -> front: other addons -> moon shield -> tank body (on top, fully visible).
		var sprite_idx := sprite.get_index() if sprite else get_child_count() - 1
		if addon_name == "moon-shield":
			move_child(addon_sprite, sprite_idx)  # just behind the tank body
			_shield_sprite = addon_sprite
		else:
			move_child(addon_sprite, 0)  # behind everything
		_addon_sprites[addon_name] = addon_sprite
		_layout_addons()

func is_bullet_blocked(bullet_direction: Vector2) -> bool:
	if not has_moon_shield:
		return false
	return bullet_direction.dot(current_direction) < 0

func get_gun_level() -> int:
	return weapon_level

func get_player_index() -> int:
	return player_id

## The moon shield first: it is what a hit would cost first, too.
func get_addon_names() -> Array:
	var names: Array = []
	if has_moon_shield:
		names.append("moon-shield")
	if not _current_utility_addon.is_empty():
		names.append(_current_utility_addon)
	return names

func lose_addon(addon_name: String) -> void:
	if addon_name == "moon-shield":
		_remove_moon_shield()
	elif addon_name == _current_utility_addon:
		_remove_utility_addon()

func is_invulnerable() -> bool:
	return is_invincible

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
	_shot_sound(&"fire_ap")
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
	# Lay the mine first; if there's no free spot, spend neither ammo nor cooldown.
	if not _place_mine(weapon_level):
		return
	SoundManager.play(&"lay_mine")
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
	_shot_sound(&"fire_rapid")

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
	_shot_sound(&"fire_fire")
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
	_shot_sound(&"fire_explosion")
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
	if has_boat or is_flying or not is_instance_valid(self) or Net.is_client():
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
	_sync_wreath()

## The invincible helmet cookie: the one invincibility that shows the wreath.
func activate_helmet(duration: float) -> void:
	_helmet_invincible = true
	_activate_invincibility(duration)

func _process(delta: float) -> void:
	super(delta)
	_sync_wreath()
	_blink_while_invincible()

func _sync_wreath() -> void:
	var wreath := is_invincible and _helmet_invincible and invincible_timer > WREATH_MIN_LEFT
	var hold := _hold_stage()
	if wreath != _wreath_shown or hold != _hold_shown:
		_wreath_shown = wreath
		_hold_shown = hold
		match hold:
			2:
				show_state_overlay(BaseTank.get_freeze_frames())
			1:
				show_state_overlay(BaseTank.get_thaw_frames())
			_:
				_update_shield_visual(wreath)

func _hold_stage() -> int:
	if not GameManager.players_frozen:
		return 0
	var left := GameManager.players_freeze_timer
	if left > HOLD_RING_LEFT:
		return 2
	return 1 if left > HOLD_WEB_LEFT else 0

## Any other invincibility blinks the tank: drawn one frame, gone the next.
func _blink_while_invincible() -> void:
	if is_materializing:
		return  # still hidden behind its spawn burst
	if is_invincible and not _wreath_shown:
		visible = not visible
	elif not visible:
		visible = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and not is_materializing:
		visible = true  # never sit out a pause on a blank blink frame

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
	var lookahead := maxf(move_speed / float(Engine.physics_ticks_per_second), 2.0)
	return _opponent_ahead("enemies", current_direction, lookahead)

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

## The way the player is pushing (PlayerInput.move_direction): this tank's
## controls offline, whoever took its seat online.
func _read_move_direction() -> Vector2:
	return PlayerInput.move_direction(player_id)

func _rumble(pattern: Array[float]) -> void:
	rumble_player(player_id, pattern)

# --- Online (see BaseTank's net_state) ---

## Past the base's flags: invincible (it blinks), showing the helmet's wreath,
## and slowed by a mine (a client driving it drives slow too).
const NET_INVINCIBLE := NET_OWN_FLAGS
const NET_WREATH := NET_OWN_FLAGS << 1
const NET_SLOWED := NET_OWN_FLAGS << 2
## Past the base's state: the host's net_override.
const NET_OVERRIDE_AT := 9

func net_type() -> int:
	return NetWorld.T_PLAYER

func net_spawn_args() -> Array:
	return [player_id]

## A client's tank for player [param args][0], set before it enters the tree.
func net_setup(args: Array) -> void:
	player_id = clampi(int(args[0]), 0, 1)

func net_state() -> Array:
	var state := super.net_state()
	var flags: int = state[3]
	if is_invincible:
		flags |= NET_INVINCIBLE
	if is_invincible and _helmet_invincible and invincible_timer > WREATH_MIN_LEFT:
		flags |= NET_WREATH
	if is_mine_slowed:
		flags |= NET_SLOWED
	state[3] = flags
	state.append(net_override)
	return state

func net_apply(state: Array) -> void:
	super.net_apply(state)
	var flags := int(state[3])
	is_invincible = flags & NET_INVINCIBLE != 0
	# The wreath shows while more than WREATH_MIN_LEFT is left; the host says
	# when, so the clock here only has to sit on the right side of it.
	_helmet_invincible = flags & NET_WREATH != 0
	invincible_timer = WREATH_MIN_LEFT + 1.0 if _helmet_invincible else (1.0 if is_invincible else 0.0)
	is_mine_slowed = flags & NET_SLOWED != 0
	# The host's correction: this machine's tank starts again from the host's
	# position. (While the host drives it, it's already there: NetClientWorld.)
	var override := int(state[NET_OVERRIDE_AT]) if state.size() > NET_OVERRIDE_AT else 0
	if override != _override_seen:
		_override_seen = override
		if is_net_driving():
			global_position = Vector2(state[0], state[1])
			current_direction = FACINGS[clampi(int(state[2]), 0, FACINGS.size() - 1)]
			_update_sprite_direction()
			velocity = Vector2.ZERO

func _net_apply_addons(bits: int) -> void:
	var wanted := BaseTank.net_addon_names(bits)
	var moon := "moon-shield" in wanted
	if moon and not has_moon_shield:
		apply_addon("moon-shield")
	elif not moon and has_moon_shield:
		_remove_moon_shield()
	var utility := ""
	for addon_name in wanted:
		if addon_name in UTILITY_ADDONS:
			utility = addon_name
	if utility != _current_utility_addon:
		if utility.is_empty():
			_remove_utility_addon()
		else:
			apply_addon(utility)

## Rumbles player [param pid]'s controller with [param pattern], their tank on
## the field or not (a kill by a shell still flying, or by a mine). Online it's
## whoever drives that tank, on this machine or a client (Net.rumble_tank).
static func rumble_player(pid: int, pattern: Array[float]) -> void:
	Net.rumble_tank(pid, pattern[0], pattern[1], pattern[2])

func take_damage() -> void:
	if is_invincible and _hit_grace_frame != Engine.get_process_frames():
		return
	# An airborne tank (a mine throw) loses no level for the hit, as in the original.
	if not has_memory_save and not is_flying:
		_apply_hit_punishment()
	_rumble(HIT_RUMBLE)  # a fatal hit's destroy() takes over with the big one
	super.take_damage()  # reduces health + triggers the shared damage flash
	if health > 0 and not is_flying:
		_hit_grace_frame = Engine.get_process_frames()
		_activate_invincibility(HIT_GRACE)

func launch_mine_fly(mine_level: int, mine_center: Vector2, landing_hit: int = 0, owner_id: int = -1) -> void:
	if not is_flying:
		_rumble(MINE_THROW_RUMBLE)
	super.launch_mine_fly(mine_level, mine_center, landing_hit, owner_id)

func destroy() -> void:
	if is_queued_for_deletion():
		return  # already destroyed this frame (a bomb and a shell): one life
	_rumble(DEATH_RUMBLE)
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
