class_name NetHostWorld
extends Node
## The host's side of a game scene's replication (NetWorld has the format).
## Thirty times a second it gathers every replicated entity, the map cells that
## changed, the game state and the events since, and sends each client what
## that client doesn't have yet: all of it to a client new to this world, only
## the changes to one already following it. It keeps the last second and a half
## of the tanks and shells it sent, so a client's own shots, and the enemies'
## shells reaching its own tank, are judged by what that client's screen showed
## (seen_at; Bullet._meet_as_seen, PlayerTank._judge_reported_hits).
##
## Flow control: a client that hasn't acknowledged the snapshots sent it in the
## last MAX_UNACKED sends, or whose connection still has MAX_PENDING bytes
## waiting, is skipped until it catches up, then gets one snapshot covering the
## gap. A slow link gets fewer, bigger snapshots, never a growing backlog.

## Physics frames (60 a second) per snapshot.
const SEND_EVERY := 2
const MAX_UNACKED := 15
const MAX_PENDING := 48 * 1024
## Sounds and effects that pile up for a stalled client beyond this are dropped:
## a client that far behind would only play them late.
const MAX_QUEUED_EVENTS := 256
## How long back the host keeps the tanks and shells it sent (seen_at), ms: a
## client's own shots, and what reaches its own tank, are judged by what its
## screen showed, and a screen can be that far behind (a trip, its smoothing, a
## shot held up here).
const SEEN_KEEP_MS := 1500.0
## What's kept of each (seen_at): a tank's [SEEN_TANK, where, facing, solid (it
## can be hit), its moon shield on, health, an enemy's, blinking (an item's
## invulnerability)], a shell's [SEEN_SHELL, where, way, collision lanes, a
## player's, damage, fire or explosion (it goes on meeting anything), its look
## (visual style), drills (AP)].
const SEEN_TANK := 0
const SEEN_SHELL := 1

## The host world now running, for the static recorders below.
static var active: NetHostWorld = null
static var _epochs := 0
## Snapshot numbers count on across worlds (stages), so a client's ack from the
## last stage never looks like it is ahead of, or far behind, this one.
static var _sequence := 0
## Every snapshot byte sent, for measuring (and a stats line one day).
static var bytes_sent := 0

var game: Node = null
var level_manager: LevelManager = null
var stage_overlay: StageOverlay = null

var epoch := 0
var _frame := 0
var _next_nid := 1
var _views: Dictionary = {}   # peer id -> ClientView
## The tanks and shells as each snapshot had them, oldest first, SEEN_KEEP_MS
## of them: [the snapshot's time (its SNAP_TIME), {instance id: what's kept}].
var _seen: Array = []
## Per client (peer id): the tanks and shells its screen shows gone at once,
## finished by its own shots or ended on its own tank, judged by what that
## screen showed (instance id -> the moment of this world from which they're
## gone there, the host's clock; 0 all along). Its later shots aren't judged to
## meet them, nor its tank to be hit by them.
var _gone_for: Dictionary = {}
var _seen_asked: Array = []
var _seen_answer: Array = []


## What one client holds of this world.
class ClientView:
	var states: Dictionary = {}   # nid -> state Array
	var game: Dictionary = {}     # game-state key -> value
	var tiles: Dictionary = {}    # changed cells (Vector2i -> true)
	var events: Array = []
	var full := true              # needs the whole world
	var last_seq := -1


func _init() -> void:
	name = "NetHostWorld"
	process_mode = Node.PROCESS_MODE_ALWAYS  # the pause goes out too


func setup(p_game: Node, p_level_manager: LevelManager, p_overlay: StageOverlay) -> void:
	game = p_game
	level_manager = p_level_manager
	stage_overlay = p_overlay


func _enter_tree() -> void:
	_epochs += 1
	epoch = _epochs
	active = self


