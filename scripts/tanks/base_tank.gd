class_name BaseTank
extends CharacterBody2D

const HALF_TILE: int = 16
const TILE_SIZE: int = 32
const TANK_SIZE: int = 64  # Tanks occupy 2x2 tiles
const HALF_TANK: int = 32  # Half of tank size for boundary clamping
const DEFAULT_BULLET_LANE_OFFSETS: Array[float] = [-16.0, 16.0]
const FIRE_ROW_LEFT: float = -16.0
const FIRE_ROW_MID: float = 0.0
const FIRE_ROW_RIGHT: float = 16.0
const MID_ROW_COLLISION_OFFSETS: Array[float] = [-16.0, 16.0]

# Playfield boundaries in global coordinates (Playfield at 160,16; grid 40x30 @ 32px)
const PLAYFIELD_MIN_X: float = 192.0   # 160 + 32 (half tank inset)
const PLAYFIELD_MAX_X: float = 1408.0  # 160 + 40*32 - 32
const PLAYFIELD_MIN_Y: float = 48.0    # 16 + 32
const PLAYFIELD_MAX_Y: float = 944.0   # 16 + 30*32 - 32

@export var move_speed: float = 128.0
@export var max_health: int = 1
@export var bullet_speed: float = 256.0

var health: int = 1
var current_direction: Vector2 = Vector2.UP
var is_moving: bool = false
var can_shoot: bool = true
var active_bullets: int = 0
var max_bullets: int = 1
var is_on_ice: bool = false

# Fire weapon: bullets currently in flight, and per-tank immunity so ground
# fire only deals damage once per cadence window while a tank stands in it.
var active_fire_bullets: int = 0
var active_explosion_bullets: int = 0
var active_ap_bullets: int = 0
var fire_immunity_timer: float = 0.0

# Red "hit" flash, shared by every damage source (bullets and all special weapons).
# Longer than an explosion/mine blast (~0.22s) so the flash stays visible after
# the fireball fades.
const DAMAGE_FLASH_DURATION: float = 0.35
var _damage_flash_timer: float = 0.0

# Mine weapon effects on this tank.
var is_mine_slowed: bool = false        # halved speed until a cookie is picked up (players)
var is_flying: bool = false             # thrown into the air by a level 3/4 mine — helpless
var _fly_t: float = 0.0
var _fly_duration: float = 0.0
var _fly_level: int = 3
var _fly_horiz_vel: Vector2 = Vector2.ZERO
var _fly_peak_height: float = 0.0       # visual altitude at apex (px)
var _fly_peak_scale: float = 0.0        # extra sprite scale at apex
var _fly_spin_speed: float = 0.0        # rad/s (signed)
var _fly_base_sprite_scale: Vector2 = Vector2.ONE
var _fly_saved_layer: int = 0

const MINE_SLOW_FACTOR: float = 0.5

# Spawn materialize: a tank is created hidden + intangible while its spawn burst
# plays, then revealed and made collidable so it only "appears" once the effect
# finishes. Bookkeeping (enemy counts, etc.) stays synchronous at spawn time.
var is_materializing: bool = false
var _materialize_timer: float = 0.0
var _materialize_saved_layer: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_cooldown: Timer = $ShootCooldown

func _ready() -> void:
	health = max_health
	add_to_group("tanks")
	if shoot_cooldown:
		shoot_cooldown.timeout.connect(_on_shoot_cooldown_timeout)

func _process(delta: float) -> void:
	if fire_immunity_timer > 0.0:
		fire_immunity_timer -= delta
	_animate_addons(delta)
	_tick_damage_flash(delta)
	_tick_state_overlay(delta)
	_tick_materialize(delta)

## Blink the sprite red briefly after any hit. Runs in _process (never gated by
## frozen/flying state) so every tank flashes for every damage source.
func _tick_damage_flash(delta: float) -> void:
	if _damage_flash_timer <= 0.0:
		return
	_damage_flash_timer -= delta
	if not sprite:
		return
	if _damage_flash_timer <= 0.0:
		sprite.modulate = Color.WHITE
	elif fmod(_damage_flash_timer, 0.16) < 0.08:
		sprite.modulate = Color.RED
	else:
		sprite.modulate = Color.WHITE

