class_name PickupText
extends Node2D
## The words a bonus item shows when a tank takes it, as Tank.exe drew them
## (0x49623f; the words are its table at 0x4d2de4, one per item type). Two
## copies sweep in from the field's left and right edges and meet on the item
## (the right-hand one is dropped there), then the text dips, floats up and is
## gone: 2000 ticks, 1.5 s, in all. It never fades or grows.
##
## Positions are the original's at 2x. A copy starts beyond the field's edge,
## so it slides out from under the HUD panel on that side (the original's
## screen edge).

const SCALE := 2.0
## One tick of the original's clock, in seconds.
const TICK := 0.00075
const SWEEP := 300 * TICK   # in to the item
const DIP := 300 * TICK     # down 5 px
const RISE := 1400 * TICK   # then up 35
const DIP_BY := 5.0 * SCALE
const RISE_BY := 35.0 * SCALE
const LIFETIME := SWEEP + DIP + RISE
## The item the words centre on: the original's 32 px cookie.
const ITEM_SIZE := 32.0 * SCALE

## The three looks the original used: the gold font, the gold font at half
## size, and the small cyan one.
enum Style { GOLD, GOLD_HALF, SMALL }
const GOLD_FONT: FontFile = preload("res://assets/ui/fonts/tank_font.fnt")
const SMALL_FONT: FontFile = preload("res://assets/ui/fonts/tank_font_tiny.fnt")
const CELLS: Dictionary = {
	Style.GOLD: Vector2(18, 36) * SCALE,
	Style.GOLD_HALF: Vector2(9, 18) * SCALE,
	Style.SMALL: Vector2(8, 16) * SCALE,
}

## Each item's words, lines split where the original put 0xFF (padded, as it
## did, so they look centred), and their look: the gold font for the two MAX
## items, half-size gold for the upgrades and add-ons, the small font for the
## rest.
const WORDS: Dictionary = {
	CookieData.CookieType.SPEED_UP: ["Speed Up", Style.GOLD_HALF],
	CookieData.CookieType.HP_UP: ["Armor Up", Style.GOLD_HALF],
	CookieData.CookieType.WEAPONS_UP: ["Power Up", Style.GOLD_HALF],
	CookieData.CookieType.STAR_UP: ["LEVEL UP", Style.GOLD_HALF],
	CookieData.CookieType.MAX_UP: [" MAX \nSpeed\nPower", Style.GOLD],
	CookieData.CookieType.ANTI_WATER_COOKIE: ["[ AmphiTank ]", Style.GOLD_HALF],
	CookieData.CookieType.ANTI_ICE_COOKIE: ["[ AntiSkid ]", Style.GOLD_HALF],
	CookieData.CookieType.MOON_SHIELD_COOKIE: ["[ Shield of Moon ]", Style.GOLD_HALF],
	CookieData.CookieType.MEMORY_SAVE_COOKIE: ["[ Memory of Sea ]", Style.GOLD_HALF],
	CookieData.CookieType.SCORE_200: ["+ 200", Style.SMALL],
	CookieData.CookieType.SCORE_500: ["+ 500", Style.SMALL],
	CookieData.CookieType.SCORE_1000: ["+1000", Style.SMALL],
	CookieData.CookieType.SCORE_2000: ["+2000", Style.SMALL],
	CookieData.CookieType.BULLETS_MAX: ["  MAX  \nCaisson\n Armor ", Style.GOLD],
	CookieData.CookieType.BULLET_REFILL: ["Caisson", Style.SMALL],
	CookieData.CookieType.INVINCIBLE_HELMET: ["Who PA Who", Style.SMALL],
	CookieData.CookieType.FLAG_PROTECTION: ["Flag On Guard", Style.SMALL],
	CookieData.CookieType.TANK_WEB: ["Hold Enemy", Style.SMALL],
	CookieData.CookieType.TANK_BOMB: ["Bomb !!", Style.SMALL],
	CookieData.CookieType.TANK_LIFE: ["+1 UP !!!", Style.SMALL],
	CookieData.CookieType.RAPID_COOKIE: ["[ Rapid Gun ]", Style.SMALL],
	CookieData.CookieType.FIRE_COOKIE: ["[ Fire Gun ]", Style.SMALL],
	CookieData.CookieType.AP_COOKIE: ["[ AP Gun ]", Style.SMALL],
	CookieData.CookieType.EXPLOSION_COOKIE: ["[ Explosion Gun ]", Style.SMALL],
	CookieData.CookieType.MINE_COOKIE: ["[ Mine ]", Style.SMALL],
}

var _lines: PackedStringArray = []
var _style: int = Style.SMALL
var _block := Vector2.ZERO           # the text's size
var _start_x: Array[float] = [0, 0]  # where each copy's left edge starts
var _settled := Vector2.ZERO         # the text's top-left once on the item
var _t := 0.0


## Shows [param cookie_type]'s words for an item taken at [param at] (its
## centre), on a field whose left edge is [param field_left] and which is
## [param field_width] wide. Returns null for an item with no words.
static func spawn(parent: Node, cookie_type: int, at: Vector2, field_left: float,
		field_width: float) -> PickupText:
	if not WORDS.has(cookie_type):
		return null
	var text := PickupText.new()
	text.setup(cookie_type, at, field_left, field_width)
	parent.add_child(text)
	return text


func setup(cookie_type: int, at: Vector2, field_left: float, field_width: float) -> void:
	_lines = (WORDS[cookie_type][0] as String).split("\n")
	_style = WORDS[cookie_type][1]
	var cell: Vector2 = CELLS[_style]
	var longest := 0
	for line in _lines:
		longest = maxi(longest, line.length())
	_block = Vector2(cell.x * longest, cell.y * _lines.size())
	# Centred on the item; the copies start that far into the field from
	# beyond its left edge, and one field width further right (0x4962f8).
	var from_edge := (ITEM_SIZE - _block.x) / 2.0 - ITEM_SIZE
	_start_x = [field_left + from_edge, field_left + field_width + from_edge]
	_settled = at - _block / 2.0


func _ready() -> void:
	# Above the tanks and items, under the HUD panels (drawn after it).
	z_index = 0
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


## Moves the effect on by [param seconds]; it frees itself when done.
func advance(seconds: float) -> void:
	_t += seconds
	queue_redraw()
	if _t >= LIFETIME:
		queue_free()


## The words shown, one entry per line.
func get_lines() -> PackedStringArray:
	return _lines


func get_style() -> int:
	return _style


## Where each copy still shown has its top-left now: two while they sweep in,
## then the one that stays.
func copy_positions() -> Array[Vector2]:
	var y := _settled.y + DIP_BY * _ramp(_t, SWEEP, SWEEP + DIP) \
			- RISE_BY * _ramp(_t, SWEEP + DIP, LIFETIME)
	var swept := _ramp(_t, 0.0, SWEEP)
	var positions: Array[Vector2] = []
	for copy in (2 if _t < SWEEP else 1):
		positions.append(Vector2(lerpf(_start_x[copy], _settled.x, swept), y))
	return positions


func _draw() -> void:
	var cell: Vector2 = CELLS[_style]
	var font: FontFile = SMALL_FONT if _style == Style.SMALL else GOLD_FONT
	var size := int(cell.y)
	var ascent := font.get_ascent(size)
	for at in copy_positions():
		# Lines are left-aligned in the block, one cell apart.
		for i in _lines.size():
			draw_string(font, at + Vector2(0, cell.y * i + ascent), _lines[i],
					HORIZONTAL_ALIGNMENT_LEFT, -1, size)


static func _ramp(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)