func _exit_tree() -> void:
	if active == self:
		active = null


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame % SEND_EVERY != 0:
		return
	_sequence += 1
	_sync_views()
	if _views.is_empty():
		return
	var now := Time.get_ticks_msec()
	var entities := _gather()
	_keep_seen(now)
	var game_state := _game_state()
	for peer: int in _views:
		var view: ClientView = _views[peer]
		if not _ready_for(peer, view):
			continue
		var snapshot := _snapshot_for(view, entities, game_state, now)
		var body := var_to_bytes(snapshot)
		var packet := PackedByteArray()
		packet.resize(4)
		packet.encode_u32(0, _sequence)
		packet.append_array(body)
		Net.send_world(peer, packet)
		bytes_sent += packet.size()
		view.last_seq = _sequence


# =====================================================================
# Recorders: the game calls these; they do nothing without a host world.
# =====================================================================

## A one-shot event for every client: [param kind] is a NetWorld.EV_* and
## [param args] its values.
static func record(kind: int, args: Array = []) -> void:
	if active == null:
		return
	var event: Array = [kind]
	event.append_array(args)
	for view: ClientView in active._views.values():
		if view.events.size() < MAX_QUEUED_EVENTS:
			view.events.append(event)


## Map cell [param cell] changed.
static func mark_tile(cell: Vector2i) -> void:
	if active == null:
		return
	for view: ClientView in active._views.values():
		view.tiles[cell] = true


# =====================================================================
# Building snapshots
# =====================================================================

## A view per client in the session; one gone takes its view with it.
func _sync_views() -> void:
	var ids := Net.connected_client_ids()
	for peer: int in _views.keys():
		if peer not in ids:
			_views.erase(peer)
			_gone_for.erase(peer)
	for peer in ids:
		if not _views.has(peer):
			_views[peer] = ClientView.new()


func _ready_for(peer: int, view: ClientView) -> bool:
	if view.full:
		return true
	var acked: int = Net.acks.get(peer, -1)
	# Acks come from the client's clock of this world's numbers; one still on an
	# older world (or none yet) counts from the first snapshot sent it.
	if view.last_seq - acked > MAX_UNACKED:
		return false
	return Net.pending_bytes(peer) < MAX_PENDING


## Every replicated entity now: nid -> [type, spawn args, state].
func _gather() -> Dictionary:
	var out := {}
	for node: Node in get_tree().get_nodes_in_group(NetWorld.GROUP):
		if node.is_queued_for_deletion() or not node.is_inside_tree():
			continue
		var nid: int = node.get_meta(&"nid", 0)
		if nid == 0:
			nid = _new_nid(out)
			node.set_meta(&"nid", nid)
		out[nid] = [node.net_type(), node.net_spawn_args(), node.net_state()]
	return out


## Keeps the tanks and shells as the snapshot of [param now] has them, for
## seen_at, and lets go of those older than SEEN_KEEP_MS (all but one: a moment
## between it and the next is still worked out).
func _keep_seen(now: int) -> void:
	var kept := {}
	for node: Node in get_tree().get_nodes_in_group(NetWorld.GROUP):
		if node.is_queued_for_deletion() or not node.is_inside_tree():
			continue
		if node is BaseTank:
			var tank := node as BaseTank
			var enemy := tank as EnemyTank
			kept[tank.get_instance_id()] = [SEEN_TANK, tank.global_position, tank.current_direction, tank.is_solid(),
					enemy != null and enemy.has_moon_shield, tank.health, enemy != null,
					enemy != null and enemy.is_invulnerable()]
		elif node is Bullet:
			var shell := node as Bullet
			kept[shell.get_instance_id()] = [SEEN_SHELL, shell.global_position, shell.direction,
					shell.collision_lane_offsets, shell.is_player_bullet, shell.damage,
					shell.ignites_ground or shell.explodes, shell.visual_style, shell.pierces]
	_seen.append([float(now), kept])
	while _seen.size() > 2 and now - float(_seen[1][0]) > SEEN_KEEP_MS:
		_seen.pop_front()
	if _frame % 60 == 0:
		# What's finished that no snapshot kept has any more can't come up again.
		for peer: int in _gone_for:
			var gone: Dictionary = _gone_for[peer]
			for id: int in gone.keys():
				if not _seen.any(func(entry: Array) -> bool: return (entry[1] as Dictionary).has(id)):
					gone.erase(id)
	_seen_asked = []


