extends Node

## SoundManager — autoload owning all audio playback.
##
## Game code plays a *logical* sound name (e.g. &"tank_hit"), never a file path.
## Each logical name resolves to one or more wave files; when it has several the
## manager picks one at random, which is how the original game varied its
## explosions.
##
## Sounds are theme-aware. Resolution order for every file:
##   1. the current theme's sound folder      (themes/<theme>/<sounds dir>/<name>.wav)
##   2. an explicit override in theme.cfg     ([sounds] <logical name>="a.wav,b.wav")
##   3. the shared default set                (res://assets/sounds/<name>.wav)
##   4. silence — a missing sound is never an error
## So a theme overrides a sound simply by shipping a file of the same name, and
## may override as few or as many as it likes.
##
## The default set is the original Tank.exe audio, extracted from its DelphiX
## TDXWaveList. See docs/sound_original_spec.md for the id-by-id provenance.

signal sounds_reloaded(theme_name: String)

const DEFAULT_DIR: String = "res://assets/sounds/"
const THEMES_DIR: String = "res://themes/"
const SFX_BUS: StringName = &"SFX"
const MUSIC_BUS: StringName = &"Music"

## Simultaneous sound effects. The original mixed 8 DirectSound buffers.
const SFX_VOICES: int = 16

## Two requests for the same sound closer together than this collapse into one.
## Guards against a single frame spawning a dozen identical voices (which only
## phases and clips); well below any real repeat rate, so per-bullet sounds
## still fire per bullet.
const MIN_REPEAT_INTERVAL: float = 0.03

## How long a client waits for the host's sound of a shot it heard already
## (play_predicted).
const PREDICTED_WAIT_MS := 1500

## Logical sound name -> the wave file(s) that can satisfy it, without extension.
## Several entries mean "pick one at random" (the original used Random(2) for
## explosions and mine blasts). Several logical names may share a file: the
## original played the same explosion pair for a dead tank and a dead base.
const CATALOG: Dictionary = {
	# --- weapons: the original indexed these by weapon type, 0-5 ---
	&"fire_primary":    ["fire_primary"],
	&"fire_rapid":      ["fire_rapid"],
	&"fire_fire":       ["fire_fire"],
	&"fire_ap":         ["fire_ap"],
	&"fire_explosion":  ["fire_explosion"],
	&"lay_mine":        ["lay_mine"],
	# --- destruction ---
	&"tank_destroyed":  ["explode_1", "explode_2"],
	&"base_destroyed":  ["explode_1", "explode_2"],
	&"mine_explode":    ["mine_explode_1", "mine_explode_2"],
	# --- impacts ---
	&"tank_hit":        ["tank_hit"],
	&"shield_absorb":   ["shield_absorb"],
	&"bullet_clink":    ["bullet_clink"],
	# --- pickups and rewards ---
	&"powerup_appear":  ["powerup_appear"],
	&"powerup_pickup":  ["powerup_pickup"],
	&"extra_life":      ["extra_life"],
	&"bonus_reward":    ["bonus_reward"],
	# --- interface ---
	&"ui_select":       ["ui_select"],
	&"player_join":     ["player_join"],
	# --- music (long, plays on the music bus, stops the previous track) ---
	&"stage_win":       ["stage_win"],
	&"stage_lose":      ["stage_lose"],
}

## The menus' click: always this machine's own, never sent to or taken from a host.
const UI_KEY: StringName = &"ui_select"

## Logical names routed to the music bus instead of the sfx bus.
const MUSIC_KEYS: Array[StringName] = [&"stage_win", &"stage_lose"]

var _streams: Dictionary = {}        # file base name -> AudioStream (or null when missing)
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _next_voice: int = 0
var _last_played: Dictionary = {}    # logical name -> msec of last playback
var _rng := RandomNumberGenerator.new()
## Online, on a client: its own tanks' shots it heard as it fired them, ahead of
## the host's sound of them (play_predicted): [tank, logical name, msec], oldest
## first. The host's sound of each is left out when it comes.
var _predicted: Array = []


func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	_build_players()
	apply_saved_volumes()
	reload_sounds()
	ThemeManager.theme_changed.connect(_on_theme_changed)
	_connect_events()


# =====================================================================
# Event routing
# =====================================================================

