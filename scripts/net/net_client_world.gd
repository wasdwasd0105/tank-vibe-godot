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
## How finely an AP shell's way is worked out (ap_walk), px.
const AP_STEP := 4.0
## An enemy one of this machine's own shells reached (note_own_hit) that the
## host says has gone within this long is shown going at once
## (_show_own_kills); its explosion and score this close to where it was.
const OWN_HIT_MS := 1500.0
const KILL_NEAR := 32.0
## A kill or a clash guessed here (guess_kill, clash) that the host's word
## hasn't settled in this long, either way, shows what went again; as does one
## whose shell the host has seen this far past where it ended here. The host
## judges this machine's shots by what it shows, perhaps a frame off: a shot
## hits a tank driving across its way for sure only this far inside its sides.
const GUESS_MAX_MS := 1500.0
const GUESS_PAST := 12.0
const SURE_INSIDE := 4.0
## Shown further behind the host than this (the trip there and back and the
## smoothing), the host may not look back as far as this machine's screen
## (NetHostWorld.SEEN_KEEP_MS, less a shot held up there): no guess.
const GUESS_MAX_LAG_MS := 700.0
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
## Enemies this machine's own shells have reached here (note_own_hit):
## instance id -> msec.
var _own_hits: Dictionary = {}
## Kills guessed here from this machine's own shots (guess_kill), and the
## enemies' shells guessed gone meeting them (clash), till the host's word
## settles them: instance id -> {"nid", "owner" and "shot" (the shot's
## number), "end" where that shot ended here and "way" it went, "msec"}. How
## many turned out wrong, for tests.
var _guessed_kills: Dictionary = {}
var _guessed_clashes: Dictionary = {}
var guesses_undone := 0


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
	if _started and not full:
		_show_own_kills(decoded)
		_settle_guesses(decoded)
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
	Net.client_view_time = _view_time(render) if _started else 0.0
	_fly_own_shells()
	for id: int in _guessed_kills:
		var gone := instance_from_id(id) as Node2D
		if gone:
			gone.visible = false  # (whatever its state says meanwhile)


