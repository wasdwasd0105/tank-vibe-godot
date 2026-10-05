class_name NetClientWorld
extends Node
## A client's side of the game scene: it shows the host's world and runs none
## of it (NetWorld has the format). Snapshots are buffered and shown a little
## behind the host's clock (render_delay), so that however the network bunches
## them up, each is shown on time and positions glide from one to the next. The
## entities are the game's own scenes, built in mirror mode: their logic stays
## off and they draw themselves from the host's state (net_setup, net_apply).
## This machine's own tanks and shots run ahead of that (lag compensation).

## How far behind the host's clock the world is shown, ms, until the snapshots'
## timing has been measured (then render_delay: SMOOTHING, AUTO by default).
const DELAY_MS := 100.0
## AUTO smoothing: the snapshots' spacing, plus how late nine in ten of the
## latest LATE_SAMPLES came, plus a frame to spare, within these bounds.
const LATE_SAMPLES := 60
const AUTO_SPARE_MS := 10.0
const AUTO_MIN_MS := 40.0
const AUTO_MAX_MS := 250.0
## How fast the delay goes after a new aim, ms per second: quickly up, so a
## stuttering connection is met before it shows, slowly down, unnoticed.
const DELAY_UP_RATE := 100.0
const DELAY_DOWN_RATE := 20.0
## A ghost of a shot the host's shell never took over within the trip there and
## back, the delay and this long was a shot the host didn't fire. (Each is
## numbered, and the host fires each one it can: so wait out a spike on the
## line rather than lose a shot that's on its way.)
const GHOST_GRACE_MS := 1000.0
## The host's shell taking over from a ghost eases from where the ghost was to
## its own place in this long.
const HANDOFF_MS := 150.0
## The end of a shell of this machine's own, shown here at once (predict_hit):
## the host's picture of it coming within the trip there and back, the delay
## and PREDICTED_HIT_MS, this close to it, isn't shown again.
const PREDICTED_HIT_MS := 500.0
const PREDICTED_HIT_NEAR := 28.0
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
var _delay_ms := DELAY_MS        # how far behind the host's clock it's shown now
var _late: Array[float] = []     # how late each recent snapshot came, ms, oldest first
var _started := false
var _scenes: Dictionary = {}     # path -> loaded scene or script
## How many of each event (NetWorld.EV_*) have played here, for tests.
var played: Dictionary = {}
## Shells of this machine's own tanks, drawn ahead (_lead_shell): nid ->
## {"start" where the host had it at "host_time", the snapshot that brought it,
## "range" how far it goes (<= 0 no end), "pierces" drills through walls; and
## from a ghost it took over, "offset" from its own place to the ghost's at
## "offset_at" msec, and "hidden" if the ghost had hit something; and, flying
## on the ghost's own line, "start" is where the ghost left, at "born" msec on
## this machine's clock, at "speed0"}.
var _own_shells: Dictionary = {}
## Shots of this machine's own tanks fired here at once (add_ghost), not yet
## taken over by the host's shells: {"node": Bullet, "born": msec, "start":
## where it left, "speed0": its speed then}, oldest first.
var _ghosts: Array = []
## Ends of this machine's own shells shown here at once (predict_hit), oldest
## first: [visual style, where, msec, whether its theme has its own picture].
var _predicted_hits: Array = []


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


## How far behind the host's clock the world is shown now, ms (SMOOTHING).
func render_delay() -> float:
	return _delay_ms


## The client world of [param tree]'s game, or null (not a client's).
static func of(tree: SceneTree) -> NetClientWorld:
	var game := tree.get_first_node_in_group("game")
	return game.get_node_or_null("NetClientWorld") as NetClientWorld if game else null


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
	# comes closest to the truth. The rest came that much later (AUTO smoothing).
	var sample: float = decoded["time"] - Time.get_ticks_msec()
	if not _have_clock or sample > _clock_offset:
		_clock_offset = sample
		_have_clock = true
	_late.append(_clock_offset - sample)
	if _late.size() > LATE_SAMPLES:
		_late.pop_front()


# =====================================================================
# Showing
# =====================================================================

