class_name EnemyTank
extends BaseTank

# Tank type ID (1-24) matching tank_<id>.png sprites and Stage.dat EnemyCount values
@export var tank_type_id: int = 1
@export var points_value: int = 100

var special_weapon_type: String = "none"
var special_weapon_level: int = 0
## The gun level its type came on the field with, at the difficulty then. A hit
## it survives knocks back out what items gave it above this; a difficulty
## changed mid-stage leaves it be, so lowering one shakes no gun items loose.
var _base_weapon_level: int = 0
var _shoot_cooldown: float = 0.0
var _hits_taken: int = 0
## The player credited with destroying this tank: the owner of the weapon that
## dealt its last point (-1: an enemy's weapon, grass fire, or nobody).
var killed_by: int = -1
var _rapid_special_fire_step: int = 0

# --- How it moves: Tank.exe's TEnemyTank.Think (0x00494c38), rule for rule
# (docs/enemy_ai_original_spec.md). Every AI step it decides what to do: drive
# up, right, down or left, or stop. A hunter takes the cheapest way to the base
# on the level's EnemyRoutes map, deciding at each grid line it comes to and
# whenever it stands; one cut off from the base wanders, as does any enemy that
# doesn't hunt. A moving tank keeps to the grid line across its way. How it
# fires is the remake's own (_fire_at_will). ---

## Told to stand (the other commands are BaseTank.FACINGS' indices).
const STOP := 4
## The original's AI step: every other 15 ms frame.
const AI_STEP := 0.03
## A hit it survives holds its course this long (the original's 250 ticks).
const HIT_HOLD := 0.1875
## A wanderer turns at random 1 step in this many, by difficulty (the original's
## f4, 0x004d2860): the upgraded type of each pair (an even id) as is, the
## other half as long again.
const TURN_PERIOD: Array[int] = [80, 65, 50, 40, 32, 25]
## It fires faster this near the base (~6 tiles).
const EAGLE_ATTACK_RANGE: float = 192.0

## Every enemy hunts the base here, as in the remake's AI before (Sean kept it,
## 2026-09-25). The original rolled it once per enemy as it came on, by the
## difficulty and its gun (docs/enemy_ai_original_spec.md section 4.1).
var hunts_base := true
## What it's told to do: 0-3 drive that way (up, right, down, left), STOP stand.
## A new one starts with right, down, left or stop, which only rules out the
## way back for its first pick.
var _command := STOP
## It moved last frame (the original's speed above 0). Standing, it decides
## every step.
var _moving := false
var _ai_clock := 0.0
## After a hit it survives, it holds its course this long, deciding nothing.
var _hit_hold := 0.0
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
## With ENEMY MINES off, the mine tanks (21-24) fire rapid shells, at the gun
## levels of their rapid counterparts (5-8), sixteen types back.
const MINE_TO_RAPID_TYPE: int = 16
## The special weapons fired as shells: their tanks may have this many in
## flight. The plain gun, which mine tanks fire too, has one at a time.
const SHELL_SPECIALS: Array[String] = ["rapid", "fire", "explosion", "ap"]
const SHELL_SPECIAL_MAX_BULLETS: int = 12
const PLAIN_MAX_BULLETS: int = 1

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
	_apply_weapon()
	special_weapon_level = _base_weapon_level
	InputSettings.enemy_mines_changed.connect(_on_enemy_mines_changed)
	current_direction = Vector2.DOWN
	_command = randi_range(1, 4)  # the original's Random(4) + 1
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
	if Net.is_client():
		return  # the host drives every tank; this one only shows it
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

	_think(delta)
	# Told a way (or to stop): at once, but on ice (BaseTank._ice_steer).
	is_on_ice = not has_anti_ice and _on_ice_terrain()
	var top := move_speed * (MINE_SLOW_FACTOR if is_mine_slowed else 1.0)
	var wanted: Vector2 = FACINGS[_command] if _command != STOP else Vector2.ZERO
	if is_on_ice:
		velocity = _ice_steer(wanted, top, move_speed, delta)
		if velocity != Vector2.ZERO:
			_face(current_direction)  # on its grid line as it slides
	else:
		if wanted != Vector2.ZERO:
			_face(wanted)
		velocity = wanted * top
		ice_speed = velocity.length()

	# A player in the way: it stops (it never shoves one) and fires at them.
	var player_blocking := _is_player_ahead()
	if _shoot_cooldown <= 0:
		if player_blocking:
			_fire_weapon(0.3, 0.6)
		else:
			_fire_at_will()
	if player_blocking:
		velocity = Vector2.ZERO
		ice_speed = 0.0
	var from := global_position
	var meant := velocity.length() * delta  # (move_and_slide takes what a wall stops off velocity)
	move_and_slide()
	clamp_to_playfield()
	var moved := global_position.distance_to(from)
	_moving = moved > 0.01
	if is_on_ice and moved < meant * 0.5:
		ice_speed = 0.0  # stopped dead, as the original's

	# (Damage flash is handled centrally in BaseTank._process.)

