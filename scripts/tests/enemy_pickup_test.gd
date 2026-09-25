extends Node
## Headless test for enemies taking bonus items, as Tank.exe let them (its
## pickup filter at 0x0049595b and the item effects after it): which items an
## enemy may take, what each does for the enemies or against the players, and
## that an enemy just drives over the rest.
## Run as an override main scene:
##   Godot --headless res://scenes/test/enemy_pickup_test.tscn

const T := CookieData.CookieType

var _fail := 0
var _game: Node
var _lm: LevelManager
var _spawner: EnemySpawner
var _player: PlayerTank
var _pickups: Array = []  # [type, player_id] per cookie_collected


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


# --- helpers -------------------------------------------------------------

func _frames(n: int = 2) -> void:
	for i in range(n):
		await get_tree().physics_frame
	await get_tree().process_frame


func _at(local: Vector2) -> Vector2:
	return _lm.global_position + local


## An enemy with its AI off, so it sits where it is put.
func _spawn_enemy(local: Vector2, type_id: int) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.enemies_container.add_child(e)
	e.set_physics_process(false)
	e.global_position = _at(local)
	return e


func _drop(type: int, local: Vector2) -> Cookie:
	var c: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	c.setup(type)
	_game.powerups_container.add_child(c)
	c.global_position = _at(local)
	return c


## An item dropped right under [param enemy], given the physics steps to find it.
func _feed(enemy: EnemyTank, type: int):  # the Cookie, freed once taken
	var c := _drop(type, enemy.global_position - _lm.global_position)
	await _frames(3)
	return c


func _taken(c) -> bool:
	return not is_instance_valid(c) or c.is_queued_for_deletion()


func _words() -> Array:
	var found: Array = []
	for node in _game.effects_container.get_children():
		if node is PickupText and not node.is_queued_for_deletion():
			found.append(Array(node.get_lines()))
	return found


func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for c in get_tree().get_nodes_in_group("cookies"):
		c.queue_free()
	for fx in _game.effects_container.get_children():
		fx.queue_free()
	_pickups.clear()
	await _frames()


func _addon_sprites(e: EnemyTank) -> Array:
	var names: Array = []
	for child in e.get_children():
		if child is Sprite2D and child.has_meta(&"addon") and not child.is_queued_for_deletion():
			names.append(child.get_meta(&"addon"))
	return names


func _takes(e: EnemyTank) -> Array:
	var allowed: Array = []
	for type_id in T.values():
		if e.can_take_cookie(type_id):
			allowed.append(type_id)
	return allowed


## What the player's state overlay shows now (its frames), or [] when hidden.
func _overlay() -> Array:
	var fx: Sprite2D = _player._state_fx_sprite
	if fx == null or not is_instance_valid(fx) or not fx.visible:
		return []
	return _player._state_fx_frames


func _cookies_of(type: int) -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("cookies"):
		if c.cookie_type == type and not c.is_queued_for_deletion():
			n += 1
	return n


func _base_wall_codes() -> Array:
	var codes: Array = []
	var tiles: Array = _lm._original_base_walls.keys()
	tiles.sort()
	for tile in tiles:
		codes.append(_lm._fg_tile_data[tile]["code"] if _lm._fg_tile_data.has(tile) else -1)
	return codes


