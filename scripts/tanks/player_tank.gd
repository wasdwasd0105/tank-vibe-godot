class_name PlayerTank
extends BaseTank

@export var player_id: int = 0  # 0 or 1

# --- HP system ---
const MAX_HP: int = 8
const DEFAULT_HP: int = 4

# --- Speed & weapon levels (0-3, default 0) ---
var speed_level: int = 1
var weapon_level: int = 0

# --- Secondary weapon ---
var secondary_weapon_type: String = "rapid"
var secondary_weapon_count: int = 50

var has_boat: bool = false
var is_invincible: bool = false
var invincible_timer: float = 0.0
var is_spawning: bool = false
var spawn_timer: float = 0.0
var _hits_taken: int = 0

# --- Addon system ---
var has_moon_shield: bool = false
var has_anti_ice: bool = false
var has_memory_save: bool = false
var _addon_sprites: Dictionary = {}  # addon_name -> Sprite2D
var _shield_sprite: Sprite2D = null
# anti-water, anti-ice, memory-save are mutually exclusive (only one active at a time)
const UTILITY_ADDONS: Array = ["anti-water", "anti-ice", "memory-save"]
var _current_utility_addon: String = ""
## Add-on size relative to TANK_SIZE. Where each one sits is BaseTank's
## _layout_addons, as the original placed them.
const ADDON_CONFIG: Dictionary = {
	"moon-shield":  { "scale": 1.0 },
	"anti-water":   { "scale": 1.0 },
	"anti-ice":     { "scale": 1.0 },
	"memory-save":  { "scale": 1.0 },
}

const SPAWN_INVINCIBILITY: float = 3.0
## Tank.exe showed the shield wreath only while at least 3000 ticks (2.25 s) of
## invulnerability were left, which in practice means the helmet cookie. Any
## shorter invulnerability, and the helmet's last 2.25 s, blinked instead: the
## tank drawn on every other frame (its DoDraw, 0x0049208c).
const WREATH_MIN_LEFT: float = 2.25
var _helmet_invincible: bool = false
var _wreath_shown: bool = false
## A player held by an enemy's "Hold Enemy" is wrapped in frost: the ringed web
## while more than 5000 ticks of the hold are left, the bare web down to 1000,
## then none (Tank.exe 0x0049495a). The frost covers the helmet's wreath.
const HOLD_RING_LEFT: float = 3.75
const HOLD_WEB_LEFT: float = 0.75
var _hold_shown: int = 0  # 2 ringed web, 1 bare web, 0 none
## A player who survives a hit is untouchable for 750 ticks (0.5625 s), blinking
## like any short invincibility (Tank.exe's Damage, 0x00492640). Bots get none,
## and neither does a tank hit while airborne.
const HIT_GRACE: float = 0.5625
## The frame whose hit started the grace. The original dealt a blast's or a
## shell's damage in one go before the grace began, so the rest of that same
## hit still lands.
var _hit_grace_frame: int = -1

# Controller rumble [weak motor, strong motor, seconds]: a jolt per hit that
# costs HP, a big one when the tank is destroyed or a mine throws it; and
# (Sean, 2026-09-25) a lighter thump for each enemy the player destroys, and
# the big one again for a bomb taken, which covers the bomb's own kills.
const HIT_RUMBLE: Array[float] = [0.45, 0.6, 0.2]
const DEATH_RUMBLE: Array[float] = [0.9, 1.0, 0.55]
const MINE_THROW_RUMBLE: Array[float] = [0.6, 0.9, 0.35]
const KILL_RUMBLE: Array[float] = [0.3, 0.5, 0.15]
const BOMB_RUMBLE: Array[float] = DEATH_RUMBLE

const POWERUP_INVINCIBILITY: float = 10.0

# Player colors
const PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.0),   # Player 1: Yellow/Gold
	Color(0.3, 0.85, 0.3),   # Player 2: Green
]

# Speed mapping: speed_level -> pixels/sec
const SPEED_MAP: Dictionary = {
	0: 96.0,
	1: 128.0,
	2: 160.0,
	3: 192.0,
}

const REGULAR_WEAPON_COOLDOWN_MAP: Dictionary = {
	0: 0.7,
	1: 0.4,
	2: 0.3,
	3: 0.25,
}

const PLAYER_MAX_ACTIVE_BULLETS: int = 12
## Secondary weapons that keep firing while their button is held (the others
## fire once a press).
const AUTO_SECONDARY: Array[String] = ["rapid", "fire", "explosion", "ap"]
## The rows a shot leaves from, as a client numbers them (Net.note_shot).
const SHOT_ROWS: Array[float] = [FIRE_ROW_LEFT, FIRE_ROW_MID, FIRE_ROW_RIGHT]
## Host: a client's own shot that can't be fired here for this long (a shell
## of its kind still flying here, say) is let go: its ghost there goes too.
const CLIENT_SHOT_WAIT_MS := 500

var _regular_fire_step: int = 0
var _rapid_special_fire_step: int = 0
var _rapid_special_ammo_progress: int = 0

# --- Online: lag compensation (docs/network_design.md section 7) ---

## Host: a client's tank's copy here catches up at up to this many times its own
## speed. Held up this far behind it for this long (by what the client didn't
## see in time), the client is told to start again from the host's position.
const FOLLOW_SPEED := 2.0
const APART_DISTANCE := 24.0
const APART_TIME := 0.3
## Host: the client's reports are played back steadily, a frame of its own a
## frame here, as far behind as they need: how late 98 in 100 of the latest
## came (PlayerInput's LATE_REPORTS) plus PLAY_SPARE, in frames, between these
## bounds; PLAY_DELAY_START until it has seen 30 come. So its tank moves here as
## smoothly as it drove, however unevenly the network brings them.
const PLAY_DELAY_START := 3.0
const PLAY_DELAY_MIN := 1.0
const PLAY_DELAY_MAX := 15.0
const PLAY_SPARE := 1.0
## Off that place (the delay changed, or either machine's frames slipped
## against the other's), the playback gets back to it by running slower or
## faster, never by going back: a tenth slower when it's too close behind the
## newest report, and faster by a sixtieth for each frame it's too far behind,
## from a hundredth to a tenth faster.
const PLAY_SLOWER := 0.1
const PLAY_FASTER_PER_FRAME := 1.0 / 60.0
const PLAY_FASTER_MIN := 0.01
const PLAY_FASTER_MAX := 0.1
## Whatever the two machines' clocks make of each other, what's played is never
## further behind the newest report than PLAY_BEHIND_MAX frames, nor further
## past it than PLAY_CARRY: there (a late one), a moving tank carries on its
## way that far rather than stopping.
const PLAY_BEHIND_MAX := 18.0
const PLAY_CARRY := 2.0

