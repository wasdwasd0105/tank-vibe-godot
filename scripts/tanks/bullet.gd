class_name Bullet
extends Area2D

@export var speed: float = 256.0
var direction: Vector2 = Vector2.UP
var owner_tank: BaseTank = null
var is_player_bullet: bool = true
## The player who fired it (-1: an enemy): who its hits are credited to.
var owner_player: int = -1
## Lets an ordinary bullet clear an iron block. NOTHING grants this today: in the
## original only the AP shell gets through steel, and it does so on its own path
## (see pierces / LevelManager.ap_drill_tiles), spending a damage pool per tile.
## Kept as the hook for any future weapon that should breach steel outright.
var can_destroy_steel: bool = false
var visual_style: String = "regular"
var visual_lane_offsets: Array[float] = [-16.0, 16.0]
var collision_lane_offsets: Array[float] = [-16.0, 16.0]
## Lanes tested against the tile grid; empty = the collision lanes. Tank-wide
## shots use the shooter's whole body here (BaseTank.BODY_LANE_OFFSETS) while
## their hitbox against tanks stays the narrower collision lanes.
var tile_lane_offsets: Array[float] = []
var _destroyed: bool = false
var _visual_sprites: Array[Sprite2D] = []
var _animation_timer: float = 0.0
var _current_frame: int = 0

# How much damage this bullet deals to an opposing bullet it crosses (rule 6).
# A bullet dies when its damage is reduced to 0 or below.
var damage: int = 1

# Fire weapon: this bullet leaves a burning patch wherever it dies.
var ignites_ground: bool = false
var max_range: float = -1.0   # px; <= 0 means unlimited
var _traveled: float = 0.0

# Explosion weapon: this bullet detonates a shockwave wherever it dies.
var explodes: bool = false
var explosion_level: int = 0
var _direct_hit_tank: Node2D = null  # tank the explosion bullet struck (excluded from its own wave)

# AP weapon: a slow-then-fast shell whose "damage" is a pool it spends piercing
# through tanks and walls (it keeps flying until the pool is empty). accel/max_speed
# make it accelerate after launch.
var pierces: bool = false
var accel: float = 0.0
var max_speed: float = 0.0
const SHIELD_BREAK_THRESHOLD: int = 6  # AP pool needed to strip a moon shield

var _level_manager: LevelManager = null
## Online, on a client: a ghost of the host's shell for a shot its own tank fired
## (NetClientWorld.add_ghost), flying here at once until the host's shows.
var net_ghost := false
## Online: the number the client gave a shot of its own tank's (Net.note_shot),
## on its ghost there and on the host's shell for it, so the one takes over
## from the other; -1 for any other shell.
var net_shot := -1
## A ghost's: where it left, and for an AP shell how far its drilling has been
## worked out (NetClientWorld.ap_walk).
var net_origin := Vector2.ZERO
var net_walk: Dictionary = {}
## Host: a client's own shot (lag compensation, docs/network_design.md section
## 7): [the controller (PlayerInput) of the client that fired it, the run of
## its reports and the frame it fired it at]; [] for any other shell. It meets
## tanks and the enemies' shells where that client's screen had them as this
## shot got there on it (_meet_as_seen), not where they are here by then.
var net_view: Array = []
var _net_steps := 0
var _met_as_seen: Dictionary = {}
static var _bullet_texture_cache: Dictionary = {}

