class_name EnemyRoutes
extends Node

## The enemies' way to the base: Tank.exe's "walking distance" map, rule for
## rule (its builder 0x00490eec; docs/enemy_ai_original_spec.md has the
## addresses). One value per cell of the map (the field and its steel border,
## 42 x 32 cells; map cell (x, y) is the field's tile (x - 1, y - 1)): what it
## costs to get from there to the base, spread out from the base's 4 cells.
## A hunting enemy (EnemyTank) sums its 2x2 footprint where it is and one cell
## each way, and takes the cheapest.
##
## What a cell costs to enter: open ground 3, a brick 8 (what's left of one 6),
## a whole hard brick 16 (a damaged one 3, the original's slip), iron 4096,
## super steel 100000; water 6144 more, ice 12. The lines of fire, the columns
## over the base and the rows beside it out to the first iron, steel or water,
## are searched first at 2/3 of that. A free cell squeezed between iron, steel
## or water is closed (a 1-cell gap), and so are the cells of a tank standing
## or crawling, players' too, which then take the highest value round them.
## So hunters drive round what they can't break, through any gap a tank wide,
## however far off, and through bricks, shooting their way.
##
## Three maps: one for most tanks, one for those that cross water (anti-water:
## water costs nothing more and closes nothing) and one for those that don't
## skid (anti-ice: ice costs nothing more). They're rebuilt on the original's
## clock only, never on a wall change: the first at once as a stage starts,
## then the normal map every 1.8 s and the other two every 3.6 s.

## The map's size, its border included.
const W := 42
const H := 32
## A cell nothing reaches, and super steel's cost.
const UNREACHED := 100000
## A footprint summing to this or more is cut off from the base: its tank
## wanders instead (0x00494e50).
const HUNT_LIMIT := 400000
enum Mode { NORMAL, AMPHI, ANTISKID }
## The original's frame, 20 ticks of 0.75 ms: the clock below counts these.
const FRAME_TIME := 0.015
## A tank at or under the original's speed 100 (0.2 of its px a frame) is in
## the way: px/s here.
const SLOW_SPEED := 100.0 / 500.0 * 2.0 / FRAME_TIME
## The base's 4 cells, the map's only sources, and the ring of cells round
## them (map cells).
const BASE_FROM := Vector2i(20, 29)
const RING_FROM := Vector2i(19, 28)
const RING_TO := Vector2i(22, 30)
## Up, right, down, left (the original's table 0x004d2970, as BaseTank.FACINGS).
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## The 8 directions from north round (0x004d2990): a narrow cell is looked for
## east, south-east, south and south-west of a blocked one (entries 2-5), with
## the directions either side of each.
const DIRS8: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

var level_manager: LevelManager = null
var _maps: Array[PackedInt32Array] = []
## The scheduler's count of frames (the original's manager +8).
var _counter := 0
var _clock := 0.0
## Each tank's place a physics frame ago and how fast it went: instance id ->
## [position, px/s].
var _seen: Dictionary = {}


func _ready() -> void:
	for i in 3:
		var m := PackedInt32Array()
		m.resize(W * H)
		m.fill(UNREACHED)
		_maps.append(m)


## A stage starts: the normal map now, the rest on the clock (the original's
## manager reset, 0x00499688).
func restart() -> void:
	_counter = 0
	_clock = 0.0
	_seen.clear()
	_tick()


## [param mode]'s map, as last built: the value of map cell x, y is at
## x * H + y.
func map_for(mode: int) -> PackedInt32Array:
	return _maps[mode]


## The sum of [param m] over the 2x2 footprint whose top-left map cell is
## [param x], [param y] (0x00494be0).
static func footprint(m: PackedInt32Array, x: int, y: int) -> int:
	if x < 0 or y < 0 or x + 1 >= W or y + 1 >= H:
		return UNREACHED * 4
	return m[x * H + y] + m[(x + 1) * H + y] + m[x * H + y + 1] + m[(x + 1) * H + y + 1]


## The map cell of [param at] (a tank's centre, world px), as the original
## rounds a tank's top-left: its footprint's top-left cell.
func cell_of(at: Vector2) -> Vector2i:
	var u := (at - level_manager.global_position) / LevelManager.TILE_SIZE
	return Vector2i(round_even(u.x), round_even(u.y))


