class_name StageOverlay
extends Control
## Tank.exe's stage screens, drawn over the playfield where the original drew
## them on its 640x480 screen (here at 2x: the playfield is 1280x960).
##
## - The intro (the original's state 4, 0x4c9a20): the stage's picture covers the
##   freshly built map in four quarters; "Stage NN" drops in above the caption;
##   after 2.25 s the letters swell, spin a full turn and fade while the quarters
##   fly off the screen, revealing the map, and play begins.
## - The mission screen (state 6, 0x4ca03c): "Mission Complete" or "Mission Fail"
##   rises to the top while the field plays on; after 2.25 s the win or lose
##   picture closes over it in four quarters.
## - The results (state 7, 0x4c90b4): over that picture a panel per player
##   slides in and counts up the stage's kills; a reward flies in for the best.
## - Game over (state 8, 0x4c8b74): "Game Over" fades in, then its letters fly
##   apart, growing, spinning and fading.
##
## Times are the original's at its default speed (1000 ticks = 0.75 s). Holding
## a fire button runs the intro, results and game over faster, as the original
## does: 3.5x with one player holding, 6x with both (an extra Move(50) per
## 20-tick step, 0x4ce31e). The mission screen can't be hurried.
## Positions in comments are the original's screen pixels.

signal intro_finished
signal mission_finished
## A player's stage reward lands: the game adds it to their score.
signal reward_given(player: int, amount: int)
signal results_finished
signal game_over_finished

## Original screen px -> overlay px.
const SCALE := 2.0
const SCREEN_SIZE := Vector2(640, 480) * SCALE
const QUARTER_SIZE := SCREEN_SIZE / 2.0
## One tick of the original's clock, in seconds.
const TICK := 0.00075

## The three fonts, in the colours of the original's gold (Text3), white (Text)
## and tiny (Text2), drawn from open-licensed pixel fonts (tools/make_fonts.py).
## They are proportional: text is measured, not counted in cells. A cell's
## height is the size a font is drawn at.
const GOLD_FONT: FontFile = preload("res://assets/ui/fonts/gold_font.fnt")
const WHITE_FONT: FontFile = preload("res://assets/ui/fonts/white_font.fnt")
const TINY_FONT: FontFile = preload("res://assets/ui/fonts/tiny_font.fnt")
const GOLD_CELL := Vector2(18, 36) * SCALE
const WHITE_CELL := Vector2(12, 24) * SCALE
const TINY_CELL := Vector2(8, 16) * SCALE

## What covers the field where a theme has no stage-end picture.
const PLAIN_BACKDROP := Color(0.05, 0.05, 0.07)

# --- The intro ---------------------------------------------------------------
# The text drops and fades in, holds, then everything leaves together.
const INTRO_IN_START := 500 * TICK
const INTRO_IN_END := 1000 * TICK
const INTRO_OUT_START := 3000 * TICK
const INTRO_END := 3500 * TICK
# "Stage NN" in the gold font at 2x (36x72 cells): its box drops from y -72 to
# 150 and ends twice as large, its bottom still at 222.
const STAGE_CELL := GOLD_CELL * 2.0
const STAGE_TOP_START := -72.0 * SCALE
const STAGE_TOP := 150.0 * SCALE
# The caption in the white font, a block of left-aligned lines centred at x 320
# with its top at y 279.
const CAPTION_TOP := 279.0 * SCALE

# --- The mission screen --------------------------------------------------------
const MISSION_RISE_END := 500 * TICK       # the title rises from y 222 to 50
const MISSION_CLOSE_START := 3000 * TICK   # the picture's quarters start closing
const MISSION_CLOSE_END := 3500 * TICK
const MISSION_END := 4000 * TICK
const TITLE_WON := "Mission Complete"
const TITLE_LOST := "Mission Fail"
const TITLE_TOP_START := 222.0 * SCALE
const TITLE_TOP := 50.0 * SCALE

