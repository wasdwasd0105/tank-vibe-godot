class_name ExplosionBlast
extends Node2D

## The blast of the explosion weapon, of a mine, and of a mine-thrown tank's
## landing: Tank.exe's TExploseSprite (VMT 0x004902dc), rule for rule.
## docs/explosion_weapon_original_spec.md has the addresses.
##
## It's a square 8 tiles a side on the tile grid, centred on the tile corner
## nearest what went off (grid_origin). As it starts it works out, once:
##   - each quarter tile's heat: power - distance * falloff (power 250 + 25 per
##     level, falloff 60 - 5 per level; the distance from the centre in quarter
##     tiles), or none if a wall's quarter stands in the way (a straight march
##     out from the centre over the walls' standing quarters, as the original
##     marched it, its quirks too: _shadowed);
##   - each tile's heat, per mille of the power (its hottest quarter), and which
##     piece of the fireball it shows, by which of its quarters are lit.
## It lasts 15 frames of 15 ms. Each tile plays the fireball's 8 frames, the
## hotter the sooner (_tile_frame), as its own 16 px slice of the picture (32
## here), so the tiles make one body of fire, from puffs to embers.
## On the host only: the walls it reaches change on its 8th frame (wall_change).
## A tile hurts what's on it while it burns (its own frames 1 to 6): an opposing
## tank, by the hottest of its tiles, in one hit (then no blast hurts that tank
## for BLAST_IMMUNITY); an opposing shell, as much; and it sets off an opposing
## mine it reaches hot enough. A moon shield facing the centre saves its tank
## from the tiles on that side. A client draws it, nothing more.

const TILE_SIZE := 32.0
const TILES := 8
const QUARTERS := 16
## The original's frame: 20 engine ticks of 0.75 ms.
const FRAME_TIME := 0.015
const LAST_FRAME := 15
## Its walls change on this frame (the first with less than half its life left).
const WALL_FRAME := 8
## A tile hurts while its own frame is within these.
const HURT_FROM := 1
const HURT_TO := 6
## No blast hurts a tank or a shell again for this long after one has (250
## ticks; the original's +0xc0, shared by every blast).
const BLAST_IMMUNITY := 0.1875
## A tile changes its wall if its heat (per mille) times the power reaches this.
const WALL_HEAT := 25000
## Which fireball piece a tile shows, by its lit quarters (TL 1, TR 2, BL 4,
## BR 8): the original's table at 0x004d2e48. Pieces are the picture's 3x3
## slices, 0 its top-left corner to 8 its bottom-right.
const PIECES: Array[int] = [-1, 8, 6, 7, 2, 5, 4, 4, 0, 4, 3, 4, 1, 4, 4, 4]
## How much of a tank, a shell and a mine the blast reaches (half their boxes,
## px): a tank's is its picture less 6 px a side, but 12 px more a side while it
## blinks.
const TANK_REACH := 26.0
const BLINKING_TANK_REACH := 44.0
const SHELL_REACH := 14.0
const MINE_REACH := 16.0
## The size of what goes off, in the original's pixels (half a remake one): a
## shell's or a mine's box is 16, a tank's 32. The blast's place goes by its
## left and top edges (grid_origin).
const SHELL_SIZE := 16.0
const MINE_SIZE := 16.0
const TANK_SIZE := 32.0

const FRAME_PATH_FMT: String = "res://assets/sprites/effects/explosion_wave/explosion_wave_%d.png"

var level: int = 0
var from_player: bool = true
var neutral: bool = false  # a mine-thrown tank's landing: it hurts both sides
var owner_id: int = -1  # the player whose shell or mine this is (-1: an enemy's, or nobody's)
var spare_players: bool = false  # a mine a player's bomb set off: the players' tanks, shells and mines take nothing
## The top-left tile of its 8x8.
var origin: Vector2i = Vector2i.ZERO