## The moment of the host's world shown here at host time [param render]: the
## snapshot shown, on towards the next as far as _glide takes it. The host
## judges this machine's own shots by it (Net.client_view_time).
func _view_time(render: float) -> float:
	if _buffer.is_empty() or float(_buffer[0]["time"]) <= _shown_time:
		return _shown_time
	return clampf(render, _shown_time, float(_buffer[0]["time"]))


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
	_own_hits.clear()
	_guessed_kills.clear()
	_guessed_clashes.clear()
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
	shell.net_origin = shell.global_position
	if shell.pierces:
		shell.net_walk = {"pool": shell.damage}
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
			info["looked"] = ((ghost as Node2D).global_position - left).dot(shell.direction)  # (as far as the ghost got)
			if shell.pierces and not ghost.net_walk.is_empty():
				info["walk"] = ghost.net_walk  # its drilling, worked out as far as the ghost went
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
	var direction := (shell as Bullet).direction
	# One that ended on a tank or a shell here stays ended there (that may be
	# shown gone before the host's word of this shell's end comes), unless the
	# host's shell is seen going on past it: then on it flies.
	if info.has("ended_at") and (at - info["ended_at"]).dot(direction) > 8.0:
		info.erase("ended_at")
	var stop := -1.0
	if not hidden and info.has("ended_at"):
		stop = maxf((info["ended_at"] - at).dot(direction), 0.0)
	elif not hidden:
		stop = _shell_stop(shell as Bullet, at, now, info)
		if stop >= 0.0 and not info.get("ended", false):
			info["ended"] = true
			predict_hit(shell as Bullet, at + direction * stop)  # its end, shown at once, where it stops
		elif stop < 0.0:
			info["ended"] = false  # (what stopped it has gone: on it flies)
		if stop >= 0.0 and info.get("sticky", false):
			info["ended_at"] = at + direction * stop
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
	if info["pierces"]:
		# An AP shell drills on through walls and tanks while its pool lasts.
		if not info.has("walk"):
			var level := int(GameManager.player_weapon_levels[clampi(shell.owner_player, 0, 1)])
			info["walk"] = {"pool": int(CookieData.get_weapon_fire_config("ap", level).get("damage", 8))}
		var start: Vector2 = info["start"]
		var drilled_to := ap_walk(shell, start, (to - start).dot(direction), info["walk"])
		if drilled_to >= 0.0:
			stop = minf(stop, maxf(drilled_to - (from - start).dot(direction), 0.0))
	elif length > 0.0:
		# The walls it reaches, as Bullet._solid_tiles_touched has them: its tile
		# lanes, where it is and a little ahead.
		var across := Vector2.RIGHT if direction.x == 0.0 else Vector2.DOWN
		var lanes: Array[float] = shell.collision_lane_offsets
		var tile_lanes: Array[float] = shell.tile_lane_offsets if not shell.tile_lane_offsets.is_empty() else lanes
		if level_manager and not info["pierces"]:
			var done := 0.0
			while done < minf(length, stop):
				done = minf(done + AP_STEP, length)
				for ahead: float in [0.0, 6.0]:
					for lane: float in tile_lanes:
						var cell := level_manager.world_to_tile(from + direction * (done + ahead) + across * lane)
						var tile: Dictionary = level_manager._fg_tile_data.get(cell, {})
						if not tile.is_empty() and LevelData.is_solid_tile(LevelData.get_tile_category(int(tile.get("code", 0)))):
							stop = minf(stop, done)
		# Then the enemies' shells and tanks it meets as shown here now, on the
		# way it has come since the last look (what it got past, it got past),
		# as the host judges it (Bullet._meet_as_seen): a wall first, then a
		# shell, then a tank, where more are at once.
		var start: Vector2 = info["start"]
		var looked := maxf(float(info.get("looked", -INF)) - (from - start).dot(direction), 0.0)
		info["looked"] = (to - start).dot(direction)
		var own_half := Bullet.box_half(direction, lanes)
		var met: Node2D = null
		var met_at := INF
		for theirs: Bullet in _shown_enemy_shells():
			var touch := _first_touch(from, direction, looked, length,
					own_half + Bullet.box_half(theirs.direction, theirs.collision_lane_offsets), theirs.global_position)
			if touch >= 0.0 and touch < met_at:
				met = theirs
				met_at = touch
		for node in get_tree().get_nodes_in_group("enemies"):
			var tank := node as BaseTank
			if tank == null or not tank.is_solid():
				continue
			var touch := _first_touch(from, direction, looked, length,
					own_half + Vector2.ONE * BaseTank.HITBOX_SIZE * 0.5, tank.global_position)
			if touch >= 0.0 and touch < met_at:
				met = tank
				met_at = touch
		info["sticky"] = met != null and met_at < stop
		if info["sticky"]:
			stop = met_at
			var end := from + direction * stop
			if met is Bullet:
				clash(shell, met as Bullet, shell.damage, end)
			else:
				note_own_hit(met)  # it stops on that one before anything else
				guess_kill(met as BaseTank, shell.tank_damage(), shell, end)
	return stop if stop < INF else -1.0


## How far along [param way] from [param from] a box first touches
## [param target] (within [param reach] of it on each axis: the two boxes' half
## sizes added), looking from [param looked] to [param length] along; -1 if it
## doesn't there.
static func _first_touch(from: Vector2, way: Vector2, looked: float, length: float, reach: Vector2,
		target: Vector2) -> float:
	var along_reach := reach.y if way.x == 0.0 else reach.x
	var across_reach := reach.x if way.x == 0.0 else reach.y
	var offset := target - from
	if absf(offset.dot(Vector2(absf(way.y), absf(way.x)))) >= across_reach:
		return -1.0
	var ahead := offset.dot(way)
	if ahead + along_reach <= looked or ahead - along_reach >= length:
		return -1.0
	return maxf(ahead - along_reach, looked)


## The enemies' shells shown here, those guessed gone (clash) aside.
func _shown_enemy_shells() -> Array[Bullet]:
	var out: Array[Bullet] = []
	for node: Variant in _nodes.values():
		if is_instance_valid(node) and node is Bullet and (node as Bullet).owner_player < 0 and (node as Bullet).visible:
			out.append(node as Bullet)
	return out


## The enemies' shell shown here that own [param shell], at [param at], is on,
## the nearest if more; null if none (a ghost's check, as the host judges it:
## Bullet.shells_touch).
func shell_met(shell: Bullet, at: Vector2) -> Bullet:
	var met: Bullet = null
	for theirs: Bullet in _shown_enemy_shells():
		if Bullet.shells_touch(at, shell.direction, shell.collision_lane_offsets,
				theirs.global_position, theirs.direction, theirs.collision_lane_offsets) \
				and (met == null or (theirs.global_position - met.global_position).dot(shell.direction) < 0.0):
			met = theirs
	return met


