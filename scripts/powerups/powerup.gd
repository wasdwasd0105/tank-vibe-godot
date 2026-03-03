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

func setup(type: int, delay: float = 0.0, origin: Vector2 = Vector2.ZERO) -> void:
	cookie_type = type
	_pickup_delay = delay
	var info: Dictionary = CookieData.COOKIE_INFO.get(cookie_type, {})
	if not info.is_empty():
		_despawn_time = info["despawn_time"]
	if origin != Vector2.ZERO:
		_spray_origin = origin

func _ready() -> void:
	add_to_group("cookies")
	body_entered.connect(_on_body_entered)
	# Set collision
	set_collision_layer_value(7, true)  # powerups layer
	set_collision_mask_value(3, true)   # player tanks
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
	# Start spray animation if origin was set
	if _spray_origin != Vector2.ZERO:
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
	# Spray animation: arc from origin to target
	if _is_spraying:
		_spray_timer += delta
		var t: float = clampf(_spray_timer / _spray_duration, 0.0, 1.0)
		# Ease-out for smooth landing
		var ease_t: float = 1.0 - (1.0 - t) * (1.0 - t)
		# Horizontal position: lerp from origin to target
		var pos := _spray_origin.lerp(_spray_target, ease_t)
		# Vertical arc: parabola peaking at t=0.5
		var arc: float = -4.0 * SPRAY_ARC_HEIGHT * t * (t - 1.0)
		pos.y -= arc
		global_position = pos
		# Scale: grow from 0.3 to 1.0
		var s: float = lerpf(0.3, 1.0, ease_t)
		scale = Vector2(s, s)
		if t >= 1.0:
			_is_spraying = false
			global_position = _spray_target
			scale = Vector2.ONE
			# Re-enable collision after landing
			set_deferred("monitoring", true)
		return  # Don't tick lifetime or fade during spray

	# Tick pickup delay
	if _pickup_delay > 0.0:
		_pickup_delay -= delta
		if _pickup_delay <= 0.0:
			_delay_just_expired = true

	# After delay expires, check if player is already overlapping
	if _delay_just_expired:
		_delay_just_expired = false
		for body in get_overlapping_bodies():
			if body is PlayerTank:
				_on_body_entered(body)
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

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerTank:
		if _pickup_delay > 0.0:
			return  # Cannot pick up yet
		Events.cookie_collected.emit(cookie_type, body.player_id)
		_apply_effect(body)
		queue_free()

func _apply_effect(player: PlayerTank) -> void:
	# Grant 1-second pickup invincibility
	player.activate_pickup_invincibility()

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
			player._activate_invincibility(60.0)
		CookieData.CookieType.FLAG_PROTECTION:
			Events.fortify_base.emit(60.0)
		CookieData.CookieType.TANK_WEB:
			Events.freeze_enemies.emit(40.0)
		CookieData.CookieType.TANK_BOMB:
			Events.bomb_all_enemies.emit()
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
