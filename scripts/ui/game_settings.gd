class_name GameSettings
extends RefCounted
## The settings' GAME tab, shared by the title screen and the pause menu: the
## difficulty, the game's speed, whether the base can fall, whether the enemies'
## mine tanks lay mines, and the strongest mine they lay. Each applies at once,
## in a running stage too (GameManager.set_difficulty, and InputSettings'
## game_speed_changed, base_invincible_changed and enemy_mines_changed).
##
## The host keeps this object, puts [method rows] in its navigation and passes
## left / right on them through [method adjust], as with CommonSettings.

const DIFFICULTY_NAMES: Array[String] = ["EASY", "NORMAL", "HARD", "EXPERT", "INSANE"]
## A row that does nothing for now (ENEMY MINE LEVEL with the mines off) is
## dimmed, as the controls page dims its fixed rows.
const OFF_ROW_TINT := Color(1, 1, 1, 0.5)

var difficulty_row: Button
var game_speed_row: Button
var base_row: Button
var enemy_mines_row: Button
var mine_level_row: Button


func _init(container: VBoxContainer) -> void:
	difficulty_row = _add_value_row(container, "DIFFICULTY", _cycle_difficulty)
	game_speed_row = _add_value_row(container, "GAME SPEED", _cycle_game_speed)
	base_row = _add_value_row(container, "BASE INVINCIBLE", _toggle_base_invincible)
	enemy_mines_row = _add_value_row(container, "ENEMY MINES", _toggle_enemy_mines)
	mine_level_row = _add_value_row(container, "ENEMY MINE LEVEL", _cycle_mine_level)
	refresh()


## The rows, top to bottom, for the host's navigation.
func rows() -> Array[Control]:
	return [difficulty_row, game_speed_row, base_row, enemy_mines_row, mine_level_row]


## Left / right on [param focused]: steps its setting. False when it isn't one
## of these rows.
func adjust(focused: Control, direction: int) -> bool:
	if focused == difficulty_row:
		_cycle_difficulty(direction)
	elif focused == game_speed_row:
		_cycle_game_speed(direction)
	elif focused == base_row:
		_toggle_base_invincible(direction)
	elif focused == enemy_mines_row:
		_toggle_enemy_mines(direction)
	elif focused == mine_level_row:
		_cycle_mine_level(direction)
	else:
		return false
	return true


## The rows as the settings are now. ENEMY MINE LEVEL is greyed out, and skipped
## by the keys, while the enemies lay no mines.
func refresh() -> void:
	var difficulty := clampi(GameManager.difficulty, 1, GameManager.MAX_DIFFICULTY)
	MenuRows.value_label(difficulty_row).text = "%d   %s" % [difficulty, tr(DIFFICULTY_NAMES[difficulty - 1])]
	MenuRows.arrow(difficulty_row, "Left").disabled = difficulty <= 1
	MenuRows.arrow(difficulty_row, "Right").disabled = difficulty >= GameManager.MAX_DIFFICULTY
	var speed := InputSettings.get_saved_game_speed()
	MenuRows.value_label(game_speed_row).text = "%d%%" % speed
	MenuRows.arrow(game_speed_row, "Left").disabled = speed <= InputSettings.GAME_SPEEDS[0]
	MenuRows.arrow(game_speed_row, "Right").disabled = speed >= InputSettings.GAME_SPEEDS[-1]
	MenuRows.value_label(base_row).text = "ON" if InputSettings.get_base_invincible() else "OFF"
	var mines := InputSettings.get_enemy_mines()
	MenuRows.value_label(enemy_mines_row).text = "ON" if mines else "OFF"
	var level := InputSettings.get_enemy_mine_level()
	MenuRows.value_label(mine_level_row).text = str(level)
	mine_level_row.disabled = not mines
	mine_level_row.modulate = Color.WHITE if mines else OFF_ROW_TINT
	MenuRows.arrow(mine_level_row, "Left").disabled = not mines or level <= InputSettings.ENEMY_MINE_LEVEL_MIN
	MenuRows.arrow(mine_level_row, "Right").disabled = not mines or level >= InputSettings.ENEMY_MINE_LEVEL_MAX


## The difficulty one step up or down, stopping at EASY and INSANE: a running
## stage takes it up at once, and new games start from it.
func _cycle_difficulty(direction: int) -> void:
	GameManager.set_difficulty(GameManager.difficulty + direction)
	refresh()


## The next speed of the original's five, stopping at either end; a running
## stage takes it up at once (game.gd).
func _cycle_game_speed(direction: int) -> void:
	var speeds := InputSettings.GAME_SPEEDS
	var at := speeds.find(InputSettings.get_saved_game_speed())
	InputSettings.save_game_speed(speeds[clampi(at + direction, 0, speeds.size() - 1)])
	refresh()


## The base invincible or not: on, no shell can destroy it, and its flag shows
## the guard (Bullet, LevelManager), in a running stage at once.
func _toggle_base_invincible(_direction: int) -> void:
	InputSettings.save_base_invincible(not InputSettings.get_base_invincible())
	refresh()


## Enemy mines on or off. Off, the mine tanks fire rapid shells, those on the
## field at once, and the enemies' mines already laid go (EnemyTank, LevelManager).
func _toggle_enemy_mines(_direction: int) -> void:
	InputSettings.save_enemy_mines(not InputSettings.get_enemy_mines())
	refresh()


## The strongest mine an enemy lays, 1-4, stopping at either end.
func _cycle_mine_level(direction: int) -> void:
	if not InputSettings.get_enemy_mines():
		return
	InputSettings.save_enemy_mine_level(InputSettings.get_enemy_mine_level() + direction)
	refresh()


func _add_value_row(container: VBoxContainer, title: String, cycle: Callable) -> Button:
	var row := MenuRows.make_value_row(title)
	container.add_child(row)
	row.mouse_entered.connect(row.grab_focus)   # hovering focuses, as everywhere in the menus
	row.pressed.connect(cycle.bind(1))
	for side: String in ["Left", "Right"]:
		var arrow := MenuRows.arrow(row, side)
		arrow.pressed.connect(cycle.bind(-1 if side == "Left" else 1))
		arrow.mouse_entered.connect(row.grab_focus)
	return row
