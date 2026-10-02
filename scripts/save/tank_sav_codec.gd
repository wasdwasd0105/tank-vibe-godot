class_name TankSavCodec
extends RefCounted
## Reads the original Tank.exe save files (.sav) and converts them into the
## JSON layout SaveManager writes to user://save/*.tsave.
##
## Port of tank_save_codec.py: a save is exactly 860 bytes, XOR-obfuscated with
## a key derived from the byte index and a fixed password, and starts with a
## checksum over the rest of the record. All numbers are little-endian; strings
## are Pascal-style (length byte first).

const SAVE_SIZE := 860
const PASSWORD := "Leonardo Liang 's Tank"

# Header layout (offsets into the decrypted record)
const HEADER_GAME_MODE := 0x004
const HEADER_P1_NAME := 0x008
const HEADER_P2_NAME := 0x108
const HEADER_EXTRA := 0x208
const HEADER_CREATED := 0x218
const HEADER_SAVED := 0x220
const HEADER_START_DIFFICULTY := 0x228
const HEADER_DIFFICULTY := 0x22A
const HEADER_MAX_CREDITS := 0x22C
const HEADER_CREDIT := 0x22E
const HEADER_STAGE := 0x230
const HEADER_COUNTER := 0x232
const PLAYER1_BASE := 0x274
const PLAYER2_BASE := 0x2E8

# Player record layout (relative to the player base)
const PLAYER_SCORE := 0x00
const PLAYER_LIVES := 0x04
const PLAYER_KEY := 0x08
const PLAYER_ACTIVE_1 := 0x18
const PLAYER_ACTIVE_2 := 0x1A
const PLAYER_STAGES := 0x1C
const PLAYER_HP := 0x60
const PLAYER_WEAPON_LEVEL := 0x64
const PLAYER_SPEED_LEVEL := 0x68
const PLAYER_SPECIAL_COUNT := 0x6C
const PLAYER_SPECIAL_TYPE := 0x70
const PLAYER_ADDON_TYPE := 0x71

## Delphi TDateTime counts days since 1899-12-30; this is that day as unix time.
const TDATETIME_EPOCH_UNIX := -2209161600

## Original secondary weapon indices (see docs/*_weapon_original_spec.md):
## 0 normal, 1 rapid, 2 fire, 3 AP, 4 explosion, 5 mine.
## The remake has no "normal" secondary weapon, so 0 becomes rapid.
const WEAPON_NAMES := {0: "rapid", 1: "rapid", 2: "fire", 3: "ap", 4: "explosion", 5: "mine"}
const DEFAULT_WEAPON := "rapid"

## Original defense addon byte, in the addon cookie order:
## 0 none, 1 anti-water, 2 anti-ice, 3 moon shield, 4 memory save.
## Names use the save-file spelling (underscores) that SaveManager expects.
const ADDON_NAMES := {1: "anti_water", 2: "anti_ice", 3: "moon_shield", 4: "memory_save"}
const MOON_SHIELD := "moon_shield"
const MAX_UPGRADE_LEVEL := 3


## Decodes raw .sav bytes into nested dictionaries (same keys as the Python
## codec). Returns {"error": message} when the bytes are not a valid save.
static func decode(encrypted: PackedByteArray) -> Dictionary:
	if encrypted.size() != SAVE_SIZE:
		return {"error": TranslationServer.translate("wrong size (%d bytes, expected %d)") % [encrypted.size(), SAVE_SIZE]}
	var clear := crypt(encrypted)
	if clear.decode_u32(0) != checksum(clear):
		return {"error": TranslationServer.translate("checksum mismatch (damaged file or not a Tank.exe save)")}
	return {
		"header": {
			"game_mode": clear.decode_u32(HEADER_GAME_MODE),
			"player1_name": _short_string(clear, HEADER_P1_NAME, 256),
			"player2_name": _short_string(clear, HEADER_P2_NAME, 256),
			"extra_string": _short_string(clear, HEADER_EXTRA, 16),
			"created_iso": tdatetime_to_iso(clear.decode_double(HEADER_CREATED)),
			"saved_iso": tdatetime_to_iso(clear.decode_double(HEADER_SAVED)),
			"start_difficulty": clear.decode_u16(HEADER_START_DIFFICULTY),
			"difficulty": clear.decode_u16(HEADER_DIFFICULTY),
			"max_credits": clear.decode_u16(HEADER_MAX_CREDITS),
			"credit": clear.decode_u16(HEADER_CREDIT),
			"current_stage": clear.decode_u16(HEADER_STAGE),
			"counter": clear.decode_u16(HEADER_COUNTER),
		},
		"players": {
			"player1": _decode_player(clear, PLAYER1_BASE),
			"player2": _decode_player(clear, PLAYER2_BASE),
		},
	}


## Applies the original game's XOR obfuscation. It is symmetric: the same call
## encrypts a clear record and decrypts an encrypted one.
static func crypt(data: PackedByteArray) -> PackedByteArray:
	var out := data.duplicate()
	var password := PASSWORD.to_ascii_buffer()
	for i in out.size():
		var key := (~((i & 0xFF) + password[i % password.size()])) & 0xFF
		out[i] = out[i] ^ key
	return out


