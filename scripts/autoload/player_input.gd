extends Node
## Where every read of a player's controls goes: which way they push and their
## two fire buttons. The game asks by tank (0 is P1's tank, 1 is P2's).
##
## Offline, tank 0 answers to the P1 controls and tank 1 to the P2 controls, as
## they always have. Online, a tank answers to whoever holds its seat: one of
## this machine's two local players (its P1 or its P2 controls), or a player on
## a client, through the latest input message from them (Net sends and applies
## those). An empty seat pushes nothing.
##
## A controller is one local player on one machine, keyed peer * 2 + slot: the
## multiplayer peer id (1 is the host, and offline everything is 1) and the slot,
## 0 for that machine's P1 controls, 1 for its P2 controls.

const BUTTONS: Array[String] = ["shoot", "shoot2"]
const MOVES: Array[String] = ["up", "down", "left", "right"]
const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const NO_SEAT := -1
## This machine's own two controllers, as the host (or offline).
const LOCAL_P1 := 2  # peer 1, slot 0
const LOCAL_P2 := 3  # peer 1, slot 1

signal seats_changed

## seats[tank] = the controller driving it, or NO_SEAT.
var seats: Array[int] = [LOCAL_P1, LOCAL_P2]

## Remote controllers' latest state, by controller key.
var _remote: Dictionary = {}


class RemotePad:
	var direction: int = -1  # index into DIRECTIONS; -1 pushes nothing
	var held: Array[bool] = [false, false]
	## The client's press counters (0-255, wrapping) and where each frame kind
	## last caught up with them: a press is "just" pressed for one physics frame
	## and one idle frame, however soon it was let go.
	var presses: Array[int] = [0, 0]
	var seen_physics: Array[int] = [0, 0]
	var seen_idle: Array[int] = [0, 0]
	var just_physics: Array[bool] = [false, false]
	var just_idle: Array[bool] = [false, false]
	## Lag compensation: the client runs its own tank itself (its setting on),
	## and the tank as it drives it there, ahead of the host by the trip across
	## (PlayerTank._follow_client goes after it): where it is, its facing (an
	## index into BaseTank.FACINGS), whether it drives, and the last correction
	## it has taken (PlayerTank.net_override).
	var report_predicts := false
	var has_report := false
	var report_position := Vector2.ZERO
	var report_facing := 0
	var report_moving := false
	var report_override := 0


func _ready() -> void:
	# Ahead of the tanks each frame, and on through a pause, like Input itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	process_physics_priority = -100


func _process(_delta: float) -> void:
	for pad: RemotePad in _remote.values():
		for b in 2:
			pad.just_idle[b] = pad.presses[b] != pad.seen_idle[b]
			pad.seen_idle[b] = pad.presses[b]


func _physics_process(_delta: float) -> void:
	for pad: RemotePad in _remote.values():
		for b in 2:
			pad.just_physics[b] = pad.presses[b] != pad.seen_physics[b]
			pad.seen_physics[b] = pad.presses[b]


# =====================================================================
# Controllers
# =====================================================================

static func controller_key(peer: int, slot: int) -> int:
	return peer * 2 + slot


static func controller_peer(key: int) -> int:
	return key >> 1


static func controller_slot(key: int) -> int:
	return key & 1


## True for this machine's own controllers (the host's, or offline).
static func is_local(key: int) -> bool:
	return controller_peer(key) == 1


## The input action prefix of local slot [param slot]: "p1_" or "p2_".
static func action_prefix(slot: int) -> String:
	return "p%d_" % (slot + 1)


# =====================================================================
# Reading a tank's controls
# =====================================================================

## The way tank [param tank]'s driver pushes: the strongest of the four
## directions, so a stick held off the diagonal drives along its main axis.
## Keys all push at full strength, and a tie keeps the order up, down, left,
## right.
func move_direction(tank: int) -> Vector2:
	var key := seats[tank]
	if key == NO_SEAT:
		return Vector2.ZERO
	if is_local(key):
		return local_direction(controller_slot(key))
	var pad: RemotePad = _remote.get(key)
	if pad == null or pad.direction < 0:
		return Vector2.ZERO
	return DIRECTIONS[pad.direction]


## True while tank [param tank]'s driver holds fire button [param button]
## (0 fire 1, 1 fire 2).
func is_held(tank: int, button: int) -> bool:
	var key := seats[tank]
	if key == NO_SEAT:
		return false
	if is_local(key):
		return Input.is_action_pressed(action_prefix(controller_slot(key)) + BUTTONS[button])
	var pad: RemotePad = _remote.get(key)
	return pad != null and pad.held[button]


## True on the frame tank [param tank]'s driver pressed fire button
## [param button]: the physics frame when asked from physics, else the idle one.
func is_just_pressed(tank: int, button: int) -> bool:
	var key := seats[tank]
	if key == NO_SEAT:
		return false
	return _controller_just_pressed(key, button)


## True while tank [param tank]'s driver holds either fire button.
func is_fire_held(tank: int) -> bool:
	return is_held(tank, 0) or is_held(tank, 1)


# =====================================================================
# Fire presses, for joining
# =====================================================================

## The controllers that pressed a fire button this frame, seated or not:
## [{"key": controller, "seat": the tank it drives or NO_SEAT}]. Offline that
## is the P1 and P2 controls; online, the host's own two and every client's.
func fire_presses() -> Array:
	var presses: Array = []
	for key in _controllers():
		if _controller_just_pressed(key, 0) or _controller_just_pressed(key, 1):
			presses.append({"key": key, "seat": seats.find(key)})
	return presses


