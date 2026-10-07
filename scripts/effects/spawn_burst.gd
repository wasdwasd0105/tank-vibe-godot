class_name SpawnBurst
extends Node2D

## The energy burst that plays where a new tank appears (Tank_Out.bmp, 6 frames).
## A self-contained Node2D: loads its frames once into a static cache, plays them
## at the spawn position, then frees itself. Spawn it via SpawnBurst.spawn_at().

const FRAME_COUNT: int = 6
const FRAME_DUR: float = 0.09
const DURATION: float = FRAME_COUNT * FRAME_DUR  # total play time; tanks appear after this
const SIZE_PX: float = 64.0  # matches the 2x2-tile tank footprint
const PATH_FMT: String = "res://assets/sprites/effects/spawn/spawn_%d.png"

static var _frames: Array[Texture2D] = []

var _t: float = 0.0
var _sprite: Sprite2D = null


## Play a spawn burst at [param world_pos]. No-op if the effects container is gone.
static func spawn_at(tree: SceneTree, world_pos: Vector2) -> void:
	var container: Node = tree.get_first_node_in_group("effects_container")
	if container == null:
		return
	NetHostWorld.record(NetWorld.EV_SPAWN_BURST, [world_pos.x, world_pos.y])
	var fx := SpawnBurst.new()
	container.add_child(fx)
	fx.global_position = world_pos


func _ready() -> void:
	# Over the tanks, under the grass and the blasts: the original's appearing
	# tank showed this picture itself, at its Z 2.
	z_index = 0
	_load_frames()
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
		var ts := _frames[0].get_size()
		if ts.x > 0:
			_sprite.scale = Vector2(SIZE_PX / ts.x, SIZE_PX / ts.y)
	add_child(_sprite)


func _process(delta: float) -> void:
	_t += delta
	var f := int(_t / FRAME_DUR)
	if _frames.is_empty() or f >= _frames.size():
		queue_free()
		return
	_sprite.texture = _frames[f]


static func _load_frames() -> void:
	if not _frames.is_empty():
		return
	for i in range(1, FRAME_COUNT + 1):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(PATH_FMT % i)) == OK:
			img.convert(Image.FORMAT_RGBA8)
			_frames.append(ImageTexture.create_from_image(img))
