class_name EnemyTank
extends BaseTank

enum EnemyType { BASIC = 0, FAST = 1, POWER = 2, ARMOR = 3 }

@export var enemy_type: EnemyType = EnemyType.BASIC
@export var has_powerup: bool = false
@export var points_value: int = 100

var _direction_change_timer: float = 0.0
var _shoot_cooldown: float = 0.0
var _flash_timer: float = 0.0

const TYPE_STATS: Dictionary = {
	EnemyType.BASIC:  { "speed": 96.0,  "health": 1, "bullet_speed": 192.0, "points": 100 },
	EnemyType.FAST:   { "speed": 192.0, "health": 1, "bullet_speed": 256.0, "points": 200 },
	EnemyType.POWER:  { "speed": 128.0, "health": 1, "bullet_speed": 384.0, "points": 300 },
	EnemyType.ARMOR:  { "speed": 128.0, "health": 4, "bullet_speed": 256.0, "points": 400 },
}

const TYPE_COLORS: Dictionary = {
	EnemyType.BASIC: Color(0.7, 0.7, 0.7),     # Grey
	EnemyType.FAST:  Color(0.7, 0.7, 1.0),      # Light blue
	EnemyType.POWER: Color(1.0, 0.5, 0.5),      # Light red
	EnemyType.ARMOR: Color(0.3, 0.8, 0.3),      # Green
}

const ARMOR_COLORS: Array[Color] = [
	Color(0.3, 0.8, 0.3),  # Green (4 HP)
	Color(0.9, 0.9, 0.2),  # Yellow (3 HP)
	Color(0.7, 0.7, 0.7),  # Grey (2 HP)
	Color(0.9, 0.5, 0.3),  # Orange (1 HP)
]

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	var stats: Dictionary = TYPE_STATS[enemy_type]
	move_speed = stats["speed"]
	max_health = stats["health"]
	health = max_health
	bullet_speed = stats["bullet_speed"]
	points_value = stats["points"]
	current_direction = Vector2.DOWN
	_direction_change_timer = randf_range(1.0, 3.0)
	_shoot_cooldown = randf_range(0.5, 2.0)
	# Set collision layers
	set_collision_layer_value(1, false)
	set_collision_layer_value(4, true)  # enemy_tanks
	set_collision_mask_value(1, true)   # walls
	set_collision_mask_value(2, true)   # water
	set_collision_mask_value(3, true)   # player_tanks
	set_collision_mask_value(5, true)   # player_bullets
	# Update sprite color
	_update_color()
	_update_sprite_direction()

func _physics_process(delta: float) -> void:
	if GameManager.enemies_frozen:
		velocity = Vector2.ZERO
		return

	_ai_update(delta)
	velocity = current_direction * move_speed

	var collided := move_and_slide()
	if collided:
		_change_direction()

	# Flash effect for powerup carrier
	if has_powerup:
		_flash_timer += delta
		if sprite:
			if fmod(_flash_timer, 0.3) < 0.15:
				sprite.modulate = Color.RED
			else:
				_update_color()

func _ai_update(delta: float) -> void:
	_direction_change_timer -= delta
	_shoot_cooldown -= delta

	if _direction_change_timer <= 0:
		_direction_change_timer = randf_range(1.0, 3.0)
		if randf() < 0.4:
			_change_direction()

	if _shoot_cooldown <= 0:
		_shoot_cooldown = randf_range(0.5, 2.0)
		shoot()

	# Occasional bias toward eagle
	if randf() < 0.003:
		_bias_toward_eagle()

func _change_direction() -> void:
	var dirs := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	dirs.erase(current_direction)
	current_direction = dirs[randi() % dirs.size()]
	# Snap to grid when changing direction
	if current_direction.x != 0:
		position.y = round(position.y / HALF_TILE) * HALF_TILE
	else:
		position.x = round(position.x / HALF_TILE) * HALF_TILE
	_update_sprite_direction()

func _bias_toward_eagle() -> void:
	var eagle = get_tree().get_first_node_in_group("eagle")
	if not eagle:
		return
	var diff: Vector2 = eagle.global_position - global_position
	if absf(diff.y) > absf(diff.x):
		current_direction = Vector2.DOWN if diff.y > 0 else Vector2.UP
	else:
		current_direction = Vector2.RIGHT if diff.x > 0 else Vector2.LEFT
	_update_sprite_direction()

func _update_color() -> void:
	if not sprite:
		return
	if enemy_type == EnemyType.ARMOR:
		var color_index := clampi(max_health - health, 0, ARMOR_COLORS.size() - 1)
		sprite.modulate = ARMOR_COLORS[color_index]
	else:
		sprite.modulate = TYPE_COLORS[enemy_type]

func take_damage() -> void:
	health -= 1
	_update_color()
	if health <= 0:
		destroy()

func destroy() -> void:
	Events.enemy_destroyed.emit(self, points_value)
	if has_powerup:
		_spawn_powerup()
	_spawn_explosion()
	queue_free()

func _spawn_powerup() -> void:
	var powerup_scene := preload("res://scenes/powerups/powerup.tscn")
	var powerup := powerup_scene.instantiate()
	# Random position on the playfield
	powerup.global_position = Vector2(
		randf_range(48, 48 + 13 * 32),
		randf_range(48, 48 + 13 * 32)
	)
	powerup.global_position = powerup.global_position.snapped(Vector2(32, 32))
	var container = get_tree().get_first_node_in_group("powerups_container")
	if container:
		container.add_child(powerup)
	else:
		get_tree().current_scene.add_child(powerup)