# --- The results -----------------------------------------------------------------
# The panel (264x307) sits in each player's half of the screen, sliding in
# from beyond its own side.
const PANEL_SIZE := Vector2(264, 307) * SCALE
const PANEL_TOP := 110.0 * SCALE
const PANEL_HOME_X: Array[float] = [28.0 * SCALE, 348.0 * SCALE]
const PANEL_AWAY_X: Array[float] = [-264.0 * SCALE, 904.0 * SCALE]
const RESULTS_IN_END := 1000 * TICK        # slid in; the counters start rolling
const RESULTS_COUNT_END := 2000 * TICK     # counted up; the reward comes
const RESULTS_OUT_START_WON := 7000 * TICK # held longer when the game goes on
const RESULTS_OUT_START_LOST := 5000 * TICK
const RESULTS_OUT := 333 * TICK
## The panel's eight kill cells by enemy type (the remake's, the original's - 3),
## row by row as [left, right]; each kill in row r scores r + 1 (table 0x4d2bb0).
const KILL_CELLS: Array = [
	[[1, 2], [3, 4]],                      # x1: plain shells
	[[5, 6, 7, 8], [21, 22, 23, 24]],      # x2: rapid fire, mines
	[[17, 18, 19, 20], [9, 10, 11, 12]],   # x3: explosive, fire
	[[13, 14], [15, 16]],                  # x4: armour-piercing
]
## The tank each cell shows (the last of its types, facing up), drawn on a
## panel the theme doesn't picture.
const KILL_CELL_ICONS: Array = [[2, 4], [8, 24], [20, 12], [14, 16]]
# Where the panel's text goes, from its top-left (original px).
const MAX_HITS_AT := Vector2(28, 74)
const NUMBERS_RIGHT := 240.0               # the right-aligned columns end here
const ROW_TEXT_AT := Vector2(60, 110)      # "LL      RR    xN =" (the points 4 px higher)
const ROW_STEP := 32.0
const TOTAL_TOP := 256.0
# Our own box around it all (a theme may bring a picture instead), in the menus'
# style: their panel, a gold header with the player's tag, a band for the chains
# and one per kill row, gold rules. Laid out on the original's panel (original px).
const BOX_THEME: Theme = preload("res://assets/ui/menu_theme.tres")
const BOX_HEADER := "RESULTS"
const BOX_TOTAL := "TOTAL"
const BOX_HEADER_TOP := 16.0
const BOX_RULES: Array[float] = [62.0, 236.0]   # under the header, over the total
const BOX_RULE_COLOUR := Color(0.85, 0.62, 0.16, 0.85)
const BOX_INSET := 12.0                          # the bands' and rules' side margin
const CHAIN_BAND := Rect2(BOX_INSET, 70, 264 - 2 * BOX_INSET, 24)
const KILL_BAND_TOP := 96.0                      # each kill row's band: 31 tall, one per ROW_STEP
## The players' tags and colours, as the HUD's "I P" and "II P".
const PLAYER_TAGS: Array[String] = ["I P", "II P"]
const PLAYER_TAG_COLOURS: Array[Color] = [Color(0.9, 0.7, 0.1), Color(0.1, 0.8, 0.2)]

# --- The reward ------------------------------------------------------------------
## Reward per difficulty (0-5), times 30 for beating the other player or 10 for
## a clear alone or level with them (table 0x4d2860, bonus callback 0x4cb660).
const REWARD_FACTORS: Array[int] = [33, 66, 100, 150, 200, 250]
const REWARD_WIN_TIMES := 30
const REWARD_SHARE_TIMES := 10
const REWARD_WIN_COPIES := 6
const REWARD_SHARE_COPIES := 4
## "Reward +N" copies fly in to just under the panel (y 426), the lead settling
## bright and the rest faint behind it, then all fly off the top (y -52).
const REWARD_TOP := 426.0 * SCALE
const REWARD_GONE_TOP := -52.0 * SCALE
const REWARD_FLY := 333                    # ticks, each copy after 100 x its place
const REWARD_SETTLE := 333                 # the lead; the others 60 x their place less
const REWARD_HOLD := 750

