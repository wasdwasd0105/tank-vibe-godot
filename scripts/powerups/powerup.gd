class_name PowerUp
extends Area2D

enum Type { STAR = 0, HELMET = 1, BOMB = 2, CLOCK = 3, SHOVEL = 4, TANK = 5, BOAT = 6 }

@export var type: Type = Type.STAR

var _blink_timer: float = 0.0
var _lifetime: float = 0.0
const DESPAWN_TIME: float = 15.0

const S: int = 64  # sprite size (2x2 tiles)

# Cached textures (generated once, shared across all powerup instances)
static var _textures: Dictionary = {}

func _ready() -> void:
	type = randi() % Type.size() as Type
	add_to_group("powerups")
	body_entered.connect(_on_body_entered)
	# Set collision
	set_collision_layer_value(7, true)  # powerups layer
	set_collision_mask_value(3, true)   # player tanks
	# Update collision shape to 2x2 tile size
	var col := get_node_or_null("CollisionShape2D")
	if col:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(S, S)
		col.shape = rect
	# Generate textures on first use
	if _textures.is_empty():
		_generate_all_textures()
	# Set sprite
	if has_node("Sprite2D"):
		$Sprite2D.texture = _textures.get(type, null)
		$Sprite2D.modulate = Color.WHITE

func _process(delta: float) -> void:
	_blink_timer += delta
	visible = fmod(_blink_timer, 0.3) < 0.2

	_lifetime += delta
	if _lifetime > DESPAWN_TIME:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body is PlayerTank:
		Events.powerup_collected.emit(type, body.player_id)
		_apply_effect(body)
		queue_free()

func _apply_effect(player: PlayerTank) -> void:
	match type:
		Type.STAR:
			player.apply_powerup(Type.STAR)
		Type.HELMET:
			player.apply_powerup(Type.HELMET)
		Type.BOMB:
			Events.bomb_all_enemies.emit()
		Type.CLOCK:
			Events.freeze_enemies.emit(10.0)
		Type.SHOVEL:
			Events.fortify_base.emit(20.0)
		Type.TANK:
			player.apply_powerup(Type.TANK)
		Type.BOAT:
			player.apply_powerup(Type.BOAT)

# =====================================================================
# Texture Generation — all icons are 64x64 with transparent background
# =====================================================================

static func _generate_all_textures() -> void:
	_textures[Type.STAR] = _create_star_texture()
	_textures[Type.HELMET] = _create_helmet_texture()
	_textures[Type.BOMB] = _create_bomb_texture()
	_textures[Type.CLOCK] = _create_clock_texture()
	_textures[Type.SHOVEL] = _create_shovel_texture()
	_textures[Type.TANK] = _create_tank_texture()
	_textures[Type.BOAT] = _create_boat_texture()

static func _new_img() -> Image:
	return Image.create(S, S, false, Image.FORMAT_RGBA8)

static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < S and y >= 0 and y < S:
		img.set_pixel(x, y, c)

static func _fill_rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_put(img, x, y, c)

static func _fill_circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				_put(img, x, y, c)

static func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, thickness: int, c: Color) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	if steps == 0:
		_fill_circle(img, x0, y0, thickness / 2, c)
		return
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var px := int(lerpf(float(x0), float(x1), t))
		var py := int(lerpf(float(y0), float(y1), t))
		for dy in range(-thickness / 2, thickness / 2 + 1):
			for dx in range(-thickness / 2, thickness / 2 + 1):
				_put(img, px + dx, py + dy, c)