## Host: changes whenever the host, not the client driving this tank, says
## where it is: a correction, or a spell the host drives (materializing, a
## mine's flight, a hold). The client starts again from the host's position,
## and only reports that have taken the change are followed.
var net_override := 0
var _host_drives := false
## Host: the client driving this tank, its lag compensation off, had its keys
## move it here: should it turn it on, it starts again from here.
var _host_moved_it := false
var _apart_time := 0.0
## Host: playing back the client's reports (PLAY_DELAY_START): whose they are
## and which run of them, the client's frame being shown, this machine's
## physics frame it was last shown at (-1: not under way), and what's being
## followed ([frame, position, facing, moving, override], [] none).
var _play_key := PlayerInput.NO_SEAT
var _play_run := 0
var _play_at := 0.0
var _play_seen := -1
var _played: Array = []
## Host: the shot of the client's own being fired just now (PlayerInput's
## shots_due entry), or [].
var _client_shot: Array = []
## Client: the fire button of the shot being fired just now (_predict_fire).
var _firing_button := 0
## Host: the latest moment of the host's world (its clock, ms) that the screen
## of the client driving this tank has been judged for (_judge_reported_hits):
## the enemies' shells it may yet show hitting it wait for that
## (Bullet._end_with).
var judged_view := 0.0
## Host: a shell of the enemies' is noted as maybe on this tank as its client's
## screen will show it (may_be_met_there) this much further out than the way the
## tank can drive meanwhile: a turn's snap to the grid.
const MEET_SPARE := HALF_TILE
## Host: the frame of the client driving this tank (and the run of its reports)
## in which a hit its screen showed started the tank's grace
## (_judge_reported_hits): another hit its screen shows within HIT_GRACE of that,
## by its own frames, is in that grace, whenever the reports come here; one after
## it isn't. And whether this tank's invincibility here is no more than a hit's
## grace (lift_hit_grace).
var _screen_grace_frame := 0
var _screen_grace_run := -1
var _hit_grace_only := false
## Client: a hit this machine's own tank survives, shown here at once
## (NetClientWorld._show_own_hits): its red flash till then (msec), and the
## physics frame its grace began in, as the host judges it (by the frames this
## machine reports, _judge_reported_hits); and those hits whose flash the
## host's word is still to bring (msec each, oldest first), which it then
## doesn't start again (_shown_flash). One owed this long goes unpaid.
var _flash_guessed_until := 0
var _grace_guessed_frame := -100000
var _flashes_owed: Array[int] = []
var _host_flash_was := 0.0
var _host_flash_left_out := false
const FLASH_OWED_MS := 1500
## Client: this machine drives this tank (its own seat), with local slot
## [member net_slot]'s controls. It moves here at once (_predict), ahead of the
## host by the trip there, and the host's copy follows it.
var net_predicted := false
var net_slot := 0
var _override_seen := 0

func _ready() -> void:
	super._ready()
	add_to_group("players")
	net_override = randi() % 256  # no report about an earlier tank can match it

	# Load persisted stats from GameManager
	speed_level = GameManager.get_speed_level(player_id)
	weapon_level = GameManager.get_weapon_level(player_id)
	secondary_weapon_type = GameManager.get_secondary_weapon_type(player_id)
	secondary_weapon_count = GameManager.get_secondary_weapon_count(player_id)

	# Apply HP: max is always MAX_HP, load persisted HP from GameManager
	max_health = MAX_HP
	health = clampi(GameManager.player_hp[player_id], 1, MAX_HP)

	_apply_speed_upgrade()
	_apply_weapon_upgrade()
	_activate_invincibility(SPAWN_INVINCIBILITY)

	# Set collision layers (before addon restore, so addons can override)
	set_collision_layer_value(1, false)
	set_collision_layer_value(3, true)  # player_tanks
	set_collision_mask_value(1, true)   # walls
	set_collision_mask_value(2, true)   # water
	set_collision_mask_value(4, false)  # enemy_tanks (no mutual push; each stops for the other via _opponent_ahead)
	set_collision_mask_value(6, true)   # enemy_bullets
	set_collision_mask_value(7, true)   # powerups

	# Restore persisted addons from GameManager (after collision setup so addons like anti-water can override)
	var saved_addons: Array = GameManager.player_addons[player_id]
	for addon_name in saved_addons:
		apply_addon(addon_name)
	# Apply theme sprite and color
	if sprite:
		var tank_key := "p1" if player_id == 0 else "p2"
		var theme_tex := ThemeManager.get_tank_texture(tank_key)
		if theme_tex:
			sprite.texture = theme_tex
		# Dynamically scale sprite to fit 64x64 (2x2 tile) tank size
		var tex_size := sprite.texture.get_size()
		sprite.scale = Vector2(TANK_SIZE / tex_size.x, TANK_SIZE / tex_size.y)
		sprite.modulate = Color.WHITE

func _physics_process(delta: float) -> void:
	if Net.is_client():
		if is_net_driving():
			_predict()
		return  # the host drives every other tank; this one only shows it
	_judge_reported_hits()
	if is_materializing:
		velocity = Vector2.ZERO
		_take_over()
		return
	if is_flying:
		_update_flying(delta)
		_take_over()
		return
	if is_invincible:
		invincible_timer -= delta
		if invincible_timer <= 0:
			is_invincible = false
			_helmet_invincible = false
			_sync_wreath()
	if GameManager.players_frozen:
		glide_while_held("enemies")  # an enemy took "Hold Enemy"
		_take_over()
		return

	if not PlayerInput.is_remote_seat(player_id):
		_drive(_read_move_direction())
	elif PlayerInput.remote_predicts(player_id):
		_follow_client(delta)
	else:
		_drive_for_client()

	# (Damage flash is handled centrally in BaseTank._process.)

	if PlayerInput.remote_predicts(player_id):
		# Its shots are the ones it fired there itself, each fired here once.
		_fire_client_shots()
		if secondary_weapon_type == "mine" and PlayerInput.is_just_pressed(player_id, 1):
			shoot_secondary()  # (mines aren't fired there: laid here on its press)
		return
	# Held, or a tap between two frames: a client's press and release can come
	# in one bunch, and its counter still says it pressed.
	if PlayerInput.is_held(player_id, 0) or PlayerInput.is_just_pressed(player_id, 0):
		shoot_regular()
	var auto_secondary_held := secondary_weapon_type in AUTO_SECONDARY and PlayerInput.is_held(player_id, 1)
	if auto_secondary_held or PlayerInput.is_just_pressed(player_id, 1):
		shoot_secondary()

## One step of driving with [param input_dir] pushed: the turn, ice, an enemy
## in the way, the walls. The host's own players drive this way, and so does
## a client's own tank on the client (_predict).
func _drive(input_dir: Vector2) -> void:
	var delta := get_physics_process_delta_time()
	is_on_ice = not has_anti_ice and _on_ice_terrain()
	if is_on_ice:
		velocity = _ice_steer(input_dir, move_speed * (MINE_SLOW_FACTOR if is_mine_slowed else 1.0), move_speed, delta)
		is_moving = velocity != Vector2.ZERO
	elif input_dir != Vector2.ZERO:
		try_move(input_dir)
		ice_speed = velocity.length()
	else:
		stop_moving()
	# Stop movement when an enemy is immediately ahead, but don't let physics contact push the player.
	if velocity != Vector2.ZERO and _is_enemy_ahead():
		velocity = Vector2.ZERO
		ice_speed = 0.0
	var from := global_position
	var meant := velocity.length() * delta  # (move_and_slide takes what a wall stops off velocity)
	move_and_slide()
	clamp_to_playfield()
	if is_on_ice and global_position.distance_to(from) < meant * 0.5:
		ice_speed = 0.0  # stopped dead against a wall, as the original's

