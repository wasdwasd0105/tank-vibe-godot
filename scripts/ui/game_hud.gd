extends Control

@onready var enemy_count_label: Label = $EnemyCount
@onready var p1_lives_label: Label = $P1Lives
@onready var p2_lives_label: Label = $P2Lives
@onready var stage_label: Label = $StageLabel

func _ready() -> void:
	update_display()

func _process(_delta: float) -> void:
	update_display()

func update_display() -> void:
	if enemy_count_label:
		enemy_count_label.text = "ENEMY\n" + str(GameManager.enemies_remaining)
	if p1_lives_label:
		p1_lives_label.text = "P1: " + str(maxi(GameManager.player_lives[0], 0))
	if p2_lives_label:
		if GameManager.is_two_player:
			p2_lives_label.text = "P2: " + str(maxi(GameManager.player_lives[1], 0))
			p2_lives_label.visible = true
		else:
			p2_lives_label.visible = false
	if stage_label:
		stage_label.text = "ST\n" + str(GameManager.current_stage)