## STAR — Yellow 5-pointed star on transparent background
static func _create_star_texture() -> Texture2D:
	var img := _new_img()
	var yellow := Color(1.0, 0.85, 0.0)
	var highlight := Color(1.0, 1.0, 0.5)
	var outline := Color(0.8, 0.6, 0.0)
	var cx := S / 2
	var cy := S / 2
	# Draw 5-pointed star using angle-based approach
	var outer_r := 28.0
	var inner_r := 12.0
	var points: Array[Vector2] = []
	for i in range(10):
		var angle := (i * TAU / 10.0) - TAU / 4.0
		var r := outer_r if i % 2 == 0 else inner_r
		points.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	# Fill star polygon using scanline
	for y in range(S):
		var nodes_x: Array[float] = []
		var n := points.size()
		for i in range(n):
			var j := (i + 1) % n
			var yi := points[i].y
			var yj := points[j].y
			if (yi <= y and yj > y) or (yj <= y and yi > y):
				var x_intersect := points[i].x + (y - yi) / (yj - yi) * (points[j].x - points[i].x)
				nodes_x.append(x_intersect)
		nodes_x.sort()
		for k in range(0, nodes_x.size() - 1, 2):
			var x_start := int(nodes_x[k])
			var x_end := int(nodes_x[k + 1])
			for x in range(x_start, x_end + 1):
				_put(img, x, y, yellow)
	# Outline
	for i in range(points.size()):
		var j := (i + 1) % points.size()
		_draw_line(img, int(points[i].x), int(points[i].y), int(points[j].x), int(points[j].y), 2, outline)
	# Center highlight
	_fill_circle(img, cx, cy, 4, highlight)
	return ImageTexture.create_from_image(img)

## HELMET — White/silver helmet shape
static func _create_helmet_texture() -> Texture2D:
	var img := _new_img()
	var helmet := Color(0.85, 0.85, 0.9)
	var helmet_dk := Color(0.6, 0.6, 0.7)
	var visor := Color(0.2, 0.4, 0.7)
	var highlight := Color(1.0, 1.0, 1.0)
	var cx := S / 2
	# Helmet dome
	_fill_circle(img, cx, cx - 2, 22, helmet_dk)
	_fill_circle(img, cx, cx - 2, 20, helmet)
	# Bottom chin guard
	_fill_rect(img, 12, S / 2 + 6, S - 24, 12, helmet)
	_fill_rect(img, 14, S / 2 + 16, S - 28, 4, helmet_dk)
	# Visor slit
	_fill_rect(img, 16, S / 2 - 4, S - 32, 6, visor)
	# Visor reflection
	_fill_rect(img, 18, S / 2 - 3, 6, 2, Color(0.4, 0.6, 0.9))
	# Top highlight
	_fill_circle(img, cx - 4, 14, 5, highlight)
	return ImageTexture.create_from_image(img)

## BOMB — Dark bomb with fuse and spark
static func _create_bomb_texture() -> Texture2D:
	var img := _new_img()
	var bomb_body := Color(0.2, 0.2, 0.25)
	var bomb_hi := Color(0.35, 0.35, 0.4)
	var fuse := Color(0.7, 0.5, 0.1)
	var spark := Color(1.0, 0.4, 0.0)
	var spark_hi := Color(1.0, 0.9, 0.2)
	var cx := S / 2
	# Bomb body
	_fill_circle(img, cx, cx + 4, 20, bomb_body)
	# Highlight
	_fill_circle(img, cx - 8, cx - 2, 6, bomb_hi)
	# Fuse line from top of bomb going up-right
	_draw_line(img, cx + 2, 18, cx + 14, 6, 3, fuse)
	# Spark burst at end of fuse
	_fill_circle(img, cx + 14, 6, 5, spark)
	_fill_circle(img, cx + 14, 6, 3, spark_hi)
	# Small sparks
	_fill_rect(img, cx + 10, 2, 2, 2, spark_hi)
	_fill_rect(img, cx + 18, 4, 2, 2, spark_hi)
	_fill_rect(img, cx + 16, 0, 2, 2, spark)
	return ImageTexture.create_from_image(img)

## CLOCK — Cyan clock face with hands
static func _create_clock_texture() -> Texture2D:
	var img := _new_img()
	var face := Color(0.0, 0.7, 0.7)
	var face_inner := Color(0.1, 0.85, 0.85)
	var rim := Color(0.0, 0.5, 0.5)
	var hands := Color(1.0, 1.0, 1.0)
	var center := Color(1.0, 0.3, 0.0)
	var cx := S / 2
	var cy := S / 2
	# Clock face
	_fill_circle(img, cx, cy, 26, rim)
	_fill_circle(img, cx, cy, 23, face)
	_fill_circle(img, cx, cy, 20, face_inner)
	# Hour marks
	var mark := Color(0.9, 0.9, 0.9)
	_fill_rect(img, cx - 1, cy - 22, 3, 5, mark)   # 12
	_fill_rect(img, cx + 17, cy - 1, 5, 3, mark)    # 3
	_fill_rect(img, cx - 1, cy + 17, 3, 5, mark)    # 6
	_fill_rect(img, cx - 22, cy - 1, 5, 3, mark)    # 9
	# Minute hand (pointing to 12)
	_draw_line(img, cx, cy, cx, cy - 16, 3, hands)
	# Hour hand (pointing to ~2 o'clock)
	_draw_line(img, cx, cy, cx + 8, cy - 10, 3, hands)
	# Center dot
	_fill_circle(img, cx, cy, 3, center)
	return ImageTexture.create_from_image(img)