## Delphi's Round: halves go to the even neighbour.
static func round_even(v: float) -> int:
	var f := floorf(v)
	var r := v - f
	if r > 0.5 or (r == 0.5 and int(f) % 2 != 0):
		return int(f) + 1
	return int(f)


func _physics_process(delta: float) -> void:
	if level_manager == null or level_manager.net_mirror:
		return
	_note_speeds(delta)
	_clock += delta
	while _clock >= FRAME_TIME:
		_clock -= FRAME_TIME
		_tick()


## The original's scheduler, once a frame (0x00499dd0).
func _tick() -> void:
	_counter -= 1
	if _counter == 180:
		build(Mode.AMPHI)
	elif _counter == 120:
		build(Mode.NORMAL)
	elif _counter == 60:
		build(Mode.ANTISKID)
	elif _counter <= 0:
		build(Mode.NORMAL)
		_counter = 240


func _note_speeds(delta: float) -> void:
	var now := {}
	for node in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies"):
		var tank := node as BaseTank
		if tank == null or not is_instance_valid(tank):
			continue
		var was: Variant = _seen.get(tank.get_instance_id())
		var speed := 0.0
		if was != null and delta > 0.0:
			speed = tank.global_position.distance_to((was as Array)[0]) / delta
		now[tank.get_instance_id()] = [tank.global_position, speed]
	_seen = now


## The tanks in the way: [cell, ...] for each one standing or crawling (the
## original's speed <= 100), players' too, as the map's search finds them.
func _slow_tanks() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for node in get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies"):
		var tank := node as BaseTank
		if tank == null or not is_instance_valid(tank) or tank.is_queued_for_deletion() or tank.health <= 0:
			continue
		if tank.is_flying:
			continue
		var seen: Variant = _seen.get(tank.get_instance_id())
		if seen != null and float((seen as Array)[1]) > SLOW_SPEED:
			continue
		cells.append(cell_of(tank.global_position))
	return cells


## The original's id for what stands on map cell [param x], [param y]: -1
## nothing, 8 grass, 12 burned grass, 24 a brick (28 what's left of one),
## 40-55 a hard brick by its state, 56 iron, 60 super steel, 64 the border,
## 160 a brick hiding an item.
func _wall_id(x: int, y: int) -> int:
	if x == 0 or y == 0 or x == W - 1 or y == H - 1:
		return 64
	var cell := Vector2i(x - 1, y - 1)
	var data: Variant = level_manager._fg_tile_data.get(cell)
	if data == null:
		return -1
	var code: int = (data as Dictionary).get("code", 0)
	match LevelData.get_tile_category(code):
		LevelData.TileCategory.GRASS:
			return 8
		LevelData.TileCategory.BURNED_GRASS:
			return 12
		LevelData.TileCategory.SOFT_BRICK_FULL, LevelData.TileCategory.SOFT_BRICK_PARTIAL:
			if code == 0xA1 or code == 0xAB or code == 0xAC:
				return 160
			return 24 if int(level_manager._brick_damage.get(cell, 0b1111)) == 0b1111 else 28
		LevelData.TileCategory.HARD_BRICK:
			return code - 1  # 40-43 whole, 44-55 by the points it has lost
		LevelData.TileCategory.IRON_BLOCK:
			return 56
		LevelData.TileCategory.SUPER_BLOCK:
			return 60
	return -1


## The original's id for the ground of map cell [param x], [param y]: -1
## nothing, 0 ice, 4 water, 64 the border.
func _ground_id(x: int, y: int) -> int:
	if x == 0 or y == 0 or x == W - 1 or y == H - 1:
		return 64
	var data: Variant = level_manager._bg_tile_data.get(Vector2i(x - 1, y - 1))
	if data == null:
		return -1
	match LevelData.get_tile_category(int((data as Dictionary).get("code", 0))):
		LevelData.TileCategory.ICE:
			return 0
		LevelData.TileCategory.WATER:
			return 4
	return -1


