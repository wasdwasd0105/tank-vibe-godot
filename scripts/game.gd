extends Node2D
## One stage, from its intro to its end, following Tank.exe's sequence: the
## intro over the new map, play, then "Mission Complete" or "Mission Fail" as
## the stage-end picture closes in, the results panels, and either the next
## stage or "Game Over" and the title. The screens themselves are the
## StageOverlay's; this script runs the stage around them.

@onready var level_manager: LevelManager = $Playfield
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var players_container: Node2D = $Entities/Players
@onready var enemies_container: Node2D = $Entities/Enemies
@onready var bullets_container: Node2D = $Entities/Bullets
@onready var powerups_container: Node2D = $Entities/PowerUps
@onready var effects_container: Node2D = $Entities/Effects
@onready var eagle: BaseFlag = $Playfield/Eagle
@onready var hud: Control = $HUD
@onready var pause_menu: Control = $PauseLayer/PauseMenu
@onready var stage_overlay: StageOverlay = $StageLayer/StageOverlay

## False skips the stage intro and starts play at once (tests that only need a
## running stage set it before adding the scene).
var show_intro: bool = true

var debug_freeze: DebugFreeze

## Where the stage is: its intro, play, then the original's closing screens.
enum Phase { INTRO, PLAY, MISSION, RESULTS, GAME_OVER }
var _phase: Phase = Phase.INTRO
var _won: bool = false

var _stage_clear_pending: bool = false
var _clear_wait: float = 0.0
var _game_over_countdown: float = -1.0
var _base_destroyed: bool = false
var _player_dead_timers: Array[float] = [0.0, 0.0]  # Time since each player died (lives < 0)
## Who has had a tank on the field this stage: they get a results panel.
var _played_stage: Array[bool] = [false, false]
## How long everyone being out waits for a rejoin before the stage is lost
## (Sean's 5 s; the original's was 5.25 s).
const GAME_OVER_COUNTDOWN_DURATION: float = 5.0
const PLAYER_HUD_CLEAR_TIME: float = 15.0
## The original's first enemies came 3 s into play.
const FIRST_WAVE_DELAY: float = 3.0
## A cleared stage waits for its leftover bonus items: up to this long for each
## one still lying on the field (0x4cbb96).
const ITEM_WAIT: float = 2.25

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
	Events.freeze_players.connect(_on_freeze_players)
	Events.bomb_all_players.connect(_on_bomb_all_players)
	Events.base_guard_broken.connect(_on_base_guard_broken)
	Events.enemy_reinforcements.connect(_on_enemy_reinforcements)
	# Deferred: a tank reports its death before its life is taken
	# (PlayerTank.destroy), and the handler needs the count after it.
	Events.player_died.connect(_on_player_died, CONNECT_DEFERRED)

	# Connect pause menu signals
	if pause_menu:
		pause_menu.player_enabled_requested.connect(set_player_enabled)
		pause_menu.restart_requested.connect(_on_pause_restart)
		pause_menu.main_menu_requested.connect(_on_pause_main_menu)
		pause_menu.exit_requested.connect(_on_pause_exit)

	stage_overlay.intro_finished.connect(_begin_play)
	stage_overlay.mission_finished.connect(_show_results)
	stage_overlay.reward_given.connect(_on_reward_given)
	stage_overlay.results_finished.connect(_on_results_finished)
	stage_overlay.game_over_finished.connect(_on_game_over_finished)

	debug_freeze = DebugFreeze.new()
	debug_freeze.name = "DebugFreeze"
	debug_freeze.setup(level_manager)
	add_child(debug_freeze)

	# Snapshot state at stage start (for restart)
	GameManager.save_stage_start_snapshot()

	_start_stage()

## Builds the map and plays the intro over it; the tanks come when it's done.
func _start_stage() -> void:
	level_manager.load_stage(GameManager.current_stage)
	GameManager.reset_stage_stats()
	enemy_spawner.prepare_stage(GameManager.current_stage)
	if show_intro:
		_phase = Phase.INTRO
		stage_overlay.play_intro(GameManager.current_stage)
	else:
		_begin_play()

## The map is revealed: the players' tanks roll in and the enemies follow.
func _begin_play() -> void:
	_phase = Phase.PLAY
	for pid in range(2):
		if GameManager.player_active[pid]:
			_spawn_player(pid)
	enemy_spawner.begin(FIRST_WAVE_DELAY)
	Events.stage_started.emit(GameManager.current_stage)

func _spawn_player(player_id: int) -> void:
	if GameManager.player_lives[player_id] < 0 or GameManager.player_disabled[player_id]:
		return
	_played_stage[player_id] = true
	var player_scene := preload("res://scenes/tanks/player_tank.tscn")
	var player: PlayerTank = player_scene.instantiate()
	player.player_id = player_id

	var spawn_pos := _player_revive_position(player_id)
	player.global_position = spawn_pos
	players_container.add_child(player)
	# The tank materializes only after its spawn burst finishes playing.
	player.begin_materialize(SpawnBurst.DURATION)
	SpawnBurst.spawn_at(get_tree(), spawn_pos)