# --- Game over -------------------------------------------------------------------
## "Game Over" in the gold font at 2x, centred where the original's nine
## 36 px cells stood (x 176 to 500), at y 204.
const GAME_OVER_TEXT := "Game Over"
const GAME_OVER_CENTRE_X := (176.0 + 9 * 36 / 2.0) * SCALE
const GAME_OVER_TOP := 204.0 * SCALE
const GAME_OVER_CELL := GOLD_CELL * 2.0
const GAME_OVER_FADE_END := 1500 * TICK
const GAME_OVER_FLY_START := 3000 * TICK
const GAME_OVER_FLY_END := 4500 * TICK
const GAME_OVER_END := 5500 * TICK
## A flying letter ends 72x216: twice as wide, three times as tall.
const GAME_OVER_GROWTH := Vector2(2, 3)
## The original's tiny font was 8 px wide a character, and the results panel
## was laid out in its columns: they still fix where each field goes.
const ORIGINAL_COLUMN := 8.0

enum Mode { NONE, INTRO, MISSION, RESULTS, GAME_OVER }

## One of the original's three ways for the quarters to move (0x4c9c60,
## 0x4ca1e7): 0 top / bottom, 1 each out of its own corner, 2 left / right.
var quarter_pattern: int = 0

var _mode: Mode = Mode.NONE
var _t: float = 0.0
var _picture: Texture2D = null
## Where a theme has no picture, stage-end screens cover the field with a plain
## backdrop; an intro just plays over the map.
var _plain_backdrop := false
var _stage_text: String = ""
var _caption_lines: PackedStringArray = []
var _title: String = ""
var _won := false
var _panels: Array[ResultsPanel] = []
var _panel_texture: Texture2D = null
var _band_styles: Array[StyleBoxFlat] = []   # a kill row's band: even rows, odd rows
var _rewarded := false
var _letters: Array[FlyingLetter] = []


## One player's results panel.
class ResultsPanel:
	var player: int = 0
	## Kills per cell, [row][side].
	var kills: Array = []
	var max_hits: int = 0
	var max_combos: int = 0
	var total: int = 0
	var reward: int = 0
	## The reward that beat the other player (it has its own sound).
	var reward_won := false
	var copies: Array[RewardCopy] = []

	func row_points(row: int) -> int:
		return (kills[row][0] + kills[row][1]) * (row + 1)


## One copy of a panel's "Reward +N".
class RewardCopy:
	var start: Vector2
	var target: Vector2


## One letter of "Game Over" and where it flies.
class FlyingLetter:
	var glyph: String
	var width: float   # the glyph's own width, drawn GAME_OVER_CELL high
	var home: Vector2
	var away: Vector2
	var turns: float


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	visible = false
	for alpha in [0.05, 0.025]:
		var band := StyleBoxFlat.new()
		band.bg_color = Color(1, 1, 1, alpha)
		band.border_color = Color(1, 1, 1, 0.07)
		band.set_border_width_all(1)
		band.set_corner_radius_all(4)
		_band_styles.append(band)


## Covers the playfield with [param stage_num]'s intro and plays it; emits
## [signal intro_finished] once the map is revealed.
func play_intro(stage_num: int) -> void:
	_picture = ThemeManager.get_stage_picture(LevelData.get_stage_intro_picture(stage_num))
	_plain_backdrop = false
	_title = ""
	_stage_text = "Stage %02d" % stage_num
	_caption_lines = LevelData.get_stage_caption_lines(stage_num)
	quarter_pattern = randi() % 3
	_start(Mode.INTRO)


## "Mission Complete" ([param won]) or "Mission Fail" over the running field,
## then the stage-end picture closes over it; emits [signal mission_finished].
func play_mission(won: bool) -> void:
	_won = won
	_title = TITLE_WON if won else TITLE_LOST
	_picture = ThemeManager.get_screen_texture("stage_win" if won else "stage_lose")
	_plain_backdrop = _picture == null
	quarter_pattern = randi() % 3
	_start(Mode.MISSION)


## The results panels, one per entry of [param tallies]: {"player": 0/1,
## "kills": {enemy type: count}, "max_hits", "max_combos"}. After a won stage
## ([param won]) the best total earns a reward scaled by [param difficulty],
## handed over by [signal reward_given]. Emits [signal results_finished].
func play_results(won: bool, tallies: Array, difficulty: int) -> void:
	_won = won
	_panels.clear()
	for tally: Dictionary in tallies:
		var panel := ResultsPanel.new()
		panel.player = tally["player"]
		panel.kills = cell_kills(tally["kills"])
		panel.max_hits = tally.get("max_hits", 0)
		panel.max_combos = tally.get("max_combos", 0)
		for row in KILL_CELLS.size():
			panel.total += panel.row_points(row)
		_panels.append(panel)
	if won:
		var totals: Array[int] = []
		for panel in _panels:
			totals.append(panel.total)
		var rewards := rewards_for(totals, difficulty)
		for i in _panels.size():
			_panels[i].reward = rewards[i]["amount"]
			_panels[i].reward_won = rewards[i]["beat_other"]
			_panels[i].copies = _make_copies(_panels[i], rewards[i]["copies"])
	_panel_texture = ThemeManager.get_screen_texture("results_panel")
	_rewarded = false
	_start(Mode.RESULTS)