## The tank controller [param key] would take by pressing fire: its own
## number's tank if free, else the other one; only a seat [param may_drive]
## allows (a Callable(controller, tank) -> bool). NO_SEAT when neither is free.
func free_seat_for(key: int, may_drive: Callable) -> int:
	var slot := controller_slot(key)
	for tank: int in [slot, 1 - slot]:
		if seats[tank] == NO_SEAT and may_drive.call(key, tank):
			return tank
	return NO_SEAT


func set_seat(tank: int, key: int) -> void:
	if seats[tank] == key:
		return
	# A controller drives one tank at a time.
	if key != NO_SEAT:
		var other := seats.find(key)
		if other >= 0 and other != tank:
			seats[other] = NO_SEAT
	seats[tank] = key
	seats_changed.emit()


func clear_seat(tank: int) -> void:
	set_seat(tank, NO_SEAT)


## Offline seating: P1's controls drive tank 0 and P2's drive tank 1.
func reset_to_local() -> void:
	_remote.clear()
	seats = [LOCAL_P1, LOCAL_P2]
	seats_changed.emit()


## Online seating: nobody drives either tank until they take it.
func reset_to_empty() -> void:
	_remote.clear()
	seats = [NO_SEAT, NO_SEAT]
	seats_changed.emit()


# =====================================================================
# Remote controllers (the host's side of the clients' input messages)
# =====================================================================

## Stores client [param peer]'s local player [param slot]: pushing
## [param direction] (-1 none, else an index into DIRECTIONS), holding
## [param held] fire buttons, with its press counters [param presses].
func set_remote(peer: int, slot: int, direction: int, held: Array, presses: Array) -> void:
	var key := controller_key(peer, slot)
	var pad: RemotePad = _remote.get(key)
	if pad == null:
		pad = RemotePad.new()
		# A controller's presses count from when it's first heard, not from 0.
		for b in 2:
			pad.seen_physics[b] = int(presses[b])
			pad.seen_idle[b] = int(presses[b])
		_remote[key] = pad
	pad.direction = direction if direction >= -1 and direction < DIRECTIONS.size() else -1
	for b in 2:
		pad.held[b] = bool(held[b])
		pad.presses[b] = int(presses[b]) & 0xff


## Client [param peer]'s local player [param slot]'s tank, where it drives it on
## the client ([param has] false: it doesn't drive one there just now), and
## whether that client runs its own tank at all ([param predicts]: its lag
## compensation is on).
func set_remote_report(peer: int, slot: int, has: bool, predicts: bool, position: Vector2, facing: int,
		moving: bool, override: int) -> void:
	var pad: RemotePad = _remote.get(controller_key(peer, slot))
	if pad == null:
		return
	pad.report_predicts = predicts
	pad.has_report = has
	pad.report_position = position
	pad.report_facing = clampi(facing, 0, 3)
	pad.report_moving = moving
	pad.report_override = override & 0xff


## True when a player on a client drives tank [param tank]: the host's copy of
## it follows that client's own (PlayerTank._follow_client).
func is_remote_seat(tank: int) -> bool:
	var key := seats[tank]
	return key != NO_SEAT and not is_local(key)


## True when the client driving tank [param tank] runs it itself, ahead of the
## host (its lag compensation on): the host's copy follows its reports. Else
## the client's keys drive the copy, as they come.
func remote_predicts(tank: int) -> bool:
	if not is_remote_seat(tank):
		return false
	var pad: RemotePad = _remote.get(seats[tank])
	return pad != null and pad.report_predicts


## Where the client driving tank [param tank] has it: its pad with the report,
## or null (no word of it yet, or not a client's tank).
func remote_report(tank: int) -> RemotePad:
	if not is_remote_seat(tank):
		return null
	var pad: RemotePad = _remote.get(seats[tank])
	return pad if pad != null and pad.has_report else null


## Forgets client [param peer]'s controllers and frees the seats they held.
## Returns the tanks freed.
func remove_peer(peer: int) -> Array[int]:
	var freed: Array[int] = []
	for slot in 2:
		var key := controller_key(peer, slot)
		_remote.erase(key)
		var tank := seats.find(key)
		if tank >= 0:
			seats[tank] = NO_SEAT
			freed.append(tank)
	if not freed.is_empty():
		seats_changed.emit()
	return freed


# =====================================================================
# This machine's own controls
# =====================================================================

## Local slot [param slot]'s push (see move_direction).
static func local_direction(slot: int) -> Vector2:
	var prefix := action_prefix(slot)
	var best := Vector2.ZERO
	var best_strength := 0.0
	for i in MOVES.size():
		var strength := Input.get_action_strength(prefix + MOVES[i])
		if strength > best_strength:
			best_strength = strength
			best = DIRECTIONS[i]
	return best


## Local slot [param slot]'s push as an index into DIRECTIONS, -1 for none.
static func local_direction_index(slot: int) -> int:
	return DIRECTIONS.find(local_direction(slot))


func _controllers() -> Array[int]:
	var keys: Array[int] = [LOCAL_P1, LOCAL_P2]
	for key: int in _remote:
		keys.append(key)
	return keys


func _controller_just_pressed(key: int, button: int) -> bool:
	if is_local(key):
		return Input.is_action_just_pressed(action_prefix(controller_slot(key)) + BUTTONS[button])
	var pad: RemotePad = _remote.get(key)
	if pad == null:
		return false
	return pad.just_physics[button] if Engine.is_in_physics_frame() else pad.just_idle[button]
