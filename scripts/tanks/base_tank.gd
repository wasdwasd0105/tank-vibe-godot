class_name BaseTank
extends CharacterBody2D

const HALF_TILE: int = 16
const TILE_SIZE: int = 32

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
	can_shoot = false
	if shoot_cooldown:
		shoot_cooldown.start()
	active_bullets += 1

	var bullet_scene := preload("res://scenes/tanks/bullet.tscn")
	var bullet: Node2D = bullet_scene.instantiate()
	bullet.direction = current_direction
	bullet.speed = bullet_speed
	bullet.owner_tank = self
	bullet.is_player_bullet = is_in_group("players")
	# 3-star player tanks can destroy steel
	if self is PlayerTank and self.star_level >= 3:
		bullet.can_destroy_steel = true
	bullet.global_position = global_position + current_direction * (TILE_SIZE * 0.5)

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
	var effects_container = get_tree().get_first_node_in_group("effects_container")
	if effects_container:
		effects_container.add_child(explosion)
	else:
		get_tree().current_scene.add_child(explosion)

func _on_shoot_cooldown_timeout() -> void:
	can_shoot = true
