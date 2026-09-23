class_name Mine
extends Area2D

## A laid mine, rebuilt from Tank.exe's TMineSprite (VMT 0x004903d8). Every rule
## below is the original's; docs/mine_weapon_original_spec.md has the addresses.
##
## Level is the layer's gun level, 0-3, and picks the sprite row. A new mine is
## hidden and inert while its row plays; it surfaces and arms near the row's end
## and holds the last frame. A level-3 mine then loops the ringed row instead.
## A player's mine is always drawn; an enemy mine only fades in while a player
## tank or the base is close, and never becomes fully opaque.
##
## An opposing tank that touches an armed mine sets it off (anti-ice skates over
## anything below level 3). The blast is the explosion weapon's at the mine's
## level, and the tank that touched it suffers by level:
##   L0  the blast alone
##   L1  + slowed to a quarter speed until an add-on or MAX pickup, or death
##   L2  + a direct hit, and the tank is thrown into the air
##   L3  the same, a harder hit and a longer flight
## An add-on soaks part of that direct hit and is lost; memory-save never flies.
## Opposing explosions set mines off too, so fields chain. Bullets never do.

const TILE_SIZE: int = 32

## The original advanced the row 0.01 frame per 0.75 ms engine tick, so each
## frame lasts 75 ms, and the mine surfaced once the frame rounded to the last
## one, 2.5 frames in.
const DEPLOY_FRAME_TIME: float = 0.075
const ARM_TIME: float = DEPLOY_FRAME_TIME * 2.5
const FRAMES_PER_ROW: int = 4
const LAST_FRAME: int = FRAMES_PER_ROW - 1
## Level 3 switches to the ringed row (sheet row 4) and loops it at 0.002 frame
## a tick, 1.5 s around.
const RING_ROW: int = 4
const RING_FRAME_TIME: float = 0.375

## Enemy-mine reveal, in the original's own units: 8 px distance steps (16 px
## here) and alpha in steps of 16, capped at 192 and hidden below 64.
const REVEAL_STEP: float = 16.0
const REVEAL_MAX_ALPHA: int = 192
const REVEAL_MIN_ALPHA: int = 64

var level: int = 0                     # 0-3, the layer's gun level
var from_player: bool = true           # side: true = laid by a player (hurts enemies)
var cell: Vector2i = Vector2i.ZERO     # top-left tile of the 2x2 block it sits on

var _level_manager: LevelManager = null
var _age: float = 0.0
var _armed: bool = false
var _triggered: bool = false
var _fuse: float = -1.0                # >= 0: an explosion reached it, goes off when this runs out
var _sprite: Sprite2D = null

# Frame textures per sheet row (0-4), loaded once.
static var _tex_by_row: Dictionary = {}
const FRAME_PATH_FMT: String = "res://assets/sprites/mines/mine_row%d_f%d.png"


func setup(p_cell: Vector2i, p_level: int, p_from_player: bool, p_level_manager: LevelManager) -> void:
	cell = p_cell
	level = clampi(p_level, 0, 3)
	from_player = p_from_player
	_level_manager = p_level_manager


func _ready() -> void:
	z_index = 0  # on the ground, below tanks (Playfield subtree draws before Entities)
	collision_layer = 0
	set_collision_mask_value(3, true)  # player_tanks
	set_collision_mask_value(4, true)  # enemy_tanks
	monitorable = false
	set_deferred("monitoring", true)   # deferred: mines can be laid mid-physics-step

	# The original's 16 px mine, doubled. Tanks touch it with their own box.
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frames := _load_row(level)
	if not frames.is_empty():
		var tex_w: float = (frames[0] as Texture2D).get_size().x
		if tex_w > 0.0:
			_sprite.scale = Vector2.ONE * (float(TILE_SIZE) / tex_w)
	add_child(_sprite)
	visible = false  # hidden until it surfaces


func _process(delta: float) -> void:
	_age += delta
	if _age <= ARM_TIME:
		return  # still deploying: hidden, and nothing can touch it

	if not _armed:
		_armed = true
		visible = from_player  # an enemy mine waits for the reveal
	_show_frame()
	# The original re-ran the reveal only while the frame rounded to 3: always,
	# once a mine has settled, but only a quarter of each ring loop at level 3.
	if not from_player and _frame_rounds_to_last():
		_update_reveal()

	if _triggered:
		return
	for body in get_overlapping_bodies():
		if body is BaseTank and _on_tank_contact(body as BaseTank):
			return
	if _fuse >= 0.0:
		_fuse -= delta
		if _fuse <= 0.0:
			set_off()


func is_armed() -> bool:
	return _armed and not _triggered


