extends Node2D

@onready var level_manager: LevelManager = $Playfield
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var players_container: Node2D = $Entities/Players
@onready var enemies_container: Node2D = $Entities/Enemies
@onready var bullets_container: Node2D = $Entities/Bullets
@onready var powerups_container: Node2D = $Entities/PowerUps
@onready var effects_container: Node2D = $Entities/Effects
@onready var eagle: StaticBody2D = $Playfield/Eagle
@onready var hud: Control = $HUD

var _game_over_pending: bool = false
var _stage_clear_pending: bool = false

func _ready() -> void:
	add_to_group("game")
	enemies_container.add_to_group("enemies_container")
	bullets_container.add_to_group("bullets_container")
	powerups_container.add_to_group("powerups_container")
	effects_container.add_to_group("effects_container")

	# Connect signals
	Events.all_enemies_defeated.connect(_on_all_enemies_defeated)
	Events.base_destroyed.connect(_on_base_destroyed)
	Events.game_over.connect(_on_game_over)
	Events.enemy_destroyed.connect(_on_enemy_destroyed)
	Events.bomb_all_enemies.connect(_on_bomb_all_enemies)
	Events.freeze_enemies.connect(_on_freeze_enemies)
	Events.fortify_base.connect(_on_fortify_base)
	Events.player_died.connect(_on_player_died)

	_start_stage()

func _start_stage() -> void:
	# Load level
	level_manager.load_stage(GameManager.current_stage)

	# Spawn players
	_spawn_player(0)
	if GameManager.is_two_player:
		_spawn_player(1)

	# Start enemy spawning
	enemy_spawner.start_stage(GameManager.current_stage)

func _spawn_player(player_id: int) -> void:
	if GameManager.player_lives[player_id] < 0:
		return
	var player_scene := preload("res://scenes/tanks/player_tank.tscn")
	var player: PlayerTank = player_scene.instantiate()
	player.player_id = player_id

	# Spawn positions: P1 bottom-left area, P2 bottom-right area
	# Tanks are 2x2 tiles, centered on even tile boundaries
	var pf: Vector2 = level_manager.global_position
	var spawn_x: float
	if player_id == 0:
		spawn_x = pf.x + 12 * 32 + 32  # Grid columns 12-13 center
	else:
		spawn_x = pf.x + 26 * 32 + 32  # Grid columns 26-27 center

	var spawn_y: float = pf.y + 28 * 32 + 32  # Grid rows 28-29 center

	player.global_position = Vector2(spawn_x, spawn_y)
	players_container.add_child(player)

func get_level_manager() -> LevelManager:
	return level_manager

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		get_tree().paused = not get_tree().paused

func _on_enemy_destroyed(enemy: Node2D, points: int) -> void:
	GameManager.enemies_remaining -= 1
	# Award points to closest player (simplified)
	GameManager.add_score(0, points, enemy.tank_type_id)
	_update_hud()

func _on_all_enemies_defeated() -> void:
	if _stage_clear_pending:
		return
	_stage_clear_pending = true
	Events.stage_cleared.emit()
	# Wait a moment then go to next stage
	await get_tree().create_timer(2.0).timeout
	GameManager.next_stage()

func _on_base_destroyed() -> void:
	# Destroy eagle visual
	if eagle and eagle.has_node("Sprite2D"):
		eagle.get_node("Sprite2D").modulate = Color.RED
	# Spawn big explosion
	var explosion_scene := preload("res://scenes/effects/explosion.tscn")
	var explosion := explosion_scene.instantiate()
	explosion.global_position = eagle.global_position
	explosion.scale = Vector2(5, 5)
	effects_container.add_child(explosion)
	GameManager.trigger_game_over()

func _on_game_over() -> void:
	if _game_over_pending:  
		return
	_game_over_pending = true
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/game_over_screen.tscn")

func _on_player_died(player_id: int) -> void:
	if GameManager.player_lives[player_id] >= 0:
		# Respawn after a short delay
		await get_tree().create_timer(1.0).timeout
		if not _game_over_pending:
			_spawn_player(player_id)

func _on_bomb_all_enemies() -> void:
	enemy_spawner.destroy_all_enemies()

func _on_freeze_enemies(duration: float) -> void:
	GameManager.freeze_all_enemies(duration)

func _on_fortify_base(duration: float) -> void:
	level_manager.fortify_base(duration)

func _update_hud() -> void:
	if hud and hud.has_method("update_display"):
		hud.update_display()