## "Game Over" over the lost stage's picture; emits [signal game_over_finished].
func play_game_over() -> void:
	_letters.clear()
	var lefts := _glyph_lefts(GOLD_FONT, GAME_OVER_CELL, GAME_OVER_TEXT)
	var left := GAME_OVER_CENTRE_X - _text_width(GOLD_FONT, GAME_OVER_CELL, GAME_OVER_TEXT) / 2.0
	for i in GAME_OVER_TEXT.length():
		if GAME_OVER_TEXT[i] == " ":
			continue
		var letter := FlyingLetter.new()
		letter.glyph = GAME_OVER_TEXT[i]
		letter.width = GOLD_FONT.get_char_size(GAME_OVER_TEXT.unicode_at(i), int(GAME_OVER_CELL.y)).x
		letter.home = Vector2(left + lefts[i], GAME_OVER_TOP)
		# Off whichever edge Random(4) picks, a whole enlarged letter beyond it.
		match randi() % 4:
			0: letter.away = Vector2(randi() % 640, -272)
			1: letter.away = Vector2(randi() % 640, 680)
			2: letter.away = Vector2(-236, randi() % 480)
			_: letter.away = Vector2(840, randi() % 480)
		letter.away *= SCALE
		# Random(1024) - 512 in 256ths of a turn: up to two turns either way.
		letter.turns = (randi() % 1024 - 512) / 256.0
		_letters.append(letter)
	_start(Mode.GAME_OVER)


func is_playing() -> bool:
	return _mode != Mode.NONE


## The screen showing now, by name: "intro", "mission", "results", "game_over"
## or "" when none is.
func get_screen() -> String:
	return ["", "intro", "mission", "results", "game_over"][_mode]


## How far the showing screen has got, in seconds of its own clock.
func get_time() -> float:
	return _t


func _start(mode: Mode) -> void:
	_mode = mode
	_t = 0.0
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _mode == Mode.NONE:
		return
	advance(delta * (1.0 if _mode == Mode.MISSION else _speed()))


## Moves the showing screen on by [param seconds] of its own clock.
func advance(seconds: float) -> void:
	var before := _t
	_t += seconds
	queue_redraw()
	match _mode:
		Mode.INTRO:
			if _t >= INTRO_END:
				_mode = Mode.NONE
				visible = false
				intro_finished.emit()
		Mode.MISSION:
			if _t >= MISSION_END:
				# The picture and title stay up for the results.
				_mode = Mode.NONE
				mission_finished.emit()
		Mode.RESULTS:
			if not _rewarded and _t >= RESULTS_COUNT_END:
				_rewarded = true
				for panel in _panels:
					if panel.reward > 0:
						reward_given.emit(panel.player, panel.reward)
			# The winner's reward sounds as its lead copy settles.
			var settled := RESULTS_COUNT_END + (REWARD_FLY + REWARD_SETTLE) * TICK
			if before < settled and _t >= settled:
				for panel in _panels:
					if panel.reward_won:
						SoundManager.play(&"bonus_reward")
			if _t >= _results_end():
				_mode = Mode.NONE
				results_finished.emit()
		Mode.GAME_OVER:
			if _t >= GAME_OVER_END:
				_mode = Mode.NONE
				game_over_finished.emit()


## How fast the clock runs: every player holding a fire button adds 2.5x.
func _speed() -> float:
	var holding := 0
	for prefix in ["p1_", "p2_"]:
		if Input.is_action_pressed(prefix + "shoot") or Input.is_action_pressed(prefix + "shoot2"):
			holding += 1
	return 1.0 + 2.5 * holding


