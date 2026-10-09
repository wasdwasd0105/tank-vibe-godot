extends Node
## Online play (docs/network_design.md): one machine hosts and runs the game, and
## up to three clients join it, everything over one port, TCP or UDP as the host
## picks (a client finds out which by itself). Godot's high-level multiplayer
## carries it: SceneMultiplayer over a WebSocketMultiplayerPeer (TCP) or an
## ENetMultiplayerPeer (UDP). The handshake is SceneMultiplayer's
## authentication, control messages are RPCs on this node (the same path,
## /root/Net, on every machine) and the world's snapshots go as raw packets.
##
## The host keeps the session: who is connected, their names, which tank each
## may drive, and the seats (PlayerInput). A client sends its two local players'
## inputs and gets the host's screen, its world (for NetClientWorld) and its
## rumbles.

signal session_changed
## The session is over: [param reason] is one of the END_* codes.
signal session_ended(reason: String)
signal join_succeeded
signal join_failed(reason: String)
## Someone joined or left: shown as a line over the screen.
signal notice_posted(text: String)
## Host: [param tank]'s driver left, was kicked or lost the right to drive it.
signal seat_vacated(tank: int)
## This machine began hosting (host): a running game sets up its side of it.
signal hosting_started
## Client: the host plays on a map set this computer doesn't have, [param map]
## {"name", "hash", "size"}. A NetMapPrompt asks whether to download it.
signal map_offered(map: Dictionary)
## Client: a map download has [param received] of [param total] bytes.
signal map_progress(received: int, total: int)
## Client: a map download ended, saved as pool [param name], or failed ("") and
## [param error] says why.
signal map_download_finished(name: String, error: String)
## Host: client [param peer] timed its trip here and back again (peer_ping).
signal peer_ping_changed(peer: int)

enum Role { OFFLINE, HOST, CLIENT }
## How a host takes its players: TCP (a WebSocket) or UDP (ENet).
enum Transport { TCP, UDP }

## Bump when the messages change, or what either side makes of them: a host
## only lets in its own protocol.
const PROTOCOL := 10
const DEFAULT_PORT := 24680
## The most remote players a host lets in: four players in all.
const MAX_CLIENTS := 3
const NAME_MAX := 14
const DEFAULT_NAME := "PLAYER"
const CONNECT_TIMEOUT := 8.0
const AUTH_TIMEOUT := 5.0
## Each side says something at least this often, and gives up on the other
## after SILENCE_LIMIT of nothing.
const KEEPALIVE := 1.0
## How often a client times a trip to the host and back (ping_ms), and how
## many of the latest it goes by.
const PING_EVERY := 1.0
const PING_SAMPLES := 5
## The input message: the newest snapshot (4 bytes), each local player's
## controls (4 each), then each one's own tank as it drives here (12 each:
## flags, facing, last correction taken, the physics frame it was there (0-255,
## wrapping), x and y as 32-bit floats), then the shots each one's tank has
## fired here (3 each: a count per fire button, 0-255, wrapping; and the row
## the latest of each left from, 0 left to 2 right, two bits each), then the
## moment of the host's world this machine shows just now (4: the host's clock,
## ms; 0 none), which the host judges its shots by (NetHostWorld.seen_at).
const INPUT_SIZE := 46
const REPORT_AT := 12
const REPORT_SIZE := 12
const SHOTS_AT := 36
const SHOTS_SIZE := 3
const VIEW_AT := 42
## A report's flags: there is one (the tank drives here just now), it's moving,
## this machine runs its own tanks at all (its lag compensation on), and it's
## in the air (a mine threw it here: nothing meets it).
const REPORT_HAS := 1
const REPORT_MOVING := 2
const REPORT_PREDICTS := 4
const REPORT_FLYING := 8
## The client's word of what happened to its own tank there, decided there
## (lag compensation: PlayerTank, NetClientWorld.own_tank_step), after the
## input message it goes with: records of OWN_SIZE bytes, each [local slot,
## OWN_HIT or OWN_MINE, the physics frame of its tank's report then (0-255),
## the hit's points or the mine's level, OWN_* flags, the player whose fire or
## blast it was + 1 (0: the enemies' or nobody's), 2 unused, the mine's id
## (u32), where its tank was (two 32-bit floats), the mine's centre (two)].
const OWN_SIZE := 28
const OWN_HIT := 1
const OWN_MINE := 2
## A hit by fire; one by a mine-thrown tank's landing (its moon shield or
## another add-on, and the points, as an airborne tank takes them); a mine that
## slowed its tank; one that threw it, and tumbling which way.
const OWN_FIRE := 1
const OWN_LANDING := 2
const OWN_SLOWED := 4
const OWN_THROWN := 8
const OWN_SPIN_BACK := 16
## The most of them one message carries.
const OWN_MAX := 32
const SILENCE_LIMIT := 10.0
## A rejected or kicked client gets this long to read why before it's cut off.
const PARTING_DELAY := 0.5
## Big enough for a whole world (the map and every entity) in one go.
const BUFFER_SIZE := 1 << 20
## The names the host's PORT TYPE shows (Transport order).
const TRANSPORT_NAMES: Array[String] = ["TCP", "UDP"]
## UDP: ENet channels, the world's snapshots on one of their own so a big one
## never holds up a key press or a map piece behind it.
const UDP_CHANNELS := 2
const WORLD_CHANNEL := 1
## UDP: the connections ENet takes at once, more than the game's players, so a
## newcomer turned away still hears why.
const UDP_MAX_PEERS := 8
## Client: a TCP answer waits this long for the UDP try before the join turns to
## TCP, so a UDP host with something else on its TCP port isn't missed.
const TCP_SWITCH_DELAY := 0.4
## The random challenge a host with a password sends each newcomer, in bytes.
const NONCE_SIZE := 32
## A map set goes to a client that asks for it in pieces this big, one a frame
## while its connection has less than MAP_SEND_BACKLOG waiting, so the game's
## snapshots keep flowing. Bigger map files aren't sent at all.
const MAP_CHUNK := 32 * 1024
const MAP_SEND_BACKLOG := 128 * 1024
const MAX_MAP_SIZE := 8 * 1024 * 1024

const SCREEN_NONE := ""
const SCREEN_LOBBY := "lobby"
const SCREEN_GAME := "game"
const LOBBY_SCENE := "res://scenes/join_screen.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const ONLINE_SCENE := "res://scenes/online_screen.tscn"

## Why a session ended, or a join was refused. The screens show end_text().
const END_LEFT := "left"            # we left
const END_HOST_LEFT := "host_left"  # the host ended the game
const END_KICKED := "kicked"
const END_LOST := "lost"            # the connection dropped or went silent
const END_NO_HOST := "no_host"      # nothing answered at that address
const END_VERSION := "version"
const END_FULL := "full"
const END_LOCKED := "locked"
const END_BAD_NAME := "bad_name"
const END_NEED_PASSWORD := "need_password"    # the game has one, and we gave none
const END_WRONG_PASSWORD := "wrong_password"
const END_PORT := "port"            # hosting: the port is taken

const NOTICE_JOINED := "joined"
const NOTICE_LEFT := "left"

var role: Role = Role.OFFLINE
## This machine's player name, and the host's once joined.
var local_name := DEFAULT_NAME
var host_name := ""
var port := DEFAULT_PORT