func _process(delta: float) -> void:
	_expire_ghosts()
	if not _have_clock:
		return
	_clock_offset -= CLOCK_SETTLE_MS * delta
	var aim := _aimed_delay()
	_delay_ms = move_toward(_delay_ms, aim, (DELAY_UP_RATE if aim > _delay_ms else DELAY_DOWN_RATE) * delta)
	var render := Time.get_ticks_msec() + _clock_offset - _delay_ms
	while not _buffer.is_empty():
		var next: Dictionary = _buffer[0]
		if next["time"] > render and _started and _buffer.size() <= MAX_BUFFERED:
			break
		_apply(_buffer.pop_front())
	_take_own_tanks()
	_glide(render)
	_fly_own_shells()


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
		_own_shells[nid] = {"start": Vector2(state[0], state[1]), "host_time": _shown_time,
				"range": shell.max_range, "pierces": shell.pierces}
		_take_over_ghost(shell, _own_shells[nid])
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
	for ghost: Dictionary in _ghosts:
		if is_instance_valid(ghost["node"]):
			ghost["node"].queue_free()
	_ghosts.clear()
	_predicted_hits.clear()
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
## each with the local controls in its seat, unless its lag compensation is
## off; the others show the host's.
func _take_own_tanks() -> void:
	var compensating := InputSettings.get_lag_compensation()
	for node: Node in _nodes.values():
		if is_instance_valid(node) and node is PlayerTank:
			var tank := node as PlayerTank
			var key: int = PlayerInput.seats[tank.player_id]
			tank.set_net_predicted(compensating and Net.is_my_seat(tank.player_id), PlayerInput.controller_slot(key))


## How far behind the host's clock to show the world, ms: SMOOTHING's choice,
## or with AUTO as far as the snapshots' timing needs (auto_delay).
func _aimed_delay() -> float:
	var chosen := InputSettings.get_smoothing()
	if chosen > 0:
		return float(chosen)
	if _late.size() < LATE_SAMPLES / 2.0:
		return DELAY_MS  # not measured yet
	return auto_delay(_late, 1000.0 * NetHostWorld.SEND_EVERY / Engine.physics_ticks_per_second)


## AUTO smoothing for snapshots sent [param spacing] ms apart that came
## [param late] ms later than the fastest of them, each: the next snapshot must
## be in by the time the world shown gets to it, nine times in ten, with a frame
## to spare.
static func auto_delay(late: Array[float], spacing: float) -> float:
	var sorted := late.duplicate()
	sorted.sort()
	var most: float = sorted[int(sorted.size() * 0.9)] if not sorted.is_empty() else 0.0
	return clampf(spacing + most + AUTO_SPARE_MS, AUTO_MIN_MS, AUTO_MAX_MS)


## A shot of this machine's own tank, fired here at once (BaseTank._spawn_bullet
## on a client): drawn and flown here as a ghost (Bullet.net_ghost) until the
## host's shell for it shows and takes over (_take_over_ghost).
func add_ghost(shell: Bullet) -> void:
	var parent: Node = containers.get("bullets")
	if parent == null:
		shell.free()
		return
	shell.net_ghost = true
	shell.collision_layer = 0
	shell.collision_mask = 0
	parent.add_child(shell)
	_strip_physics(shell)
	_ghosts.append({"node": shell, "born": Time.get_ticks_msec(), "start": shell.global_position, "speed0": shell.speed})


## Ghosts the host's shells never took over in time: shots the host didn't fire
## (its cooldown came out a frame different, say).
func _expire_ghosts() -> void:
	var limit := Net.ping_ms + _delay_ms + GHOST_GRACE_MS
	var now := Time.get_ticks_msec()
	while not _ghosts.is_empty() and now - int(_ghosts[0]["born"]) > limit:
		var ghost: Variant = _ghosts.pop_front()["node"]
		if is_instance_valid(ghost):
			ghost.queue_free()


## The host's [param shell] for a shot of this machine's has come: the ghost
## with its number gives way to it (else, from a host that doesn't number them,
## the oldest of that player's with its look and way). The host fired it from
## where this machine had its tank, so it's on the ghost's own line: it flies on
## from there by this machine's own clock, as the ghost did, without a jump.
## Off that line (the host fired it from its copy), it eases from where the
## ghost was to its own place (HANDOFF_MS). If the ghost had hit something, the
## shell stays hidden till the host's word of the hit.
func _take_over_ghost(shell: Bullet, info: Dictionary) -> void:
	for i in _ghosts.size():
		var ghost: Variant = _ghosts[i]["node"]
		if not is_instance_valid(ghost) or ghost.owner_player != shell.owner_player:
			continue
		if shell.net_shot >= 0:
			if ghost.net_shot != shell.net_shot:
				continue
		elif ghost.visual_style != shell.visual_style or ghost.direction != shell.direction:
			continue
		var left: Vector2 = _ghosts[i]["start"]
		var across := Vector2(absf(shell.direction.y), absf(shell.direction.x))
		if ghost.direction == shell.direction and ((info["start"] - left) * across).length() < 1.0:
			info["start"] = left
			info["born"] = int(_ghosts[i]["born"])
			info["speed0"] = float(_ghosts[i]["speed0"])
		info["offset"] = (ghost as Node2D).global_position - _shell_now(shell, info)
		info["offset_at"] = Time.get_ticks_msec()
		info["hidden"] = not (ghost as Node2D).visible
		ghost.queue_free()
		_ghosts.remove_at(i)
		return


