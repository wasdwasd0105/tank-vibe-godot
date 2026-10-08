extends Node
## Headless test for the score and drop values Sean set on 2026-10-08: extra
## lives at 10,000, 30,000, 60,000 and 100,000 points, then every 100,000 more;
## Armor Up, MAX, MAX Caisson Armor, Hold Enemy and Bomb dropping half as often
## as before, every other item at its old odds. Run as an override main scene:
##   Godot --headless res://scenes/test/value_test.tscn

const ROLLS := 400000

var _fail := 0


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	AudioServer.set_bus_mute(0, true)  # the extra-life jingle, many times over
	GameManager.reset()

	print("\n[A] Extra lives: at 10,000, 30,000, 60,000 and 100,000 points, then every 100,000")
	var lives_at := {0: 0, 9999: 0, 10000: 1, 29999: 1, 30000: 2, 59999: 2, 60000: 3,
		99999: 3, 100000: 4, 199999: 4, 200000: 5, 300000: 6, 1000000: 13}
	var wrong := []
	for score: int in lives_at:
		if GameManager.extra_lives_at(score) != lives_at[score]:
			wrong.append("%d: %d" % [score, GameManager.extra_lives_at(score)])
	check(wrong.is_empty(), "the lives each score has earned %s" % str(wrong))
	# [score before, points, lives they give], each as a kill's points and as a reward's
	var gains := [[9900, 100, 1], [10000, 600, 0], [19900, 200, 0], [29900, 200, 1],
		[59500, 600, 1], [99800, 300, 1], [119900, 200, 0], [199000, 2000, 1], [0, 35000, 2]]
	wrong.clear()
	for gain: Array in gains:
		for reward in [false, true]:
			GameManager.player_scores[0] = gain[0]
			GameManager.player_lives[0] = 3
			if reward:
				GameManager.add_score_direct(0, gain[1])
			else:
				GameManager.add_score(0, gain[1], 5)
			if GameManager.player_lives[0] != 3 + gain[2]:
				wrong.append("%d + %d: %d" % [gain[0], gain[1], GameManager.player_lives[0] - 3])
	check(wrong.is_empty(),
		"points give the lives they pass: 9,900 + 100 one, 19,900 + 200 none, 119,900 + 200 none, 0 + 35,000 two %s" % str(wrong))
	GameManager.reset()

	print("\n[B] Death drops: Armor Up, MAX, MAX Caisson Armor, Hold Enemy and Bomb half as often as before, the rest unchanged")
	seed(20261008)
	_check_drops(6, true)
	_check_drops(2, false)

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)


## Rolls [param type_id]'s death drop ROLLS times against the odds it should
## have: 60% drops, split over four pools (an [param armed] tank's, the fourth
## its own gun's item) or three, each item an even share of its pool, but the
## five Sean named at half of theirs.
func _check_drops(type_id: int, armed: bool) -> void:
	var T = CookieData.CookieType
	var power := [T.SPEED_UP, T.HP_UP, T.WEAPONS_UP, T.STAR_UP, T.MAX_UP]
	var score := [T.SCORE_200, T.SCORE_500, T.SCORE_1000, T.SCORE_2000, T.BULLETS_MAX, T.BULLET_REFILL]
	var special := [T.INVINCIBLE_HELMET, T.FLAG_PROTECTION, T.TANK_WEB, T.TANK_BOMB, T.TANK_LIFE]
	var halved := [T.HP_UP, T.MAX_UP, T.BULLETS_MAX, T.TANK_WEB, T.TANK_BOMB]
	var shares: Array = [0.25, 0.25, 0.25] if armed else [0.333, 0.333, 0.334]
	var odds := {}
	for c in power:
		odds[c] = 0.6 * shares[0] / 5.0
	for c in score:
		odds[c] = 0.6 * shares[1] / 6.0
	for c in special:
		odds[c] = 0.6 * shares[2] / 5.0
	for c in halved:
		odds[c] /= 2.0
	if armed:
		odds[CookieData.WEAPON_TO_COOKIE[CookieData.TYPE_WEAPON_MAP[type_id]]] = 0.6 * 0.25
	var dropped := 0.0
	for c in odds:
		dropped += odds[c]
	odds[-1] = 1.0 - dropped

	var counts := {}
	for i in ROLLS:
		var c := CookieData.roll_death_drop(type_id)
		counts[c] = counts.get(c, 0) + 1
	var halved_off := []  # the five, and the drops they give up
	var others_off := []
	for c in counts:
		if not odds.has(c):
			others_off.append("%s dropped" % _name(c))
	for c in odds:
		var seen := float(counts.get(c, 0)) / ROLLS
		if absf(seen - odds[c]) > 4.0 * sqrt(odds[c] * (1.0 - odds[c]) / ROLLS):
			var miss := "%s %.2f%% (not %.2f%%)" % [_name(c), seen * 100.0, odds[c] * 100.0]
			(halved_off if c in halved or c == -1 else others_off).append(miss)
	var label := "type %d (%s)" % [type_id, "armed" if armed else "plain gun"]
	check(halved_off.is_empty(), "%s: Armor Up %s, Bomb %s, Hold Enemy %s, MAX %s, MAX Caisson Armor %s of kills; no drop %s %s" % [label,
		_share(counts, T.HP_UP), _share(counts, T.TANK_BOMB), _share(counts, T.TANK_WEB),
		_share(counts, T.MAX_UP), _share(counts, T.BULLETS_MAX), _share(counts, -1), str(halved_off)])
	check(others_off.is_empty(), "%s: every other item as before: Speed Up %s, LEVEL UP %s, +1 UP %s, Who PA Who %s %s" % [label,
		_share(counts, T.SPEED_UP), _share(counts, T.STAR_UP), _share(counts, T.TANK_LIFE),
		_share(counts, T.INVINCIBLE_HELMET), str(others_off)])


## How often [param cookie_type] came up in [param counts], as a percentage.
func _share(counts: Dictionary, cookie_type: int) -> String:
	return "%.2f%%" % (counts.get(cookie_type, 0) * 100.0 / ROLLS)


func _name(cookie_type: int) -> String:
	return "nothing" if cookie_type < 0 else CookieData.CookieType.keys()[cookie_type]
