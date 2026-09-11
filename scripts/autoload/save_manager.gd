extends Node

## SaveManager — handles saving/loading game state to .tsave files (JSON format).
## Save directory: user://save/

const SAVE_DIR := "user://save/"

func _ready() -> void:
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# =====================================================================
# Public API
# =====================================================================

## Create a new save file for the current game. Called when starting a new game.
func create_new_save() -> void:
	var save_name := _generate_save_name()
	var filename := save_name + ".tsave"
	GameManager.current_save_file = SAVE_DIR + filename
	save_game()

## Save the current GameManager state to the active .tsave file.
func save_game() -> void:
	if GameManager.current_save_file.is_empty():
		create_new_save()
		return

	# Build save data from live player tanks first
	GameManager.save_player_states()

	var data := _build_save_data()
	var json_string := JSON.stringify(data, "  ")

	var file := FileAccess.open(GameManager.current_save_file, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	else:
		push_warning("SaveManager: Failed to write save file: " + GameManager.current_save_file)

## Load a save file and restore GameManager state, then go to stage_intro.
func load_game(filepath: String) -> void:
	var file := FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_warning("SaveManager: Failed to open save file: " + filepath)
		return

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_string)
	if err != OK:
		push_warning("SaveManager: Failed to parse save file: " + filepath)
		return

	var data: Dictionary = json.data
	_restore_from_data(data)
	GameManager.current_save_file = filepath

	# Go directly to stage intro (skip join screen)
	get_tree().change_scene_to_file("res://scenes/stage_intro.tscn")

## Delete a save file by path.
func delete_save(filepath: String) -> bool:
	if FileAccess.file_exists(filepath):
		var err := DirAccess.remove_absolute(filepath)
		if err == OK:
			return true
		else:
			push_warning("SaveManager: Failed to delete save file: " + filepath)
	return false

