class_name PickupText
extends Node2D
## The words a bonus item shows when a tank takes it, as Tank.exe wrote them
## (0x49623f; the words are its table at 0x4d2de4, one per item type). They
## appear on the item, dip, float up and are gone, never fading or growing.
##
## Sean's changes to the original (2026-09-24): the words just appear, where
## the original swept two copies in from the screen's edges to meet on the
## item; and the two MAX items use the upgrades' half-size gold, where the
## original wrote them in the full-size gold font.

const SCALE := 2.0
## One tick of the original's clock, in seconds.
const TICK := 0.00075
const DIP := 300 * TICK     # down 5 px
const RISE := 1400 * TICK   # then up 35
const DIP_BY := 5.0 * SCALE
const RISE_BY := 35.0 * SCALE
const LIFETIME := DIP + RISE

## The two looks: the gold font at half size (lines 18 high in the original)
## and the small cyan one (lines 16 high).
enum Style { GOLD, SMALL }
const GOLD_FONT: FontFile = preload("res://assets/ui/fonts/gold_font.fnt")
const SMALL_FONT: FontFile = preload("res://assets/ui/fonts/tiny_font.fnt")
const LINE_HEIGHTS: Dictionary = {
	Style.GOLD: 18.0 * SCALE,
	Style.SMALL: 16.0 * SCALE,
}

## Each item's words, lines split where the original put 0xFF, and their look:
## gold for the upgrades, the MAX items and the add-ons, the small font for the
## rest. Each line is centred on the item (the original padded its monospace
## lines with spaces to the same end; the padding is even, so it still is).
const WORDS: Dictionary = {
	CookieData.CookieType.SPEED_UP: ["Speed Up", Style.GOLD],
	CookieData.CookieType.HP_UP: ["Armor Up", Style.GOLD],
	CookieData.CookieType.WEAPONS_UP: ["Power Up", Style.GOLD],
	CookieData.CookieType.STAR_UP: ["LEVEL UP", Style.GOLD],
	CookieData.CookieType.MAX_UP: [" MAX \nSpeed\nPower", Style.GOLD],
	CookieData.CookieType.ANTI_WATER_COOKIE: ["[ AmphiTank ]", Style.GOLD],
	CookieData.CookieType.ANTI_ICE_COOKIE: ["[ AntiSkid ]", Style.GOLD],
	CookieData.CookieType.MOON_SHIELD_COOKIE: ["[ Shield of Moon ]", Style.GOLD],
	CookieData.CookieType.MEMORY_SAVE_COOKIE: ["[ Memory of Sea ]", Style.GOLD],
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
var _widths: PackedFloat32Array = []  # each line's width
var _style: int = Style.SMALL
var _block := Vector2.ZERO    # the text's size
var _start := Vector2.ZERO    # its top-left when it appears, centred on the item
var _t := 0.0


## Shows [param cookie_type]'s words for an item taken at [param at] (its
## centre). Returns null for an item with no words.
static func spawn(parent: Node, cookie_type: int, at: Vector2) -> PickupText:
	if not WORDS.has(cookie_type):
		return null
	var text := PickupText.new()
	text.setup(cookie_type, at)
	parent.add_child(text)
	return text


func setup(cookie_type: int, at: Vector2) -> void:
	_lines = (WORDS[cookie_type][0] as String).split("\n")
	_style = WORDS[cookie_type][1]
	var height: float = LINE_HEIGHTS[_style]
	_widths.clear()
	for line in _lines:
		_widths.append(_font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(height)).x)
	_block = Vector2(Array(_widths).max(), height * _lines.size())
	_start = at - _block / 2.0


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


## The words' size: the widest line by the lines' height.
func get_block() -> Vector2:
	return _block


## The words shown, one entry per line.
func get_lines() -> PackedStringArray:
	return _lines


func get_style() -> int:
	return _style


## The text's top-left now: 5 px down over 300 ticks, then 35 up over 1400.
func text_position() -> Vector2:
	return _start + Vector2(0, DIP_BY * _ramp(_t, 0.0, DIP) - RISE_BY * _ramp(_t, DIP, LIFETIME))


func _draw() -> void:
	var height: float = LINE_HEIGHTS[_style]
	var font := _font()
	var at := text_position() + Vector2(0, font.get_ascent(int(height)))
	# Each line centred in the block, one line height apart.
	for i in _lines.size():
		var x := (_block.x - _widths[i]) / 2.0
		draw_string(font, at + Vector2(x, height * i), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(height))


func _font() -> FontFile:
	return SMALL_FONT if _style == Style.SMALL else GOLD_FONT


static func _ramp(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)
