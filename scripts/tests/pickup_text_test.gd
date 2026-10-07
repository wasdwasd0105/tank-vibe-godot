extends Node
## Headless test for the words a bonus item shows when a tank takes it, as
## Tank.exe wrote them: each item's own words (its table at 0x4d2de4) in its
## font, appearing on the item (no sweep in: Sean's call), dipping, rising and
## gone after 1.275 s; the item itself taken as before.
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
		[types.SPEED_UP, ["Speed Up"], PickupText.Style.GOLD],
		[types.HP_UP, ["Armor Up"], PickupText.Style.GOLD],
		[types.MAX_UP, [" MAX ", "Speed", "Power"], PickupText.Style.GOLD],
		[types.MOON_SHIELD_COOKIE, ["[ Shield of Moon ]"], PickupText.Style.GOLD],
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
		text.setup(e[0], Vector2(500, 500))
		check(Array(text.get_lines()) == e[1] and text.get_style() == e[2],
			"%s: %s" % [types.keys()[e[0]], " / ".join(text.get_lines())])
		text.free()
	check(PickupText.LINE_HEIGHTS.size() == 2 and PickupText.LINE_HEIGHTS[PickupText.Style.GOLD] == 36.0
		and PickupText.LINE_HEIGHTS[PickupText.Style.SMALL] == 32.0,
		"two looks: half-size gold, 18 px lines (the MAX items too), and small, 16 px lines, at 2x")

	print("\n[B] Taking an item: the words appear on it, dip, rise, and go")
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
	var width := PickupText.SMALL_FONT.get_string_size("+ 500", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	check(text.get_block().is_equal_approx(Vector2(width, 32)), "as wide as the words measure (%.0f px)" % width)
	var start := at - Vector2(width, 32.0) / 2.0
	check(text.text_position().is_equal_approx(start), "right on the item from the start, no sweep in: %s" % str(text.text_position()))
	text.advance(PickupText.DIP)
	check(text.text_position().is_equal_approx(start + Vector2(0, 10)), "5 px down (10 here) in 300 ticks")
	text.advance(PickupText.RISE / 2.0)
	check(text.text_position().is_equal_approx(start + Vector2(0, 10 - 35)), "then rising, 35 px of 70 halfway")
	text.advance(PickupText.RISE / 2.0 - 0.01)
	check(not text.is_queued_for_deletion() and text.text_position().y < start.y - 59, "still up just before the end")
	text.advance(0.02)
	check(text.is_queued_for_deletion() and is_equal_approx(PickupText.LIFETIME, 1700 * PickupText.TICK),
		"gone after 1700 ticks")
	check(text.z_index == KillText.Z_INDEX and game.hud.z_index > text.z_index,
		"drawn over the grass and the items, as the kill words, and under the HUD panels")

	print("\n[C] A MAX item: the upgrades' gold, three lines")
	var max_cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	max_cookie.setup(types.MAX_UP)
	game.powerups_container.add_child(max_cookie)
	max_cookie.global_position = Vector2(400, 300)
	await tree.process_frame
	max_cookie._on_body_entered(player)
	var max_text: PickupText = _texts()[-1]
	check(Array(max_text.get_lines()) == [" MAX ", "Speed", "Power"] and max_text.get_style() == PickupText.Style.GOLD
		and max_text.get_block().y == 36 * 3
		and max_text.text_position().is_equal_approx(Vector2(400, 300) - max_text.get_block() / 2.0),
		"\" MAX / Speed / Power\" in the same gold as Speed Up, centred on the item")

	tree.root.remove_child(game)
	game.free()
	await tree.create_timer(0.8).timeout  # let the pickup sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
