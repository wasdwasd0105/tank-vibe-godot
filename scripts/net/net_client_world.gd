class_name NetClientWorld
extends Node
## A client's side of the game scene: it shows the host's world and runs none
## of it (NetWorld has the format). Snapshots are buffered and shown DELAY_MS
## behind the host's clock, so that however TCP bunches them up, each is shown
## on time and positions glide from one to the next. The entities are the game's
## own scenes, built in mirror mode: their logic stays off and they draw
## themselves from the host's state (net_setup, net_apply).

## How far behind the host's newest snapshot the world is shown: three snapshots,
## so one or two can come late without the picture stopping.
const DELAY_MS := 100.0
## With this many snapshots waiting, the client has fallen behind (it stalled):
## it catches up at once.
const MAX_BUFFERED := 45
## The clock estimate may run fast by this much a second; a newer sample that
## says the host is further ahead corrects it at once.
const CLOCK_SETTLE_MS := 1.0

var game: Node = null
var level_manager: LevelManager = null
var overlay: StageOverlay = null
## Where each kind of entity goes: NetWorld.TYPES' parent keys -> nodes.
var containers: Dictionary = {}
var effects: Node = null

var _buffer: Array = []          # decoded snapshots, oldest first
var _epoch := -1
var _templates: Dictionary = {}  # nid -> the spawn state: how its updates are typed
var _states: Dictionary = {}     # nid -> its state as shown now
var _types: Dictionary = {}      # nid -> type
var _nodes: Dictionary = {}      # nid -> the node showing it
var _glides: Dictionary = {}     # type -> the state fields past the position that glide
var _game: Dictionary = {}       # the game state as shown now
var _clock_offset := 0.0         # host ms - local ms, as estimated
var _have_clock := false
var _shown_time := 0.0           # host time of the snapshot shown now
var _started := false
var _scenes: Dictionary = {}     # path -> loaded scene or script
## How many of each event (NetWorld.EV_*) have played here, for tests.
var played: Dictionary = {}
## Shells of this machine's own tanks, drawn ahead (_lead_shell): nid ->
## {"velocity" px/s, "start" where it set out, "range" how far it goes (<= 0
## no end), "pierces" drills through walls}.
var _own_shells: Dictionary = {}


func _init() -> void:
	name = "NetClientWorld"
	process_mode = Node.PROCESS_MODE_ALWAYS  # it shows the host's pause too


func setup(p_game: Node, p_level_manager: LevelManager, p_overlay: StageOverlay,
		p_containers: Dictionary, p_effects: Node) -> void:
	game = p_game
	level_manager = p_level_manager
	overlay = p_overlay
	containers = p_containers
	effects = p_effects


func _ready() -> void:
	Net.world_sink = _on_packet
	for packet in Net.take_world_packets():
		_on_packet(packet)


func _exit_tree() -> void:
	if Net.world_sink.is_valid() and Net.world_sink.get_object() == self:
		Net.world_sink = Callable()


## True once the host's world is showing.
func is_started() -> bool:
	return _started


## How many entities are showing (for tests and the debug overlay).
func entity_count() -> int:
	return _nodes.size()


## The node showing host entity [param nid], or null.
func node_for(nid: int) -> Node:
	return _nodes.get(nid)


# =====================================================================
# Receiving
# =====================================================================

func _on_packet(body: PackedByteArray) -> void:
	var snapshot: Variant = bytes_to_var(body)
	if not (snapshot is Array) or (snapshot as Array).size() != NetWorld.SNAP_SIZE:
		return
	var epoch: int = snapshot[NetWorld.SNAP_EPOCH]
	var full: bool = int(snapshot[NetWorld.SNAP_FLAGS]) & NetWorld.FLAG_FULL != 0
	if epoch < _epoch:
		return  # the last stage's, overtaken
	if epoch > _epoch or full:
		if not full:
			return  # a world can only be joined from its start
		_epoch = epoch
		_buffer.clear()  # what's left of the old world is moot
		_templates.clear()
	var spawns: Array = snapshot[NetWorld.SNAP_SPAWNS]
	for spawn: Array in spawns:
		_templates[int(spawn[0])] = spawn[3]
	var decoded := {
		"time": float(snapshot[NetWorld.SNAP_TIME]),
		"full": full,
		"map": snapshot[NetWorld.SNAP_MAP],
		"spawns": spawns,
		"updates": NetWorld.read_updates(snapshot[NetWorld.SNAP_UPDATES], _templates),
		"removed": snapshot[NetWorld.SNAP_REMOVED],
		"tiles": snapshot[NetWorld.SNAP_TILES],
		"game": snapshot[NetWorld.SNAP_GAME],
		"events": snapshot[NetWorld.SNAP_EVENTS],
	}
	_buffer.append(decoded)
	# The host's clock is at least this far ahead of ours: the fastest packet
	# comes closest to the truth.
	var sample: float = decoded["time"] - Time.get_ticks_msec()
	if not _have_clock or sample > _clock_offset:
		_clock_offset = sample
		_have_clock = true