## The original's range test on a 16-bit id: [param lo] to [param lo] + [param n] - 1.
static func _in(id: int, lo: int, n: int) -> bool:
	return ((id - lo) & 0xFFFF) < n


## What entering a cell of [param wall] and [param ground] ids costs
## (0x00490db0): on a line of fire ([param first]) 2/3 of it.
static func cost(wall: int, ground: int, first: bool, mode: int) -> int:
	var c := 3
	if wall < 40:
		if _in(wall, 24, 4):
			c = 8
		elif _in(wall, 28, 12):
			c = 6
	elif _in(wall, 40, 4):
		c = 16
	elif _in(wall, 56, 4):
		c = 4096
	elif _in(wall, 60, 5):
		return UNREACHED
	var later := 0 if first else 1
	if first:
		c = c * 2 / 3
	if mode != Mode.AMPHI and _in(ground, 4, 4):
		return c + later * 2048 + 4096
	if mode != Mode.ANTISKID and _in(ground, 0, 4):
		c += later * 4 + 8
	return c


## Builds [param mode]'s map from the field and its tanks as they are now
## ([param tanks]: the slow ones' cells, or all those in the way), as the
## original's builder does, step by step: its queues are first in, first out,
## and the order things are met in matters.
func build(mode: int, tanks: Variant = null) -> void:
	var wall := PackedInt32Array()
	var ground := PackedInt32Array()
	wall.resize(W * H)
	ground.resize(W * H)
	for x in W:
		for y in H:
			wall[x * H + y] = _wall_id(x, y)
			ground[x * H + y] = _ground_id(x, y)
	var slow: Array[Vector2i] = _slow_tanks() if tanks == null else tanks
	_maps[mode] = make_map(wall, ground, mode, slow)


