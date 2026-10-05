extends Node

## The game's difficulty was changed while it runs (set_difficulty).
signal difficulty_changed

var current_stage: int = 1
var player_active: Array[bool] = [false, false]
## An active player sitting out (the pause menu's PLAYER 2 option): no tank on the
## field, but everything they had is kept, in the save too, for when they return.
var player_disabled: Array[bool] = [false, false]
var is_game_over: bool = false
var enemies_frozen: bool = false
## The players are held (an enemy took "Hold Enemy"): no driving, no firing.
var players_frozen: bool = false
var players_freeze_timer: float = 0.0
var current_map_pool_id: String = ""

# --- Difficulty ---
## The original's hardest level, which only looping the map reaches.
const MAX_DIFFICULTY := 5
var difficulty: int = 1  # 1-5
var start_difficulty: int = 1  # Difficulty when game started (saved)

# --- Save system ---
var current_save_file: String = ""  # Path to active .tsave file (empty if no save yet)
var save_counter: int = 0  # Total stages won in this save
var save_created_iso: String = ""  # ISO timestamp when save was first created

# --- Per-player persistent data ---
# Starting at 3: first game start is treated as a "revive" (4 lives, use 1 = 3)
var player_lives: Array[int] = [3, 3]
var player_scores: Array[int] = [0, 0]
var player_speed_levels: Array[int] = [1, 1]    # 0-3, default 1
var player_weapon_levels: Array[int] = [0, 0]    # 0-3, default 0
var player_secondary_weapon_types: Array[String] = ["rapid", "rapid"]
var player_secondary_weapon_counts: Array[int] = [50, 50]  # default rapid reload_count
var player_hp: Array[int] = [4, 4]                          # current HP, persists across stages
var player_addons: Array[Array] = [[], []]                   # addon name lists, persists across stages
var player_kills: Array[Dictionary] = [{}, {}]  # kills by enemy type per player

# --- This stage's best chains, for the results panel (the original's MaxHits and
# MaxCombos). A hit chain goes on while each hit on an enemy lands within
# HIT_CHAIN_WINDOW of the last (60 frames); a combo while each kill lands within
# COMBO_WINDOW (180 frames). Folded into the best when it lapses (0x498dac).
const HIT_CHAIN_WINDOW: float = 0.9
const COMBO_WINDOW: float = 2.7
var player_max_hits: Array[int] = [0, 0]
var player_max_combos: Array[int] = [0, 0]
var _hit_chains: Array[int] = [0, 0]
var _hit_chain_timers: Array[float] = [0.0, 0.0]
var _combos: Array[int] = [0, 0]
var _combo_timers: Array[float] = [0.0, 0.0]

var enemies_remaining: int = 20
var freeze_timer: float = 0.0
var _stage_start_snapshot: Dictionary = {}

const EXTRA_LIFE_SCORE: int = 20000

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if Net.is_client():
		return  # online, a client's copy of these is the host's
	if enemies_frozen:
		freeze_timer -= delta
		if freeze_timer <= 0:
			enemies_frozen = false
	if players_frozen:
		players_freeze_timer -= delta
		if players_freeze_timer <= 0:
			players_frozen = false
	_tick_chains(delta)

func reset() -> void:
	current_stage = 1
	is_game_over = false
	enemies_frozen = false
	players_frozen = false
	player_active = [false, false]
	player_disabled = [false, false]
	player_lives = [3, 3]
	player_scores = [0, 0]
	player_speed_levels = [1, 1]
	player_weapon_levels = [0, 0]
	player_secondary_weapon_types = ["rapid", "rapid"]
	player_secondary_weapon_counts = [50, 50]
	player_hp = [4, 4]
	player_addons = [[], []]
	player_kills = [{}, {}]
	enemies_remaining = 20
	# Save system fields
	current_save_file = ""
	save_counter = 0
	save_created_iso = ""
	start_difficulty = difficulty

