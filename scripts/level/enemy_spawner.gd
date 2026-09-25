class_name EnemySpawner
extends Node2D
## Sends a stage's enemies onto the field as Tank.exe did (0x4cbbbe, 0x498190;
## docs/enemy_spawn_original_spec.md).
##
## They come in waves: one to four tries, then 0.9375 s for each try until the
## next wave, however many came; the first wave comes when begin() says (3 s
## into play). A try is refused while the field holds the stage's limit or
## none are left to come, and that ends the wave. Each enemy comes in on a
## random tank-sized spot along the top of the field with no wall or water on
## it, as a random one of the types still to come.

## A wave's most tries (the original's Random(4) + 1).
const WAVE_MAX_TRIES: int = 4
## How long each of a wave's tries holds the next wave back (1250 ticks).
const WAVE_GAP_PER_TRY: float = 0.9375
## A spawn spot is a tank's 2x2 tiles, its top-left on the field's top row.
const SPOT_SIZE := Vector2i(2, 2)
const NO_SPOT := Vector2i(-1, -1)

@export var max_concurrent_enemies: int = 4

## The type IDs (1-24) still to come, one entry per tank, in no particular order.
var _spawn_queue: Array = []
var _active_enemies: int = 0
var _total_spawned: int = 0
var _halted: bool = false

@onready var spawn_timer: Timer = $SpawnTimer

func _ready() -> void:
	if spawn_timer:
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)

## Readies [param stage_num]'s enemies and starts sending them in at once.
func start_stage(stage_num: int) -> void:
	prepare_stage(stage_num)
	begin()

## Lines up [param stage_num]'s enemies (the HUD counts them from here) without
## sending any yet.
func prepare_stage(stage_num: int) -> void:
	_spawn_queue.clear()
	_total_spawned = 0
	_active_enemies = 0
	_halted = false

	# Every tank the stage lists, as many as the difficulty sends
	_spawn_queue = LevelData.get_enemy_spawn_queue(stage_num, GameManager.difficulty)

	GameManager.enemies_remaining = _spawn_queue.size()

	# Worked out once a stage, as the original did; the players don't change it.
	max_concurrent_enemies = LevelData.get_max_concurrent(stage_num, GameManager.difficulty)

## Starts sending the enemies in: the first wave after [param first_delay]
## seconds (at once for 0), then wave after wave until the stage ends. A stage
## the difficulty left without enemies is won there and then.
func begin(first_delay: float = 0.0) -> void:
	if _spawn_queue.is_empty():
		Events.all_enemies_defeated.emit()
		return
	if first_delay > 0.0:
		spawn_timer.start(first_delay)
		return
	_send_wave()

## Holds the reinforcements back ([param held]) or lets them come again.
func hold(held: bool) -> void:
	spawn_timer.paused = held

## No more enemies this stage.
func halt() -> void:
	_halted = true
	spawn_timer.stop()

func _on_spawn_timer_timeout() -> void:
	_send_wave()

## One wave (0x4cbbc7): one to four tries, ending at the first one refused, and
## the next wave 0.9375 s later for each try, however many enemies came. The
## waves go on while the stage does, so enemies that join late still come.
func _send_wave() -> void:
	var tries := randi_range(1, WAVE_MAX_TRIES)
	for i in tries:
		if not _spawn_enemy():
			break
	spawn_timer.start(tries * WAVE_GAP_PER_TRY)

## One try of a wave: an enemy comes in if there's room for it on the field, one
## still to come and a spot for it. False if it was refused.
func _spawn_enemy() -> bool:
	if _spawn_queue.is_empty() or _active_enemies >= max_concurrent_enemies:
		return false
	var lm := _level_manager()
	if lm == null:
		return false
	var spot := _pick_spot(lm)
	if spot == NO_SPOT:
		return false
	var spawn_pos := _spot_centre(lm, spot)
	var type_id := _take_type()

	var enemy_scene := preload("res://scenes/tanks/enemy_tank.tscn")
	var enemy: EnemyTank = enemy_scene.instantiate()
	enemy.tank_type_id = type_id

	var enemies_container = get_tree().get_first_node_in_group("enemies_container")
	if enemies_container:
		enemies_container.add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.tree_exited.connect(_on_enemy_removed)
	# The tank materializes only after its spawn burst finishes playing.
	enemy.begin_materialize(SpawnBurst.DURATION)
	SpawnBurst.spawn_at(get_tree(), spawn_pos)

	_total_spawned += 1
	_active_enemies += 1
	return true

