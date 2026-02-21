class_name PlayerTank
extends BaseTank

@export var player_id: int = 0  # 0 or 1

var star_level: int = 0
var has_boat: bool = false
var is_invincible: bool = false
var invincible_timer: float = 0.0
var is_spawning: bool = false
var spawn_timer: float = 0.0

const SPAWN_INVINCIBILITY: float = 3.0
const POWERUP_INVINCIBILITY: float = 10.0

var _input_prefix: String = "p1_"

# Player colors
const PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.0),   # Player 1: Yellow/Gold
	Color(0.3, 0.85, 0.3),   # Player 2: Green
]

func _ready() -> void:
	super._ready()
	_input_prefix = "p%d_" % (player_id + 1)
	add_to_group("players")
	star_level = GameManager.get_star_level(player_id)
	_apply_star_upgrades()
	_activate_invincibility(SPAWN_INVINCIBILITY)
	# Set collision layers
	set_collision_layer_value(1, false)
	set_collision_layer_value(3, true)  # player_tanks
	set_collision_mask_value(1, true)   # walls
	set_collision_mask_value(2, true)   # water
	set_collision_mask_value(4, true)   # enemy_tanks
	set_collision_mask_value(6, true)   # enemy_bullets
	set_collision_mask_value(7, true)   # powerups
	# Apply theme sprite and color
	if sprite:
		var tank_key := "p1" if player_id == 0 else "p2"
		var theme_tex := ThemeManager.get_tank_texture(tank_key)
		if theme_tex:
			sprite.texture = theme_tex
		if ThemeManager.is_tank_modulate_mode():
			sprite.modulate = PLAYER_COLORS[player_id]
		else:
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

	if input_dir != Vector2.ZERO:
		try_move(input_dir)
	else:
		if not is_on_ice:
			stop_moving()

	move_and_slide()

	if Input.is_action_just_pressed(_input_prefix + "shoot"):
		shoot()

func apply_powerup(type: int) -> void:
	match type:
		0:  # STAR
			star_level = mini(star_level + 1, 3)
			GameManager.set_star_level(player_id, star_level)
			_apply_star_upgrades()
		1:  # HELMET
			_activate_invincibility(POWERUP_INVINCIBILITY)
		5:  # TANK (extra life)
			GameManager.add_life(player_id)
		6:  # BOAT
			has_boat = true
			set_collision_mask_value(2, false)  # can cross water

func _apply_star_upgrades() -> void:
	match star_level:
		0:
			bullet_speed = 256.0
			max_bullets = 1
			move_speed = 128.0
		1:
			bullet_speed = 384.0
			max_bullets = 1
			move_speed = 128.0
		2:
			bullet_speed = 384.0
			max_bullets = 2
			move_speed = 128.0
		3:
			bullet_speed = 384.0
			max_bullets = 2
			move_speed = 160.0

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
	invincible_timer = duration
	_update_shield_visual(true)

func _update_shield_visual(active: bool) -> void:
	var shield = get_node_or_null("ShieldEffect")
	if shield:
		shield.visible = active

func take_damage() -> void:
	if is_invincible:
		return
	super.take_damage()

func destroy() -> void:
	Events.player_died.emit(player_id)
	GameManager.lose_life(player_id)
	_spawn_explosion()
	queue_free()