func _is_player_ahead() -> bool:
	## Check if a player tank is blocking movement in the current direction.
	var lookahead := maxf(move_speed / float(Engine.physics_ticks_per_second), 2.0)
	return _opponent_ahead("players", current_direction, lookahead)

## The AI's clock: a step every AI_STEP of play, as the original's.
func _think(delta: float) -> void:
	_shoot_cooldown -= delta
	_hit_hold = maxf(_hit_hold - delta, 0.0)
	_ai_clock += delta
	while _ai_clock >= AI_STEP:
		_ai_clock -= AI_STEP
		_ai_step()

## One step of the original's think (0x00494d7c): a hunter that stands, or has
## come to the grid line it's driving to, takes the cheapest way on; one cut
## off from the base, or not hunting, wanders.
func _ai_step() -> void:
	var lm := _level()
	if lm == null or lm.routes == null:
		return
	var at := lm.routes.cell_of(global_position)
	if hunts_base and _hit_hold <= 0.0:
		if _moving and not _at_line(at):
			return  # on its way
		if _hunt(lm.routes, at):
			return
	_wander(at)

## On the half cell before the grid line it's driving to, the line itself
## included (0x00494d96): where a moving hunter decides. [param at] is its
## footprint's top-left map cell, rounded.
func _at_line(at: Vector2i) -> bool:
	var u := (global_position - _level().global_position) / TILE_SIZE
	if current_direction == Vector2.UP:
		return at.y <= u.y
	if current_direction == Vector2.RIGHT:
		return at.x >= u.x
	if current_direction == Vector2.LEFT:
		return at.x <= u.x
	return at.y >= u.y

## The hunter's choice (0x00494e19): of the footprint where it is and one cell
## each way, the one summing least on its map, a tie taken 1 time in 3; where
## it is, it stops. False if its footprint is cut off from the base.
func _hunt(routes: EnemyRoutes, at: Vector2i) -> bool:
	var m := routes.map_for(_map_mode())
	var best := EnemyRoutes.footprint(m, at.x, at.y)
	if best >= EnemyRoutes.HUNT_LIMIT:
		return false
	var choice := STOP
	for i in 4:
		var d: Vector2i = EnemyRoutes.DIRS[i]
		var sum := EnemyRoutes.footprint(m, at.x + d.x, at.y + d.y)
		if sum < best:
			best = sum
			choice = i
		elif sum == best and randi() % 3 == 0:
			choice = i
	_command = choice
	return true

## Which map it goes by: across water with anti-water, over ice unskidding with
## anti-ice (the original's one add-on, 0x00494e19).
func _map_mode() -> int:
	if "anti-water" in addons:
		return EnemyRoutes.Mode.AMPHI
	if has_anti_ice:
		return EnemyRoutes.Mode.ANTISKID
	return EnemyRoutes.Mode.NORMAL

