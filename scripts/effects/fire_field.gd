class_name FireField
extends RefCounted

## A growing/shrinking square of ground fire, owned and ticked by LevelManager.
## Implements the fire-weapon area rules:
##  - Rule 1: a fresh field is size 4 (4x4 minus the 4 corners = 12 tiles).
##  - Rule 2: it burns BURN_TIME seconds, then its outer ring winks out randomly
##    over DECAY_TIME (the "6th second").
##  - Rule 3: a fire bullet landing on the burning area grows it by one ring
##    (5x5-4, 6x6-4, ... up to 8x8-4 = 60); each burn cycle that ends with no new
##    fire shrinks it by one ring, until it drops below size 4 and disappears.
## Tiles themselves are GroundFire nodes parented into the level's terrain layer.

const MIN_SIZE: int = 4
const MAX_SIZE: int = 8
const BURN_TIME: float = 5.0    # steady burn before a ring decays (rule 2)
const DECAY_TIME: float = 1.0   # the "6th second" ragged fade of a ring
const TILE_ARM: float = 0.05

var center: Vector2i
var size: int = MIN_SIZE
var from_player: bool = true
var owner_id: int = -1  # the player whose shell lit or last fed it (-1: an enemy's)

var _lm: LevelManager
var _burn_timer: float = BURN_TIME
var _dead: bool = false
var _tiles: Dictionary = {}  # offset (Vector2i) -> GroundFire node

# offsets_for(size) cache: size -> Array[Vector2i]
static var _offset_cache: Dictionary = {}


func _init(p_center: Vector2i, p_from_player: bool, p_lm: LevelManager, p_owner: int = -1) -> void:
	center = p_center
	from_player = p_from_player
	owner_id = p_owner
	_lm = p_lm
	for off in offsets_for(MIN_SIZE):
		_add_tile(off)


## A new fire bullet reached this burning area (rule 3): grow one ring and
## refresh the burn timer so continued fire keeps it alive and expanding.
func feed(p_from_player: bool, p_owner: int = -1) -> void:
	from_player = p_from_player
	owner_id = p_owner
	if size < MAX_SIZE:
		var next := size + 1
		for off in _ring(next):
			_add_tile(off)
		size = next
	_burn_timer = BURN_TIME


func update(delta: float) -> void:
	if _dead:
		return
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_shrink()


func is_dead() -> bool:
	return _dead


## Immediately drop every tile (used on stage reload).
func force_clear() -> void:
	for off in _tiles.keys():
		var tile = _tiles[off]
		_unindex(center + off)
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()
	_dead = true


func _shrink() -> void:
	var target := size - 1
	# Outer ring = tiles present at the current size but not at the smaller size.
	for off in _ring(size):
		_remove_tile(off)
	size = target
	if size < MIN_SIZE:
		_die()
	else:
		_burn_timer = BURN_TIME


func _die() -> void:
	# Whatever remains fades out raggedly, then the field is done.
	for off in _tiles.keys():
		_remove_tile(off)
	_dead = true


func _add_tile(off: Vector2i) -> void:
	var world: Vector2i = center + off
	if not _lm._fire_tile_ignitable(world):
		return
	# Green grass in the patch burns as a neutral grass fire (which then spreads),
	# not as a side-based weapon-fire tile.
	if _lm._is_green_grass(world):
		_lm.ignite_grass(world, from_player)
		return
	if _lm._fire_index.has(world) or _lm._grass_index.has(world):
		return  # already burning (weapon fire or grass fire) — don't stack tiles
	var tile = _lm._spawn_fire_tile(world, from_player, TILE_ARM, owner_id)
	if tile == null:
		return
	_lm._fire_index[world] = self
	_tiles[off] = tile
	# The weapon fire's edge also sets adjacent grass alight (the wildfire seed).
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_lm.ignite_grass(world + d, from_player)


func _remove_tile(off: Vector2i) -> void:
	if not _tiles.has(off):
		return
	var tile = _tiles[off]
	_unindex(center + off)
	if is_instance_valid(tile):
		tile.start_decay(randf() * DECAY_TIME)
	_tiles.erase(off)


func _unindex(world: Vector2i) -> void:
	if _lm._fire_index.get(world) == self:
		_lm._fire_index.erase(world)


## The set of offsets added when growing to [param s] (its outer frame).
func _ring(s: int) -> Array:
	var outer := offsets_for(s)
	var inner := {}
	for o in offsets_for(s - 1):
		inner[o] = true
	var result: Array = []
	for o in outer:
		if not inner.has(o):
			result.append(o)
	return result


## Offsets of an s x s block centred on the field, minus the 4 corner tiles.
## Concentric across sizes so growth adds a clean frame each step.
static func offsets_for(s: int) -> Array:
	if _offset_cache.has(s):
		return _offset_cache[s]
	var result: Array = []
	if s >= 1:
		var lo: int = -int(floor((s - 1) / 2.0))
		var hi: int = lo + s - 1
		for dy in range(lo, hi + 1):
			for dx in range(lo, hi + 1):
				var is_corner := (dx == lo or dx == hi) and (dy == lo or dy == hi)
				if not is_corner:
					result.append(Vector2i(dx, dy))
	_offset_cache[s] = result
	return result
