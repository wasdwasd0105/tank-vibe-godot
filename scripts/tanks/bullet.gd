class_name Bullet
extends Area2D

@export var speed: float = 256.0
var direction: Vector2 = Vector2.UP
var owner_tank: BaseTank = null
var is_player_bullet: bool = true
var can_destroy_steel: bool = false
var _destroyed: bool = false

var _level_manager: LevelManager = null

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	monitoring = true
	monitorable = true
	# Cache level manager reference
	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("get_level_manager"):
		_level_manager = game.get_level_manager()

func _physics_process(delta: float) -> void:
	if _destroyed:
		return

	var movement: Vector2 = direction * speed * delta
	position += movement

	# Check bounds (playfield boundaries)
	if position.x < 32 or position.x > 480 or position.y < 0 or position.y > 448:
		_destroy()
		return

	# Proactively check tile collision every frame using grid lookup
	_check_tile_collision()

func _check_tile_collision() -> void:
	if not _level_manager or _destroyed:
		return

	# Check both bullet center and tip to avoid tunneling through thin walls
	var positions_to_check: Array[Vector2] = [
		global_position,
		global_position + direction * 4.0,  # tip of bullet
	]

	for check_pos in positions_to_check:
		if _destroyed:
			return
		var tile_pos: Vector2i = _level_manager.world_to_tile(check_pos)
		_try_hit_tile(tile_pos)

func _try_hit_tile(tile_pos: Vector2i) -> void:
	if not _level_manager._tile_data.has(tile_pos):
		return

	var data: Dictionary = _level_manager._tile_data[tile_pos]
	var tile_type: int = data.get("type", 0)

	match tile_type:
		LevelData.Tile.BRICK:
			_level_manager._damage_brick(tile_pos, direction)
			_destroy()
		LevelData.Tile.STEEL:
			if can_destroy_steel:
				_level_manager._remove_tile(tile_pos)
			_destroy()
		LevelData.Tile.WATER:
			pass  # Bullets pass through water
		LevelData.Tile.TREE:
			pass  # Bullets pass through trees
		LevelData.Tile.ICE:
			pass  # Bullets pass through ice

func _on_body_entered(body: Node2D) -> void:
	if _destroyed:
		return
	if body == owner_tank:
		return

	# Tank hits
	if is_player_bullet and body is EnemyTank:
		body.take_damage()
		_destroy()
	elif not is_player_bullet and body is PlayerTank:
		if not body.is_invincible:
			body.take_damage()
		_destroy()
	elif body.is_in_group("eagle"):
		Events.base_destroyed.emit()
		_destroy()
	# Note: boundary walls and tile walls are now handled by _check_tile_collision()
	# but we still catch boundaries here as backup
	elif body.is_in_group("boundary"):
		_destroy()

func _on_area_entered(area: Area2D) -> void:
	if _destroyed:
		return
	if area is Bullet:
		var other_bullet := area as Bullet
		if is_player_bullet != other_bullet.is_player_bullet:
			other_bullet._destroy()
			_destroy()

func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	if owner_tank and is_instance_valid(owner_tank):
		owner_tank.on_bullet_destroyed()
	# Spawn small explosion
	var explosion_scene := preload("res://scenes/effects/explosion.tscn")
	var explosion := explosion_scene.instantiate()
	explosion.global_position = global_position
	explosion.scale = Vector2(0.5, 0.5)
	var effects_container = get_tree().get_first_node_in_group("effects_container")
	if effects_container:
		effects_container.add_child(explosion)
	else:
		get_tree().current_scene.add_child(explosion)
	queue_free()