# =====================================================================
# Showing
# =====================================================================

func _process(delta: float) -> void:
	if not _have_clock:
		return
	_clock_offset -= CLOCK_SETTLE_MS * delta
	var render := Time.get_ticks_msec() + _clock_offset - DELAY_MS
	while not _buffer.is_empty():
		var next: Dictionary = _buffer[0]
		if next["time"] > render and _started and _buffer.size() <= MAX_BUFFERED:
			break
		_apply(_buffer.pop_front())
	_take_own_tanks()
	_glide(render)


## Moves everything to where it is at host time [param render]: between the
## snapshot shown and the next one.
func _glide(render: float) -> void:
	if _buffer.is_empty():
		return
	var next: Dictionary = _buffer[0]
	var span: float = next["time"] - _shown_time
	var weight := clampf((render - _shown_time) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var next_updates: Dictionary = next["updates"]
	for nid: int in _nodes:
		var node: Node = _nodes[nid]
		if not is_instance_valid(node):
			continue
		var state: Array = _states[nid]
		var change: Dictionary = next_updates.get(nid, {})
		var glides: Array = _glides.get(_types[nid], [])
		if change.has(0) or change.has(1):
			var from := Vector2(state[0], state[1])
			var to := Vector2(change.get(0, state[0]), change.get(1, state[1]))
			if span > 0.0 and _own_shells.has(nid):
				_own_shells[nid]["velocity"] = (to - from) * 1000.0 / span
			_place(nid, node as Node2D, from.lerp(to, weight))
		if not glides.is_empty():
			var shown := state.duplicate()
			var moved := false
			for i: int in glides:
				if change.has(i):
					shown[i] = lerpf(float(state[i]), float(change[i]), weight)
					moved = true
			if moved:
				node.net_apply(shown)
	# The stage screens' clock, unless the next snapshot starts a new screen.
	if overlay and _game.has(NetWorld.G_OVERLAY_T):
		var next_game: Dictionary = next["game"]
		if next_game.has(NetWorld.G_OVERLAY_T) and not next_game.has(NetWorld.G_OVERLAY):
			overlay.net_set_time(lerpf(float(_game[NetWorld.G_OVERLAY_T]),
					float(next_game[NetWorld.G_OVERLAY_T]), weight))


func _apply(snapshot: Dictionary) -> void:
	_shown_time = snapshot["time"]
	if snapshot["full"]:
		_clear()
		if level_manager:
			level_manager.net_load_map(snapshot["map"])
		_started = true
	for spawn: Array in snapshot["spawns"]:
		_spawn(int(spawn[0]), int(spawn[1]), spawn[2], spawn[3])
	var updates: Dictionary = snapshot["updates"]
	for nid: int in updates:
		var state: Variant = _states.get(nid)
		if state == null:
			continue
		var change: Dictionary = updates[nid]
		for i: int in change:
			state[i] = change[i]
		var node: Node = _nodes.get(nid)
		if is_instance_valid(node):
			_place(nid, node as Node2D, Vector2(state[0], state[1]))
			node.net_apply(state)
	for nid: int in snapshot["removed"]:
		_despawn(nid)
	var tiles: PackedInt32Array = snapshot["tiles"]
	if level_manager:
		for i in range(0, tiles.size() - 4, 5):
			level_manager.net_set_cell(Vector2i(tiles[i], tiles[i + 1]), tiles[i + 2], tiles[i + 3], tiles[i + 4])
	_apply_game(snapshot["game"])
	for event: Array in snapshot["events"]:
		_play(event)


func _spawn(nid: int, type: int, args: Array, state: Array) -> void:
	_despawn(nid)  # an id the host reused
	var info: Array = NetWorld.TYPES.get(type, [])
	if info.is_empty():
		return
	var parent: Node = containers.get(info[1])
	if parent == null:
		return
	var resource: Variant = _scenes.get(info[0])
	if resource == null:
		resource = load(info[0])
		_scenes[info[0]] = resource
	var node: Node = resource.instantiate() if resource is PackedScene else resource.new()
	node.net_setup(args)
	parent.add_child(node)
	_strip_physics(node)
	var shown := state.duplicate()
	_states[nid] = shown
	_types[nid] = type
	_nodes[nid] = node
	var shell := node as Bullet
	if shell and shell.owner_player >= 0 and Net.is_my_seat(shell.owner_player):
		_own_shells[nid] = {"velocity": shell.direction * shell.speed, "start": Vector2(state[0], state[1]),
				"range": shell.max_range, "pierces": shell.pierces}
	_place(nid, node as Node2D, Vector2(state[0], state[1]))
	if not _glides.has(type):
		var glides: Variant = node.get(&"NET_GLIDES")
		_glides[type] = glides if glides is Array else []
	node.net_apply(shown)


func _despawn(nid: int) -> void:
	var node: Node = _nodes.get(nid)
	if is_instance_valid(node):
		node.queue_free()
	_nodes.erase(nid)
	_states.erase(nid)
	_types.erase(nid)
	_own_shells.erase(nid)


func _clear() -> void:
	for nid: int in _nodes.keys():
		_despawn(nid)
	_game.clear()


## Puts [param node], showing [param nid], at [param at]: where the host had it
## at the time shown. This machine's own tanks drive themselves, though, and
## its own shells are drawn ahead (_lead_shell).
func _place(nid: int, node: Node2D, at: Vector2) -> void:
	if node is PlayerTank and (node as PlayerTank).is_net_driving():
		return
	if _own_shells.has(nid):
		at = _lead_shell(nid, node, at)
	node.global_position = at


# =====================================================================
# Lag compensation (docs/network_design.md section 7)
# =====================================================================

## This machine's own tanks drive here at once (PlayerTank predicts them),
## each with the local controls in its seat; the others show the host's.
func _take_own_tanks() -> void:
	for node: Node in _nodes.values():
		if is_instance_valid(node) and node is PlayerTank:
			var tank := node as PlayerTank
			var key: int = PlayerInput.seats[tank.player_id]
			tank.set_net_predicted(Net.is_my_seat(tank.player_id), PlayerInput.controller_slot(key))


## A shell of this machine's own tank: that tank drives ahead of the world shown
## here, by the trip to the host and back and DELAY_MS, so the shell is drawn
## that far ahead on its way too, coming out of the barrel where the tank is
## now. One that would be past a wall, an enemy, the end of its range or the
## field by then is hidden: the host's word of its hit is on its way.
func _lead_shell(nid: int, shell: Node2D, at: Vector2) -> Vector2:
	var info: Dictionary = _own_shells[nid]
	var ahead: Vector2 = info["velocity"] * (Net.ping_ms + DELAY_MS) / 1000.0
	var clear := _shell_way_clear(shell as Bullet, at, at + ahead, info)
	shell.visible = clear
	return at + ahead if clear else at


## True if nothing stops [param shell] going from [param from] to [param to].
func _shell_way_clear(shell: Bullet, from: Vector2, to: Vector2, info: Dictionary) -> bool:
	if to.x < 144.0 or to.x > 1456.0 or to.y < 0.0 or to.y > 992.0:
		return false
	var reach: float = info["range"]
	if reach > 0.0 and to.distance_to(info["start"]) > reach:
		return false
	if shell == null:
		return true
	var direction := shell.direction
	var length := (to - from).dot(direction)
	if length <= 0.0:
		return true
	# Its lanes lie across its way as Bullet._check_tile_collision has them.
	var across := Vector2.RIGHT if direction.x == 0.0 else Vector2.DOWN
	var lanes: Array[float] = shell.collision_lane_offsets
	if level_manager and not info["pierces"]:
		var done := 0.0
		while done < length:
			done = minf(done + 8.0, length)
			for lane: float in lanes:
				var cell := level_manager.world_to_tile(from + direction * done + across * lane)
				var tile: Dictionary = level_manager._fg_tile_data.get(cell, {})
				if not tile.is_empty() and LevelData.is_solid_tile(LevelData.get_tile_category(int(tile.get("code", 0)))):
					return false
	var half := BaseTank.HITBOX_SIZE * 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var tank := node as BaseTank
		if tank == null or not tank.is_solid():
			continue
		var offset := tank.global_position - from
		var ahead := offset.dot(direction)
		for lane: float in lanes:
			if ahead > 0.0 and ahead - half < length and absf(offset.dot(across) - lane) < half:
				return false
	return true


## A shown entity touches nothing: no layers, no masks, no monitoring. It can't
## be hit, pick anything up or block anything; the host decides all that.
static func _strip_physics(node: Node) -> void:
	if node is CollisionObject2D:
		var body := node as CollisionObject2D
		body.collision_layer = 0
		body.collision_mask = 0
	if node is Area2D:
		node.set_deferred(&"monitoring", false)
		node.set_deferred(&"monitorable", false)
	for child in node.get_children():
		_strip_physics(child)


# =====================================================================
# The game state and the events
# =====================================================================

func _apply_game(changed: Dictionary) -> void:
	var gm := GameManager
	for key: String in changed:
		var value: Variant = changed[key]
		_game[key] = value
		match key:
			NetWorld.G_STAGE:
				gm.current_stage = int(value)
			NetWorld.G_PLAYED:
				gm.save_counter = int(value)
			NetWorld.G_ENEMIES:
				gm.enemies_remaining = int(value)
			NetWorld.G_DIFFICULTY:
				gm.difficulty = int(value)
			NetWorld.G_ACTIVE:
				_pair(gm.player_active, value, TYPE_BOOL)
			NetWorld.G_DISABLED:
				_pair(gm.player_disabled, value, TYPE_BOOL)
			NetWorld.G_LIVES:
				_pair(gm.player_lives, value, TYPE_INT)
			NetWorld.G_SCORES:
				_pair(gm.player_scores, value, TYPE_INT)
			NetWorld.G_SPEED:
				_pair(gm.player_speed_levels, value, TYPE_INT)
			NetWorld.G_WEAPON:
				_pair(gm.player_weapon_levels, value, TYPE_INT)
			NetWorld.G_WEAPON2:
				_pair(gm.player_secondary_weapon_types, value, TYPE_STRING)
			NetWorld.G_AMMO:
				_pair(gm.player_secondary_weapon_counts, value, TYPE_INT)
			NetWorld.G_HP:
				_pair(gm.player_hp, value, TYPE_INT)
			NetWorld.G_ADDONS:
				for i in 2:
					gm.player_addons[i] = Array(value[i]) if value is Array and value.size() == 2 else []
			NetWorld.G_CHAINS:
				_pair(gm._hit_chains, value, TYPE_INT)
			NetWorld.G_ENEMIES_FROZEN:
				gm.enemies_frozen = bool(value)
			NetWorld.G_PLAYERS_FROZEN:
				gm.players_frozen = bool(value)
			NetWorld.G_HOLD_LEFT:
				gm.players_freeze_timer = float(value)
			NetWorld.G_PAUSED:
				if game:
					game.net_set_host_paused(bool(value))
			NetWorld.G_SPEED_SCALE:
				Engine.time_scale = clampf(float(value), 0.5, 2.0)
			NetWorld.G_COUNTDOWN:
				if game:
					game.net_countdown = float(value)
			NetWorld.G_DEAD_TIMERS:
				if game and value is Array and value.size() == 2:
					game.net_dead_timers = [float(value[0]), float(value[1])]
			NetWorld.G_BASE_DEAD:
				if game and game.eagle:
					game.eagle.destroyed = bool(value)
			NetWorld.G_BASE_GUARD:
				if game and game.eagle:
					game.eagle.invincible = bool(value)
			NetWorld.G_OVERLAY:
				if overlay and value is Array:
					overlay.net_show(value)
			NetWorld.G_OVERLAY_T:
				if overlay:
					overlay.net_set_time(float(value))


## Writes the host's pair [param value] into the game's typed pair
## [param target] in place (a typed array can't take a plain one whole).
static func _pair(target: Array, value: Variant, type: int) -> void:
	if not (value is Array) or (value as Array).size() != 2:
		return
	for i in 2:
		target[i] = type_convert(value[i], type)


func _play(event: Array) -> void:
	if event.is_empty():
		return
	played[int(event[0])] = int(played.get(int(event[0]), 0)) + 1
	var args := event.slice(1)
	match int(event[0]):
		NetWorld.EV_SOUND:
			SoundManager.play_from_host(StringName(str(args[0])))
		NetWorld.EV_MUSIC:
			SoundManager.play_music_from_host(StringName(str(args[0])))
		NetWorld.EV_STOP_MUSIC:
			SoundManager.stop_music()
		NetWorld.EV_HIT:
			var frames: Array = []
			var duration := 0.0
			if str(args[0]) == "tank":
				frames = ThemeManager.get_tank_explode_frames()
				duration = ThemeManager.get_tank_explode_duration()
			else:
				frames = ThemeManager.get_hit_frames(str(args[0]))
				duration = ThemeManager.get_hit_duration()
			if not frames.is_empty() and effects:
				HitEffect.spawn(effects, Vector2(args[1], args[2]), frames, duration)
		NetWorld.EV_SPAWN_BURST:
			SpawnBurst.spawn_at(get_tree(), Vector2(args[0], args[1]))
		NetWorld.EV_EXPLOSION:
			if effects:
				var explosion: Node2D = preload("res://scenes/effects/explosion.tscn").instantiate()
				explosion.global_position = Vector2(args[0], args[1])
				explosion.scale = Vector2.ONE * float(args[2])
				effects.add_child(explosion)
		NetWorld.EV_BLAST:
			if effects:
				var blast := ExplosionBlast.new()
				blast.setup(int(args[2]), true, level_manager)
				blast.global_position = Vector2(args[0], args[1])
				effects.add_child(blast)
		NetWorld.EV_KILL_TEXT:
			if effects:
				KillText.spawn(effects, int(args[0]), int(args[1]), Vector2(args[2], args[3]))
		NetWorld.EV_PICKUP_TEXT:
			if effects:
				PickupText.spawn(effects, int(args[0]), Vector2(args[1], args[2]))
