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
## Half the tanks' 60x60 hitbox (see the tank scenes), less half a pixel so a
## lane stays strictly inside the body.
const BODY_EDGE: float = 29.5
## Perpendicular offsets spanning a tank's whole hitbox. A tank snapped to a
## half-tile straddles three tile columns, so "which tiles is this tank up
## against" needs all three: +/-16 misses the outer column on one side, which
## left tanks walled in by a brick their own shots never reached.
const BODY_LANE_OFFSETS: Array[float] = [-BODY_EDGE, 0.0, BODY_EDGE]
## Side of every tank's square hitbox (the tank scenes' collision shapes).
const HITBOX_SIZE: float = 60.0

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

## The player whose weapon deals the hit about to land: a weapon sets it just
## before calling take_damage(), which reads and clears it. -1 for an enemy's
## weapon, grass fire and anything else no player owns. It decides who is
## credited with the hit and with a kill.
var hit_by: int = -1

# Red "hit" flash, shared by every damage source (bullets and all special weapons).
# Longer than an explosion/mine blast (~0.22s) so the flash stays visible after
# the fireball fades.
const DAMAGE_FLASH_DURATION: float = 0.35
var _damage_flash_timer: float = 0.0
## No blast hurts it while this is above 0, s (ExplosionBlast.BLAST_IMMUNITY).
var blast_immunity: float = 0.0

# Mine weapon effects on this tank.
var is_mine_slowed: bool = false        # quarter speed until an add-on or MAX pickup, or death
var is_flying: bool = false             # thrown into the air by a level 2/3 mine — helpless
var _fly_landing_hit: int = 0           # HP the throwing mine costs when the tank comes down
var _fly_hit_by: int = -1               # whose mine threw it (-1: an enemy's)
var _fly_velocity: Vector2 = Vector2.ZERO   # px/s, away from the mine
var _fly_altitude: float = 0.0          # the sprite draws at (altitude + 1) times its size
var _fly_climb: float = 0.0             # altitude gained per time unit
var _fly_angle: float = 0.0             # tumble so far, in 1/256 turns
var _fly_spin: float = 0.0              # 1/256 turns per time unit
var _fly_spin_accel: float = 0.0
var _fly_base_sprite_scale: Vector2 = Vector2.ONE
var _fly_base_rotation: float = 0.0
var _fly_saved_layer: int = 0
var _fly_saved_z: int = 0

## The original quartered a mined tank's move speed (0x00492f24).
const MINE_SLOW_FACTOR: float = 0.25

## The mine flight, ported from the original's TFlyingTank (0x0049a5ec, DoMove
## 0x0049a7f4). Its clock ran in units of 1000 engine ticks, 0.75 s.
const FLY_TIME_UNIT: float = 0.75
## Launch speed: this many times the tank's offset from the mine centre, per unit.
const FLY_THROW: float = 5.0
## Altitude climbs at (mine level + 2) per unit to begin with, and falls at this.
const FLY_GRAVITY: float = -5.0
## The tumble starts at 200 x the mine level in 1/256 turns per unit, and slows.
const FLY_SPIN_PER_LEVEL: float = 200.0
const FLY_SPIN_SLOWDOWN: float = 55.0
## Airborne tanks draw over grass, blasts and everything else on the field.
const FLY_Z_INDEX: int = 30
## The original's facing numbers: 0 up, 1 right, 2 down, 3 left.
const FACINGS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

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
	add_to_group(NetWorld.GROUP)
	if shoot_cooldown:
		shoot_cooldown.timeout.connect(_on_shoot_cooldown_timeout)

func _process(delta: float) -> void:
	if fire_immunity_timer > 0.0:
		fire_immunity_timer -= delta
	_animate_addons(delta)
	_layout_addons()
	_tick_damage_flash(delta)
	if blast_immunity > 0.0:
		blast_immunity -= delta
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
## The original stepped both rings 3 frames per 1000 ticks (0.75 s).
const ADDON_ANIM_FRAME_DUR: float = 0.25

