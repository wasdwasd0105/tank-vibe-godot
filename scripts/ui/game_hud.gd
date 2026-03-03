extends Control

@onready var stage_label: Label = $LeftPanel/StageLabel
@onready var p1_lives_label: Label = $LeftPanel/P1Lives
@onready var p1_stats_label: Label = $LeftPanel/P1Stats
@onready var credit_label: Label = $LeftPanel/CreditLabel
@onready var p1_score_label: Label = $LeftPanel/P1Score

@onready var enemy_count_label: Label = $RightPanel/EnemyCount
@onready var p2_header: Label = $RightPanel/P2Header
@onready var p2_lives_label: Label = $RightPanel/P2Lives
@onready var p2_stats_label: Label = $RightPanel/P2Stats
@onready var p2_score_label: Label = $RightPanel/P2Score

func _ready() -> void:
	update_display()

func _process(_delta: float) -> void:
	update_display()

func _get_player_hp(pid: int) -> int:
	for tank in get_tree().get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == pid:
			return tank.health
	return 0  # Dead / not spawned

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
	if enemy_count_label:
		enemy_count_label.text = str(GameManager.enemies_remaining)

	# Player 1 info (left panel)
	if p1_lives_label:
		p1_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[0], 0))
	if p1_stats_label:
		p1_stats_label.text = _format_stats(0)
	if credit_label:
		credit_label.text = "Credit: " + str(maxi(GameManager.credits, 0))
	if p1_score_label:
		p1_score_label.text = str(GameManager.player_scores[0])

	# Player 2 info (right panel)
	if GameManager.is_two_player:
		if p2_header:
			p2_header.visible = true
		if p2_lives_label:
			p2_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[1], 0))
			p2_lives_label.visible = true
		if p2_stats_label:
			p2_stats_label.text = _format_stats(1)
			p2_stats_label.visible = true
		if p2_score_label:
			p2_score_label.text = str(GameManager.player_scores[1])
			p2_score_label.visible = true
	else:
		if p2_header:
			p2_header.visible = false
		if p2_lives_label:
			p2_lives_label.visible = false
		if p2_stats_label:
			p2_stats_label.visible = false
		if p2_score_label:
			p2_score_label.visible = false
