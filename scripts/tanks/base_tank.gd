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

@onready var sprite: Sprite2D = $Sprite2D
@onready var shoot_cooldown: Timer = $ShootCooldown

func _ready() -> void:
	health = max_health
	add_to_group("tanks")
	if shoot_cooldown:
		shoot_cooldown.timeout.connect(_on_shoot_cooldown_timeout)

func try_move(new_direction: Vector2) -> void:
	if new_direction != current_direction:
		current_direction = new_direction
		# Snap perpendicular axis to grid
		if new_direction.x != 0:
			position.y = round(position.y / HALF_TILE) * HALF_TILE
		else:
			position.x = round(position.x / HALF_TILE) * HALF_TILE
		_update_sprite_direction()
	velocity = current_direction * move_speed
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
	bullet_speed_override: float = -1.0
) -> void:
	var bullet_scene := preload("res://scenes/tanks/bullet.tscn")
	var bullet: Bullet = bullet_scene.instantiate()
	bullet.direction = current_direction
	bullet.speed = bullet_speed_override if bullet_speed_override > 0.0 else bullet_speed
	bullet.owner_tank = self
	bullet.is_player_bullet = is_in_group("players")
	bullet.visual_lane_offsets = visual_lane_offsets.duplicate()
	bullet.collision_lane_offsets = collision_lane_offsets.duplicate()
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

func _spawn_single_row_bullet(row_offset: float, bullet_speed_override: float = -1.0) -> void:
	var spawn_position := global_position + current_direction * (TANK_SIZE * 0.5)
	spawn_position += _get_firing_right_vector() * row_offset
	_spawn_bullet(spawn_position, [0.0], _get_single_row_collision_offsets(row_offset), bullet_speed_override)

func on_bullet_destroyed() -> void:
	active_bullets = maxi(active_bullets - 1, 0)

func take_damage() -> void:
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