# --- Add-on placement. Tank.exe drew every add-on at the tank's own spot and
# size, under the body, pushed along the facing (0x00493720). In original px,
# doubled here: the moon shield 4 px ahead, the memory-save ring 2 px behind,
# and the anti-water ring and anti-ice wings 2 px behind while driving but 1 px
# when still or on ice. The wings and the shield have a drawn frame per facing;
# the rings stay upright. A tank in the air (a mine flight) shows none.
const ADDON_PUSH: Dictionary = {
	"moon-shield": 8.0, "memory-save": -4.0, "anti-water": -4.0, "anti-ice": -4.0,
}
const ADDON_PUSH_EASED: float = -2.0
const ADDONS_EASED_WHEN_IDLE: Array = ["anti-water", "anti-ice"]
const UPRIGHT_ADDONS: Array = ["anti-water", "memory-save"]
const FACING_ROTATIONS: Array[float] = [0.0, PI / 2, PI, -PI / 2]

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

## Marks [param sprite] as the [param addon_name] add-on, for _layout_addons.
func tag_addon_sprite(sprite: Sprite2D, addon_name: String) -> void:
	sprite.set_meta(&"addon", addon_name)

func _layout_addons() -> void:
	var facing := maxi(FACINGS.find(current_direction), 0)
	var eased := -1  # worked out once, when an add-on first needs it
	for child in get_children():
		var spr := child as Sprite2D
		if spr == null or not spr.has_meta(&"addon"):
			continue
		var addon_name: String = spr.get_meta(&"addon")
		spr.visible = not is_flying
		var frames: Array = ThemeManager.get_addon_facing_textures(addon_name)
		if frames.size() == FACINGS.size():
			spr.texture = frames[facing]
			spr.rotation = 0.0
		elif addon_name in UPRIGHT_ADDONS:
			spr.rotation = 0.0
		else:
			spr.rotation = FACING_ROTATIONS[facing]  # only one frame: turn it
		var push: float = ADDON_PUSH.get(addon_name, 0.0)
		if addon_name in ADDONS_EASED_WHEN_IDLE:
			if eased < 0:
				eased = 1 if velocity == Vector2.ZERO or _on_ice_terrain() else 0
			if eased == 1:
				push = ADDON_PUSH_EASED
		spr.position = current_direction * push

## Two or more of the four tiles under the tank iced over, as the original
## judged it (TTankSprite's DoMove, 0x004923cd): for its controls on ice and
## the add-on push.
func _on_ice_terrain() -> bool:
	var lm := _get_level_manager()
	return lm != null and lm.ice_tiles_under(global_position) >= 2

# --- On ice a tank answers its controls 8 times slower, as the original's
# (TTankSprite's DoCommand, 0x0049180c; docs/ice_original_spec.md). Told its
# own way, it speeds up by an eighth of its usual step; told to stop, it brakes
# by an eighth of its usual two; told another way, it brakes so, sliding on as
# it was, till it's down to the original's speed 200, then turns with what's
# left below that. Its usual step is 60/650 of its top speed every 0.03 s.
# Off ice the remake's tanks answer at once. ---

## The original's speed 200 (0.4 of its px a 15 ms frame), px/s: on ice a tank
## turns only once it's down to this.
const ICE_TURN_SPEED := 200.0 / 500.0 * 2.0 / 0.015
## An eighth of its usual step (60/650 of its top speed every 0.03 s), as a
## share of its top speed a second.
const ICE_STEP := 60.0 / 650.0 / 8.0 / 0.03
## Its speed along its facing, px/s: kept as it drives, so it slides on onto
## ice at the speed it had.
var ice_speed := 0.0

## On ice: its velocity, told [param wanted] (a facing, or ZERO to stop) for
## [param delta], up to [param top] px/s (slowed by a mine, say); its step goes
## by [param full], its top speed unslowed. It turns (_turn_to) only once slow
## enough.
func _ice_steer(wanted: Vector2, top: float, full: float, delta: float) -> Vector2:
	var step := full * ICE_STEP * delta
	if wanted == Vector2.ZERO:
		ice_speed = maxf(ice_speed - 2.0 * step, 0.0)
	elif wanted != current_direction:
		ice_speed -= 2.0 * step
		if ice_speed <= ICE_TURN_SPEED:
			_turn_to(wanted)
			ice_speed = ICE_TURN_SPEED - ice_speed
	else:
		ice_speed = minf(ice_speed + step, top)
	return current_direction * ice_speed

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
static var _thaw_frames: Array[Texture2D] = []

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