## Host: this tank's driver is on a client, which drives its own copy at once
## and reports where it is (lag compensation). This copy goes after it, at up
## to FOLLOW_SPEED times its speed, stopped by the walls, water and enemies
## this machine has. Held up for too long, it tells the client to start again
## from here (net_override); until the client has, this copy waits.
func _follow_client(delta: float) -> void:
	_host_drives = false
	if _host_moved_it:
		_host_moved_it = false
		_correct_client()  # its keys moved it here meanwhile (_drive_for_client)
	var report := _play_reports()
	if report.is_empty() or int(report[4]) != net_override:
		stop_moving()
		_apart_time = 0.0
		return
	var target: Vector2 = report[1]
	var reported_moving: bool = report[3]
	var speed := move_speed * (MINE_SLOW_FACTOR if is_mine_slowed else 1.0)
	var way: Vector2 = target - global_position
	# Across the way it faces now first: the rest of the way it went before
	# it turned. Within half a tile, that's the turn's own snap to the grid
	# (try_move), taken at once as the client did.
	var facing: Vector2 = FACINGS[int(report[2])]
	var across := way * Vector2(absf(facing.y), absf(facing.x))
	if across.length() > HALF_TILE:
		way = across
	else:
		position += across
		way -= across
	var step := way.limit_length(speed * FOLLOW_SPEED * delta)
	var moved := 0.0
	if step != Vector2.ZERO:
		facing = step.normalized()
		if not _opponent_ahead("enemies", facing, maxf(step.length(), 2.0)):
			var before := global_position
			move_and_collide(step)
			clamp_to_playfield()
			moved = global_position.distance_to(before)
	if facing != current_direction:
		current_direction = facing
		_update_sprite_direction()
	is_moving = reported_moving or moved > 0.0
	velocity = current_direction * speed if is_moving else Vector2.ZERO
	if global_position.distance_to(target) > APART_DISTANCE and moved < step.length() * 0.5:
		_apart_time += delta
		if _apart_time >= APART_TIME:
			_correct_client()
	else:
		_apart_time = 0.0

## Host: where the client's tank is to be shown now, from its reports: played
## back steadily a frame of its own a frame here, its delay (PLAY_DELAY_START)
## behind the quickest they have come lately, so however unevenly the network
## brings them, the copy goes on as evenly as the client's tank did. Between
## two reports, the way between them; past the newest, a little further on its
## way. [] while there's none to follow.
func _play_reports() -> Array:
	var key: int = PlayerInput.seats[player_id]
	if key != _play_key:
		_play_key = key
		_play_seen = -1
		_played = []
	var pad := PlayerInput.remote_pad(player_id)
	if pad == null or pad.report_frame < 0:
		_play_seen = -1
		_played = []
		return _played
	var delay := PLAY_DELAY_START
	if pad.report_late.size() >= 30:
		var sorted := pad.report_late.duplicate()
		sorted.sort()
		delay = clampf(sorted[int(sorted.size() * 0.98)] + PLAY_SPARE, PLAY_DELAY_MIN, PLAY_DELAY_MAX)
	var now := Engine.get_physics_frames()
	var place := now + pad.report_clock - delay  # where the playback belongs
	if _play_seen != now - 1 or pad.report_run != _play_run:
		_play_run = pad.report_run
		_play_at = place  # a start, a fresh run, or on again after the host drove it a spell
	else:
		_play_at += 1.0
		var off := place - _play_at
		if off < 0.0:
			_play_at -= minf(-off, PLAY_SLOWER)
		else:
			_play_at += minf(off, clampf(off * PLAY_FASTER_PER_FRAME, PLAY_FASTER_MIN, PLAY_FASTER_MAX))
	_play_seen = now
	# The two machines' clocks aside: no further from the newest than this.
	var newest := float(pad.report_frame)
	_play_at = clampf(_play_at, newest - PLAY_BEHIND_MAX, newest + PLAY_CARRY)
	var play := _play_at
	var reports := pad.reports
	while reports.size() >= 2 and float(reports[1][0]) <= play:
		reports.pop_front()
	if reports.is_empty() or play < float(reports[0][0]):
		return _played  # nothing due yet: as it was
	var a: Array = reports[0]
	if reports.size() >= 2:
		var b: Array = reports[1]
		var t := (play - float(a[0])) / float(int(b[0]) - int(a[0]))
		if a[2] != b[2] or a[4] != b[4]:
			_played = a if t < 0.5 else b  # a turn's snap, or a correction taken: no halfway
		else:
			_played = [play, (a[1] as Vector2).lerp(b[1], t), a[2], a[3], a[4]]
		return _played
	var on_its_way: Vector2 = a[1]
	if a[3]:
		on_its_way += FACINGS[int(a[2])] * move_speed * (MINE_SLOW_FACTOR if is_mine_slowed else 1.0) \
				* (play - float(a[0])) * get_physics_process_delta_time()
	_played = [play, on_its_way, a[2], a[3], a[4]]
	return _played

## Host: the shots a client running this tank ahead (lag compensation) fired
## there itself (PlayerInput's shots_due), each fired here once, in order, as it
## fired it: the same weapon and row, from where it had the tank, numbered so
## its ghost there gives way to this very shell (_shot_origin, _shot_row,
## _shot_number). It kept to the cooldown on its own clock, so the host's
## doesn't hold a shot back however the network bunched them; one whose kind
## still has too many shells flying here waits (CLIENT_SHOT_WAIT_MS at most).
func _fire_client_shots() -> void:
	var pad := PlayerInput.remote_pad(player_id)
	if pad == null:
		return
	var now := Time.get_ticks_msec()
	while not pad.shots_due.is_empty():
		var shot: Array = pad.shots_due[0]
		var button := int(shot[0])
		if now - int(shot[4]) > CLIENT_SHOT_WAIT_MS or (button == 1 and secondary_weapon_type == "mine"):
			pad.shots_due.pop_front()
			continue
		if not _client_shot_ready(button):
			return
		pad.shots_due.pop_front()
		var fired := active_bullets
		var could := can_shoot
		_client_shot = shot
		can_shoot = true
		if button == 0:
			shoot_regular()
		else:
			shoot_secondary()
		_client_shot = []
		if active_bullets == fired:
			can_shoot = could  # it couldn't fire here at all (no ammo, say)

## Host: whether a client's own shot with fire button [param button] can leave
## here now: its kind's shells in flight here below their limit.
func _client_shot_ready(button: int) -> bool:
	if button == 0:
		return true
	var flying := {"fire": active_fire_bullets, "explosion": active_explosion_bullets, "ap": active_ap_bullets}
	if not flying.has(secondary_weapon_type):
		return true
	var limit: int = CookieData.get_weapon_fire_config(secondary_weapon_type, weapon_level).get(
			"max_in_flight", {"fire": 3, "explosion": 2, "ap": 2}[secondary_weapon_type])
	return int(flying[secondary_weapon_type]) < limit

## Host: a client's own shot leaves from where that client had this tank as it
## fired, facing its way: the report that came with the shot (else the newest).
## Not from this copy, played back behind it, perhaps not yet turned the way it
## fired: the client's shot would jump back to the host's shell, or never be
## taken over. A report that hasn't taken the latest correction, or one further
## from this copy than the playback ever lags (a client held up here), fires
## from here.
func _shot_origin() -> Vector2:
	var report := _shooter_report()
	return report[1] if not report.is_empty() else global_position

func _shot_facing() -> Vector2:
	var report := _shooter_report()
	return FACINGS[int(report[2])] if not report.is_empty() else current_direction

func _shot_row(row_offset: float) -> float:
	return row_offset if _client_shot.is_empty() else SHOT_ROWS[int(_client_shot[1])]

func _shot_number() -> int:
	return -1 if _client_shot.is_empty() else int(_client_shot[3])

## Host: a client's own shot is judged by what that client's screen showed as
## it flew there: its controller, and the run of reports and the frame it was
## fired at (the report that came with it, else the newest).
func _shot_view() -> Array:
	if _client_shot.is_empty():
		return []
	var report: Array = _client_shot[2]
	var frame := int(report[0]) if not report.is_empty() else PlayerInput.remote_report_frame(player_id)
	return [PlayerInput.seats[player_id], int(_client_shot[5]), frame]

