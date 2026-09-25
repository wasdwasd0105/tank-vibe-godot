extends Node
## Headless test for the words a player's hits and kills show, as Tank.exe's
## Damage routine wrote them (docs/damage_text_original_spec.md): a kill's score
## over the wreck, "N Combos" over it once a combo is on, dipping, then rising
## and fading to half, over the explosion; none for a bomb's kills or an enemy's;
## and a hit chain's "N Hits" over the player's panel from its second hit until
## it lapses. The killer's controller thumps for each kill (not the bomb's), and
## a bomb taken rumbles as hard as a lost tank.
## Run as an override main scene:
##   Godot --headless res://scenes/test/kill_text_test.tscn

var _fail := 0
var _game: Node
var _rumbles: Array = []  # [player, weak, strong, seconds] per rumble asked for


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _texts() -> Array:
	var found: Array = []
	for node in _game.effects_container.get_children():
		if node is KillText and not node.is_queued_for_deletion():
			found.append(node)
	return found


func _enemy(type_id: int, tile: Vector2i) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _game.level_manager.tile_to_world(tile)
	e.tree_exited.connect(_game.enemy_spawner._on_enemy_removed)
	_game.enemy_spawner._active_enemies += 1
	return e


## A rumble as _rumbles records it.
func _r(pid: int, pattern: Array[float]) -> Array:
	return [pid, pattern[0], pattern[1], pattern[2]]


## Lets every hit chain and combo lapse, as 2.7 s without a hit or a kill would
## (the timer runs out one frame, the chain is counted the next).
func _lapse() -> void:
	GameManager._tick_chains(GameManager.COMBO_WINDOW + 0.1)
	GameManager._tick_chains(0.0)


