class_name Cookie
extends Area2D

## The specific cookie type from CookieData.CookieType
var cookie_type: int = -1

var _lifetime: float = 0.0
var _despawn_time: float = 40.0
var _pickup_delay: float = 0.0
var _delay_just_expired: bool = false

# Spray animation
var _spray_origin: Vector2 = Vector2.ZERO
var _spray_target: Vector2 = Vector2.ZERO
var _spray_timer: float = 0.0
var _spray_duration: float = 0.0
var _is_spraying: bool = false
const SPRAY_ARC_HEIGHT: float = 80.0  # Peak height of the arc in pixels
const SPRAY_SPEED: float = 400.0  # Pixels per second (determines duration from distance)
const SPRAY_MIN_DURATION: float = 0.1
const SPRAY_MAX_DURATION: float = 0.4

const S: int = 64  # sprite size (2x2 tiles)
## Drawn over the grass (z 10) and the blasts (z 20), under the words
## (KillText, PickupText: z 21, drawn after the items): the original's items
## were Z 11, over its wall layer's 8 and the blasts' 10.
const ITEM_Z := 21

## "Hold Enemy" taken by an enemy holds the players for 10000 ticks.
const ENEMY_HOLD_TIME: float = 7.5
## A player's "Hold Enemy" holds the enemies this long, s, and "Who PA Who"
## shields the player this long (Sean, 2026-10-08; they were 40 s and 60 s;
## the original's were 15 s, 7.5 s more while over 7.5 s were left, and 18.75 s).
## A hold left at a stage's end runs on into the next (GameManager.advance_stage).
const FREEZE_TIME: float = 20.0
const HELMET_TIME: float = 25.0

func setup(type: int, delay: float = 0.0, origin: Vector2 = Vector2.ZERO) -> void:
	cookie_type = type
	_pickup_delay = delay
	var info: Dictionary = CookieData.COOKIE_INFO.get(cookie_type, {})
	if not info.is_empty():
		_despawn_time = info["despawn_time"]
	if origin != Vector2.ZERO:
		_spray_origin = origin

func _ready() -> void:
	z_index = ITEM_Z
	add_to_group("cookies")
	add_to_group(NetWorld.GROUP)
	body_entered.connect(_on_body_entered)
	# Set collision
	set_collision_layer_value(7, true)  # powerups layer
	set_collision_mask_value(3, true)   # player tanks
	set_collision_mask_value(4, true)   # enemy tanks: they take some items too
	# Update collision shape to 2x2 tile size
	var col := get_node_or_null("CollisionShape2D")
	if col:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(S, S)
		col.shape = rect
	# Set sprite from image asset
	if has_node("Sprite2D"):
		var tex := CookieData.get_cookie_texture(cookie_type)
		if tex:
			$Sprite2D.texture = tex
			var tex_size := tex.get_size()
			$Sprite2D.scale = Vector2(S / tex_size.x, S / tex_size.y)
		$Sprite2D.modulate = Color.WHITE
	# Start spray animation if origin was set (one sprayed out by the host's word
	# of it is set already: net_setup)
	if _spray_origin != Vector2.ZERO and not net_sprayed_here:
		_spray_target = global_position
		global_position = _spray_origin
		var dist := _spray_origin.distance_to(_spray_target)
		_spray_duration = clampf(dist / SPRAY_SPEED, SPRAY_MIN_DURATION, SPRAY_MAX_DURATION)
		_spray_timer = 0.0
		_is_spraying = true
		# Start small and grow during flight
		scale = Vector2(0.3, 0.3)
		# Disable collision during spray
		set_deferred("monitoring", false)

