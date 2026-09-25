extends Node
## Headless test for how the difficulty sets a stage's enemies, as the original
## did (docs/difficulty_original_spec.md): each type's count and the limit on
## enemies at once are scaled by the level's percentage and rounded by chance;
## the limit stays within 4-20 and ignores the number of players; a stage left
## without enemies is won at once; looping the map raises the level up to 5.
## Run as an override main scene:
##   Godot --headless res://scenes/test/difficulty_count_test.tscn

var _fail := 0
var _cleared := 0


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


## Calls [param roll] [param n] times: {result: how many times it came up}.
func _tally(roll: Callable, n: int) -> Dictionary:
	var seen := {}
	for i in range(n):
		var result = roll.call()
		seen[result] = seen.get(result, 0) + 1
	return seen


## True if [param seen] (a _tally) holds nothing but [param results].
func _only(seen: Dictionary, results: Array) -> bool:
	for result in seen:
		if result not in results:
			return false
	return true


## How many of each type (1-24) [param queue] holds, index 0 = type 1.
func _by_type(queue: Array) -> Array[int]:
	var counts: Array[int] = []
	for type_id in range(1, 25):
		counts.append(queue.count(type_id))
	return counts


## Stage 1's listing padded to all 24 types.
func _listing(first: Array) -> Array:
	var counts := first.duplicate()
	counts.resize(24)
	for i in range(first.size(), 24):
		counts[i] = 0
	return counts


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	if InputSettings.get_save_path() != InputSettings.TEST_SAVE_PATH:
		print("  FAIL: not a test run: stopping before touching the player's settings")
		tree.quit(1)
		return
	seed(20260925)

	print("\n[A] The original's rounding: the part after the point is the chance of one more")
	var exact := _tally(func() -> int: return LevelData.scale_by_chance(4, 75), 2000)
	check(exact.size() == 1 and exact.get(3) == 2000, "4 × 75 %% is always 3 (%s)" % exact)
	exact = _tally(func() -> int: return LevelData.scale_by_chance(2, 150), 2000)
	check(exact.size() == 1 and exact.get(3) == 2000, "2 × 150 %% is always 3 (%s)" % exact)
	exact = _tally(func() -> int: return LevelData.scale_by_chance(0, 175), 500)
	check(exact.size() == 1 and exact.get(0) == 500, "none stay none (%s)" % exact)
	var ones := _tally(func() -> int: return LevelData.scale_by_chance(1, 75), 4000)
	check(_only(ones, [0, 1]) and absf(ones.get(1, 0) / 4000.0 - 0.75) < 0.03,
		"1 × 75 %%: 1 three times in four, else 0 (%s)" % ones)
	var threes := _tally(func() -> int: return LevelData.scale_by_chance(3, 83), 4000)
	check(_only(threes, [2, 3]) and absf(threes.get(3, 0) / 4000.0 - 0.49) < 0.03,
		"3 × 83 %%: 3 about half the time (49 %%), else 2 (%s)" % threes)

	print("\n[B] Each type of a stage's list, by difficulty")
	var tourist := _listing([4, 2, 4, 2])
	check(LevelData.enemies_for_difficulty(tourist, 2) == _listing([4, 2, 4, 2]),
		"NORMAL (100 %): the list as it is")
	check(LevelData.enemies_for_difficulty(tourist, 0) == _listing([2, 1, 2, 1]),
		"the original's easiest (50 %): half of each")
	var easy := _tally(func() -> Array: return LevelData.enemies_for_difficulty(tourist, 1), 400)
	check(_only(easy, [_listing([3, 1, 3, 1]), _listing([3, 2, 3, 1]), _listing([3, 1, 3, 2]), _listing([3, 2, 3, 2])])
		and easy.size() == 4,
		"EASY (75 %): 3 of each 4; 1 or 2 of each 2, every mix turning up")
	check(LevelData.enemies_for_difficulty(tourist, 5).slice(0, 4) in
		[[7, 3, 7, 3], [7, 4, 7, 3], [7, 3, 7, 4], [7, 4, 7, 4]],
		"INSANE (175 %): 7 of each 4; 3 or 4 of each 2")
	check(LevelData.enemies_for_difficulty([4], 9) == [7] and LevelData.enemies_for_difficulty([4], -3) == [2],
		"a level past 5 counts as 5, one below 0 as 0")
	check(LevelData.enemies_for_difficulty([100, 99, 0], 2) == [0, 99, 0], "a type listed over 99 times is none")

	print("\n[C] The bundled map, stage 1")
	check(LevelData.get_stage_caption(1) == "Tourist",
		"stage 1 is Tourist, the original's first stage, not its title-demo map (%s)" % LevelData.get_stage_caption(1))
	var queue := LevelData.get_enemy_spawn_queue(1, 2)
	check(queue.size() == 12 and _by_type(queue).slice(0, 4) == [4, 2, 4, 2],
		"NORMAL: its 12 enemies as listed (%d)" % queue.size())
	var total := 0
	var always_three := true
	for i in range(400):
		queue = LevelData.get_enemy_spawn_queue(1, 1)
		total += queue.size()
		var types := _by_type(queue)
		always_three = always_three and types[0] == 3 and types[2] == 3 and queue.size() >= 8 and queue.size() <= 10
	check(always_three and absf(total / 400.0 - 9.0) < 0.2,
		"EASY: 8 to 10 enemies, 9 on average (%.2f), always 3 of types 1 and 3" % (total / 400.0))
	queue = LevelData.get_enemy_spawn_queue(1, 5)
	check(queue.size() >= 20 and queue.size() <= 22, "INSANE: 20 to 22 (%d)" % queue.size())
	var blank := LevelData.StageData.new()
	blank.enemy_count = _listing([150])  # a count the original reads as none
	var lone := LevelData.StageData.new()
	lone.enemy_count = _listing([1])
	var bundled := LevelData.get_stage_count()
	LevelData._loaded_stages.append_array([blank, lone])
	check(LevelData.get_enemy_spawn_queue(bundled + 1, 2) == LevelData.DEFAULT_SPAWN_QUEUE,
		"a stage listing no enemies still gets the remake's 20 basic tanks")
	var lone_sizes := _tally(func() -> int: return LevelData.get_enemy_spawn_queue(bundled + 2, 0).size(), 400)
	check(_only(lone_sizes, [0, 1]) and lone_sizes.has(0) and lone_sizes.has(1),
		"a lone tank at 50 %%: there half the time, else rounded away to none (%s)" % lone_sizes)
	LevelData._loaded_stages.resize(bundled)

	print("\n[D] The limit on enemies at once")
	var limit := _tally(func() -> int: return LevelData.on_screen_for_difficulty(4, 1), 500)
	check(limit.size() == 1 and limit.get(4) == 500, "a limit of 4 on EASY (83 %%: 3 or 4) never drops below 4 (%s)" % limit)
	limit = _tally(func() -> int: return LevelData.on_screen_for_difficulty(4, 3), 2000)
	check(_only(limit, [4, 5]) and absf(limit.get(5, 0) / 2000.0 - 0.68) < 0.04,
		"4 on HARD (117 %%): 5 about two times in three, else 4 (%s)" % limit)
	check(LevelData.on_screen_for_difficulty(4, 5) == 6, "4 on INSANE (150 %): 6")
	check(LevelData.on_screen_for_difficulty(26, 2) == 20 and LevelData.on_screen_for_difficulty(20, 5) == 20,
		"never more than 20, whatever the stage lists")
	check(LevelData.on_screen_for_difficulty(0, 2) == 4, "never fewer than 4")
	check(LevelData.get_max_concurrent(1, 2) == 4 and LevelData.get_max_concurrent(1, 5) == 6,
		"stage 1's own 4: 4 on NORMAL, 6 on INSANE")
	check(LevelData.get_max_concurrent(53, 2) == 20, "stage 53 lists 25: held to 20")

	print("\n[E] A stage start: the spawner takes both from the difficulty")
	var spawner := EnemySpawner.new()
	var timer := Timer.new()
	timer.name = "SpawnTimer"
	spawner.add_child(timer)
	add_child(spawner)
	Events.all_enemies_defeated.connect(func() -> void: _cleared += 1)
	GameManager.player_active = [true, true]
	GameManager.player_disabled = [false, false]
	GameManager.difficulty = 1
	spawner.prepare_stage(1)
	var size := spawner._spawn_queue.size()
	check(size >= 8 and size <= 10 and GameManager.enemies_remaining == size,
		"EASY: 8 to 10 enemies, and the HUD counts them (%d)" % GameManager.enemies_remaining)
	check(spawner.max_concurrent_enemies == 4, "two players in play: still 4 at once, as in the original (%d)"
		% spawner.max_concurrent_enemies)
	GameManager.difficulty = 5
	spawner.prepare_stage(1)
	check(spawner._spawn_queue.size() >= 20 and spawner.max_concurrent_enemies == 6,
		"INSANE: %d enemies, 6 at once" % spawner._spawn_queue.size())
	spawner.begin(1.5)
	check(_cleared == 0 and not spawner.spawn_timer.is_stopped(), "a stage with enemies starts sending them")
	spawner.halt()
	spawner._spawn_queue.clear()  # as if the difficulty had rounded every one away
	spawner.begin(1.5)
	check(_cleared == 1 and spawner.spawn_timer.is_stopped(), "a stage left with none is won at once")

	print("\n[F] Looping the map")
	var last := LevelData.get_stage_count()
	GameManager.current_stage = 3
	GameManager.difficulty = 2
	GameManager.advance_stage()
	check(GameManager.current_stage == 4 and GameManager.difficulty == 2, "stage 3 to 4: the same level")
	GameManager.current_stage = last
	GameManager.difficulty = 4
	GameManager.advance_stage()
	check(GameManager.current_stage == 1 and GameManager.difficulty == 5, "past stage %d: stage 1, one level up" % last)
	GameManager.current_stage = last
	GameManager.advance_stage()
	check(GameManager.current_stage == 1 and GameManager.difficulty == 5,
		"and past it again at 5: still 5, the original's top (%d)" % GameManager.difficulty)

	GameManager.difficulty = 1
	GameManager.current_stage = 1
	spawner.queue_free()
	await tree.process_frame
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