## The tanks and shells as the screen of client [param peer] showed them at
## [param time] (the host's clock, ms; <= 0: as the newest snapshot had them),
## worked out as that client does between the two snapshots around it
## (NetClientWorld._glide: the places glide, the rest as the earlier one had it),
## less those its screen shows gone by then (mark_gone). Further back than what's
## kept, as the oldest had them. [[instance id, what's kept (SEEN_TANK,
## SEEN_SHELL)], ...].
func seen_at(time: float, peer: int) -> Array:
	var asked := [Engine.get_physics_frames(), time, peer, _seen.size()]
	if asked == _seen_asked:
		return _seen_answer
	var out: Array = []
	if not _seen.is_empty():
		var at := _seen.size() - 1
		if time > 0.0:
			at = 0
			for i in range(_seen.size() - 1, -1, -1):
				if float(_seen[i][0]) <= time:
					at = i
					break
		var before: Dictionary = _seen[at][1]
		var after: Dictionary = _seen[at + 1][1] if at + 1 < _seen.size() else {}
		var span: float = float(_seen[at + 1][0]) - float(_seen[at][0]) if at + 1 < _seen.size() else 0.0
		var weight := clampf((time - float(_seen[at][0])) / span, 0.0, 1.0) if span > 0.0 and time > 0.0 else 0.0
		var gone: Dictionary = _gone_for.get(peer, {})
		for id: int in before:
			if gone.has(id) and (time <= 0.0 or time >= float(gone[id])):
				continue
			var kept: Array = before[id]
			if after.has(id) and weight > 0.0:
				kept = kept.duplicate()
				kept[1] = (kept[1] as Vector2).lerp(after[id][1], weight)
			out.append([id, kept])
	_seen_asked = asked
	_seen_answer = out
	return out


## Client [param peer]'s screen shows tank or shell [param id] gone at once from
## the moment [param from] of this world (the host's clock; 0 all along): its
## own shot finished it, or it ended on its own tank, judged by what that screen
## showed. So its later shots don't meet it, nor does it hit its tank after.
func mark_gone(peer: int, id: int, from: float = 0.0) -> void:
	if not _gone_for.has(peer):
		_gone_for[peer] = {}
	_gone_for[peer][id] = minf(from, float(_gone_for[peer].get(id, from)))
	_seen_asked = []


## A fresh id: 16 bits, counting up, so one is not reused while a client could
## still hold the entity that had it.
func _new_nid(in_use: Dictionary) -> int:
	for i in 65535:
		var nid := _next_nid
		_next_nid = _next_nid % 65535 + 1
		if not in_use.has(nid):
			return nid
	return 1


