class_name ExplosionBlast
extends Node2D

## The shockwave from the explosion weapon and mines. Instead of one big scaled
## image, it sprays a per-tile fireball outward from the center in an expanding
## ring (like the water/fire tiles): each 32px block plays the 8-frame explosion,
## and each ring starts one step later than the one inside it.
## Damage: every opposing tank within the radius takes a flat spray amount (once);
## a mine's slow/fly and the bullet's direct hit are applied separately.
## See docs/explosion_weapon_original_spec.md for the original recovered constants.

const TILE_SIZE: float = 32.0
const HALF_TILE: float = 16.0
const ANIM_FRAMES: int = 8
const WALL_FRAMES: int = ANIM_FRAMES / 2  # tiles that hit a wall only play half the cycle
const FRAME_DUR: float = 0.05      # per animation frame
const RING_STEP_FRAMES: int = 1    # frames of delay per ring outward

# Per blast level 0-3 (remake units).
const RADIUS_TILES: Array[int] = [2, 3, 3, 4]      # how far the wave sprays
const SPRAY_DAMAGE: Array[int] = [1, 2, 3, 3]      # flat damage to a tank in the wave

const FRAME_PATH_FMT: String = "res://assets/sprites/effects/explosion_wave/explosion_wave_%d.png"

var level: int = 0
var from_player: bool = true
var neutral: bool = false  # neutral blast (e.g. a mine-fly landing) hurts BOTH sides
var exclude_tank: Node = null  # a directly-hit tank already took the direct hit; skip it
var _level_manager: LevelManager = null

var _t: float = 0.0
var _terrain_done: bool = false
var _tiles: Array = []      # Array of { "sprite": Sprite2D, "step": int }
var _max_step: int = 0

static var _frames: Array[Texture2D] = []


func setup(p_level: int, p_from_player: bool, p_level_manager: LevelManager, p_neutral: bool = false, p_exclude: Node = null) -> void:
	level = clampi(p_level, 0, 3)
	from_player = p_from_player
	neutral = p_neutral
	exclude_tank = p_exclude
	_level_manager = p_level_manager


func _ready() -> void:
	z_index = 20  # explosions draw in front of everything
	_load_frames()
	_build_tiles()
	_apply_tank_damage()


## One Sprite2D per tile within the (circular) radius, hidden until its ring's turn.
func _build_tiles() -> void:
	var r := RADIUS_TILES[level]
	_max_step = r
	var scale_factor := 1.0
	if not _frames.is_empty():
		var tw := _frames[0].get_size().x
		if tw > 0:
			scale_factor = TILE_SIZE / tw
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist > float(r) + 0.5:
				continue  # circular footprint
			var spr := Sprite2D.new()
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(dx, dy) * TILE_SIZE
			spr.scale = Vector2.ONE * scale_factor
			spr.visible = false
			add_child(spr)
			# A cell that lands on a wall (or is shadowed behind one) only plays
			# half the fireball cycle, so the wave visibly dampens at walls.
			var frames := ANIM_FRAMES
			if _hits_wall(Vector2(dx, dy) * TILE_SIZE):
				frames = WALL_FRAMES
			_tiles.append({
				"sprite": spr,
				"step": int(round(dist)) * RING_STEP_FRAMES,
				"frames": frames,
			})


## A cell "hits a wall" if it lands on a solid tile or a wall shadows it from
## the blast center. The center cell itself never counts (it always blooms).
func _hits_wall(local_offset: Vector2) -> bool:
	if _level_manager == null or local_offset == Vector2.ZERO:
		return false
	var cell_world: Vector2 = global_position + local_offset
	if _level_manager.is_solid_at_world(cell_world):
		return true
	return not _level_manager.has_line_of_sight(global_position, cell_world)


func _process(delta: float) -> void:
	_t += delta
	var gframe := int(_t / FRAME_DUR)

	if not _frames.is_empty():
		for tile in _tiles:
			var fi: int = gframe - int(tile["step"])
			var spr: Sprite2D = tile["sprite"]
			if fi >= 0 and fi < int(tile["frames"]) and fi < _frames.size():
				spr.visible = true
				spr.texture = _frames[fi]
			else:
				spr.visible = false

	# Terrain is destroyed once, shortly after the wave starts spreading.
	if not _terrain_done and _t >= FRAME_DUR * 2.0:
		_terrain_done = true
		_apply_terrain_damage()

	# Done once the outermost ring has finished its animation.
	if gframe > _max_step + ANIM_FRAMES:
		queue_free()


## Flat spray damage to opposing tanks within the radius. Same-side and
## wall-shadowed tanks are skipped; a shielded front blocks it. Applied once.
func _apply_tank_damage() -> void:
	var r := float(RADIUS_TILES[level])
	var dmg := SPRAY_DAMAGE[level]
	var tanks: Array = get_tree().get_nodes_in_group("players") + get_tree().get_nodes_in_group("enemies")
	for tank in tanks:
		if not (tank is BaseTank) or not is_instance_valid(tank):
			continue
		if tank == exclude_tank:
			continue  # already took the bullet's direct hit
		var is_player: bool = tank.is_in_group("players")
		if not neutral and from_player == is_player:
			continue  # a normal blast never hurts its own side; a neutral one hits everyone
		var dist_tiles: float = global_position.distance_to(tank.global_position) / TILE_SIZE
		if dist_tiles > r + 0.5:
			continue
		if _level_manager and not _level_manager.has_line_of_sight(global_position, tank.global_position):
			continue
		# Moon shield blocks a wave reaching the tank's shielded front.
		if tank.is_bullet_blocked(tank.global_position - global_position):
			continue
		for i in range(dmg):
			if is_instance_valid(tank) and tank.health > 0:
				tank.take_damage()


func _apply_terrain_damage() -> void:
	if not _level_manager:
		return
	# Break destructible terrain across the wave's footprint (radius in half-tiles).
	_level_manager.explosion_destroy_terrain(
		_level_manager.world_to_tile(global_position), float(RADIUS_TILES[level]) * 2.0)


func _load_frames() -> void:
	if not _frames.is_empty():
		return
	for i in range(1, ANIM_FRAMES + 1):
		var path := FRAME_PATH_FMT % i
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) != OK:
			continue
		img.convert(Image.FORMAT_RGBA8)
		_frames.append(ImageTexture.create_from_image(img))