func _shooter_report() -> Array:
	if Net.is_client() or not PlayerInput.remote_predicts(player_id):
		return []
	var report: Array = []
	if not _client_shot.is_empty():
		report = _client_shot[2]
	else:
		var pad := PlayerInput.remote_pad(player_id)
		if pad != null and pad.report_frame >= 0 and not pad.reports.is_empty():
			report = pad.reports[-1]
	if report.is_empty():
		return []
	if int(report[4]) != net_override or (report[1] as Vector2).distance_to(global_position) > _report_reach():
		return []
	return report

## Host: how far from this copy a report of the client driving it can be: the
## playback is never further behind it, nor past it, than this.
func _report_reach() -> float:
	return move_speed * (PLAY_BEHIND_MAX + PLAY_CARRY) * get_physics_process_delta_time() + HALF_TILE

## Host: the screen of the client driving this tank says which of the enemies'
## shells hit it (_judge_reported_hits), not this copy (Bullet._on_body_entered
## lets it be): that client runs it itself (its lag compensation on), reports
## where, with the moment of this world its screen showed, not further back
## than what's kept of it (NetHostWorld.SEEN_KEEP_MS), and the host isn't
## driving it just now.
func hits_judged_there() -> bool:
	if Net.is_client() or NetHostWorld.active == null or not PlayerInput.remote_predicts(player_id):
		return false
	if _host_drives or is_materializing or is_flying or is_queued_for_deletion():
		return false
	var pad := PlayerInput.remote_pad(player_id)
	if pad == null or pad.report_frame < 0 or pad.views.is_empty():
		return false
	return Time.get_ticks_msec() - float(pad.views[-1][2]) < NetHostWorld.SEEN_KEEP_MS - 100.0

## Host: the client driving this tank, its frames as they come: the enemies'
## shells its screen had on its tank in each (where it said its tank was, at the
## moment of this world it said its screen showed: NetHostWorld.seen_at) hit
## it, as they would here (Bullet.hit_seen_tank), each once, its facing there
## saying whether its moon shield took it. Its screen shows them ending there at
## once (NetClientWorld._show_own_hits) and gone after, for its own shots too
## (NetHostWorld.mark_gone). So a shell it dodged on its screen misses it, and
## one it drove into hits it, however far behind its tank this copy is: the
## popular shooters favor the shooter; this favors the player, the enemies
## being the machine's.
func _judge_reported_hits() -> void:
	var pad := PlayerInput.remote_pad(player_id)
	if pad == null or pad.judge.is_empty():
		return
	var world := NetHostWorld.active
	var judging := hits_judged_there()
	var peer := PlayerInput.controller_peer(PlayerInput.seats[player_id])
	while not pad.judge.is_empty():
		var said: Array = pad.judge.pop_front()
		var view := float(said[3])
		judged_view = maxf(judged_view, view)
		if not judging or health <= 0 or is_queued_for_deletion():
			continue
		var at: Vector2 = said[1]
		if at.distance_to(global_position) > _report_reach():
			continue  # nowhere this copy could be following
		var met: Array = []
		for seen: Array in world.seen_at(view, peer):
			var kept: Array = seen[1]
			if int(kept[0]) == NetHostWorld.SEEN_SHELL and not bool(kept[4]) \
					and Bullet.touches_tank(kept[1], kept[2], kept[3], at):
				met.append(seen)
		var facing: Vector2 = FACINGS[int(said[2])]
		var frame := int(said[0])
		for seen: Array in met:
			world.mark_gone(peer, int(seen[0]), view)
			var graced := _screen_grace_run == pad.report_run \
					and frame - _screen_grace_frame < roundi(HIT_GRACE * Engine.physics_ticks_per_second)
			if not graced:
				lift_hit_grace()  # (over on its screen, if it's still running here)
				if _finished_by(seen[1], facing):
					global_position = at  # it goes up where its screen had it
			var was := health
			Bullet.hit_seen_tank(seen, self, facing, graced)
			if health <= 0 or is_queued_for_deletion():
				break
			if health < was:
				_screen_grace_frame = frame  # its grace, as its screen has it
				_screen_grace_run = pad.report_run

## Host: ends this tank's invincibility here if it's no more than the grace
## after a hit: the screen of the client driving it, which judges what hits it,
## has that grace over by now (_judge_reported_hits).
func lift_hit_grace() -> void:
	if is_invincible and _hit_grace_only:
		is_invincible = false
		invincible_timer = 0.0
		_hit_grace_only = false
		_sync_wreath()

## Host: whether the enemies' shell [param kept] (as NetHostWorld.seen_at keeps
## it) finishes this tank, facing [param facing]: not on its moon shield's
## front, nor while it blinks, and with as much damage as it has health (a
## direct hit's for an explosion shell, its pool for an AP shell).
func _finished_by(kept: Array, facing: Vector2) -> bool:
	if is_invincible or (has_moon_shield and (kept[2] as Vector2).dot(facing) < 0.0):
		return false
	var damage := int(kept[5]) if bool(kept[8]) or str(kept[7]) == "explosion" else 1
	return damage >= health

## Host: whether a shell at [param at] going [param way] on [param lanes] may be
## on this tank as the screen of the client driving it will show the moment
## [param now] of this world (the host's clock, ms): within the way it can drive
## from where it said it was in its newest frame, in the time between the
## moment that frame showed and this one (and MEET_SPARE); or on this copy.
func may_be_met_there(at: Vector2, way: Vector2, lanes: Array, now: float) -> bool:
	var pad := PlayerInput.remote_pad(player_id)
	if pad == null or pad.reports.is_empty() or pad.views.is_empty():
		return false
	var since := maxf(now - float(pad.views[-1][2]), 0.0) / 1000.0 * Engine.time_scale
	var reach := Bullet.box_half(way, lanes) + Vector2.ONE * (HITBOX_SIZE * 0.5 + move_speed * since + MEET_SPARE)
	for center: Vector2 in [pad.reports[-1][1], global_position]:
		var offset := center - at
		if absf(offset.x) < reach.x and absf(offset.y) < reach.y:
			return true
	return false

## Host: whether a shell of the enemies' going [param way] that ends at walls
## [param walls] (cells of [param level_manager]'s) at [param end_at] can't
## have met this tank on its client's screen on its way: the tank, where that
## client last said it was and as this copy, is on the far side of them, in
## their way, so it couldn't have come round in front of them.
func walled_off(end_at: Vector2, way: Vector2, walls: Array[Vector2i], level_manager: LevelManager) -> bool:
	var pad := PlayerInput.remote_pad(player_id)
	if pad == null or pad.reports.is_empty() or level_manager == null:
		return false
	var across := Vector2(absf(way.y), absf(way.x))
	for center: Vector2 in [pad.reports[-1][1], global_position]:
		if (center - end_at).dot(way) <= HITBOX_SIZE * 0.5:
			return false  # not past where it ends
		var in_way := false
		for cell: Vector2i in walls:
			in_way = in_way or absf((level_manager.tile_to_world(cell) - center).dot(across)) \
					< (HITBOX_SIZE + LevelManager.TILE_SIZE) * 0.5
		if not in_way:
			return false
	return true

## Host: the client driving this tank doesn't run it ahead (its lag
## compensation is off): its keys drive it here as they come, as they did
## before lag compensation.
func _drive_for_client() -> void:
	var before := global_position
	_drive(_read_move_direction())
	if global_position != before:
		_host_moved_it = true