var power: int = 250
var falloff: int = 60
## Heat per quarter tile, x-major (x * QUARTERS + y); per tile, per mille of
## the power and the piece it shows, x-major (x * TILES + y).
var _heat: PackedInt32Array = PackedInt32Array()
var _tile_heat: PackedInt32Array = PackedInt32Array()
var _tile_piece: PackedInt32Array = PackedInt32Array()
var _sprites: Array[Sprite2D] = []
var _level_manager: LevelManager = null
var _clock: float = 0.0
var _frame: int = 0

## The fireball's 8 frames, each cut in its 3x3 pieces: [frame][piece].
static var _slices: Array = []


func setup(p_level: int, p_from_player: bool, p_level_manager: LevelManager, p_neutral: bool = false,
		p_owner: int = -1, p_spare_players: bool = false) -> void:
	level = clampi(p_level, 0, 3)
	from_player = p_from_player
	_level_manager = p_level_manager
	neutral = p_neutral
	owner_id = p_owner
	spare_players = p_spare_players


## Where a blast goes: the top-left tile of its 8x8 for something of
## [param size] (the original's px) centred at [param center], local to the
## level (its tile 0,0 at 0,0). As the original: its left (top) edge in the
## original's map pixels, a 1-cell border included, / 16 - 3, truncated toward
## zero: the 8x8 centred on the tile corner nearest its centre (an exact half
## goes right, or down), one tile further in near the field's left and top
## edges.
static func grid_origin(center: Vector2, size: float) -> Vector2i:
	var edge := center / 2.0 + Vector2.ONE * (16.0 - size / 2.0)
	return Vector2i(int(edge.x / 16.0 - 3.0), int(edge.y / 16.0 - 3.0)) - Vector2i.ONE


func _ready() -> void:
	z_index = 20  # over the walls, the grass and the tanks
	if _level_manager:
		global_position = _level_manager.global_position + Vector2(origin) * TILE_SIZE
	_build()
	_load_slices()
	for x in TILES:
		for y in TILES:
			var spr := Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(x, y) * TILE_SIZE
			spr.scale = Vector2.ONE * 2.0
			spr.visible = false
			add_child(spr)
			_sprites.append(spr)


func _process(delta: float) -> void:
	_clock += delta
	while _clock >= FRAME_TIME and _frame <= LAST_FRAME:
		_clock -= FRAME_TIME
		_frame += 1
		_step()


## One frame of it: its picture, and on the host what it does.
func _step() -> void:
	if _frame > LAST_FRAME:
		queue_free()
		return
	for x in TILES:
		for y in TILES:
			var i := x * TILES + y
			var f := _tile_frame(i)
			var spr := _sprites[i]
			spr.visible = _tile_piece[i] >= 0 and f >= 0 and f < 8 and f < _slices.size()
			if spr.visible:
				spr.texture = _slices[f][_tile_piece[i]]
	if Net.is_client():
		return  # a client's blast is only its picture: the host's does the rest
	if _frame == WALL_FRAME:
		_change_walls()
	_hurt_tanks()
	_hurt_shells()
	_set_off_mines()


## The fireball frame tile [param i] shows this frame (0-7 shown; the
## original's Trunc toward zero shows frame 0 for two frames).
func _tile_frame(i: int) -> int:
	return int(_tile_heat[i] / 250.0 + _frame - 7.5)


# --- The grid ---