## Everyone in the session, the host (peer 1) first:
## peer id -> {"name": String, "allow": [may drive P1, may drive P2]}.
var peers: Dictionary = {}
## Host: newcomers are turned away.
var lock_new := false
## Host: how many remote players it lets in, 1 to MAX_CLIENTS.
var max_clients := MAX_CLIENTS
## Host: the password newcomers must know ("" for none). It never goes over the
## wire: a newcomer answers a random challenge with it (_check_proof).
var _password := ""
## Host: newcomers that were sent a challenge and haven't answered yet:
## peer id -> {"name": String, "nonce": PackedByteArray}.
var _knocking: Dictionary = {}
## Client: the password of the game being joined, to answer its challenge with.
var _join_password := ""
## Where the host is: SCREEN_LOBBY or SCREEN_GAME (SCREEN_NONE before either).
var host_screen := SCREEN_NONE
## The lobby's lines the clients show: who has joined, loaded game.
var lobby := {"active": [false, false], "loaded": false}
## Why the last session ended, for the ONLINE screen (take_end_reason).
var _last_end_reason := ""

## Client: the host's snapshots waiting for the game view to take them.
var _world_packets: Array[PackedByteArray] = []
## Client: the game view that takes snapshots as they come (NetClientWorld).
var world_sink: Callable = Callable()
## Host: acks each client sent with its inputs, the latest snapshot it has.
var acks: Dictionary = {}

var _peer: MultiplayerPeer = null
## The session's transport: TCP or UDP.
var transport: Transport = Transport.TCP
## Client: finding out which transport the host takes. A plain TCP connection
## tries the port while the UDP join itself goes on beside it; the first to
## answer decides (_find_transport).
var _tcp_probe: StreamPeerTCP = null
var _udp_lost := false              # the UDP try gave up while the probe was out
var _tcp_answered_at := -1          # msec the probe got in, -1 not (yet)
var _join_target: Dictionary = {}   # {"address", "port"} of the join
var _mp: SceneMultiplayer = null
var _ending := false
var _end_reason := ""
var _connect_timer := 0.0
var _joined := false
var _last_heard: Dictionary = {}   # peer id -> Time.get_ticks_msec() of its last message
var _last_sent := 0                # msec we last said anything
var _session_dirty := false

# Client: the two local players' press counters, their tanks' shots fired here
# and the row of the latest per fire button (note_shot), and what was last sent.
var _presses: Array = [[0, 0], [0, 0]]
var _shots: Array = [[0, 0], [0, 0]]
var _shot_rows: Array = [[1, 1], [1, 1]]
var _sent_input := PackedByteArray()
## Client: the newest snapshot received, acknowledged with the next input
## message.
var _latest_snapshot := -1
## Client: while its own menu is open, it sends its players as idle.
var input_blocked := false
## Client: this machine's own tanks as they drive here, ahead of the host
## (lag compensation: PlayerTank predicts them), by local slot: {"position",
## "facing", "moving", "override", "frame"}, or {} for none. They go out with
## the inputs, and the host's copies follow them.
var _tank_reports: Array = [{}, {}]
## Client: what happened to this machine's own tanks here since the last input
## message (note_own_event), OWN_SIZE bytes each, to go out after it.
var _own_events := PackedByteArray()
## Client: the moment of the host's world shown here just now, on the host's
## clock (ms; NetClientWorld sets it each frame), or 0 while none is.
var client_view_time := 0.0
## Client: the trip to the host and back, ms: the middle one of the latest
## PING_SAMPLES (a stall here, as when a stage loads, is one bad trip), 0 until
## timed.
var ping_ms := 0.0
var _ping_timer := 0.0
var _ping_samples: Array[float] = []
## Tests: this client's line to the host is this many ms long each way
## ("--net-lag-ms=N"): its inputs and pings go out, and the host's world and
## answers come in, that much later; and each comes up to sim_jitter_ms later
## still, at random, never overtaking the one before, as over TCP
## ("--net-jitter-ms=N"). 0 normally.
var sim_lag_ms := 0
var sim_jitter_ms := 0
var _lagged: Array = []   # [due msec, Callable], oldest first
## Client: the same while the map question is on the screen (NetMapPrompt).
var map_prompt_open := false

## The map set the game is played on, as the host announced it: {"name",
## "hash", "size"}, or {} (none told).
var host_map: Dictionary = {}
## Client: map sets already asked about this session, by hash.
var _maps_asked: Dictionary = {}
## Client: the map set coming: {"name", "hash", "size", "bytes"}, or {}.
var _map_download: Dictionary = {}
## Host: map sets on their way: peer id -> {"hash", "bytes", "offset"}.
var _map_sends: Dictionary = {}


func _ready() -> void:
	# Messages, keepalives and the host's paused game all go on through a pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A client's input goes out after its own tank's step, so a press of fire
	# comes with where the tank was as it fired (PlayerTank._shot_origin).
	process_physics_priority = 100
	local_name = InputSettings.get_online_name()
	port = InputSettings.get_online_port()
	PlayerInput.seats_changed.connect(func() -> void:
		if role == Role.HOST:
			_session_dirty = true)
	var toasts := NetToasts.new()
	add_child(toasts)
	notice_posted.connect(toasts.show_notice)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net-lag-ms="):
			sim_lag_ms = maxi(int(arg.trim_prefix("--net-lag-ms=")), 0)
		elif arg.begins_with("--net-jitter-ms="):
			sim_jitter_ms = maxi(int(arg.trim_prefix("--net-jitter-ms=")), 0)


func _notification(what: int) -> void:
	# Closing the window: tell the others first, so they read why.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and role != Role.OFFLINE:
		_say_goodbye(END_HOST_LEFT if role == Role.HOST else END_LEFT)
		_flush(0.2)


# =====================================================================
# State
# =====================================================================

func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


## True on a client: this machine shows the host's game and runs none of it.
func is_client() -> bool:
	return role == Role.CLIENT


## This machine's peer id: 1 for the host (and offline).
func my_id() -> int:
	return _mp.get_unique_id() if _mp != null and role == Role.CLIENT else 1


func peer_name(peer: int) -> String:
	return peers.get(peer, {}).get("name", "")


## True if [param peer] may drive tank [param tank].
func may_drive_peer(peer: int, tank: int) -> bool:
	var allow: Array = peers.get(peer, {}).get("allow", [false, false])
	return bool(allow[tank])


## PlayerInput.free_seat_for's rule: controller [param key] may take tank
## [param tank]. Offline anyone may.
func may_drive(key: int, tank: int) -> bool:
	if role == Role.OFFLINE:
		return true
	return may_drive_peer(PlayerInput.controller_peer(key), tank)


## The tank controller [param key] takes if it presses fire now (see
## PlayerInput.free_seat_for), or -1.
func free_seat_for(key: int) -> int:
	return PlayerInput.free_seat_for(key, may_drive)


## Who drives tank [param tank], for the screens: their name, "" for nobody.
## A machine's second local player shows as "NAME (2)".
func seat_label(tank: int) -> String:
	var key: int = PlayerInput.seats[tank]
	if key == PlayerInput.NO_SEAT:
		return ""
	var peer := PlayerInput.controller_peer(key)
	var name := peer_name(peer)
	if PlayerInput.controller_slot(key) == 1:
		name += " (2)"
	return name


## The seat [param tank] is driven from this machine.
func is_my_seat(tank: int) -> bool:
	var key: int = PlayerInput.seats[tank]
	return key != PlayerInput.NO_SEAT and PlayerInput.controller_peer(key) == my_id()


## This machine's IPv4 addresses on its networks, the private ones (a LAN's)
## first: what a host tells the others to type. Loopback and link-local are left
## out.
static func local_addresses() -> PackedStringArray:
	var private := PackedStringArray()
	var others := PackedStringArray()
	for address: String in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		var parts := address.split(".")
		var second := int(parts[1]) if parts.size() == 4 else -1
		if address.begins_with("192.168.") or address.begins_with("10.") \
				or (address.begins_with("172.") and second >= 16 and second <= 31):
			private.append(address)
		else:
			others.append(address)
	private.append_array(others)
	return private


## "ADDRESS : PORT" for the host to share, as the join screen takes it.
func share_address() -> String:
	var addresses := local_addresses()
	return "%s : %d" % [addresses[0] if not addresses.is_empty() else "127.0.0.1", port]