## Everything the game already announces through Events is wired here, so the
## mapping from game event to sound lives in one readable place. Sounds with no
## matching signal (weapon fire, damage, menu clicks) call play() directly at
## their site instead.
func _connect_events() -> void:
	Events.player_died.connect(func(_player_id: int) -> void: play(&"tank_destroyed"))
	Events.enemy_destroyed.connect(func(_enemy: Node2D, _points: int) -> void: play(&"tank_destroyed"))
	Events.base_destroyed.connect(func() -> void: play(&"base_destroyed"))
	Events.player_joined.connect(func(_player_id: int) -> void: play(&"player_join"))
	Events.cookie_spawned.connect(func(_cookie: Node2D) -> void: play(&"powerup_appear"))
	Events.cookie_collected.connect(func(_type: int, _player_id: int) -> void: play(&"powerup_pickup"))
	Events.stage_cleared.connect(func() -> void: play_music(&"stage_win"))
	Events.game_over.connect(func() -> void: play_music(&"stage_lose"))


# =====================================================================
# Public API
# =====================================================================

## Plays a sound effect by logical name. Unknown or missing sounds do nothing.
## Online, a host's game sounds go to its clients too, as player [param tank]'s
## tank's if it made it (its shots: the client driving it heard them already,
## play_predicted). A client's game plays only the host's (play_from_host), and
## its own menu clicks.
func play(key: StringName, tank: int = -1) -> void:
	if key in MUSIC_KEYS:
		play_music(key)
		return
	if key != UI_KEY:
		if Net.is_client():
			return
		NetHostWorld.record(NetWorld.EV_SOUND, [String(key)] if tank < 0 else [String(key), tank])
	_play_sfx(key)


## A client plays a shot of its own tank, player [param tank]'s, as it fires it
## (lag compensation): the host's sound of that shot, when it comes, is left out.
func play_predicted(key: StringName, tank: int) -> void:
	_predicted.append([tank, key, Time.get_ticks_msec()])
	_play_sfx(key)


## A client plays a sound the host's game played, player [param tank]'s tank's
## if it made it.
func play_from_host(key: StringName, tank: int = -1) -> void:
	if tank >= 0 and _take_predicted(key, tank):
		return  # heard already, as this machine fired it
	if key in MUSIC_KEYS:
		play_music_from_host(key)
	elif CATALOG.has(key):
		_play_sfx(key)


## True if a client heard [param tank]'s [param key] already (play_predicted),
## which the host's sound of it now settles.
func _take_predicted(key: StringName, tank: int) -> bool:
	var now := Time.get_ticks_msec()
	while not _predicted.is_empty() and now - int(_predicted[0][2]) > PREDICTED_WAIT_MS:
		_predicted.pop_front()  # a shot the host never fired
	for i in _predicted.size():
		if _predicted[i][0] == tank and _predicted[i][1] == key:
			_predicted.remove_at(i)
			return true
	return false


func _play_sfx(key: StringName) -> void:
	var stream := _pick_stream(key)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	var last: int = _last_played.get(key, -100000)
	if now - last < int(MIN_REPEAT_INTERVAL * 1000.0):
		return
	_last_played[key] = now
	var player := _next_sfx_player()
	player.stream = stream
	player.play()


## Plays a long track on the music bus, replacing whatever was playing.
func play_music(key: StringName) -> void:
	if Net.is_client():
		return
	NetHostWorld.record(NetWorld.EV_MUSIC, [String(key)])
	play_music_from_host(key)


## A client plays a track the host's game played.
func play_music_from_host(key: StringName) -> void:
	if not CATALOG.has(key):
		return
	var stream := _pick_stream(key)
	if stream == null:
		return
	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	NetHostWorld.record(NetWorld.EV_STOP_MUSIC)
	if _music_player:
		_music_player.stop()


## Gives every button under [param root] the menu click sound. Safe to call
## again after rebuilding a list; already-wired buttons are skipped.
func attach_ui_sounds(root_node: Node) -> void:
	for node: Node in _all_buttons(root_node):
		var button := node as BaseButton
		if not button.pressed.is_connected(_play_ui_select):
			button.pressed.connect(_play_ui_select)


func _all_buttons(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is BaseButton:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_all_buttons(child))
	return found