func _process(delta: float) -> void:
	if Net.is_client():
		# The host times and hands out every item; this one only shows it,
		# sprayed out here as the host's word says (net_setup).
		if _is_spraying:
			_spray_step(delta)
		return
	if _is_spraying:
		_spray_step(delta)
		return  # Don't tick lifetime or fade during spray

	# Tick pickup delay
	if _pickup_delay > 0.0:
		_pickup_delay -= delta
		if _pickup_delay <= 0.0:
			_delay_just_expired = true

	# After delay expires, check if a tank is already overlapping
	if _delay_just_expired:
		_delay_just_expired = false
		for body in get_overlapping_bodies():
			_on_body_entered(body)
			if is_queued_for_deletion():
				return

	# An enemy sitting on an item it could not take may be allowed it later (a
	# MAX turns it into the stronger type): the original checked every frame.
	if monitoring and _pickup_delay <= 0.0:
		for body in get_overlapping_bodies():
			if body is EnemyTank:
				_on_body_entered(body)
				if is_queued_for_deletion():
					return

	_lifetime += delta

	# Breathing + fade when past 50% lifetime
	var fade_start: float = _despawn_time * 0.5
	if _lifetime <= fade_start:
		modulate.a = 1.0
	else:
		var fade_progress: float = (_lifetime - fade_start) / (_despawn_time - fade_start)
		# Base alpha fades from 1.0 down to 0.05
		var base_alpha: float = lerpf(1.0, 0.05, fade_progress)
		# Slow sine breathing that gets faster as time runs out
		# Speed: starts at 2 Hz, ramps up to 5 Hz near the end
		var breath_speed: float = lerpf(0.5, 1.0, fade_progress)
		var breath: float = (sin(_lifetime * breath_speed * TAU) + 1.0) * 0.5  # 0.0 to 1.0
		# Breathing amplitude shrinks as base_alpha gets lower
		var amplitude: float = base_alpha * 0.4
		modulate.a = base_alpha - amplitude + breath * amplitude

	if _lifetime > _despawn_time:
		queue_free()

## One step of the spray, [param delta] s on: an arc from the origin to where it
## lands, growing as it goes.
func _spray_step(delta: float) -> void:
	_spray_timer += delta
	var t: float = clampf(_spray_timer / _spray_duration, 0.0, 1.0)
	global_position = _spray_point()
	# Scale: grow from 0.3 to 1.0
	var s: float = lerpf(0.3, 1.0, 1.0 - (1.0 - t) * (1.0 - t))
	scale = Vector2(s, s)
	if t >= 1.0:
		_is_spraying = false
		global_position = _spray_target
		scale = Vector2.ONE
		# Re-enable collision after landing
		if not Net.is_client():
			set_deferred("monitoring", true)

## Where the spray has it now: an arc from the origin to where it lands,
## easing out, peaking halfway.
func _spray_point() -> Vector2:
	var t: float = clampf(_spray_timer / _spray_duration, 0.0, 1.0)
	var pos := _spray_origin.lerp(_spray_target, 1.0 - (1.0 - t) * (1.0 - t))
	pos.y -= -4.0 * SPRAY_ARC_HEIGHT * t * (t - 1.0)
	return pos

## True while it's sprayed out, not yet down.
func is_spraying() -> bool:
	return _is_spraying

## Host: a player's tank may take it now (take_for): down, and its pickup delay over.
func may_be_taken() -> bool:
	return not _is_spraying and _pickup_delay <= 0.0 and not is_queued_for_deletion()

## Host: [param player]'s tank takes it where the client driving that tank had
## it (PlayerTank._take_items_where_reported), as if it had driven onto it here.
func take_for(player: PlayerTank) -> void:
	_on_body_entered(player)

# --- Online (NetWorld): an item is its type and, while it's sprayed out of a
# tank, where from and where to (a client sprays it out itself, from when the
# host's word comes: no stale arc after it's down); where it is, its size (it
# grows as it's sprayed out) and how faded it is (it breathes out as it
# expires).

const NET_GLIDES: Array[int] = [2, 3]
## Client: sprayed out here by the host's word of it (net_setup): its place and
## size are its own, not the host's states'.
var net_sprayed_here := false

func net_type() -> int:
	return NetWorld.T_COOKIE

func net_spawn_args() -> Array:
	if not _is_spraying:
		return [cookie_type]
	return [cookie_type, _spray_origin.x, _spray_origin.y, _spray_target.x, _spray_target.y,
			_spray_duration, _spray_timer]

func net_state() -> Array:
	return [global_position.x, global_position.y, scale.x, modulate.a]