const BULLET_LENGTH: float = 10.0
const BULLET_THICKNESS: float = 10.0
const LINE_WIDTH: float = 2.0
const FRAME_DURATION: float = 0.5
# Per-style animation frame duration (falls back to FRAME_DURATION). Fire
# flickers fast to read as a live flame.
const FRAME_DURATIONS: Dictionary = {
	"fire": 0.05,
	"explosion": 0.05,
}
const BULLET_VISUAL_SCALE: float = 2.0
const BULLET_TEXTURE_PATHS: Dictionary = {
	"regular": [
		"res://assets/sprites/bullets/regular/regular_1.png",
		"res://assets/sprites/bullets/regular/regular_2.png",
	],
	"rapid": [
		"res://assets/sprites/bullets/rapid/rapid_1.png",
		"res://assets/sprites/bullets/rapid/rapid_2.png",
	],
	"fire": [
		"res://assets/sprites/bullets/fire/fire_1.png",
		"res://assets/sprites/bullets/fire/fire_2.png",
	],
	"explosion": [
		"res://assets/sprites/bullets/explosion/explosion_dir1.png",
	],
	"ap": [
		"res://assets/sprites/bullets/ap/ap_1.png",
		"res://assets/sprites/bullets/ap/ap_2.png",
	],
}
const BG_KEY_R: float = 248.0 / 255.0
const BG_KEY_G: float = 0.0
const BG_KEY_B: float = 248.0 / 255.0
const BG_KEY_THRESHOLD: float = 0.05

func _ready() -> void:
	add_to_group(NetWorld.GROUP)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = true

	var old_sprite = get_node_or_null("Sprite2D")
	if old_sprite:
		old_sprite.queue_free()

	if visual_lane_offsets.is_empty():
		visual_lane_offsets = [0.0]
	if collision_lane_offsets.is_empty():
		collision_lane_offsets = visual_lane_offsets.duplicate()

	_load_bullet_textures(visual_style)

	var col_shape = get_node_or_null("CollisionShape2D")
	if col_shape and col_shape.shape is RectangleShape2D:
		# Its own box: the scene's shape is one resource every shell shares.
		var rect := (col_shape.shape as RectangleShape2D).duplicate() as RectangleShape2D
		rect.size = box_half(direction, collision_lane_offsets) * 2.0
		col_shape.shape = rect

	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("get_level_manager"):
		_level_manager = game.get_level_manager()

	_create_visual_sprites()
	queue_redraw()

## Half the box a shell's shape covers about its middle, going [param way] on
## collision lanes [param lanes]: their span and BULLET_THICKNESS across its
## way, BULLET_LENGTH along it.
static func box_half(way: Vector2, lanes: Array) -> Vector2:
	var span := 0.0
	if lanes.size() > 1:
		span = float(lanes.max()) - float(lanes.min())
	var across := maxf(BULLET_THICKNESS, span + BULLET_THICKNESS)
	return (Vector2(across, BULLET_LENGTH) if way.x == 0.0 else Vector2(BULLET_LENGTH, across)) * 0.5

## Whether a shell at [param at] going [param way] on [param lanes] is on a tank
## at [param tank_at]: their shapes overlap, as the physics has them (a tank's
## is BaseTank.HITBOX_SIZE square).
static func touches_tank(at: Vector2, way: Vector2, lanes: Array, tank_at: Vector2) -> bool:
	var reach := box_half(way, lanes) + Vector2.ONE * BaseTank.HITBOX_SIZE * 0.5
	var offset := tank_at - at
	return absf(offset.x) < reach.x and absf(offset.y) < reach.y

## Whether two shells' shapes overlap: one at [param at] going [param way] on
## [param lanes], the other at [param other_at] going [param other_way] on
## [param other_lanes].
static func shells_touch(at: Vector2, way: Vector2, lanes: Array,
		other_at: Vector2, other_way: Vector2, other_lanes: Array) -> bool:
	var reach := box_half(way, lanes) + box_half(other_way, other_lanes)
	var offset := other_at - at
	return absf(offset.x) < reach.x and absf(offset.y) < reach.y

func _draw() -> void:
	if not _visual_sprites.is_empty():
		return
	var color := Color.WHITE
	var half_len := BULLET_LENGTH / 2.0

	if direction == Vector2.UP or direction == Vector2.DOWN:
		for lane_offset in visual_lane_offsets:
			draw_line(Vector2(lane_offset, -half_len), Vector2(lane_offset, half_len), color, LINE_WIDTH)
	else:
		for lane_offset in visual_lane_offsets:
			draw_line(Vector2(-half_len, lane_offset), Vector2(half_len, lane_offset), color, LINE_WIDTH)