func _play_ui_select() -> void:
	play(UI_KEY)


## True when the current theme (or the default set) can actually play this name.
func has_sound(key: StringName) -> bool:
	return _pick_stream(key) != null


## Reloads every wave for the current theme. Called on theme change.
func reload_sounds() -> void:
	_streams.clear()
	var wanted: Dictionary = {}
	for key: StringName in CATALOG:
		for base: String in _files_for(key):
			wanted[base] = true
	for base: String in wanted:
		_streams[base] = _load_stream(base)
	sounds_reloaded.emit(ThemeManager.current_theme)


# --- volume, 0.0 to 1.0 ---

func set_sfx_volume(value: float) -> void:
	_set_bus_volume(SFX_BUS, value)
	InputSettings.save_sfx_volume(value)


func set_music_volume(value: float) -> void:
	_set_bus_volume(MUSIC_BUS, value)
	InputSettings.save_music_volume(value)


func get_sfx_volume() -> float:
	return InputSettings.get_saved_sfx_volume()


func get_music_volume() -> float:
	return InputSettings.get_saved_music_volume()


func apply_saved_volumes() -> void:
	_set_bus_volume(SFX_BUS, InputSettings.get_saved_sfx_volume())
	_set_bus_volume(MUSIC_BUS, InputSettings.get_saved_music_volume())


# =====================================================================
# Resolution
# =====================================================================

## The wave file base names backing a logical sound, honouring a theme's
## explicit [sounds] override before falling back to the catalogue.
func _files_for(key: StringName) -> Array:
	var override: String = _theme_value(String(key), "")
	if not override.is_empty():
		var names: Array = []
		for part: String in override.split(",", false):
			names.append(part.strip_edges().get_file().get_basename())
		if not names.is_empty():
			return names
	return CATALOG.get(key, [])


func _pick_stream(key: StringName) -> AudioStream:
	var candidates: Array = []
	for base: String in _files_for(key):
		var stream: AudioStream = _streams.get(base)
		if stream != null:
			candidates.append(stream)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## Theme sound file for [param base], or the shared default, or null.
func _load_stream(base: String) -> AudioStream:
	for path: String in _candidate_paths(base):
		var stream := _load_wave(path)
		if stream != null:
			return stream
	return null


func _candidate_paths(base: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	var theme_dir := THEMES_DIR + ThemeManager.current_theme + "/"
	var sounds_dir: String = _theme_value("dir", "sounds/")
	if not sounds_dir.is_empty():
		if not sounds_dir.ends_with("/"):
			sounds_dir += "/"
		paths.append(theme_dir + sounds_dir + base + ".wav")
	paths.append(DEFAULT_DIR + base + ".wav")
	return paths


## Loads a wave, preferring the imported resource so exported builds work
## (res:// files live inside the pack and have no real filesystem path there),
## and falling back to a raw read for theme folders Godot has not imported.
func _load_wave(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStream:
			return res
	var fs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(fs_path):
		return null
	return AudioStreamWAV.load_from_file(fs_path)


## Reads a key from the current theme's [sounds] section.
func _theme_value(key: String, fallback: String) -> String:
	return str(ThemeManager.get_theme_setting("sounds", key, fallback))


# =====================================================================
# Setup
# =====================================================================

func _ensure_buses() -> void:
	for bus_name: StringName in [SFX_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, &"Master")


func _build_players() -> void:
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		# Sounds keep playing across a pause menu only if we say so; the game
		# pauses the tree, and a cut-off explosion sounds broken.
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_sfx_players.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)


## Round-robin voice allocation, preferring one that is not already busy.
func _next_sfx_player() -> AudioStreamPlayer:
	for i in _sfx_players.size():
		var index := (_next_voice + i) % _sfx_players.size()
		if not _sfx_players[index].playing:
			_next_voice = (index + 1) % _sfx_players.size()
			return _sfx_players[index]
	# Every voice busy: steal the next one in rotation.
	var steal := _next_voice
	_next_voice = (_next_voice + 1) % _sfx_players.size()
	return _sfx_players[steal]


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var clamped := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, is_zero_approx(clamped))
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped, 0.0001)))


func _on_theme_changed(_theme_name: String) -> void:
	reload_sounds()
