extends Control

@onready var enemy_count_label: Label = $RightPanel/EnemyCount
@onready var stage_label: Label = $RightPanel/StageLabel

@onready var p1_lives_label: Label = $LeftPanel/P1Lives
@onready var p1_score_label: Label = $LeftPanel/P1Score
@onready var p2_header: Label = $LeftPanel/P2Header
@onready var p2_lives_label: Label = $LeftPanel/P2Lives
@onready var p2_score_label: Label = $LeftPanel/P2Score

func _ready() -> void:
	update_display()

func _process(_delta: float) -> void:
	update_display()

func update_display() -> void:
	if enemy_count_label:
		enemy_count_label.text = str(GameManager.enemies_remaining)
	if stage_label:
		stage_label.text = str(GameManager.current_stage)
	if p1_lives_label:
		p1_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[0], 0))
	if p1_score_label:
		p1_score_label.text = str(GameManager.player_scores[0])
	if GameManager.is_two_player:
		if p2_header:
			p2_header.visible = true
		if p2_lives_label:
			p2_lives_label.text = "Lives: " + str(maxi(GameManager.player_lives[1], 0))
			p2_lives_label.visible = true
		if p2_score_label:
			p2_score_label.text = str(GameManager.player_scores[1])
			p2_score_label.visible = true
	else:
		if p2_header:
			p2_header.visible = false
		if p2_lives_label:
			p2_lives_label.visible = false
		if p2_score_label:
			p2_score_label.visible = false