## The text a screen shows for an END_* reason.
static func end_text(reason: String) -> String:
	match reason:
		END_HOST_LEFT:
			return "The host has ended the game."
		END_KICKED:
			return "The host removed you from the game."
		END_LOST:
			return "The connection to the host was lost."
		END_NO_HOST:
			return "No game answered at that address."
		END_VERSION:
			return "The host is running a different version."
		END_FULL:
			return "That game is full."
		END_LOCKED:
			return "The host isn't letting new players in."
		END_BAD_NAME:
			return "Enter a name first."
		END_NEED_PASSWORD:
			return "This game needs a password."
		END_WRONG_PASSWORD:
			return "Wrong password."
		END_PORT:
			return "That port is in use. Try another."
	return ""


## An address as a player types it: "HOST", "HOST:PORT", "[IPV6]:PORT" or a
## bare IPv6 address, where HOST is an IP or a name. Returns [host, port]:
## DEFAULT_PORT when it gives none, 0 when the one it gives isn't a port.
static func split_address(text: String) -> Array:
	var address := text.strip_edges()
	var address_port := DEFAULT_PORT
	if address.begins_with("[") and address.contains("]"):
		var rest := address.get_slice("]", 1)
		address = address.get_slice("]", 0).trim_prefix("[")
		if not rest.is_empty():
			address_port = _port_in(rest.trim_prefix(":")) if rest.begins_with(":") else 0
	elif address.count(":") == 1:
		address_port = _port_in(address.get_slice(":", 1))
		address = address.get_slice(":", 0)
	return [address, address_port]


static func _port_in(text: String) -> int:
	var value := text.strip_edges()
	return int(value) if value.is_valid_int() and int(value) >= 1 and int(value) <= 65535 else 0


# =====================================================================
# Hosting
# =====================================================================

## Opens this machine's game to others on [param p_port] as [param p_name]: up
## to [param p_max_clients] remote players, with a [param password] only those
## who know it, over [param p_transport]. Returns OK, or an error when the port
## can't be listened on. Every tank starts without a driver; a running game seats its players
## again on hosting_started (game.gd).
func host(p_port: int, p_name: String, password: String = "", p_max_clients: int = MAX_CLIENTS,
		p_transport: Transport = Transport.TCP) -> Error:
	leave()
	var peer: MultiplayerPeer
	var err: Error
	if p_transport == Transport.UDP:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_server(p_port, UDP_MAX_PEERS, UDP_CHANNELS)
		peer = enet
	else:
		var socket := WebSocketMultiplayerPeer.new()
		_configure(socket)
		err = socket.create_server(p_port)
		peer = socket
	if err != OK:
		return err
	transport = p_transport
	port = p_port
	local_name = clean_name(p_name)
	host_name = local_name
	_start(peer)
	role = Role.HOST
	lock_new = false
	max_clients = clampi(p_max_clients, 1, MAX_CLIENTS)
	_password = password
	peers = {1: {"name": local_name, "allow": [true, true]}}
	host_screen = SCREEN_NONE
	PlayerInput.reset_to_empty()
	hosting_started.emit()
	session_changed.emit()
	return OK


## Turns newcomers away, or lets them in again.
func set_lock_new(on: bool) -> void:
	lock_new = on
	_session_dirty = true
	session_changed.emit()


## Host: the password newcomers need from now on ("" for none). Those already
## in stay.
func set_password(password: String) -> void:
	_password = password


func has_password() -> bool:
	return not _password.is_empty()


## Host: lets in up to [param count] remote players from now on. Those already
## in stay, even past it.
func set_max_clients(count: int) -> void:
	max_clients = clampi(count, 1, MAX_CLIENTS)
	session_changed.emit()


## Lets [param peer] drive tank [param tank], or not. Taking it away frees the
## seat if they hold it.
func set_allow(peer: int, tank: int, on: bool) -> void:
	if not peers.has(peer):
		return
	peers[peer]["allow"][tank] = on
	if not on:
		var key: int = PlayerInput.seats[tank]
		if key != PlayerInput.NO_SEAT and PlayerInput.controller_peer(key) == peer:
			PlayerInput.clear_seat(tank)
			seat_vacated.emit(tank)
	_session_dirty = true


## Removes a client from the game.
func kick(peer: int) -> void:
	if role != Role.HOST or peer == 1 or not peers.has(peer):
		return
	_h_bye.rpc_id(peer, END_KICKED)
	get_tree().create_timer(PARTING_DELAY, true, false, true).timeout.connect(_drop_peer.bind(peer))


## Host: cuts [param peer] off and lets them go as if they had left.
## (SceneMultiplayer.disconnect_peer forgets a peer without emitting
## peer_disconnected, so the leaving is done here.)
func _drop_peer(peer: int) -> void:
	if _mp == null or role != Role.HOST:
		return
	if _mp.get_peers().has(peer) or _mp.get_authenticating_peers().has(peer):
		_mp.disconnect_peer(peer)
	_on_peer_disconnected(peer)


## The host moved to [param screen]: every client follows. (The game there may
## be on another map set: the session goes out again, with its map.)
func set_host_screen(screen: String) -> void:
	if role != Role.HOST:
		return
	host_screen = screen
	_h_screen.rpc(screen)
	_session_dirty = true


## The lobby's state for the clients' copy of it.
func set_lobby(active: Array, loaded: bool) -> void:
	var next := {"active": [bool(active[0]), bool(active[1])], "loaded": loaded}
	if next == lobby:
		return
	lobby = next
	_session_dirty = true


## Host: a world snapshot for client [param peer].
func send_world(peer: int, bytes: PackedByteArray) -> void:
	if _mp != null and _mp.get_peers().has(peer):
		_mp.send_bytes(bytes, peer, MultiplayerPeer.TRANSFER_MODE_RELIABLE,
				WORLD_CHANNEL if transport == Transport.UDP else 0)
		_last_sent = Time.get_ticks_msec()


## Host: how many bytes wait to go out to [param peer]: a slow link backs up
## here. (ENet doesn't say; over UDP the snapshots' acks alone hold a slow
## client back.)
func pending_bytes(peer: int) -> int:
	if not _peer is WebSocketMultiplayerPeer or not _mp.get_peers().has(peer):
		return 0
	var ws := (_peer as WebSocketMultiplayerPeer).get_peer(peer)
	return ws.get_current_outbound_buffered_amount() if ws else 0


## Host: the clients, newcomers through the handshake included.
func client_ids() -> Array[int]:
	var ids: Array[int] = []
	if role == Role.HOST:
		for peer: int in peers:
			if peer != 1:
				ids.append(peer)
	return ids


## Host: the clients whose connection is open, the ones the host's world sends
## to. A newcomer is in [member peers] from the end of its handshake, a moment
## before its connection opens; a world sent it then would be lost, and with it
## the whole world every later snapshot only adds to.
func connected_client_ids() -> Array[int]:
	var ids: Array[int] = []
	if _mp == null:
		return ids
	var open := _mp.get_peers()
	for peer in client_ids():
		if open.has(peer):
			ids.append(peer)
	return ids


## A client asks for tank [param tank] (a click on its lobby card), as its P1
## controls' fire would ask for a free one.
func request_seat(tank: int) -> void:
	if role == Role.CLIENT and _joined:
		_c_claim.rpc_id(1, tank)


## Rumbles tank [param tank]'s driver's controller: this machine's own, or
## theirs on a client.
func rumble_tank(tank: int, weak: float, strong: float, duration: float) -> void:
	if role == Role.CLIENT:
		return  # the host decides
	var key: int = PlayerInput.seats[tank]
	if key == PlayerInput.NO_SEAT:
		return
	var slot := PlayerInput.controller_slot(key)
	var peer := PlayerInput.controller_peer(key)
	if peer == 1:
		InputSettings.rumble(slot, weak, strong, duration)
	elif _mp != null and _mp.get_peers().has(peer):
		_h_rumble.rpc_id(peer, slot, weak, strong, duration)


