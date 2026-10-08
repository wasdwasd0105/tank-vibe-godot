extends Node
## Headless test for what a joining player's own play shows on its own screen
## at once, before the host's word of it (docs/network_design.md section 7;
## Sean, 2026-10-08: "the fire on the ground will have delay, when player get
## hit the add-on drop will have delay"): its fire shell's patch of fire, its
## explosion shell's blast and the walls it breaks, its mines, an enemy its
## shot hits and doesn't finish (flash and sound), what a hit on its own tank
## costs it (health, add-on, a level), what an item it takes does (and the host
## taking it where its screen had its tank), and the items sprayed out of its
## kills and its own tank as the host's word of them comes. Each is the host's
## to settle, or to undo. In one offline process, as net_follow_test: the
## client's side by NetClientWorld's own functions, the host's by its own.
## Run as an override main scene:
##   Godot --headless res://scenes/test/net_predict_test.tscn

## The client driving tank 1 (here player 0's): a peer id no real one has.
const PEER := 9

var _fail := 0
var _game: Node
var _lm: LevelManager
var _player: PlayerTank
var _world: NetClientWorld
var _fx: Node2D
var _home := Vector2(320, 384)


func check(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + msg)
	if not cond:
		_fail += 1


func _ready() -> void:
	_run()


func _at(local: Vector2) -> Vector2:
	return _lm.global_position + local


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Its own tank fires (or lays) with [param action] on the client: pressed in
## an idle frame of its own, so it's just pressed there.
func _press_here(action: String) -> void:
	await _wait_frames(2)
	await get_tree().process_frame
	_player.can_shoot = true
	Input.action_press(action)
	Net.role = Net.Role.CLIENT
	_player._predict_fire()
	Net.role = Net.Role.OFFLINE
	Input.action_release(action)


## The newest ghost of its shots, flown on frame by frame till it ends.
func _fly_last_ghost() -> Bullet:
	var shot: Bullet = _world._ghosts[-1]["node"] if not _world._ghosts.is_empty() else null
	if shot:
		shot.set_physics_process(false)
		for i in 240:
			shot._fly_ghost(1.0 / 60.0)
			if not shot.visible:
				break
	return shot


func _clear_ghosts() -> void:
	for entry: Dictionary in _world._ghosts:
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
	_world._ghosts.clear()


## A snapshot of the host's, as the client decodes it, shown with _apply.
func _snap(time: float, spawns: Array = [], tiles: PackedInt32Array = PackedInt32Array(), game: Dictionary = {}) -> Dictionary:
	return {"time": time, "full": false, "map": [], "spawns": spawns, "updates": {}, "removed": PackedInt32Array(),
			"tiles": tiles, "game": game, "events": []}


## The host's snapshot comes to the client world, saying [param removed] have
## gone and [param spawns] have come; its time far off, so only what's shown at
## once shows. Returns it as kept for its time.
func _host_says(removed: Array, spawns: Array = []) -> Dictionary:
	var packet := []
	packet.resize(NetWorld.SNAP_SIZE)
	packet[NetWorld.SNAP_SEQ] = 1
	packet[NetWorld.SNAP_EPOCH] = 1
	packet[NetWorld.SNAP_TIME] = Time.get_ticks_msec() + 100000
	packet[NetWorld.SNAP_FLAGS] = 0
	packet[NetWorld.SNAP_MAP] = []
	packet[NetWorld.SNAP_SPAWNS] = spawns
	packet[NetWorld.SNAP_UPDATES] = PackedByteArray()
	packet[NetWorld.SNAP_REMOVED] = PackedInt32Array(removed)
	packet[NetWorld.SNAP_TILES] = PackedInt32Array()
	packet[NetWorld.SNAP_GAME] = {}
	packet[NetWorld.SNAP_EVENTS] = []
	var was := [_world._started, _world._epoch, _world._clock_offset, _world._have_clock, _world._late.duplicate()]
	_world._started = true
	_world._epoch = 1
	_world._on_packet(var_to_bytes(packet))
	var kept: Dictionary = _world._buffer[-1] if not _world._buffer.is_empty() else {}
	_world._buffer.clear()
	_world._started = was[0]
	_world._epoch = was[1]
	_world._clock_offset = was[2]
	_world._have_clock = was[3]
	_world._late = was[4]
	return kept


func _spawn_enemy(local: Vector2, type_id: int = 1) -> EnemyTank:
	var e: EnemyTank = load("res://scenes/tanks/enemy_tank.tscn").instantiate()
	e.tank_type_id = type_id
	_game.get_node("Entities/Enemies").add_child(e)
	e.set_physics_process(false)
	e.global_position = _at(local)
	return e