## Host: the host drives this tank itself just now (a spell): the client
## driving it starts again from wherever it ends up.
func _take_over() -> void:
	var pad := PlayerInput.remote_pad(player_id) if not Net.is_client() else null
	if pad != null:
		pad.shots_due.clear()  # fired there before it knew: not fired here
	if not _host_drives:
		_host_drives = true
		_correct_client()

## Host: the client driving this tank is to start again from where it is here.
func _correct_client() -> void:
	net_override = (net_override + 1) % 256
	_apart_time = 0.0

## Client: this machine drives this tank here (see net_predicted), unless the
## host moves it itself just now: materializing, a mine's flight, a hold.
func is_net_driving() -> bool:
	return net_predicted and not is_materializing and not is_flying and not GameManager.players_frozen

func _net_drives_itself() -> bool:
	return is_net_driving()

## Client: this machine takes over this tank, with local slot [param slot]'s
## controls ([param on]), or stops. Driving it, it bumps into the walls, water
## and the base here as it would on the host.
func set_net_predicted(on: bool, slot: int) -> void:
	net_slot = slot
	if on == net_predicted:
		return
	net_predicted = on
	collision_layer = 0
	collision_mask = 0
	if on:
		set_collision_layer_value(3, true)  # player_tanks
		for layer: int in [1, 2, 8]:        # walls, water, the base
			set_collision_mask_value(layer, true)
		if has_boat:
			set_collision_mask_value(2, false)
	else:
		velocity = Vector2.ZERO

## Client: one step of this machine's own tank, as the host would drive it, at
## once: the keys don't wait for the trip to the host and back. Where it is goes
## to the host with the next input message, and the host's copy follows.
func _predict() -> void:
	speed_level = int(GameManager.player_speed_levels[player_id])
	_apply_speed_upgrade()
	var blocked := Net.input_blocked or Net.map_prompt_open
	_drive(Vector2.ZERO if blocked else PlayerInput.local_direction(net_slot))
	Net.report_tank(net_slot, global_position, maxi(FACINGS.find(current_direction), 0),
			velocity != Vector2.ZERO, _override_seen)
	var world := NetClientWorld.of(get_tree())
	if world:
		world.predict_pickups(self)  # the items it drives onto, taken here at once
	if not blocked:
		_predict_fire()

## Client: this tank's shots, fired here at once as the host will fire them when
## the keys reach it: each is seen and heard now, a ghost of the host's shell
## to come (BaseTank._spawn_bullet, NetClientWorld.add_ghost). Mines are left
## to the host.
func _predict_fire() -> void:
	_take_host_weapons()
	var prefix := PlayerInput.action_prefix(net_slot)
	var fire := prefix + PlayerInput.BUTTONS[0]
	if Input.is_action_pressed(fire) or Input.is_action_just_pressed(fire):
		_firing_button = 0
		shoot_regular()
	if secondary_weapon_type == "mine":
		return
	var held := Input.is_action_pressed(prefix + PlayerInput.BUTTONS[1])
	if (held and secondary_weapon_type in AUTO_SECONDARY) or Input.is_action_just_pressed(prefix + PlayerInput.BUTTONS[1]):
		_firing_button = 1
		shoot_secondary()

## Client: [param shell], a shot of this tank's, flies here at once as a ghost:
## the host is told which button fired it and from which row, and fires that
## very shot (_fire_client_shots); its shell takes over by the number given.
func _net_ghost_fired(shell: Bullet) -> void:
	var across := (shell.global_position - global_position).dot(Vector2(-shell.direction.y, shell.direction.x))
	var row := 0 if across < -8.0 else (2 if across > 8.0 else 1)
	shell.net_shot = Net.note_shot(net_slot, _firing_button, row)

## Client: this tank's weapons as the host has them (GameManager's numbers come
## from the host), and its shells in flight as shown here, so its shots go as
## the host's will.
func _take_host_weapons() -> void:
	var level := int(GameManager.player_weapon_levels[player_id])
	if level != weapon_level:
		weapon_level = level
		_apply_weapon_upgrade()
	var kind := str(GameManager.player_secondary_weapon_types[player_id])
	if kind != secondary_weapon_type:
		secondary_weapon_type = kind
		_rapid_special_fire_step = 0
		_rapid_special_ammo_progress = 0
	secondary_weapon_count = int(GameManager.player_secondary_weapon_counts[player_id])
	var world := NetClientWorld.of(get_tree())
	if world:
		active_bullets = world.own_shells_in_flight(player_id)
		active_fire_bullets = world.own_shells_in_flight(player_id, "fire")
		active_explosion_bullets = world.own_shells_in_flight(player_id, "explosion")
		active_ap_bullets = world.own_shells_in_flight(player_id, "ap")

## A shot's sound. The host's goes to its clients marked as this tank's, so the
## client driving it, which heard it as it fired (_predict_fire), doesn't again.
func _shot_sound(key: StringName) -> void:
	if Net.is_client():
		SoundManager.play_predicted(key, player_id)
	else:
		SoundManager.play(key, player_id)

# --- Speed & weapon upgrade application ---

func _apply_speed_upgrade() -> void:
	move_speed = SPEED_MAP.get(speed_level, 128.0)

func _apply_weapon_upgrade() -> void:
	weapon_level = clampi(weapon_level, 0, 3)
	match weapon_level:
		0:
			bullet_speed = 256.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
		1:
			bullet_speed = 384.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
		2:
			bullet_speed = 384.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
		3:
			bullet_speed = 384.0
			max_bullets = PLAYER_MAX_ACTIVE_BULLETS
	_regular_fire_step = 0
	if shoot_cooldown:
		shoot_cooldown.wait_time = REGULAR_WEAPON_COOLDOWN_MAP.get(weapon_level, 0.4)

func _get_regular_fire_rows() -> Array[float]:
	match weapon_level:
		2:
			return [FIRE_ROW_LEFT, FIRE_ROW_RIGHT]
		3:
			return [FIRE_ROW_LEFT, FIRE_ROW_MID, FIRE_ROW_RIGHT, FIRE_ROW_MID]
		_:
			return [FIRE_ROW_MID]

func shoot_regular() -> void:
	if not can_shoot:
		return

	var fire_rows := _get_regular_fire_rows()
	var row_offset: float = fire_rows[_regular_fire_step % fire_rows.size()]
	_regular_fire_step = (_regular_fire_step + 1) % fire_rows.size()

	_set_shoot_cooldown_wait_time(REGULAR_WEAPON_COOLDOWN_MAP.get(weapon_level, 0.4))
	_begin_shot()
	_shot_sound(&"fire_primary")
	_spawn_single_row_bullet(row_offset)

# --- Cookie effect methods ---

const COOKIE_PICKUP_INVINCIBILITY: float = 1.0

func activate_pickup_invincibility() -> void:
	_activate_invincibility(COOKIE_PICKUP_INVINCIBILITY)

func apply_cookie_speed_up() -> void:
	speed_level = mini(speed_level + 1, 3)
	GameManager.set_speed_level(player_id, speed_level)
	_apply_speed_upgrade()

func apply_cookie_hp_up() -> void:
	health = mini(health + 1, MAX_HP)

func apply_cookie_weapons_up() -> void:
	weapon_level = mini(weapon_level + 1, 3)
	GameManager.set_weapon_level(player_id, weapon_level)
	_apply_weapon_upgrade()

func apply_cookie_star_up() -> void:
	apply_cookie_speed_up()
	apply_cookie_hp_up()
	apply_cookie_weapons_up()

