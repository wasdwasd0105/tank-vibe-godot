extends Node

var current_stage: int = 1
var is_two_player: bool = false
var is_game_over: bool = false
var enemies_frozen: bool = false
var current_map_pool_id: String = ""

# --- Credits (shared between both players) ---
var credits: int = 3
var max_credits: int = 3

# --- Per-player persistent data ---
# Starting at 3: first game start is treated as a "revive" (4 lives, use 1 = 3)
var player_lives: Array[int] = [3, 3]
var player_scores: Array[int] = [0, 0]
var player_speed_levels: Array[int] = [1, 1]    # 0-3, default 1
var player_weapon_levels: Array[int] = [1, 1]    # 0-3, default 1
var player_secondary_weapon_types: Array[String] = ["rapid", "rapid"]
var player_secondary_weapon_counts: Array[int] = [50, 50]  # default rapid reload_count
var player_hp: Array[int] = [4, 4]                          # current HP, persists across stages
var player_addons: Array[Array] = [[], []]                   # addon name lists, persists across stages
var player_kills: Array[Dictionary] = [{}, {}]  # kills by enemy type per player

var enemies_remaining: int = 20
var freeze_timer: float = 0.0

const EXTRA_LIFE_SCORE: int = 20000

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if enemies_frozen:
		freeze_timer -= delta
		if freeze_timer <= 0:
			enemies_frozen = false

func reset() -> void:
	current_stage = 1
	is_game_over = false
	enemies_frozen = false
	credits = max_credits
	player_lives = [3, 3]
	player_scores = [0, 0]
	player_speed_levels = [1, 1]
	player_weapon_levels = [1, 1]
	player_secondary_weapon_types = ["rapid", "rapid"]
	player_secondary_weapon_counts = [50, 50]
	player_hp = [4, 4]
	player_addons = [[], []]
	player_kills = [{}, {}]
	enemies_remaining = 20

func start_game(two_player: bool) -> void:
	is_two_player = two_player
	reset()
	get_tree().change_scene_to_file("res://scenes/stage_intro.tscn")

func next_stage() -> void:
	current_stage += 1
	enemies_remaining = 20
	enemies_frozen = false
	player_kills = [{}, {}]
	if current_stage > get_max_stages():
		current_stage = 1  # Loop back
	get_tree().change_scene_to_file("res://scenes/stage_intro.tscn")

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

func lose_life(player_id: int) -> void:
	player_lives[player_id] -= 1
	# Reset stats to defaults on death
	player_speed_levels[player_id] = 1
	player_weapon_levels[player_id] = 1
	player_secondary_weapon_types[player_id] = "rapid"
	player_secondary_weapon_counts[player_id] = CookieData.WEAPON_DATA["rapid"]["reload_count"]
	player_hp[player_id] = 4  # DEFAULT_HP
	player_addons[player_id] = []

	if player_lives[player_id] < 0:
		# Try to use a shared credit
		if credits > 0:
			credits -= 1
			# 1 credit = 4 new lives, use 1 to revive = 3 left
			player_lives[player_id] = 3
		else:
			# Player is out of lives and credits
			if is_two_player:
				if player_lives[0] < 0 and player_lives[1] < 0:
					trigger_game_over()
			else:
				trigger_game_over()

func add_score_direct(player_id: int, points: int) -> void:
	var old_score := player_scores[player_id]
	player_scores[player_id] += points
	if old_score / EXTRA_LIFE_SCORE < player_scores[player_id] / EXTRA_LIFE_SCORE:
		player_lives[player_id] += 1

func add_life(player_id: int) -> void:
	player_lives[player_id] += 1

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
			var pid: int = tank.player_id
			player_hp[pid] = tank.health
			# Collect active addons from the tank
			var addons: Array = []
			if tank.has_moon_shield:
				addons.append("moon-shield")
			if tank._current_utility_addon != "":
				addons.append(tank._current_utility_addon)
			player_addons[pid] = addons

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

func trigger_game_over() -> void:
	is_game_over = true
	Events.game_over.emit()