## How many shells of player [param player]'s are on their way as shown here,
## ghosts and all (of [param style] only, if given): its shots go as the host's
## will (PlayerTank._take_host_weapons).
func own_shells_in_flight(player: int, style: String = "") -> int:
	var count := 0
	var shells: Array = _ghosts.map(func(ghost: Dictionary) -> Variant: return ghost["node"])
	for nid: int in _own_shells:
		shells.append(_nodes.get(nid))
	for shell: Variant in shells:
		if is_instance_valid(shell) and shell.owner_player == player \
				and (style.is_empty() or shell.visual_style == style):
			count += 1
	return count


## A shell of this machine's own tank, shown here at [param at] as the host had
## it: that tank drives ahead of the world shown here, by the trip to the host
## and back and render_delay, so the shell is drawn where it is by then too
## (_shell_now), coming out of the barrel where the tank is now (and on from its
## ghost's place, _take_over_ghost). One that would be past a wall, an enemy,
## the end of its range or the field by then is hidden: the host's word of its
## hit is on its way.
func _lead_shell(nid: int, shell: Node2D, at: Vector2) -> Vector2:
	if not InputSettings.get_lag_compensation():
		shell.visible = true
		return at  # this machine shows the host's game as it is
	var info: Dictionary = _own_shells[nid]
	info["at"] = at
	var now := _shell_now(shell as Bullet, info)
	var hidden: bool = info.get("hidden", false)
	var stop := -1.0 if hidden else _shell_stop(shell as Bullet, at, now, info)
	if stop >= 0.0 and not hidden and not info.get("ended", false):
		info["ended"] = true  # its end, shown at once, where it stops
		predict_hit(shell as Bullet, at + (shell as Bullet).direction * stop)
	var clear := not hidden and stop < 0.0
	shell.visible = clear
	if not clear:
		return at
	var offset: Vector2 = info.get("offset", Vector2.ZERO)
	if offset != Vector2.ZERO:
		offset *= clampf(1.0 - (Time.get_ticks_msec() - int(info["offset_at"])) / HANDOFF_MS, 0.0, 1.0)
	return now + offset


## This machine's own shells fly on each frame, whether a snapshot moved them or
## not (_shell_now).
func _fly_own_shells() -> void:
	for nid: int in _own_shells:
		var node: Node = _nodes.get(nid)
		if is_instance_valid(node):
			_place(nid, node as Node2D, _own_shells[nid].get("at", (node as Node2D).global_position))


## Where own [param shell] is by now on this machine's clock, a trip to the host
## ahead of the host's own (as this machine's tanks are). One on its ghost's
## line: where the ghost left, on at its speed for the time since it left here,
## exactly as the ghost flew. Else from where the host had it at the snapshot
## that brought it, on at its speed for the time since, and the trip there and
## back. Worked out from its speed rather than from the snapshots' spacing,
## which the host's frames make uneven, so it flies on as smoothly as its ghost.
func _shell_now(shell: Bullet, info: Dictionary) -> Vector2:
	if info.has("born"):
		var flown := maxf(Time.get_ticks_msec() - float(info["born"]), 0.0) / 1000.0 * Engine.time_scale
		return info["start"] + shell.direction * Bullet.flight(info["speed0"], shell.accel, shell.max_speed, flown)
	var host_now := Time.get_ticks_msec() + _clock_offset
	var seconds := maxf(host_now - float(info["host_time"]) + Net.ping_ms, 0.0) / 1000.0 * Engine.time_scale
	return info["start"] + shell.direction * shell.distance_in(seconds)


