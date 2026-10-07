class_name KillText
extends Node2D
## The score a player's kill shows over the wrecked tank, as Tank.exe wrote it
## (its Damage routine, 0x00492886): "+ N" for a lone kill; once a combo is on
## (the next kill within 2.7 s), "N Combos" over the score. The words sit on the
## tank, dip, then float up fading to half, and are gone after 1800 ticks, in the
## white font at half size.
##
## Only damage shows them: shells, fire, mines and blasts. The original's bomb
## set its victims' HP to nothing without going through Damage, so a bomb's kills
## show none.
##
## The numbers are the remake's: the points the kill scored. The original showed
## its own formula's, 20 for each point of the killing shot and each two types up,
## and a combo's multiplier after them ("+ 40 x125%").

const SCALE := 2.0
## One tick of the original's clock, in seconds.
const TICK := 0.00075
const DIP := 300 * TICK     # down 3 px
const RISE := 1500 * TICK   # then up 30, fading to half
const DIP_BY := 3.0 * SCALE
const RISE_BY := 30.0 * SCALE
const END_ALPHA := 128.0 / 255.0
const LIFETIME := DIP + RISE

## The original's white Text font at half size: lines 12 px high.
const FONT: FontFile = preload("res://assets/ui/fonts/white_font.fnt")
const LINE_HEIGHT := 12.0 * SCALE
## How far under the tank's top edge the words start: a lone kill's line 8 px,
## a combo's two lines 12 (the original's tanks are 32 high).
const LONE_TOP := 8.0 * SCALE
const COMBO_TOP := 12.0 * SCALE
const TANK_HALF := 16.0 * SCALE
## Over the grass (z 10), the blasts (z 20) and the items (z 21, drawn before
## the words), as the original's words (draw order 20) read over them all.
const Z_INDEX := 21

var _lines: PackedStringArray = []
var _widths: PackedFloat32Array = []  # each line's width
var _block := Vector2.ZERO    # the text's size
var _start := Vector2.ZERO    # its top-left when it appears
var _t := 0.0


## Shows the score of a kill worth [param points], the [param combo]th of a
## combo (1 for a lone kill), over the tank that stood at [param tank_centre].
static func spawn(parent: Node, points: int, combo: int, tank_centre: Vector2) -> KillText:
	NetHostWorld.record(NetWorld.EV_KILL_TEXT, [points, combo, tank_centre.x, tank_centre.y])
	var text := KillText.new()
	text.setup(points, combo, tank_centre)
	parent.add_child(text)
	return text


## The words for a kill worth [param points], the [param combo]th of a combo.
static func words(points: int, combo: int) -> PackedStringArray:
	var score := "+ %d" % points
	if combo < 2:
		return PackedStringArray([score])
	return PackedStringArray(["%d Combos" % combo, score])


func setup(points: int, combo: int, tank_centre: Vector2) -> void:
	_lines = words(points, combo)
	_widths.clear()
	for line in _lines:
		_widths.append(FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(LINE_HEIGHT)).x)
	_block = Vector2(Array(_widths).max(), LINE_HEIGHT * _lines.size())
	# Centred across the tank, as the original's offsets put its monospace lines.
	var top := LONE_TOP if _lines.size() == 1 else COMBO_TOP
	_start = Vector2(tank_centre.x - _block.x / 2.0, tank_centre.y - TANK_HALF + top)


func _ready() -> void:
	z_index = Z_INDEX
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


## The text's top-left now: 3 px down over 300 ticks, then 30 up over 1500.
func text_position() -> Vector2:
	return _start + Vector2(0, DIP_BY * _ramp(_t, 0.0, DIP) - RISE_BY * _ramp(_t, DIP, LIFETIME))


## Its opacity now: solid through the dip, then fading to half as it rises.
func text_alpha() -> float:
	return lerpf(1.0, END_ALPHA, _ramp(_t, DIP, LIFETIME))


func _draw() -> void:
	var at := text_position() + Vector2(0, FONT.get_ascent(int(LINE_HEIGHT)))
	var tint := Color(1, 1, 1, text_alpha())
	# Each line centred in the block, one line height apart.
	for i in _lines.size():
		var x := (_block.x - _widths[i]) / 2.0
		draw_string(FONT, at + Vector2(x, LINE_HEIGHT * i), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(LINE_HEIGHT), tint)


static func _ramp(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)