## The wanderer's choice (0x00494ebd): standing, facing the field's edge, or
## at random 1 step in its turn period, it picks up, right, down, left or stop
## at random, but never off the field, never stop twice, and never back the
## way it was told unless that's down. So it drifts down, and turns where a
## wall meets the field's edge, as gaps there. Not while a hit holds it.
func _wander(at: Vector2i) -> void:
	var allowed := 0b11111
	if at.x <= 1:
		allowed &= ~(1 << 3)
	elif at.x >= 39:
		allowed &= ~(1 << 1)
	if at.y <= 1:
		allowed &= ~(1 << 0)
	elif at.y >= 29:
		allowed &= ~(1 << 2)
	if _hit_hold > 0.0:
		return
	var facing := FACINGS.find(current_direction)
	if _moving and allowed & (1 << facing) != 0 and randi() % _turn_period() != 0:
		return
	var pick := STOP
	while true:
		pick = randi() % 5
		if allowed & (1 << pick) == 0:
			continue
		if pick == STOP:
			if _command != STOP:
				break
		elif pick != (_command + 2) & 3 or pick == 2:
			break
	_command = pick

## Its turn period, AI steps: the difficulty's, half as long again for the
## basic type of each pair (an odd id).
func _turn_period() -> int:
	var period: int = TURN_PERIOD[clampi(GameManager.difficulty, 0, TURN_PERIOD.size() - 1)]
	return period if tank_type_id % 2 == 0 else period * 3 / 2

## Faces [param dir] and keeps to the grid line across it, as the original
## snapped a moving tank every frame (0x00492244): so it turns on a grid line,
## and lines up with a gap a tank wide.
func _face(dir: Vector2) -> void:
	if dir != current_direction:
		current_direction = dir
		_update_sprite_direction()
	_keep_to_grid()

## Turns on ice once slow enough (BaseTank._ice_steer): on its grid line.
func _turn_to(new_direction: Vector2) -> void:
	_face(new_direction)

## The remake's own firing (Sean kept it, 2026-09-25), along its facing: fast
## at the base when lined up facing it close by, fast at a brick in its way,
## faster near the base, else every 0.5-2 s. (The original fired 1 step in its
## turn period, wherever it faced.)
func _fire_at_will() -> void:
	var eagle := get_tree().get_first_node_in_group("eagle") as Node2D
	var near := eagle != null and global_position.distance_to(eagle.global_position) < EAGLE_ATTACK_RANGE
	if near and _facing_eagle(eagle):
		_fire_weapon(0.1, 0.25)
	elif not _moving and _command != STOP and _brick_ahead():
		_fire_weapon(0.15, 0.3)
	elif near:
		_fire_weapon(0.15, 0.4)
	else:
		_fire_weapon(0.5, 2.0)

## Lined up with the base (within half a tank) and facing it.
func _facing_eagle(eagle: Node2D) -> bool:
	var diff := eagle.global_position - global_position
	if absf(diff.x) < HALF_TANK:
		return current_direction == (Vector2.DOWN if diff.y > 0.0 else Vector2.UP)
	if absf(diff.y) < HALF_TANK:
		return current_direction == (Vector2.RIGHT if diff.x > 0.0 else Vector2.LEFT)
	return false

## A wall its shells break right in front of it: a brick or a hard brick.
func _brick_ahead() -> bool:
	var lm := _level()
	if lm == null:
		return false
	var ahead := global_position + current_direction * (HALF_TANK + HALF_TILE)
	var across := Vector2(current_direction.y, current_direction.x)
	for offset in BODY_LANE_OFFSETS:
		var data: Variant = lm._fg_tile_data.get(lm.world_to_tile(ahead + across * offset))
		if data == null:
			continue
		var cat := LevelData.get_tile_category(int((data as Dictionary).get("code", 0)))
		if cat == LevelData.TileCategory.SOFT_BRICK_FULL or cat == LevelData.TileCategory.SOFT_BRICK_PARTIAL \
				or cat == LevelData.TileCategory.HARD_BRICK:
			return true
	return false

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

## The weapon its type carries, as ENEMY MINES has it: with mines off, a mine
## tank fires rapid shells instead, at its rapid counterpart's gun level. Sets
## the level it starts from, and how many shells it may have in flight.
func _apply_weapon() -> void:
	var weapon: String = CookieData.TYPE_WEAPON_MAP.get(tank_type_id, "none")
	var level_type := tank_type_id
	if weapon == "mine" and not InputSettings.get_enemy_mines():
		weapon = "rapid"
		level_type -= MINE_TO_RAPID_TYPE
	special_weapon_type = weapon
	_base_weapon_level = CookieData.get_enemy_weapon_level(level_type, GameManager.difficulty)
	max_bullets = SHELL_SPECIAL_MAX_BULLETS if weapon in SHELL_SPECIALS else PLAIN_MAX_BULLETS