## An enemy tank shown here as the host's entity [param nid].
func _shown_enemy(nid: int, local: Vector2, hp: int) -> EnemyTank:
	var enemy := _spawn_enemy(local)
	enemy.health = hp
	enemy.current_direction = Vector2.UP
	_world._nodes[nid] = enemy
	_world._states[nid] = enemy.net_state()
	_world._types[nid] = NetWorld.T_ENEMY
	return enemy


## A shell of the enemies' shown here as the host's entity [param nid].
func _shown_enemy_shell(nid: int, local: Vector2, way: Vector2) -> Bullet:
	var theirs: Bullet = load("res://scenes/tanks/bullet.tscn").instantiate()
	theirs.net_setup([BaseTank.FACINGS.find(way), "regular", [0.0], -1, 256.0, -1.0, false, 0.0, 0.0, -1, 1,
			[0.0], [0, -1, -1]])
	_game.get_node("Entities/Bullets").add_child(theirs)
	theirs.set_physics_process(false)
	NetClientWorld._strip_physics(theirs)
	theirs.global_position = _at(local)
	_world._nodes[nid] = theirs
	_world._states[nid] = [theirs.global_position.x, theirs.global_position.y]
	_world._types[nid] = NetWorld.T_BULLET
	return theirs


## An item of [param type] shown here as the host's entity [param nid].
func _shown_item(nid: int, local: Vector2, type: int) -> Cookie:
	var item: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	item.net_setup([type])
	_game.get_node("Entities/PowerUps").add_child(item)
	NetClientWorld._strip_physics(item)
	item.set_process(false)
	item.global_position = _at(local)
	_world._nodes[nid] = item
	_world._states[nid] = item.net_state()
	_world._types[nid] = NetWorld.T_COOKIE
	return item


## The host's state of the client's own tank (entity 5) as it has it now, with
## [param health] and add-ons [param bits]: shown, as a snapshot would.
func _host_tank_state(health: int, bits: int) -> Array:
	var state := _player.net_state()
	state[7] = health
	state[8] = bits
	return state


