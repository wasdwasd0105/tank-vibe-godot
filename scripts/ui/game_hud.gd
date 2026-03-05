extends Control

@onready var stage_label: Label = $LeftPanel/StageLabel
@onready var games_played_label: Label = $LeftPanel/GamesPlayed
@onready var p1_lives_label: Label = $LeftPanel/P1Lives
@onready var p1_stats_label: Label = $LeftPanel/P1Stats
@onready var p1_score_label: Label = $LeftPanel/P1Score

@onready var enemy_count_label: Label = $RightPanel/EnemyCount
@onready var credit_label: Label = $RightPanel/CreditLabel
@onready var p2_header: Label = $RightPanel/P2Header
@onready var p2_lives_label: Label = $RightPanel/P2Lives
@onready var p2_stats_label: Label = $RightPanel/P2Stats
@onready var p2_score_label: Label = $RightPanel/P2Score
@onready var countdown_label: Label = $CountdownLabel
@onready var p1_header: Label = $LeftPanel/P1Header

func _ready() -> void:
	update_display()

func _process(_delta: float) -> void:
	update_display()

func _get_player_hp(pid: int) -> int:
	for tank in get_tree().get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == pid:
			return tank.health
	return 0  # Dead / not spawned

func _is_player_hud_hidden(pid: int) -> bool:
	if not GameManager.player_active[pid]:
		return true
	var game_node = get_tree().get_first_node_in_group("game")
	if game_node and game_node.has_method("get_player_dead_timer"):
		if game_node.get_player_dead_timer(pid) >= 15.0:
			return true
	return false

func _format_stats(pid: int) -> String:
	var hp := str(_get_player_hp(pid))
	var spd := str(GameManager.player_speed_levels[pid])
	var wpn := str(GameManager.player_weapon_levels[pid])
	var w2_type := GameManager.player_secondary_weapon_types[pid]
	var w2_count := str(GameManager.player_secondary_weapon_counts[pid])
	return "HP:" + hp + " Spd:" + spd + " Wpn:" + wpn + "\n2nd:" + w2_type + "(" + w2_count + ")"

func update_display() -> void:
	if stage_label:
		stage_label.text = str(GameManager.current_stage)
	if games_played_label:
		games_played_label.text = "Played: " + str(InputSettings.get_games_played())
	if enemy_count_label:
		enemy_count_label.text = str(GameManager.enemies_remaining)

	if credit_label:
		credit_label.text = "Credit: " + str(maxi(GameManager.credits, 0))

	# Player 1 info (left panel)
	var p1_hidden := _is_player_hud_hidden(0)
	if p1_header:
		p1_header.visible = not p1_hidden
	if p1_lives_label:
		p1_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[0], 0))
		p1_lives_label.visible = not p1_hidden
	if p1_stats_label:
		p1_stats_label.text = _format_stats(0)
		p1_stats_label.visible = not p1_hidden
	if p1_score_label:
		p1_score_label.text = str(GameManager.player_scores[0])
		p1_score_label.visible = not p1_hidden

	# Player 2 info (right panel)
	var p2_hidden := _is_player_hud_hidden(1)
	if p2_header:
		p2_header.visible = not p2_hidden
	if p2_lives_label:
		p2_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[1], 0))
		p2_lives_label.visible = not p2_hidden
	if p2_stats_label:
		p2_stats_label.text = _format_stats(1)
		p2_stats_label.visible = not p2_hidden
	if p2_score_label:
		p2_score_label.text = str(GameManager.player_scores[1])
		p2_score_label.visible = not p2_hidden

	# Game over countdown
	if countdown_label:
		var game_node = get_tree().get_first_node_in_group("game")
		if game_node and game_node.has_method("get_game_over_countdown"):
			var countdown: float = game_node.get_game_over_countdown()
			if countdown >= 0:
				countdown_label.text = "REJOIN: %ds" % ceili(countdown)
				countdown_label.visible = true
			else:
				countdown_label.visible = false
		else:
			countdown_label.visible = false