## Own [param shell], with [param damage] left, ends at [param end] or flies on
## (an AP shell with more), meeting the enemies' shell [param theirs] here as
## the host will have them meet: it judges this machine's shots by what this
## machine shows. Theirs goes too, unless it had more damage than that (Bullet's
## rule 6; a fire or explosion shell always goes): hidden at once, its end shown
## where it is, till the host's word settles it (_settle_guesses).
func clash(shell: Bullet, theirs: Bullet, damage: int, end: Vector2) -> void:
	if theirs.damage > damage and theirs.visual_style not in ["fire", "explosion"]:
		return
	theirs.visible = false
	predict_hit(theirs, theirs.global_position)
	_guessed_clashes[theirs.get_instance_id()] = _guess(theirs, shell, end)


## A guess of what own [param shell], ending at [param end], did to
## [param target] (guess_kill, clash), for _settle_guesses.
func _guess(target: Node, shell: Bullet, end: Vector2) -> Dictionary:
	var nid := 0
	for key: int in _nodes:
		if _nodes[key] == target:
			nid = key
			break
	return {"nid": nid, "owner": shell.owner_player, "shot": shell.net_shot, "end": end, "way": shell.direction,
			"msec": Time.get_ticks_msec()}


## How far an AP shell of this machine's own gets, drilling on as the host's
## does (Bullet._ap_hit_tank, LevelManager.ap_drill_tiles): from
## [param origin], its pool is spent on each strip of wall it reaches, on each
## of the enemies' shells it meets (rule 6) and on each enemy, from what this
## machine shows of them (a tank's health, its moon shield's front, super-steel
## stopping it), worked out as far as [param distance] along its way. The host
## judges it by what this machine shows (Bullet._meet_as_seen), so this is
## where it goes there too. [param walk] carries the pool left ("pool"), how
## far it's worked out ("done"), the strips, shells and tanks spent on
## already, and where it stopped ("stop"). Returns that, its distance from
## origin, or -1 while it drills on.
func ap_walk(shell: Bullet, origin: Vector2, distance: float, walk: Dictionary) -> float:
	if walk.has("stop"):
		return walk["stop"]
	var direction := shell.direction
	var across := Vector2.RIGHT if direction.x == 0.0 else Vector2.DOWN
	var on_rows := direction.x == 0.0  # its strips are rows of tiles going up or down
	var tile_lanes: Array[float] = shell.tile_lane_offsets if not shell.tile_lane_offsets.is_empty() else shell.collision_lane_offsets
	var done: float = walk.get("done", 0.0)
	var pool: int = walk.get("pool", 0)
	var strips: Dictionary = walk.get("strips", {})
	var shells: Dictionary = walk.get("shells", {})
	var tanks: Dictionary = walk.get("tanks", {})
	var stop := -1.0
	while done < distance and stop < 0.0:
		done = minf(done + AP_STEP, distance)
		var at := origin + direction * done
		# The walls it reaches (as Bullet._solid_tiles_touched), a strip at a time.
		if level_manager:
			var reached: Dictionary = {}
			for ahead: float in [0.0, 6.0]:
				for lane: float in tile_lanes:
					var cell := level_manager.world_to_tile(at + direction * ahead + across * lane)
					var tile: Dictionary = level_manager._fg_tile_data.get(cell, {})
					if tile.is_empty() or not LevelData.is_solid_tile(LevelData.get_tile_category(int(tile.get("code", 0)))):
						continue
					var key: int = cell.y if on_rows else cell.x
					if not strips.has(key):
						if not reached.has(key):
							reached[key] = []
						reached[key].append(cell)
			var keys := reached.keys()
			keys.sort()
			if (direction.y if on_rows else direction.x) < 0.0:
				keys.reverse()
			for key: int in keys:
				strips[key] = true
				var cost := level_manager.ap_strip_cost(reached[key])
				pool = 0 if cost < 0 else pool - cost
				if pool <= 0:
					stop = done
					break
		if stop >= 0.0:
			break
		# The enemies' shells it meets: each takes the other's damage.
		for theirs: Bullet in _shown_enemy_shells():
			if shells.has(theirs.get_instance_id()) or not Bullet.shells_touch(at, direction, shell.collision_lane_offsets,
					theirs.global_position, theirs.direction, theirs.collision_lane_offsets):
				continue
			shells[theirs.get_instance_id()] = true
			clash(shell, theirs, pool, at)
			pool -= theirs.damage
			if pool <= 0:
				stop = done
				break
		if stop >= 0.0:
			break
		# The enemies it reaches (as Bullet._enemy_met).
		for node in get_tree().get_nodes_in_group("enemies"):
			var tank := node as BaseTank
			if tank == null or not tank.is_solid() or tanks.has(tank.get_instance_id()) \
					or not Bullet.touches_tank(at, direction, shell.collision_lane_offsets, tank.global_position):
				continue
			tanks[tank.get_instance_id()] = true
			note_own_hit(tank)
			if tank.is_bullet_blocked(direction):
				pool = 0
			else:
				guess_kill(tank, pool, shell, at)
				pool -= mini(pool, tank.health)
			if pool <= 0:
				stop = done
				break
	walk["done"] = done
	walk["pool"] = pool
	walk["strips"] = strips
	walk["shells"] = shells
	walk["tanks"] = tanks
	if stop >= 0.0:
		walk["stop"] = stop
	return stop