func _physics_process(delta: float) -> void:
	if _destroyed:
		return

	_animate(delta)
	if Net.is_client():
		if net_ghost:
			_fly_ghost(delta)
		return  # the host flies every shell; this one only shows it

	# AP shells launch slow and accelerate to a high top speed.
	if accel > 0.0 and max_speed > 0.0:
		speed = minf(speed + accel * delta, max_speed)

	var movement: Vector2 = direction * speed * delta
	position += movement
	_net_steps += 1

	# Fire bullets drop (and ignite) once they exceed their range.
	if max_range > 0.0:
		_traveled += movement.length()
		if _traveled >= max_range:
			_destroy()
			return

	if position.x < 144 or position.x > 1456 or position.y < 0 or position.y > 992:
		_destroy()
		return

	_check_tile_collision()
	if not net_view.is_empty() and not _destroyed:
		_meet_as_seen()

## One step of a ghost (net_ghost): the flight the host's shell will make,
## touching nothing. Where that shell ends, the ghost ends: the host judges it
## by what this machine shows (Bullet._meet_as_seen), so a wall, a shell of the
## enemies' (both going, as on the host) or a tank shown here is where it ends
## there too; the end, a kill and a wall broken are shown at once.
func _fly_ghost(delta: float) -> void:
	if not visible:
		return
	if accel > 0.0 and max_speed > 0.0:
		speed = minf(speed + accel * delta, max_speed)
	var movement: Vector2 = direction * speed * delta
	position += movement
	_traveled += movement.length()
	# An AP shell drills on through walls, shells and tanks while its pool
	# lasts, as the host's does; any other stops at the first, in the host's
	# order: the walls, then the shells, then the tanks.
	var world := NetClientWorld.of(get_tree())
	var drilled_to := world.ap_walk(self, net_origin, _traveled, net_walk) if pierces and world else -1.0
	if drilled_to >= 0.0:
		global_position = net_origin + direction * drilled_to
	var out := (max_range > 0.0 and _traveled >= max_range) \
			or position.x < 144 or position.x > 1456 or position.y < 0 or position.y > 992
	var walls: Array[Vector2i] = []
	if not pierces and not out:
		walls = _solid_tiles_touched()
	var ended := drilled_to >= 0.0 or out or not walls.is_empty()
	if not ended and not pierces and world:
		var theirs := world.shell_met(self, global_position)
		if theirs:
			world.clash(self, theirs, damage, global_position)  # (it ends: 1 damage, or a fire or explosion shell)
			ended = true
	var met: BaseTank = null
	if not ended and not pierces:
		met = _enemy_met()
		ended = met != null
	if ended:
		visible = false
		if world:
			if met:
				world.note_own_hit(met)
				world.guess_kill(met, tank_damage(), self, global_position)  # its kill too, if it is one
			elif not walls.is_empty():
				world.predict_wall(self, walls, global_position)  # the wall it broke too
			world.predict_hit(self, global_position)  # its end, shown at once

## How far this shell flies in [param seconds] from its speed now: an AP shell
## speeds up to its top speed as it goes.
func distance_in(seconds: float) -> float:
	return flight(speed, accel, max_speed, seconds)

## How far a shell leaving at [param from_speed] flies in [param seconds],
## speeding up by [param accel] to [param top] (if it does).
static func flight(from_speed: float, accel: float, top: float, seconds: float) -> float:
	if accel <= 0.0 or top <= from_speed:
		return from_speed * seconds
	var to_top := (top - from_speed) / accel
	if seconds <= to_top:
		return from_speed * seconds + 0.5 * accel * seconds * seconds
	return from_speed * to_top + 0.5 * accel * to_top * to_top + top * (seconds - to_top)

## How much of a tank's health this shell takes on hitting it (not an AP
## shell's, which spends its pool): a direct hit's damage for an explosion
## shell, else one. A client's shell of the host's doesn't know whether it
## explodes, but its look says.
func tank_damage() -> int:
	if explodes:
		return damage
	if visual_style == "explosion":
		var level := int(GameManager.player_weapon_levels[clampi(owner_player, 0, 1)])
		return int(CookieData.get_weapon_fire_config("explosion", level).get("damage", 1))
	return 1