func _results_out_start() -> float:
	return RESULTS_OUT_START_WON if _won else RESULTS_OUT_START_LOST


func _results_end() -> float:
	return _results_out_start() + RESULTS_OUT


# =====================================================================
# The rules
# =====================================================================

## A player's kills ([param kills]: enemy type -> count) sorted into the panel's
## cells, [row][left, right].
static func cell_kills(kills: Dictionary) -> Array:
	var cells: Array = []
	for row: Array in KILL_CELLS:
		var counts: Array[int] = []
		for types: Array in row:
			var n := 0
			for type_id: int in types:
				n += int(kills.get(type_id, 0))
			counts.append(n)
		cells.append(counts)
	return cells


## Each panel's reward after a won stage, from the panels' [param totals] (one
## or two) at [param difficulty]: {"amount", "copies", "beat_other"}. Beating
## the other player's total pays 30x; a total above 0 that's alone or level
## pays 10x; anything less, nothing.
static func rewards_for(totals: Array[int], difficulty: int) -> Array:
	var factor: int = REWARD_FACTORS[clampi(difficulty, 0, REWARD_FACTORS.size() - 1)]
	var rewards: Array = []
	for i in totals.size():
		var other := -1 if totals.size() < 2 else totals[1 - i]
		var reward := {"amount": 0, "copies": 0, "beat_other": false}
		if other >= 0 and totals[i] > other:
			reward = {"amount": factor * REWARD_WIN_TIMES, "copies": REWARD_WIN_COPIES, "beat_other": true}
		elif totals[i] > 0 and totals[i] >= other:
			reward = {"amount": factor * REWARD_SHARE_TIMES, "copies": REWARD_SHARE_COPIES, "beat_other": false}
		rewards.append(reward)
	return rewards


## Where each copy of [param panel]'s reward comes from: Random(2) picks the
## top (anywhere across) or the far side of the screen (anywhere down).
func _make_copies(panel: ResultsPanel, count: int) -> Array[RewardCopy]:
	var copies: Array[RewardCopy] = []
	var width := _text_width(GOLD_FONT, GOLD_CELL, _reward_text(panel))
	var target_x := PANEL_HOME_X[panel.player] + floorf((PANEL_SIZE.x - width) / 2.0 / SCALE) * SCALE
	for k in count:
		var copy := RewardCopy.new()
		if randi() % 2 == 0:
			copy.start = Vector2(randi() % 640 - 16, -216) * SCALE
		elif panel.player == 0:
			copy.start = Vector2(624 * SCALE, (randi() % 480 - 16) * SCALE)
		else:
			copy.start = Vector2(-width - 16 * SCALE, (randi() % 480 - 16) * SCALE)
		copy.target = Vector2(target_x, REWARD_TOP)
		copies.append(copy)
	return copies


static func _reward_text(panel: ResultsPanel) -> String:
	return "Reward +%d" % panel.reward


# =====================================================================
# Drawing
# =====================================================================

func _draw() -> void:
	match _mode:
		Mode.INTRO:
			_draw_quarters(_ramp(_t, INTRO_OUT_START, INTRO_END))
			_draw_stage_text()
			_draw_caption(_ramp(_t, INTRO_IN_START, INTRO_IN_END) - _ramp(_t, INTRO_OUT_START, INTRO_END))
		Mode.MISSION:
			_draw_quarters(1.0 - _ramp(_t, MISSION_CLOSE_START, MISSION_CLOSE_END))
			_draw_title(lerpf(TITLE_TOP_START, TITLE_TOP, _ramp(_t, 0.0, MISSION_RISE_END)))
		Mode.RESULTS:
			_draw_quarters(0.0)
			_draw_title(TITLE_TOP)
			for panel in _panels:
				_draw_panel(panel)
		Mode.GAME_OVER:
			_draw_quarters(0.0)
			_draw_title(TITLE_TOP)
			_draw_game_over()
		Mode.NONE:
			# Between screens (a mission handing over to its results) the
			# picture and title hold.
			if _title != "":
				_draw_quarters(0.0)
				_draw_title(TITLE_TOP)