func apply_cookie_max_up() -> void:
	speed_level = 3
	weapon_level = 3
	health = MAX_HP
	GameManager.set_speed_level(player_id, speed_level)
	GameManager.set_weapon_level(player_id, weapon_level)
	_apply_speed_upgrade()
	_apply_weapon_upgrade()

func apply_addon(addon_name: String) -> void:
	# If it's a utility addon (anti-water/anti-ice/memory-save), remove the old one first
	if addon_name in UTILITY_ADDONS:
		_remove_utility_addon()
		_current_utility_addon = addon_name
	# Apply gameplay effect
	match addon_name:
		"anti-water":
			has_boat = true
			set_collision_mask_value(2, false)
		"anti-ice":
			has_anti_ice = true
		"moon-shield":
			has_moon_shield = true
		"memory-save":
			has_memory_save = true
	# Add visual overlay sprite
	_add_addon_sprite(addon_name)

func _remove_utility_addon() -> void:
	if _current_utility_addon.is_empty():
		return
	# Undo gameplay effect of old addon
	match _current_utility_addon:
		"anti-water":
			has_boat = false
			set_collision_mask_value(2, true)
			# Losing the boat while afloat: the tank sinks. Deferred so it runs
			# after the current add/remove-addon logic finishes.
			_sink_if_stranded_on_water.call_deferred()
		"anti-ice":
			has_anti_ice = false
		"memory-save":
			has_memory_save = false
	# Remove old sprite
	if _addon_sprites.has(_current_utility_addon):
		var old_spr: Sprite2D = _addon_sprites[_current_utility_addon]
		if old_spr and is_instance_valid(old_spr):
			old_spr.queue_free()
		_addon_sprites.erase(_current_utility_addon)
	_current_utility_addon = ""

func _add_addon_sprite(addon_name: String) -> void:
	# Prefer a 4-frame animation (anti-water / memory-save) over the single sprite.
	var frames: Array = ThemeManager.get_addon_frames(addon_name)
	var tex: Texture2D = frames[0] if not frames.is_empty() else ThemeManager.get_addon_texture(addon_name)
	if tex:
		var cfg: Dictionary = ADDON_CONFIG.get(addon_name, { "scale": 1.0 })
		var addon_sprite := Sprite2D.new()
		tag_addon_sprite(addon_sprite, addon_name)
		addon_sprite.texture = tex
		addon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp, no magenta-key blur
		var tex_size := tex.get_size()
		var addon_size: float = TANK_SIZE * cfg["scale"]
		addon_sprite.scale = Vector2(addon_size / tex_size.x, addon_size / tex_size.y)
		add_child(addon_sprite)
		if not frames.is_empty():
			register_animated_addon(addon_sprite, frames)
		# Draw order via sibling order (all at z 0 so nothing sinks below the world),
		# back -> front: other addons -> moon shield -> tank body (on top, fully visible).
		var sprite_idx := sprite.get_index() if sprite else get_child_count() - 1
		if addon_name == "moon-shield":
			move_child(addon_sprite, sprite_idx)  # just behind the tank body
			_shield_sprite = addon_sprite
		else:
			move_child(addon_sprite, 0)  # behind everything
		_addon_sprites[addon_name] = addon_sprite
		_layout_addons()

func is_bullet_blocked(bullet_direction: Vector2) -> bool:
	if not has_moon_shield:
		return false
	return bullet_direction.dot(current_direction) < 0

func get_gun_level() -> int:
	return weapon_level

func get_player_index() -> int:
	return player_id

## The moon shield first: it is what a hit would cost first, too.
func get_addon_names() -> Array:
	var names: Array = []
	if has_moon_shield:
		names.append("moon-shield")
	if not _current_utility_addon.is_empty():
		names.append(_current_utility_addon)
	return names

func lose_addon(addon_name: String) -> void:
	if addon_name == "moon-shield":
		_remove_moon_shield()
	elif addon_name == _current_utility_addon:
		_remove_utility_addon()

func is_invulnerable() -> bool:
	return is_invincible

# --- Secondary weapon system ---

func set_secondary_weapon(weapon_type: String) -> void:
	var weapon_data: Dictionary = CookieData.WEAPON_DATA.get(weapon_type, {})
	if weapon_data.is_empty():
		return
	if weapon_type != secondary_weapon_type:
		_rapid_special_fire_step = 0
		_rapid_special_ammo_progress = 0
	if weapon_type == secondary_weapon_type:
		# Same weapon: refill by reload_count (capped at max)
		secondary_weapon_count = mini(
			secondary_weapon_count + weapon_data["reload_count"],
			weapon_data["max_count"]
		)
	else:
		# Different weapon: switch and set to reload_count
		secondary_weapon_type = weapon_type
		secondary_weapon_count = weapon_data["reload_count"]
	# Persist to GameManager
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func apply_cookie_bullets_max() -> void:
	var weapon_data: Dictionary = CookieData.WEAPON_DATA.get(secondary_weapon_type, {})
	if weapon_data.is_empty():
		return
	secondary_weapon_count = weapon_data["max_count"]
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func apply_cookie_bullet_refill() -> void:
	var weapon_data: Dictionary = CookieData.WEAPON_DATA.get(secondary_weapon_type, {})
	if weapon_data.is_empty():
		return
	secondary_weapon_count = mini(
		secondary_weapon_count + weapon_data["reload_count"],
		weapon_data["max_count"]
	)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func shoot_secondary() -> void:
	if secondary_weapon_count <= 0 or not can_shoot or active_bullets >= max_bullets:
		return
	if secondary_weapon_type == "rapid":
		_shoot_secondary_rapid()
		return
	if secondary_weapon_type == "fire":
		_shoot_secondary_fire()
		return
	if secondary_weapon_type == "explosion":
		_shoot_secondary_explosion()
		return
	if secondary_weapon_type == "mine":
		_shoot_secondary_mine()
		return
	if secondary_weapon_type == "ap":
		_shoot_secondary_ap()
		return
	secondary_weapon_count -= 1
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)
	super.shoot()

func _shoot_secondary_ap() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("ap", weapon_level)
	if config.is_empty():
		return
	_shot_sound(&"fire_ap")
	if active_ap_bullets >= int(config.get("max_in_flight", 2)):
		return

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.6))
	_begin_shot()
	_spawn_ap_bullet(config)

	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

## AP shell stripped this player's moon shield: remove it and grant a brief grace.
func break_moon_shield_grace() -> void:
	if has_moon_shield:
		_remove_moon_shield()
	_activate_invincibility(AP_SHIELD_GRACE)

const AP_SHIELD_GRACE: float = 1.125

func _shoot_secondary_mine() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("mine", weapon_level)
	if config.is_empty():
		return
	# Lay the mine first; if there's no free spot, spend neither ammo nor cooldown.
	if not _place_mine(weapon_level):
		return
	SoundManager.play(&"lay_mine")
	can_shoot = false
	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.6))
	if shoot_cooldown:
		shoot_cooldown.start()
	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func _shoot_secondary_rapid() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("rapid", weapon_level)
	if config.is_empty():
		return
	_shot_sound(&"fire_rapid")

	var fire_rows: Array = config.get("rows", [FIRE_ROW_MID])
	var ammo_per_count: int = config.get("ammo_per_count", 1)
	var speed_multiplier: float = config.get("speed_multiplier", 1.0)
	var row_offset: float = fire_rows[_rapid_special_fire_step % fire_rows.size()]
	_rapid_special_fire_step = (_rapid_special_fire_step + 1) % fire_rows.size()

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.4))
	_begin_shot()
	_spawn_single_row_bullet(row_offset, bullet_speed * speed_multiplier, "rapid")

	_rapid_special_ammo_progress += 1
	if _rapid_special_ammo_progress >= ammo_per_count:
		_rapid_special_ammo_progress = 0
		secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
		GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func _shoot_secondary_fire() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("fire", weapon_level)
	if config.is_empty():
		return
	_shot_sound(&"fire_fire")
	if active_fire_bullets >= int(config.get("max_in_flight", 3)):
		return

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.27))
	_begin_shot()
	_spawn_fire_bullet(config)

	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