## One of this machine's own shells reached enemy [param tank] here: if the
## host's word that it has gone comes soon (OWN_HIT_MS), it goes at once
## (_show_own_kills).
func note_own_hit(tank: Node) -> void:
	_own_hits[tank.get_instance_id()] = Time.get_ticks_msec()


## One of this machine's own shells, [param shell], ends at [param end] on
## enemy [param tank] here with [param damage] to deal. The host judges this
## machine's shots by what it shows (Bullet._meet_as_seen), so if that's all the
## health the tank has left, it's shown dying at once, its explosion and sound,
## rather than a trip and a frame later (Sean, 2026-10-06: "react locally
## first"); the host's word settles it (_show_own_kills, _settle_guesses). Not
## guessed, the host's word to say, when it can't be sure: a moon shield's front
## to the shot, a blink after an item, the shot not well inside the sides of
## one driving across its way (SURE_INSIDE), or this machine shown further
## behind the host than the host looks back (GUESS_MAX_LAG_MS). Returns true if
## shown.
func guess_kill(tank: BaseTank, damage: int, shell: Bullet, end: Vector2) -> bool:
	var enemy := tank as EnemyTank
	if enemy == null or enemy.net_gone:
		return false
	var guess := _guess(enemy, shell, end)
	if int(guess["nid"]) == 0:
		return false
	for snapshot: Dictionary in _buffer:
		if int(guess["nid"]) in snapshot["removed"]:
			# The host's word that it has gone has come already: shown now (once
			# this frame's going through what's shown is done), not a guess.
			note_own_hit(enemy)
			_show_heard_kills.call_deferred()
			return true
	if Net.ping_ms + _delay_ms > GUESS_MAX_LAG_MS:
		return false
	if enemy.is_invulnerable() or damage < enemy.health or enemy.is_bullet_blocked(shell.direction):
		return false
	# One driving across the shot's way is where the host looks for it to within
	# a frame's driving; one standing or going along it is just where it's shown.
	var across := Vector2(absf(shell.direction.y), absf(shell.direction.x))
	var reach := Bullet.box_half(shell.direction, shell.collision_lane_offsets).dot(across) + BaseTank.HITBOX_SIZE * 0.5
	var sure := SURE_INSIDE if enemy.velocity != Vector2.ZERO and absf(enemy.current_direction.dot(across)) > 0.5 else 0.5
	if absf((enemy.global_position - end).dot(across)) > reach - sure:
		return false
	enemy.net_gone = true
	enemy.visible = false
	var shown_at := enemy.global_position
	_play([NetWorld.EV_HIT, "tank", shown_at.x, shown_at.y] if not ThemeManager.get_tank_explode_frames().is_empty()
			else [NetWorld.EV_EXPLOSION, shown_at.x, shown_at.y, 2.0])
	SoundManager.play_from_host(&"tank_destroyed")
	_guessed_kills[enemy.get_instance_id()] = guess
	note_own_hit(enemy)
	return true


## The kills by this machine's own shells in the snapshots come but not shown
## yet, shown now (_show_own_kills).
func _show_heard_kills() -> void:
	for snapshot: Dictionary in _buffer:
		_show_own_kills(snapshot)


## The host's word on the kills and clashes guessed here (guess_kill, clash),
## in a snapshot just come. One whose tank or shell it has gone is settled
## (_show_own_kills took a tank). One still there shows again when the host's
## shell that was to finish it has gone, or has been seen past where it ended
## here (GUESS_PAST), or (never seen, gone at once) a later shot's has come;
## so does one with no word either way in GUESS_MAX_MS.
func _settle_guesses(snapshot: Dictionary) -> void:
	if _guessed_kills.is_empty() and _guessed_clashes.is_empty():
		return
	for guesses: Dictionary in [_guessed_kills, _guessed_clashes]:
		for id: int in guesses.keys():
			var target := instance_from_id(id) as Node2D
			var guess: Dictionary = guesses[id]
			if target == null or not _nodes.has(int(guess["nid"])) or int(guess["nid"]) in snapshot["removed"]:
				guesses.erase(id)  # gone, as guessed
			elif _guess_wrong(guess, snapshot):
				guesses.erase(id)
				if target is BaseTank:
					(target as BaseTank).net_gone = false
					target.visible = not (target as BaseTank).is_materializing
				else:
					target.visible = true
				guesses_undone += 1