func _snapshot_for(view: ClientView, entities: Dictionary, game_state: Dictionary, now: int) -> Array:
	var snapshot := []
	snapshot.resize(NetWorld.SNAP_SIZE)
	snapshot[NetWorld.SNAP_SEQ] = _sequence
	snapshot[NetWorld.SNAP_EPOCH] = epoch
	snapshot[NetWorld.SNAP_TIME] = now
	snapshot[NetWorld.SNAP_FLAGS] = 0
	if view.full:
		view.full = false
		view.states.clear()
		view.game.clear()
		view.tiles.clear()
		snapshot[NetWorld.SNAP_FLAGS] = NetWorld.FLAG_FULL
		snapshot[NetWorld.SNAP_MAP] = level_manager.net_map() if level_manager else []

	var spawns: Array = []
	var updates := StreamPeerBuffer.new()
	for nid: int in entities:
		var entry: Array = entities[nid]
		var state: Array = entry[2]
		if not view.states.has(nid):
			spawns.append([nid, entry[0], entry[1], state])
			view.states[nid] = state
		elif NetWorld.put_update(updates, nid, state, view.states[nid]):
			view.states[nid] = state
	var removed := PackedInt32Array()
	for nid: int in view.states.keys():
		if not entities.has(nid):
			removed.append(nid)
			view.states.erase(nid)
	snapshot[NetWorld.SNAP_SPAWNS] = spawns
	snapshot[NetWorld.SNAP_UPDATES] = updates.data_array
	snapshot[NetWorld.SNAP_REMOVED] = removed

	var tiles := PackedInt32Array()
	if level_manager:
		for cell: Vector2i in view.tiles:
			var values: Array = level_manager.net_cell(cell)
			tiles.append_array([cell.x, cell.y, values[0], values[1], values[2]])
	view.tiles.clear()
	snapshot[NetWorld.SNAP_TILES] = tiles

	var changed := {}
	for key: String in game_state:
		var value: Variant = game_state[key]
		if not view.game.has(key) or view.game[key] != value:
			changed[key] = value
			view.game[key] = value
	snapshot[NetWorld.SNAP_GAME] = changed

	snapshot[NetWorld.SNAP_EVENTS] = view.events
	view.events = []
	return snapshot


## What the HUD, the stage screens and the tanks' looks read from the game.
func _game_state() -> Dictionary:
	var gm := GameManager
	var state := {
		NetWorld.G_STAGE: gm.current_stage,
		NetWorld.G_PLAYED: gm.save_counter,
		NetWorld.G_ENEMIES: gm.enemies_remaining,
		NetWorld.G_ACTIVE: [gm.player_active[0], gm.player_active[1]],
		NetWorld.G_DISABLED: [gm.player_disabled[0], gm.player_disabled[1]],
		NetWorld.G_LIVES: [gm.player_lives[0], gm.player_lives[1]],
		NetWorld.G_SCORES: [gm.player_scores[0], gm.player_scores[1]],
		NetWorld.G_SPEED: [gm.player_speed_levels[0], gm.player_speed_levels[1]],
		NetWorld.G_WEAPON: [gm.player_weapon_levels[0], gm.player_weapon_levels[1]],
		NetWorld.G_WEAPON2: [gm.player_secondary_weapon_types[0], gm.player_secondary_weapon_types[1]],
		NetWorld.G_AMMO: [gm.player_secondary_weapon_counts[0], gm.player_secondary_weapon_counts[1]],
		NetWorld.G_HP: [gm.player_hp[0], gm.player_hp[1]],
		NetWorld.G_ADDONS: [gm.player_addons[0].duplicate(), gm.player_addons[1].duplicate()],
		NetWorld.G_CHAINS: [gm.get_hit_chain(0), gm.get_hit_chain(1)],
		NetWorld.G_DIFFICULTY: gm.difficulty,
		NetWorld.G_ENEMIES_FROZEN: gm.enemies_frozen,
		NetWorld.G_PLAYERS_FROZEN: gm.players_frozen,
		# Tenths: the frost's look changes at 3.75 s and 0.75 s left.
		NetWorld.G_HOLD_LEFT: snappedf(gm.players_freeze_timer, 0.05) if gm.players_frozen else 0.0,
		NetWorld.G_PAUSED: get_tree().paused,
		NetWorld.G_SPEED_SCALE: Engine.time_scale,
	}
	if game:
		state[NetWorld.G_COUNTDOWN] = snappedf(game.get_game_over_countdown(), 0.1)
		state[NetWorld.G_DEAD_TIMERS] = [snappedf(game.get_player_dead_timer(0), 0.5),
				snappedf(game.get_player_dead_timer(1), 0.5)]
		var eagle: BaseFlag = game.eagle
		if eagle:
			state[NetWorld.G_BASE_DEAD] = eagle.destroyed
			state[NetWorld.G_BASE_GUARD] = eagle.invincible
	if stage_overlay:
		state[NetWorld.G_OVERLAY] = stage_overlay.net_screen()
		state[NetWorld.G_OVERLAY_T] = stage_overlay.get_time()
	return state