func _shoot_secondary_explosion() -> void:
	var config: Dictionary = CookieData.get_weapon_fire_config("explosion", weapon_level)
	if config.is_empty():
		return
	_shot_sound(&"fire_explosion")
	if active_explosion_bullets >= int(config.get("max_in_flight", 2)):
		return

	_set_shoot_cooldown_wait_time(config.get("cooldown", 0.45))
	_begin_shot()
	_spawn_explosion_bullet(config)

	secondary_weapon_count = maxi(secondary_weapon_count - 1, 0)
	GameManager.set_secondary_weapon(player_id, secondary_weapon_type, secondary_weapon_count)

## If this tank is sitting on water without a boat, it sinks. Called when the
## anti-water addon is lost (e.g. shot off) while afloat.
func _sink_if_stranded_on_water() -> void:
	if has_boat or is_flying or not is_instance_valid(self) or Net.is_client():
		return
	var game = get_tree().get_first_node_in_group("game")
	if not game or not game.has_method("get_level_manager"):
		return
	var lm = game.get_level_manager()
	if lm and lm.is_water_at_world(global_position):
		destroy()  # sank — no boat on water

func _activate_invincibility(duration: float) -> void:
	_hit_grace_only = false
	is_invincible = true
	invincible_timer = maxf(invincible_timer, duration)
	_sync_wreath()

## The invincible helmet cookie: the one invincibility that shows the wreath.
func activate_helmet(duration: float) -> void:
	_helmet_invincible = true
	_activate_invincibility(duration)

func _process(delta: float) -> void:
	super(delta)
	_sync_wreath()
	_blink_while_invincible()

func _sync_wreath() -> void:
	var wreath := is_invincible and _helmet_invincible and invincible_timer > WREATH_MIN_LEFT
	var hold := _hold_stage()
	if wreath != _wreath_shown or hold != _hold_shown:
		_wreath_shown = wreath
		_hold_shown = hold
		match hold:
			2:
				show_state_overlay(BaseTank.get_freeze_frames())
			1:
				show_state_overlay(BaseTank.get_thaw_frames())
			_:
				_update_shield_visual(wreath)

func _hold_stage() -> int:
	if not GameManager.players_frozen:
		return 0
	var left := GameManager.players_freeze_timer
	if left > HOLD_RING_LEFT:
		return 2
	return 1 if left > HOLD_WEB_LEFT else 0

## Any other invincibility blinks the tank: drawn one frame, gone the next.
func _blink_while_invincible() -> void:
	if is_materializing:
		return  # still hidden behind its spawn burst
	if is_invincible and not _wreath_shown:
		visible = not visible
	elif not visible:
		visible = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and not is_materializing:
		visible = true  # never sit out a pause on a blank blink frame

func _update_shield_visual(active: bool) -> void:
	# The old procedural arc is replaced by the animated shield wreath (Tank_T row 1).
	var old = get_node_or_null("ShieldEffect")
	if old:
		old.visible = false
	if active:
		show_state_overlay(BaseTank.get_shield_frames())
	else:
		hide_state_overlay()

func _is_enemy_ahead() -> bool:
	## Check if an enemy tank is blocking movement in the current direction.
	var lookahead := maxf(move_speed / float(Engine.physics_ticks_per_second), 2.0)
	return _opponent_ahead("enemies", current_direction, lookahead)

# --- Hit punishment system ---

func _remove_moon_shield() -> void:
	has_moon_shield = false
	if _shield_sprite and is_instance_valid(_shield_sprite):
		_shield_sprite.queue_free()
		_shield_sprite = null
	if _addon_sprites.has("moon-shield"):
		_addon_sprites.erase("moon-shield")

func _drop_player_addon_cookie(addon_name: String) -> void:
	var cookie_type: int = CookieData.ADDON_TO_COOKIE.get(addon_name, -1)
	if cookie_type == -1:
		return
	# Remove the addon from the tank
	if addon_name == "moon-shield":
		_remove_moon_shield()
	elif addon_name in UTILITY_ADDONS:
		_remove_utility_addon()
	# Spawn the addon cookie on the playfield
	_spawn_cookie_at_position(cookie_type)

func _spawn_cookie_at_position(cookie_type: int) -> void:
	var cookie_scene := preload("res://scenes/powerups/powerup.tscn")
	var cookie: Node2D = cookie_scene.instantiate()
	# Random position on the playfield (40x30 grid, offset 160,16)
	# Inset by 32px (half cookie size) so the 64px cookie stays fully inside
	var spawn_pos := Vector2(
		randf_range(160 + 32, 160 + 40 * 32 - 32),
		randf_range(16 + 32, 16 + 30 * 32 - 32)
	).snapped(Vector2(32, 32))
	# Check if any player is at the spawn position (overlapping)
	var delay: float = 0.0
	var players := get_tree().get_nodes_in_group("players")
	for player in players:
		if player is PlayerTank and is_instance_valid(player):
			if spawn_pos.distance_to(player.global_position) < 48.0:
				delay = 1.0
				break
	cookie.setup(cookie_type, delay, global_position)
	cookie.global_position = spawn_pos
	var container = get_tree().get_first_node_in_group("powerups_container")
	if container:
		container.add_child(cookie)
	else:
		get_tree().current_scene.add_child(cookie)

func _apply_hit_punishment() -> void:
	# Priority 1: drop moon-shield if have it
	if has_moon_shield:
		_drop_player_addon_cookie("moon-shield")
		return
	# Priority 2: drop utility addon (anti-water/anti-ice) if have one
	if _current_utility_addon != "" and _current_utility_addon != "memory-save":
		_drop_player_addon_cookie(_current_utility_addon)
		return
	# Priority 3: alternate -1 speed / -1 weapon
	_hits_taken += 1
	if (_hits_taken % 2) == 1:
		# Odd (1, 3, 5, ...): -1 speed
		if speed_level > 0:
			speed_level -= 1
			GameManager.set_speed_level(player_id, speed_level)
			_apply_speed_upgrade()
	else:
		# Even (2, 4, 6, ...): -1 weapon
		if weapon_level > 0:
			weapon_level -= 1
			GameManager.set_weapon_level(player_id, weapon_level)
			_apply_weapon_upgrade()

## The way the player is pushing (PlayerInput.move_direction): this tank's
## controls offline, whoever took its seat online.
func _read_move_direction() -> Vector2:
	return PlayerInput.move_direction(player_id)

func _rumble(pattern: Array[float]) -> void:
	rumble_player(player_id, pattern)

# --- Online (see BaseTank's net_state) ---

## Past the base's flags: invincible (it blinks), showing the helmet's wreath,
## slowed by a mine (a client driving it drives slow too), and invincible only
## for the grace after a hit (which the client driving it judges by its own
## frames, as the host does: NetClientWorld._guess_hit).
const NET_INVINCIBLE := NET_OWN_FLAGS
const NET_WREATH := NET_OWN_FLAGS << 1
const NET_SLOWED := NET_OWN_FLAGS << 2
const NET_HIT_GRACE := NET_OWN_FLAGS << 3
## Client: the host's invincibility for this tank is only a hit's grace.
var net_hit_grace_only := false
## Past the base's state: the host's net_override.
const NET_OVERRIDE_AT := 9