# --- Animated addon sprites (anti-water / memory-save, 4-frame loops) ---
var _animated_addons: Array = []   # Array of { "sprite": Sprite2D, "frames": Array }
var _addon_anim_time: float = 0.0
const ADDON_ANIM_FRAME_DUR: float = 1.0

## Hide + freeze this tank while its spawn burst plays; it reveals after [param duration].
## collision_layer is zeroed (mirroring the fly state) so it can't be hit or block meanwhile.
func begin_materialize(duration: float) -> void:
	is_materializing = true
	_materialize_timer = duration
	velocity = Vector2.ZERO
	visible = false
	_materialize_saved_layer = collision_layer
	collision_layer = 0

func _tick_materialize(delta: float) -> void:
	if not is_materializing:
		return
	_materialize_timer -= delta
	if _materialize_timer <= 0.0:
		is_materializing = false
		visible = true
		collision_layer = _materialize_saved_layer

## Register an addon sprite to cycle through [param frames] each ADDON_ANIM_FRAME_DUR.
func register_animated_addon(sprite: Sprite2D, frames: Array) -> void:
	_animated_addons.append({ "sprite": sprite, "frames": frames })

func _animate_addons(delta: float) -> void:
	if _animated_addons.is_empty():
		return
	_addon_anim_time += delta
	var f := int(_addon_anim_time / ADDON_ANIM_FRAME_DUR)
	var alive: Array = []
	for a in _animated_addons:
		var spr = a["sprite"]  # untyped: a freed instance must not hit a typed assign
		if is_instance_valid(spr):
			var frames: Array = a["frames"]
			(spr as Sprite2D).texture = frames[f % frames.size()]
			alive.append(a)
	_animated_addons = alive

# --- State-effect overlay: one fast-cycling Sprite2D child that plays while a
# state is active (player invincibility shield, enemy freeze frost). A tank only
# ever needs one at a time, so a single reusable slot suffices. Frames are the
# extracted Tank_T rows (48px, drawn ~1.5x the 64px tank so they wreathe it).
const STATE_FX_FRAME_DUR: float = 0.08
const STATE_FX_SIZE: float = 96.0
var _state_fx_sprite: Sprite2D = null
var _state_fx_frames: Array = []
var _state_fx_time: float = 0.0

static var _shield_frames: Array[Texture2D] = []
static var _freeze_frames: Array[Texture2D] = []

## Cached loader for a numbered effect strip under assets/sprites/effects/.
static func _load_fx_frames(stem: String, count: int) -> Array[Texture2D]:
	var arr: Array[Texture2D] = []
	for i in range(1, count + 1):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path("res://assets/sprites/effects/%s_%d.png" % [stem, i])) == OK:
			img.convert(Image.FORMAT_RGBA8)
			arr.append(ImageTexture.create_from_image(img))
	return arr

static func get_shield_frames() -> Array[Texture2D]:
	if _shield_frames.is_empty():
		_shield_frames = _load_fx_frames("shield/shield", 8)
	return _shield_frames

static func get_freeze_frames() -> Array[Texture2D]:
	if _freeze_frames.is_empty():
		_freeze_frames = _load_fx_frames("freeze/freeze", 8)
	return _freeze_frames

## Show (creating on first use) the state overlay with [param frames]. Drawn on
## top of the tank body by default so the wreath reads over it.
func show_state_overlay(frames: Array, on_top: bool = true) -> void:
	if frames.is_empty():
		return
	if _state_fx_sprite == null or not is_instance_valid(_state_fx_sprite):
		_state_fx_sprite = Sprite2D.new()
		_state_fx_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_state_fx_sprite)
		if not on_top and sprite:
			move_child(_state_fx_sprite, sprite.get_index())
	_state_fx_frames = frames
	var tex: Texture2D = frames[0]
	var ts := tex.get_size()
	if ts.x > 0:
		_state_fx_sprite.scale = Vector2(STATE_FX_SIZE / ts.x, STATE_FX_SIZE / ts.y)
	_state_fx_sprite.texture = tex
	_state_fx_sprite.visible = true

func hide_state_overlay() -> void:
	if _state_fx_sprite and is_instance_valid(_state_fx_sprite):
		_state_fx_sprite.visible = false

func _tick_state_overlay(delta: float) -> void:
	if _state_fx_sprite == null or not is_instance_valid(_state_fx_sprite):
		return
	if not _state_fx_sprite.visible or _state_fx_frames.is_empty():
		return
	_state_fx_time += delta
	var f := int(_state_fx_time / STATE_FX_FRAME_DUR) % _state_fx_frames.size()
	_state_fx_sprite.texture = _state_fx_frames[f]