## Go off with no one on it: the blast alone. Used when an explosion reaches it.
func set_off() -> void:
	if _triggered:
		return
	_triggered = true
	# The original only sounded mines from level 2 up.
	if level >= 2:
		SoundManager.play(&"mine_explode")
	if _level_manager:
		_level_manager.spawn_explosion_blast(global_position, level, from_player)
		_level_manager.unregister_mine(self)
	queue_free()


## Go off after [param delay] seconds, so a chain follows the blast wave out.
func set_off_after(delay: float) -> void:
	if _triggered or (_fuse >= 0.0 and _fuse <= delay):
		return
	_fuse = maxf(delay, 0.0)


## A tank touched the armed mine (TTankSprite.DoCollision, 0x00491aac). Returns
## true if the mine went off.
func _on_tank_contact(tank: BaseTank) -> bool:
	var addons: Array = tank.get_addon_names()
	var anti_ice: bool = "anti-ice" in addons
	if anti_ice and level < 3:
		return false  # skates over it; the mine stays for the next tank
	if from_player == tank.is_in_group("players"):
		return false  # never the layer's own side
	set_off()
	if not is_instance_valid(tank) or tank.health <= 0 or tank.is_flying:
		return true

	var invulnerable: bool = tank.is_invulnerable()
	var memory: bool = "memory-save" in addons
	# L1+ slows to a quarter speed. Anti-ice is immune; memory-save only below L3.
	if not invulnerable and level >= 1 and not anti_ice and not (memory and level < 3):
		tank.apply_mine_slow()
	# L2+ hits the tank and throws it. Memory-save never flies.
	if level < 2 or memory:
		return true
	if not invulnerable:
		if anti_ice:
			tank.lose_addon("anti-ice")       # the add-on takes the whole hit
		elif not addons.is_empty():
			tank.lose_addon(addons[0])        # the add-on soaks one point of it
			_hit(tank, level - 2)
		else:
			_hit(tank, level - 1)
	if is_instance_valid(tank) and tank.health > 0:
		tank.launch_mine_fly(level, global_position)
	return true


func _hit(tank: BaseTank, points: int) -> void:
	for i in range(points):
		if not is_instance_valid(tank) or tank.health <= 0:
			return
		tank.take_damage()


## The level's row, played once and held on its last frame; level 3 then loops
## the ringed row, picking up where the deploy row left off (2.5 frames in).
func _show_frame() -> void:
	var frames: Array
	var frame: int
	if level == 3:
		frames = _load_row(RING_ROW)
		frame = int(_ring_position()) % FRAMES_PER_ROW
	else:
		frames = _load_row(level)
		frame = mini(int(_age / DEPLOY_FRAME_TIME), LAST_FRAME)
	if frame < frames.size():
		_sprite.texture = frames[frame] as Texture2D


func _ring_position() -> float:
	return 2.5 + (_age - ARM_TIME) / RING_FRAME_TIME


func _frame_rounds_to_last() -> bool:
	if level != 3:
		return true
	return round_half_even(fmod(_ring_position(), float(FRAMES_PER_ROW))) == LAST_FRAME


## How visible an enemy mine is: the nearest of the base (whose reach is 6 steps
## longer) and each player tank (8 steps longer while airborne, 4 with anti-ice).
func _update_reveal() -> void:
	var steps := 16  # nothing in range
	var eagle := get_tree().get_first_node_in_group("eagle") as Node2D
	if eagle:
		steps = _steps_to(eagle.global_position) - 6
	for node in get_tree().get_nodes_in_group("players"):
		var tank := node as BaseTank
		if tank == null or not is_instance_valid(tank):
			continue
		var s := _steps_to(tank.global_position)
		if tank.is_flying:
			s -= 8
		elif "anti-ice" in tank.get_addon_names():
			s -= 4
		steps = mini(steps, s)
	var alpha := mini((16 - steps) * 16, REVEAL_MAX_ALPHA)
	visible = alpha >= REVEAL_MIN_ALPHA
	_sprite.modulate.a = clampf(alpha / 255.0, 0.0, 1.0)


func _steps_to(point: Vector2) -> int:
	return round_half_even(global_position.distance_to(point) / REVEAL_STEP)


## Delphi's Round, which the original used everywhere: halves go to the even
## neighbour (2.5 -> 2, 3.5 -> 4).
static func round_half_even(x: float) -> int:
	var f := floorf(x)
	var rest := x - f
	if rest > 0.5:
		return int(f) + 1
	if rest < 0.5:
		return int(f)
	return int(f) + (int(f) & 1)


static func _load_row(row: int) -> Array:
	if _tex_by_row.has(row):
		return _tex_by_row[row]
	var frames: Array = []
	for f in range(1, FRAMES_PER_ROW + 1):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(FRAME_PATH_FMT % [row + 1, f])) != OK:
			continue
		img.convert(Image.FORMAT_RGBA8)
		frames.append(ImageTexture.create_from_image(img))
	_tex_by_row[row] = frames
	return frames