## The picture in four quarters, each [param away] (0..1) of the way off the
## screen along the quarter pattern.
func _draw_quarters(away: float) -> void:
	if away >= 1.0 or (_picture == null and not _plain_backdrop):
		return
	var source_quarter := _picture.get_size() / 2.0 if _picture else Vector2.ZERO
	for k in 4:
		var cell := Vector2(k & 1, k >> 1)
		var home := cell * QUARTER_SIZE
		var off := Vector2.ZERO
		if quarter_pattern >= 1:
			off.x = (-1.0 if cell.x == 0 else 1.0) * QUARTER_SIZE.x
		if quarter_pattern <= 1:
			off.y = (-1.0 if cell.y == 0 else 1.0) * QUARTER_SIZE.y
		var rect := Rect2(home + off * away, QUARTER_SIZE)
		if _picture:
			draw_texture_rect_region(_picture, rect, Rect2(cell * source_quarter, source_quarter))
		else:
			draw_rect(rect, PLAIN_BACKDROP)


## "Stage NN": dropping in, holding, then swelling to twice its size while each
## letter spins a full turn clockwise about its own centre and fades out.
func _draw_stage_text() -> void:
	var grow := _ramp(_t, INTRO_OUT_START, INTRO_END)
	var stretch := 1.0 + grow
	var cell := STAGE_CELL * stretch
	# Dropping in, then growing upward: the bottom stays at y 222 (the box's
	# y and height blend linearly together in the original).
	var top := lerpf(STAGE_TOP_START, STAGE_TOP, _ramp(_t, INTRO_IN_START, INTRO_IN_END)) \
			- (cell.y - STAGE_CELL.y)
	var lefts := _glyph_lefts(GOLD_FONT, STAGE_CELL, _stage_text)
	var left := (SCREEN_SIZE.x - _text_width(GOLD_FONT, STAGE_CELL, _stage_text) * stretch) / 2.0
	for i in _stage_text.length():
		var width := GOLD_FONT.get_char_size(_stage_text.unicode_at(i), int(STAGE_CELL.y)).x
		var centre := Vector2(left + (lefts[i] + width / 2.0) * stretch, top + cell.y / 2.0)
		_draw_glyph(GOLD_FONT, _stage_text[i], STAGE_CELL, centre, Vector2.ONE * stretch,
				TAU * grow, Color(1, 1, 1, 1.0 - grow))


func _draw_caption(alpha: float) -> void:
	if _caption_lines.is_empty() or alpha <= 0.0:
		return
	var widest := 0.0
	for line in _caption_lines:
		widest = maxf(widest, _text_width(WHITE_FONT, WHITE_CELL, line))
	var left := (SCREEN_SIZE.x - widest) / 2.0
	for i in _caption_lines.size():
		_draw_text(WHITE_FONT, WHITE_CELL, Vector2(left, CAPTION_TOP + WHITE_CELL.y * i),
				_caption_lines[i], Color(1, 1, 1, alpha))


## The mission title, centred, its top at [param top]. It never fades: the
## original drew it without its alpha flag.
func _draw_title(top: float) -> void:
	var left := (SCREEN_SIZE.x - _text_width(GOLD_FONT, GOLD_CELL, _title)) / 2.0
	_draw_text(GOLD_FONT, GOLD_CELL, Vector2(left, top), _title)


