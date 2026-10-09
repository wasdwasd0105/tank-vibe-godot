class_name NetWorld
## What the host's world streams to its clients (NetHostWorld builds it,
## NetClientWorld shows it): the kinds of entity, the one-shot events and the
## encoding the two share. docs/network_design.md section 5.
##
## A snapshot is var_to_bytes of an Array:
##   [SNAP_SEQ] its number, [SNAP_EPOCH] the host's game scene it's from (a new
##   stage is a new one), [SNAP_TIME] the host's real clock in ms,
##   [SNAP_FLAGS] FLAG_FULL (a whole world: the client starts over from it),
##   [SNAP_MAP] the whole map (full snapshots only),
##   [SNAP_SPAWNS] new entities: [nid, type, spawn args, state] each,
##   [SNAP_UPDATES] changed entity state (encode_updates),
##   [SNAP_REMOVED] entities gone, [SNAP_TILES] changed map cells,
##   [SNAP_GAME] changed game-state values, [SNAP_EVENTS] one-shot events.
##
## Every entity's state is an Array of ints and floats whose first two are its
## global position; update values keep the type the spawn gave them.

const SNAP_SEQ := 0
const SNAP_EPOCH := 1
const SNAP_TIME := 2
const SNAP_FLAGS := 3
const SNAP_MAP := 4
const SNAP_SPAWNS := 5
const SNAP_UPDATES := 6
const SNAP_REMOVED := 7
const SNAP_TILES := 8
const SNAP_GAME := 9
const SNAP_EVENTS := 10
const SNAP_SIZE := 11

const FLAG_FULL := 1

# --- Entity types: which scene or script a client builds, and where. ---
const T_PLAYER := 1
const T_ENEMY := 2
const T_BULLET := 3
const T_COOKIE := 4
const T_MINE := 5
const T_FIRE := 6

## type -> [scene or script path, parent: "players", "enemies", "bullets",
## "powerups" (the game's containers) or "terrain" (the playfield's layer)]
const TYPES: Dictionary = {
	T_PLAYER: ["res://scenes/tanks/player_tank.tscn", "players"],
	T_ENEMY: ["res://scenes/tanks/enemy_tank.tscn", "enemies"],
	T_BULLET: ["res://scenes/tanks/bullet.tscn", "bullets"],
	T_COOKIE: ["res://scenes/powerups/powerup.tscn", "powerups"],
	T_MINE: ["res://scripts/effects/mine.gd", "terrain"],
	T_FIRE: ["res://scripts/effects/ground_fire.gd", "terrain"],
}

## The group every replicated node joins; its script answers net_type(),
## net_spawn_args(), net_state(), and on a client net_setup(args) and
## net_apply(state).
const GROUP := &"net"

# --- One-shot events: [kind, args...] ---
const EV_SOUND := 1         # [key]
const EV_MUSIC := 2         # [key]
const EV_STOP_MUSIC := 3    # []
const EV_HIT := 4           # [frames key, x, y]: HitEffect ("tank" or a shot style)
const EV_SPAWN_BURST := 5   # [x, y]
const EV_EXPLOSION := 6     # [x, y, scale]: the built-in burst (explosion.tscn)
const EV_BLAST := 7         # [tile x, tile y, level, kind (blast_kind)]: ExplosionBlast's picture, its 8x8 from that tile
const EV_KILL_TEXT := 8     # [points, combo, x, y]
const EV_PICKUP_TEXT := 9   # [cookie type, x, y]
## An EV_BLAST's kind: the players' (else the enemies'), a mine-thrown tank's
## landing (everyone's), a mine a player's bomb set off (sparing the players).
const BLAST_PLAYERS := 1
const BLAST_NEUTRAL := 2
const BLAST_SPARES_PLAYERS := 4


## The kind of a blast (EV_BLAST) [param from_player], [param neutral],
## [param spare_players] (ExplosionBlast.setup).
static func blast_kind(from_player: bool, neutral: bool, spare_players: bool) -> int:
	return (BLAST_PLAYERS if from_player else 0) | (BLAST_NEUTRAL if neutral else 0) \
			| (BLAST_SPARES_PLAYERS if spare_players else 0)