## SHOVEL — Brown handle + silver blade
static func _create_shovel_texture() -> Texture2D:
	var img := _new_img()
	var handle := Color(0.55, 0.3, 0.1)
	var handle_hi := Color(0.7, 0.45, 0.15)
	var blade := Color(0.65, 0.65, 0.7)
	var blade_hi := Color(0.8, 0.8, 0.85)
	# Handle (diagonal from top-right to bottom-left)
	_draw_line(img, 44, 8, 16, 36, 4, handle)
	_draw_line(img, 45, 9, 17, 37, 2, handle_hi)
	# Handle grip (top end)
	_draw_line(img, 40, 4, 50, 14, 4, handle)
	# Blade (bottom-left, rounded shovel head)
	_fill_circle(img, 14, 42, 14, blade)
	_fill_circle(img, 14, 40, 10, blade_hi)
	# Blade edge
	_fill_rect(img, 4, 48, 20, 4, Color(0.5, 0.5, 0.55))
	return ImageTexture.create_from_image(img)

## TANK — Green extra life tank (top-down view)
static func _create_tank_texture() -> Texture2D:
	var img := _new_img()
	var body := Color(0.1, 0.7, 0.1)
	var body_dk := Color(0.05, 0.5, 0.05)
	var barrel := Color(0.08, 0.55, 0.08)
	var track := Color(0.05, 0.35, 0.05)
	var track_det := Color(0.08, 0.45, 0.08)
	var cx := S / 2
	# Tracks (left and right)
	_fill_rect(img, 8, 16, 10, 36, track)
	_fill_rect(img, S - 18, 16, 10, 36, track)
	# Track detail lines
	for i in range(6):
		var ty := 18 + i * 6
		_fill_rect(img, 8, ty, 10, 2, track_det)
		_fill_rect(img, S - 18, ty, 10, 2, track_det)
	# Body
	_fill_rect(img, 18, 18, S - 36, 28, body)
	# Turret (centered rectangle)
	_fill_rect(img, 20, 22, S - 40, 18, body_dk)
	# Barrel (pointing up)
	_fill_rect(img, cx - 2, 4, 5, 22, barrel)
	# Barrel tip
	_fill_rect(img, cx - 3, 4, 7, 3, body)
	# Center dot
	_fill_circle(img, cx, 32, 3, Color(0.2, 0.85, 0.2))
	return ImageTexture.create_from_image(img)

## BOAT — Brown boat on blue waves
static func _create_boat_texture() -> Texture2D:
	var img := _new_img()
	var hull := Color(0.5, 0.3, 0.1)
	var hull_hi := Color(0.65, 0.4, 0.15)
	var deck := Color(0.6, 0.45, 0.2)
	var water := Color(0.15, 0.3, 0.9)
	var water_hi := Color(0.3, 0.5, 1.0)
	var mast := Color(0.55, 0.35, 0.15)
	var flag := Color(1.0, 0.3, 0.0)
	var cx := S / 2
	# Water at bottom
	for x in range(S):
		var wave_y := 38 + int(sin(x * 0.25) * 3)
		for y in range(wave_y, S):
			var c := water_hi if (x + y) % 4 < 2 else water
			_put(img, x, y, c)
	# Hull (trapezoid)
	for y in range(28, 44):
		var inset := (y - 28) * 3 / 16
		var left := 8 + inset
		var right := S - 8 - inset
		for x in range(left, right):
			_put(img, x, y, hull)
	# Deck
	_fill_rect(img, 12, 28, S - 24, 4, deck)
	# Hull highlight
	_fill_rect(img, 12, 30, S - 24, 2, hull_hi)
	# Mast
	_fill_rect(img, cx - 1, 6, 3, 24, mast)
	# Flag
	_fill_rect(img, cx + 2, 6, 12, 8, flag)
	_fill_rect(img, cx + 2, 8, 10, 4, Color(1.0, 0.5, 0.1))
	return ImageTexture.create_from_image(img)
