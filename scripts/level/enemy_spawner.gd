class_name EnemySpawner
extends Node2D

@export var spawn_interval: float = 2.0
@export var max_concurrent_enemies: int = 4

var _spawn_queue: Array = []  # Array of int (tank type IDs 1-24)
var _current_spawn_point: int = 0
var _active_enemies: int = 0
var _total_spawned: int = 0

@onready var spawn_timer: Timer = $SpawnTimer

var spawn_points: Array[Marker2D] = []

func _ready() -> void:
	for child in get_children():
		if child is Marker2D:
			spawn_points.append(child)
	if spawn_timer:
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)

func start_stage(stage_num: int) -> void:
	_spawn_queue.clear()
	_total_spawned = 0
	_active_enemies = 0

	# Get the sequential spawn queue of tank type IDs (1-24)
	_spawn_queue = LevelData.get_enemy_spawn_queue(stage_num)

	GameManager.enemies_remaining = _spawn_queue.size()

	max_concurrent_enemies = LevelData.get_max_concurrent(stage_num)
	if GameManager.get_active_player_count() >= 2:
		max_concurrent_enemies = maxi(max_concurrent_enemies, 6)

	spawn_timer.wait_time = spawn_interval
	spawn_timer.start()

	# Spawn first enemy immediately
	_spawn_enemy()

func _on_spawn_timer_timeout() -> void:
	if _spawn_queue.is_empty():
		spawn_timer.stop()
		return
	if _active_enemies >= max_concurrent_enemies:
		return
	_spawn_enemy()

func _spawn_enemy() -> void:
	if _spawn_queue.is_empty():
		return
	if spawn_points.is_empty():
		return

	var spawn_pos: Vector2 = spawn_points[_current_spawn_point % spawn_points.size()].global_position
	_current_spawn_point = (_current_spawn_point + 1) % spawn_points.size()

	# Check if spawn point is clear
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = spawn_pos
	query.collision_mask = 0b1100  # player and enemy tanks
	var results := space_state.intersect_point(query)
	if not results.is_empty():
		return  # Spawn point blocked, try next tick

	var type_id: int = _spawn_queue.pop_front()

	# Clear any wall/brick tiles at the spawn area so the tank doesn't get stuck
	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("get_level_manager"):
		var lm = game.get_level_manager()
		if lm:
			lm.clear_spawn_area(spawn_pos)

	var enemy_scene := preload("res://scenes/tanks/enemy_tank.tscn")
	var enemy: EnemyTank = enemy_scene.instantiate()
	enemy.tank_type_id = type_id

	var enemies_container = get_tree().get_first_node_in_group("enemies_container")
	if enemies_container:
		enemies_container.add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.tree_exited.connect(_on_enemy_removed)
	# The tank materializes only after its spawn burst finishes playing.
	enemy.begin_materialize(SpawnBurst.DURATION)
	SpawnBurst.spawn_at(get_tree(), spawn_pos)

	_total_spawned += 1
	_active_enemies += 1

func _on_enemy_removed() -> void:
	_active_enemies -= 1
	if _spawn_queue.is_empty() and _active_enemies <= 0:
		Events.all_enemies_defeated.emit()

func destroy_all_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.destroy()

func get_remaining_count() -> int:
	return _spawn_queue.size() + _active_enemies