## ENEMY MINES switched with this tank on the field (the pause menu): a mine
## tank changes weapon at once, keeping the gun levels items gave it.
func _on_enemy_mines_changed() -> void:
	if CookieData.TYPE_WEAPON_MAP.get(tank_type_id, "none") != "mine":
		return
	var gained := special_weapon_level - _base_weapon_level
	_apply_weapon()
	special_weapon_level = clampi(_base_weapon_level + gained, 0, MAX_ITEM_GUN)

## A mine at the tank's gun level, held to the ENEMY MINE LEVEL setting (1-4 as
## players count them, so a mine level one lower).
func _lay_mine_special() -> bool:
	if not _place_mine(mini(special_weapon_level, InputSettings.get_enemy_mine_level() - 1)):
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
	_base_weapon_level = maxi(_base_weapon_level, _promoted_base_level())
	_apply_type_look()

## The gun level the stronger type starts with, for the weapon fired now.
func _promoted_base_level() -> int:
	var level_type := tank_type_id
	if CookieData.TYPE_WEAPON_MAP.get(tank_type_id, "none") == "mine" and special_weapon_type == "rapid":
		level_type -= MINE_TO_RAPID_TYPE
	return CookieData.get_enemy_weapon_level(level_type, GameManager.difficulty)

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
	_take_points(1, bullet_direction)

## One hit of [param points] (a blast's, or an explosion shell's): one
## downgrade for it, one flash, one sound.
func take_hit(points: int) -> void:
	_take_points(points, Vector2.ZERO)

## [param points] off its health in one hit, from a shell going
## [param bullet_direction] (ZERO: no shooter to turn on).
func _take_points(points: int, bullet_direction: Vector2) -> void:
	var attacker := hit_by
	hit_by = -1
	if health <= 0:
		return  # already destroyed this frame: nothing more to take
	if is_invulnerable():
		return  # the original's Damage ignored an invulnerable tank
	health -= points
	_hits_taken += 1
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	# A hit it survives holds its course a moment, deciding nothing (the
	# original's). A shot turns it on the shooter, and it fires back at once:
	# the remake's (the original turned half the time, always with a moon
	# shield). Not while frozen, the debug freeze included, which stops this
	# tank from processing.
	if health > 0:
		_hit_hold = HIT_HOLD
	var face := FACINGS.find(-bullet_direction)
	if face >= 0 and health > 0 and not GameManager.enemies_frozen and can_process():
		_command = face
		_face(FACINGS[face])
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
	if special_weapon_level > _base_weapon_level:
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
	if lm == null or Net.is_client():
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

# --- Online (see BaseTank's net_state; its type follows the rest) ---

## Past the base's flags: the blink of an item's invulnerability.
const NET_BLINKING := NET_OWN_FLAGS

func net_type() -> int:
	return NetWorld.T_ENEMY

func net_spawn_args() -> Array:
	return [tank_type_id]

## A client's tank of type [param args][0], set before it enters the tree.
func net_setup(args: Array) -> void:
	tank_type_id = clampi(int(args[0]), 1, 24)

func net_state() -> Array:
	var state := super.net_state()
	if _invulnerable_timer > 0.0:
		state[3] = int(state[3]) | NET_BLINKING
	state.append(tank_type_id)
	return state

func net_apply(state: Array) -> void:
	super.net_apply(state)
	# The blink runs here; the host says while.
	_invulnerable_timer = 1.0 if int(state[3]) & NET_BLINKING else 0.0
	if state.size() > 9 and int(state[9]) != tank_type_id:
		tank_type_id = clampi(int(state[9]), 1, 24)  # a MAX promoted it
		_apply_type_look()

func _net_apply_addons(bits: int) -> void:
	var wanted := BaseTank.net_addon_names(bits)
	for addon_name: String in addons.duplicate():
		if addon_name not in wanted:
			_remove_addon(addon_name)
	for addon_name in wanted:
		if addon_name not in addons:
			_add_addon(addon_name)

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