## Works out the heat of each quarter tile and of each tile, and the pieces.
func _build() -> void:
	power = 250 + 25 * level
	falloff = 60 - 5 * level
	var walls := PackedByteArray()
	walls.resize(QUARTERS * QUARTERS)
	if _level_manager:
		for x in TILES:
			for y in TILES:
				var standing := _level_manager.blast_shadow_quarters(origin + Vector2i(x, y))
				for q in 4:
					if standing & (8 >> q):
						walls[(2 * x + (q & 1)) * QUARTERS + 2 * y + (q >> 1)] = 1
	_heat.resize(QUARTERS * QUARTERS)
	for x in QUARTERS:
		for y in QUARTERS:
			var heat := Mine.round_half_even(power - sqrt((x - 7.5) * (x - 7.5) + (y - 7.5) * (y - 7.5)) * falloff)
			if heat > 0 and not _shadowed(walls, x, y):
				_heat[x * QUARTERS + y] = heat
	_tile_heat.resize(TILES * TILES)
	_tile_piece.resize(TILES * TILES)
	for x in TILES:
		for y in TILES:
			var lit := [_heat[(2 * x) * QUARTERS + 2 * y], _heat[(2 * x + 1) * QUARTERS + 2 * y],
					_heat[(2 * x) * QUARTERS + 2 * y + 1], _heat[(2 * x + 1) * QUARTERS + 2 * y + 1]]
			var bits := 0
			for q in 4:
				if lit[q] > 0:
					bits |= 1 << q
			_tile_heat[x * TILES + y] = int(lit.max()) * 1000 / power
			_tile_piece[x * TILES + y] = PIECES[bits]


## True if a wall's quarter in [param walls] stands between the centre and
## quarter ([param x], [param y]): two straight marches out from the centre,
## column by column, then row by row, as the original's (0x004969d7). Its own
## quarter never counts. The original's quirk is kept: towards the left (top),
## it walks the columns (rows) from the far end while the line's height steps
## from the centre, so it tests the line mirrored on that side.
static func _shadowed(walls: PackedByteArray, x: int, y: int) -> bool:
	var slope := (y - 7.5) / (x - 7.5)
	var first := 8 if x > 7 else x + 1
	var last := x - 1 if x > 7 else 7
	var step := slope if x > 7 else -slope
	var along := 7.5
	for col in range(first, last + 1):
		along += step
		if walls[col * QUARTERS + int(along) + (1 if y > 7 else 0)]:
			return true
	first = 8 if y > 7 else y + 1
	last = y - 1 if y > 7 else 7
	step = 1.0 / slope if y > 7 else -1.0 / slope
	along = 7.5
	for row in range(first, last + 1):
		along += step
		if walls[(int(along) + (1 if x > 7 else 0)) * QUARTERS + row]:
			return true
	return false


## The heat (in hit points) the blast puts on a box this frame: [param center]
## (global) with [param reach] its half size, from the hottest of the tiles it's
## on that burn now (their frames HURT_FROM to HURT_TO): round(per mille *
## power / 100000 + 0.25). A moon shield ([param shielded]) facing
## [param facing] saves it from the tiles on the side it faces. Returns [heat,
## whether the shield saved it from any].
func heat_on(center: Vector2, reach: float, shielded: bool = false, facing: Vector2 = Vector2.ZERO) -> Array:
	var local := center - global_position
	var heat := 0
	var saved := false
	for x in range(maxi(floori((local.x - reach) / TILE_SIZE), 0), mini(ceili((local.x + reach) / TILE_SIZE), TILES)):
		for y in range(maxi(floori((local.y - reach) / TILE_SIZE), 0), mini(ceili((local.y + reach) / TILE_SIZE), TILES)):
			var i := x * TILES + y
			var f := _tile_frame(i)
			if _tile_heat[i] <= 0 or f < HURT_FROM or f > HURT_TO:
				continue
			if shielded and _shield_faces(x, y, facing):
				saved = true
				continue
			heat = maxi(heat, Mine.round_half_even(_tile_heat[i] * power / 100000.0 + 0.25))
	return [heat, saved]


## True if a moon shield facing [param facing] faces the blast's centre from
## tile ([param x], [param y]): a tile up-left of the centre is covered facing
## right or down, and so on round.
static func _shield_faces(x: int, y: int, facing: Vector2) -> bool:
	var to_center := Vector2(1.0 if x < TILES / 2 else -1.0, 1.0 if y < TILES / 2 else -1.0)
	return facing == Vector2(to_center.x, 0.0) or facing == Vector2(0.0, to_center.y)


# --- What it does (the host) ---