## The enemy tank this shell is on as shown here, the nearest if more (a
## ghost's check, as the host judges it: touches_tank).
func _enemy_met() -> BaseTank:
	var met: BaseTank = null
	for node in get_tree().get_nodes_in_group("enemies"):
		var tank := node as BaseTank
		if tank == null or not tank.is_solid():
			continue
		if touches_tank(global_position, direction, collision_lane_offsets, tank.global_position) \
				and (met == null or (tank.global_position - met.global_position).dot(direction) < 0.0):
			met = tank
	return met

func _check_tile_collision() -> void:
	if not _level_manager or _destroyed:
		return
	var solid_tiles := _solid_tiles_touched()
	if not solid_tiles.is_empty():
		# AP shells drill through walls, spending their pool per tile, and keep
		# flying as long as the pool survives.
		if pierces:
			damage = _level_manager.ap_drill_tiles(solid_tiles, damage, direction)
			if damage <= 0:
				_destroy()
			return

		hit_tiles(_level_manager, solid_tiles, direction, can_destroy_steel)
		_destroy()

## A shell going [param way] ends on [param tiles] of [param level_manager]'s:
## a brick loses the side it hit, a hard brick a point, steel only to a shell
## that [param through_steel] goes through it. (A client breaks them so for its
## own shells at once: NetClientWorld.predict_wall.)
static func hit_tiles(level_manager: LevelManager, tiles: Array[Vector2i], way: Vector2,
		through_steel: bool = false) -> void:
	for tile_pos in tiles:
		if not level_manager._fg_tile_data.has(tile_pos):
			continue
		var data: Dictionary = level_manager._fg_tile_data[tile_pos]
		var code: int = data.get("code", 0)
		var cat := LevelData.get_tile_category(code)
		match cat:
			LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
				level_manager._damage_brick(tile_pos, way)
			LevelData.TileCategory.HARD_BRICK:
				level_manager._damage_hard_brick(tile_pos)
			LevelData.TileCategory.IRON_BLOCK:
				if through_steel:
					level_manager._remove_fg_tile(tile_pos)
			LevelData.TileCategory.SUPER_BLOCK:
				pass

## The solid tiles this shell's lanes are on, or about to be.
func _solid_tiles_touched() -> Array[Vector2i]:
	if not _level_manager:
		return []
	var lanes: Array[float] = tile_lane_offsets if not tile_lane_offsets.is_empty() else collision_lane_offsets
	return solid_tiles_at(_level_manager, global_position, direction, lanes)

## The solid tiles of [param level_manager]'s that a shell at [param at] going
## [param way] has its tile [param lanes] on, or is about to.
static func solid_tiles_at(level_manager: LevelManager, at: Vector2, way: Vector2, lanes: Array) -> Array[Vector2i]:
	var solid_tiles: Array[Vector2i] = []
	var perp: Vector2 = Vector2.RIGHT if way == Vector2.UP or way == Vector2.DOWN else Vector2.DOWN
	var tiles_to_check: Array[Vector2i] = []
	for base_pos: Vector2 in [at, at + way * 6.0]:
		for lane_offset: float in lanes:
			var tile_pos: Vector2i = level_manager.world_to_tile(base_pos + perp * lane_offset)
			if tile_pos not in tiles_to_check:
				tiles_to_check.append(tile_pos)
	for tile_pos in tiles_to_check:
		if not level_manager._fg_tile_data.has(tile_pos):
			continue
		var data: Dictionary = level_manager._fg_tile_data[tile_pos]
		var code: int = data.get("code", 0)
		if LevelData.is_solid_tile(LevelData.get_tile_category(code)):
			solid_tiles.append(tile_pos)
	return solid_tiles