## A new game: fresh state, then the join screen.
func start_game() -> void:
	reset()
	start_difficulty = difficulty
	save_created_iso = Time.get_datetime_string_from_system(false, true)
	get_tree().change_scene_to_file("res://scenes/join_screen.tscn")

func next_stage() -> void:
	advance_stage()
	# Auto-save after stage number is updated so loaded game starts on the correct stage
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

## Moves the game on a stage. Past the last it loops back to the first one level
## harder, up to MAX_DIFFICULTY, where the original stopped too (0x499132).
func advance_stage() -> void:
	current_stage += 1
	enemies_remaining = 20
	enemies_frozen = false
	players_frozen = false
	player_kills = [{}, {}]
	if current_stage > get_max_stages():
		current_stage = 1  # Loop back to stage 1
		difficulty = mini(difficulty + 1, MAX_DIFFICULTY)  # Increase difficulty on map loop

## The DIFFICULTY setting (1-5). Unlike the original, which fixed it when a game
## began, it can change any time: a running stage takes it up at once
## (EnemySpawner.apply_difficulty), and new games start from it.
func set_difficulty(value: int) -> void:
	value = clampi(value, 1, MAX_DIFFICULTY)
	InputSettings.save_difficulty(value)
	if value != difficulty:
		difficulty = value
		difficulty_changed.emit()

func get_max_stages() -> int:
	return LevelData.get_stage_count()

func add_score(player_id: int, points: int, enemy_type: int) -> void:
	var old_score := player_scores[player_id]
	player_scores[player_id] += points
	# Track kills by type
	if not player_kills[player_id].has(enemy_type):
		player_kills[player_id][enemy_type] = 0
	player_kills[player_id][enemy_type] += 1
	# Extra life every 20000 points
	if old_score / EXTRA_LIFE_SCORE < player_scores[player_id] / EXTRA_LIFE_SCORE:
		player_lives[player_id] += 1
		SoundManager.play(&"extra_life")

func lose_life(player_id: int) -> void:
	player_lives[player_id] -= 1
	# Reset stats to defaults on death
	player_speed_levels[player_id] = 1
	player_weapon_levels[player_id] = 0
	player_secondary_weapon_types[player_id] = "rapid"
	player_secondary_weapon_counts[player_id] = CookieData.WEAPON_DATA["rapid"]["reload_count"]
	player_hp[player_id] = 4  # DEFAULT_HP
	player_addons[player_id] = []

func add_score_direct(player_id: int, points: int) -> void:
	var old_score := player_scores[player_id]
	player_scores[player_id] += points
	if old_score / EXTRA_LIFE_SCORE < player_scores[player_id] / EXTRA_LIFE_SCORE:
		player_lives[player_id] += 1
		SoundManager.play(&"extra_life")

func add_life(player_id: int) -> void:
	player_lives[player_id] += 1
	SoundManager.play(&"extra_life")

## [param player_id] joins the game. Credits are unlimited (Sean, 2026-10-02):
## joining, and coming back in after a game over, never runs out.
func join_player(player_id: int) -> void:
	player_active[player_id] = true
	player_lives[player_id] = 3

## [param player_id], out of lives, comes back in with fresh lives and a fresh
## tank, as often as they like.
func rejoin_player(player_id: int) -> void:
	player_lives[player_id] = 3
	player_speed_levels[player_id] = 1
	player_weapon_levels[player_id] = 0
	player_secondary_weapon_types[player_id] = "rapid"
	player_secondary_weapon_counts[player_id] = CookieData.WEAPON_DATA["rapid"]["reload_count"]
	player_hp[player_id] = 4
	player_addons[player_id] = []
	Events.player_joined.emit(player_id)

func is_any_player_active() -> bool:
	return player_active[0] or player_active[1]

## In the game and not sitting out: the player has a tank on the field, or will.
func is_player_in_play(player_id: int) -> bool:
	return player_active[player_id] and not player_disabled[player_id]

## Players in play (not those sitting out).
func get_active_player_count() -> int:
	var count := 0
	for pid in range(2):
		if is_player_in_play(pid):
			count += 1
	return count