func net_type() -> int:
	return NetWorld.T_PLAYER

func net_spawn_args() -> Array:
	return [player_id]

## A client's tank for player [param args][0], set before it enters the tree.
func net_setup(args: Array) -> void:
	player_id = clampi(int(args[0]), 0, 1)

func net_state() -> Array:
	var state := super.net_state()
	var flags: int = state[3]
	if is_invincible:
		flags |= NET_INVINCIBLE
	if is_invincible and _helmet_invincible and invincible_timer > WREATH_MIN_LEFT:
		flags |= NET_WREATH
	if is_mine_slowed:
		flags |= NET_SLOWED
	if is_invincible and _hit_grace_only:
		flags |= NET_HIT_GRACE
	state[3] = flags
	state.append(net_override)
	return state

func net_apply(state: Array) -> void:
	super.net_apply(state)
	var flags := int(state[3])
	is_invincible = flags & NET_INVINCIBLE != 0
	net_hit_grace_only = flags & NET_HIT_GRACE != 0
	# The wreath shows while more than WREATH_MIN_LEFT is left; the host says
	# when, so the clock here only has to sit on the right side of it.
	_helmet_invincible = flags & NET_WREATH != 0
	invincible_timer = WREATH_MIN_LEFT + 1.0 if _helmet_invincible else (1.0 if is_invincible else 0.0)
	is_mine_slowed = flags & NET_SLOWED != 0
	# The host's correction: this machine's tank starts again from the host's
	# position. (While the host drives it, it's already there: NetClientWorld.)
	var override := int(state[NET_OVERRIDE_AT]) if state.size() > NET_OVERRIDE_AT else 0
	if override != _override_seen:
		_override_seen = override
		if is_net_driving():
			global_position = Vector2(state[0], state[1])
			current_direction = FACINGS[clampi(int(state[2]), 0, FACINGS.size() - 1)]
			_update_sprite_direction()
			velocity = Vector2.ZERO

func _net_apply_addons(bits: int) -> void:
	var wanted := BaseTank.net_addon_names(bits)
	var moon := "moon-shield" in wanted
	if moon and not has_moon_shield:
		apply_addon("moon-shield")
	elif not moon and has_moon_shield:
		_remove_moon_shield()
	var utility := ""
	for addon_name in wanted:
		if addon_name in UTILITY_ADDONS:
			utility = addon_name
	if utility != _current_utility_addon:
		if utility.is_empty():
			_remove_utility_addon()
		else:
			apply_addon(utility)

## Rumbles player [param pid]'s controller with [param pattern], their tank on
## the field or not (a kill by a shell still flying, or by a mine). Online it's
## whoever drives that tank, on this machine or a client (Net.rumble_tank).
static func rumble_player(pid: int, pattern: Array[float]) -> void:
	Net.rumble_tank(pid, pattern[0], pattern[1], pattern[2])

func take_damage() -> void:
	take_hit(1)

## One hit of [param points]: one level lost for it, one rumble, and the grace.
func take_hit(points: int) -> void:
	if is_invincible and _hit_grace_frame != Engine.get_process_frames():
		return
	# An airborne tank (a mine throw) loses no level for the hit, as in the original.
	if not has_memory_save and not is_flying:
		_apply_hit_punishment()
	_rumble(HIT_RUMBLE)  # a fatal hit's destroy() takes over with the big one
	super.take_hit(points)  # reduces health + triggers the shared damage flash
	if health > 0 and not is_flying:
		var longer := is_invincible and invincible_timer > HIT_GRACE  # (a helmet's, say, runs on)
		_hit_grace_frame = Engine.get_process_frames()
		_activate_invincibility(HIT_GRACE)
		_hit_grace_only = not longer

## The hit's sound is this player's tank's: the client driving it, having shown
## the hit at once (guess_hit_here), leaves the host's out.
func _hit_sound_tank() -> int:
	return player_id

## Client: a shell of the enemies' met this machine's own tank as this screen
## shows it in its physics frame [param frame], a hit it survives, which the
## host judges by what this screen shows (NetClientWorld._show_own_hits): its
## red flash and its sound at once, and the grace after it, as the host's word
## will have them. Its damage and the rumble come with that word.
func guess_hit_here(frame: int) -> void:
	var now := Time.get_ticks_msec()
	_flash_guessed_until = now + int(DAMAGE_FLASH_DURATION * 1000.0)
	_grace_guessed_frame = frame
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	_flashes_owed.append(now)
	SoundManager.play_predicted(&"tank_hit", player_id)

## Client: in its physics frame [param frame], within the grace after a hit
## shown here at once (guess_hit_here), counted in frames as the host does.
func in_guessed_grace(frame: int) -> bool:
	return frame - _grace_guessed_frame < roundi(HIT_GRACE * Engine.physics_ticks_per_second)

## Client: the host's flash of a hit shown here at once already (the host's
## state starting a flash with one owed) is left out, and a flash shown here at
## once runs on whatever the host's state says meanwhile.
func _shown_flash(host: float) -> float:
	var now := Time.get_ticks_msec()
	if host > _host_flash_was + 0.05:
		while not _flashes_owed.is_empty() and now - _flashes_owed[0] > FLASH_OWED_MS:
			_flashes_owed.pop_front()
		_host_flash_left_out = not _flashes_owed.is_empty()
		if _host_flash_left_out:
			_flashes_owed.pop_front()
	elif host <= 0.0:
		_host_flash_left_out = false
	_host_flash_was = host
	var guessed := maxf(float(_flash_guessed_until - now), 0.0) / 1000.0
	return maxf(0.0 if _host_flash_left_out else host, guessed)

func launch_mine_fly(mine_level: int, mine_center: Vector2, landing_hit: int = 0, owner_id: int = -1) -> void:
	if not is_flying:
		_rumble(MINE_THROW_RUMBLE)
	super.launch_mine_fly(mine_level, mine_center, landing_hit, owner_id)

func destroy() -> void:
	if is_queued_for_deletion():
		return  # already destroyed this frame (a bomb and a shell): one life
	_rumble(DEATH_RUMBLE)
	if has_memory_save:
		# Spray the memory-save addon cookie
		var mem_cookie_type: int = CookieData.ADDON_TO_COOKIE.get("memory-save", -1)
		if mem_cookie_type >= 0:
			_spawn_cookie_at_position(mem_cookie_type)
		# Save current stats before lose_life() resets them
		var saved_speed: int = speed_level
		var saved_weapon: int = weapon_level
		var saved_secondary_type: String = secondary_weapon_type
		var saved_secondary_count: int = secondary_weapon_count
		var saved_addons: Array = []
		if has_moon_shield:
			saved_addons.append("moon-shield")
		# Normal death flow
		Events.player_died.emit(player_id)
		GameManager.lose_life(player_id)
		# Restore saved stats into GameManager so the respawned tank loads them
		GameManager.player_speed_levels[player_id] = saved_speed
		GameManager.player_weapon_levels[player_id] = saved_weapon
		GameManager.player_secondary_weapon_types[player_id] = saved_secondary_type
		GameManager.player_secondary_weapon_counts[player_id] = saved_secondary_count
		GameManager.player_addons[player_id] = saved_addons
		_spawn_explosion()
		queue_free()
	else:
		Events.player_died.emit(player_id)
		GameManager.lose_life(player_id)
		_spawn_explosion()
		queue_free()