## Hits [param e] with [param pid]'s weapon until it's gone (-1: an enemy's).
func _kill(e: EnemyTank, pid: int) -> void:
	while is_instance_valid(e) and not e.is_queued_for_deletion():
		e.hit_by = pid
		e.take_damage()


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame

	print("\n[A] The words: the score, and the combo over it")
	check(Array(KillText.words(100, 1)) == ["+ 100"], "a lone kill: \"+ 100\"")
	check(Array(KillText.words(300, 2)) == ["2 Combos", "+ 300"], "the second of a combo: \"2 Combos\" over \"+ 300\"")
	check(Array(KillText.words(600, 12)) == ["12 Combos", "+ 600"], "and on: \"12 Combos\"")

	print("\n[B] On the tank, dipping, then rising and fading to half")
	var lone := KillText.new()
	lone.setup(100, 1, Vector2(500, 400))
	var width := KillText.FONT.get_string_size("+ 100", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	check(lone.get_block().is_equal_approx(Vector2(width, 24)),
		"the white font at half size: one 12 px line (24 here), as wide as it measures (%.0f)" % width)
	var start := Vector2(500 - width / 2.0, 400 - 32 + 16)
	check(lone.text_position().is_equal_approx(start),
		"centred across the tank, its top 8 px under the tank's (16 here): %s" % str(lone.text_position()))
	check(is_equal_approx(lone.text_alpha(), 1.0), "solid at first")
	lone.advance(KillText.DIP)
	check(lone.text_position().is_equal_approx(start + Vector2(0, 6)) and is_equal_approx(lone.text_alpha(), 1.0),
		"3 px down (6 here) in 300 ticks, still solid")
	lone.advance(KillText.RISE / 2.0)
	check(lone.text_position().is_equal_approx(start + Vector2(0, 6 - 30))
		and is_equal_approx(lone.text_alpha(), lerpf(1.0, 128.0 / 255.0, 0.5)),
		"then rising, 30 px of 60 halfway, and fading (%.2f)" % lone.text_alpha())
	lone.advance(KillText.RISE / 2.0 - 0.01)
	check(not lone.is_queued_for_deletion() and absf(lone.text_alpha() - 128.0 / 255.0) < 0.01,
		"down to half just before the end (%.2f)" % lone.text_alpha())
	check(is_equal_approx(KillText.LIFETIME, 1800 * KillText.TICK), "1800 ticks in all")
	lone.free()
	var combo := KillText.new()
	combo.setup(300, 2, Vector2(500, 400))
	var widths := [KillText.FONT.get_string_size("2 Combos", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x,
		KillText.FONT.get_string_size("+ 300", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x]
	check(combo.get_block().is_equal_approx(Vector2(widths.max(), 48))
		and combo.text_position().is_equal_approx(Vector2(500 - widths.max() / 2.0, 400 - 32 + 24)),
		"a combo's two lines start 12 px under the tank's top (24 here), centred on it")
	combo.free()

	print("\n[C] In a stage: a player's kills")
	GameManager.current_stage = 1
	GameManager.difficulty = 1
	GameManager.player_active = [true, true]
	GameManager.player_disabled = [false, false]
	GameManager.player_scores = [0, 0]
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in 3:
		await tree.process_frame
	_game.enemy_spawner.halt()
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	await tree.process_frame

	InputSettings.rumbled.connect(func(pid: int, weak: float, strong: float, seconds: float) -> void:
		_rumbles.append([pid, weak, strong, seconds]))
	var e1 := _enemy(1, Vector2i(8, 10))
	var e1_at := e1.global_position
	_kill(e1, 0)
	check(_rumbles == [_r(0, PlayerTank.KILL_RUMBLE)], "and P1's controller thumps for it: %s" % str(_rumbles))
	var shown := _texts()
	check(shown.size() == 1 and Array(shown[0].get_lines()) == ["+ 100"] and GameManager.player_scores[0] == 100,
		"P1's shell takes out a 100-point tank: \"+ 100\" over it, and 100 scored")
	var text: KillText = shown[0]
	check(text.text_position().is_equal_approx(e1_at + Vector2(-text.get_block().x / 2.0, -16)),
		"centred on the wreck")
	var blast: CanvasItem = null
	for node in _game.effects_container.get_children():
		if not node is KillText and not node is PickupText and node is Node2D and node.global_position.distance_to(e1_at) < 1.0:
			blast = node
	check(blast != null and text.z_index > blast.z_index,
		"drawn over the tank's explosion (z %d over %d)" % [text.z_index, blast.z_index if blast else -1])
	text.advance(KillText.LIFETIME)
	await tree.process_frame
	check(_texts().is_empty(), "and gone when it's done")

	var c1 := _enemy(1, Vector2i(14, 10))
	var c2 := _enemy(3, Vector2i(20, 10))
	var c3 := _enemy(5, Vector2i(26, 10))
	_rumbles.clear()
	_kill(c1, 1)
	_kill(c2, 1)
	_kill(c3, 1)
	check(_rumbles == [_r(1, PlayerTank.KILL_RUMBLE), _r(1, PlayerTank.KILL_RUMBLE), _r(1, PlayerTank.KILL_RUMBLE)],
		"a thump on P2's controller for each of P2's kills, none on P1's")
	var lines: Array = _texts().map(func(t: KillText) -> String: return " / ".join(t.get_lines()))
	check(lines == ["+ 100", "2 Combos / + 100", "3 Combos / + 200"],
		"P2's three quick kills: %s" % str(lines))
	for t: KillText in _texts():
		t.free()
	_lapse()
	var c4 := _enemy(1, Vector2i(32, 10))
	_kill(c4, 1)
	lines = _texts().map(func(t: KillText) -> String: return " / ".join(t.get_lines()))
	check(lines == ["+ 100"], "after 2.7 s without one, a lone kill again: %s" % str(lines))
	for t: KillText in _texts():
		t.free()

	print("\n[D] No words for a bomb's kills or an enemy's")
	var b1 := _enemy(1, Vector2i(8, 16))
	var b2 := _enemy(3, Vector2i(14, 16))
	var score_before: int = GameManager.player_scores[0]
	_rumbles.clear()
	_game.enemy_spawner.destroy_all_enemies(0)
	await tree.process_frame
	check(not is_instance_valid(b1) and not is_instance_valid(b2) and _texts().is_empty(),
		"P1's bomb: both tanks gone, no words (the original's bomb skipped Damage)")
	check(GameManager.player_scores[0] == score_before + 200, "though the remake still scores them")
	var victim := _enemy(1, Vector2i(20, 16))
	_kill(victim, -1)
	check(_texts().is_empty(), "an enemy's weapon (no player's): no words")
	check(_rumbles.is_empty(), "and no thumps for either (the bomb's own rumble covers its kills)")
	InputSettings.set_vibration("p1", false)
	_kill(_enemy(1, Vector2i(26, 16)), 0)
	check(_rumbles.is_empty(), "P1 with VIBRATION off: none for P1's kill")
	InputSettings.set_vibration("p1", true)

	print("\n[E] A hit chain: \"N Hits\" over the player's panel")
	var hud = _game.hud
	var tough := _enemy(16, Vector2i(26, 18))
	_lapse()  # any chain so far
	tough.hit_by = 0
	tough.take_damage()
	await tree.process_frame
	check(not hud.p1_hits_label.visible, "one hit: nothing yet")
	tough.hit_by = 0
	tough.take_damage()
	await tree.process_frame
	check(hud.p1_hits_label.visible and hud.p1_hits_label.text == "2 Hits", "the second: \"2 Hits\"")
	tough.hit_by = 0
	tough.take_damage()
	await tree.process_frame
	check(hud.p1_hits_label.text == "3 Hits" and not hud.p2_hits_label.visible,
		"the third: \"3 Hits\", on P1's panel only")
	var label_top: float = hud.p1_hits_label.global_position.y + hud.p1_hits_label.size.y
	check(label_top <= hud.p1_header.global_position.y and hud.p1_hits_label.get_parent() == hud.p1_header.get_parent(),
		"just above the \"I P\" tag")
	GameManager._tick_chains(GameManager.HIT_CHAIN_WINDOW + 0.1)
	GameManager._tick_chains(0.0)
	await tree.process_frame
	check(not hud.p1_hits_label.visible and GameManager.player_max_hits[0] >= 3,
		"0.9 s without a hit: the chain lapses and the line goes (best %d)" % GameManager.player_max_hits[0])
	tough.hit_by = 1
	tough.take_damage()
	tough.hit_by = 1
	tough.take_damage()
	await tree.process_frame
	check(hud.p2_hits_label.visible and hud.p2_hits_label.text == "2 Hits" and not hud.p1_hits_label.visible,
		"P2's chain on P2's panel")

	print("\n[F] A bomb taken: as hard a rumble as a lost tank")
	var p1: PlayerTank = null
	for tank in tree.get_nodes_in_group("players"):
		if tank is PlayerTank and tank.player_id == 0:
			p1 = tank
	var d1 := _enemy(1, Vector2i(8, 22))
	var d2 := _enemy(3, Vector2i(14, 22))
	_rumbles.clear()
	var bomb = load("res://scenes/powerups/powerup.tscn").instantiate()
	bomb.setup(CookieData.CookieType.TANK_BOMB)
	_game.powerups_container.add_child(bomb)
	bomb._apply_effect(p1)
	bomb.queue_free()
	await tree.process_frame
	check(not is_instance_valid(d1) and not is_instance_valid(d2) and _rumbles == [_r(0, PlayerTank.DEATH_RUMBLE)],
		"P1 takes a bomb: the tanks go up, and P1's controller gives a lost tank's big rumble, once: %s" % str(_rumbles))

	tree.root.remove_child(_game)
	_game.free()
	await tree.create_timer(0.8).timeout  # let the sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