## No player in play has a life left. One sitting out doesn't count: the stage
## is lost unless someone rejoins, or is brought back in from the pause menu.
func all_active_players_dead() -> bool:
	for pid in range(2):
		if is_player_in_play(pid) and player_lives[pid] >= 0:
			return false
	return true

# --- Speed level ---
func get_speed_level(player_id: int) -> int:
	return player_speed_levels[player_id]

func set_speed_level(player_id: int, level: int) -> void:
	player_speed_levels[player_id] = clampi(level, 0, 3)

# --- Weapon level ---
func get_weapon_level(player_id: int) -> int:
	return player_weapon_levels[player_id]

func set_weapon_level(player_id: int, level: int) -> void:
	player_weapon_levels[player_id] = clampi(level, 0, 3)

# --- Secondary weapon ---
func get_secondary_weapon_type(player_id: int) -> String:
	return player_secondary_weapon_types[player_id]

func get_secondary_weapon_count(player_id: int) -> int:
	return player_secondary_weapon_counts[player_id]

func set_secondary_weapon(player_id: int, weapon_type: String, count: int) -> void:
	if Net.is_client():
		return  # a client's numbers are the host's (NetClientWorld); its own shots don't spend them
	player_secondary_weapon_types[player_id] = weapon_type
	var max_ct: int = CookieData.WEAPON_DATA.get(weapon_type, {}).get("max_count", 200)
	player_secondary_weapon_counts[player_id] = clampi(count, 0, max_ct)

func add_secondary_weapon_ammo(player_id: int, amount: int) -> void:
	var weapon_type: String = player_secondary_weapon_types[player_id]
	var max_ct: int = CookieData.WEAPON_DATA.get(weapon_type, {}).get("max_count", 200)
	player_secondary_weapon_counts[player_id] = clampi(
		player_secondary_weapon_counts[player_id] + amount, 0, max_ct
	)

func set_secondary_weapon_to_max(player_id: int) -> void:
	var weapon_type: String = player_secondary_weapon_types[player_id]
	var max_ct: int = CookieData.WEAPON_DATA.get(weapon_type, {}).get("max_count", 200)
	player_secondary_weapon_counts[player_id] = max_ct

## Save live player tank state to GameManager before stage transition.
## Call this before next_stage() so HP and addons persist.
func save_player_states() -> void:
	for tank in get_tree().get_nodes_in_group("players"):
		if tank is PlayerTank:
			save_player_state(tank)

## [param tank]'s HP and add-ons, the state that lives on the tank; its levels
## and weapon are kept here as they change.
func save_player_state(tank: PlayerTank) -> void:
	var pid: int = tank.player_id
	player_hp[pid] = tank.health
	player_addons[pid] = tank.get_addon_names()

## Set the active map pool by id. Loads the pool's stages into LevelData.
func set_map_pool(pool_id: String) -> void:
	var pools := LevelData.get_available_pools()
	for pool in pools:
		if pool.id == pool_id:
			current_map_pool_id = pool_id
			LevelData.load_pool(pool)
			return
	push_warning("GameManager: Map pool not found: " + pool_id)

func freeze_all_enemies(duration: float) -> void:
	enemies_frozen = true
	freeze_timer = duration

func freeze_all_players(duration: float) -> void:
	players_frozen = true
	players_freeze_timer = duration

## Save a snapshot of all player state at the start of a stage.
## Used by "Restart Stage" in the pause menu to restore state.
func save_stage_start_snapshot() -> void:
	_stage_start_snapshot = {
		"player_active": [player_active[0], player_active[1]],
		"player_lives": [player_lives[0], player_lives[1]],
		"player_scores": [player_scores[0], player_scores[1]],
		"player_speed_levels": [player_speed_levels[0], player_speed_levels[1]],
		"player_weapon_levels": [player_weapon_levels[0], player_weapon_levels[1]],
		"player_secondary_weapon_types": [player_secondary_weapon_types[0], player_secondary_weapon_types[1]],
		"player_secondary_weapon_counts": [player_secondary_weapon_counts[0], player_secondary_weapon_counts[1]],
		"player_hp": [player_hp[0], player_hp[1]],
		"player_addons": [player_addons[0].duplicate(), player_addons[1].duplicate()],
	}