func _level_manager() -> LevelManager:
	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("get_level_manager"):
		return game.get_level_manager()
	return null

## Where the next enemy comes in, as its spot's top-left tile: a random one of
## the 39 spots along the top of the field with no wall or water on it, as the
## original picked (0x4981ea); grass and ice are fine. The original let a tank
## appear on top of another, so unlike it, a spot with a tank on it or
## appearing there is passed over. NO_SPOT when every open spot is taken.
func _pick_spot(lm: LevelManager) -> Vector2i:
	var spots: Array[Vector2i] = []
	for col in LevelManager.GRID_WIDTH - 1:
		if lm.is_open_ground(Vector2i(col, 0), SPOT_SIZE):
			spots.append(Vector2i(col, 0))
	# A map walled in all along its top, which hung the original: any spot will
	# do, cleared for the tank.
	var walled_in := spots.is_empty()
	if walled_in:
		for col in LevelManager.GRID_WIDTH - 1:
			spots.append(Vector2i(col, 0))
	var free: Array[Vector2i] = []
	for spot in spots:
		if not _tank_near(_spot_centre(lm, spot)):
			free.append(spot)
	if free.is_empty():
		return NO_SPOT
	var picked: Vector2i = free.pick_random()
	if walled_in:
		lm.clear_spawn_area(_spot_centre(lm, picked))
	return picked

## Where a tank on [param spot] (its top-left tile) has its centre.
func _spot_centre(lm: LevelManager, spot: Vector2i) -> Vector2:
	return lm.tile_to_world(spot) + Vector2(LevelManager.TILE_SIZE, LevelManager.TILE_SIZE) / 2.0

## True if a tank, whether on the field, in the air or still appearing, would
## overlap one centred at [param centre].
func _tank_near(centre: Vector2) -> bool:
	for tank in get_tree().get_nodes_in_group("tanks"):
		if tank.is_queued_for_deletion():
			continue
		var offset: Vector2 = (tank as Node2D).global_position - centre
		if absf(offset.x) < BaseTank.HITBOX_SIZE and absf(offset.y) < BaseTank.HITBOX_SIZE:
			return true
	return false

## The next enemy's type, taken off the queue: any type still to come, each as
## likely as any other however many of it are left (0x4981d6).
func _take_type() -> int:
	var types: Array = []
	for type_id in _spawn_queue:
		if type_id not in types:
			types.append(type_id)
	var type_id: int = types.pick_random()
	_spawn_queue.erase(type_id)
	return type_id

func _on_enemy_removed() -> void:
	# Leaving the game (menu, restart, game over) takes every tank out of the tree
	# along with the spawner. That is not the enemies being beaten, and a stage
	# clear fired from the closing scene crashed on its null get_tree().
	if not is_inside_tree():
		return
	_active_enemies -= 1
	if _spawn_queue.is_empty() and _active_enemies <= 0:
		Events.all_enemies_defeated.emit()

## Every enemy on the field goes up at once (the bomb): the kills are
## [param by_player]'s (-1: nobody's).
func destroy_all_enemies(by_player: int = -1) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.set("killed_by", by_player)
			enemy.destroy()

## An enemy took "+1 UP": one more of every type still to come, and of the
## taker's own type, each sounding the extra-life jingle.
func add_reinforcements(taker_type: int) -> void:
	var types: Array = []
	for type_id in _spawn_queue:
		if type_id not in types:
			types.append(type_id)
	if taker_type not in types:
		types.append(taker_type)
	for type_id in types:
		_spawn_queue.append(type_id)
		GameManager.enemies_remaining += 1
		SoundManager.play(&"extra_life")
	# The waves run until the stage ends; should they have stopped, they start again.
	if not _halted and spawn_timer.is_stopped():
		spawn_timer.start(WAVE_GAP_PER_TRY)

func get_remaining_count() -> int:
	return _spawn_queue.size() + _active_enemies