## Checksum over the clear record with its first four bytes treated as zero.
static func checksum(clear: PackedByteArray) -> int:
	var acc1 := 0
	var acc2 := 0
	for i in SAVE_SIZE:
		var value := 0 if i < 4 else clear[i]
		acc1 += value * (i & 0xFF)
		acc2 += value * ((SAVE_SIZE - 1 - i) & 0xFF)
	return ((acc2 & 0xFFFF) << 16) | (acc1 & 0xFFFF)


## Delphi TDateTime (days since 1899-12-30) to "YYYY-MM-DDTHH:MM:SS.mmm".
## Zero (no timestamp) gives an empty string.
static func tdatetime_to_iso(value: float) -> String:
	if value == 0.0:
		return ""
	var seconds := value * 86400.0 + float(TDATETIME_EPOCH_UNIX)
	var whole := floori(seconds)
	var micros := roundi((seconds - float(whole)) * 1000000.0)
	if micros >= 1000000:
		whole += 1
		micros -= 1000000
	return "%s.%03d" % [Time.get_datetime_string_from_unix_time(whole, false), micros / 1000]


static func _decode_player(clear: PackedByteArray, base: int) -> Dictionary:
	return {
		"score": clear.decode_u32(base + PLAYER_SCORE),
		"lives": clear.decode_u32(base + PLAYER_LIVES),
		"player_key": _short_string(clear, base + PLAYER_KEY, 16),
		"active_flag1": clear.decode_s16(base + PLAYER_ACTIVE_1),
		"active_flag2": clear.decode_s16(base + PLAYER_ACTIVE_2),
		"stages_completed": clear.decode_u32(base + PLAYER_STAGES),
		"hp": clear.decode_u32(base + PLAYER_HP),
		"weapon_level": clear.decode_u32(base + PLAYER_WEAPON_LEVEL),
		"speed_level": clear.decode_u32(base + PLAYER_SPEED_LEVEL),
		"special_weapon_count": clear.decode_u32(base + PLAYER_SPECIAL_COUNT),
		"special_weapon_type": clear[base + PLAYER_SPECIAL_TYPE],
		"defense_addon_type": clear[base + PLAYER_ADDON_TYPE],
	}


## Pascal short string: length byte followed by Latin-1 characters.
static func _short_string(clear: PackedByteArray, offset: int, slot_size: int) -> String:
	var length := mini(clear[offset], slot_size - 1)
	return clear.slice(offset + 1, offset + 1 + length).get_string_from_ascii()


# =====================================================================
# Conversion to the remake's save layout
# =====================================================================

## Builds the dictionary SaveManager stores as a .tsave from a decoded record.
static func to_tsave(decoded: Dictionary, save_name: String, source_name: String) -> Dictionary:
	var header: Dictionary = decoded["header"]
	var players: Dictionary = decoded["players"]
	var player1: Dictionary = players["player1"]
	var player2: Dictionary = players["player2"]
	var p1_active := _is_active(player1)
	var p2_active := _is_active(player2)
	if not p1_active and not p2_active:
		# Neither slot carries an active flag: fall back to whoever has progress.
		p1_active = _has_progress(player1)
		p2_active = _has_progress(player2)
	var saved_iso: String = header["saved_iso"]
	if saved_iso.is_empty():
		saved_iso = Time.get_datetime_string_from_system(false, true)
	return {
		"meta": {
			"save_name": save_name,
			"imported_from": source_name,
			"player1_name": header["player1_name"],
			"player2_name": header["player2_name"],
		},
		"header": {
			"game_mode": header["game_mode"],
			"created_iso": header["created_iso"],
			"saved_iso": saved_iso,
			"start_difficulty": maxi(1, header["start_difficulty"]),
			"difficulty": maxi(1, header["difficulty"]),
			"current_stage": maxi(1, header["current_stage"]),
			"counter": header["counter"],
		},
		"players": {
			"player1": _convert_player(player1, "p1") if p1_active else null,
			"player2": _convert_player(player2, "p2") if p2_active else null,
		},
	}


static func _is_active(player: Dictionary) -> bool:
	return player["active_flag1"] != 0 or player["active_flag2"] != 0


static func _has_progress(player: Dictionary) -> bool:
	return player["lives"] > 0 or player["score"] > 0 or player["stages_completed"] > 0


static func _convert_player(player: Dictionary, player_name: String) -> Dictionary:
	var weapon: String = WEAPON_NAMES.get(player["special_weapon_type"], DEFAULT_WEAPON)
	var max_count: int = CookieData.WEAPON_DATA[weapon]["max_count"]
	var addon: String = ADDON_NAMES.get(player["defense_addon_type"], "")
	return {
		"player_name": player_name,
		"score": player["score"],
		"lives": player["lives"],
		"stages_completed": player["stages_completed"],
		"hp": maxi(1, player["hp"]),
		"weapon_level": clampi(player["weapon_level"], 0, MAX_UPGRADE_LEVEL),
		"speed_level": clampi(player["speed_level"], 0, MAX_UPGRADE_LEVEL),
		"special_weapon_count": clampi(player["special_weapon_count"], 0, max_count),
		"special_weapon_type": weapon,
		"defense_addon_type": "" if addon == MOON_SHIELD else addon,
		"defense_addon_type_2": MOON_SHIELD if addon == MOON_SHIELD else "",
	}