## The frost without its ring (Tank_T row 3): a hold running out.
static func get_thaw_frames() -> Array[Texture2D]:
	if _thaw_frames.is_empty():
		_thaw_frames = _load_fx_frames("thaw/thaw", 8)
	return _thaw_frames

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
func on_fire_contact(from_player_fire: bool, reburn: float, hurts_both: bool = false, owner_id: int = -1) -> void:
	if fire_immunity_timer > 0.0:
		return
	# Grass fire is neutral and burns everyone; weapon fire never burns its own side.
	if not hurts_both:
		var is_player := is_in_group("players")
		if from_player_fire == is_player:
			return  # player fire never burns players; enemy fire never burns enemies
	fire_immunity_timer = reburn
	hit_by = owner_id
	take_damage()

func try_move(new_direction: Vector2) -> void:
	if new_direction != current_direction:
		_turn_to(new_direction)
	velocity = current_direction * move_speed * (MINE_SLOW_FACTOR if is_mine_slowed else 1.0)
	is_moving = true

## Faces [param new_direction], snapped to the grid across it.
func _turn_to(new_direction: Vector2) -> void:
	current_direction = new_direction
	# Snap perpendicular axis to grid
	if new_direction.x != 0:
		position.y = round(position.y / HALF_TILE) * HALF_TILE
	else:
		position.x = round(position.x / HALF_TILE) * HALF_TILE
	_update_sprite_direction()

func stop_moving() -> void:
	velocity = Vector2.ZERO
	is_moving = false
	ice_speed = 0.0

## One step of a tank held by "Hold Enemy". The hold stops a tank's commands,
## never its motion: one that was moving glides on at the speed it had, straight
## ahead, until a wall, water or a tank of [param opponents] blocks it, then
## stays put for the rest of the hold. No driving, turning or firing meanwhile
## (Tank.exe runs its movement step on, 0x00492244, while the hold skips the
## commands that would brake it, 0x00494d08 / 0x004949fd).
func glide_while_held(opponents: String) -> void:
	if velocity == Vector2.ZERO:
		return
	var motion := velocity * get_physics_process_delta_time()
	if _opponent_ahead(opponents, velocity.normalized(), maxf(motion.length(), 2.0)):
		stop_moving()
		return
	# Straight on, never sliding along what it meets: the original never moved a
	# tank sideways. Blocked, it stays there for the rest of the hold.
	if move_and_collide(motion):
		stop_moving()
	clamp_to_playfield()

## True if a tank from [param group] ("players" or "enemies") is in the way of a
## [param distance] px step along [param direction]. Players and bots never
## collide physically (a bot must not shove the player), so they stop for each
## other here instead. Only a tank AHEAD counts: two tanks that already overlap,
## which a turn's grid snap, a revive or a mine landing can cause, can always
## drive apart. A physics test move from inside the overlap hits in every
## direction and left both tanks frozen.
func _opponent_ahead(group: String, direction: Vector2, distance: float) -> bool:
	var across := Vector2(-direction.y, direction.x)
	for node in get_tree().get_nodes_in_group(group):
		var other := node as BaseTank
		if other == null or other == self or not other.is_solid():
			continue  # airborne or still materializing: nothing to bump into
		var offset: Vector2 = other.global_position - global_position
		var ahead: float = offset.dot(direction)
		if ahead > 0.0 and ahead - HITBOX_SIZE < distance \
				and absf(offset.dot(across)) < HITBOX_SIZE:
			return true
	return false

## Something to bump into: not airborne, not still materializing. (A client's
## tanks show the host's and touch nothing, so there their state tells.)
func is_solid() -> bool:
	if net_gone:
		return false
	if Net.is_client():
		return not is_materializing and not is_flying
	return collision_layer != 0

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
	_layout_addons()

