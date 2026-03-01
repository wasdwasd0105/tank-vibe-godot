extends Node

var current_stage: int = 1
var is_two_player: bool = false
var is_game_over: bool = false
var enemies_frozen: bool = false

var player_lives: Array[int] = [3, 3]
var player_scores: Array[int] = [0, 0]
var player_stars: Array[int] = [0, 0]
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
	player_lives = [3, 3]
	player_scores = [0, 0]
	player_stars = [0, 0]
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
	player_stars[player_id] = 0
	if player_lives[player_id] < 0:
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

func get_star_level(player_id: int) -> int:
	return player_stars[player_id]

func set_star_level(player_id: int, level: int) -> void:
	player_stars[player_id] = mini(level, 3)

func freeze_all_enemies(duration: float) -> void:
	enemies_frozen = true
	freeze_timer = duration

func trigger_game_over() -> void:
	is_game_over = true
	Events.game_over.emit()
