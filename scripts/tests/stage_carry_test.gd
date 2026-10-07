extends Node
## Headless test for what a stage hands the next, as Tank.exe's: a hold ("Hold
## Enemy", either way) runs on into it, its timer never reset by a stage; a
## player's tank starts it as a fresh one, under the original's 5000-tick shield
## (3.75 s), the wreath for its first 1.5 s, then blinking. Run as an override
## main scene:
##   Godot --headless res://scenes/test/stage_carry_test.tscn

var _fail := 0


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _player_of(tree: SceneTree) -> PlayerTank:
	for p in tree.get_nodes_in_group("players"):
		return p
	return null


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.reset()
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false

	print("\n[A] A hold runs on into the next stage")
	GameManager.freeze_all_enemies(12.0)
	GameManager.freeze_all_players(3.0)
	GameManager.advance_stage()
	check(GameManager.current_stage == 2 and GameManager.enemies_frozen and is_equal_approx(GameManager.freeze_timer, 12.0),
		"the enemies' hold: still on, with what was left")
	check(GameManager.players_frozen and is_equal_approx(GameManager.players_freeze_timer, 3.0),
		"the players' hold too (an enemy took Hold Enemy)")
	await tree.create_timer(0.5).timeout
	check(GameManager.freeze_timer < 11.6 and GameManager.freeze_timer > 11.0,
		"and it counts down meanwhile, as through the stage screens (%.2f s left)" % GameManager.freeze_timer)
	GameManager.reset()
	check(not GameManager.enemies_frozen and not GameManager.players_frozen, "a new game starts without")
	GameManager.current_stage = 1
	GameManager.player_active[0] = true

	print("\n[B] The next stage: a fresh tank's shield, 3.75 s, the wreath for its first 1.5 s, then blinking")
	GameManager.freeze_all_enemies(30.0)
	GameManager.advance_stage()
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_intro = false  # straight into play
	tree.root.add_child(game)
	var player: PlayerTank = null
	while player == null or player.is_materializing:
		await tree.process_frame
		player = _player_of(tree)
	check(player.is_invincible and player.invincible_timer > 3.6 and player.invincible_timer <= PlayerTank.SPAWN_INVINCIBILITY,
		"the original's 5000 ticks (%.2f s left as it appears)" % player.invincible_timer)
	await tree.process_frame
	check(player._state_fx_sprite != null and player._state_fx_sprite.visible and player.visible,
		"under the wreath, drawn solid")
	while player.invincible_timer > PlayerTank.WREATH_MIN_LEFT - 0.1:
		await tree.process_frame
	var shown := []
	for i in 6:
		await tree.process_frame
		shown.append(player.visible)
	check((player._state_fx_sprite == null or not player._state_fx_sprite.visible) and shown.has(true) and shown.has(false),
		"its last 2.25 s: no wreath, blinking (%s)" % str(shown))
	while player.is_invincible:
		await tree.process_frame
	await tree.process_frame
	check(player.visible and (player._state_fx_sprite == null or not player._state_fx_sprite.visible), "then a plain tank")

	print("\n[C] ... with the enemies still held: one that appears stands")
	var enemy: EnemyTank = null
	var waited := 0.0
	while enemy == null and waited < 8.0:
		await tree.create_timer(0.1).timeout
		waited += 0.1
		for e in tree.get_nodes_in_group("enemies"):
			if e is EnemyTank and not e.is_materializing:
				enemy = e
	check(enemy != null and GameManager.enemies_frozen, "an enemy appeared, the hold still on (%.1f s of it left)" % GameManager.freeze_timer)
	if enemy:
		var at := enemy.global_position
		await tree.create_timer(1.0).timeout
		check(is_instance_valid(enemy) and enemy.global_position.distance_to(at) < 0.5, "held: it hasn't moved in 1 s")
	GameManager.reset()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