## Drives [param tank] by hand (its AI is off) for [param seconds].
func _drive(tank: EnemyTank, dir: Vector2, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		tank._tick_afloat()
		tank.velocity = dir * 64.0
		tank.move_and_slide()
		t += 1.0 / Engine.physics_ticks_per_second


func _names(types: Array) -> String:
	var names: Array = []
	for t in types:
		names.append(T.keys()[t])
	return ", ".join(names)


# --- the test ------------------------------------------------------------

func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	GameManager.current_stage = 1
	GameManager.player_active = [true, false]
	GameManager.player_lives = [3, 3]
	GameManager.player_scores = [0, 0]
	Events.cookie_collected.connect(func(type: int, pid: int) -> void: _pickups.append([type, pid]))
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_lm = _game.get_level_manager()
	_spawner = _game.enemy_spawner
	_spawner.halt()
	for tile in _lm._fg_tile_data.keys():
		if tile.y < 22:
			_lm._remove_fg_tile(tile)
	for tile in _lm._bg_tile_data.keys():
		_lm._remove_bg_tile(tile)
	_player = tree.get_nodes_in_group("players")[0]
	while _player.is_materializing:
		await tree.process_frame
	_player.global_position = _at(Vector2(96, 640))
	await _clear()

	var upgrades := [T.SPEED_UP, T.HP_UP, T.WEAPONS_UP, T.STAR_UP, T.MAX_UP,
		T.ANTI_WATER_COOKIE, T.ANTI_ICE_COOKIE, T.MOON_SHIELD_COOKIE, T.MEMORY_SAVE_COOKIE]
	var specials := [T.BULLETS_MAX, T.BULLET_REFILL, T.INVINCIBLE_HELMET, T.FLAG_PROTECTION,
		T.TANK_WEB, T.TANK_BOMB, T.TANK_LIFE]

	print("\n[A] Which items an enemy may take")
	var cases := [
		[1, [T.BULLET_REFILL], "plain gun, weaker type: only \"Caisson\", its gun's"],
		[3, [T.BULLET_REFILL], "type 3 the same"],
		[5, [T.RAPID_COOKIE], "rapid, weaker type: only its own gun"],
		[21, [T.MINE_COOKIE], "mine, weaker type: only its own gun"],
		[2, upgrades + [T.BULLET_REFILL], "plain, stronger type: the upgrades and add-ons too"],
		[12, upgrades + [T.FIRE_COOKIE], "fire, stronger type (moon shield): the same"],
		[8, upgrades + [T.BULLETS_MAX, T.BULLET_REFILL, T.INVINCIBLE_HELMET, T.FLAG_PROTECTION,
			T.TANK_WEB, T.TANK_BOMB, T.TANK_LIFE, T.RAPID_COOKIE], "memory-save: the specials as well"],
	]
	var x := 96.0
	for case: Array in cases:
		var e := _spawn_enemy(Vector2(x, 96), case[0])
		x += 96.0
		var got := _takes(e)
		var want: Array = case[1]
		got.sort()
		want.sort()
		check(got == want, "type %d, %s (%s)" % [case[0], case[2], _names(got)])
	var weak_memory := _spawn_enemy(Vector2(x, 96), 9)
	weak_memory.set_addon("memory-save")
	var memory_want: Array = upgrades + specials + [T.FIRE_COOKIE]
	memory_want.sort()
	var memory_got := _takes(weak_memory)
	memory_got.sort()
	check(memory_got == memory_want, "memory-save opens up a weaker type as well")
	var scores := [T.SCORE_200, T.SCORE_500, T.SCORE_1000, T.SCORE_2000]
	var any_score := false
	for e in tree.get_nodes_in_group("enemies"):
		for s in scores:
			any_score = any_score or e.can_take_cookie(s)
	check(not any_score, "no enemy ever takes a score item")
	var appearing := _spawn_enemy(Vector2(x + 96, 96), 8)
	appearing.begin_materialize(1.0)
	check(_takes(appearing).is_empty(), "nor anything while it is still appearing")
	await _clear()

	print("\n[B] Driving over: what it may not take stays; what it may, it takes")
	var plain := _spawn_enemy(Vector2(320, 320), 1)
	var speed_before := plain.move_speed
	var left = await _feed(plain, T.SPEED_UP)
	check(not _taken(left) and plain.move_speed == speed_before and _words().is_empty() and _pickups.is_empty(),
		"a weaker plain tank drives over Speed Up: it stays, nothing happens")
	var caisson = await _feed(plain, T.BULLET_REFILL)
	check(_taken(caisson) and _words() == [["Caisson"]] and _pickups == [[T.BULLET_REFILL, -1]],
		"\"Caisson\" it takes: gone, its words shown, the pickup sound (cookie_collected, -1)")
	check(plain.is_invulnerable() and plain._invulnerable_timer <= EnemyTank.PICKUP_INVULNERABILITY
		and plain._invulnerable_timer > EnemyTank.PICKUP_INVULNERABILITY - 0.1,
		"then untouchable for 1000 ticks (0.75 s)")
	var t_left: float = plain._invulnerable_timer
	await _feed(plain, T.BULLET_REFILL)
	check(plain._invulnerable_timer > t_left + EnemyTank.PICKUP_INVULNERABILITY - 0.1,
		"a second item adds its 0.75 s to what is left (%.2f s now)" % plain._invulnerable_timer)
	var hp := plain.health
	plain.hit_by = 0
	plain.take_damage(Vector2.UP)
	check(plain.health == hp and plain.hit_by == -1, "a player's shell does nothing meanwhile")
	var shown := {}
	for i in range(6):
		await tree.process_frame
		shown[plain.visible] = true
	check(shown.size() == 2, "and it blinks")
	await tree.create_timer(plain._invulnerable_timer + 0.05).timeout
	await tree.process_frame
	check(not plain.is_invulnerable() and plain.visible, "once it runs out it can be hurt again, and shows")
	plain.hit_by = 0
	plain.take_damage(Vector2.UP)
	check(plain.health == hp - 1 or not is_instance_valid(plain) or plain.is_queued_for_deletion(),
		"and a shell hurts it")
	check(not _taken(left), "Speed Up still lies there")
	await _clear()

	print("\n[C] The upgrades build the taker up")
	var strong := _spawn_enemy(Vector2(320, 320), 2)
	strong.apply_mine_slow()
	var s0 := strong.move_speed
	await _feed(strong, T.SPEED_UP)
	check(strong.move_speed == s0 + EnemyTank.ITEM_SPEED_STEP and not strong.is_mine_slowed,
		"Speed Up: a speed step faster (%.0f -> %.0f), mine slow gone" % [s0, strong.move_speed])
	var h0 := strong.health
	await _feed(strong, T.HP_UP)
	check(strong.health == h0 + 1, "Armor Up: one more HP (%d -> %d)" % [h0, strong.health])
	var g0 := strong.special_weapon_level
	await _feed(strong, T.WEAPONS_UP)
	check(strong.special_weapon_level == g0 + 1, "Power Up: a gun level")
	await _feed(strong, T.STAR_UP)
	check(strong.move_speed == s0 + 2 * EnemyTank.ITEM_SPEED_STEP and strong.health == h0 + 2
		and strong.special_weapon_level == g0 + 2, "LEVEL UP: all three")
	for i in range(8):
		await _feed(strong, T.STAR_UP)
	check(strong.health == EnemyTank.MAX_ITEM_HP and strong.special_weapon_level == EnemyTank.MAX_ITEM_GUN
		and strong.move_speed == EnemyTank.ITEM_MAX_SPEED,
		"capped: HP 8, gun 3, speed %.0f" % EnemyTank.ITEM_MAX_SPEED)
	await _clear()

	print("\n[D] An add-on item replaces the add-on it wore")
	var boat := _spawn_enemy(Vector2(320, 320), 2)
	check(boat.addons == ["anti-water"] and not boat.get_collision_mask_value(2), "type 2 wears anti-water")
	boat.apply_mine_slow()
	await _feed(boat, T.MOON_SHIELD_COOKIE)
	check(boat.addons == ["moon-shield"] and boat.has_moon_shield and boat.get_collision_mask_value(2)
		and _addon_sprites(boat) == ["moon-shield"],
		"after Shield of Moon: the moon shield only, water stops it again, one add-on drawn")
	check(not boat.is_mine_slowed, "and the mine slow is gone")
	await _feed(boat, T.ANTI_ICE_COOKIE)
	check(boat.addons == ["anti-ice"] and boat.has_anti_ice and not boat.has_moon_shield
		and _addon_sprites(boat) == ["anti-ice"], "AntiSkid in its place")
	await _clear()

	print("\n[E] MAX builds up every enemy on the field")
	var taker := _spawn_enemy(Vector2(320, 320), 2)
	var e1 := _spawn_enemy(Vector2(96, 96), 1)
	var e4 := _spawn_enemy(Vector2(224, 96), 4)
	var e5 := _spawn_enemy(Vector2(352, 96), 5)
	var late := _spawn_enemy(Vector2(480, 96), 3)
	late.begin_materialize(5.0)
	var before := {}
	for e: EnemyTank in [taker, e1, e4, e5, late]:
		before[e] = [e.tank_type_id, e.health, e.move_speed, e.special_weapon_level]
	var sprite_before := e1.sprite.texture
	e5.apply_mine_slow()
	var parked = _drop(T.HP_UP, Vector2(96, 96))
	await _frames(3)
	check(not _taken(parked), "type 1 sits on an Armor Up it may not take")
	await _feed(taker, T.MAX_UP)
	check(e1.tank_type_id == 2 and e5.tank_type_id == 6 and e4.tank_type_id == 4 and taker.tank_type_id == 2,
		"the weaker types become the stronger of their pair (1 -> 2, 5 -> 6); 2 and 4 stay")
	check(e1.sprite.texture != sprite_before and e1.sprite.texture == ThemeManager.get_tank_texture("e2"),
		"and look it")
	var all_up := true
	for e: EnemyTank in [taker, e1, e4, e5]:
		var b: Array = before[e]
		all_up = all_up and e.move_speed == b[2] + EnemyTank.ITEM_SPEED_STEP \
			and e.special_weapon_level == b[3] + 1 and e.health == b[1] + (1 if e == e1 else 0)
	check(all_up, "each a speed step and a gun level up, the taker too; HP as it was")
	check(_taken(parked) and e1.health == before[e1][1] + 1,
		"now type 2, the tank takes the Armor Up it was sitting on (checked every frame)")
	check(e1.addons == ["memory-save"] and e5.addons == ["memory-save"] and e4.addons == ["moon-shield"]
		and taker.addons == ["anti-water"], "memory-save for those without an add-on; the others keep theirs")
	check(not e5.is_mine_slowed, "mine slows gone")
	var lb: Array = before[late]
	check(late.tank_type_id == lb[0] and late.move_speed == lb[2] and late.addons.is_empty(),
		"a tank still appearing is left out")
	await _clear()

	print("\n[F] MAX Caisson Armor: every enemy on the field, the stronger type and 2 HP")
	var m_taker := _spawn_enemy(Vector2(320, 320), 8)
	var m1 := _spawn_enemy(Vector2(96, 96), 1)
	var m13 := _spawn_enemy(Vector2(224, 96), 13)
	var m1_hp := m1.health
	var m13_hp := m13.health
	var taker_hp := m_taker.health
	m13.apply_mine_slow()
	await _feed(m_taker, T.BULLETS_MAX)
	check(m1.tank_type_id == 2 and m13.tank_type_id == 14 and m_taker.tank_type_id == 8,
		"1 -> 2, 13 -> 14, the taker stays 8")
	check(m1.health == m1_hp + 2 and m13.health == mini(m13_hp + 2, 8) and m_taker.health == taker_hp + 2,
		"two more HP each (to 8 at most)")
	check(not m13.is_mine_slowed, "mine slows gone")
	await _clear()

	print("\n[G] Who PA Who: a moon shield for every enemy, even one appearing")
	var w_taker := _spawn_enemy(Vector2(320, 320), 24)
	var w2 := _spawn_enemy(Vector2(96, 96), 2)
	var w1 := _spawn_enemy(Vector2(224, 96), 1)
	var w_late := _spawn_enemy(Vector2(352, 96), 6)
	w_late.begin_materialize(5.0)
	var player_addons := _player.get_addon_names()
	await _feed(w_taker, T.INVINCIBLE_HELMET)
	var shielded := true
	for e: EnemyTank in [w_taker, w2, w1, w_late]:
		shielded = shielded and e.addons == ["moon-shield"] and e.has_moon_shield
	check(shielded, "all four wear the moon shield, in place of anti-water, anti-ice, memory-save")
	check(w2.get_collision_mask_value(2), "type 2 lost its anti-water with it")
	check(_player.get_addon_names() == player_addons and not _player._helmet_invincible,
		"the players get nothing")
	await _clear()

	print("\n[H] Flag On Guard taken by an enemy ends the base's fortification")
	var f_taker := _spawn_enemy(Vector2(320, 320), 8)
	var plain_walls := _base_wall_codes()
	await _feed(f_taker, T.FLAG_PROTECTION)
	check(not _lm._is_fortified and _base_wall_codes() == plain_walls, "with none, nothing changes")
	_lm.fortify_base(60.0)
	var iron := true
	for code in _base_wall_codes():
		iron = iron and LevelData.get_tile_category(code) in [LevelData.TileCategory.IRON_BLOCK,
			LevelData.TileCategory.SUPER_BLOCK]
	check(_lm._is_fortified and iron and _base_wall_codes() != plain_walls and _game.eagle.invincible,
		"a player's fortification: iron walls (super blocks stay), the flag safe")
	await _feed(f_taker, T.FLAG_PROTECTION)
	check(not _lm._is_fortified and _base_wall_codes() == plain_walls and not _game.eagle.invincible,
		"an enemy's Flag On Guard ends it at once: the map's own walls back, the flag open")
	await _clear()

	print("\n[I] Hold Enemy taken by an enemy holds the players for 7.5 s")
	var h_taker := _spawn_enemy(Vector2(320, 320), 8)
	await _feed(h_taker, T.TANK_WEB)
	check(GameManager.players_frozen and GameManager.players_freeze_timer <= Cookie.ENEMY_HOLD_TIME
		and GameManager.players_freeze_timer > Cookie.ENEMY_HOLD_TIME - 0.2, "the players are held, for 7.5 s")
	check(not GameManager.enemies_frozen, "the enemies are not")
	await tree.process_frame
	check(_overlay() == BaseTank.get_freeze_frames(), "wrapped in the ringed frost")
	var held_at := _player.global_position
	Input.action_press("p1_up")
	Input.action_press("p1_shoot")
	await _frames(10)
	var fired := _player.active_bullets
	Input.action_release("p1_up")
	Input.action_release("p1_shoot")
	check(_player.global_position == held_at and fired == 0, "a held player neither drives nor fires")
	GameManager.players_freeze_timer = 3.0
	await _frames()
	check(_overlay() == BaseTank.get_thaw_frames() and not BaseTank.get_thaw_frames().is_empty(),
		"with under 5000 ticks left, the bare web")
	GameManager.players_freeze_timer = 0.6
	await _frames()
	Input.action_press("p1_up")
	await _frames(5)
	Input.action_release("p1_up")
	check(_overlay().is_empty() and GameManager.players_frozen and _player.global_position == held_at,
		"the last 1000 ticks show nothing, though it is still held")
	GameManager.players_freeze_timer = 0.01
	await _frames(3)
	check(not GameManager.players_frozen, "the hold wears off")
	Input.action_press("p1_up")
	await _frames(10)
	Input.action_release("p1_up")
	check(_player.global_position.y < held_at.y, "and the player drives again")
	_player.activate_helmet(60.0)
	await _frames()
	check(_overlay() == BaseTank.get_shield_frames(), "a helmet shows its wreath")
	GameManager.freeze_all_players(Cookie.ENEMY_HOLD_TIME)
	await _frames()
	check(_overlay() == BaseTank.get_freeze_frames() and _player.visible, "a hold's frost covers it (and no blinking)")
	GameManager.players_freeze_timer = 0.01
	await _frames(3)
	check(_overlay() == BaseTank.get_shield_frames(), "and the wreath is back when the hold ends")
	await _clear()

	print("\n[J] Bomb !! taken by an enemy destroys every player tank, invincible or not")
	var b_taker := _spawn_enemy(Vector2(640, 96), 8)
	_player.activate_helmet(60.0)
	var lives := GameManager.player_lives[0]
	var old_player := _player
	await _feed(b_taker, T.TANK_BOMB)
	check(not is_instance_valid(old_player) or old_player.is_queued_for_deletion(), "the helmeted player is gone")
	check(GameManager.player_lives[0] == lives - 1, "one life lost, as to a shell (%d -> %d)" % [lives, GameManager.player_lives[0]])
	await tree.create_timer(1.2).timeout
	var respawned: Array = tree.get_nodes_in_group("players")
	check(respawned.size() == 1 and respawned[0] != old_player, "and a new tank comes")
	_player = respawned[0]
	while _player.is_materializing:
		await tree.process_frame
	_player.global_position = _at(Vector2(96, 640))
	lives = GameManager.player_lives[0]
	_player.health = 0
	_player.destroy()
	_player.destroy()  # a shell landing the same frame as the bomb
	check(GameManager.player_lives[0] == lives - 1, "destroyed twice in one frame, it loses one life")
	await tree.create_timer(1.2).timeout
	_player = tree.get_nodes_in_group("players")[0]
	while _player.is_materializing:
		await tree.process_frame
	_player.global_position = _at(Vector2(96, 640))
	await _clear()
	var b_taker2 := _spawn_enemy(Vector2(640, 96), 8)
	_player.begin_materialize(1.0)
	lives = GameManager.player_lives[0]
	await _feed(b_taker2, T.TANK_BOMB)
	check(is_instance_valid(_player) and not _player.is_queued_for_deletion() and GameManager.player_lives[0] == lives,
		"a tank still appearing is spared")
	while _player.is_materializing:
		await tree.process_frame
	await _clear()

	print("\n[K] +1 UP taken by an enemy: one more of each type still to come, and its own")
	_spawner._spawn_queue = [3, 3, 7, 8]
	GameManager.enemies_remaining = 5
	var u_taker := _spawn_enemy(Vector2(320, 320), 8)
	await _feed(u_taker, T.TANK_LIFE)
	var q: Array = _spawner._spawn_queue.duplicate()
	q.sort()
	check(q == [3, 3, 3, 7, 7, 8, 8], "the queue gains a 3, a 7 and one 8, the taker's type waiting too (%s)" % str(q))
	check(GameManager.enemies_remaining == 8, "three more to beat (%d)" % GameManager.enemies_remaining)
	check(GameManager.player_lives[0] == lives, "and the players' lives are untouched")
	_spawner._spawn_queue.clear()
	_spawner._halted = false  # a stage still being played, its queue run dry
	_spawner.spawn_timer.stop()
	var u_taker2 := _spawn_enemy(Vector2(480, 320), 8)
	await _feed(u_taker2, T.TANK_LIFE)
	check(_spawner._spawn_queue == [8] and not _spawner.spawn_timer.is_stopped(),
		"with none left to come: one of its own type, and the spawner starts again")
	_spawner.halt()
	_spawner._spawn_queue.clear()
	await _clear()

	print("\n[M] A hit it survives knocks out an upgrade it took, to be won back")
	var d := _spawn_enemy(Vector2(640, 320), 2)
	d.health = 6
	var d_speed := d.move_speed
	var d_gun := d.special_weapon_level
	await _feed(d, T.STAR_UP)
	await tree.create_timer(d._invulnerable_timer + 0.05).timeout
	var power_ups := _cookies_of(T.WEAPONS_UP)
	var speed_ups := _cookies_of(T.SPEED_UP)
	d.hit_by = 0
	d.take_damage(Vector2.UP)
	await _frames()
	check(d.special_weapon_level == d_gun and d.move_speed == d_speed + EnemyTank.ITEM_SPEED_STEP
		and _cookies_of(T.WEAPONS_UP) == power_ups + 1 and _cookies_of(T.SPEED_UP) == speed_ups,
		"the first hit takes the gun level back: a Power Up flung out")
	d.take_damage(Vector2.UP)
	await _frames()
	check(d.move_speed == d_speed and _cookies_of(T.SPEED_UP) == speed_ups + 1, "the next the speed step: a Speed Up")
	d.take_damage(Vector2.UP)
	await _frames()
	check(_cookies_of(T.WEAPONS_UP) == power_ups + 1 and _cookies_of(T.SPEED_UP) == speed_ups + 1,
		"then it has nothing above its type's own to lose")
	var flung: Cookie = null
	for c in tree.get_nodes_in_group("cookies"):
		if c.cookie_type == T.WEAPONS_UP:
			flung = c
	check(flung != null and flung._spray_origin.distance_to(d.global_position) < 1.0,
		"flung out from the tank")
	var airborne := _spawn_enemy(Vector2(640, 480), 2)
	airborne.health = 6
	airborne.item_gun_up()
	airborne.is_flying = true
	airborne.take_damage()
	airborne.is_flying = false
	check(airborne.special_weapon_level == d_gun + 1, "not while it is in the air (a mine's hit)")
	var last_hp := _spawn_enemy(Vector2(640, 640), 1)
	last_hp.item_gun_up()
	var before_kill := _cookies_of(T.WEAPONS_UP)
	last_hp.take_damage(Vector2.UP)
	await _frames()
	check(_cookies_of(T.WEAPONS_UP) == before_kill, "nor on the hit that finishes it")
	await _clear()

	print("\n[N] An enemy that loses anti-water on water stays afloat until it drives off")
	for ty in range(6, 14):
		for tx in range(10, 18):
			_lm._place_bg_tile(Vector2i(tx, ty), 0x05)
	var deep := _spawn_enemy(Vector2(448, 320), 2)
	var shore := _spawn_enemy(Vector2(368, 416), 2)
	await _frames()
	deep.set_addon("moon-shield")
	shore.set_addon("moon-shield")
	var deep_at := deep.global_position
	await _drive(deep, Vector2.UP, 0.5)
	check(deep.global_position.distance_to(deep_at) < 16.0 and deep.get_collision_mask_value(2),
		"mid-lake it stays where it is, water blocking it again (moved %.1f px)" % deep.global_position.distance_to(deep_at))
	await _drive(shore, Vector2.LEFT, 2.0)
	var shore_x := shore.global_position.x - _lm.global_position.x
	check(shore_x < 290.0 and shore._afloat_on.is_empty(), "near the shore it drives out (x %.0f)" % shore_x)
	await _drive(shore, Vector2.RIGHT, 2.0)
	shore_x = shore.global_position.x - _lm.global_position.x
	check(absf(shore_x - 290.0) < 1.0, "and the water stops it again (x %.1f, the pool's edge 290)" % shore_x)
	for ty in range(6, 14):
		for tx in range(10, 18):
			_lm._remove_bg_tile(Vector2i(tx, ty))
	await _clear()

	print("\n[L] The players still take every item as before")
	var sp := _player.speed_level
	var mine = _drop(T.SPEED_UP, _player.global_position - _lm.global_position)
	await _frames(3)
	check(_taken(mine) and _player.speed_level == mini(sp + 1, 3) and _pickups[-1] == [T.SPEED_UP, 0],
		"a player takes Speed Up")

	GameManager.players_frozen = false
	tree.root.remove_child(_game)
	_game.free()
	await tree.create_timer(0.8).timeout  # let the pickup sounds finish before quitting
	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
