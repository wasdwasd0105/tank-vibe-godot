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
## A shell of the enemies' shown meeting this machine's own tank by this much
## (px, on both axes) is a hit for sure (_show_own_hits): the host looks at what
## this machine shows to within a hair.
const SURE_HIT := 0.5
## The host's word of such a hit comes within the trip there and back and this
## long (ms) on its clock: a snapshot of a later moment still with that shell
## in it says it missed (_settle_guesses).
const HIT_WORD_MS := 150.0
## Shown further behind the host than this (the trip there and back and the
## smoothing), the host may not judge its hits by this screen (it looks back
## NetHostWorld.SEEN_KEEP_MS, less 100 ms): none shown at once.
const HIT_GUESS_MAX_LAG_MS := NetHostWorld.SEEN_KEEP_MS - 300.0
## A blast laid here at once has its walls settled by the host's word once its
## own picture has been shown this long (ms, the host's clock): its walls
## change on its WALL_FRAME, a snapshot or two later at most.
const BLAST_WALLS_MS := ExplosionBlast.WALL_FRAME * ExplosionBlast.FRAME_TIME * 1000.0 + 70.0
## An item sprayed out of an enemy one of this machine's own shots finished, or
## out of its own tank (the add-on a hit cost it), from this near where that
## tank was shown, is shown as the host's word of it comes (_show_own_drops).
const DROP_NEAR := 96.0
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
## Walls this machine's own shells broke here at once (predict_wall), till the
## host's word of those cells: a key, counting up -> the guess as above with
## "cells", [[cell, [bg, fg, standing quarters] as it was, as the guess left
## it, the snapshot shown then (_shown_arrival)]...] for "nid".
var _guessed_walls: Dictionary = {}
## The host's latest word of each map cell it has changed in this world, for
## putting back a wall guessed wrong here (_undo_cell): cell -> [bg, fg,
## standing quarters, the snapshot that said it (its count as it came)].
var _host_cells: Dictionary = {}
## Snapshots counted as they come (_on_packet), and the count of the one shown
## last (_apply).
var _arrivals := 0
var _shown_arrival := 0
var _walls_guessed := 0
## Items this machine's own tanks took here at once (predict_pickups), till the
## host's word: cookie instance id -> {"nid", "type", "at" where, "msec"}.
var _guessed_pickups: Dictionary = {}
## The enemies' shells shown ending on this machine's own tanks at once
## (_show_own_hits), till the host's word: shell instance id -> {"nid", "at"
## where, "way" it went, "lanes" it hits on, "style" its look, "until" the
## host's clock by which that word comes, "msec"}.
var _guessed_hits: Dictionary = {}
## Patches of fire laid here at once where a fire shell ended (predict_hit),
## till the host's fires for them come: {"fires" cell -> GroundFire, "msec",
## "came" once one of the host's has}, oldest first.
var _guessed_fires: Array = []
## Blasts laid here at once where an explosion shell ended (predict_hit), till
## the host's picture of each comes and its walls are settled: {"origin",
## "level", "msec", "t0" the host's clock as its picture came (-1 not yet),
## "walls" [[cell, its state before, after]...] it broke here}, oldest first.
var _predicted_blasts: Array = []
## Mines this machine's own tanks laid here at once (predict_mine), till the
## host's with their numbers come: {"node": Mine, "born": msec}, oldest first.
var _ghost_mines: Array = []
## What this machine's own play did to its own tanks and its players' numbers,
## shown here at once (a hit guessed, an item taken) till the host's word of it
## shows: {"tank", "player", "values" name -> value (own_value), "msec", and
## "hit" (the guessed hit's shell instance id, "expect" the host's health once
## its word has come) or "pickup" (the item's instance id)}, oldest first.
var _own_effects: Array = []
## Enemies this machine's own shells hit here and didn't finish, their flash
## and sound shown at once (_show_enemy_hit): "shot:enemy" -> msec.
var _hits_shown: Dictionary = {}


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
		_host_cells.clear()
	var spawns: Array = snapshot[NetWorld.SNAP_SPAWNS]
	for spawn: Array in spawns:
		_templates[int(spawn[0])] = spawn[3]
	_arrivals += 1
	var said: PackedInt32Array = snapshot[NetWorld.SNAP_TILES]
	for i in range(0, said.size() - 4, 5):
		_host_cells[Vector2i(said[i], said[i + 1])] = [said[i + 2], said[i + 3], said[i + 4], _arrivals]
	var decoded := {
		"arrival": _arrivals,
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
		_show_own_pickups(decoded)
		_show_own_drops(decoded)
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
	_settle_fires()
	_expire_guesses()
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
	if _started:
		_show_own_hits()
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
	# Its walls shown, it's the snapshot shown: not before, as a guess made above
	# (an own shell it brought or moved, drawn on into a wall) was made on the
	# walls as they were, and its word of them is newer than that guess.
	_shown_arrival = int(snapshot.get("arrival", _shown_arrival))
	_keep_guessed_walls(tiles)
	for key: int in _guessed_walls.keys():
		if int(_guessed_walls[key].get("caught_up", _shown_arrival + 1)) <= _shown_arrival:
			_guessed_walls.erase(key)  # its word shown
	_apply_game(snapshot["game"])
	for event: Array in snapshot["events"]:
		_play(event)
	_settle_blast_walls(snapshot)
	_settle_own_effects(snapshot)


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
	if node is GroundFire:
		_fire_came(node as GroundFire)
	elif node is Mine and (node as Mine).net_shot >= 0:
		_mine_came(node as Mine)


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
	for guess: Dictionary in _guessed_fires:
		for fire: Variant in guess["fires"].values():
			if is_instance_valid(fire):
				fire.queue_free()
	_guessed_fires.clear()
	for laid: Dictionary in _ghost_mines:
		if is_instance_valid(laid["node"]):
			laid["node"].queue_free()
	_ghost_mines.clear()
	_predicted_blasts.clear()
	_predicted_hits.clear()
	_own_hits.clear()
	_guessed_kills.clear()
	_guessed_clashes.clear()
	_guessed_walls.clear()
	_guessed_pickups.clear()
	_guessed_hits.clear()
	_own_effects.clear()
	_hits_shown.clear()
	_game.clear()


## Puts [param node], showing [param nid], at [param at]: where the host had it
## at the time shown. This machine's own tanks drive themselves, though, its
## own shells are drawn ahead (_lead_shell), and an item sprayed out goes by
## its own spray (Cookie.net_place).
func _place(nid: int, node: Node2D, at: Vector2) -> void:
	if node is PlayerTank and (node as PlayerTank).is_net_driving():
		return
	if _own_shells.has(nid):
		at = _lead_shell(nid, node, at)
	elif node is Cookie:
		at = (node as Cookie).net_place(at)
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
## (its cooldown came out a frame different, say); and mines laid here it
## didn't lay (predict_mine).
func _expire_ghosts() -> void:
	var limit := Net.ping_ms + _delay_ms + GHOST_GRACE_MS
	var now := Time.get_ticks_msec()
	while not _ghosts.is_empty() and now - int(_ghosts[0]["born"]) > limit:
		var ghost: Variant = _ghosts.pop_front()["node"]
		if is_instance_valid(ghost):
			ghost.queue_free()
	while not _ghost_mines.is_empty() and now - int(_ghost_mines[0]["born"]) > limit:
		var laid: Variant = _ghost_mines.pop_front()["node"]
		if is_instance_valid(laid):
			laid.queue_free()


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
		var before_walls := stop
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
		elif stop < before_walls:
			# A wall: broken here at once, as the host's shell will break it, and
			# the shell stays ended there (the wall it stopped on may be gone now).
			info["sticky"] = true
			if not info.get("walled", false):
				info["walled"] = true
				var end := from + direction * stop
				predict_wall(shell, Bullet.solid_tiles_at(level_manager, end, direction, tile_lanes), end)
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
## rule 6; a fire shell always goes): hidden at once, its end shown where it is,
## till the host's word settles it (_settle_guesses).
func clash(shell: Bullet, theirs: Bullet, damage: int, end: Vector2) -> void:
	if theirs.damage > damage and theirs.visual_style != "fire":
		return
	theirs.visible = false
	predict_hit(theirs, theirs.global_position)
	_guessed_clashes[theirs.get_instance_id()] = _guess(theirs, shell, end)


## A guess of what own [param shell], ending at [param end], did to
## [param target] (guess_kill, clash), for _settle_guesses.
func _guess(target: Node, shell: Bullet, end: Vector2) -> Dictionary:
	return {"nid": _nid_of(target), "owner": shell.owner_player, "shot": shell.net_shot, "end": end,
			"way": shell.direction, "msec": Time.get_ticks_msec()}


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
				var strip: Array[Vector2i] = []
				strip.assign(reached[key])
				pool = _drill_here(shell, strip, pool, origin + direction * done)
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


## Own [param shell] ends on [param tiles] here at [param end] (a wall, as
## Bullet._solid_tiles_touched has it): they break here at once as the host's
## shell will break them (Bullet.hit_tiles; the host judges its walls as it has
## them, which this machine shows), rather than a trip and the smoothing later.
## The host's word of those cells settles it, or they're put back as they were
## if its shell didn't get there (_settle_guesses).
func predict_wall(shell: Bullet, tiles: Array[Vector2i], end: Vector2) -> void:
	if level_manager == null or tiles.is_empty():
		return
	var before := tiles.map(func(cell: Vector2i) -> Array: return [cell, level_manager.net_cell(cell)])
	Bullet.hit_tiles(level_manager, tiles, shell.direction, shell.breaks_iron(), shell.wall_heat())
	_note_wall(shell, before, end)


## Own AP [param shell] at [param end] spends [param pool] on [param strip], the
## walls side by side across its way, breaking them here at once as the host's
## will (LevelManager.ap_drill_tiles), and the guess is kept as predict_wall's.
## Returns the pool left.
func _drill_here(shell: Bullet, strip: Array[Vector2i], pool: int, end: Vector2) -> int:
	var before := strip.map(func(cell: Vector2i) -> Array: return [cell, level_manager.net_cell(cell)])
	var left := level_manager.ap_drill_tiles(strip, pool, shell.direction)
	_note_wall(shell, before, end)
	return left


## Keeps the cells of [param before] ([cell, its state as it was]) that own
## [param shell], ending at [param end], has just changed here, as a guess
## (_guessed_walls).
func _note_wall(shell: Bullet, before: Array, end: Vector2) -> void:
	var changed := _changed_cells(before)
	if changed.is_empty():
		return
	_walls_guessed += 1
	_guessed_walls[_walls_guessed] = {"cells": changed, "owner": shell.owner_player, "shot": shell.net_shot,
			"end": end, "way": shell.direction, "msec": Time.get_ticks_msec()}


## This machine's own [param tank] drives onto items shown here: each is taken
## here at once, as the host's copy of the tank will take it on its way after it
## (PlayerTank._follow_client): gone, its name shown and its sound heard, rather
## than a trip and the smoothing later. What it does (a level, a score) still
## comes with the host's word, and one still flying out of a tank is left to
## the host. The host's word settles it (_show_own_pickups), or it shows again.
func predict_pickups(tank: PlayerTank) -> void:
	var reach := Cookie.S * 0.5 + BaseTank.HITBOX_SIZE * 0.5
	for nid: int in _nodes:
		var node: Variant = _nodes[nid]
		if not is_instance_valid(node) or not node is Cookie:
			continue
		var cookie := node as Cookie
		if not cookie.visible or cookie.scale.x < 0.99 or _guessed_pickups.has(cookie.get_instance_id()):
			continue
		var off := cookie.global_position - tank.global_position
		if absf(off.x) >= reach or absf(off.y) >= reach:
			continue
		cookie.visible = false
		if effects:
			PickupText.spawn(effects, cookie.cookie_type, cookie.global_position)
		SoundManager.play_from_host(&"powerup_pickup")
		_guessed_pickups[cookie.get_instance_id()] = {"nid": nid, "type": cookie.cookie_type,
				"at": cookie.global_position, "msec": Time.get_ticks_msec()}
		_guess_pickup_effect(tank, cookie)


## What item [param cookie], taken here at once by own [param tank]
## (predict_pickups), does to it and its player's numbers, as the host's
## Cookie._apply_effect will: shown at once (own_value) till the host's word of
## the item shows (_settle_own_effects), so its next shots and its driving go
## as they will there too; the host takes it where this machine had the tank
## (PlayerTank._take_items_where_reported), before those. A bomb's kills are
## shown at once (_guess_bomb); Hold Enemy and Flag On Guard are the host's to
## show.
func _guess_pickup_effect(tank: PlayerTank, cookie: Cookie) -> void:
	var p := tank.player_id
	var gm := GameManager
	var speed := int(gm.player_speed_levels[p])
	var weapon := int(gm.player_weapon_levels[p])
	var weapon2 := str(gm.player_secondary_weapon_types[p])
	var ammo := int(gm.player_secondary_weapon_counts[p])
	var health := tank.health
	var bits := _addon_bits_of(tank)
	var now := Time.get_ticks_msec()
	var values := {"invincible_until": now + int(PlayerTank.COOKIE_PICKUP_INVINCIBILITY * 1000.0)}
	var held: Dictionary = CookieData.WEAPON_DATA.get(weapon2, {})
	var types := CookieData.CookieType
	match cookie.cookie_type:
		types.SPEED_UP:
			values["speed"] = mini(speed + 1, 3)
		types.HP_UP:
			values["health"] = mini(health + 1, PlayerTank.MAX_HP)
		types.WEAPONS_UP:
			values["weapon"] = mini(weapon + 1, 3)
		types.STAR_UP:
			values["speed"] = mini(speed + 1, 3)
			values["health"] = mini(health + 1, PlayerTank.MAX_HP)
			values["weapon"] = mini(weapon + 1, 3)
		types.MAX_UP:
			values["speed"] = 3
			values["weapon"] = 3
			values["health"] = PlayerTank.MAX_HP
		types.ANTI_WATER_COOKIE, types.ANTI_ICE_COOKIE, types.MEMORY_SAVE_COOKIE:
			var addon: String = CookieData.ADDON_TO_COOKIE.find_key(cookie.cookie_type)
			values["addons"] = (bits & int(BaseTank.NET_ADDON_BITS["moon-shield"])) | int(BaseTank.NET_ADDON_BITS[addon])
		types.MOON_SHIELD_COOKIE:
			values["addons"] = bits | int(BaseTank.NET_ADDON_BITS["moon-shield"])
		types.SCORE_200, types.SCORE_500, types.SCORE_1000, types.SCORE_2000:
			var points: int = {types.SCORE_200: 200, types.SCORE_500: 500, types.SCORE_1000: 1000,
					types.SCORE_2000: 2000}[cookie.cookie_type]
			var score := int(gm.player_scores[p])
			values["score"] = score + points
			values["lives"] = int(gm.player_lives[p]) + gm.extra_lives_at(score + points) - gm.extra_lives_at(score)
		types.INVINCIBLE_HELMET:
			values["invincible_until"] = now + int(Cookie.HELMET_TIME * 1000.0)
			values["wreath_until"] = now + int((Cookie.HELMET_TIME - PlayerTank.WREATH_MIN_LEFT) * 1000.0)
		types.TANK_BOMB:
			_guess_bomb(tank)
		types.TANK_LIFE:
			values["lives"] = int(gm.player_lives[p]) + 1
		types.BULLETS_MAX:
			if not held.is_empty():
				values["ammo"] = int(held["max_count"])
		types.BULLET_REFILL:
			if not held.is_empty():
				values["ammo"] = mini(ammo + int(held["reload_count"]), int(held["max_count"]))
		types.RAPID_COOKIE, types.FIRE_COOKIE, types.AP_COOKIE, types.EXPLOSION_COOKIE, types.MINE_COOKIE:
			var kind: String = CookieData.WEAPON_TO_COOKIE.find_key(cookie.cookie_type)
			var data: Dictionary = CookieData.WEAPON_DATA[kind]
			if kind == weapon2:
				values["ammo"] = mini(ammo + int(data["reload_count"]), int(data["max_count"]))
			else:
				values["weapon2"] = kind
				values["ammo"] = int(data["reload_count"])
	_add_own_effect(tank, values, {"pickup": cookie.get_instance_id()})


## Own [param tank] took a bomb here at once: every enemy shown goes at once,
## as the host's EnemySpawner.destroy_all_enemies takes them all, its
## explosion and sound shown now; the host's word of each settles it as a kill
## guessed here (_show_own_kills, _settle_guesses), or, none come in
## GUESS_MAX_MS, it shows again.
func _guess_bomb(tank: PlayerTank) -> void:
	if Net.ping_ms + _delay_ms > GUESS_MAX_LAG_MS:
		return
	var now := Time.get_ticks_msec()
	var any := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyTank
		if enemy == null or enemy.net_gone or enemy.is_queued_for_deletion():
			continue
		var nid := _nid_of(enemy)
		if nid == 0:
			continue
		enemy.net_gone = true
		enemy.visible = false
		var at := enemy.global_position
		_play([NetWorld.EV_HIT, "tank", at.x, at.y] if not ThemeManager.get_tank_explode_frames().is_empty()
				else [NetWorld.EV_EXPLOSION, at.x, at.y, 2.0])
		_guessed_kills[enemy.get_instance_id()] = {"nid": nid, "owner": tank.player_id, "shot": -1,
				"end": at, "way": Vector2.ZERO, "msec": now}
		note_own_hit(enemy)
		any = true
	if any:
		SoundManager.play_from_host(&"tank_destroyed")


## A snapshot just come says items have gone. One this machine's own tank took
## here already (predict_pickups) goes for good now, and that snapshot's name
## and sound for it, shown and heard already, are left out.
func _show_own_pickups(snapshot: Dictionary) -> void:
	if _guessed_pickups.is_empty():
		return
	var left := PackedInt32Array()
	var events: Array = snapshot["events"]
	for nid: int in snapshot["removed"]:
		var node: Variant = _nodes.get(nid)
		var cookie: Cookie = node as Cookie if is_instance_valid(node) else null
		if cookie == null or not _guessed_pickups.has(cookie.get_instance_id()):
			left.append(nid)
			continue
		var pickup: Dictionary = _guessed_pickups[cookie.get_instance_id()]
		_guessed_pickups.erase(cookie.get_instance_id())
		# What it did, shown here at once, is the host's to show once this
		# snapshot is (_settle_own_effects).
		if not snapshot.has("settles"):
			snapshot["settles"] = []
		snapshot["settles"].append(cookie.get_instance_id())
		_despawn(nid)
		var named := false
		var heard := false
		var rest: Array = []
		for event: Array in events:
			var its := false
			match int(event[0]):
				NetWorld.EV_PICKUP_TEXT:
					its = not named and int(event[1]) == int(pickup["type"]) \
							and Vector2(event[2], event[3]).distance_to(pickup["at"]) <= KILL_NEAR
					named = named or its
				NetWorld.EV_SOUND:
					its = not heard and str(event[1]) == "powerup_pickup"
					heard = heard or its
			if not its:
				rest.append(event)
		events = rest
	snapshot["removed"] = left
	snapshot["events"] = events


## The enemies' shells shown here meeting this machine's own tanks. The host
## judges what hits those by what this machine shows (PlayerTank's
## _judge_reported_hits), so each hit shows at once, rather than a trip and the
## smoothing later: the shell ends there, its end's picture shown, and a hit the
## tank survives flashes it red with its sound (_guess_hit). Its damage, a fatal
## hit's explosion and the rumble come with the host's word, which settles it
## (_settle_guesses). Not a meeting by a hair (SURE_HIT), nor while shown
## further behind the host than it judges this screen's hits by
## (HIT_GUESS_MAX_LAG_MS).
func _show_own_hits() -> void:
	if Net.ping_ms + _delay_ms > HIT_GUESS_MAX_LAG_MS:
		return
	var shells := _shown_enemy_shells()
	if shells.is_empty():
		return
	for node: Variant in _nodes.values():
		if not is_instance_valid(node) or not node is PlayerTank or not (node as PlayerTank).is_net_driving():
			continue
		var tank := node as PlayerTank
		for theirs: Bullet in shells:
			if not theirs.visible:
				continue  # ended on the other tank of this machine's
			var reach := Bullet.box_half(theirs.direction, theirs.collision_lane_offsets) \
					+ Vector2.ONE * (BaseTank.HITBOX_SIZE * 0.5 - SURE_HIT)
			var off := tank.global_position - theirs.global_position
			if absf(off.x) < reach.x and absf(off.y) < reach.y:
				_guess_hit(tank, theirs)


## Shell [param theirs] of the enemies' ends on this machine's own
## [param tank] here at once (_show_own_hits): hidden, its end's picture shown
## (the host's, when it comes, isn't shown again: _seen_here), and if it's a hit
## the tank survives as shown here, its red flash and sound
## (PlayerTank.guess_hit_here): not on a moon shield's front, nor in a blink
## (the grace after a hit counted in this machine's frames, as the host counts
## it), nor a fatal one (the explosion is the host's word to show), nor an AP
## shell's (its pool left is the host's to know).
func _guess_hit(tank: PlayerTank, theirs: Bullet) -> void:
	theirs.visible = false
	predict_hit(theirs, theirs.global_position)
	_guessed_hits[theirs.get_instance_id()] = {"nid": _nid_of(theirs), "at": theirs.global_position,
			"way": theirs.direction, "lanes": theirs.collision_lane_offsets.duplicate(), "style": theirs.visual_style,
			"until": Time.get_ticks_msec() + _clock_offset + Net.ping_ms + HIT_WORD_MS, "msec": Time.get_ticks_msec()}
	var frame := Net.reported_frame(tank.net_slot)
	var invincible := tank.is_invincible and not tank.net_hit_grace_only
	if theirs.pierces or invincible or tank.in_guessed_grace(frame) \
			or (tank.has_moon_shield and theirs.direction.dot(tank.current_direction) < 0.0):
		return
	var damage := theirs.damage if theirs.visual_style == "explosion" else 1
	if damage < tank.health:
		tank.guess_hit_here(frame)
		_guess_hit_costs(tank, damage, theirs)


## What a hit shown here at once on own [param tank] costs it (_guess_hit), as
## the host's PlayerTank.take_hit will take it: [param damage] of its health
## and, unless it wears memory-save or flies, its moon shield, else its other
## add-on, else a speed step or a gun level by turns (_apply_hit_punishment;
## the host says whose turn, NET_HITS_ODD). Shown at once till the host's word
## of the hit shows (_settle_own_effects). The add-on's item, sprayed out on
## the host, comes with that word (_show_own_drops).
func _guess_hit_costs(tank: PlayerTank, damage: int, theirs: Bullet) -> void:
	var p := tank.player_id
	var values := {"health": tank.health - damage}
	if not tank.has_memory_save and not tank.is_flying:
		var bits := _addon_bits_of(tank)
		if tank.has_moon_shield:
			values["addons"] = bits & ~int(BaseTank.NET_ADDON_BITS["moon-shield"])
		elif not tank._current_utility_addon.is_empty():
			values["addons"] = bits & ~int(BaseTank.NET_ADDON_BITS.get(tank._current_utility_addon, 0))
		else:
			if tank.net_hits_odd:
				values["weapon"] = maxi(int(GameManager.player_weapon_levels[p]) - 1, 0)
			else:
				values["speed"] = maxi(int(GameManager.player_speed_levels[p]) - 1, 0)
			values["hits_odd"] = not tank.net_hits_odd
	# The host's word of it has come once its health for this tank is down by
	# this hit and those still awaited before it.
	var expect := _host_health(tank) - damage
	for effect: Dictionary in _own_effects:
		if effect["tank"] == tank and effect.has("hit"):
			expect -= int(effect["damage"])
	_add_own_effect(tank, values, {"hit": theirs.get_instance_id(), "damage": damage, "expect": expect})


## The add-on bits of what [param tank] wears as shown (BaseTank.NET_ADDON_BITS).
static func _addon_bits_of(tank: BaseTank) -> int:
	var bits := 0
	for addon_name: String in tank.get_addon_names():
		bits |= int(BaseTank.NET_ADDON_BITS.get(addon_name, 0))
	return bits


## The health the host's latest word gives own [param tank] (its state shown).
func _host_health(tank: PlayerTank) -> int:
	var state: Variant = _states.get(_nid_of(tank))
	return int(state[7]) if state is Array and (state as Array).size() > 7 else tank.health


## A shell of the enemies' shown ending on this machine's own tank here
## ([param hit], _guessed_hits) has gone from the host's world in
## [param snapshot]. The host may have had it end further on its way, waiting
## for this machine's word (Bullet._end_with): that end's picture never came on
## this screen, so it's left out.
func _drop_ends_past(hit: Dictionary, snapshot: Dictionary) -> void:
	var way: Vector2 = hit["way"]
	var across := Vector2(absf(way.y), absf(way.x))
	var span := 0.0
	for lane: float in hit["lanes"]:
		span = maxf(span, absf(lane))
	var rest: Array = []
	for event: Array in snapshot["events"]:
		var at := Vector2.INF
		match int(event[0]):
			NetWorld.EV_HIT:
				if str(event[1]) == str(hit["style"]):
					at = Vector2(event[2], event[3])
			NetWorld.EV_EXPLOSION:
				if is_equal_approx(float(event[3]), 1.0):
					at = Vector2(event[1], event[2])
		if at != Vector2.INF:
			var off: Vector2 = at - (hit["at"] as Vector2)
			if off.dot(way) > PREDICTED_HIT_NEAR and absf(off.dot(across)) <= span + 1.0:
				continue
		rest.append(event)
	snapshot["events"] = rest


## The host's entity number of [param node] shown here, or 0.
func _nid_of(node: Node) -> int:
	for key: int in _nodes:
		if _nodes[key] == node:
			return key
	return 0


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
	if enemy.is_invulnerable() or enemy.is_bullet_blocked(shell.direction):
		return false
	# One driving across the shot's way is where the host looks for it to within
	# a frame's driving; one standing or going along it is just where it's shown.
	var across := Vector2(absf(shell.direction.y), absf(shell.direction.x))
	var reach := Bullet.box_half(shell.direction, shell.collision_lane_offsets).dot(across) + BaseTank.HITBOX_SIZE * 0.5
	var sure := SURE_INSIDE if enemy.velocity != Vector2.ZERO and absf(enemy.current_direction.dot(across)) > 0.5 else 0.5
	if absf((enemy.global_position - end).dot(across)) > reach - sure:
		return false
	if damage < enemy.health:
		_show_enemy_hit(enemy, shell)
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


## Own [param shell] hit [param enemy] here and it lives on (guess_kill): its
## red flash and its sound at once, as the host's word will have them, which
## then aren't shown again (BaseTank._shown_flash; the host marks that sound as
## the shot's, SoundManager.SHOT_TAG). Once for each shot and enemy.
func _show_enemy_hit(enemy: EnemyTank, shell: Bullet) -> void:
	var now := Time.get_ticks_msec()
	for key: String in _hits_shown.keys():
		if now - int(_hits_shown[key]) > OWN_HIT_MS:
			_hits_shown.erase(key)
	var shot := shell.net_shot if shell.net_shot >= 0 else shell.get_instance_id()
	var key := "%d:%d" % [shot, enemy.get_instance_id()]
	if _hits_shown.has(key):
		return
	_hits_shown[key] = now
	enemy.guess_flash_here()
	SoundManager.play_predicted(&"tank_hit", SoundManager.SHOT_TAG + shell.owner_player)


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
## so does one with no word either way in GUESS_MAX_MS. So do the walls and
## items guessed here (predict_wall, predict_pickups), and the enemies' shells
## shown ending on this machine's own tanks (_show_own_hits): one gone is
## settled, one still there in a snapshot of a moment its word would have come
## by (or after GUESS_MAX_MS) flies on.
func _settle_guesses(snapshot: Dictionary) -> void:
	for id: int in _guessed_hits.keys():
		var hit: Dictionary = _guessed_hits[id]
		var shell := instance_from_id(id) as Bullet
		if shell == null or not _nodes.has(int(hit["nid"])) or int(hit["nid"]) in snapshot["removed"]:
			_guessed_hits.erase(id)  # gone, as guessed
			_drop_ends_past(hit, snapshot)
		elif float(snapshot["time"]) > float(hit["until"]) or Time.get_ticks_msec() - int(hit["msec"]) > GUESS_MAX_MS:
			_guessed_hits.erase(id)
			shell.visible = true
			guesses_undone += 1
			_drop_own_effects(func(effect: Dictionary) -> bool: return effect.get("hit", 0) == id)
	if not _guessed_walls.is_empty():
		for key: int in _guessed_walls.keys():
			var guess: Dictionary = _guessed_walls[key]
			if guess.has("caught_up"):
				continue  # (gone once the snapshot that caught up with it is shown: _apply)
			if guess["cells"].all(func(entry: Array) -> bool: return _host_caught_up(entry)):
				# The host's word of those cells: as guessed, or further. It stands
				# over older words till the snapshot bringing it is shown.
				guess["caught_up"] = int(snapshot["arrival"])
			elif _guess_wrong(guess, snapshot):
				_guessed_walls.erase(key)
				for entry: Array in guess["cells"]:
					_undo_cell(entry)
				guesses_undone += 1
	for id: int in _guessed_pickups.keys():
		var cookie := instance_from_id(id) as Node2D
		if cookie == null or not _nodes.has(int(_guessed_pickups[id]["nid"])):
			_guessed_pickups.erase(id)
		elif Time.get_ticks_msec() - int(_guessed_pickups[id]["msec"]) > GUESS_MAX_MS:
			_guessed_pickups.erase(id)
			cookie.visible = true
			guesses_undone += 1
			_drop_own_effects(func(effect: Dictionary) -> bool: return effect.get("pickup", 0) == id)
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
		if not snapshot.has("drop_near"):
			snapshot["drop_near"] = []
		snapshot["drop_near"].append(at)  # (what it drops shows now too: _show_own_drops)
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
	# What it leaves where it ends, as the host's Bullet._destroy leaves it.
	if shell.ignites_ground:
		_predict_fire(shell, at)
	if shell.explodes:
		_predict_blast(shell, at)


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


# =====================================================================
# What this machine's own play did to its own tanks, shown at once
# =====================================================================

## The value [param name] shows for this machine's own [param tank]: what its
## own play did to it, shown before the host's word of it (_own_effects, the
## newest that has it), else the host's [param host]. Names: "health",
## "addons" (BaseTank.NET_ADDON_BITS), "hits_odd" (PlayerTank.NET_HITS_ODD),
## "invincible_until" and "wreath_until" (msec), and its player's numbers
## "speed", "weapon", "weapon2", "ammo", "lives", "score" (_keep_own_numbers).
func own_value(tank: PlayerTank, name: String, host: Variant) -> Variant:
	for i in range(_own_effects.size() - 1, -1, -1):
		var effect: Dictionary = _own_effects[i]
		if effect["tank"] == tank and (effect["values"] as Dictionary).has(name):
			return effect["values"][name]
	return host


## Own [param tank] shows [param values] at once (own_value), till the host's
## word of what did it shows ([param keys]: "hit" or "pickup", see
## _own_effects).
func _add_own_effect(tank: PlayerTank, values: Dictionary, keys: Dictionary) -> void:
	var effect := {"tank": tank, "player": tank.player_id, "values": values, "msec": Time.get_ticks_msec()}
	effect.merge(keys)
	_own_effects.append(effect)
	_keep_own_numbers()
	_show_own_tank(tank)


## The effects [param done] says are done with (settled, wrong or too old) go:
## what they showed gives way to the host's word.
func _drop_own_effects(done: Callable) -> void:
	var tanks: Array = []
	for effect: Dictionary in _own_effects.duplicate():
		if done.call(effect):
			_own_effects.erase(effect)
			if effect["tank"] not in tanks:
				tanks.append(effect["tank"])
	if tanks.is_empty():
		return
	# The host's numbers as last heard, then what's still shown over them.
	for key: String in [NetWorld.G_LIVES, NetWorld.G_SCORES, NetWorld.G_SPEED, NetWorld.G_WEAPON,
			NetWorld.G_WEAPON2, NetWorld.G_AMMO]:
		if _game.has(key):
			_apply_game({key: _game[key]})
	_keep_own_numbers()
	for tank: Variant in tanks:
		if is_instance_valid(tank):
			_show_own_tank(tank)


## This machine's own players' numbers (GameManager) as its own play left them,
## over the host's, till its word comes (_own_effects, the newest last).
func _keep_own_numbers() -> void:
	var gm := GameManager
	for effect: Dictionary in _own_effects:
		var p: int = effect["player"]
		var values: Dictionary = effect["values"]
		for name: String in values:
			match name:
				"speed":
					gm.player_speed_levels[p] = int(values[name])
				"weapon":
					gm.player_weapon_levels[p] = int(values[name])
				"weapon2":
					gm.player_secondary_weapon_types[p] = str(values[name])
				"ammo":
					gm.player_secondary_weapon_counts[p] = int(values[name])
				"lives":
					gm.player_lives[p] = int(values[name])
				"score":
					gm.player_scores[p] = int(values[name])


## Own [param tank] shows the host's latest state of it again, with what its
## own play did over that (PlayerTank.net_apply asks own_value).
func _show_own_tank(tank: PlayerTank) -> void:
	var state: Variant = _states.get(_nid_of(tank))
	if state is Array:
		tank.net_apply(state)


## The host's word in [param snapshot], just shown: a hit guessed here on an own
## tank has come once its health for that tank is down to what the hit left it
## ("expect"); an item taken here once the snapshot that took it is shown
## ("settles", _show_own_pickups). Then what they did is the host's to show.
func _settle_own_effects(snapshot: Dictionary) -> void:
	if _own_effects.is_empty():
		return
	var settled: Array = snapshot.get("settles", [])
	_drop_own_effects(func(effect: Dictionary) -> bool:
		if not is_instance_valid(effect["tank"]):
			return true
		if effect.has("pickup"):
			return int(effect["pickup"]) in settled
		return effect.has("hit") and _host_health(effect["tank"]) <= int(effect["expect"]))


## Guesses with no word either way for too long go: what they showed gives way
## to the host's (own effects, blasts' walls, enemy hits' marks).
func _expire_guesses() -> void:
	var now := Time.get_ticks_msec()
	if not _own_effects.is_empty():
		_drop_own_effects(func(effect: Dictionary) -> bool:
			return now - int(effect["msec"]) > GUESS_MAX_MS + 500)
	for record: Dictionary in _predicted_blasts.duplicate():
		if now - int(record["msec"]) > GUESS_MAX_MS:
			_put_back_walls(record)
			_predicted_blasts.erase(record)


# =====================================================================
# The ends of shells shown at once: fire and blasts
# =====================================================================

## A fire shell's patch, laid here at once where [param shell] ended at
## [param at] (predict_hit), as the host's LevelManager.ignite_fire_patch will
## lay it: on each of its tiles that fire can lie on and its side's fire isn't
## shown on already (the host feeds that one instead), armed as the host's.
## The host's fire for a tile takes over from it as it comes (_fire_came); the
## rest of a patch the host's word brought goes then, all of one with no word in
## GUESS_MAX_MS (_settle_fires).
func _predict_fire(shell: Bullet, at: Vector2) -> void:
	var parent: Node = containers.get("terrain")
	if level_manager == null or parent == null:
		return
	var side := 1 if shell.is_player_bullet else 0
	var row := 3 if side > 0 else 2
	var burning := {}
	for node: Node in parent.get_children():
		var lit := node as GroundFire
		if lit and not lit.is_queued_for_deletion() and lit._current_row() == row:
			burning[level_manager.world_to_tile(lit.global_position)] = true
	var fires := {}
	for tile: Array in LevelManager.fire_patch_tiles(level_manager.fire_anchor(at)):
		var cell: Vector2i = tile[0]
		if burning.has(cell) or not level_manager.fire_can_lie(cell):
			continue
		var fire: GroundFire = GroundFire.new()
		fire.setup(null, cell, side, -1, shell.fire_level, 0.0, float(tile[1]), int(tile[2]))
		parent.add_child(fire)
		fire.remove_from_group(NetWorld.GROUP)
		fire.global_position = level_manager.tile_to_world(cell)
		fires[cell] = fire
	if not fires.is_empty():
		_guessed_fires.append({"fires": fires, "msec": Time.get_ticks_msec()})


## The host's [param fire] has come: one laid here at once on its tile
## (_predict_fire) gives way to it, as far into showing and burning, and the
## patch it was of is the host's to say now (_settle_fires).
func _fire_came(fire: GroundFire) -> void:
	if level_manager == null:
		return
	var cell := level_manager.world_to_tile(fire.global_position)
	for guess: Dictionary in _guessed_fires:
		var laid: Variant = guess["fires"].get(cell)
		if laid == null or not is_instance_valid(laid) or (laid as GroundFire)._current_row() != fire._current_row():
			continue
		fire.take_over_from(laid)
		laid.queue_free()
		guess["fires"].erase(cell)
		guess["came"] = true
		return


## Patches laid here at once that the host's word has spoken for (its fires
## lay all of a patch at once: tiles of it it didn't bring weren't), or not in
## GUESS_MAX_MS, go.
func _settle_fires() -> void:
	var now := Time.get_ticks_msec()
	for guess: Dictionary in _guessed_fires.duplicate():
		if guess.get("came", false) or now - int(guess["msec"]) > GUESS_MAX_MS:
			for laid: Variant in guess["fires"].values():
				if is_instance_valid(laid):
					laid.queue_free()
			_guessed_fires.erase(guess)


## An explosion shell's blast, laid here at once where [param shell] ended at
## [param at] (predict_hit), as the host's LevelManager.spawn_explosion_blast
## lays it: its picture now, and on its wall frame its walls broken here as the
## host's will break them (_blast_walls). The host's picture of it isn't shown
## again when it comes (_blast_seen_here).
func _predict_blast(shell: Bullet, at: Vector2) -> void:
	if level_manager == null or effects == null:
		return
	var blast := ExplosionBlast.new()
	blast.setup(shell.explosion_level, shell.is_player_bullet, level_manager)
	blast.origin = ExplosionBlast.grid_origin(at - level_manager.global_position, ExplosionBlast.SHELL_SIZE)
	var record := {"origin": blast.origin, "level": blast.level, "msec": Time.get_ticks_msec(), "t0": -1.0,
			"walls": []}
	blast.net_walls = func(gone_off: ExplosionBlast) -> void: _blast_walls(gone_off, record)
	effects.add_child(blast)
	_predicted_blasts.append(record)


## Blast [param blast], laid here at once, breaks its walls here on its wall
## frame, as the host's will on the same frame: kept in [param record] as they
## were, for its settling (_settle_blast_walls).
func _blast_walls(blast: ExplosionBlast, record: Dictionary) -> void:
	if not _predicted_blasts.has(record):
		return  # settled already: the host's word of its walls came first
	var before := blast.wall_cells().map(func(cell: Vector2i) -> Array: return [cell, level_manager.net_cell(cell)])
	blast.change_walls_here()
	record["walls"] = _changed_cells(before)


## True if the host's picture of a blast, [param level] at [param origin], was
## laid here at once already (_predict_blast): its own blast, off by a tile at
## most (it went off a little elsewhere on the host). That blast's walls are
## settled from then on (_settle_blast_walls).
func _blast_seen_here(origin: Vector2i, level: int) -> bool:
	for record: Dictionary in _predicted_blasts:
		if float(record["t0"]) >= 0.0 or int(record["level"]) != level:
			continue
		var off: Vector2i = origin - (record["origin"] as Vector2i)
		if absi(off.x) <= 1 and absi(off.y) <= 1:
			record["t0"] = _shown_time
			return true
	return false


## The blasts laid here at once whose pictures the host's word has brought:
## once [param snapshot], just shown, is of a moment their own blasts on the
## host have had time to break their walls by (BLAST_WALLS_MS), the walls they
## broke here are as the host's word says (_put_back_walls).
func _settle_blast_walls(snapshot: Dictionary) -> void:
	if _predicted_blasts.is_empty():
		return
	var time: float = snapshot["time"]
	for record: Dictionary in _predicted_blasts.duplicate():
		var t0: float = record["t0"]
		if t0 >= 0.0 and time >= t0 + BLAST_WALLS_MS:
			_put_back_walls(record)
			_predicted_blasts.erase(record)


## The walls blast [param record] broke here go back as the host's word has
## them (_undo_cell): those its own blast broke stay broken, the others are
## as they were.
func _put_back_walls(record: Dictionary) -> void:
	if level_manager == null:
		return
	for entry: Array in record["walls"]:
		if _undo_cell(entry):
			guesses_undone += 1


## The entries of [param before] ([cell, its state before]) whose cells a guess
## here has just changed, each as [cell, before, its state now, the snapshot
## shown now] (_undo_cell).
func _changed_cells(before: Array) -> Array:
	var changed: Array = []
	for entry: Array in before:
		var after: Array = level_manager.net_cell(entry[0])
		if after != entry[1]:
			changed.append([entry[0], entry[1], after, _shown_arrival])
	return changed


## How much wall a cell's [param state] ([bg, fg, standing quarters]) has:
## none 0, a brick its standing quarters, a hard brick 4 more than its points,
## iron and super steel more still. A wall only loses it (but the base's ring,
## built and taken away by the host).
static func _standing(state: Array) -> int:
	var code := int(state[1])
	if code == 0:
		return 0
	match LevelData.get_tile_category(code):
		LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
			var mask := int(state[2])
			return (mask & 1) + (mask >> 1 & 1) + (mask >> 2 & 1) + (mask >> 3 & 1)
		LevelData.TileCategory.HARD_BRICK:
			return 4 + LevelData.get_hard_brick_hp(code)
		LevelData.TileCategory.IRON_BLOCK, LevelData.TileCategory.SUPER_BLOCK:
			return 100
	return 0


## True if the host's word of cell [param entry] ([cell, before, after, the
## snapshot shown then]: a guess here) has caught up with that guess: a word of
## it not shown yet as the guess was made that leaves no more wall standing
## than the guess did. An older word (another shot's, before this one's) isn't.
func _host_caught_up(entry: Array) -> bool:
	var said: Variant = _host_cells.get(entry[0])
	return said != null and int(said[3]) > int(entry[3]) \
			and _standing([said[0], said[1], said[2]]) <= _standing(entry[2])


## The cells of [param tiles] (the host's word just shown) that guesses here
## still wait on show as the newest of those guessed them, where that leaves
## less wall standing than the host's word: an older word of the host's (a shot
## before this one's, the host's own) doesn't put back what this machine's own
## shot broke since (Sean, 2026-10-09: a block the guest broke came back).
func _keep_guessed_walls(tiles: PackedInt32Array) -> void:
	if level_manager == null or tiles.is_empty() or (_guessed_walls.is_empty() and _predicted_blasts.is_empty()):
		return
	var pending: Array = []  # [msec, entry], to go through oldest first
	for key: int in _guessed_walls:
		for entry: Array in _guessed_walls[key]["cells"]:
			pending.append([int(_guessed_walls[key]["msec"]), entry])
	for record: Dictionary in _predicted_blasts:
		for entry: Array in record["walls"]:
			pending.append([int(record["msec"]), entry])
	pending.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var newest := {}
	for each: Array in pending:
		newest[each[1][0]] = each[1][2]
	for i in range(0, tiles.size() - 4, 5):
		var cell := Vector2i(tiles[i], tiles[i + 1])
		if not newest.has(cell):
			continue
		var guessed: Array = newest[cell]
		if _standing(guessed) < _standing(level_manager.net_cell(cell)):
			level_manager.net_set_cell(cell, int(guessed[0]), int(guessed[1]), int(guessed[2]))


## Cell [param entry] ([cell, its state before a guess here, after it, the
## snapshot shown then]), the guess wrong, goes back: to the host's word of it,
## if one has come that wasn't shown yet as the guess was made (shown since or
## still to show); else as it was before the guess. Not if something changed it
## since (the host's word shown, a later guess): that stays. So a wall the host
## broke never comes back here (Sean, 2026-10-09: a block the guest broke came
## back on its screen, gone on the host's). True if it changed.
func _undo_cell(entry: Array) -> bool:
	var cell: Vector2i = entry[0]
	if level_manager == null or level_manager.net_cell(cell) != entry[2]:
		return false
	var back: Array = entry[1]
	var said: Variant = _host_cells.get(cell)
	if said != null and int(said[3]) > int(entry[3]):
		back = [said[0], said[1], said[2]]
	if back == entry[2]:
		return false
	level_manager.net_set_cell(cell, int(back[0]), int(back[1]), int(back[2]))
	return true


# =====================================================================
# Mines laid at once, and items sprayed out shown as the word comes
# =====================================================================

## This machine's own [param tank] lays a mine of [param level] here at once
## (PlayerTank._place_mine), where the host's LevelManager.try_place_mine will
## lay it from where this machine has the tank as it presses: the first free
## spot of the ring round it, as this machine shows the field. Numbered as a
## shot (Net.note_shot), the host told with the next input message: its mine
## with that number takes over from this one (_mine_came), or, none come, this
## one goes as a ghost shot does (_expire_ghosts). False if no spot is free.
func predict_mine(tank: PlayerTank, level: int) -> bool:
	var parent: Node = containers.get("terrain")
	if level_manager == null or parent == null:
		return false
	var taken := {}
	var points: Array[Vector2] = []
	for node: Node in parent.get_children():
		var mine := node as Mine
		if mine and not mine.is_queued_for_deletion():
			taken[level_manager.world_to_tile(mine.global_position) - Vector2i.ONE] = mine
			if mine.is_armed():
				points.append(mine.global_position + LevelManager.MINE_POINT_OFFSET)
	for group: String in ["players", "enemies"]:
		for node in get_tree().get_nodes_in_group(group):
			var other := node as BaseTank
			if other and not other.is_queued_for_deletion() and not other.net_gone and not other.is_materializing:
				points.append(other.global_position)
	if game and game.get(&"eagle"):
		points.append((game.eagle as Node2D).global_position)
	for key: String in ["powerups", "bullets"]:
		var holder: Node = containers.get(key)
		if holder:
			for child in holder.get_children():
				if child is Node2D and (child as Node2D).visible:
					points.append((child as Node2D).global_position)
	var cell := level_manager.mine_spot_for(tank.global_position, tank.current_direction,
			"anti-water" in tank.get_addon_names(), taken, points)
	if cell == LevelManager.NO_MINE_SPOT:
		return false
	var laid := Mine.new()
	laid.setup(cell, level, true, level_manager)
	laid.owner_id = tank.player_id
	laid.net_shot = Net.note_shot(tank.net_slot, 1, 1)
	parent.add_child(laid)
	laid.remove_from_group(NetWorld.GROUP)
	_strip_physics(laid)
	laid.global_position = level_manager.mine_center(cell)
	_ghost_mines.append({"node": laid, "born": Time.get_ticks_msec()})
	return true


## The host's mine [param mine] has come, numbered as one of this machine's own:
## the one laid here at once with that number gives way to it (or it lies where
## the host laid it, if elsewhere).
func _mine_came(mine: Mine) -> void:
	for i in _ghost_mines.size():
		var laid: Variant = _ghost_mines[i]["node"]
		if not is_instance_valid(laid) or (laid as Mine).net_shot != mine.net_shot:
			continue
		mine.take_over_from(laid)
		laid.queue_free()
		_ghost_mines.remove_at(i)
		return


## A snapshot just come: the items it brings sprayed out of an enemy one of this
## machine's own shots finished (_show_own_kills, "drop_near"), or out of its
## own tanks (the add-on a hit cost it), are shown now, sprayed out from here on
## (Cookie.net_setup), rather than when the snapshot's time comes, render_delay
## later: with the kill or the hit shown here already.
func _show_own_drops(snapshot: Dictionary) -> void:
	var near: Array = snapshot.get("drop_near", []).duplicate()
	for node: Variant in _nodes.values():
		if is_instance_valid(node) and node is PlayerTank and (node as PlayerTank).net_predicted:
			near.append((node as Node2D).global_position)
	if near.is_empty():
		return
	var rest: Array = []
	for spawn: Array in snapshot["spawns"]:
		var args: Array = spawn[2]
		if int(spawn[1]) == NetWorld.T_COOKIE and args.size() >= 7:
			var from := Vector2(args[1], args[2])
			if near.any(func(at: Vector2) -> bool: return at.distance_to(from) <= DROP_NEAR):
				_spawn(int(spawn[0]), int(spawn[1]), args, spawn[3])
				continue
		rest.append(spawn)
	snapshot["spawns"] = rest


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
	if not _own_effects.is_empty():
		_keep_own_numbers()  # (what its own play did still shows over these)


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
			if _blast_seen_here(Vector2i(int(args[0]), int(args[1])), int(args[2])):
				return  # this machine's own shell's blast, laid here as it ended
			if effects:
				var blast := ExplosionBlast.new()
				blast.setup(int(args[2]), true, level_manager)
				blast.origin = Vector2i(int(args[0]), int(args[1]))
				effects.add_child(blast)
		NetWorld.EV_KILL_TEXT:
			if effects:
				KillText.spawn(effects, int(args[0]), int(args[1]), Vector2(args[2], args[3]))
		NetWorld.EV_PICKUP_TEXT:
			if effects:
				PickupText.spawn(effects, int(args[0]), Vector2(args[1], args[2]))