func _on_body_entered(body: Node2D) -> void:
	if _destroyed:
		return
	if body == owner_tank:
		return
	if not net_view.is_empty() and body is BaseTank:
		return  # a client's own shot meets tanks where its screen had them (_meet_as_seen)

	if pierces:
		_ap_on_body(body)
		return

	if is_player_bullet and body is EnemyTank:
		_hit_enemy(body, body.is_bullet_blocked(direction))
	elif not is_player_bullet and body is PlayerTank:
		if body.is_bullet_blocked(direction):
			_destroy()
			return
		if not body.is_invincible:
			if explodes:
				_explode_direct_hit(body)
			else:
				body.take_damage()
		_destroy()
	elif body.is_in_group("eagle"):
		_hit_base()
	elif body.is_in_group("boundary"):
		_destroy()

## A player's shell hits enemy [param tank], its moon shield's front to the
## shell ([param blocked]) or not, and ends. (null: a tank finished here already
## that the client firing it still had on its screen: it just ends there.)
func _hit_enemy(tank: EnemyTank, blocked: bool) -> void:
	if tank != null and not blocked:
		if explodes:
			_explode_direct_hit(tank)
		else:
			tank.hit_by = owner_player
			tank.take_damage(direction)
	_destroy()

## The shell reached the base: it falls, unless the BASE INVINCIBLE setting is
## on, when the shell just stops there.
func _hit_base() -> void:
	if not InputSettings.get_base_invincible():
		Events.base_destroyed.emit()
	_destroy()

## An explosion bullet's DIRECT hit: deal its `damage` as HP (no retaliation),
## then the caller detonates the wave.
func _explode_direct_hit(tank: Node2D) -> void:
	_direct_hit_tank = tank  # its own wave should not double-hit it
	for i in range(damage):
		if is_instance_valid(tank) and tank.health > 0:
			tank.hit_by = owner_player
			tank.take_damage()

## AP shell hitting a body: spend the damage pool, pierce through dead tanks.
func _ap_on_body(body: Node2D) -> void:
	var tank: BaseTank = null
	if is_player_bullet and body is EnemyTank:
		tank = body
	elif not is_player_bullet and body is PlayerTank:
		tank = body

	if tank:
		_ap_hit_tank(tank, tank.is_bullet_blocked(direction))
		return

	if body.is_in_group("eagle"):
		_hit_base()
	elif body.is_in_group("boundary"):
		_destroy()

## The AP shell reaches [param tank], its moon shield's front to the shell
## ([param blocked]) or not: its pool is spent on it. (null: a tank finished
## here already that the client firing it still had on its screen, with
## [param health_seen] then: the pool goes as it would have.)
func _ap_hit_tank(tank: BaseTank, blocked: bool, health_seen: int = 0) -> void:
	# An invincible tank is fully untouchable: the shell is absorbed WITHOUT
	# stripping its moon shield or dealing damage. (Check before the shield.)
	if tank is PlayerTank and tank.is_invincible:
		_destroy()
		return
	# Moon-shield front hit: a strong enough pool (>= threshold) strips the
	# shield (tank unhurt + grace); a worn-down shell is just absorbed.
	if blocked:
		SoundManager.play(&"shield_absorb")
		if damage >= SHIELD_BREAK_THRESHOLD and tank:
			tank.break_moon_shield_grace()
		_destroy()
		return
	# Spend min(pool, tankHP): the tank takes that much, the pool drops by it.
	var dealt: int = mini(damage, tank.health if tank else health_seen)
	for i in range(dealt):
		if is_instance_valid(tank) and tank.health > 0:
			tank.hit_by = owner_player
			tank.take_damage()  # no direction -> no retaliation while being drilled
	damage -= dealt
	if damage <= 0:
		_destroy()
	# else: the tank died and the shell flies on through it (pass-through)