# =====================================================================
# Joining
# =====================================================================

## Connects to the game at [param address] (a name or IP, IPv6 too) on
## [param p_port] as [param p_name], with the game's [param password] if it has
## one, over TCP or UDP, whichever the host takes. join_succeeded or
## join_failed follows.
func join(address: String, p_port: int, p_name: String, password: String = "") -> Error:
	leave()
	local_name = clean_name(p_name)
	if local_name.is_empty():
		return ERR_INVALID_PARAMETER
	_join_target = {"address": address.strip_edges().trim_prefix("[").trim_suffix("]"), "port": p_port}
	_udp_lost = false
	_tcp_answered_at = -1
	_tcp_probe = StreamPeerTCP.new()
	if _tcp_probe.connect_to_host(_join_target["address"], p_port) != OK:
		_tcp_probe = null
	var err := _connect_client(Transport.UDP)
	if err != OK:
		if _tcp_probe == null:
			return err
		_udp_lost = true  # a TCP host can still answer
	port = p_port
	role = Role.CLIENT
	_joined = false
	_join_password = password
	_connect_timer = CONNECT_TIMEOUT
	_world_packets.clear()
	_presses = [[0, 0], [0, 0]]
	_shots = [[0, 0], [0, 0]]
	_shot_rows = [[1, 1], [1, 1]]
	client_view_time = 0.0
	_sent_input = PackedByteArray()
	_latest_snapshot = -1
	_ping_timer = PING_EVERY  # the first once the host's screen has loaded here
	return OK


## Ends the session: a host closes the game, a client leaves it.
func leave() -> void:
	if role == Role.OFFLINE:
		return
	_say_goodbye(END_HOST_LEFT if role == Role.HOST else END_LEFT)
	_flush(0.1)
	_end(END_LEFT)


