extends Node
## Headless test for the words a bonus item shows when a tank takes it, as
## Tank.exe drew them: each item's own words (its table at 0x4d2de4) in its
## font; two copies sweeping in from the field's edges to the item, the text
## dipping, rising and gone after 1.5 s; the item itself taken as before.
## Run as an override main scene:
##   Godot --headless res://scenes/test/pickup_text_test.tscn

var _fail := 0


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _texts() -> Array:
	var found: Array = []
	for node in get_tree().get_nodes_in_group("effects_container")[0].get_children():
		if node is PickupText and not node.is_queued_for_deletion():
			found.append(node)
	return found


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	var types := CookieData.CookieType

	print("\n[A] Every item's words, in the original's font")
	var missing: Array = []
	for type_id in types.values():
		if not PickupText.WORDS.has(type_id):
			missing.append(types.keys()[type_id])
	check(missing.is_empty() and PickupText.WORDS.size() == types.size(), "all %d items have words %s" % [types.size(), str(missing)])
	var expect := [
		[types.SPEED_UP, ["Speed Up"], PickupText.Style.GOLD_HALF],
		[types.HP_UP, ["Armor Up"], PickupText.Style.GOLD_HALF],
		[types.MAX_UP, [" MAX ", "Speed", "Power"], PickupText.Style.GOLD],
		[types.MOON_SHIELD_COOKIE, ["[ Shield of Moon ]"], PickupText.Style.GOLD_HALF],
		[types.SCORE_500, ["+ 500"], PickupText.Style.SMALL],
		[types.BULLETS_MAX, ["  MAX  ", "Caisson", " Armor "], PickupText.Style.GOLD],
		[types.BULLET_REFILL, ["Caisson"], PickupText.Style.SMALL],
		[types.INVINCIBLE_HELMET, ["Who PA Who"], PickupText.Style.SMALL],
		[types.TANK_WEB, ["Hold Enemy"], PickupText.Style.SMALL],
		[types.TANK_LIFE, ["+1 UP !!!"], PickupText.Style.SMALL],
		[types.EXPLOSION_COOKIE, ["[ Explosion Gun ]"], PickupText.Style.SMALL],
	]
	for e: Array in expect:
		var text := PickupText.new()
		text.setup(e[0], Vector2(500, 500), 160, 1280)
		check(Array(text.get_lines()) == e[1] and text.get_style() == e[2],
			"%s: %s" % [types.keys()[e[0]], " / ".join(text.get_lines())])
		text.free()
	check(PickupText.CELLS[PickupText.Style.GOLD] == Vector2(36, 72)
		and PickupText.CELLS[PickupText.Style.GOLD_HALF] == Vector2(18, 36)
		and PickupText.CELLS[PickupText.Style.SMALL] == Vector2(16, 32), "cells: gold 18x36, half 9x18, small 8x16, at 2x")

	print("\n[B] Taking an item: two copies sweep in, then the text dips, rises, and goes")
	GameManager.current_stage = 1
	GameManager.player_active = [true, false]
	GameManager.player_scores = [0, 0]
	var game: Node = load("res://scenes/game.tscn").instantiate()
	game.show_intro = false  # straight into play
	tree.root.add_child(game)
	for i in 3:
		await tree.process_frame
	game.enemy_spawner.halt()
	var player: PlayerTank = tree.get_nodes_in_group("players")[0]
	var cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	cookie.setup(types.SCORE_500)
	game.powerups_container.add_child(cookie)
	var at := Vector2(640, 400)
	cookie.global_position = at
	await tree.process_frame
	cookie._on_body_entered(player)
	check(cookie.is_queued_for_deletion() and GameManager.player_scores[0] == 500,
		"the item is taken as before: gone at once, +500")
	var shown: Array = _texts()
	check(shown.size() == 1 and Array(shown[0].get_lines()) == ["+ 500"], "\"+ 500\" shows")
	var text: PickupText = shown[0]
	var width := 16.0 * 5
	var height := 32.0
	var field_left: float = game.get_level_manager().global_position.x
	var copies: Array[Vector2] = text.copy_positions()
	var from_edge := (64.0 - width) / 2.0 - 64.0
	check(copies.size() == 2 and copies[0] == Vector2(field_left + from_edge, at.y - height / 2.0)
		and copies[1] == Vector2(field_left + 1280 + from_edge, at.y - height / 2.0),
		"two copies start beyond the field's left and right edges, level with the item: %s" % str(copies))
	text.advance(PickupText.SWEEP / 2.0)
	copies = text.copy_positions()
	check(copies.size() == 2 and copies[0].x > field_left + from_edge and copies[1].x < field_left + 1280 + from_edge,
		"halfway, both sweep towards it")
	text.advance(PickupText.SWEEP / 2.0)
	copies = text.copy_positions()
	var settled := at - Vector2(width, height) / 2.0
	check(copies.size() == 1 and copies[0].is_equal_approx(settled),
		"after 300 ticks they meet, centred on the item; the second is gone")
	text.advance(PickupText.DIP)
	check(text.copy_positions()[0].is_equal_approx(settled + Vector2(0, 10)), "then 5 px down (10 here) in 300 ticks")
	text.advance(PickupText.RISE / 2.0)
	check(text.copy_positions()[0].is_equal_approx(settled + Vector2(0, 10 - 35)), "then rising, 35 px of 70 halfway")
	text.advance(PickupText.RISE / 2.0 - 0.01)
	check(not text.is_queued_for_deletion() and text.copy_positions()[0].y < settled.y - 59, "still up just before 1.5 s")
	text.advance(0.02)
	check(text.is_queued_for_deletion(), "gone at 1.5 s (2000 ticks)")
	check(text.z_index == 0 and text.get_index() >= 0 and game.hud.get_index() > game.get_node("Entities").get_index(),
		"drawn under the HUD panels, so the copies slide out from under them")

	print("\n[C] A MAX item: the big gold font, three lines")
	var max_cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	max_cookie.setup(types.MAX_UP)
	game.powerups_container.add_child(max_cookie)
	max_cookie.global_position = Vector2(400, 300)
	await tree.process_frame
	max_cookie._on_body_entered(player)
	var max_text: PickupText = _texts()[-1]
	check(Array(max_text.get_lines()) == [" MAX ", "Speed", "Power"] and max_text.get_style() == PickupText.Style.GOLD
		and max_text.copy_positions()[0].y == 300 - 72 * 3 / 2.0, "\" MAX / Speed / Power\" in gold, centred on the item")

	tree.root.remove_child(game)
	game.free()
	await tree.create_timer(0.8).timeout  # let the pickup sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