## Import an original Tank.exe save (.sav) as a new .tsave in the save directory.
## The new save is named after the source file. Returns
## {"ok": true, "filepath": ..., "save_name": ...} or {"ok": false, "error": ...}.
func import_original_save(source_path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		return {"ok": false, "error": "could not read %s" % source_path.get_file()}
	var decoded := TankSavCodec.decode(bytes)
	if decoded.has("error"):
		return {"ok": false, "error": decoded["error"]}

	var save_name := _unique_save_name(_sanitize_save_name(source_path.get_file().get_basename()))
	var data := TankSavCodec.to_tsave(decoded, save_name, source_path.get_file())
	var filepath := SAVE_DIR + save_name + ".tsave"
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if not file:
		return {"ok": false, "error": "could not write %s" % filepath}
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return {"ok": true, "filepath": filepath, "save_name": save_name}

## Get list of save files with metadata for the load screen.
## Returns Array of Dictionaries sorted by saved_iso (newest first).
func get_save_list() -> Array:
	var saves: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return saves

	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tsave"):
			var info := _read_save_info(SAVE_DIR + fname)
			if not info.is_empty():
				info["filepath"] = SAVE_DIR + fname
				saves.append(info)
		fname = dir.get_next()
	dir.list_dir_end()

	# Sort newest first
	saves.sort_custom(func(a, b): return a.get("saved_iso", "") > b.get("saved_iso", ""))
	return saves

# =====================================================================
# Build save data from GameManager
# =====================================================================

func _build_save_data() -> Dictionary:
	var gm := GameManager
	var save_name := _get_save_name_from_path(gm.current_save_file)

	var data := {
		"meta": {
			"save_name": save_name,
		},
		"header": {
			"game_mode": 0,
			"created_iso": gm.save_created_iso,
			"saved_iso": Time.get_datetime_string_from_system(false, true),
			"start_difficulty": gm.start_difficulty,
			"difficulty": gm.difficulty,
			"max_credits": gm.max_credits,
			"credit": gm.credits,
			"current_stage": gm.current_stage,
			"counter": gm.save_counter,
		},
		"players": {},
	}

	# Player 1
	if gm.player_active[0]:
		data["players"]["player1"] = _build_player_data(0)
	else:
		data["players"]["player1"] = null

	# Player 2
	if gm.player_active[1]:
		data["players"]["player2"] = _build_player_data(1)
	else:
		data["players"]["player2"] = null

	return data

func _build_player_data(pid: int) -> Dictionary:
	var gm := GameManager
	var addons: Array = gm.player_addons[pid]

	# Split addons into defense_addon_type (utility) and defense_addon_type_2 (moon-shield)
	var defense_addon := ""
	var defense_addon_2 := ""
	for addon_name in addons:
		if addon_name == "moon-shield":
			defense_addon_2 = _addon_to_save(addon_name)
		else:
			defense_addon = _addon_to_save(addon_name)

	return {
		"player_name": "p1" if pid == 0 else "p2",
		"score": gm.player_scores[pid],
		"lives": gm.player_lives[pid],
		"hp": gm.player_hp[pid],
		"weapon_level": gm.player_weapon_levels[pid],
		"speed_level": gm.player_speed_levels[pid],
		"special_weapon_count": gm.player_secondary_weapon_counts[pid],
		"special_weapon_type": gm.player_secondary_weapon_types[pid],
		"defense_addon_type": defense_addon,
		"defense_addon_type_2": defense_addon_2,
	}

# =====================================================================
# Restore GameManager from save data
# =====================================================================

func _restore_from_data(data: Dictionary) -> void:
	var gm := GameManager
	var header: Dictionary = data.get("header", {})
	var players: Dictionary = data.get("players", {})
	var meta: Dictionary = data.get("meta", {})

	# Header
	gm.current_stage = header.get("current_stage", 1)
	gm.difficulty = header.get("difficulty", 1)
	gm.start_difficulty = header.get("start_difficulty", 1)
	gm.max_credits = header.get("max_credits", 3)
	gm.credits = header.get("credit", 3)
	gm.save_counter = header.get("counter", 0)
	gm.save_created_iso = header.get("created_iso", "")

	# Reset runtime state
	gm.is_game_over = false
	gm.enemies_frozen = false
	gm.enemies_remaining = 20
	gm.player_kills = [{}, {}]

	# Player 1
	var p1_data = players.get("player1")
	if p1_data != null and p1_data is Dictionary:
		gm.player_active[0] = true
		_restore_player(0, p1_data)
	else:
		gm.player_active[0] = false
		_reset_player_defaults(0)

	# Player 2
	var p2_data = players.get("player2")
	if p2_data != null and p2_data is Dictionary:
		gm.player_active[1] = true
		_restore_player(1, p2_data)
	else:
		gm.player_active[1] = false
		_reset_player_defaults(1)

func _restore_player(pid: int, pdata: Dictionary) -> void:
	var gm := GameManager
	gm.player_scores[pid] = pdata.get("score", 0)
	gm.player_lives[pid] = pdata.get("lives", 3)
	gm.player_hp[pid] = pdata.get("hp", 4)
	gm.player_weapon_levels[pid] = pdata.get("weapon_level", 0)
	gm.player_speed_levels[pid] = pdata.get("speed_level", 1)
	gm.player_secondary_weapon_counts[pid] = pdata.get("special_weapon_count", 50)
	gm.player_secondary_weapon_types[pid] = pdata.get("special_weapon_type", "rapid")

	# Restore addons
	var addons: Array = []
	var addon1: String = pdata.get("defense_addon_type", "")
	var addon2: String = pdata.get("defense_addon_type_2", "")
	if addon1 != "":
		addons.append(_addon_from_save(addon1))
	if addon2 != "":
		addons.append(_addon_from_save(addon2))
	gm.player_addons[pid] = addons

func _reset_player_defaults(pid: int) -> void:
	var gm := GameManager
	gm.player_lives[pid] = 3
	gm.player_scores[pid] = 0
	gm.player_hp[pid] = 4
	gm.player_speed_levels[pid] = 1
	gm.player_weapon_levels[pid] = 0
	gm.player_secondary_weapon_types[pid] = "rapid"
	gm.player_secondary_weapon_counts[pid] = 50
	gm.player_addons[pid] = []

# =====================================================================
# Read save info for the load screen (lightweight, no full restore)
# =====================================================================

func _read_save_info(filepath: String) -> Dictionary:
	var file := FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return {}
	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		return {}

	var data: Dictionary = json.data
	var meta: Dictionary = data.get("meta", {})
	var header: Dictionary = data.get("header", {})
	var players: Dictionary = data.get("players", {})

	var p1_data = players.get("player1")
	var p2_data = players.get("player2")

	return {
		"save_name": meta.get("save_name", "???"),
		"stage": header.get("current_stage", 1),
		"counter": header.get("counter", 0),
		"difficulty": header.get("difficulty", 1),
		"saved_iso": header.get("saved_iso", ""),
		"p1_active": p1_data != null and p1_data is Dictionary,
		"p1_score": p1_data.get("score", 0) if p1_data is Dictionary else 0,
		"p2_active": p2_data != null and p2_data is Dictionary,
		"p2_score": p2_data.get("score", 0) if p2_data is Dictionary else 0,
	}

# =====================================================================
# Helpers
# =====================================================================

## Convert addon name from code format to save format: "anti-water" → "anti_water"
func _addon_to_save(name: String) -> String:
	return name.replace("-", "_")

## Convert addon name from save format to code format: "anti_water" → "anti-water"
func _addon_from_save(name: String) -> String:
	return name.replace("_", "-")

## Generate a unique save name like "Save_001", "Save_002", etc.
func _generate_save_name() -> String:
	var existing := get_save_list()
	var max_num := 0
	for info in existing:
		var sn: String = info.get("save_name", "")
		if sn.begins_with("Save_"):
			var num_str := sn.substr(5)
			if num_str.is_valid_int():
				max_num = maxi(max_num, num_str.to_int())
	return "Save_%03d" % (max_num + 1)

## Keep only letters, digits, "_" and "-" so the name is safe as a file name.
func _sanitize_save_name(name: String) -> String:
	var clean := RegEx.create_from_string("[^A-Za-z0-9_-]+").sub(name, "_", true).left(40)
	return clean if not clean.is_empty() else "Imported"

## Append _2, _3, ... until no save file with that name exists.
func _unique_save_name(base: String) -> String:
	var candidate := base
	var suffix := 2
	while FileAccess.file_exists(SAVE_DIR + candidate + ".tsave"):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate

## Extract save name from file path (without extension)
func _get_save_name_from_path(path: String) -> String:
	var fname := path.get_file()
	if fname.ends_with(".tsave"):
		return fname.substr(0, fname.length() - 6)
	return fname