## The builder itself, on the original's ids ([param wall] and [param ground],
## x * H + y) and the top-left cells of the tanks in the way ([param tanks]).
static func make_map(wall: PackedInt32Array, ground: PackedInt32Array, mode: int,
		tanks: Array[Vector2i]) -> PackedInt32Array:
	var m := PackedInt32Array()
	m.resize(W * H)
	var blocked := PackedByteArray()
	blocked.resize(W * H)
	var q1 := _Queue.new()  # the lines of fire
	var q2 := _Queue.new()  # the rest
	var q3 := _Queue.new()  # tanks
	var q4 := _Queue.new()  # narrow cells
	# 1: what's blocked (iron, super steel, the border; water but for the
	# anti-water map), the border, the base and the ring round it.
	for y in H:
		for x in W:
			var i := x * H + y
			var b := _in(wall[i], 56, 9) or (mode != Mode.AMPHI and _in(ground[i], 4, 4))
			blocked[i] = 1 if b else 0
			if x == 0 or x == W - 1 or y == 0 or y == H - 1:
				m[i] = -4
			elif x >= BASE_FROM.x and x <= BASE_FROM.x + 1 and y >= BASE_FROM.y and y <= BASE_FROM.y + 1:
				_push(m, q1, x, y, 0)
			elif x >= RING_FROM.x and x <= RING_TO.x and y >= RING_FROM.y and y <= RING_TO.y:
				m[i] = -1
			else:
				m[i] = -2
	# 2: the lines of fire up the columns over the base,
	for x in range(RING_FROM.x, RING_TO.x + 1):
		for y in range(RING_FROM.y - 1, 0, -1):
			if blocked[x * H + y]:
				break
			m[x * H + y] = -1
	# 3: and along the rows beside it.
	for y in range(RING_FROM.y, RING_TO.y + 1):
		for x in range(RING_FROM.x - 1, 0, -1):
			if blocked[x * H + y]:
				break
			m[x * H + y] = -1
		for x in range(RING_TO.x + 1, W - 1):
			if blocked[x * H + y]:
				break
			m[x * H + y] = -1
	# 4: narrow cells: a free cell beside a blocked one, with another blocked
	# one beyond it or either side of it.
	for y in range(0, H - 2):
		for x in range(2, W - 2):
			if x >= RING_FROM.x and x <= RING_TO.x and y >= RING_FROM.y and y <= RING_TO.y:
				continue
			if not blocked[x * H + y]:
				continue
			for k in range(2, 6):
				var e: Vector2i = DIRS8[k]
				var n := Vector2i(x, y) + e
				if _blocked_at(blocked, n):
					continue
				if _blocked_at(blocked, n + e) or _blocked_at(blocked, n + DIRS8[k - 1]) \
						or _blocked_at(blocked, n + DIRS8[k + 1]):
					_push(m, q4, n.x, n.y, -6)
	# 5: the tanks in the way.
	for t in tanks:
		for c: Vector2i in [t, t + Vector2i(1, 0), t + Vector2i(1, 1), t + Vector2i(0, 1)]:
			if c.x >= 0 and c.y >= 0 and c.x < W and c.y < H:
				_push(m, q3, c.x, c.y, -5)
	# 6: out from the base along the lines of fire, at 2/3 the cost; the first
	# step off them goes to the rest.
	while not q1.empty():
		var item := q1.pop()
		if m[item.x * H + item.y] != item.z:
			continue
		for d in DIRS:
			var n := Vector2i(item.x, item.y) + d
			var cur := m[n.x * H + n.y]
			if cur < -2:
				continue
			var c := cost(wall[n.x * H + n.y], ground[n.x * H + n.y], true, mode)
			if cur >= 0 and cur <= item.z + c:
				continue
			if cur >= -1:
				_push(m, q1, n.x, n.y, item.z + c)
			else:
				_push(m, q2, n.x, n.y, item.z + c)
	# 7: everything else.
	while not q2.empty():
		var item := q2.pop()
		if item.z != -1 and m[item.x * H + item.y] != item.z:
			continue
		for d in DIRS:
			var n := Vector2i(item.x, item.y) + d
			var cur := m[n.x * H + n.y]
			if cur < -2:
				continue
			var c := cost(wall[n.x * H + n.y], ground[n.x * H + n.y], false, mode)
			if cur >= 0 and cur <= item.z + c:
				continue
			_push(m, q2, n.x, n.y, item.z + c)
	# 8: the border.
	for x in W:
		m[x * H] = UNREACHED
		m[x * H + H - 1] = UNREACHED
	for y in range(1, H - 1):
		m[y] = UNREACHED
		m[(W - 1) * H + y] = UNREACHED
	# 9: a tank's cells take the highest value met going out each way.
	while not q3.empty():
		var item := q3.pop()
		var best := 0
		for d in DIRS:
			var v := _first_value(m, Vector2i(item.x, item.y), d)
			if best < v and v < UNREACHED:
				best = v
		m[item.x * H + item.y] = best if best > 0 else UNREACHED
	# 10: a narrow cell takes the average of the first values each way, the
	# walls' included.
	while not q4.empty():
		var item := q4.pop()
		var total := 0
		for d in DIRS:
			total += _first_value(m, Vector2i(item.x, item.y), d)
		m[item.x * H + item.y] = total / 4
	# 11: whatever nothing reached.
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if m[x * H + y] < 0:
				m[x * H + y] = UNREACHED
	return m


static func _blocked_at(blocked: PackedByteArray, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return true  # off the map: the border's
	return blocked[c.x * H + c.y] != 0


## The first value of 0 or more going [param d] from next to [param from].
static func _first_value(m: PackedInt32Array, from: Vector2i, d: Vector2i) -> int:
	var c := from + d
	while c.x >= 0 and c.y >= 0 and c.x < W and c.y < H and m[c.x * H + c.y] < 0:
		c += d
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return UNREACHED
	return m[c.x * H + c.y]


## Writes [param v] to map cell [param x], [param y] and queues it (0x00490ea4).
static func _push(m: PackedInt32Array, q: _Queue, x: int, y: int, v: int) -> void:
	m[x * H + y] = v
	q.push(Vector3i(x, y, v))


## First in, first out (the original's TQueue).
class _Queue:
	var _items: Array[Vector3i] = []
	var _head := 0

	func push(item: Vector3i) -> void:
		_items.append(item)

	func pop() -> Vector3i:
		_head += 1
		return _items[_head - 1]

	func empty() -> bool:
		return _head >= _items.size()