func shoot() -> void:
	if active_bullets >= max_bullets or not can_shoot:
		return
	_begin_shot()
	_spawn_bullet(
		_shot_origin() + _shot_facing() * (TANK_SIZE * 0.5),
		DEFAULT_BULLET_LANE_OFFSETS,
		DEFAULT_BULLET_LANE_OFFSETS
	)

## Where this tank's shots leave from, which way they go, from which row
## (given [param row_offset], across the barrel) and with what number: its own
## place and facing, that row, none. (A client's tank on the host fires that
## client's own shots as it fired them, and tells it so: PlayerTank.)
func _shot_origin() -> Vector2:
	return global_position

func _shot_facing() -> Vector2:
	return current_direction

func _shot_row(row_offset: float) -> float:
	return row_offset

func _shot_number() -> int:
	return -1

## Host: for a client's own shot, which client's screen it's judged by as it
## flies (Bullet.net_view); [] for any other.
func _shot_view() -> Array:
	return []

## On a client: [param shell], a shot of this machine's own tank, is about to
## fly here as a ghost (PlayerTank tells the host).
func _net_ghost_fired(_shell: Bullet) -> void:
	pass

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
	bullet.direction = _shot_facing()
	bullet.speed = bullet_speed_override if bullet_speed_override > 0.0 else bullet_speed
	bullet.owner_tank = self
	bullet.is_player_bullet = is_in_group("players")
	bullet.owner_player = get_player_index()
	bullet.visual_lane_offsets = visual_lane_offsets.duplicate()
	bullet.collision_lane_offsets = collision_lane_offsets.duplicate()
	# A tank-wide shot tests the tile grid across the shooter's whole body, so it
	# can always clear what the tank is blocked by. Its hitbox against tanks keeps
	# the narrower collision lanes, so it hits tanks exactly as before.
	if collision_lane_offsets.size() > 1:
		bullet.tile_lane_offsets = BODY_LANE_OFFSETS
	bullet.visual_style = bullet_visual_style
	bullet.ignites_ground = ignites_ground
	bullet.damage = bullet_damage
	bullet.max_range = max_range
	bullet.explodes = explodes
	bullet.explosion_level = explosion_level
	bullet.pierces = pierces
	bullet.accel = accel
	bullet.max_speed = max_speed
	bullet.net_shot = _shot_number()
	bullet.net_view = _shot_view()
	bullet.global_position = spawn_position

	# On a client this is its own tank's shot, fired here at once (lag
	# compensation): a ghost of the host's shell to come, touching nothing.
	if Net.is_client():
		var world := NetClientWorld.of(get_tree())
		if world:
			_net_ghost_fired(bullet)
			world.add_ghost(bullet)
		else:
			bullet.free()
		return

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
	var facing := _shot_facing()
	return Vector2(-facing.y, facing.x)

func _get_single_row_collision_offsets(row_offset: float) -> Array[float]:
	if is_zero_approx(row_offset):
		return MID_ROW_COLLISION_OFFSETS
	return [0.0]

func _spawn_single_row_bullet(
	row_offset: float,
	bullet_speed_override: float = -1.0,
	bullet_visual_style: String = "regular"
) -> void:
	row_offset = _shot_row(row_offset)
	var spawn_position := _shot_origin() + _shot_facing() * (TANK_SIZE * 0.5)
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
	var spawn_position := _shot_origin() + _shot_facing() * (TANK_SIZE * 0.5)
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
	var spawn_position := _shot_origin() + _shot_facing() * (TANK_SIZE * 0.5)
	active_explosion_bullets += 1
	# Two collision lanes so a wall hit damages the full 2-tile tank width.
	_spawn_bullet(
		spawn_position,
		[0.0],
		DEFAULT_BULLET_LANE_OFFSETS,
		config.get("speed", 355.6),
		"explosion",
		false,
		int(config.get("damage", 1)),
		-1.0,
		true,
		int(config.get("level", 0)),
		false,
		float(config.get("accel", 0.0)),
		float(config.get("max_speed", 0.0))
	)