# --- Game-state keys (SNAP_GAME) ---
const G_STAGE := "stage"
const G_PLAYED := "played"
const G_ENEMIES := "enemies"
const G_ACTIVE := "active"
const G_DISABLED := "disabled"
const G_LIVES := "lives"
const G_SCORES := "scores"
const G_SPEED := "speed"
const G_WEAPON := "weapon"
const G_WEAPON2 := "weapon2"
const G_AMMO := "ammo"
const G_HP := "hp"
const G_ADDONS := "addons"
const G_CHAINS := "chains"
const G_DIFFICULTY := "difficulty"
const G_ENEMIES_FROZEN := "enemies_frozen"
const G_PLAYERS_FROZEN := "players_frozen"
const G_HOLD_LEFT := "hold_left"
const G_COUNTDOWN := "countdown"
const G_DEAD_TIMERS := "dead_timers"
const G_BASE_DEAD := "base_dead"
const G_BASE_GUARD := "base_guard"
const G_PAUSED := "paused"
const G_SPEED_SCALE := "time_scale"
const G_OVERLAY := "overlay"       # StageOverlay.net_screen(): the screen and its draws
const G_OVERLAY_T := "overlay_t"   # the screen's own clock
## Keys whose numbers glide between snapshots on a client.
const LERP_GAME_KEYS: Array[String] = [G_OVERLAY_T]


# =====================================================================
# Update encoding: [u16 nid][varint mask] then each changed value, an int as a
# zigzag varint and a float as 32 bits. The client decodes against the state it
# already holds, which gives each value's type.
# =====================================================================

static func put_varint(buf: StreamPeerBuffer, value: int) -> void:
	var v := value
	for i in 10:
		var byte := v & 0x7f
		v = (v >> 7) & 0x01ffffffffffffff  # as unsigned
		if v == 0:
			buf.put_u8(byte)
			return
		buf.put_u8(byte | 0x80)


static func get_varint(buf: StreamPeerBuffer) -> int:
	var value := 0
	var shift := 0
	while buf.get_position() < buf.get_size() and shift < 64:
		var byte := buf.get_u8()
		value |= (byte & 0x7f) << shift
		if byte & 0x80 == 0:
			break
		shift += 7
	return value


static func put_zigzag(buf: StreamPeerBuffer, value: int) -> void:
	put_varint(buf, (value << 1) ^ (value >> 63))


static func get_zigzag(buf: StreamPeerBuffer) -> int:
	var v := get_varint(buf)
	return (v >> 1) ^ -(v & 1)


## Adds entity [param nid]'s changed values: those of [param state] that differ
## from [param before] (the state the client holds). Returns false, writing
## nothing, when none did.
static func put_update(buf: StreamPeerBuffer, nid: int, state: Array, before: Array) -> bool:
	var mask := 0
	for i in state.size():
		if i >= before.size() or not _same(state[i], before[i]):
			mask |= 1 << i
	if mask == 0:
		return false
	buf.put_u16(nid)
	put_varint(buf, mask)
	for i in state.size():
		if mask & (1 << i):
			if state[i] is float:
				buf.put_float(state[i])
			else:
				put_zigzag(buf, int(state[i]))
	return true


## Reads the updates in [param bytes] against [param states] (nid -> state
## Array, the client's): {nid: {index: value}}. Unknown nids end the read (the
## rest can't be sized), which only a desync causes.
static func read_updates(bytes: PackedByteArray, states: Dictionary) -> Dictionary:
	var out := {}
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	while buf.get_position() + 2 <= buf.get_size():
		var nid := buf.get_u16()
		var mask := get_varint(buf)
		var state: Variant = states.get(nid)
		if state == null:
			break
		var changed := {}
		for i in (state as Array).size():
			if mask & (1 << i):
				changed[i] = buf.get_float() if (state as Array)[i] is float else get_zigzag(buf)
		out[nid] = changed
	return out


static func _same(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b