## Called by GroundFire when this tank overlaps a burning tile.
## The tank's own side is immune to its own fire; damage is throttled by
## [member fire_immunity_timer].
func on_fire_contact(from_player_fire: bool, reburn: float, hurts_both: bool = false) -> void:
	if fire_immunity_timer > 0.0:
		return
	# Grass fire is neutral and burns everyone; weapon fire never burns its own side.
	if not hurts_both:
		var is_player := is_in_group("players")
		if from_player_fire == is_player:
			return  # player fire never burns players; enemy fire never burns enemies
	fire_immunity_timer = reburn
	take_damage()

func try_move(new_direction: Vector2) -> void:
	if new_direction != current_direction:
		current_direction = new_direction
		# Snap perpendicular axis to grid
		if new_direction.x != 0:
			position.y = round(position.y / HALF_TILE) * HALF_TILE
		else:
			position.x = round(position.x / HALF_TILE) * HALF_TILE
		_update_sprite_direction()
	velocity = current_direction * move_speed * (MINE_SLOW_FACTOR if is_mine_slowed else 1.0)
	is_moving = true

func stop_moving() -> void:
	velocity = Vector2.ZERO
	is_moving = false

func _update_sprite_direction() -> void:
	if not sprite:
		return
	if current_direction == Vector2.UP:
		sprite.rotation = 0
	elif current_direction == Vector2.DOWN:
		sprite.rotation = PI
	elif current_direction == Vector2.LEFT:
		sprite.rotation = -PI / 2
	elif current_direction == Vector2.RIGHT:
		sprite.rotation = PI / 2

func shoot() -> void:
	if active_bullets >= max_bullets or not can_shoot:
		return
	_begin_shot()
	_spawn_bullet(
		global_position + current_direction * (TANK_SIZE * 0.5),
		DEFAULT_BULLET_LANE_OFFSETS,
		DEFAULT_BULLET_LANE_OFFSETS
	)

func _begin_shot() -> void:
	can_shoot = false
	if shoot_cooldown:
		shoot_cooldown.start()
	active_bullets += 1

func _set_shoot_cooldown_wait_time(wait_time: float) -> void:
	if shoot_cooldown:
		shoot_cooldown.wait_time = wait_time

func _spawn_bullet(
	spawn_position: Vector2,
	visual_lane_offsets: Array[float],
	collision_lane_offsets: Array[float],
	bullet_speed_override: float = -1.0,
	bullet_visual_style: String = "regular",
	ignites_ground: bool = false,
	bullet_damage: int = 1,
	max_range: float = -1.0,
	explodes: bool = false,
	explosion_level: int = 0,
	pierces: bool = false,
	accel: float = 0.0,
	max_speed: float = 0.0
) -> void:
	var bullet_scene := preload("res://scenes/tanks/bullet.tscn")
	var bullet: Bullet = bullet_scene.instantiate()
	bullet.direction = current_direction
	bullet.speed = bullet_speed_override if bullet_speed_override > 0.0 else bullet_speed
	bullet.owner_tank = self
	bullet.is_player_bullet = is_in_group("players")
	bullet.visual_lane_offsets = visual_lane_offsets.duplicate()
	bullet.collision_lane_offsets = collision_lane_offsets.duplicate()
	bullet.visual_style = bullet_visual_style
	bullet.ignites_ground = ignites_ground
	bullet.damage = bullet_damage
	bullet.max_range = max_range
	bullet.explodes = explodes
	bullet.explosion_level = explosion_level
	bullet.pierces = pierces
	bullet.accel = accel
	bullet.max_speed = max_speed
	# Weapon level 3 player tanks can destroy steel
	if self is PlayerTank and self.weapon_level >= 3:
		bullet.can_destroy_steel = true
	bullet.global_position = spawn_position

	# Set collision layers based on owner
	if bullet.is_player_bullet:
		bullet.set_collision_layer_value(5, true)
		bullet.set_collision_mask_value(1, true)  # walls
		bullet.set_collision_mask_value(4, true)  # enemy tanks
		bullet.set_collision_mask_value(6, true)  # enemy bullets
		bullet.set_collision_mask_value(8, true)  # eagle
	else:
		bullet.set_collision_layer_value(6, true)
		bullet.set_collision_mask_value(1, true)  # walls
		bullet.set_collision_mask_value(3, true)  # player tanks
		bullet.set_collision_mask_value(5, true)  # player bullets
		bullet.set_collision_mask_value(8, true)  # eagle

	var bullets_container = get_tree().get_first_node_in_group("bullets_container")
	if bullets_container:
		bullets_container.add_child(bullet)
	else:
		get_tree().current_scene.add_child(bullet)

