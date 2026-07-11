class_name GroundFire
extends Area2D

## One burning ground tile. Tiles are created and managed by a FireField
## (see fire_field.gd); this node only handles its own visuals, arming, damage
## to overlapping opposing tanks, and its ragged burn-out ("decay").

const TILE_SIZE: int = 32
const ARM_DELAY: float = 0.05       # brief invisible+harmless grace after ignition
const REBURN_INTERVAL: float = 1.0  # per-tank damage cadence while standing in fire
const DAMAGE_POLL: float = 0.1      # how often to re-check overlapping tanks
const ANIM_FRAME_TIME: float = 0.05 # 8-frame loop = 400ms
const ANIM_FRAMES: int = 8

var from_player: bool = true   # true = lit by a player bullet (hurts enemies only)
var is_grass_fire: bool = false  # neutral grass fire: hurts BOTH sides, uses row 1
var tile_pos: Vector2i = Vector2i.ZERO

var _armed: bool = false
var _arm_timer: float = ARM_DELAY
var _decaying: bool = false
var _decay_timer: float = 0.0
var _damage_timer: float = 0.0
var _anim_timer: float = 0.0
var _frame: int = 0

var _sprite: Sprite2D = null
var _shape: CollisionShape2D = null
var _frames: Array = []   # this fire's row of textures

# The _B_Fire sheet has 3 rows: row 1 = grass fire (neutral, hurts both),
# row 2 = enemy-lit fire, row 3 = player-lit fire.
static var _row_textures: Dictionary = {}  # int row -> Array[Texture2D]
const FRAME_PATH_FMT: String = "res://assets/sprites/effects/ground_fire/ground_fire_r%d_f%d.png"


## Which sprite row this fire uses, per its owner.
func _current_row() -> int:
	if is_grass_fire:
		return 1
	return 3 if from_player else 2


func setup(p_tile: Vector2i, p_from_player: bool, p_arm_delay: float) -> void:
	tile_pos = p_tile
	from_player = p_from_player
	_arm_timer = p_arm_delay
	# Stagger the animation so a freshly-stamped patch doesn't flicker in unison.
	_frame = (p_tile.x + p_tile.y) % ANIM_FRAMES
	_anim_timer = randf() * ANIM_FRAME_TIME


func _ready() -> void:
	# Draw above the floor but BELOW tanks: fire lives in the Playfield subtree,
	# which renders before the Entities (tank) subtree at the same z_index.
	z_index = 0
	collision_layer = 0
	set_collision_mask_value(3, true)  # player_tanks
	set_collision_mask_value(4, true)  # enemy_tanks
	monitorable = false
	# Monitoring runs the whole life; damage is gated by `_armed`. Deferred because
	# a fire is often spawned from inside a physics callback (a bullet's death).
	set_deferred("monitoring", true)

	_frames = _load_textures(_current_row())

	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	_shape.shape = rect
	add_child(_shape)

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

	visible = false  # hidden until armed


func _process(delta: float) -> void:
	if not _armed:
		_arm_timer -= delta
		if _arm_timer <= 0.0:
			_armed = true
			visible = true
		return

	_damage_timer -= delta
	if _damage_timer <= 0.0:
		_damage_timer = DAMAGE_POLL
		_apply_damage()

	_advance_animation(delta)

	if _decaying:
		_decay_timer -= delta
		if _decay_timer <= 0.0:
			queue_free()


## Begin a ragged burn-out after [param delay] seconds. The tile keeps burning
## (and damaging) until then, so a shrinking field's outer ring winks out one
## tile at a time rather than all at once.
func start_decay(delay: float) -> void:
	if _decaying:
		return
	_decaying = true
	_decay_timer = maxf(delay, 0.0)


func _apply_damage() -> void:
	# A grass fire is neutral (hurts_both); weapon fire stays own-side-immune.
	for body in get_overlapping_bodies():
		if body is BaseTank:
			(body as BaseTank).on_fire_contact(from_player, REBURN_INTERVAL, is_grass_fire)


func _advance_animation(delta: float) -> void:
	if _frames.is_empty():
		return
	_anim_timer += delta
	if _anim_timer >= ANIM_FRAME_TIME:
		_anim_timer -= ANIM_FRAME_TIME
		_frame = (_frame + 1) % _frames.size()
		_sprite.texture = _frames[_frame] as Texture2D


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