func _bricks(row: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var home_cell := _lm.world_to_tile(_at(_home))
	for dx in range(-2, 3):
		var cell := Vector2i(home_cell.x + dx, row)
		_lm._remove_fg_tile(cell)
		_lm._brick_damage.erase(cell)
		_lm._place_fg_tile(cell, 0x19)
		cells.append(cell)
	return cells


func _clear_bricks(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_lm._remove_fg_tile(cell)
		_lm._brick_damage.erase(cell)


func _run() -> void:
	var tree := get_tree()
	await tree.process_frame
	AudioServer.set_bus_mute(0, true)
	GameManager.current_stage = 1
	GameManager.player_active[0] = true
	GameManager.player_active[1] = false
	_game = load("res://scenes/game.tscn").instantiate()
	_game.show_intro = false  # straight into play
	tree.root.add_child(_game)
	for i in range(5):
		await tree.process_frame
	_lm = _game.get_level_manager()
	_game.get_node("EnemySpawner").spawn_timer.stop()
	for p in tree.get_nodes_in_group("players"):
		_player = p
	while _player.is_materializing:
		await tree.process_frame
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	# Open ground in the middle of the field.
	for tile in _lm._fg_tile_data.keys():
		if tile.x >= 4 and tile.x <= 36 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_fg_tile(tile)
			_lm._brick_damage.erase(tile)
			_lm._hard_brick_hp.erase(tile)
	for tile in _lm._bg_tile_data.keys():
		if tile.x >= 4 and tile.x <= 36 and tile.y >= 3 and tile.y <= 22:
			_lm._remove_bg_tile(tile)
	await tree.process_frame
	_player.set_physics_process(false)
	_player.global_position = _at(_home)
	_player.current_direction = Vector2.UP
	_player._update_sprite_direction()
	_player.is_invincible = false
	_fx = Node2D.new()
	_game.add_child(_fx)
	_world = NetClientWorld.new()
	_world.setup(_game, _lm, null, {"players": _game.get_node("Entities/Players"),
			"enemies": _game.get_node("Entities/Enemies"), "bullets": _game.get_node("Entities/Bullets"),
			"powerups": _game.get_node("Entities/PowerUps"), "terrain": _lm.terrain_node}, _fx)
	_game.add_child(_world)
	_world.set_process(false)  # (its own clock: this test runs it by hand)
	_player.set_net_predicted(true, 0)
	_world._nodes[5] = _player
	_world._states[5] = _player.net_state()
	_world._types[5] = NetWorld.T_PLAYER
	Net.ping_ms = 30.0
	var gm := GameManager
	var home_cell := _lm.world_to_tile(_at(_home))

	print("\n[A] Its fire shell's patch of fire: laid at once where it ends, the host's taking over")
	gm.player_weapon_levels[0] = 0
	gm.player_secondary_weapon_types[0] = "fire"
	gm.player_secondary_weapon_counts[0] = 30
	var bricks := _bricks(home_cell.y - 4)
	await _press_here("p1_shoot2")
	var fire_shot := _fly_last_ghost()
	var guess: Dictionary = _world._guessed_fires[0] if _world._guessed_fires.size() == 1 else {}
	var expected: Array = []
	if fire_shot:
		for tile: Array in LevelManager.fire_patch_tiles(_lm.fire_anchor(fire_shot.global_position)):
			if _lm.fire_can_lie(tile[0]):
				expected.append(tile[0])
	var laid: Array = guess.get("fires", {}).keys()
	laid.sort()
	expected.sort()
	check(fire_shot != null and fire_shot.ignites_ground and not fire_shot.visible and not laid.is_empty() and laid == expected,
		"its fire shell ends at the bricks: its patch laid there at once, on the tiles the host's will lay it on (%d)" % laid.size())
	var one: GroundFire = guess["fires"][laid[0]] if not laid.is_empty() else null
	check(one != null and one.get_parent() == _lm.terrain_node and not one.is_in_group(NetWorld.GROUP)
		and one._current_row() == 3 and not one.visible,
		"each a players' fire, on the ground, no entity of the host's world, armed a moment later as the host's")
	await tree.create_timer(0.12).timeout
	check(guess["fires"].values().all(func(f: GroundFire) -> bool: return f.visible), "then all showing")
	var spec := fire_shot.net_spawn_args() if fire_shot else []
	var copy := Bullet.new()
	copy.net_setup(spec)
	check(spec.size() == 13 and spec[12] == [1, 0, -1] and copy.ignites_ground and copy.is_player_bullet and not copy.explodes,
		"a shell tells the clients its side and the fire it drops: %s" % str(spec[12] if spec.size() == 13 else spec))
	copy.free()
	# The host's word: its fires for two of those tiles come (it lays a patch all
	# at once): they show on from the ones laid here; the rest laid here go.
	var spawns: Array = []
	for i in 2:
		var at := _lm.tile_to_world(laid[i])
		spawns.append([200 + i, NetWorld.T_FIRE, [3, 0.05, 0, 0.0], [at.x, at.y]])
	_world._apply(_snap(Time.get_ticks_msec(), spawns))
	_world._settle_fires()
	await tree.process_frame
	var host_fire := _world.node_for(200) as GroundFire
	var left := _lm.terrain_node.get_children().filter(func(n: Node) -> bool:
		return n is GroundFire and not n.is_queued_for_deletion() and not n.is_in_group(NetWorld.GROUP))
	check(host_fire != null and host_fire.visible and _world._guessed_fires.is_empty() and left.is_empty(),
		"the host's fires come for two of its tiles: showing at once from where those were, the rest laid here gone")
	# Its side burning on a tile already: the host feeds that one, none laid there.
	_world._despawn(201)
	await _press_here("p1_shoot2")
	_fly_last_ghost()
	var fed: Dictionary = _world._guessed_fires[-1].get("fires", {}) if not _world._guessed_fires.is_empty() else {}
	check(not fed.is_empty() and not fed.has(laid[0]), "a tile its side's fire burns on already: none laid there (the host feeds that one)")
	# No word of a patch for long: it goes.
	for each: Dictionary in _world._guessed_fires:
		each["msec"] = int(each["msec"]) - NetClientWorld.GUESS_MAX_MS - 1
	_world._settle_fires()
	check(_world._guessed_fires.is_empty(), "a patch the host's word never brings: gone after a while")
	_world._despawn(200)
	_clear_ghosts()
	# An enemies' fire shell ending on its own tank: their patch, laid there too.
	var enemy_fire := _shown_enemy_shell(300, _home + Vector2(0, -30), Vector2.DOWN)
	enemy_fire.ignites_ground = true
	enemy_fire.is_player_bullet = false
	_player.health = 4
	_world._states[5] = _player.net_state()
	_world._show_own_hits()
	var theirs_laid: Dictionary = _world._guessed_fires[-1].get("fires", {}) if not _world._guessed_fires.is_empty() else {}
	check(not enemy_fire.visible and not theirs_laid.is_empty() and theirs_laid.values()[0]._current_row() == 2,
		"an enemies' fire shell ending on its own tank: their patch laid there at once too")
	_world._despawn(300)
	for each: Dictionary in _world._guessed_fires:
		each["msec"] = 0
	_world._settle_fires()
	_world._drop_own_effects(func(_e: Dictionary) -> bool: return true)
	_world._guessed_hits.clear()
	_clear_bricks(bricks)

	print("\n[B] Its explosion shell's blast: its picture at once, its walls broken here as the host's will")
	bricks = _bricks(home_cell.y - 4)
	gm.player_secondary_weapon_types[0] = "explosion"
	gm.player_secondary_weapon_counts[0] = 20
	var bystander := _shown_enemy(310, _home + Vector2(96, -128), 9)
	var fx_before := _fx.get_child_count()
	await _press_here("p1_shoot2")
	var blast_shot := _fly_last_ghost()
	var blasts := _fx.get_children().filter(func(n: Node) -> bool: return n is ExplosionBlast)
	var blast: ExplosionBlast = blasts[-1] if not blasts.is_empty() else null
	var origin := ExplosionBlast.grid_origin(blast_shot.global_position - _lm.global_position, ExplosionBlast.SHELL_SIZE) \
			if blast_shot else Vector2i.ZERO
	check(blast_shot != null and blast_shot.explodes and blast != null and blast.net_walls.is_valid()
		and blast.origin == origin and _world._predicted_blasts.size() == 1 and _fx.get_child_count() > fx_before,
		"it ends at the bricks: its blast laid there at once, where the host's goes off")
	await tree.create_timer(0.2).timeout
	var record: Dictionary = _world._predicted_blasts[0] if _world._predicted_blasts.size() == 1 else {}
	var broke: Array = record.get("walls", [])
	check(not broke.is_empty() and broke.all(func(entry: Array) -> bool: return _lm.net_cell(entry[0]) != entry[1]),
		"on its wall frame, the walls it reaches broken here (%d), as the host's will break them" % broke.size())
	check(is_instance_valid(bystander) and bystander.health == 9,
		"a blast laid here hurts nothing: the host's does")
	fx_before = _fx.get_child_count()
	_world._shown_time = Time.get_ticks_msec()
	_world._play([NetWorld.EV_BLAST, origin.x, origin.y + 1, blast.level if blast else 0])
	check(_fx.get_child_count() == fx_before and float(record.get("t0", -1.0)) == _world._shown_time,
		"the host's picture of it, a tile off: not shown again")
	# Its walls settled once the host's blast has had time to break them: the
	# cells its word spoke of are as it says, the others broken here put back.
	if broke.size() >= 2:
		var heard_cell: Vector2i = broke[0][0]
		var was_other: Array = broke[1][1]
		var now_heard := _lm.net_cell(heard_cell)
		var undone := _world.guesses_undone
		_world._apply(_snap(float(record["t0"]) + 30.0, [], PackedInt32Array([heard_cell.x, heard_cell.y,
				now_heard[0], now_heard[1], now_heard[2]])))
		check(_world._predicted_blasts.size() == 1, "its walls not settled before the host's blast could break them")
		_world._apply(_snap(float(record["t0"]) + NetClientWorld.BLAST_WALLS_MS + 1.0))
		check(_world._predicted_blasts.is_empty() and _lm.net_cell(heard_cell) == now_heard
			and _lm.net_cell(broke[1][0]) == was_other and _world.guesses_undone == undone + broke.size() - 1,
			"then: the cell the host spoke of as it says, the ones it didn't put back as they were")
	# One the host's word never brings: all put back.
	_clear_bricks(bricks)
	bricks = _bricks(home_cell.y - 4)
	_clear_ghosts()
	await _press_here("p1_shoot2")
	_fly_last_ghost()
	await tree.create_timer(0.2).timeout
	var lost: Dictionary = _world._predicted_blasts[0] if _world._predicted_blasts.size() == 1 else {}
	var lost_walls: Array = lost.get("walls", [])
	lost["msec"] = int(lost.get("msec", 0)) - NetClientWorld.GUESS_MAX_MS - 1
	_world._expire_guesses()
	check(not lost_walls.is_empty() and _world._predicted_blasts.is_empty()
		and lost_walls.all(func(entry: Array) -> bool: return _lm.net_cell(entry[0]) == entry[1]),
		"a blast the host's word never brings: its walls put back")
	_world._despawn(310)
	_clear_ghosts()
	_clear_bricks(bricks)

	print("\n[C] Its mines: laid at once where the host will lay them, the host's taking over")
	gm.player_secondary_weapon_types[0] = "mine"
	gm.player_secondary_weapon_counts[0] = 20
	_player.global_position = _at(_home)
	_player.current_direction = Vector2.UP
	await _press_here("p1_shoot2")
	var mine_here: Mine = _world._ghost_mines[0]["node"] if _world._ghost_mines.size() == 1 else null
	var behind := Vector2i(Mine.round_half_even(_home.x / 32.0 - 1.0), Mine.round_half_even(_home.y / 32.0 - 1.0)) + Vector2i(0, 2)
	check(mine_here != null and mine_here.global_position == _lm.mine_center(behind) and mine_here.net_shot >= 256
		and mine_here.get_parent() == _lm.terrain_node and _lm.get_mines().is_empty(),
		"its press: a mine laid here at once, straight behind its tank as the host lays it, numbered as a shot")
	await tree.create_timer(Mine.ARM_TIME + 0.05).timeout
	check(mine_here != null and mine_here.visible, "it surfaces as the host's does")
	var at_mine := _lm.mine_center(behind)
	_world._apply(_snap(Time.get_ticks_msec(), [[210, NetWorld.T_MINE, [0, 1, 0.05, mine_here.net_shot if mine_here else 0],
			[at_mine.x, at_mine.y, 0, 1.0]]]))
	var host_mine := _world.node_for(210) as Mine
	await tree.process_frame
	check(host_mine != null and _world._ghost_mines.is_empty() and not is_instance_valid(mine_here)
		and host_mine._age >= Mine.ARM_TIME and host_mine.visible,
		"the host's mine with its number comes: it lies on from the one laid here, showing")
	_world._despawn(210)
	await _press_here("p1_shoot2")
	var unlaid: Mine = _world._ghost_mines[0]["node"] if _world._ghost_mines.size() == 1 else null
	var had_one := unlaid != null
	if not _world._ghost_mines.is_empty():
		_world._ghost_mines[0]["born"] = 0
	_world._expire_ghosts()
	await tree.process_frame
	check(had_one and not is_instance_valid(unlaid) and _world._ghost_mines.is_empty(),
		"one the host never lays: gone after a while, as a shot's ghost")

	print("\n[D] An enemy its shot hits and doesn't finish: its flash and sound at once")
	gm.player_secondary_weapon_types[0] = "rapid"
	var tough := _shown_enemy(320, _home + Vector2(0, -160), 3)
	SoundManager._predicted.clear()
	await _press_here("p1_shoot")
	_fly_last_ghost()
	check(not tough.net_gone and tough.visible and tough._damage_flash_timer > 0.1
		and SoundManager._predicted.any(func(p: Array) -> bool: return p[0] == SoundManager.SHOT_TAG and p[1] == &"tank_hit"),
		"its red flash and its hit's sound at once, alive")
	var flash_state := tough.net_state()
	flash_state[4] = BaseTank.DAMAGE_FLASH_DURATION
	tough._flash_guessed_until = Time.get_ticks_msec()
	tough.net_apply(flash_state)
	check(tough._damage_flash_timer <= 0.0, "the host's flash of that hit, come after it ended here: left out")
	var heard: int = SoundManager._last_played.get(&"tank_hit", 0)
	await tree.create_timer(0.05).timeout
	SoundManager.play_from_host(&"tank_hit", SoundManager.SHOT_TAG)
	check(SoundManager._last_played.get(&"tank_hit", 0) == heard, "the host's sound of it, marked as its shot's: not again")
	_world._show_enemy_hit(tough, _world._ghosts[-1]["node"])
	check(tough._damage_flash_timer <= 0.0, "that shot's hit again: once only")
	# The host marks that sound as the shot's.
	var host_world := NetHostWorld.new()
	host_world.setup(_game, _lm, null)
	_game.add_child(host_world)
	var listener := NetHostWorld.ClientView.new()
	host_world._views[PEER] = listener
	var target := _spawn_enemy(_home + Vector2(200, -200), 2)
	target.hit_by = 0
	target.take_damage(Vector2.UP)
	check(listener.events.has([NetWorld.EV_SOUND, "tank_hit", SoundManager.SHOT_TAG]),
		"host: an enemy player 1's shot hits and doesn't finish: its sound goes out marked as that shot's")
	target.queue_free()
	host_world.queue_free()
	await tree.process_frame
	_world._despawn(320)
	_clear_ghosts()

	print("\n[E] A hit on its own tank: what it costs shown at once")
	_player.health = 4
	_player.apply_addon("anti-water")
	_world._states[5] = _player.net_state()
	var incoming := _shown_enemy_shell(330, _home + Vector2(0, -30), Vector2.DOWN)
	_world._show_own_hits()
	check(_player.health == 3 and _player._current_utility_addon.is_empty() and not _player.has_boat
		and _world._own_effects.size() == 1,
		"the hit: its health down and its add-on off at once")
	_player.net_apply(_host_tank_state(4, 2))
	check(_player.health == 3 and _player._current_utility_addon.is_empty(),
		"the host's state from before its word of it: still shown so")
	_world._states[5] = _host_tank_state(3, 0)
	_world._apply(_snap(Time.get_ticks_msec()))
	check(_world._own_effects.is_empty() and _player.health == 3, "its word shown (health down): the host's to show now")
	_world._despawn(330)
	_world._guessed_hits.clear()
	# No add-on: a speed step and a gun level by turns, the host saying whose.
	_player.health = 4
	gm.player_speed_levels[0] = 2
	gm.player_weapon_levels[0] = 2
	_world._game[NetWorld.G_SPEED] = [2, 1]
	_world._game[NetWorld.G_WEAPON] = [2, 0]
	_world._states[5] = _host_tank_state(4, 0)
	_player.net_apply(_world._states[5])
	_player._grace_guessed_frame = -100000  # (past the grace after the last)
	var turn := _shown_enemy_shell(331, _home + Vector2(0, -30), Vector2.DOWN)
	_world._show_own_hits()
	check(gm.player_speed_levels[0] == 1 and gm.player_weapon_levels[0] == 2 and _player.net_hits_odd,
		"no add-on, its turn for speed: a speed step off at once, the next turn the gun's")
	_world._apply_game({NetWorld.G_SPEED: [2, 1]})
	check(gm.player_speed_levels[0] == 1, "the host's numbers from before its word: still shown so")
	# The host says the hit missed: all as it was.
	_world._guessed_hits[turn.get_instance_id()]["until"] = 0.0
	_host_says([])
	check(turn.visible and _world._own_effects.is_empty() and gm.player_speed_levels[0] == 2 and _player.health == 4
		and not _player.net_hits_odd, "its word that it missed: speed, health and turn as the host has them")
	_world._despawn(331)
	_world._guessed_hits.clear()
	# The gun's turn, the host says: a gun level off, the next turn speed's.
	var odd := _host_tank_state(4, 0)
	odd[3] = int(odd[3]) | PlayerTank.NET_HITS_ODD
	_world._states[5] = odd
	_player.net_apply(odd)
	_player._grace_guessed_frame = -100000
	_shown_enemy_shell(334, _home + Vector2(0, -30), Vector2.DOWN)
	_world._show_own_hits()
	check(gm.player_weapon_levels[0] == 1 and gm.player_speed_levels[0] == 2 and not _player.net_hits_odd,
		"its turn for the gun, the host says: a gun level off at once, the next turn speed's")
	_world._drop_own_effects(func(_e: Dictionary) -> bool: return true)
	_world._despawn(334)
	_world._guessed_hits.clear()
	_world._states[5] = _host_tank_state(4, 0)
	_player.net_apply(_world._states[5])
	var taken_was := _player._hits_taken
	_player._hits_taken = 1
	var odd_out := int(_player.net_state()[3]) & PlayerTank.NET_HITS_ODD != 0
	_player._hits_taken = 2
	check(odd_out and int(_player.net_state()[3]) & PlayerTank.NET_HITS_ODD == 0,
		"host: whose turn the next level-costing hit is goes out with its tank")
	_player._hits_taken = taken_was
	# Memory-save keeps it all but the health; the moon shield goes before another add-on.
	_player.apply_addon("memory-save")
	_world._states[5] = _host_tank_state(4, BaseTank.NET_ADDON_BITS["memory-save"])
	_player._grace_guessed_frame = -100000
	_shown_enemy_shell(332, _home + Vector2(0, -30), Vector2.DOWN)
	_world._show_own_hits()
	var kept_all: Dictionary = _world._own_effects[-1]["values"] if not _world._own_effects.is_empty() else {}
	check(kept_all.keys() == ["health"] and _player.has_memory_save, "memory-save: only its health")
	_world._drop_own_effects(func(_e: Dictionary) -> bool: return true)
	_world._despawn(332)
	_world._guessed_hits.clear()
	_player._remove_utility_addon()
	_player.apply_addon("anti-ice")
	_player.apply_addon("moon-shield")
	_world._states[5] = _host_tank_state(4, BaseTank.NET_ADDON_BITS["moon-shield"] | BaseTank.NET_ADDON_BITS["anti-ice"])
	_player.net_apply(_world._states[5])
	_player._grace_guessed_frame = -100000
	_shown_enemy_shell(333, _home + Vector2(0, 30), Vector2.UP)  # (from behind: the shield faces up)
	_world._show_own_hits()
	check(not _player.has_moon_shield and _player._current_utility_addon == "anti-ice",
		"a moon shield and another: the shield goes first")
	_world._drop_own_effects(func(_e: Dictionary) -> bool: return true)
	_world._despawn(333)
	_world._guessed_hits.clear()
	_player._remove_moon_shield()
	_player._remove_utility_addon()
	_world._states[5] = _host_tank_state(4, 0)
	_player.net_apply(_world._states[5])
	await tree.create_timer(0.7).timeout  # (past its grace after those)

	print("\n[F] An item it takes: what it does shown at once; the host takes it where its screen had it")
	var T := CookieData.CookieType
	gm.player_weapon_levels[0] = 0
	_world._game[NetWorld.G_WEAPON] = [0, 0]
	_player.net_apply(_world._states[5])
	var power := _shown_item(340, _home + Vector2(0, 20), T.WEAPONS_UP)
	_world.predict_pickups(_player)
	check(not power.visible and gm.player_weapon_levels[0] == 1 and _player.is_invincible,
		"Power Up taken here: its gun a level up at once, and the item's moment of shield")
	_world._apply_game({NetWorld.G_WEAPON: [0, 0]})
	check(gm.player_weapon_levels[0] == 1, "the host's numbers from before its word: still shown so")
	var word := _host_says([340])
	check(not _world._nodes.has(340) and word.get("settles", []).has(power.get_instance_id()) and _world._own_effects.size() == 1,
		"the host's word of it comes: the item gone for good, what it did settled once that word is shown")
	word["game"] = {NetWorld.G_WEAPON: [1, 0]}
	_world._apply(word)
	check(_world._own_effects.is_empty() and gm.player_weapon_levels[0] == 1, "shown: the host's numbers now")
	var never := _shown_item(341, _home + Vector2(0, 20), T.WEAPONS_UP)
	_world.predict_pickups(_player)
	check(gm.player_weapon_levels[0] == 2, "another taken here")
	_world._guessed_pickups[never.get_instance_id()]["msec"] -= NetClientWorld.GUESS_MAX_MS + 1
	_host_says([])
	check(never.visible and gm.player_weapon_levels[0] == 1 and _world._own_effects.is_empty(),
		"no word of it for long: the item back, its gun as the host has it")
	_world._despawn(341)
	_world._guessed_pickups.clear()
	# The others, each from what it shows.
	var cases := [
		[T.SPEED_UP, "Speed Up: a speed step up"],
		[T.HP_UP, "Armor Up: a health point"],
		[T.MOON_SHIELD_COOKIE, "Shield of Moon: on at once"],
		[T.FIRE_COOKIE, "a gun: switched to, its ammo"],
		[T.BULLETS_MAX, "MAX Caisson Armor: its ammo full"],
		[T.TANK_LIFE, "+1 UP: a life"],
		[T.SCORE_1000, "+1000 past 10,000: the score, and the life it earns"],
		[T.INVINCIBLE_HELMET, "Who PA Who: shielded, the wreath on"],
	]
	for case: Array in cases:
		gm.player_speed_levels[0] = 2
		gm.player_secondary_weapon_types[0] = "rapid"
		gm.player_secondary_weapon_counts[0] = 10
		gm.player_lives[0] = 3
		gm.player_scores[0] = 9400
		_player.health = 4
		_world._states[5] = _host_tank_state(4, 0)
		_player.net_apply(_world._states[5])
		_shown_item(342, _home + Vector2(0, 20), case[0])
		_world.predict_pickups(_player)
		var shown := false
		match int(case[0]):
			T.SPEED_UP:
				shown = gm.player_speed_levels[0] == 3
			T.HP_UP:
				shown = _player.health == 5
			T.MOON_SHIELD_COOKIE:
				shown = _player.has_moon_shield
			T.FIRE_COOKIE:
				shown = gm.player_secondary_weapon_types[0] == "fire" \
						and gm.player_secondary_weapon_counts[0] == CookieData.WEAPON_DATA["fire"]["reload_count"]
			T.BULLETS_MAX:
				shown = gm.player_secondary_weapon_counts[0] == CookieData.WEAPON_DATA["rapid"]["max_count"]
			T.TANK_LIFE:
				shown = gm.player_lives[0] == 4
			T.SCORE_1000:
				shown = gm.player_scores[0] == 10400 and gm.player_lives[0] == 4
			T.INVINCIBLE_HELMET:
				shown = _player.is_invincible and _player.invincible_timer > PlayerTank.WREATH_MIN_LEFT
		check(shown, case[1])
		_world._drop_own_effects(func(_e: Dictionary) -> bool: return true)
		_world._despawn(342)
		_world._guessed_pickups.clear()
	# A bomb: every enemy shown goes at once, the host's word settling each.
	var foes := [_shown_enemy(350, _home + Vector2(-200, -200), 2), _shown_enemy(351, _home + Vector2(200, -200), 4)]
	_shown_item(352, _home + Vector2(0, 20), T.TANK_BOMB)
	_world.predict_pickups(_player)
	check(foes.all(func(e: EnemyTank) -> bool: return e.net_gone and not e.visible) and _world._guessed_kills.size() == 2,
		"Bomb !!: every enemy shown goes at once, its explosion shown")
	_host_says([350, 351, 352])
	check(not _world._nodes.has(350) and not _world._nodes.has(351) and _world._guessed_kills.is_empty(),
		"the host's word of them: gone for good")
	_world._drop_own_effects(func(_e: Dictionary) -> bool: return true)
	_world._guessed_pickups.clear()
	# The host takes an item where the client's report had its tank, before its
	# copy gets there; a report further off than the copy ever lags isn't believed.
	Net.role = Net.Role.OFFLINE
	_player.set_net_predicted(false, 0)
	PlayerInput.set_remote(PEER, 0, -1, [false, false], [0, 0])
	PlayerInput.set_seat(0, PlayerInput.controller_key(PEER, 0))
	_player.weapon_level = 0
	_player._host_drives = false  # (the client drives it: no spell of the host's on)
	gm.player_weapon_levels[0] = 0
	var ahead: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	ahead.setup(T.WEAPONS_UP, 0.0)
	_game.get_node("Entities/PowerUps").add_child(ahead)
	ahead.global_position = _player.global_position + Vector2(0, -40)
	var far: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	far.setup(T.SPEED_UP, 0.0)
	_game.get_node("Entities/PowerUps").add_child(far)
	far.global_position = _player.global_position + Vector2(400, 0)
	await tree.process_frame
	var frame := 0
	for spot: Vector2 in [_player.global_position + Vector2(0, -30), _player.global_position + Vector2(400, 0)]:
		frame += 1
		PlayerInput.set_remote_report(PEER, 0, true, true, spot, 0, true, _player.net_override, frame, 0.0)
	_player._take_items_where_reported()
	check(ahead.is_queued_for_deletion() and _player.weapon_level == 1 and not far.is_queued_for_deletion(),
		"host: the item where its report had its tank taken at once (its gun up); one where it can't be, not")
	far.queue_free()
	PlayerInput.reset_to_local()
	_player.set_net_predicted(true, 0)
	await tree.process_frame

	print("\n[G] Items sprayed out of its kills and its own tank: shown as the host's word comes")
	var victim := _shown_enemy(360, _home + Vector2(0, -200), 1)
	_world.note_own_hit(victim)
	var from := victim.global_position
	var to := from + Vector2(160, 64)
	var sprayed := [361, NetWorld.T_COOKIE, [T.SCORE_500, from.x, from.y, to.x, to.y, 0.3, 0.0], [from.x, from.y, 0.3, 1.0]]
	var far_off := from + Vector2(-500, 300)
	var elsewhere := [362, NetWorld.T_COOKIE, [T.SCORE_200, far_off.x, far_off.y, far_off.x + 64, far_off.y, 0.2, 0.0],
			[far_off.x, far_off.y, 0.3, 1.0]]
	word = _host_says([360], [sprayed, elsewhere])
	var drop := _world.node_for(361) as Cookie
	check(drop != null and drop.net_sprayed_here and drop.is_spraying() and not _world._nodes.has(362)
		and word.get("spawns", []).size() == 1 and int(word["spawns"][0][0]) == 362,
		"its kill's word comes with the item it drops: shown at once, sprayed out here; one from elsewhere waits its time")
	await tree.create_timer(0.4).timeout
	_world._place(361, drop, from + Vector2(80, -60))
	check(drop != null and not drop.is_spraying() and drop.global_position.distance_to(to) < 0.5 and drop.scale.x > 0.99,
		"sprayed out, it lies where it lands, whatever later states of its flight say")
	_world._despawn(361)
	# Its own tank's add-on, sprayed out by a hit: shown as the word comes too.
	var mine_at := _player.global_position + Vector2(-20, 10)
	var shed := [363, NetWorld.T_COOKIE, [T.ANTI_WATER_COOKIE, mine_at.x, mine_at.y, mine_at.x + 200, mine_at.y, 0.3, 0.0],
			[mine_at.x, mine_at.y, 0.3, 1.0]]
	_host_says([], [shed])
	check(_world._nodes.has(363), "the add-on a hit cost its own tank, sprayed out: shown as the word comes")
	_world._despawn(363)
	# The host sprays its items out so: from where, to where, how long, how far on.
	var host_item: Cookie = load("res://scenes/powerups/powerup.tscn").instantiate()
	host_item.setup(T.SCORE_500, 0.0, _player.global_position)
	host_item.global_position = _player.global_position + Vector2(128, 0)
	_game.get_node("Entities/PowerUps").add_child(host_item)
	var while_out := host_item.net_spawn_args()
	await tree.create_timer(0.5).timeout
	check(while_out.size() == 7 and Vector2(while_out[3], while_out[4]).distance_to(_player.global_position + Vector2(128, 0)) < 0.5
		and host_item.net_spawn_args().size() == 1,
		"host: an item still sprayed out tells where from and to; one down just what it is")
	host_item.queue_free()

	print("\n==== %s ====" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	tree.quit(_fail)