## True if the snapshot just come says [param guess] (see _guessed_kills) was
## wrong: the host's shell for that shot gone, or seen past where it ended here
## (on this machine's own line, so it goes where it went here), or never seen
## while a later shot's has been; or no word either way in GUESS_MAX_MS.
func _guess_wrong(guess: Dictionary, snapshot: Dictionary) -> bool:
	var wrong := Time.get_ticks_msec() - int(guess["msec"]) > GUESS_MAX_MS
	var shot := int(guess["shot"])
	var found := false
	var later := false
	var removed := Array(snapshot["removed"])
	var updates: Dictionary = snapshot["updates"]
	for nid: int in _own_shells:
		var shell := _nodes.get(nid) as Bullet
		if shell == null or shell.owner_player != int(guess["owner"]):
			continue
		if shell.net_shot >> 8 == shot >> 8 and (shell.net_shot - shot) & 0xff in range(1, 128):
			later = true
		if shell.net_shot != shot:
			continue
		found = true
		if nid in removed:
			wrong = true  # its shell gone, what it was to finish not
		elif updates.has(nid) and _own_shells[nid].has("born"):
			var state: Array = _states[nid]
			var change: Dictionary = updates[nid]
			var now_at := Vector2(change.get(0, state[0]), change.get(1, state[1]))
			wrong = wrong or (now_at - (guess["end"] as Vector2)).dot(guess["way"]) > GUESS_PAST  # on past it
	return wrong or (later and not found)


## A snapshot just come says enemies have gone. One that this machine's own
## shells reached (note_own_hit) goes at once, with its explosion, its score
## and its sound from that snapshot, rather than when the snapshot's time
## comes, render_delay later: so its own shots land as soon as the host's
## word of them can. The snapshot, shown in its time, leaves them out. It's
## the host's word, so nothing shows that didn't happen: the tank just goes
## a little before the rest of the world shown here gets there.
func _show_own_kills(snapshot: Dictionary) -> void:
	if _own_hits.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id: int in _own_hits.keys():
		if now - int(_own_hits[id]) > OWN_HIT_MS:
			_own_hits.erase(id)
	var left := PackedInt32Array()
	var events: Array = snapshot["events"]
	for nid: int in snapshot["removed"]:
		var node: Variant = _nodes.get(nid)
		var tank: EnemyTank = node as EnemyTank if is_instance_valid(node) else null
		if tank == null or not _own_hits.has(tank.get_instance_id()):
			left.append(nid)
			continue
		_own_hits.erase(tank.get_instance_id())
		# A kill guessed here showed its explosion and sound already: only its score is news.
		var guessed := _guessed_kills.has(tank.get_instance_id())
		_guessed_kills.erase(tank.get_instance_id())
		var at := tank.global_position
		_despawn(nid)
		var heard := false
		var rest: Array = []
		for event: Array in events:
			var its := false
			var shown := false
			match int(event[0]):
				NetWorld.EV_HIT:
					its = str(event[1]) == "tank" and Vector2(event[2], event[3]).distance_to(at) <= KILL_NEAR
					shown = guessed
				NetWorld.EV_EXPLOSION:
					its = float(event[3]) > 1.0 and Vector2(event[1], event[2]).distance_to(at) <= KILL_NEAR
					shown = guessed
				NetWorld.EV_KILL_TEXT:
					its = Vector2(event[3], event[4]).distance_to(at) <= KILL_NEAR
				NetWorld.EV_SOUND:
					its = not heard and str(event[1]) == "tank_destroyed"
					heard = heard or its
					shown = guessed
			if its and not shown:
				_play(event)
			elif not its:
				rest.append(event)
		events = rest
	snapshot["removed"] = left
	snapshot["events"] = events


## The end of [param shell], a shell of this machine's own, seen here at
## [param at] (a ghost's, or one drawn ahead of the host's): shown at once as
## the host will show it (Bullet._destroy's look: its theme's hit picture, or
## the flash on each of its lanes), rather than a trip and the delay later.
## The host's picture of the same end, when it comes, isn't shown again
## (_seen_here).
func predict_hit(shell: Bullet, at: Vector2) -> void:
	if effects == null:
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