func _on_area_entered(area: Area2D) -> void:
	if _destroyed:
		return
	if area is Bullet:
		var other_bullet := area as Bullet
		if other_bullet._destroyed:
			return
		if is_player_bullet == other_bullet.is_player_bullet:
			return  # same side — bullets pass through each other
		if not net_view.is_empty() or not other_bullet.net_view.is_empty():
			return  # a client's own shot meets shells where its screen had them (_meet_as_seen)

		# Each bullet subtracts the other's damage (rule 6). Normal bullets die
		# only when reduced to <= 0, so two normal bullets annihilate 1-for-1.
		# Special bullets (fire/explosion) always drop on contact and run their
		# death effect (ignite / detonate), even if their damage survives.
		var my_dmg := damage
		var their_dmg := other_bullet.damage
		take_bullet_damage(their_dmg)
		other_bullet.take_bullet_damage(my_dmg)
		# The original clinked only when one shell outlived the clash; a mutual
		# annihilation was silent.
		if _destroyed != other_bullet._destroyed:
			SoundManager.play(&"bullet_clink")
		if (ignites_ground or explodes) and not _destroyed:
			_destroy()
		if (other_bullet.ignites_ground or other_bullet.explodes) and not other_bullet._destroyed:
			other_bullet._destroy()

## Host: a step of a client's own shot (net_view): the tanks and the enemies'
## shells it meets are those where that client's screen had them as the shot
## got here on it (NetHostWorld.seen_at), not where they are here by now. So its
## player's own screen, which shows its shots' ends and kills at once, is right
## (lag compensation as the popular shooters have it, "favor the shooter"). As
## the physics has them: the shells first, then the tanks, the nearest first.
func _meet_as_seen() -> void:
	var world := NetHostWorld.active
	if world == null:
		net_view = []  # the session is over: it meets what's here, as any shell does
		return
	var key := int(net_view[0])
	var peer := PlayerInput.controller_peer(key)
	var time := PlayerInput.view_time(key, int(net_view[1]), int(net_view[2]) + _net_steps)
	var shells: Array = []
	var tanks: Array = []
	for seen: Array in world.seen_at(time, peer):
		var kept: Array = seen[1]
		if _met_as_seen.has(seen[0]) or int(seen[0]) == get_instance_id():
			continue
		if int(kept[0]) == NetHostWorld.SEEN_SHELL:
			if bool(kept[4]) != is_player_bullet \
					and shells_touch(global_position, direction, collision_lane_offsets, kept[1], kept[2], kept[3]):
				shells.append(seen)
		elif bool(kept[6]) == is_player_bullet and bool(kept[3]) \
				and touches_tank(global_position, direction, collision_lane_offsets, kept[1]):
			tanks.append(seen)
	var nearer := func(a: Array, b: Array) -> bool:
		return (a[1][1] - global_position).dot(direction) < (b[1][1] - global_position).dot(direction)
	shells.sort_custom(nearer)
	tanks.sort_custom(nearer)
	for seen: Array in shells:
		_met_as_seen[seen[0]] = true
		_clash_as_seen(seen, world, peer)
		if _destroyed:
			return
	for seen: Array in tanks:
		var kept: Array = seen[1]
		_met_as_seen[seen[0]] = true
		var tank := instance_from_id(int(seen[0])) as EnemyTank
		if tank != null and (tank.is_queued_for_deletion() or tank.health <= 0):
			tank = null  # finished here already, by something else
		var blocked: bool = bool(kept[4]) and direction.dot(kept[2]) < 0.0
		# Shown dying at once on that screen (NetClientWorld.guess_kill): its later
		# shots there pass where it was, so here too.
		if not blocked and not bool(kept[7]) and (damage if pierces else tank_damage()) >= int(kept[5]):
			world.mark_gone(peer, int(seen[0]))
		if pierces:
			_ap_hit_tank(tank, blocked, int(kept[5]))
		else:
			_hit_enemy(tank, blocked)
		if _destroyed:
			return