## How far past [param from] own [param shell] stops on its way to
## [param to]: at a wall, an enemy, the end of its range or of the field; -1
## if nothing stops it.
func _shell_stop(shell: Bullet, from: Vector2, to: Vector2, info: Dictionary) -> float:
	var direction := shell.direction
	var length := (to - from).dot(direction)
	var stop := INF
	if to.x < 144.0 or to.x > 1456.0 or to.y < 0.0 or to.y > 992.0:
		var edge := 0.0
		if direction.x > 0.0:
			edge = 1456.0 - from.x
		elif direction.x < 0.0:
			edge = from.x - 144.0
		elif direction.y > 0.0:
			edge = 992.0 - from.y
		else:
			edge = from.y
		stop = maxf(edge, 0.0)
	var reach: float = info["range"]
	if reach > 0.0 and to.distance_to(info["start"]) > reach:
		stop = minf(stop, maxf(reach - (from - info["start"]).dot(direction), 0.0))
	if length > 0.0:
		# Its lanes lie across its way as Bullet._check_tile_collision has them.
		var across := Vector2.RIGHT if direction.x == 0.0 else Vector2.DOWN
		var lanes: Array[float] = shell.collision_lane_offsets
		if level_manager and not info["pierces"]:
			var done := 0.0
			while done < minf(length, stop):
				done = minf(done + 8.0, length)
				for lane: float in lanes:
					var cell := level_manager.world_to_tile(from + direction * done + across * lane)
					var tile: Dictionary = level_manager._fg_tile_data.get(cell, {})
					if not tile.is_empty() and LevelData.is_solid_tile(LevelData.get_tile_category(int(tile.get("code", 0)))):
						stop = minf(stop, done)
		var half := BaseTank.HITBOX_SIZE * 0.5
		for node in get_tree().get_nodes_in_group("enemies"):
			var tank := node as BaseTank
			if tank == null or not tank.is_solid():
				continue
			var offset := tank.global_position - from
			var ahead := offset.dot(direction)
			for lane: float in lanes:
				if ahead > 0.0 and ahead - half < length and absf(offset.dot(across) - lane) < half:
					stop = minf(stop, maxf(ahead - half, 0.0))
	return stop if stop < INF else -1.0


## The end of [param shell], a shell of this machine's own, seen here at
## [param at] (a ghost's, or one drawn ahead of the host's): shown at once as
## the host will show it (Bullet._destroy's look: its theme's hit picture, or
## the flash on each of its lanes), rather than a trip and the delay later.
## The host's picture of the same end, when it comes, isn't shown again
## (_seen_here). (An AP shell drills on through tanks: the host shows its end.)
func predict_hit(shell: Bullet, at: Vector2) -> void:
	if shell.pierces or effects == null:
		return
	var frames: Array = ThemeManager.get_hit_frames(shell.visual_style)
	if not frames.is_empty():
		HitEffect.spawn(effects, at, frames, ThemeManager.get_hit_duration())
	else:
		var across := Vector2.RIGHT if shell.direction.x == 0.0 else Vector2.DOWN
		for lane: float in shell.collision_lane_offsets:
			var flash: Node2D = preload("res://scenes/effects/explosion.tscn").instantiate()
			flash.global_position = at + across * lane
			effects.add_child(flash)
	_predicted_hits.append([shell.visual_style, at, Time.get_ticks_msec(), not frames.is_empty()])


## True if the host's picture of a shell's end at [param at] (its theme's,
## [param style]; "" the flash) was shown here already (predict_hit).
func _seen_here(style: String, at: Vector2) -> bool:
	var now := Time.get_ticks_msec()
	var wait := Net.ping_ms + _delay_ms + PREDICTED_HIT_MS
	while not _predicted_hits.is_empty() and now - int(_predicted_hits[0][2]) > wait:
		_predicted_hits.pop_front()
	for hit: Array in _predicted_hits:
		var themed: bool = hit[3]
		if themed != not style.is_empty() or (themed and hit[0] != style):
			continue
		if (hit[1] as Vector2).distance_to(at) <= PREDICTED_HIT_NEAR:
			return true
	return false


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
			SoundManager.play_from_host(StringName(str(args[0])), int(args[1]) if args.size() > 1 else -1)
		NetWorld.EV_MUSIC:
			SoundManager.play_music_from_host(StringName(str(args[0])))
		NetWorld.EV_STOP_MUSIC:
			SoundManager.stop_music()
		NetWorld.EV_HIT:
			if str(args[0]) != "tank" and _seen_here(str(args[0]), Vector2(args[1], args[2])):
				return  # this machine's own shell's end, shown here as it came
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
			if is_equal_approx(float(args[2]), 1.0) and _seen_here("", Vector2(args[0], args[1])):
				return  # this machine's own shell's end, shown here as it came
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