## Restore the snapshot saved at stage start.
func restore_stage_start_snapshot() -> void:
	if _stage_start_snapshot.is_empty():
		return
	player_active = [_stage_start_snapshot["player_active"][0], _stage_start_snapshot["player_active"][1]]
	player_lives = [_stage_start_snapshot["player_lives"][0], _stage_start_snapshot["player_lives"][1]]
	player_scores = [_stage_start_snapshot["player_scores"][0], _stage_start_snapshot["player_scores"][1]]
	player_speed_levels = [_stage_start_snapshot["player_speed_levels"][0], _stage_start_snapshot["player_speed_levels"][1]]
	player_weapon_levels = [_stage_start_snapshot["player_weapon_levels"][0], _stage_start_snapshot["player_weapon_levels"][1]]
	player_secondary_weapon_types = [_stage_start_snapshot["player_secondary_weapon_types"][0], _stage_start_snapshot["player_secondary_weapon_types"][1]]
	player_secondary_weapon_counts = [_stage_start_snapshot["player_secondary_weapon_counts"][0], _stage_start_snapshot["player_secondary_weapon_counts"][1]]
	player_hp = [_stage_start_snapshot["player_hp"][0], _stage_start_snapshot["player_hp"][1]]
	player_addons = [_stage_start_snapshot["player_addons"][0].duplicate(), _stage_start_snapshot["player_addons"][1].duplicate()]

## Restart the current stage, restoring state from stage start.
func restart_current_stage() -> void:
	restore_stage_start_snapshot()
	enemies_remaining = 20
	enemies_frozen = false
	players_frozen = false
	player_kills = [{}, {}]
	is_game_over = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func trigger_game_over() -> void:
	is_game_over = true
	Events.game_over.emit()

# --- Stage statistics ---

## A fresh stage: no kills, hits or combos counted yet.
func reset_stage_stats() -> void:
	player_kills = [{}, {}]
	player_max_hits = [0, 0]
	player_max_combos = [0, 0]
	_hit_chains = [0, 0]
	_hit_chain_timers = [0.0, 0.0]
	_combos = [0, 0]
	_combo_timers = [0.0, 0.0]

## [param player_id]'s weapon took a point off an enemy.
func note_hit(player_id: int) -> void:
	_hit_chains[player_id] += 1
	_hit_chain_timers[player_id] = HIT_CHAIN_WINDOW

## [param player_id] destroyed an enemy.
func note_kill(player_id: int) -> void:
	_combos[player_id] += 1
	_combo_timers[player_id] = COMBO_WINDOW

## [param player_id]'s hit chain going on now (0 once it has lapsed).
func get_hit_chain(player_id: int) -> int:
	return _hit_chains[player_id]

## [param player_id]'s kill combo going on now, its latest kill included (0 once
## it has lapsed).
func get_combo(player_id: int) -> int:
	return _combos[player_id]

## Ends every chain now, counting it: the stage is over. (The original stopped
## folding them at its mission screen, so a stage's last chain slipped into the
## next stage's best; the remake counts it where it was made.)
func settle_chains() -> void:
	for pid in range(2):
		_hit_chain_timers[pid] = 0.0
		_combo_timers[pid] = 0.0
	_tick_chains(0.0)

func _tick_chains(delta: float) -> void:
	for pid in range(2):
		if _hit_chain_timers[pid] > 0.0:
			_hit_chain_timers[pid] -= delta
		elif _hit_chains[pid] > 0:
			player_max_hits[pid] = maxi(player_max_hits[pid], _hit_chains[pid])
			_hit_chains[pid] = 0
		if _combo_timers[pid] > 0.0:
			_combo_timers[pid] -= delta
		elif _combos[pid] > 0:
			player_max_combos[pid] = maxi(player_max_combos[pid], _combos[pid])
			_combos[pid] = 0