## Fire a single AP shell. [param config] comes from
## CookieData.get_weapon_fire_config("ap", level). Accelerating pierce bullet
## whose damage is a pool it spends through tanks and walls.
func _spawn_ap_bullet(config: Dictionary) -> void:
	var spawn_position := _shot_origin() + _shot_facing() * (TANK_SIZE * 0.5)
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

# --- Mine weapon: laying, slow debuff, and the level 2/3 fly effect ---

## Lay a level-[param level] (0-3) mine on the ring of spots around the tank,
## behind it first. Returns true if laid.
func _place_mine(level: int) -> bool:
	var lm := _get_level_manager()
	if not lm:
		return false
	return lm.try_place_mine(self, level)

## The player driving this tank (0 or 1), or -1 for an enemy.
func get_player_index() -> int:
	return -1

## Gun upgrade level 0-3. Sets the level of the mines this tank lays and the
## strength of the blast when it lands from a mine flight.
func get_gun_level() -> int:
	return 0

## The add-ons this tank carries: "anti-water", "anti-ice", "moon-shield",
## "memory-save". The mine rules key off them.
func get_addon_names() -> Array:
	return []

## A mine flight tears [param addon_name] off. Nothing drops: the original just
## cleared the tank's add-on.
func lose_addon(_addon_name: String) -> void:
	pass

## True while the tank cannot be hurt (spawn protection, the helmet).
func is_invulnerable() -> bool:
	return false

func apply_mine_slow() -> void:
	is_mine_slowed = true

func clear_mine_slow() -> void:
	is_mine_slowed = false

## Thrown into the air by a level 2/3 mine: helpless, uncollidable, tumbling.
## The throw carries the tank away from [param mine_center] at five times its
## offset from it per time unit, so a tank that drove onto the mine flies back
## the way it came: about 11 tiles from a level-2 mine, 14 from a level-3. The
## flight lasts 1.2 s or 1.5 s, until the altitude comes back down to zero.
## Thrown by a level-[param mine_level] mine centred at [param mine_center]. The
## mine's hit waits for the landing: [param landing_hit] HP, credited to
## [param owner_id] (see _take_mine_landing_hit).
func launch_mine_fly(mine_level: int, mine_center: Vector2, landing_hit: int = 0, owner_id: int = -1) -> void:
	if is_flying:
		return
	is_flying = true
	_fly_landing_hit = landing_hit
	_fly_hit_by = owner_id
	_fly_velocity = (global_position - mine_center) * FLY_THROW / FLY_TIME_UNIT
	_fly_altitude = 0.0
	_fly_climb = mine_level + 2.0
	_fly_angle = 0.0
	# A coin flip picks which way it tumbles.
	var way := 1.0 if randi() % 2 == 1 else -1.0
	_fly_spin = way * FLY_SPIN_PER_LEVEL * mine_level
	_fly_spin_accel = -way * FLY_SPIN_SLOWDOWN
	if sprite:
		_fly_base_sprite_scale = sprite.scale
		_fly_base_rotation = sprite.rotation
	# Become helpless: can't be hit, can't collide, can't trigger anything.
	_fly_saved_layer = collision_layer
	collision_layer = 0
	_fly_saved_z = z_index
	z_index = FLY_Z_INDEX
	velocity = Vector2.ZERO

## One step of the flight, integrated as the original did. Player/enemy
## _physics_process delegate here while airborne. Height shows only as size:
## the sprite never lifts off its spot.
func _update_flying(delta: float) -> void:
	var dt := delta / FLY_TIME_UNIT
	_fly_altitude += _fly_climb * dt
	_fly_climb += FLY_GRAVITY * dt
	_fly_angle += _fly_spin * dt
	_fly_spin += _fly_spin_accel * dt
	# The original also let a high tank drift up the screen by its altitude,
	# which adds up to a few pixels over a flight.
	global_position += _fly_velocity * delta + Vector2(0.0, -2.0 * _fly_altitude * dt)
	clamp_to_playfield()
	if _fly_altitude <= 0.0:
		_land_from_flight()
		return
	if sprite:
		sprite.scale = _fly_base_sprite_scale * (1.0 + _fly_altitude)
		sprite.rotation = _fly_base_rotation + _fly_angle * TAU / 256.0