func net_setup(args: Array) -> void:
	cookie_type = int(args[0])
	if args.size() >= 7:
		_spray_origin = Vector2(args[1], args[2])
		_spray_target = Vector2(args[3], args[4])
		_spray_duration = maxf(float(args[5]), SPRAY_MIN_DURATION)
		_spray_timer = float(args[6])
		_is_spraying = true
		net_sprayed_here = true
		scale = Vector2.ONE * 0.3

func net_apply(state: Array) -> void:
	if not net_sprayed_here:
		scale = Vector2.ONE * float(state[2])
	modulate.a = float(state[3])

## Client: where it shows, for the host's [param at] (NetClientWorld._place):
## one sprayed out here goes by its own spray, then lies where it landed.
func net_place(at: Vector2) -> Vector2:
	if not net_sprayed_here:
		return at
	return _spray_point() if _is_spraying else _spray_target

func _on_body_entered(body: Node2D) -> void:
	if Net.is_client():
		return
	if _pickup_delay > 0.0 or is_queued_for_deletion():
		return  # cannot be picked up yet, or already taken this frame
	if body is PlayerTank:
		Events.cookie_collected.emit(cookie_type, body.player_id)
		_apply_effect(body)
	elif body is EnemyTank and _enemy_may_take(body):
		Events.cookie_collected.emit(cookie_type, -1)
		_apply_enemy_effect(body)
	else:
		return  # an enemy it isn't for just drives over it
	_show_words()
	queue_free()

## The item's name floats up where it was taken, as in the original (PickupText).
func _show_words() -> void:
	var effects := get_tree().get_first_node_in_group("effects_container")
	if effects:
		PickupText.spawn(effects, cookie_type, global_position)

## An enemy may take its own gun's item, and more once it is the stronger tank
## of its pair or wears memory-save (EnemyTank.can_take_cookie).
func _enemy_may_take(enemy: EnemyTank) -> bool:
	return enemy.can_take_cookie(cookie_type)

## Every enemy on the field, not counting any still appearing.
func _enemies_on_field() -> Array[EnemyTank]:
	var found: Array[EnemyTank] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyTank
		if enemy and not enemy.is_materializing and not enemy.is_queued_for_deletion():
			found.append(enemy)
	return found

## What an item does taken by an enemy (Tank.exe's pickup with no player): the
## upgrades and add-ons build the taker up, the two MAX items every enemy, and
## the specials turn against the players.
func _apply_enemy_effect(enemy: EnemyTank) -> void:
	enemy.activate_pickup_invulnerability()
	# The upgrades and add-ons free the taker from a mine's slow; the MAX items
	# free every enemy they reach.
	if cookie_type in EnemyTank.UPGRADE_ITEMS:
		enemy.clear_mine_slow()
	match cookie_type:
		CookieData.CookieType.SPEED_UP:
			enemy.item_speed_up()
		CookieData.CookieType.HP_UP:
			enemy.item_hp_up()
		CookieData.CookieType.WEAPONS_UP:
			enemy.item_gun_up()
		CookieData.CookieType.STAR_UP:
			enemy.item_speed_up()
			enemy.item_hp_up()
			enemy.item_gun_up()
		CookieData.CookieType.MAX_UP:
			for other in _enemies_on_field():
				other.item_max_up()
		CookieData.CookieType.ANTI_WATER_COOKIE, CookieData.CookieType.ANTI_ICE_COOKIE, \
				CookieData.CookieType.MOON_SHIELD_COOKIE, CookieData.CookieType.MEMORY_SAVE_COOKIE:
			enemy.set_addon(CookieData.ADDON_TO_COOKIE.find_key(cookie_type))
		CookieData.CookieType.BULLETS_MAX:
			for other in _enemies_on_field():
				other.item_caisson_max()
		CookieData.CookieType.INVINCIBLE_HELMET:
			# "Who PA Who": a moon shield for every enemy, even one still appearing.
			for other in get_tree().get_nodes_in_group("enemies"):
				if other is EnemyTank and not other.is_queued_for_deletion():
					other.set_addon(EnemyTank.ADDON_MOON_SHIELD)
		CookieData.CookieType.FLAG_PROTECTION:
			Events.base_guard_broken.emit()
		CookieData.CookieType.TANK_WEB:
			Events.freeze_players.emit(ENEMY_HOLD_TIME)
		CookieData.CookieType.TANK_BOMB:
			Events.bomb_all_players.emit()
		CookieData.CookieType.TANK_LIFE:
			Events.enemy_reinforcements.emit(enemy.tank_type_id)
		# "Caisson" and a gun's own item gave an enemy a pack of ammo. The remake's
		# enemies never run out, so there is nothing to add.