## Where a player revives: the 2x2 tile block right beside the base (P1 left of the
## eagle, P2 right). If those tiles are walled in, fall back to the nearest clear
## block. Returns the world-space center of the resolved block.
func _player_revive_position(player_id: int) -> Vector2:
	# Eagle is 2x2; world_to_tile(center) lands on its bottom-right tile, so -1,-1
	# gives the top-left tile (e.g. cols 19-20 -> top-left (19,28)).
	var eagle_tl: Vector2i = level_manager.world_to_tile(eagle.global_position) - Vector2i(1, 1)
	var ideal: Vector2i
	if player_id == 0:
		ideal = Vector2i(eagle_tl.x - 2, eagle_tl.y)  # 2x2 immediately left of the eagle
	else:
		ideal = Vector2i(eagle_tl.x + 2, eagle_tl.y)  # 2x2 immediately right of the eagle
	var tl: Vector2i = level_manager.find_clear_area(ideal, Vector2i(2, 2))
	# The 2x2 block center sits at the shared corner of its four tiles.
	return level_manager.tile_to_world(tl) + Vector2(16, 16)

func get_level_manager() -> LevelManager:
	return level_manager

## Which part of the stage is on: "intro", "play", "mission", "results" or
## "game_over".
func get_phase() -> String:
	return ["intro", "play", "mission", "results", "game_over"][_phase]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:  # ` backtick
			Events.bomb_all_enemies.emit(-1)
		elif event.keycode == KEY_BACKSLASH:  # \ freeze / unfreeze the world
			debug_freeze.toggle()

func _process(delta: float) -> void:
	# The pause menu opens during play, never over the stage screens.
	if pause_menu:
		pause_menu.set_can_open(_phase == Phase.PLAY)

	if _phase != Phase.PLAY:
		return

	# Mid-game join: inactive or dead player can join by pressing fire (not one
	# sitting out: they come back from the pause menu)
	for pid in range(2):
		if GameManager.player_disabled[pid]:
			continue
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
					_cancel_lose_countdown()

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
			return

	# A cleared stage ends once its leftover items are picked up or have had
	# their time, while someone is still in it.
	if _stage_clear_pending and not GameManager.all_active_players_dead():
		_clear_wait += delta
		if _items_on_field() - floori(_clear_wait / ITEM_WAIT) <= 0:
			_start_mission(true)

## Bonus items still lying on the field.
func _items_on_field() -> int:
	var count := 0
	for cookie in get_tree().get_nodes_in_group("cookies"):
		if not cookie.is_queued_for_deletion():
			count += 1
	return count

func _on_enemy_destroyed(enemy: Node2D, points: int) -> void:
	GameManager.enemies_remaining -= 1
	# The kill is the player's whose weapon dealt the last point: its score, the
	# results tally and the combo. An enemy's or a grass fire's kill is nobody's.
	var pid: int = enemy.killed_by
	if pid >= 0:
		GameManager.add_score(pid, points, enemy.tank_type_id)
		GameManager.note_kill(pid)
		# The score shows over the wreck. Not for a bomb's kills, which leave the
		# tanks' health untouched: the original's bomb bypassed its Damage routine,
		# which is where it wrote them.
		if enemy.health <= 0:
			KillText.spawn(effects_container, points, GameManager.get_combo(pid), enemy.global_position)
	_update_hud()

func _on_all_enemies_defeated() -> void:
	# A stage only clears while it is being played, never while it is closing.
	if _stage_clear_pending or _phase != Phase.PLAY or not is_inside_tree():
		return
	_stage_clear_pending = true
	_clear_wait = 0.0

func _on_base_destroyed() -> void:
	if _base_destroyed:
		return
	_base_destroyed = true
	if eagle:
		eagle.destroyed = true
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
			GameManager.player_weapon_levels[pid] = 0
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
	_start_lose_countdown()

## Everyone is out. With credits left there's a while to rejoin, and the enemies
## hold back their reinforcements meanwhile; without, the stage is lost at once.
func _start_lose_countdown() -> void:
	if _game_over_countdown >= 0 or _phase != Phase.PLAY:
		return
	if GameManager.credits <= 0:
		GameManager.trigger_game_over()
		return
	_game_over_countdown = GAME_OVER_COUNTDOWN_DURATION
	enemy_spawner.hold(true)

## Someone is back in: the stage goes on.
func _cancel_lose_countdown() -> void:
	if _game_over_countdown >= 0:
		_game_over_countdown = -1.0
		enemy_spawner.hold(false)
		_update_hud()

