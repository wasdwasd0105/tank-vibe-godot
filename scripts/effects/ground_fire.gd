class_name GroundFire
extends Node2D

## One burning tile: Tank.exe's TFireSprite (VMT 0x0049035c), rule for rule
## (docs/fire_weapon_original_spec.md). LevelManager lays them (a fire shell's
## patch, the spread of a big fire, burning grass) and burns the tanks on them;
## each fire runs its own clock, as the original's DoMove (0x00497710), in this
## order every frame:
##   - a fire of a side (a player's or the enemies') with strength 1 or more
##     and fuel of 7000 or more spreads, every 600 - 100 * strength ticks
##     (LevelManager.spread_fire);
##   - once, 500-999 ticks after it starts, its terrain step: the grass beside
##     it burns, and a side's fire melts the ice under itself
##     (LevelManager.fire_terrain_step);
##   - it arms: only then does it burn tanks (and show, but for grass fire);
##   - it burns its fuel, and goes out when that's gone.
## The original counts in ticks of 0.75 ms; so do these.

const TILE_SIZE: int = 32
## The original's tick, s.
const TICK := 0.00075
## A fire spreads only with this much fuel or more.
const SPREAD_FUEL := 7000.0
## Arming, s: 100 ticks (from its 6th frame); 50 for the inner 2x2 of a patch.
const ARM := 0.09
const ARM_INNER := 0.06
const ANIM_FRAME_TIME: float = 0.05 # 8-frame loop = 400ms
const ANIM_FRAMES: int = 8
## Grass fire draws over the tanks and over the grass (its TreeLayer, z 10),
## as the original's Z 9 over its wall layer's 8; a side's under them all.
const GRASS_Z := 11

## Whose fire: 1 a player's, 0 the enemies', -1 nobody's (burning grass, which
## burns everyone). As the original's owner field: players 1 and 2, enemies 0.
var side := 1
var from_player: bool:
	get:
		return side > 0
var is_grass_fire: bool:
	get:
		return side < 0
## The player whose shell lit it, for the kill (-1: the enemies', or nobody's).
var owner_id := -1
var strength := 0
## Ticks of burning left.
var fuel := 0.0
var tile_pos: Vector2i = Vector2i.ZERO
## In its side's grid (LevelManager): a patch's tiles are; a big fire's spread
## and burning grass never are, as in the original.
var registered := false
## The order fires were lit in: a tank on several is burned by the first.
var serial := 0

var _level_manager: LevelManager = null
var _terrain := 0.0   # ticks till its terrain step
var _terrain_done := false
var _spread := 0.0    # ticks till its next spread, counted while it can spread
var _arm := ARM       # s till it burns tanks
var _armed := false
var _show := ARM      # s till it shows (a client's copy, and grass fire at once)
var _anim_timer: float = 0.0
var _frame: int = 0

var _sprite: Sprite2D = null
var _frames: Array = []   # this fire's row of textures

# The _B_Fire sheet has 3 rows: row 1 = burning grass (red, nobody's), row 2 =
# the enemies' (orange), row 3 = the players' (yellow).
static var _row_textures: Dictionary = {}  # int row -> Array[Texture2D]
const FRAME_PATH_FMT: String = "res://assets/sprites/effects/ground_fire/ground_fire_r%d_f%d.png"


## Its sprite row (the original's SetOwner, 0x00497b34).
func _current_row() -> int:
	if is_grass_fire:
		return 1
	return 3 if from_player else 2


## A fire of [param p_side] on [param p_tile] with [param p_fuel] ticks, armed
## after [param arm] s, its flames at frame [param frame] of their loop; shown
## at once if [param shown] (burning grass), else when armed.
func setup(lm: LevelManager, p_tile: Vector2i, p_side: int, p_owner: int, p_strength: int, p_fuel: float,
		arm: float, frame: int, shown: bool = false) -> void:
	_level_manager = lm
	tile_pos = p_tile
	side = p_side
	owner_id = p_owner
	strength = p_strength
	fuel = p_fuel
	_arm = arm
	_show = 0.0 if shown else arm
	_frame = posmod(frame, ANIM_FRAMES)
	_terrain = float(randi_range(0, 499) + 500)
	_spread = float(randi_range(0, 499) + 250)