func _land_from_flight() -> void:
	# While it still counts as airborne, so a player loses no level for it and
	# starts no hit grace.
	_take_mine_landing_hit()
	is_flying = false
	ice_speed = 0.0
	if sprite:
		sprite.position = Vector2.ZERO
		sprite.scale = _fly_base_sprite_scale
	# It lands facing where the tumble stopped, rounded back to a quarter turn.
	var quarter_turns := posmod(roundi(_fly_angle), 256) >> 6
	var facing := maxi(FACINGS.find(current_direction), 0)
	current_direction = FACINGS[(facing + quarter_turns) % FACINGS.size()]
	_update_sprite_direction()
	collision_layer = _fly_saved_layer
	z_index = _fly_saved_z
	velocity = Vector2.ZERO
	# Second (neutral) blast at the landing tile — hits the victim AND nearby
	# tanks. Its strength is the victim's own gun level, not the mine's.
	var lm := _get_level_manager()
	if lm:
		lm.spawn_explosion_blast(global_position, get_gun_level(), is_in_group("players"), true, -1, false,
				ExplosionBlast.TANK_SIZE)

## The throwing mine's hit, on landing (Sean's rule, 2026-09-24; the original hit
## the tank as it was thrown). Unless the tank is invincible by now, it loses its
## moon shield, or else another add-on, and the HP.
func _take_mine_landing_hit() -> void:
	var points := _fly_landing_hit
	_fly_landing_hit = 0
	if points <= 0 or is_invulnerable():
		return
	var addons := get_addon_names()
	if "moon-shield" in addons:
		lose_addon("moon-shield")
	elif not addons.is_empty():
		lose_addon(addons[0])
	for i in points:
		if health <= 0:
			return
		hit_by = _fly_hit_by
		take_damage()

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
	take_hit(1)

## One hit of [param points] (the original's Damage, 0x00492640): the health
## goes by that much at once, with one flash and one sound, or the tank's end.
func take_hit(points: int) -> void:
	hit_by = -1
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	health -= points
	if health <= 0:
		destroy()
	else:
		# The original only sounded a hit the tank actually survived; a fatal
		# hit is covered by the destruction sound instead.
		SoundManager.play(&"tank_hit", _hit_sound_tank())

## Online: whose tank the hit sound is (a player's number), or -1.
func _hit_sound_tank() -> int:
	return -1

## Online, on a client: how long the tank flashes red, from the host's state
## of it, [param host] (PlayerTank keeps a hit it showed at once, and leaves out
## the host's flash of that same hit).
func _shown_flash(host: float) -> float:
	return host

func destroy() -> void:
	_spawn_explosion()
	queue_free()

func _spawn_explosion() -> void:
	var effects_container = get_tree().get_first_node_in_group("effects_container")
	var parent: Node = effects_container if effects_container else get_tree().current_scene
	# A theme with the original's explosion strip plays it (Tank.exe turned a dead
	# tank into image 9, _B_48); otherwise the built-in burst.
	var frames: Array = ThemeManager.get_tank_explode_frames()
	if not frames.is_empty():
		HitEffect.spawn(parent, global_position, frames, ThemeManager.get_tank_explode_duration(), "tank")
		return
	var explosion_scene := preload("res://scenes/effects/explosion.tscn")
	var explosion := explosion_scene.instantiate()
	explosion.global_position = global_position
	explosion.scale = Vector2(2, 2)  # Larger explosion for 2x2 tanks
	parent.add_child(explosion)
	NetHostWorld.record(NetWorld.EV_EXPLOSION, [global_position.x, global_position.y, 2.0])

# =====================================================================
# Online (NetWorld): a tank's look, streamed from the host to its clients.
# State: [x, y, facing 0-3, flags, damage flash left, flight altitude, flight
# tumble, health, add-on bits] and a subclass's own after those.
# =====================================================================