func _draw_panel(panel: ResultsPanel) -> void:
	var at := Vector2(_panel_x(panel.player), PANEL_TOP)
	if _panel_texture:
		draw_texture_rect(_panel_texture, Rect2(at, PANEL_SIZE), false)
	else:
		_draw_box(at, panel.player)
	# The kill counts show at once; everything scored rolls up after the slide.
	var rolled := _ramp(_t, RESULTS_IN_END, RESULTS_COUNT_END)
	# The original wrote these as monospace lines ("MaxHits %2d", "%2d      %2d
	# xN ="); each field goes where its columns were, the numbers right-aligned.
	_draw_text(TINY_FONT, TINY_CELL, at + MAX_HITS_AT * SCALE, "MaxHits")
	_draw_text_right(TINY_FONT, TINY_CELL, at + (MAX_HITS_AT + Vector2(ORIGINAL_COLUMN * 10, 0)) * SCALE,
			str(roundi(panel.max_hits * rolled)))
	_draw_text_right(TINY_FONT, TINY_CELL, at + Vector2(NUMBERS_RIGHT - ORIGINAL_COLUMN * 3, MAX_HITS_AT.y) * SCALE,
			"MaxCombos")
	_draw_text_right(TINY_FONT, TINY_CELL, at + Vector2(NUMBERS_RIGHT, MAX_HITS_AT.y) * SCALE,
			str(roundi(panel.max_combos * rolled)))
	for row in KILL_CELLS.size():
		var y := ROW_TEXT_AT.y + ROW_STEP * row
		for side in 2:
			var right := ROW_TEXT_AT.x + ORIGINAL_COLUMN * (2 + 8 * side)
			_draw_text_right(TINY_FONT, TINY_CELL, at + Vector2(right, y) * SCALE, str(panel.kills[row][side]))
		_draw_text(TINY_FONT, TINY_CELL, at + Vector2(ROW_TEXT_AT.x + ORIGINAL_COLUMN * 14, y) * SCALE,
				"x%d =" % (row + 1))
		var points := str(roundi(panel.row_points(row) * rolled))
		_draw_text_right(TINY_FONT, TINY_CELL, at + Vector2(NUMBERS_RIGHT, y - 4) * SCALE, points)
	var total := str(roundi(panel.total * rolled))
	_draw_text_right(GOLD_FONT, GOLD_CELL, at + Vector2(NUMBERS_RIGHT, TOTAL_TOP) * SCALE, total)
	_draw_reward(panel, at.x - PANEL_HOME_X[panel.player])


## The results box's header and the name of its total, in the menus' language:
## the in-game screens stay English but for these two, which in Chinese are the
## original panel's own words, 战斗成绩 and 总计.
func box_words() -> PackedStringArray:
	return PackedStringArray([tr(BOX_HEADER), tr(BOX_TOTAL)])


## Our results box (see BOX_THEME): the panel, the header and the player's tag,
## the bands, the kill cells' tanks, the rules and "TOTAL". The counts go on it
## where the original's panel had them.
func _draw_box(at: Vector2, player: int) -> void:
	BOX_THEME.get_stylebox("panel", "MenuPanel").draw(get_canvas_item(), Rect2(at, PANEL_SIZE))
	var words := box_words()
	var header_left := (PANEL_SIZE.x - _text_width(GOLD_FONT, GOLD_CELL, words[0])) / 2.0
	_draw_text(GOLD_FONT, GOLD_CELL, at + Vector2(header_left, BOX_HEADER_TOP * SCALE), words[0])
	draw_string(ThemeDB.fallback_font, at + Vector2(BOX_INSET + 4, 36) * SCALE, PLAYER_TAGS[player],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * SCALE), PLAYER_TAG_COLOURS[player])
	_band_styles[0].draw(get_canvas_item(), Rect2(at + CHAIN_BAND.position * SCALE, CHAIN_BAND.size * SCALE))
	for row in KILL_CELL_ICONS.size():
		var band := Rect2(BOX_INSET, KILL_BAND_TOP + ROW_STEP * row, 264 - 2 * BOX_INSET, ROW_STEP - 1)
		_band_styles[row % 2].draw(get_canvas_item(), Rect2(at + band.position * SCALE, band.size * SCALE))
		for side in 2:
			var icon := ThemeManager.get_tank_texture("e%d" % KILL_CELL_ICONS[row][side])
			if icon:
				var icon_at := at + Vector2(21 + 64 * side, KILL_BAND_TOP + ROW_STEP * row) * SCALE
				draw_texture_rect(icon, Rect2(icon_at, Vector2(32, 32) * SCALE), false)
	for y in BOX_RULES:
		draw_line(at + Vector2(BOX_INSET, y) * SCALE, at + Vector2(264 - BOX_INSET, y) * SCALE, BOX_RULE_COLOUR, SCALE)
	_draw_text(GOLD_FONT, GOLD_CELL, at + Vector2(20, TOTAL_TOP) * SCALE, words[1])


## Where [param player]'s panel is: sliding in, held, sliding back out.
func _panel_x(player: int) -> float:
	var shown := _ramp(_t, 0.0, RESULTS_IN_END) - _ramp(_t, _results_out_start(), _results_end())
	return lerpf(PANEL_AWAY_X[player], PANEL_HOME_X[player], shown)