## Another shell of its side lands on it (the original's restack, 0x00493cb9):
## its strength and owner become the shell's, and fresh fuel is pumped in.
func restack(p_strength: int, p_owner: int) -> void:
	strength = p_strength
	owner_id = p_owner
	var fresh := LevelManager.fresh_fire_fuel(strength)
	var boost := fresh * (strength + 3) / 9
	fuel = float(fresh) if boost >= fuel else fuel + boost


func is_armed() -> bool:
	return _armed


func _ready() -> void:
	add_to_group(NetWorld.GROUP)
	# A side's fire draws above the floor but BELOW tanks: fire lives in the
	# Playfield subtree, which renders before the Entities (tank) subtree at the
	# same z_index. Burning grass draws over them and the grass.
	z_index = GRASS_Z if is_grass_fire else 0
	_frames = _load_textures(_current_row())
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not _frames.is_empty():
		_frame %= _frames.size()
		var tex0 := _frames[_frame] as Texture2D
		_sprite.texture = tex0
		var tex_size := tex0.get_size()
		if tex_size.x > 0:
			_sprite.scale = Vector2(TILE_SIZE / tex_size.x, TILE_SIZE / tex_size.y)
	add_child(_sprite)
	visible = _show <= 0.0


## Its own clock (the host's): spread, terrain step, arming, fuel.
func _physics_process(delta: float) -> void:
	if Net.is_client() or _level_manager == null:
		return
	var ticks := delta / TICK
	if side >= 0 and strength >= 1 and fuel >= SPREAD_FUEL:
		_spread -= ticks
		if _spread < 0.0:
			_spread += 600.0 - 100.0 * strength
			_level_manager.spread_fire(self)
	if not _terrain_done:
		_terrain -= ticks
		if _terrain <= 0.0:
			_terrain_done = true
			_level_manager.fire_terrain_step(self)
	if not _armed:
		_arm -= delta
		_armed = _arm <= 0.0
	if fuel > 0.0:
		fuel -= ticks
	else:
		_level_manager.fire_out(self)
		queue_free()


func _process(delta: float) -> void:
	if not visible:
		_show -= delta
		if _show <= 0.0:
			visible = true
		return
	_anim_timer += delta
	if _anim_timer >= ANIM_FRAME_TIME and not _frames.is_empty():
		_anim_timer -= ANIM_FRAME_TIME
		_frame = (_frame + 1) % _frames.size()
		_sprite.texture = _frames[_frame] as Texture2D


## Its flames' frame now (a spread child starts from its parent's).
func anim_frame() -> int:
	return _frame


# --- Online (NetWorld): a burning tile is its row (whose fire), how long until
# it shows, and where its flames are in their loop. ---

func net_type() -> int:
	return NetWorld.T_FIRE

func net_spawn_args() -> Array:
	return [_current_row(), maxf(_show, 0.0) if not visible else 0.0, _frame, _anim_timer]

func net_state() -> Array:
	return [global_position.x, global_position.y]

func net_setup(args: Array) -> void:
	var row := int(args[0])
	side = -1 if row == 1 else (1 if row == 3 else 0)
	_show = float(args[1])
	_frame = int(args[2])
	_anim_timer = float(args[3])

func net_apply(_state: Array) -> void:
	pass


static func _load_textures(row: int) -> Array:
	if _row_textures.has(row):
		return _row_textures[row]
	var frames: Array = []
	for f in range(1, ANIM_FRAMES + 1):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(FRAME_PATH_FMT % [row, f])) != OK:
			continue
		img.convert(Image.FORMAT_RGBA8)
		frames.append(ImageTexture.create_from_image(img))
	_row_textures[row] = frames
	return frames
