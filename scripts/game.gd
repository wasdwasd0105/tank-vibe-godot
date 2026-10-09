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

## Online, on a client: this scene shows the host's game through a
## NetClientWorld and runs none of it. The host's lose countdown and the
## players' dead timers come with its snapshots.
var _mirror := false
var net_countdown: float = -1.0
var net_dead_timers: Array = [0.0, 0.0]
var _host_paused_banner: Label = null

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

	if Net.is_client():
		_ready_as_mirror()
		return

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

	InputSettings.game_speed_changed.connect(_apply_game_speed)
	_apply_game_speed()
	WindowManager.enter_game()  # fullscreen for play, with ALWAYS FULLSCREEN on

	debug_freeze = DebugFreeze.new()
	debug_freeze.name = "DebugFreeze"
	debug_freeze.setup(level_manager)
	add_child(debug_freeze)

	# Snapshot state at stage start (for restart)
	GameManager.save_stage_start_snapshot()

	if Net.is_host():
		_ready_as_host()
	Net.hosting_started.connect(_on_hosting_started)
	Net.session_ended.connect(_on_session_ended)
	if Net.keep_hosting and not Net.is_online():
		# Switched online earlier and not off since: this stage is open to remote
		# players too (Sean, 2026-10-10), seated as when switched on mid-stage.
		Net.host_from_settings()
	_start_stage()


## Hosting: the clients see this stage through a NetHostWorld. A tank nobody
## has taken sits out until someone does, and one whose driver leaves sits out
## again.
func _ready_as_host() -> void:
	_add_host_world()
	for pid in 2:
		if GameManager.player_active[pid]:
			GameManager.player_disabled[pid] = PlayerInput.seats[pid] == PlayerInput.NO_SEAT
	Net.set_host_screen(Net.SCREEN_GAME)


## This game was opened to others in the middle of it (the pause menu's ONLINE
## tab): player 1 keeps their tank, and tank 2 is free for whoever presses fire
## first, here or there (Sean, 2026-10-06). Player 2, if in the game, sits out
## until then, keeping all they have: a saved two-player game hosted for the
## other machine's player to go on as player 2 would otherwise leave tank 2 on
## this machine's P2 controls, with nothing for them to take.
func _on_hosting_started() -> void:
	if GameManager.is_player_in_play(0):
		PlayerInput.set_seat(0, PlayerInput.LOCAL_P1)
	_on_seat_vacated(1)
	_add_host_world()
	Net.set_host_screen(Net.SCREEN_GAME)


func _add_host_world() -> void:
	if has_node("NetHostWorld"):
		return
	var world := NetHostWorld.new()
	world.setup(self, level_manager, stage_overlay)
	add_child(world)
	if not Net.seat_vacated.is_connected(_on_seat_vacated):
		Net.seat_vacated.connect(_on_seat_vacated)


## The game closed to others with nobody left on it: play goes on offline,
## where only player 2 can sit out.
func _on_session_ended(_reason: String) -> void:
	var world := get_node_or_null("NetHostWorld")
	if world:
		remove_child(world)
		world.queue_free()
	if GameManager.player_disabled[0] and GameManager.player_active[0]:
		if _phase == Phase.PLAY:
			set_player_enabled(0, true)
		else:
			GameManager.player_disabled[0] = false  # it drives out with the next stage
	_update_hud()


## On a client: the map, tanks, screens and scores are the host's. Only the
## menu (which doesn't pause the game here) and leaving are this machine's.
func _ready_as_mirror() -> void:
	_mirror = true
	level_manager.net_mirror = true
	stage_overlay.net_follow = true
	if pause_menu:
		pause_menu.set_online_client(true)
		pause_menu.main_menu_requested.connect(_on_pause_main_menu)
		pause_menu.exit_requested.connect(_on_pause_exit)
	WindowManager.enter_game()
	var world := NetClientWorld.new()
	world.setup(self, level_manager, stage_overlay, {
		"players": players_container, "enemies": enemies_container,
		"bullets": bullets_container, "powerups": powerups_container,
		"terrain": level_manager.terrain_node,
	}, effects_container)
	add_child(world)
	_host_paused_banner = _make_host_paused_banner()


## "PAUSED BY THE HOST" over the field while the host's menu is open.
func _make_host_paused_banner() -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var banner := Label.new()
	banner.theme = preload("res://assets/ui/menu_theme.tres")
	banner.theme_type_variation = &"RowNameLabel"
	banner.text = "PAUSED BY THE HOST"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.position = Vector2(160, 440)
	banner.size = Vector2(1280, 80)
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0, 0, 0, 0.6)
	banner.add_theme_stylebox_override(&"normal", backing)
	banner.visible = false
	layer.add_child(banner)
	return banner


## The host paused or went on: a client's world holds still meanwhile.
func net_set_host_paused(paused: bool) -> void:
	if not _mirror:
		return
	get_tree().paused = paused
	if _host_paused_banner:
		_host_paused_banner.visible = paused


## Online: [param tank]'s driver left or lost the right to drive it. Their
## tank sits out, keeping all it has, until someone takes it (_on_fire_press).
func _on_seat_vacated(tank: int) -> void:
	if not GameManager.is_player_in_play(tank):
		return
	if _phase == Phase.PLAY:
		set_player_enabled(tank, false, true)
	else:
		GameManager.player_disabled[tank] = true

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