## A mine's slow wears off only through these, as in the original: any add-on
## cookie frees the tank that takes it, and MAX frees every player.
func _clear_mine_slows(player: PlayerTank) -> void:
	if cookie_type in CookieData.ADDON_TO_COOKIE.values():
		player.clear_mine_slow()
	elif cookie_type == CookieData.CookieType.MAX_UP:
		for teammate in get_tree().get_nodes_in_group("players"):
			if teammate is PlayerTank and is_instance_valid(teammate):
				teammate.clear_mine_slow()

func _apply_effect(player: PlayerTank) -> void:
	# Grant 1-second pickup invincibility
	player.activate_pickup_invincibility()
	_clear_mine_slows(player)

	match cookie_type:
		# utility_power_up
		CookieData.CookieType.SPEED_UP:
			player.apply_cookie_speed_up()
		CookieData.CookieType.HP_UP:
			player.apply_cookie_hp_up()
		CookieData.CookieType.WEAPONS_UP:
			player.apply_cookie_weapons_up()
		CookieData.CookieType.STAR_UP:
			player.apply_cookie_star_up()
		CookieData.CookieType.MAX_UP:
			player.apply_cookie_max_up()
		# addon
		CookieData.CookieType.ANTI_WATER_COOKIE:
			player.apply_addon("anti-water")
		CookieData.CookieType.ANTI_ICE_COOKIE:
			player.apply_addon("anti-ice")
		CookieData.CookieType.MOON_SHIELD_COOKIE:
			player.apply_addon("moon-shield")
		CookieData.CookieType.MEMORY_SAVE_COOKIE:
			player.apply_addon("memory-save")
		# utility_score_up
		CookieData.CookieType.SCORE_200:
			GameManager.add_score_direct(player.player_id, 200)
		CookieData.CookieType.SCORE_500:
			GameManager.add_score_direct(player.player_id, 500)
		CookieData.CookieType.SCORE_1000:
			GameManager.add_score_direct(player.player_id, 1000)
		CookieData.CookieType.SCORE_2000:
			GameManager.add_score_direct(player.player_id, 2000)
		# utility_special
		CookieData.CookieType.INVINCIBLE_HELMET:
			player.activate_helmet(HELMET_TIME)
		CookieData.CookieType.FLAG_PROTECTION:
			Events.fortify_base.emit(60.0)
		CookieData.CookieType.TANK_WEB:
			Events.freeze_enemies.emit(FREEZE_TIME)
		CookieData.CookieType.TANK_BOMB:
			Events.bomb_all_enemies.emit(player.player_id)
			PlayerTank.rumble_player(player.player_id, PlayerTank.BOMB_RUMBLE)  # as hard as losing a tank
		CookieData.CookieType.TANK_LIFE:
			GameManager.add_life(player.player_id)
		CookieData.CookieType.BULLETS_MAX:
			player.apply_cookie_bullets_max()
		CookieData.CookieType.BULLET_REFILL:
			player.apply_cookie_bullet_refill()
		# weapon
		CookieData.CookieType.RAPID_COOKIE:
			player.set_secondary_weapon("rapid")
		CookieData.CookieType.FIRE_COOKIE:
			player.set_secondary_weapon("fire")
		CookieData.CookieType.AP_COOKIE:
			player.set_secondary_weapon("ap")
		CookieData.CookieType.EXPLOSION_COOKIE:
			player.set_secondary_weapon("explosion")
		CookieData.CookieType.MINE_COOKIE:
			player.set_secondary_weapon("mine")