const NET_MOVING := 1
const NET_MATERIALIZING := 2
const NET_FLYING := 4
## Bits past these are a subclass's.
const NET_OWN_FLAGS := 8
const NET_ADDON_BITS: Dictionary = {
	"moon-shield": 1, "anti-water": 2, "anti-ice": 4, "memory-save": 8,
}
## The flight's altitude and tumble glide between snapshots.
const NET_GLIDES: Array[int] = [5, 6]

func net_spawn_args() -> Array:
	return []

func net_state() -> Array:
	var flags := 0
	if velocity != Vector2.ZERO:
		flags |= NET_MOVING
	if is_materializing:
		flags |= NET_MATERIALIZING
	if is_flying:
		flags |= NET_FLYING
	var addon_bits := 0
	for addon_name: String in get_addon_names():
		addon_bits |= int(NET_ADDON_BITS.get(addon_name, 0))
	return [global_position.x, global_position.y, maxi(FACINGS.find(current_direction), 0), flags,
			snappedf(maxf(_damage_flash_timer, 0.0), 0.01),
			_fly_altitude if is_flying else 0.0, _fly_angle if is_flying else 0.0,
			health, addon_bits]

## A client's tank takes on the host's: facing, whether it drives (the add-ons
## sit differently still), hidden while it materializes, the flight's size and
## tumble, the red hit flash and its health. Its own _process draws the rest.
func net_apply(state: Array) -> void:
	var flags := int(state[3])
	if not _net_drives_itself():
		var facing: Vector2 = FACINGS[clampi(int(state[2]), 0, FACINGS.size() - 1)]
		if facing != current_direction:
			current_direction = facing
			if not is_flying:
				_update_sprite_direction()
		velocity = current_direction if flags & NET_MOVING else Vector2.ZERO
	var materializing := flags & NET_MATERIALIZING != 0
	if materializing != is_materializing:
		is_materializing = materializing
		_materialize_timer = INF if materializing else 0.0  # the host says when
		visible = not materializing
	var flying := flags & NET_FLYING != 0
	if flying and not is_flying:
		is_flying = true
		if sprite:
			_fly_base_sprite_scale = sprite.scale
			_fly_base_rotation = sprite.rotation
		_fly_saved_z = z_index
		z_index = FLY_Z_INDEX
	elif not flying and is_flying:
		is_flying = false
		z_index = _fly_saved_z
		if sprite:
			sprite.scale = _fly_base_sprite_scale
			sprite.position = Vector2.ZERO
		_update_sprite_direction()
	if is_flying and sprite:
		sprite.scale = _fly_base_sprite_scale * (1.0 + float(state[5]))
		sprite.rotation = _fly_base_rotation + float(state[6]) * TAU / 256.0
	var flash := _shown_flash(float(state[4]))
	if flash <= 0.0 and _damage_flash_timer > 0.0 and sprite:
		sprite.modulate = Color.WHITE
	_damage_flash_timer = flash
	health = int(state[7])
	_net_apply_addons(int(state[8]))

## The add-ons named by [param bits] (NET_ADDON_BITS), put on and taken off.
func _net_apply_addons(_bits: int) -> void:
	pass

## On a client: shown dead already, its death guessed from this machine's own
## shot before the host's word of it (NetClientWorld.guess_kill): hidden, and
## nothing here meets it, until the host's word settles it.
var net_gone := false

## A client's tank this machine drives itself (PlayerTank): its facing and
## motion are its own, not the host's.
func _net_drives_itself() -> bool:
	return false

## Which add-on names [param bits] holds.
static func net_addon_names(bits: int) -> Array[String]:
	var names: Array[String] = []
	for addon_name: String in NET_ADDON_BITS:
		if bits & int(NET_ADDON_BITS[addon_name]):
			names.append(addon_name)
	return names

func clamp_to_playfield() -> void:
	global_position.x = clampf(global_position.x, PLAYFIELD_MIN_X, PLAYFIELD_MAX_X)
	global_position.y = clampf(global_position.y, PLAYFIELD_MIN_Y, PLAYFIELD_MAX_Y)

func _on_shoot_cooldown_timeout() -> void:
	can_shoot = true