## Takes [param player_id] out of the stage or brings them back (the pause menu's
## PLAYER 2 option, for a two-player game with one person playing). Sitting out
## costs nothing: their tank leaves the field with its HP and add-ons kept, and
## lives, score, levels and weapon wait untouched, in the save too. Back in, they
## drive out beside the base with all of it, if they have a life left.
func set_player_enabled(player_id: int, enabled: bool) -> void:
	var disabled := not enabled
	if GameManager.player_disabled[player_id] == disabled:
		return  # already so
	GameManager.player_disabled[player_id] = disabled
	_update_hud()  # at once, though the game is paused behind the menu
	if enabled:
		_player_dead_timers[player_id] = 0.0
		_spawn_player(player_id)
		if GameManager.player_lives[player_id] >= 0:
			_cancel_lose_countdown()
		return
	for tank in get_tree().get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == player_id and not tank.is_queued_for_deletion():
			GameManager.save_player_state(tank)
			SpawnBurst.spawn_at(get_tree(), tank.global_position)
			tank.queue_free()
	# The one left may have been out of lives already.
	if GameManager.all_active_players_dead():
		_start_lose_countdown()

func _on_game_over() -> void:
	if _phase != Phase.PLAY:
		return
	_start_mission(false)

func _on_player_died(player_id: int) -> void:
	if GameManager.player_lives[player_id] >= 0:
		# Respawn after a short delay
		await get_tree().create_timer(1.0).timeout
		if _phase == Phase.PLAY:
			_spawn_player(player_id)
	elif GameManager.all_active_players_dead():
		# Player is out of lives, and so is everyone else
		_start_lose_countdown()

## The stage is over: "Mission Complete" ([param won]) or "Mission Fail" over
## the field, which plays on until the stage-end picture has closed over it.
func _start_mission(won: bool) -> void:
	_phase = Phase.MISSION
	_won = won
	_game_over_countdown = -1.0
	enemy_spawner.halt()
	GameManager.settle_chains()
	if won:
		Events.stage_cleared.emit()  # the win jingle (a loss's came with game_over)
		# One more stage cleared in this save: the HUD's "Played" at once, and
		# the Load Game list's count once next_stage() autosaves.
		GameManager.save_counter += 1
	stage_overlay.play_mission(won)
	_update_hud()

## The picture has closed: clear the field under it and count up the stage.
func _show_results() -> void:
	_phase = Phase.RESULTS
	if _won:
		GameManager.save_player_states()  # HP and add-ons go on to the next stage
	var tallies: Array = []
	for pid in range(2):
		if _played_stage[pid]:
			tallies.append({
				"player": pid,
				"kills": GameManager.player_kills[pid],
				"max_hits": GameManager.player_max_hits[pid],
				"max_combos": GameManager.player_max_combos[pid],
			})
	_clear_field()
	stage_overlay.play_results(_won, tallies, GameManager.difficulty)

## Tanks, shells, bonus items and effects go: the original cleared all but the
## picture and the HUD for its results.
func _clear_field() -> void:
	for container: Node in [players_container, enemies_container, bullets_container,
			powerups_container, effects_container]:
		for child in container.get_children():
			child.queue_free()

func _on_reward_given(player: int, amount: int) -> void:
	GameManager.add_score_direct(player, amount)

func _on_results_finished() -> void:
	if _won:
		# The next stage's intro, after an autosave.
		GameManager.next_stage()
		return
	_phase = Phase.GAME_OVER
	stage_overlay.play_game_over()

func _on_game_over_finished() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_bomb_all_enemies(player_id: int) -> void:
	enemy_spawner.destroy_all_enemies(player_id)

func _on_freeze_enemies(duration: float) -> void:
	GameManager.freeze_all_enemies(duration)

func _on_fortify_base(duration: float) -> void:
	level_manager.fortify_base(duration)

# --- Items an enemy took (see Cookie._apply_enemy_effect) ---

func _on_freeze_players(duration: float) -> void:
	GameManager.freeze_all_players(duration)

## "Bomb !!": every player tank on the field is destroyed, invincible or not,
## and dies as it would to a shell (a life, then a new tank). Tanks still
## appearing are spared.
func _on_bomb_all_players() -> void:
	for tank in get_tree().get_nodes_in_group("players"):
		if tank is PlayerTank and not tank.is_materializing and not tank.is_queued_for_deletion():
			tank.health = 0
			tank.destroy()

func _on_base_guard_broken() -> void:
	level_manager.break_base_guard()

func _on_enemy_reinforcements(taker_type: int) -> void:
	enemy_spawner.add_reinforcements(taker_type)

func _restore_base() -> void:
	_base_destroyed = false
	if eagle:
		eagle.destroyed = false
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