## Host: a client's own shot meets the enemies' shell [param seen] (as
## NetHostWorld.seen_at has it) where that client's screen had it: each takes
## the other's damage, as _on_area_entered has it. One gone here since still
## counts with its damage then; one that goes now goes where that screen had the
## two meet.
func _clash_as_seen(seen: Array, world: NetHostWorld, peer: int) -> void:
	var kept: Array = seen[1]
	var other := instance_from_id(int(seen[0])) as Bullet
	if other != null and (other._destroyed or other.is_queued_for_deletion()):
		other = null
	var my_dmg := damage
	var their_dmg: int = other.damage if other else int(kept[5])
	var other_goes := their_dmg <= my_dmg or bool(kept[6])
	take_bullet_damage(their_dmg)
	if other:
		if other_goes:
			other.global_position = kept[1]
		other.take_bullet_damage(my_dmg)
		if (other.ignites_ground or other.explodes) and not other._destroyed:
			other._destroy()
	if other_goes:
		world.mark_gone(peer, int(seen[0]))
	if _destroyed != other_goes:
		SoundManager.play(&"bullet_clink")
	if (ignites_ground or explodes) and not _destroyed:
		_destroy()

## Reduce this bullet's damage by [param amount]; destroy it if it hits 0.
func take_bullet_damage(amount: int) -> void:
	damage -= amount
	if damage <= 0:
		_destroy()

func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if owner_tank and is_instance_valid(owner_tank):
		owner_tank.on_bullet_destroyed()
		if ignites_ground:
			owner_tank.on_fire_bullet_destroyed()
		if explodes:
			owner_tank.on_explosion_bullet_destroyed()
		if pierces:
			owner_tank.on_ap_bullet_destroyed()

	# Fire bullets ignite the ground wherever they die — range end, wall/tank/bullet
	# hit, or map border. If they land on already-burning ground the field grows.
	if ignites_ground and _level_manager:
		_level_manager.ignite_fire_patch(
			_level_manager.world_to_tile(global_position), is_player_bullet, owner_player)

	# Explosion bullets detonate a shockwave wherever they die (a directly-hit
	# tank already took the direct hit, so it's excluded from the wave).
	if explodes and _level_manager:
		_level_manager.spawn_explosion_blast(
			global_position, explosion_level, is_player_bullet, false, _direct_hit_tank, owner_player)

	var effects_container = get_tree().get_first_node_in_group("effects_container")
	var parent_node = effects_container if effects_container else get_tree().current_scene

	# A theme with its own hit animation plays it once, centred on the shot, as
	# the original did; otherwise the built-in flash marks each lane.
	var hit_frames: Array = ThemeManager.get_hit_frames(visual_style)
	if not hit_frames.is_empty():
		HitEffect.spawn(parent_node, global_position, hit_frames, ThemeManager.get_hit_duration(), visual_style)
		queue_free()
		return

	var explosion_scene := preload("res://scenes/effects/explosion.tscn")

	var perp: Vector2 = Vector2.ZERO
	if direction == Vector2.UP or direction == Vector2.DOWN:
		perp = Vector2.RIGHT
	else:
		perp = Vector2.DOWN

	for lane_offset in collision_lane_offsets:
		var explosion := explosion_scene.instantiate()
		explosion.global_position = global_position + perp * lane_offset
		explosion.scale = Vector2(1.0, 1.0)
		parent_node.add_child(explosion)
		NetHostWorld.record(NetWorld.EV_EXPLOSION, [explosion.global_position.x, explosion.global_position.y, 1.0])

	queue_free()

## Steps the shell's frames on.
func _animate(delta: float) -> void:
	_animation_timer += delta
	var frame_duration: float = FRAME_DURATIONS.get(visual_style, FRAME_DURATION)
	var active_textures := _get_active_bullet_textures()
	if active_textures.size() > 1 and _animation_timer >= frame_duration:
		_animation_timer -= frame_duration
		_current_frame = (_current_frame + 1) % active_textures.size()
		_update_visual_frame()

# --- Online (NetWorld): a shell is its look and where it is. ---

func net_type() -> int:
	return NetWorld.T_BULLET

func net_spawn_args() -> Array:
	return [maxi(BaseTank.FACINGS.find(direction), 0), visual_style, Array(visual_lane_offsets),
			owner_player, speed, max_range, pierces, accel, max_speed, net_shot, damage, Array(collision_lane_offsets)]