func _get_firing_right_vector() -> Vector2:
	return Vector2(-current_direction.y, current_direction.x)

func _get_single_row_collision_offsets(row_offset: float) -> Array[float]:
	if is_zero_approx(row_offset):
		return MID_ROW_COLLISION_OFFSETS
	return [0.0]

func _spawn_single_row_bullet(
	row_offset: float,
	bullet_speed_override: float = -1.0,
	bullet_visual_style: String = "regular"
) -> void:
	var spawn_position := global_position + current_direction * (TANK_SIZE * 0.5)
	spawn_position += _get_firing_right_vector() * row_offset
	_spawn_bullet(
		spawn_position,
		[0.0],
		_get_single_row_collision_offsets(row_offset),
		bullet_speed_override,
		bullet_visual_style
	)

## Fire a single centred fire bullet. [param config] comes from
## CookieData.get_weapon_fire_config("fire", level).
func _spawn_fire_bullet(config: Dictionary) -> void:
	var spawn_position := global_position + current_direction * (TANK_SIZE * 0.5)
	active_fire_bullets += 1
	# Two collision lanes so a wall hit damages the full 2-tile tank width.
	_spawn_bullet(
		spawn_position,
		[0.0],
		DEFAULT_BULLET_LANE_OFFSETS,
		config.get("speed", 500.0),
		"fire",
		true,
		int(config.get("damage", 1)),
		float(config.get("range_px", 480.0))
	)

## Fire a single centred explosion bullet. [param config] comes from
## CookieData.get_weapon_fire_config("explosion", level).
func _spawn_explosion_bullet(config: Dictionary) -> void:
	var spawn_position := global_position + current_direction * (TANK_SIZE * 0.5)
	active_explosion_bullets += 1
	# Two collision lanes so a wall hit damages the full 2-tile tank width.
	_spawn_bullet(
		spawn_position,
		[0.0],
		DEFAULT_BULLET_LANE_OFFSETS,
		config.get("speed", 650.0),
		"explosion",
		false,
		int(config.get("damage", 1)),
		-1.0,
		true,
		int(config.get("level", 0))
	)

## Fire a single AP shell. [param config] comes from
## CookieData.get_weapon_fire_config("ap", level). Accelerating pierce bullet
## whose damage is a pool it spends through tanks and walls.
func _spawn_ap_bullet(config: Dictionary) -> void:
	var spawn_position := global_position + current_direction * (TANK_SIZE * 0.5)
	active_ap_bullets += 1
	# Two collision lanes so the shell drills a 2-tile-wide channel — wide enough
	# for the tank (2x2 tiles) to drive through the wall it destroyed.
	_spawn_bullet(
		spawn_position,
		[0.0],
		DEFAULT_BULLET_LANE_OFFSETS,
		float(config.get("speed", 222.0)),
		"ap",
		false,
		int(config.get("damage", 8)),
		-1.0,
		false,
		0,
		true,
		float(config.get("accel", 889.0)),
		float(config.get("max_speed", 667.0))
	)

## Called by an AP shell when it hits a shielded front with a strong pool.
## Overridden by PlayerTank/EnemyTank to strip the moon shield + grant grace.
func break_moon_shield_grace() -> void:
	pass

# --- Mine weapon: laying, slow debuff, and the level 3/4 fly effect ---

## Lay a mine of [param level] (1-4) on a tile behind the tank. Returns true if laid.
func _place_mine(level: int) -> bool:
	var lm := _get_level_manager()
	if not lm:
		return false
	return lm.try_place_mine(global_position, current_direction, level, is_in_group("players"))

func apply_mine_slow() -> void:
	is_mine_slowed = true

func clear_mine_slow() -> void:
	is_mine_slowed = false