## A name fit to show: printable, trimmed, at most NAME_MAX letters, upper case
## as every name on the screens is.
static func clean_name(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 32 and c != 127:
			out += char(c)
	return out.strip_edges().left(NAME_MAX).to_upper()


# =====================================================================
# Session plumbing
# =====================================================================

func _configure(peer: WebSocketMultiplayerPeer) -> void:
	peer.inbound_buffer_size = BUFFER_SIZE
	peer.outbound_buffer_size = BUFFER_SIZE
	peer.handshake_timeout = CONNECT_TIMEOUT


## Client: starts a join over [param kind] to the game at _join_target. One
## already going over the other transport is dropped quietly: the host takes
## this one.
func _connect_client(kind: Transport) -> Error:
	var address: String = _join_target["address"]
	var target_port: int = _join_target["port"]
	var peer: MultiplayerPeer
	var err: Error
	if kind == Transport.UDP:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_client(address, target_port, UDP_CHANNELS)
		peer = enet
	else:
		var socket := WebSocketMultiplayerPeer.new()
		_configure(socket)
		var url_host := "[%s]" % address if address.contains(":") else address  # IPv6 in brackets
		err = socket.create_client("ws://%s:%d" % [url_host, target_port])
		peer = socket
	if err != OK:
		return err
	_release_multiplayer()
	transport = kind
	_start(peer)
	return OK


## Client, while the join goes on: the UDP try connecting means a UDP host, and
## the probe stops. A TCP connection that opens means a TCP host: unless the UDP
## try connects within TCP_SWITCH_DELAY, it gives way to a join over TCP. With
## neither left, nothing answered.
func _find_transport() -> void:
	if transport != Transport.UDP:
		return
	if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_stop_probe()
		_tcp_answered_at = -1
		return
	if _tcp_probe != null:
		_tcp_probe.poll()
		var status := _tcp_probe.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			_stop_probe()
			_tcp_answered_at = Time.get_ticks_msec()
		elif status != StreamPeerTCP.STATUS_CONNECTING:
			_stop_probe()  # no TCP there: it's UDP or nothing
			if _udp_lost:
				_fail_join(END_NO_HOST)
			return
	if _tcp_answered_at >= 0 and (_udp_lost or Time.get_ticks_msec() - _tcp_answered_at >= int(TCP_SWITCH_DELAY * 1000.0)):
		_tcp_answered_at = -1
		if _connect_client(Transport.TCP) != OK:
			_fail_join(END_NO_HOST)


func _stop_probe() -> void:
	if _tcp_probe != null:
		_tcp_probe.disconnect_from_host()
		_tcp_probe = null


## Lets go of the multiplayer and its peer without a word from either: none of
## their signals reach this node any more.
func _release_multiplayer() -> void:
	if _mp == null:
		return
	for sig: Dictionary in _mp.get_signal_list():
		for connection: Dictionary in _mp.get_signal_connection_list(sig["name"]):
			var target: Callable = connection["callable"]
			if target.get_object() == self:
				_mp.disconnect(sig["name"], target)
	_mp.auth_callback = Callable()
	_mp.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null
	_mp = null


func _start(peer: MultiplayerPeer) -> void:
	_peer = peer
	_mp = SceneMultiplayer.new()
	_mp.auth_callback = _on_auth
	_mp.auth_timeout = AUTH_TIMEOUT
	_mp.server_relay = false            # clients only ever talk to the host
	_mp.allow_object_decoding = false
	_mp.peer_authenticating.connect(_on_peer_authenticating)
	_mp.peer_authentication_failed.connect(_on_peer_authentication_failed)
	_mp.peer_connected.connect(_on_peer_connected)
	_mp.peer_disconnected.connect(_on_peer_disconnected)
	_mp.connected_to_server.connect(_on_connected_to_server)
	_mp.connection_failed.connect(_on_connection_failed)
	_mp.server_disconnected.connect(_on_server_disconnected)
	_mp.peer_packet.connect(_on_peer_packet)
	get_tree().set_multiplayer(_mp)
	_mp.multiplayer_peer = peer
	_end_reason = ""
	_last_heard.clear()
	acks.clear()
	_last_sent = Time.get_ticks_msec()


## Ends the session once the multiplayer is done with the call it is in: the
## signals that end one (a dropped connection, a refusal) come from inside its
## poll, and freeing it there would pull it out from under itself.
func _end_soon(reason: String) -> void:
	if _ending:
		return
	_ending = true
	_end.call_deferred(reason)


## Closes everything and goes back to offline play.
func _end(reason: String) -> void:
	_ending = false
	if role == Role.OFFLINE and _mp == null:
		return
	var was := role
	var was_joined := _joined
	_stop_probe()
	_udp_lost = false
	_tcp_answered_at = -1
	if _mp != null:
		_mp.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null
	_mp = null
	get_tree().set_multiplayer(SceneMultiplayer.new())
	role = Role.OFFLINE
	peers.clear()
	acks.clear()
	_knocking.clear()
	_password = ""
	_join_password = ""
	host_screen = SCREEN_NONE
	host_name = ""
	_joined = false
	input_blocked = false
	_tank_reports = [{}, {}]
	_own_events = PackedByteArray()
	client_view_time = 0.0
	ping_ms = 0.0
	_ping_timer = 0.0
	_ping_samples.clear()
	_lagged.clear()
	host_map = {}
	_maps_asked.clear()
	_map_download = {}
	_map_sends.clear()
	_world_packets.clear()
	world_sink = Callable()
	PlayerInput.reset_to_local()
	if was != Role.OFFLINE:
		session_ended.emit(reason)
	session_changed.emit()
	# A client whose game ended under it (the host left, a kick, a lost line)
	# goes back to the ONLINE screen, which says why. (A join that never got in
	# says why through join_failed, on the screen it was started from.)
	if was == Role.CLIENT and was_joined and reason != END_LEFT:
		_last_end_reason = reason
		var tree := get_tree()
		tree.paused = false
		if tree.current_scene == null or tree.current_scene.scene_file_path != ONLINE_SCENE:
			tree.change_scene_to_file(ONLINE_SCENE)


## Why the last session ended (an END_* code), once: "" when it was our choice
## or that was already shown.
func take_end_reason() -> String:
	var reason := _last_end_reason
	_last_end_reason = ""
	return reason


func _say_goodbye(reason: String) -> void:
	if _mp == null or _mp.get_peers().is_empty():
		return
	if role == Role.HOST:
		_h_bye.rpc(reason)
	elif _joined:
		_c_bye.rpc_id(1)


## Keeps the connection turning for up to [param seconds], so what was just sent
## goes out before the socket closes.
func _flush(seconds: float) -> void:
	if _peer == null:
		return
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		_peer.poll()
		OS.delay_msec(5)


func _process(delta: float) -> void:
	if role == Role.OFFLINE:
		return
	if role == Role.CLIENT and not _joined:
		_find_transport()
		_connect_timer -= delta
		if _connect_timer <= 0.0:
			_fail_join(END_NO_HOST)
			return
	_run_lagged()
	if role == Role.CLIENT and _joined:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = PING_EVERY
			var stamp := Time.get_ticks_msec()
			var known := roundi(ping_ms)
			_later(func() -> void:
				if role == Role.CLIENT and _joined:
					_c_ping.rpc_id(1, stamp, known))
	var now := Time.get_ticks_msec()
	if _session_dirty and role == Role.HOST:
		_session_dirty = false
		_h_session.rpc(_session_info())
		session_changed.emit()
		_last_sent = now
	if not _map_sends.is_empty():
		_send_map_pieces()
		_last_sent = now
	# Keepalive both ways, and give up on the silent.
	if now - _last_sent > int(KEEPALIVE * 1000.0) and _mp != null and not _mp.get_peers().is_empty():
		if role == Role.HOST:
			_h_alive.rpc()
		elif _joined:
			_c_alive.rpc_id(1)
		_last_sent = now
	for peer: int in _last_heard.keys():
		if now - int(_last_heard[peer]) > int(SILENCE_LIMIT * 1000.0):
			_last_heard.erase(peer)
			if role == Role.HOST:
				_drop_peer(peer)
			else:
				_end_soon(END_LOST)
				return


func _physics_process(_delta: float) -> void:
	if role == Role.CLIENT and _joined:
		_run_lagged()
		_send_input()


## [param action] now, or (a test's long line, sim_lag_ms and sim_jitter_ms)
## that much later, in order.
func _later(action: Callable) -> void:
	if sim_lag_ms <= 0 and sim_jitter_ms <= 0:
		action.call()
		return
	var due := Time.get_ticks_msec() + sim_lag_ms + randi_range(0, sim_jitter_ms)
	if not _lagged.is_empty():
		due = maxi(due, int(_lagged[-1][0]))
	_lagged.append([due, action])


func _run_lagged() -> void:
	var now := Time.get_ticks_msec()
	while not _lagged.is_empty() and int(_lagged[0][0]) <= now:
		var action: Callable = _lagged.pop_front()[1]
		action.call()


## Client: local slot [param slot]'s tank, as it drives on this machine: at
## [param position], facing [param facing] (an index into BaseTank.FACINGS),
## driving or not, having taken correction [param override], and in the air
## or not ([param flying]: a mine threw it here). It goes to the host with the
## next input message.
func report_tank(slot: int, position: Vector2, facing: int, moving: bool, override: int,
		flying: bool = false) -> void:
	if slot < 0 or slot > 1:
		return
	_tank_reports[slot] = {"position": position, "facing": facing, "moving": moving, "override": override,
			"flying": flying, "frame": Engine.get_physics_frames()}


## Client: something happened to local slot [param slot]'s tank here, decided
## here (NetClientWorld.own_tank_step): [param kind] OWN_HIT ([param amount]
## its points, by [param shooter]'s fire or blast, -1 the enemies' or nobody's)
## or OWN_MINE (the mine [param nid] of level [param amount] centred at
## [param center] went off under it), [param flags] OWN_*, with its tank at
## [param at] in its latest report's frame. The host is told after the next
## input message, and does the same to its copy (PlayerTank._take_reported_events).
func note_own_event(slot: int, kind: int, amount: int, flags: int, shooter: int, nid: int, at: Vector2,
		center: Vector2 = Vector2.ZERO) -> void:
	if slot < 0 or slot > 1 or _own_events.size() >= OWN_SIZE * OWN_MAX:
		return
	var record := PackedByteArray()
	record.resize(OWN_SIZE)
	record[0] = slot
	record[1] = kind
	record[2] = reported_frame(slot) & 0xff
	record[3] = clampi(amount, 0, 255)
	record[4] = flags & 0xff
	record[5] = clampi(shooter + 1, 0, 2)
	record.encode_u32(8, maxi(nid, 0))
	record.encode_float(12, at.x)
	record.encode_float(16, at.y)
	record.encode_float(20, center.x)
	record.encode_float(24, center.y)
	_own_events.append_array(record)


## Client: the physics frame of local slot [param slot]'s tank's latest report
## (report_tank): what the host judges this machine's screen by, frame by frame.
func reported_frame(slot: int) -> int:
	if slot < 0 or slot > 1 or _tank_reports[slot].is_empty():
		return Engine.get_physics_frames()
	return int(_tank_reports[slot]["frame"])


## Client: local slot [param slot]'s tank fired a shot here at once with fire
## button [param button] (0 or 1), from row [param row] (0 left, 1 middle, 2
## right): the host is told with the next input message, and fires that very
## shot (PlayerTank._fire_client_shots). Returns its number, button * 256 + its
## count, which the host's shell for it carries too.
func note_shot(slot: int, button: int, row: int) -> int:
	if slot < 0 or slot > 1 or button < 0 or button > 1:
		return -1
	_shots[slot][button] = (int(_shots[slot][button]) + 1) & 0xff
	_shot_rows[slot][button] = clampi(row, 0, 2)
	return button * 256 + int(_shots[slot][button])


## Host: client [param peer]'s trip here and back, ms, as it last timed it (0 not yet).
func peer_ping(peer: int) -> int:
	return int(peers.get(peer, {}).get("ping", 0))


func _heard(peer: int) -> void:
	_last_heard[peer] = Time.get_ticks_msec()


## Small messages (a key press) go out at once rather than waiting to be
## bundled (Nagle's algorithm off on that connection's TCP socket; ENet never
## waits).
func _no_delay(peer: int) -> void:
	var ws := (_peer as WebSocketMultiplayerPeer).get_peer(peer) if _peer is WebSocketMultiplayerPeer else null
	if ws:
		ws.set_no_delay(true)


# --- The handshake ---

func _on_peer_authenticating(peer: int) -> void:
	# The client speaks first: its protocol and name.
	if role == Role.CLIENT and peer == 1:
		_mp.send_auth(1, var_to_bytes({"protocol": PROTOCOL, "name": local_name,
				"version": ProjectSettings.get_setting("application/config/version", "")}))


func _on_auth(peer: int, data: PackedByteArray) -> void:
	var message: Variant = bytes_to_var(data) if data.size() < 4096 else null
	if typeof(message) != TYPE_DICTIONARY:
		if role == Role.HOST:
			_refuse(peer, END_VERSION)
		return
	if role == Role.HOST:
		if _knocking.has(peer):
			_check_proof(peer, message)
		else:
			_check_newcomer(peer, message)
	elif peer == 1:
		if message.has("challenge"):
			_answer_challenge(message["challenge"])
		elif message.get("ok", false):
			host_name = clean_name(str(message.get("name", "")))
			_mp.complete_auth(1)
		else:
			_end_reason = str(message.get("reason", END_LOST))


## The host's side of the handshake: in, turned away with a reason, or (a game
## with a password) challenged to prove it knows the password.
func _check_newcomer(peer: int, hello: Dictionary) -> void:
	var name := clean_name(str(hello.get("name", "")))
	if int(hello.get("protocol", -1)) != PROTOCOL:
		_refuse(peer, END_VERSION)
	elif name.is_empty():
		_refuse(peer, END_BAD_NAME)
	elif lock_new:
		_refuse(peer, END_LOCKED)
	elif client_ids().size() >= max_clients:
		_refuse(peer, END_FULL)
	elif _password.is_empty():
		_admit(peer, name)
	else:
		var nonce := Crypto.new().generate_random_bytes(NONCE_SIZE)
		_knocking[peer] = {"name": name, "nonce": nonce}
		_mp.send_auth(peer, var_to_bytes({"challenge": nonce}))


## A challenged newcomer's answer: the challenge signed with the password.
func _check_proof(peer: int, answer: Dictionary) -> void:
	var knock: Dictionary = _knocking[peer]
	_knocking.erase(peer)
	var proof: Variant = answer.get("proof")
	var expected := password_proof(_password, knock["nonce"])
	if not proof is PackedByteArray or (proof as PackedByteArray).is_empty():
		_refuse(peer, END_NEED_PASSWORD)
	elif (proof as PackedByteArray).size() != expected.size() \
			or not Crypto.new().constant_time_compare(expected, proof):
		_refuse(peer, END_WRONG_PASSWORD)
	elif lock_new:  # while it answered
		_refuse(peer, END_LOCKED)
	elif client_ids().size() >= max_clients:
		_refuse(peer, END_FULL)
	else:
		_admit(peer, knock["name"])


func _admit(peer: int, name: String) -> void:
	peers[peer] = {"name": _unique_name(name), "allow": [true, true]}
	_mp.send_auth(peer, var_to_bytes({"ok": true, "name": local_name}))
	_mp.complete_auth(peer)


## What a player who knows [param password] answers challenge [param nonce]
## with: an HMAC-SHA256 of it, keyed with the password. The password itself
## never crosses the network.
static func password_proof(password: String, nonce: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, password.to_utf8_buffer(), nonce)


## Client: the host's game has a password. With none to give, the answer is
## empty and the host says the game needs one.
func _answer_challenge(nonce: Variant) -> void:
	if not nonce is PackedByteArray or (nonce as PackedByteArray).size() != NONCE_SIZE:
		return  # not a challenge of ours: the handshake times out
	var proof := PackedByteArray() if _join_password.is_empty() else password_proof(_join_password, nonce)
	_mp.send_auth(1, var_to_bytes({"proof": proof}))


func _refuse(peer: int, reason: String) -> void:
	_mp.send_auth(peer, var_to_bytes({"ok": false, "reason": reason}))
	get_tree().create_timer(PARTING_DELAY, true, false, true).timeout.connect(_drop_peer.bind(peer))


## [param name], or "NAME 2", "NAME 3"... when someone already has it.
func _unique_name(name: String) -> String:
	var taken: Array = []
	for info: Dictionary in peers.values():
		taken.append(info["name"])
	if name not in taken:
		return name
	for n in range(2, 10):
		var candidate := "%s %d" % [name.left(NAME_MAX - 2), n]
		if candidate not in taken:
			return candidate
	return name


# --- Peers coming and going ---

func _on_peer_connected(peer: int) -> void:
	if role != Role.HOST:
		return
	if not peers.has(peer):
		_drop_peer(peer)  # never passed the handshake
		return
	_heard(peer)
	_no_delay(peer)
	_post_notice(NOTICE_JOINED, peer_name(peer))
	_h_session.rpc(_session_info())
	_h_screen.rpc_id(peer, host_screen)
	session_changed.emit()


func _on_peer_disconnected(peer: int) -> void:
	if role != Role.HOST:
		return
	_last_heard.erase(peer)
	acks.erase(peer)
	_knocking.erase(peer)
	if not peers.has(peer):
		return
	var name := peer_name(peer)
	peers.erase(peer)
	for tank in PlayerInput.remove_peer(peer):
		seat_vacated.emit(tank)
	_post_notice(NOTICE_LEFT, name)
	_session_dirty = true
	session_changed.emit()


func _on_connected_to_server() -> void:
	_joined = true
	_heard(1)
	_no_delay(1)
	join_succeeded.emit()
	session_changed.emit()


func _on_connection_failed() -> void:
	if transport == Transport.UDP and (_tcp_probe != null or _tcp_answered_at >= 0):
		_udp_lost = true  # the probe may yet find, or has found, a TCP host
		return
	_fail_join(_end_reason if not _end_reason.is_empty() else END_NO_HOST)


func _on_peer_authentication_failed(peer: int) -> void:
	_knocking.erase(peer)  # host: a newcomer that never answered its challenge
	if role == Role.CLIENT and peer == 1 and not _joined:
		_fail_join(_end_reason if not _end_reason.is_empty() else END_LOST)


func _on_server_disconnected() -> void:
	if not _joined:
		_fail_join(_end_reason if not _end_reason.is_empty() else END_NO_HOST)
		return
	_end_soon(_end_reason if not _end_reason.is_empty() else END_LOST)


## A join that never got in: the session closes and join_failed says why.
func _fail_join(reason: String) -> void:
	if _ending or role != Role.CLIENT:
		return
	_joined = false
	_end_soon(reason)
	(func() -> void: join_failed.emit(reason)).call_deferred()


## Someone came or went: said on every machine, each in its own language.
func _post_notice(kind: String, name: String) -> void:
	notice_posted.emit(notice_text(kind, name))
	if role == Role.HOST:
		_h_notice.rpc(kind, name)


func notice_text(kind: String, name: String) -> String:
	match kind:
		NOTICE_JOINED:
			return tr("%s joined the game.") % name
		NOTICE_LEFT:
			return tr("%s left the game.") % name
	return ""


func _session_info() -> Dictionary:
	var list: Array = []
	for peer: int in peers:
		list.append([peer, peers[peer]["name"], peers[peer]["allow"][0], peers[peer]["allow"][1]])
	return {"peers": list, "seats": PlayerInput.seats.duplicate(), "lock": lock_new, "lobby": lobby,
			"map": _host_map_info()}


# --- The map set (like Counter-Strike 1.6's, a client can fetch the host's) ---

## Host: the map set this game plays on, for each client to check theirs
## against: {"name", "hash", "size"}, or {} when its file can't be read.
func _host_map_info() -> Dictionary:
	var pool := _host_map_pool()
	if pool == null:
		return {}
	var digest := LevelData.pool_hash(pool)
	var file := FileAccess.open(pool.path, FileAccess.READ)
	if digest.is_empty() or file == null:
		return {}
	return {"name": pool.display_name, "hash": digest, "size": file.get_length()}


## Host: the map set in play: the game's pick, else the one loaded.
func _host_map_pool() -> LevelData.MapPool:
	var pool_id := GameManager.current_map_pool_id
	if pool_id.is_empty():
		pool_id = LevelData._current_pool_id
	return LevelData.find_pool(pool_id)


## Client: the host's map set, from its session. One this computer doesn't
## have (no map of the same hash) is offered once a session; the game itself
## doesn't need it, as the host sends every stage's map with its world.
func _take_host_map(map: Dictionary) -> void:
	var digest := str(map.get("hash", ""))
	var size := int(map.get("size", 0))
	if not is_map_hash(digest) or size <= 0 or size > MAX_MAP_SIZE or size % LevelData.DAT_STAGE_SIZE != 0:
		host_map = {}
		return
	var name := LevelData._sanitize_pool_name(str(map.get("name", "")))
	host_map = {"name": name, "hash": digest, "size": size}
	if _maps_asked.has(digest) or LevelData.pool_with_hash(digest) != null:
		return
	_maps_asked[digest] = true
	map_offered.emit(host_map)
	get_tree().root.add_child.call_deferred(NetMapPrompt.new(host_map))


## A SHA-256 in hex, as LevelData.pool_hash writes them.
static func is_map_hash(text: String) -> bool:
	if text.length() != 64:
		return false
	for i in text.length():
		if "0123456789abcdef".find(text[i]) < 0:
			return false
	return true


## "390 KB", for the map question.
static func map_size_text(size: int) -> String:
	return "%d KB" % ceili(size / 1024.0)


## Client: fetches the host's map set (the map question's DOWNLOAD).
## map_progress follows, then map_download_finished. False when there's
## nothing to fetch it from (not in a game, or one already coming).
func download_map() -> bool:
	if role != Role.CLIENT or not _joined or host_map.is_empty() or not _map_download.is_empty():
		return false
	_map_download = host_map.duplicate()
	_map_download["bytes"] = PackedByteArray()
	_c_map_request.rpc_id(1, host_map["hash"])
	return true


func is_downloading_map() -> bool:
	return not _map_download.is_empty()


## Host: the next piece of each map set on its way.
func _send_map_pieces() -> void:
	for peer: int in _map_sends.keys():
		if _mp == null or not _mp.get_peers().has(peer):
			_map_sends.erase(peer)
			continue
		if pending_bytes(peer) > MAP_SEND_BACKLOG:
			continue  # let what's waiting go out first
		var send: Dictionary = _map_sends[peer]
		var bytes: PackedByteArray = send["bytes"]
		var offset: int = send["offset"]
		var piece := bytes.slice(offset, offset + MAP_CHUNK)
		_h_map_piece.rpc_id(peer, send["hash"], offset, bytes.size(), piece)
		send["offset"] = offset + piece.size()
		if send["offset"] >= bytes.size():
			_map_sends.erase(peer)


## Client: a map download is over: saved as pool [param name], or not and
## [param error] says why. Said over the screen too.
func _finish_map_download(name: String, error: String) -> void:
	_map_download = {}
	if name.is_empty():
		notice_posted.emit(tr("The host's map didn't come through: %s") % error)
	else:
		notice_posted.emit(tr("Saved the map %s with your maps.") % name)
	map_download_finished.emit(name, error)


# --- The world ---

## A world snapshot: its number (acknowledged at once, so the host's flow
## control sees what has arrived), then the snapshot for the game view.
func _on_peer_packet(peer: int, packet: PackedByteArray) -> void:
	if role != Role.CLIENT or peer != 1 or packet.size() < 4:
		return  # only the host sends raw packets
	_heard(1)
	_later(_take_world_packet.bind(packet))


func _take_world_packet(packet: PackedByteArray) -> void:
	if role != Role.CLIENT:
		return
	_latest_snapshot = packet.decode_u32(0)
	var body := packet.slice(4)
	if world_sink.is_valid():
		world_sink.call(body)
	else:
		_world_packets.append(body)
		if _world_packets.size() > 600:
			_world_packets.remove_at(0)  # no game view for ages: keep the newest


## Client: the snapshots that came before the game view was ready to take them.
func take_world_packets() -> Array[PackedByteArray]:
	var packets := _world_packets
	_world_packets = []
	return packets


# --- The client's inputs ---

## Samples both local players and sends them, with the newest snapshot seen,
## whenever either changed (a press always does).
func _send_input() -> void:
	var bytes := _input_message()
	if bytes != _sent_input:
		_sent_input = bytes
		_later(func() -> void:
			if role == Role.CLIENT and _joined:
				_c_input.rpc_id(1, bytes))
		_last_sent = Time.get_ticks_msec()
	# What happened to its own tanks here, after the report of the frame it did.
	if not _own_events.is_empty():
		var own := _own_events
		_own_events = PackedByteArray()
		_later(func() -> void:
			if role == Role.CLIENT and _joined:
				_c_own.rpc_id(1, own))
		_last_sent = Time.get_ticks_msec()


## The input message (INPUT_SIZE): the newest snapshot, then per local player
## the direction, both fire buttons held and a press counter each, then per
## local player whether this machine runs its own tanks (lag compensation) and
## its tank as it drives here, if it drives one, then the shots its tank fired
## here (note_shot), then the moment of the host's world shown here
## (client_view_time). Idle while this machine's menu or the map question has
## the keys.
func _input_message() -> PackedByteArray:
	var blocked := input_blocked or map_prompt_open
	for slot in 2:
		var prefix := PlayerInput.action_prefix(slot)
		for b in 2:
			if not blocked and Input.is_action_just_pressed(prefix + PlayerInput.BUTTONS[b]):
				_presses[slot][b] = (int(_presses[slot][b]) + 1) & 0xff
	var ack := _latest_snapshot
	var bytes := PackedByteArray()
	bytes.resize(INPUT_SIZE)
	bytes.encode_s32(0, ack)
	for slot in 2:
		var at := 4 + slot * 4
		var direction := -1 if blocked else PlayerInput.local_direction_index(slot)
		var held := 0
		if not blocked:
			for b in 2:
				if Input.is_action_pressed(PlayerInput.action_prefix(slot) + PlayerInput.BUTTONS[b]):
					held |= 1 << b
		bytes[at] = direction + 1
		bytes[at + 1] = held
		bytes[at + 2] = _presses[slot][0]
		bytes[at + 3] = _presses[slot][1]
		var where := REPORT_AT + slot * REPORT_SIZE
		bytes[where] = REPORT_PREDICTS if InputSettings.get_lag_compensation() else 0
		var report: Dictionary = _tank_reports[slot]
		if report.is_empty() or Engine.get_physics_frames() - int(report["frame"]) > 2:
			continue  # no tank of its own driving here
		bytes[where] |= REPORT_HAS | (REPORT_MOVING if report["moving"] else 0) \
				| (REPORT_FLYING if report.get("flying", false) else 0)
		bytes[where + 1] = int(report["facing"])
		bytes[where + 2] = int(report["override"]) & 0xff
		bytes[where + 3] = int(report["frame"]) & 0xff
		var position: Vector2 = report["position"]
		bytes.encode_float(where + 4, position.x)
		bytes.encode_float(where + 8, position.y)
	for slot in 2:
		var shots := SHOTS_AT + slot * SHOTS_SIZE
		bytes[shots] = _shots[slot][0]
		bytes[shots + 1] = _shots[slot][1]
		bytes[shots + 2] = int(_shot_rows[slot][0]) | int(_shot_rows[slot][1]) << 2
	bytes.encode_u32(VIEW_AT, clampi(roundi(client_view_time), 0, 0xffffffff))
	return bytes


# =====================================================================
# RPCs: client -> host
# =====================================================================

@rpc("any_peer", "call_remote", "reliable")
func _c_input(bytes: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not peers.has(sender) or bytes.size() != INPUT_SIZE:
		return
	_heard(sender)
	acks[sender] = bytes.decode_s32(0)
	var view := float(bytes.decode_u32(VIEW_AT))
	for slot in 2:
		var at := 4 + slot * 4
		var direction := int(bytes[at]) - 1
		var held := int(bytes[at + 1])
		PlayerInput.set_remote(sender, slot, direction,
				[held & 1 != 0, held & 2 != 0], [int(bytes[at + 2]), int(bytes[at + 3])])
		var where := REPORT_AT + slot * REPORT_SIZE
		var flags := int(bytes[where])
		var position := Vector2(bytes.decode_float(where + 4), bytes.decode_float(where + 8))
		var sane := position.is_finite() and Rect2(0, 0, 1600, 1000).has_point(position)
		PlayerInput.set_remote_report(sender, slot, flags & REPORT_HAS != 0 and sane, flags & REPORT_PREDICTS != 0,
				position, int(bytes[where + 1]), flags & REPORT_MOVING != 0, int(bytes[where + 2]), int(bytes[where + 3]), view,
				flags & REPORT_FLYING != 0)
		var shots := SHOTS_AT + slot * SHOTS_SIZE
		var rows := int(bytes[shots + 2])
		PlayerInput.set_remote_shots(sender, slot, [int(bytes[shots]), int(bytes[shots + 1])], [rows & 3, (rows >> 2) & 3])


## What happened to the client's own tanks there, decided there (note_own_event).
@rpc("any_peer", "call_remote", "reliable")
func _c_own(bytes: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not peers.has(sender):
		return
	_heard(sender)
	take_own_events(sender, bytes)


## Host: client [param peer]'s word of what happened to its own tanks there,
## [param bytes] of OWN_SIZE records (note_own_event): each is queued for the
## host's copy of that tank (PlayerTank._take_reported_events).
func take_own_events(peer: int, bytes: PackedByteArray) -> void:
	if bytes.size() % OWN_SIZE != 0 or bytes.size() > OWN_SIZE * OWN_MAX:
		return
	for at in range(0, bytes.size(), OWN_SIZE):
		var slot := int(bytes[at])
		var kind := int(bytes[at + 1])
		var tank_at := Vector2(bytes.decode_float(at + 12), bytes.decode_float(at + 16))
		var center := Vector2(bytes.decode_float(at + 20), bytes.decode_float(at + 24))
		if slot > 1 or kind not in [OWN_HIT, OWN_MINE] or not tank_at.is_finite() or not center.is_finite():
			continue
		PlayerInput.add_remote_event(peer, slot, kind, int(bytes[at + 2]), int(bytes[at + 3]), int(bytes[at + 4]),
				int(bytes[at + 5]) - 1, int(bytes.decode_u32(at + 8)), tank_at, center)


@rpc("any_peer", "call_remote", "reliable")
func _c_claim(tank: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not peers.has(sender) or tank < 0 or tank > 1:
		return
	_heard(sender)
	var scene := get_tree().current_scene
	if scene and scene.has_method(&"net_claim"):
		scene.net_claim(PlayerInput.controller_key(sender, 0), tank)


@rpc("any_peer", "call_remote", "reliable")
func _c_alive() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if role == Role.HOST and peers.has(sender):
		_heard(sender)


## A client asks for the map set [param digest]: the game's own, if it still is.
@rpc("any_peer", "call_remote", "reliable")
func _c_map_request(digest: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not peers.has(sender) or _map_sends.has(sender):
		return
	_heard(sender)
	var map := _host_map_info()
	var pool := _host_map_pool()
	var bytes := FileAccess.get_file_as_bytes(pool.path) if pool != null else PackedByteArray()
	if map.get("hash", "") != digest or bytes.is_empty() or bytes.size() > MAX_MAP_SIZE:
		_h_map_piece.rpc_id(sender, digest, 0, 0, PackedByteArray())  # nothing to send
		return
	_map_sends[sender] = {"hash": digest, "bytes": bytes, "offset": 0}


@rpc("any_peer", "call_remote", "reliable")
func _c_bye() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if role == Role.HOST and _mp != null:
		_drop_peer.call_deferred(sender)  # not from inside the poll delivering this


# =====================================================================
# RPCs: host -> clients
# =====================================================================

@rpc("authority", "call_remote", "reliable")
func _h_session(info: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	_heard(1)
	peers.clear()
	for entry: Array in info.get("peers", []):
		if entry.size() == 4:
			peers[int(entry[0])] = {"name": str(entry[1]), "allow": [bool(entry[2]), bool(entry[3])]}
	var seats: Array = info.get("seats", [])
	if seats.size() == 2:
		PlayerInput.seats = [int(seats[0]), int(seats[1])]
		PlayerInput.seats_changed.emit()
	lock_new = bool(info.get("lock", false))
	var got_lobby: Variant = info.get("lobby", {})
	if got_lobby is Dictionary:
		lobby = got_lobby
	var got_map: Variant = info.get("map", {})
	_take_host_map(got_map if got_map is Dictionary else {})
	session_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _h_screen(screen: String) -> void:
	if role != Role.CLIENT:
		return
	_heard(1)
	host_screen = screen
	var tree := get_tree()
	var current := tree.current_scene.scene_file_path if tree.current_scene else ""
	if screen == SCREEN_LOBBY and current != LOBBY_SCENE:
		tree.change_scene_to_file(LOBBY_SCENE)
	elif screen == SCREEN_GAME and current != GAME_SCENE:
		tree.change_scene_to_file(GAME_SCENE)
	session_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _h_notice(kind: String, name: String) -> void:
	if role == Role.CLIENT:
		_heard(1)
		var text := notice_text(kind, clean_name(name))
		if not text.is_empty():
			notice_posted.emit(text)


@rpc("authority", "call_remote", "reliable")
func _h_rumble(slot: int, weak: float, strong: float, duration: float) -> void:
	if role == Role.CLIENT and slot >= 0 and slot < 2:
		InputSettings.rumble(slot, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), clampf(duration, 0.0, 2.0))


## A piece of the map set [param digest] the client asked for: [param bytes]
## from [param offset], of [param total] (0: the host can't send it). The whole
## is checked against its hash before it's kept.
@rpc("authority", "call_remote", "reliable")
func _h_map_piece(digest: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	if role != Role.CLIENT:
		return
	_heard(1)
	_take_map_piece(digest, offset, total, bytes)


## Client: a piece of the map set coming (see _h_map_piece).
func _take_map_piece(digest: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	if _map_download.is_empty() or digest != _map_download["hash"]:
		return
	if total == 0:
		_finish_map_download("", tr("the host no longer plays on it"))
		return
	var got: PackedByteArray = _map_download["bytes"]
	if total != int(_map_download["size"]) or offset != got.size() or got.size() + bytes.size() > total:
		_finish_map_download("", tr("it came in out of order"))
		return
	got.append_array(bytes)
	_map_download["bytes"] = got
	map_progress.emit(got.size(), total)
	if got.size() < total:
		return
	if LevelData.bytes_hash(got) != digest:
		_finish_map_download("", tr("it isn't the map the host named"))
		return
	var result := LevelData.save_map_bytes(_map_download["name"], got)
	if result.get("ok", false):
		_finish_map_download(result["name"], "")
	else:
		_finish_map_download("", str(result.get("error", "")))


## Client [param stamp] (its clock) times a trip here and back; [param client_ping]
## is what it made of the last one, for the host's list of players.
@rpc("any_peer", "call_remote", "reliable")
func _c_ping(stamp: int, client_ping: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if role != Role.HOST or not peers.has(sender):
		return
	_heard(sender)
	var ping := clampi(client_ping, 0, 9999)
	if int(peers[sender].get("ping", 0)) != ping:
		peers[sender]["ping"] = ping
		peer_ping_changed.emit(sender)
	_h_pong.rpc_id(sender, stamp)


@rpc("authority", "call_remote", "reliable")
func _h_pong(stamp: int) -> void:
	if role != Role.CLIENT:
		return
	_heard(1)
	_later(_take_pong.bind(stamp))


func _take_pong(stamp: int) -> void:
	var trip := float(Time.get_ticks_msec() - stamp)
	if role != Role.CLIENT or trip < 0.0 or trip > 10000.0:
		return
	_ping_samples.append(trip)
	if _ping_samples.size() > PING_SAMPLES:
		_ping_samples.pop_front()
	var sorted := _ping_samples.duplicate()
	sorted.sort()
	ping_ms = sorted[(sorted.size() - 1) / 2]  # with two, the shorter


@rpc("authority", "call_remote", "reliable")
func _h_alive() -> void:
	if role == Role.CLIENT:
		_heard(1)


@rpc("authority", "call_remote", "reliable")
func _h_bye(reason: String) -> void:
	if role == Role.CLIENT:
		_end_reason = reason