## The walls on its tiles hot enough change, once (LevelManager.blast_wall).
## A whole brick keeps half: the top half on the tiles above the grid's
## diagonal, the left half on and below it. (The original meant to keep the
## half facing away from the blast; its test against 15 - y only ever kept
## these two.) Iron stays: only the shell's own hit breaks it
## (Bullet.breaks_iron).
func _change_walls() -> void:
	if _level_manager == null:
		return
	for x in TILES:
		for y in TILES:
			if _tile_heat[x * TILES + y] * power >= WALL_HEAT:
				_level_manager.blast_wall(origin + Vector2i(x, y), 0b1100 if y < x else 0b1010)


## True if the blast spares a tank, shell or mine of the players'
## ([param is_player]) or the enemies': a normal blast never touches its own
## side's; a landing's touches everyone's; a mine a player's bomb set off
## spares the players'.
func _spares(is_player: bool) -> bool:
	if is_player and spare_players:
		return true
	return not neutral and from_player == is_player


func _hurt_tanks() -> void:
	var tanks: Array = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies")
	for node: Node in tanks:
		var tank := node as BaseTank
		if tank == null or not is_instance_valid(tank) or tank.is_queued_for_deletion() or tank.health <= 0:
			continue
		if tank.is_materializing or tank.is_flying or tank.blast_immunity > 0.0:
			continue
		if _spares(tank.is_in_group("players")):
			continue
		var blinking := tank.is_invulnerable()
		var found := heat_on(tank.global_position, BLINKING_TANK_REACH if blinking else TANK_REACH,
				bool(tank.get(&"has_moon_shield")), tank.current_direction)
		var heat: int = found[0]
		if heat <= 0:
			if found[1]:
				SoundManager.play(&"shield_absorb")
			continue
		tank.blast_immunity = BLAST_IMMUNITY
		if not blinking:
			tank.hit_by = owner_id
			tank.take_hit(heat)


## Opposing shells on its burning tiles lose that much heat from their own (an
## explosion shell going off in turn).
func _hurt_shells() -> void:
	for node: Node in get_tree().get_nodes_in_group(NetWorld.GROUP):
		var shell := node as Bullet
		if shell == null or shell._destroyed or shell.is_queued_for_deletion() or shell.blast_immunity > 0.0:
			continue
		if _spares(shell.is_player_bullet):
			continue
		var heat: int = heat_on(shell.global_position, SHELL_REACH)[0]
		if heat > 0:
			shell.blast_immunity = BLAST_IMMUNITY
			shell.take_bullet_damage(heat)


## Opposing armed mines it reaches hot enough go off (the original's
## TExploseSprite collision with a mine, 0x00497550): one of no higher a level,
## where the blast's level and its heat there less 2 (less 3 above level 0)
## come to its level. So the same level chains to the next tile only, and a
## stronger blast reaches weaker mines further out. Mines of the blast's own
## side never go; a landing's blast belongs to neither; a mine a player's bomb
## set off leaves the players' be (_spares).
func _set_off_mines() -> void:
	if _level_manager == null:
		return
	for mine in _level_manager.get_mines():
		if not mine.is_armed() or mine.level > level:
			continue
		if _spares(mine.from_player):
			continue
		var heat: int = heat_on(mine.global_position, MINE_REACH)[0]
		if heat > 0 and level + heat - (2 if level <= 0 else 3) >= mine.level:
			mine.set_off()


static func _load_slices() -> void:
	if not _slices.is_empty():
		return
	for i in range(1, 9):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(FRAME_PATH_FMT % i)) != OK:
			return
		img.convert(Image.FORMAT_RGBA8)
		var whole := ImageTexture.create_from_image(img)
		var pieces: Array[Texture2D] = []
		for piece in 9:
			var slice := AtlasTexture.new()
			slice.atlas = whole
			slice.region = Rect2((piece % 3) * 16, (piece / 3) * 16, 16, 16)
			pieces.append(slice)
		_slices.append(pieces)
