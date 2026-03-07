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
@onready var pause_menu: Control = $PauseLayer/PauseMenu

var _game_over_pending: bool = false
var _stage_clear_pending: bool = false
var _game_over_countdown: float = -1.0
var _base_destroyed: bool = false
var _player_dead_timers: Array[float] = [0.0, 0.0]  # Time since each player died (lives < 0)
const GAME_OVER_COUNTDOWN_DURATION: float = 15.0
const PLAYER_HUD_CLEAR_TIME: float = 15.0

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

	# Connect pause menu signals
	if pause_menu:
		pause_menu.restart_requested.connect(_on_pause_restart)
		pause_menu.main_menu_requested.connect(_on_pause_main_menu)
		pause_menu.exit_requested.connect(_on_pause_exit)

	# Snapshot state at stage start (for restart)
	GameManager.save_stage_start_snapshot()

	_start_stage()

func _start_stage() -> void:
	# Load level
	level_manager.load_stage(GameManager.current_stage)

	# Spawn active players
	for pid in range(2):
		if GameManager.player_active[pid]:
			_spawn_player(pid)

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
		spawn_x = pf.x + 17 * 32 + 32  # Grid columns 17-18 center (left of eagle)
	else:
		spawn_x = pf.x + 21 * 32 + 32  # Grid columns 21-22 center (right of eagle)

	var spawn_y: float = pf.y + 28 * 32 + 32  # Grid rows 28-29 center

	player.global_position = Vector2(spawn_x, spawn_y)
	players_container.add_child(player)

func get_level_manager() -> LevelManager:
	return level_manager

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:  # ` backtick
			Events.bomb_all_enemies.emit()

func _process(delta: float) -> void:
	# Block pause menu during game over / stage clear
	if pause_menu:
		pause_menu.set_can_open(not _game_over_pending and not _stage_clear_pending)

	if _game_over_pending or _stage_clear_pending:
		return

	# Mid-game join: inactive or dead player can join by pressing fire
	for pid in range(2):
		if not GameManager.player_active[pid] or GameManager.player_lives[pid] < 0:
			var prefix: String = "p1_" if pid == 0 else "p2_"
			if Input.is_action_just_pressed(prefix + "shoot") or Input.is_action_just_pressed(prefix + "shoot2"):
				if GameManager.rejoin_player(pid):
					GameManager.player_active[pid] = true
					_player_dead_timers[pid] = 0.0
					_spawn_player(pid)
					# Restore base if it was destroyed
					if _base_destroyed:
						_restore_base()
					if _game_over_countdown >= 0:
						_game_over_countdown = -1.0  # Cancel countdown
						_update_hud()

	# Track per-player dead timers
	for pid in range(2):
		if GameManager.player_active[pid] and GameManager.player_lives[pid] < 0:
			_player_dead_timers[pid] += delta
		else:
			_player_dead_timers[pid] = 0.0

	# Game over countdown
	if _game_over_countdown >= 0:
		_game_over_countdown -= delta
		_update_hud()
		if _game_over_countdown <= 0:
			_game_over_countdown = -1.0
			GameManager.trigger_game_over()

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
	# Save live player HP and addons before leaving stage
	GameManager.save_player_states()
	# Wait 10s so players can collect remaining cookies
	await get_tree().create_timer(10.0).timeout
	# Increment counter (total stages won) and advance stage
	# (save happens inside next_stage after stage number is updated)
	GameManager.save_counter += 1
	GameManager.next_stage()

func _on_base_destroyed() -> void:
	if _base_destroyed:
		return
	_base_destroyed = true
	# Destroy eagle visual
	if eagle and eagle.has_node("Sprite2D"):
		eagle.get_node("Sprite2D").modulate = Color.RED
	# Spawn big explosion
	var explosion_scene := preload("res://scenes/effects/explosion.tscn")
	var explosion := explosion_scene.instantiate()
	explosion.global_position = eagle.global_position
	explosion.scale = Vector2(5, 5)
	effects_container.add_child(explosion)
	# Wipe all active players' lives so they can't respawn
	for pid in range(2):
		if GameManager.player_active[pid]:
			GameManager.player_lives[pid] = -1
			GameManager.player_speed_levels[pid] = 1
			GameManager.player_weapon_levels[pid] = 1
			GameManager.player_secondary_weapon_types[pid] = "rapid"
			GameManager.player_secondary_weapon_counts[pid] = CookieData.WEAPON_DATA["rapid"]["reload_count"]
			GameManager.player_hp[pid] = 4
			GameManager.player_addons[pid] = []
	# Remove all player tanks visually (explosion + free) without going through
	# destroy() which would trigger respawn timers via _on_player_died
	for tank in get_tree().get_nodes_in_group("players"):
		if is_instance_valid(tank) and tank is PlayerTank:
			tank._spawn_explosion()
			tank.queue_free()
	# Start countdown for rejoin
	if _game_over_countdown < 0 and not _game_over_pending:
		_game_over_countdown = GAME_OVER_COUNTDOWN_DURATION

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
	else:
		# Player is out of lives — check if all active players are dead
		if GameManager.all_active_players_dead() and _game_over_countdown < 0 and not _game_over_pending:
			_game_over_countdown = GAME_OVER_COUNTDOWN_DURATION

func _on_bomb_all_enemies() -> void:
	enemy_spawner.destroy_all_enemies()

func _on_freeze_enemies(duration: float) -> void:
	GameManager.freeze_all_enemies(duration)

func _on_fortify_base(duration: float) -> void:
	level_manager.fortify_base(duration)

func _restore_base() -> void:
	_base_destroyed = false
	# Restore eagle visual
	if eagle and eagle.has_node("Sprite2D"):
		eagle.get_node("Sprite2D").modulate = Color.WHITE
	# Fortify the base walls
	level_manager.fortify_base(30.0)

func get_game_over_countdown() -> float:
	return _game_over_countdown

func get_player_dead_timer(pid: int) -> float:
	return _player_dead_timers[pid]

func _update_hud() -> void:
	if hud and hud.has_method("update_display"):
		hud.update_display()

# --- Pause menu actions ---

func _on_pause_restart() -> void:
	GameManager.restart_current_stage()

func _on_pause_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_pause_exit() -> void:
	get_tree().quit()
