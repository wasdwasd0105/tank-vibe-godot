class_name Mine
extends Area2D

## A placed mine (weapon type "mine"), reverse-engineered from Tank.exe
## TMineSprite. It arms after a short delay, then detonates when an opposing tank
## drives onto it. Detonation reuses the explosion weapon's ExplosionBlast, scaled
## by the mine's level (1-4), and applies per-level effects to the victim:
##   L1: blast only        L2: blast + slow
##   L3: blast + fly       L4: blast + fly + slow
## See docs/mine_weapon_original_spec.md.

const TILE_SIZE: int = 32
const ARM_DELAY: float = 0.22          # inert while arming, so the layer can drive off
const ANIM_FRAME_TIME: float = 0.18    # blink animation
const ANIM_FRAMES: int = 4

var level: int = 1                      # 1-4
var from_player: bool = true            # true = laid by a player (hurts enemies)
var tile_pos: Vector2i = Vector2i.ZERO

var _level_manager: LevelManager = null
var _armed: bool = false
var _arm_timer: float = 0.0
var _triggered: bool = false
var _anim_timer: float = 0.0
var _frame: int = 0

var _sprite: Sprite2D = null

# Cache of the 4 blink frames per level row (1-4).
static var _tex_by_level: Dictionary = {}
const FRAME_PATH_FMT: String = "res://assets/sprites/mines/mine_row%d_f%d.png"


func setup(p_tile: Vector2i, p_level: int, p_from_player: bool, p_level_manager: LevelManager) -> void:
	tile_pos = p_tile
	level = clampi(p_level, 1, 4)
	from_player = p_from_player
	_level_manager = p_level_manager
	_arm_timer = ARM_DELAY


func _ready() -> void:
	z_index = 0  # on the ground, below tanks (Playfield subtree draws before Entities)
	collision_layer = 0
	set_collision_mask_value(3, true)  # player_tanks
	set_collision_mask_value(4, true)  # enemy_tanks
	monitorable = false
	set_deferred("monitoring", true)   # deferred: mines can be laid mid-physics-step

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape.shape = rect
	add_child(shape)

	var frames := _load_frames(level)
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not frames.is_empty():
		var tex0 := frames[0] as Texture2D
		_sprite.texture = tex0
		var tex_w := tex0.get_size().x
		if tex_w > 0:
			_sprite.scale = Vector2.ONE * (float(TILE_SIZE) / tex_w)
	add_child(_sprite)


func _process(delta: float) -> void:
	if not _armed:
		_arm_timer -= delta
		if _arm_timer <= 0.0:
			_armed = true
		return

	_advance_animation(delta)

	if _triggered:
		return
	for body in get_overlapping_bodies():
		if body is BaseTank and _is_enemy(body):
			_detonate(body as BaseTank)
			return


## Detonate with no victim tank (e.g. a strong bullet set it off). Blast only.
func detonate_from_bullet() -> void:
	if _triggered:
		return
	_detonate(null)


func _is_enemy(tank: BaseTank) -> bool:
	# A mine triggers only on the opposing side (same rule as fire/blast).
	return from_player != tank.is_in_group("players")


func _detonate(victim: BaseTank) -> void:
	_triggered = true
	var world := global_position
	var blast_level := clampi(level - 1, 0, 3)

	# 1. Launch blast at the mine tile (hits the victim + nearby opposing tanks).
	if _level_manager:
		_level_manager.spawn_explosion_blast(world, blast_level, from_player)

	# 2. Per-level effects on the tank that stepped on it.
	if victim and is_instance_valid(victim):
		if level >= 3:
			victim.launch_mine_fly(level)   # fly; the tank spawns its own landing blast
		if level == 2 or level == 4:
			victim.apply_mine_slow()

	if _level_manager:
		_level_manager.unregister_mine(tile_pos, self)
	queue_free()


func _advance_animation(delta: float) -> void:
	var frames := _load_frames(level)
	if frames.is_empty():
		return
	_anim_timer += delta
	if _anim_timer >= ANIM_FRAME_TIME:
		_anim_timer -= ANIM_FRAME_TIME
		_frame = (_frame + 1) % frames.size()
		_sprite.texture = frames[_frame] as Texture2D


static func _load_frames(lvl: int) -> Array:
	if _tex_by_level.has(lvl):
		return _tex_by_level[lvl]
	var frames: Array = []
	for f in range(1, ANIM_FRAMES + 1):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(FRAME_PATH_FMT % [lvl, f])) != OK:
			continue
		img.convert(Image.FORMAT_RGBA8)
		frames.append(ImageTexture.create_from_image(img))
	_tex_by_level[lvl] = frames
	return frames