## Thrown into the air by a level 3/4 mine: helpless, uncollidable, spinning arc.
func launch_mine_fly(mine_level: int) -> void:
	if is_flying:
		return
	is_flying = true
	_fly_level = mine_level
	_fly_t = 0.0
	_fly_duration = 1.2 if mine_level == 3 else 1.5
	# Thrown to a random spot anywhere on the playfield.
	var target := Vector2(
		randf_range(PLAYFIELD_MIN_X, PLAYFIELD_MAX_X),
		randf_range(PLAYFIELD_MIN_Y, PLAYFIELD_MAX_Y))
	_fly_horiz_vel = (target - global_position) / _fly_duration
	# Longer throws arc higher, so the flight reads as a real launch across the map.
	var throw_dist := global_position.distance_to(target)
	_fly_peak_height = clampf(throw_dist * 0.18, 40.0, 160.0)
	_fly_peak_scale = 1.6 if mine_level == 3 else 2.6
	var revs := 2.3 if mine_level == 3 else 4.3
	_fly_spin_speed = (1.0 if randf() < 0.5 else -1.0) * revs * TAU / _fly_duration
	if sprite:
		_fly_base_sprite_scale = sprite.scale
	# Become helpless: can't be hit, can't collide, can't trigger anything.
	_fly_saved_layer = collision_layer
	collision_layer = 0
	velocity = Vector2.ZERO

## Drive the parabolic spin arc. Player/enemy _physics_process delegate here while
## airborne. Altitude is faked with sprite offset + scale; the node drifts flat.
func _update_flying(delta: float) -> void:
	_fly_t += delta
	var t: float = _fly_t / _fly_duration
	if t >= 1.0:
		_land_from_flight()
		return
	global_position += _fly_horiz_vel * delta
	clamp_to_playfield()
	var alt: float = 4.0 * t * (1.0 - t)  # 0 -> 1 (apex) -> 0
	if sprite:
		sprite.position = Vector2(0.0, -_fly_peak_height * alt)
		sprite.scale = _fly_base_sprite_scale * (1.0 + _fly_peak_scale * alt)
		sprite.rotation += _fly_spin_speed * delta

func _land_from_flight() -> void:
	is_flying = false
	if sprite:
		sprite.position = Vector2.ZERO
		sprite.scale = _fly_base_sprite_scale
	# Land facing a random cardinal (wherever the spin stopped).
	current_direction = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT].pick_random()
	_update_sprite_direction()
	collision_layer = _fly_saved_layer
	velocity = Vector2.ZERO
	# Second (neutral) blast at the landing tile — hits the victim AND nearby tanks.
	var lm := _get_level_manager()
	if lm:
		lm.spawn_explosion_blast(global_position, clampi(_fly_level - 1, 0, 3), is_in_group("players"), true)

func _get_level_manager() -> LevelManager:
	var game := get_tree().get_first_node_in_group("game")
	if game and game.has_method("get_level_manager"):
		return game.get_level_manager()
	return null

func on_bullet_destroyed() -> void:
	active_bullets = maxi(active_bullets - 1, 0)

func on_fire_bullet_destroyed() -> void:
	active_fire_bullets = maxi(active_fire_bullets - 1, 0)

func on_explosion_bullet_destroyed() -> void:
	active_explosion_bullets = maxi(active_explosion_bullets - 1, 0)

func on_ap_bullet_destroyed() -> void:
	active_ap_bullets = maxi(active_ap_bullets - 1, 0)

func take_damage() -> void:
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	health -= 1
	if health <= 0:
		destroy()

func destroy() -> void:
	_spawn_explosion()
	queue_free()

func _spawn_explosion() -> void:
	var explosion_scene := preload("res://scenes/effects/explosion.tscn")
	var explosion := explosion_scene.instantiate()
	explosion.global_position = global_position
	explosion.scale = Vector2(2, 2)  # Larger explosion for 2x2 tanks
	var effects_container = get_tree().get_first_node_in_group("effects_container")
	if effects_container:
		effects_container.add_child(explosion)
	else:
		get_tree().current_scene.add_child(explosion)

func clamp_to_playfield() -> void:
	global_position.x = clampf(global_position.x, PLAYFIELD_MIN_X, PLAYFIELD_MAX_X)
	global_position.y = clampf(global_position.y, PLAYFIELD_MIN_Y, PLAYFIELD_MAX_Y)

func _on_shoot_cooldown_timeout() -> void:
	can_shoot = true