## The stage runs at the GAME SPEED setting's pace, as the original's speed
## option set its clock (83 % to 150 %): tanks, shells, timers, the enemies'
## waves and the stage screens alike. Sounds keep their pitch, and outside a
## stage time runs normally.
func _apply_game_speed() -> void:
	Engine.time_scale = InputSettings.get_saved_game_speed() / 100.0

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func get_level_manager() -> LevelManager:
	return level_manager

## Which part of the stage is on: "intro", "play", "mission", "results" or
## "game_over".
func get_phase() -> String:
	if _mirror:
		return "mirror"
	return ["intro", "play", "mission", "results", "game_over"][_phase]

func _unhandled_key_input(event: InputEvent) -> void:
	if _mirror:
		return  # the debug keys are the host's
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:  # ` backtick
			Events.bomb_all_enemies.emit(-1)
		elif event.keycode == KEY_BACKSLASH:  # \ freeze / unfreeze the world
			debug_freeze.toggle()

func _process(delta: float) -> void:
	if _mirror:
		# A client's menu opens any time: it never pauses the host's game.
		if pause_menu:
			pause_menu.set_can_open(true)
		return
	# The pause menu opens during play, never over the stage screens.
	if pause_menu:
		pause_menu.set_can_open(_phase == Phase.PLAY)

	if _phase != Phase.PLAY:
		return

	# Mid-game join: a player out of the game, or out of lives, comes in with
	# fire; online, so does anyone without a tank (see _on_fire_press).
	for press: Dictionary in PlayerInput.fire_presses():
		_on_fire_press(press["key"], press["seat"])

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

## Fire from controller [param key], which drives tank [param seat] (or
## PlayerInput.NO_SEAT). A player out of the game or out of lives comes back in
## beside the base, as often as they like (credits are unlimited); one sitting
## out offline comes back from the pause menu instead. Online, a player without
## a tank takes a free one they may drive: a tank waiting for a driver keeps all
## it had, otherwise they join as that tank's player.
func _on_fire_press(key: int, seat: int) -> void:
	var pid := seat
	if pid < 0:
		if not Net.is_host():
			return
		pid = Net.free_seat_for(key)
		if pid < 0:
			return
		if GameManager.player_active[pid] and GameManager.player_lives[pid] >= 0:
			PlayerInput.set_seat(pid, key)
			set_player_enabled(pid, true)
			return
	elif GameManager.player_disabled[pid]:
		return
	if GameManager.player_active[pid] and GameManager.player_lives[pid] >= 0:
		return  # already playing
	GameManager.rejoin_player(pid)
	if seat < 0:
		PlayerInput.set_seat(pid, key)
	GameManager.player_disabled[pid] = false
	GameManager.player_active[pid] = true
	_player_dead_timers[pid] = 0.0
	_spawn_player(pid)
	# Restore base if it was destroyed
	if _base_destroyed:
		_restore_base()
	_cancel_lose_countdown()

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
		# The score shows over the wreck, and the killer's controller thumps. Not
		# for a bomb's kills, which leave the tanks' health untouched: the
		# original's bomb bypassed its Damage routine, which is where it wrote
		# them (and the bomb's own big rumble covers them).
		if enemy.health <= 0:
			KillText.spawn(effects_container, points, GameManager.get_combo(pid), enemy.global_position)
			PlayerTank.rumble_player(pid, PlayerTank.KILL_RUMBLE)
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
	NetHostWorld.record(NetWorld.EV_EXPLOSION, [eagle.global_position.x, eagle.global_position.y, 5.0])
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

## Everyone is out: there's a while to rejoin (credits are unlimited), and the
## enemies hold back their reinforcements meanwhile; then the stage is lost.
func _start_lose_countdown() -> void:
	if _game_over_countdown >= 0 or _phase != Phase.PLAY:
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
func set_player_enabled(player_id: int, enabled: bool, vacated: bool = false) -> void:
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
	# The one left may have been out of lives already. (Online, a tank left
	# without a driver doesn't start it: the stage waits for one.)
	if GameManager.all_active_players_dead() and not vacated:
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
	if Net.is_host():
		# Online, everyone goes back to the lobby for another game.
		GameManager.start_game()
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_bomb_all_enemies(player_id: int) -> void:
	enemy_spawner.destroy_all_enemies(player_id)
	level_manager.set_off_enemy_mines()  # their mines too, the players and theirs spared

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
	return net_countdown if _mirror else _game_over_countdown

func get_player_dead_timer(pid: int) -> float:
	return float(net_dead_timers[pid]) if _mirror else _player_dead_timers[pid]

func _update_hud() -> void:
	if hud and hud.has_method("update_display"):
		hud.update_display()

# --- Pause menu actions ---

func _on_pause_restart() -> void:
	GameManager.restart_current_stage()

func _on_pause_main_menu() -> void:
	# Online, this leaves the game: a host ends it for everyone, and a client
	# goes back to the ONLINE screen, to join again or another.
	var tree := get_tree()
	var was_client := Net.is_client()
	if Net.is_online():
		Net.leave()
		tree.paused = false
	tree.change_scene_to_file("res://scenes/online_screen.tscn" if was_client else "res://scenes/main.tscn")

func _on_pause_exit() -> void:
	Net.leave()  # online, the others hear why first
	get_tree().quit()