## The copies of [param panel]'s "Reward +N", moving with the panel (they are
## its children in the original): each waits 100 ticks per place, flies in as
## it brightens from alpha 64 to 128, settles (the lead to 255, the rest down
## to 48), holds, and flies off the top.
func _draw_reward(panel: ResultsPanel, shift: float) -> void:
	if panel.copies.is_empty() or _t < RESULTS_COUNT_END:
		return
	var ticks := (_t - RESULTS_COUNT_END) / TICK
	var text := _reward_text(panel)
	var leave_ticks := (panel.reward + 7500) / 6
	# The lead draws on top.
	for k in range(panel.copies.size() - 1, -1, -1):
		var copy := panel.copies[k]
		var fly_start := 100.0 * k
		var settle_start := fly_start + REWARD_FLY
		var settle_ticks := REWARD_SETTLE - 60 * k
		var leave_start := settle_start + settle_ticks + REWARD_HOLD
		var leave_end := leave_start + leave_ticks
		if ticks >= leave_end:
			continue
		var pos := copy.start.lerp(copy.target, _ramp(ticks, fly_start, settle_start))
		pos.y = lerpf(pos.y, REWARD_GONE_TOP, _ramp(ticks, leave_start, leave_end))
		var alpha := lerpf(64, 128, _ramp(ticks, fly_start, settle_start))
		alpha = lerpf(alpha, 255 if k == 0 else 48, _ramp(ticks, settle_start, settle_start + settle_ticks))
		_draw_text(GOLD_FONT, GOLD_CELL, pos + Vector2(shift, 0), text, Color(1, 1, 1, alpha / 255.0))


## Each letter fades in, holds, then flies to its own spot off the screen,
## stretching to 2x3 its size, spinning and fading as it goes.
func _draw_game_over() -> void:
	var shown := _ramp(_t, 0.0, GAME_OVER_FADE_END)
	var gone := _ramp(_t, GAME_OVER_FLY_START, GAME_OVER_FLY_END)
	if gone >= 1.0:
		return
	var stretch := Vector2.ONE.lerp(GAME_OVER_GROWTH, gone)
	for letter in _letters:
		var top_left := letter.home.lerp(letter.away, gone)
		var size := Vector2(letter.width, GAME_OVER_CELL.y) * stretch
		_draw_glyph(GOLD_FONT, letter.glyph, GAME_OVER_CELL, top_left + size / 2.0,
				stretch, TAU * letter.turns * gone, Color(1, 1, 1, shown * (1.0 - gone)))


## [param text] in [param font] drawn [param cell] high, its top-left at
## [param top_left].
func _draw_text(font: FontFile, cell: Vector2, top_left: Vector2, text: String,
		color := Color.WHITE) -> void:
	var size := int(cell.y)
	draw_string(font, top_left + Vector2(0, font.get_ascent(size)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## [param text] ending at [param top_right].x.
func _draw_text_right(font: FontFile, cell: Vector2, top_right: Vector2, text: String) -> void:
	_draw_text(font, cell, top_right - Vector2(_text_width(font, cell, text), 0), text)


## One glyph of [param font] drawn [param cell] high, centred on [param centre],
## scaled by [param stretch] and turned [param angle] radians clockwise about
## its centre.
func _draw_glyph(font: FontFile, glyph: String, cell: Vector2, centre: Vector2, stretch: Vector2,
		angle: float, color: Color) -> void:
	var size := int(cell.y)
	var width := font.get_char_size(glyph.unicode_at(0), size).x
	draw_set_transform(centre, angle, stretch)
	draw_char(font, Vector2(-width / 2.0, -cell.y / 2.0 + font.get_ascent(size)), glyph, size, color)
	draw_set_transform(Vector2.ZERO)


## [param text]'s width in [param font] drawn [param cell] high.
static func _text_width(font: FontFile, cell: Vector2, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell.y)).x


## Where each of [param text]'s glyphs starts, from the text's left.
static func _glyph_lefts(font: FontFile, cell: Vector2, text: String) -> Array[float]:
	var lefts: Array[float] = []
	var x := 0.0
	for i in text.length():
		lefts.append(x)
		x += font.get_char_size(text.unicode_at(i), int(cell.y)).x
	return lefts


## 0 before [param from], 1 after [param to], linear between.
static func _ramp(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)