func net_state() -> Array:
	return [global_position.x, global_position.y]

## A client's shell: flying [param args][0] (a BaseTank facing), drawn in style
## [param args][1] on lanes [param args][2]; then whose it is (a player, or -1),
## how fast it flies, how far it goes, whether it drills through walls and how
## it speeds up, for drawing a shell of this machine's own ahead
## (NetClientWorld), the number of the client's own shot it is (net_shot), its
## damage as it left (what it takes off a shell it meets), and the lanes it
## meets things on (a shot drawn as one shell can hit on two), the walls across
## the shooter's body if more than one, as _spawn_bullet has them.
func net_setup(args: Array) -> void:
	direction = BaseTank.FACINGS[clampi(int(args[0]), 0, 3)]
	visual_style = str(args[1])
	var lanes: Array[float] = []
	for lane: Variant in args[2]:
		lanes.append(float(lane))
	visual_lane_offsets = lanes
	collision_lane_offsets = lanes.duplicate()
	if args.size() >= 9:
		owner_player = clampi(int(args[3]), -1, 1)
		speed = float(args[4])
		max_range = float(args[5])
		pierces = bool(args[6])
		accel = float(args[7])
		max_speed = float(args[8])
	if args.size() >= 10:
		net_shot = int(args[9])
	if args.size() >= 11:
		damage = int(args[10])
	if args.size() >= 12:
		var hit_lanes: Array[float] = []
		for lane: Variant in args[11]:
			hit_lanes.append(float(lane))
		collision_lane_offsets = hit_lanes
		if hit_lanes.size() > 1:
			tile_lane_offsets = BaseTank.BODY_LANE_OFFSETS

func net_apply(_state: Array) -> void:
	pass

func _create_visual_sprites() -> void:
	var active_textures := _get_active_bullet_textures()
	if active_textures.is_empty():
		return

	var sprite_rotation := _get_sprite_rotation()
	for lane_offset in visual_lane_offsets:
		var sprite := Sprite2D.new()
		sprite.texture = active_textures[_current_frame]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * BULLET_VISUAL_SCALE
		sprite.rotation = sprite_rotation
		sprite.position = _get_visual_lane_position(lane_offset)
		add_child(sprite)
		_visual_sprites.append(sprite)

func _update_visual_frame() -> void:
	var active_textures := _get_active_bullet_textures()
	if active_textures.is_empty():
		return
	for sprite in _visual_sprites:
		if sprite and is_instance_valid(sprite):
			sprite.texture = active_textures[_current_frame]

func _load_bullet_textures(style: String) -> void:
	if _bullet_texture_cache.has(style):
		return

	var textures: Array[Texture2D] = []
	for texture_path in BULLET_TEXTURE_PATHS.get(style, []):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(texture_path)) != OK:
			continue
		img.convert(Image.FORMAT_RGBA8)

		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if absf(c.r - BG_KEY_R) < BG_KEY_THRESHOLD \
					and absf(c.g - BG_KEY_G) < BG_KEY_THRESHOLD \
					and absf(c.b - BG_KEY_B) < BG_KEY_THRESHOLD:
					img.set_pixel(x, y, Color(0, 0, 0, 0))

		textures.append(ImageTexture.create_from_image(img))

	_bullet_texture_cache[style] = textures

func _get_active_bullet_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = _bullet_texture_cache.get(visual_style, [])
	if textures.is_empty() and visual_style != "regular":
		_load_bullet_textures("regular")
		textures = _bullet_texture_cache.get("regular", [])
	return textures

func _get_visual_lane_position(lane_offset: float) -> Vector2:
	if direction == Vector2.UP or direction == Vector2.DOWN:
		return Vector2(lane_offset, 0.0)
	return Vector2(0.0, lane_offset)

func _get_sprite_rotation() -> float:
	if direction == Vector2.DOWN:
		return PI
	if direction == Vector2.LEFT:
		return -PI / 2
	if direction == Vector2.RIGHT:
		return PI / 2
	return 0.0
