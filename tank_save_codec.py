#!/usr/bin/env python3
"""Tank save decoder/encoder.

Commands:
  decode <input.sav> [output.json]
  decodeall <input_folder> [output_folder]
  encode <input.json> [output.sav]
  encodeall <input_folder> [output_folder]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict

PASSWORD = b"Leonardo Liang 's Tank"
SAVE_SIZE = 860


def crypt(data: bytes) -> bytes:
    out = bytearray(data)
    pw_len = len(PASSWORD)
    for i in range(len(out)):
        key = (~(((i & 0xFF) + PASSWORD[i % pw_len]))) & 0xFF
        out[i] ^= key
    return bytes(out)


def compute_checksum(clear_data: bytes) -> int:
    if len(clear_data) != SAVE_SIZE:
        raise ValueError(f"Invalid save size: {len(clear_data)}, expected {SAVE_SIZE}")
    buf = bytearray(clear_data)
    buf[0:4] = b"\x00\x00\x00\x00"
    acc1 = 0
    acc2 = 0
    for i, v in enumerate(buf):
        acc1 += v * (i & 0xFF)
        acc2 += v * ((SAVE_SIZE - 1 - i) & 0xFF)
    return ((acc2 & 0xFFFF) << 16) | (acc1 & 0xFFFF)


def tdatetime_to_iso(value: float) -> str:
    base = dt.datetime(1899, 12, 30)
    days = int(value)
    frac = value - days
    stamp = base + dt.timedelta(days=days, seconds=frac * 86400)
    return stamp.isoformat(timespec="milliseconds")


def iso_to_tdatetime(value: str) -> float:
    base = dt.datetime(1899, 12, 30)
    stamp = dt.datetime.fromisoformat(value)
    delta = stamp - base
    return delta.total_seconds() / 86400


def parse_short_string(buf: bytes, offset: int, slot_size: int) -> str:
    n = buf[offset]
    if n > slot_size - 1:
        n = slot_size - 1
    return buf[offset + 1 : offset + 1 + n].decode("latin1", errors="replace")


def write_short_string(buf: bytearray, offset: int, slot_size: int, value: str) -> None:
    raw = value.encode("latin1", errors="replace")
    max_len = slot_size - 1
    if len(raw) > max_len:
        raw = raw[:max_len]
    buf[offset : offset + slot_size] = b"\x00" * slot_size
    buf[offset] = len(raw)
    buf[offset + 1 : offset + 1 + len(raw)] = raw


def read_u16_le(buf: bytes, offset: int) -> int:
    return int.from_bytes(buf[offset : offset + 2], "little", signed=False)


def read_i16_le(buf: bytes, offset: int) -> int:
    return int.from_bytes(buf[offset : offset + 2], "little", signed=True)


def read_u32_le(buf: bytes, offset: int) -> int:
    return int.from_bytes(buf[offset : offset + 4], "little", signed=False)


def write_u16_le(buf: bytearray, offset: int, value: int) -> None:
    buf[offset : offset + 2] = int(value).to_bytes(2, "little", signed=False)


def write_i16_le(buf: bytearray, offset: int, value: int) -> None:
    buf[offset : offset + 2] = int(value).to_bytes(2, "little", signed=True)


def write_u32_le(buf: bytearray, offset: int, value: int) -> None:
    buf[offset : offset + 4] = int(value).to_bytes(4, "little", signed=False)


def read_f64_le(buf: bytes, offset: int) -> float:
    import struct

    return struct.unpack_from("<d", buf, offset)[0]


def write_f64_le(buf: bytearray, offset: int, value: float) -> None:
    import struct

    struct.pack_into("<d", buf, offset, float(value))


def decode_player(clear_data: bytes, base: int) -> Dict[str, Any]:
    return {
        "score": read_u32_le(clear_data, base + 0x00),
        "lives": read_u32_le(clear_data, base + 0x04),
        "player_key": parse_short_string(clear_data, base + 0x08, 16),
        "active_flag1": read_i16_le(clear_data, base + 0x18),
        "active_flag2": read_i16_le(clear_data, base + 0x1A),
        "stages_completed": read_u32_le(clear_data, base + 0x1C),
        "reserved_0x20_64_hex": clear_data[base + 0x20 : base + 0x60].hex(),
        "hp": read_u32_le(clear_data, base + 0x60),
        "weapon_level": read_u32_le(clear_data, base + 0x64),
        "speed_level": read_u32_le(clear_data, base + 0x68),
        "special_weapon_count": read_u32_le(clear_data, base + 0x6C),
        "special_weapon_type": clear_data[base + 0x70],
        "defense_addon_type": clear_data[base + 0x71],
        "padding_0x72_2_hex": clear_data[base + 0x72 : base + 0x74].hex(),
    }


def encode_player(buf: bytearray, base: int, data: Dict[str, Any]) -> None:
    write_u32_le(buf, base + 0x00, int(data.get("score", 0)))
    write_u32_le(buf, base + 0x04, int(data.get("lives", 0)))
    write_short_string(buf, base + 0x08, 16, str(data.get("player_key", "")))
    write_i16_le(buf, base + 0x18, int(data.get("active_flag1", 0)))
    write_i16_le(buf, base + 0x1A, int(data.get("active_flag2", 0)))
    write_u32_le(buf, base + 0x1C, int(data.get("stages_completed", 0)))

    reserved = bytes.fromhex(str(data.get("reserved_0x20_64_hex", ""))) if data.get("reserved_0x20_64_hex") else b"\x00" * 64
    if len(reserved) != 64:
        raise ValueError("player reserved_0x20_64_hex must be 64 bytes (128 hex chars)")
    buf[base + 0x20 : base + 0x60] = reserved

    write_u32_le(buf, base + 0x60, int(data.get("hp", 0)))
    write_u32_le(buf, base + 0x64, int(data.get("weapon_level", 0)))
    write_u32_le(buf, base + 0x68, int(data.get("speed_level", 0)))
    write_u32_le(buf, base + 0x6C, int(data.get("special_weapon_count", 0)))
    buf[base + 0x70] = int(data.get("special_weapon_type", 0)) & 0xFF
    buf[base + 0x71] = int(data.get("defense_addon_type", 0)) & 0xFF

    pad = bytes.fromhex(str(data.get("padding_0x72_2_hex", ""))) if data.get("padding_0x72_2_hex") else b"\x00\x00"
    if len(pad) != 2:
        raise ValueError("player padding_0x72_2_hex must be 2 bytes (4 hex chars)")
    buf[base + 0x72 : base + 0x74] = pad


def decode_save(input_path: Path) -> Dict[str, Any]:
    encrypted = input_path.read_bytes()
    if len(encrypted) != SAVE_SIZE:
        raise ValueError(f"{input_path}: invalid save size {len(encrypted)}, expected {SAVE_SIZE}")

    clear_data = crypt(encrypted)

    stored_checksum = read_u32_le(clear_data, 0x000)
    calculated_checksum = compute_checksum(clear_data)

    created_tdatetime = read_f64_le(clear_data, 0x218)
    saved_tdatetime = read_f64_le(clear_data, 0x220)

    result = {
        "meta": {
            "source_file": str(input_path),
            "size": len(encrypted),
        },
        "header": {
            "game_mode": read_u32_le(clear_data, 0x004),
            "player1_name": parse_short_string(clear_data, 0x008, 256),
            "player2_name": parse_short_string(clear_data, 0x108, 256),
            "extra_string": parse_short_string(clear_data, 0x208, 16),
            "created_iso": tdatetime_to_iso(created_tdatetime),
            "saved_iso": tdatetime_to_iso(saved_tdatetime),
            "start_difficulty": read_u16_le(clear_data, 0x228),
            "difficulty": read_u16_le(clear_data, 0x22A),
            "max_credits": read_u16_le(clear_data, 0x22C),
            "credit": read_u16_le(clear_data, 0x22E),
            "current_stage": read_u16_le(clear_data, 0x230),
            "counter": read_u16_le(clear_data, 0x232),
            "reserved_0x234_64_hex": clear_data[0x234:0x274].hex(),
        },
        "players": {
            "player1": decode_player(clear_data, 0x274),
            "player2": decode_player(clear_data, 0x2E8),
        },
    }
    return result


def encode_save(data: Dict[str, Any]) -> bytes:
    header = data.get("header", {})
    players = data.get("players", {})

    clear_data = bytearray(b"\x00" * SAVE_SIZE)

    write_u32_le(clear_data, 0x000, 0)
    write_u32_le(clear_data, 0x004, int(header.get("game_mode", 0)))
    write_short_string(clear_data, 0x008, 256, str(header.get("player1_name", "")))
    write_short_string(clear_data, 0x108, 256, str(header.get("player2_name", "")))
    write_short_string(clear_data, 0x208, 16, str(header.get("extra_string", "")))

    if "created_tdatetime" in header:
        created_tdatetime = float(header["created_tdatetime"])
    elif "created_iso" in header:
        created_tdatetime = iso_to_tdatetime(str(header["created_iso"]))
    else:
        created_tdatetime = 0.0

    if "saved_tdatetime" in header:
        saved_tdatetime = float(header["saved_tdatetime"])
    elif "saved_iso" in header:
        saved_tdatetime = iso_to_tdatetime(str(header["saved_iso"]))
    else:
        saved_tdatetime = 0.0

    write_f64_le(clear_data, 0x218, created_tdatetime)
    write_f64_le(clear_data, 0x220, saved_tdatetime)
    write_u16_le(clear_data, 0x228, int(header.get("start_difficulty", 0)))
    write_u16_le(clear_data, 0x22A, int(header.get("difficulty", 0)))
    write_u16_le(clear_data, 0x22C, int(header.get("max_credits", 0)))
    write_u16_le(clear_data, 0x22E, int(header.get("credit", 0)))
    write_u16_le(clear_data, 0x230, int(header.get("current_stage", 0)))
    write_u16_le(clear_data, 0x232, int(header.get("counter", 0)))

    reserved = bytes.fromhex(str(header.get("reserved_0x234_64_hex", ""))) if header.get("reserved_0x234_64_hex") else b"\x00" * 64
    if len(reserved) != 64:
        raise ValueError("header reserved_0x234_64_hex must be 64 bytes (128 hex chars)")
    clear_data[0x234:0x274] = reserved

    encode_player(clear_data, 0x274, players.get("player1", {}))
    encode_player(clear_data, 0x2E8, players.get("player2", {}))

    checksum = compute_checksum(bytes(clear_data))
    write_u32_le(clear_data, 0x000, checksum)

    return crypt(bytes(clear_data))


def default_decode_output(input_path: Path) -> Path:
    return input_path.with_suffix(".json")


def default_encode_output(input_path: Path) -> Path:
    if input_path.suffix.lower() == ".json":
        return input_path.with_suffix(".sav")
    return input_path.with_name(input_path.name + ".sav")


def cmd_decode(input_file: Path, output_file: Path | None) -> None:
    decoded = decode_save(input_file)
    target = output_file if output_file is not None else default_decode_output(input_file)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(decoded, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Decoded: {input_file} -> {target}")


def cmd_decodeall(input_folder: Path, output_folder: Path | None) -> None:
    folder_out = output_folder if output_folder is not None else input_folder
    folder_out.mkdir(parents=True, exist_ok=True)
    count = 0
    for sav_file in sorted(input_folder.glob("*.sav")):
        target = folder_out / (sav_file.stem + ".json")
        cmd_decode(sav_file, target)
        count += 1
    print(f"decodeall done: {count} file(s)")


def cmd_encode(input_file: Path, output_file: Path | None) -> None:
    data = json.loads(input_file.read_text(encoding="utf-8"))
    encoded = encode_save(data)
    target = output_file if output_file is not None else default_encode_output(input_file)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(encoded)
    print(f"Encoded: {input_file} -> {target}")


def cmd_encodeall(input_folder: Path, output_folder: Path | None) -> None:
    folder_out = output_folder if output_folder is not None else input_folder
    folder_out.mkdir(parents=True, exist_ok=True)
    count = 0
    for json_file in sorted(input_folder.glob("*.json")):
        target = folder_out / (json_file.stem + ".sav")
        cmd_encode(json_file, target)
        count += 1
    print(f"encodeall done: {count} file(s)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Tank save decode/encode tool")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_decode = sub.add_parser("decode", help="decode one .sav to .json")
    p_decode.add_argument("input", type=Path, help="input .sav path")
    p_decode.add_argument("output", nargs="?", type=Path, help="output .json path")

    p_decodeall = sub.add_parser("decodeall", help="decode all .sav in folder")
    p_decodeall.add_argument("input", type=Path, help="input folder")
    p_decodeall.add_argument("output", nargs="?", type=Path, help="output folder")

    p_encode = sub.add_parser("encode", help="encode one .json to .sav")
    p_encode.add_argument("input", type=Path, help="input .json path")
    p_encode.add_argument("output", nargs="?", type=Path, help="output .sav path")

    p_encodeall = sub.add_parser("encodeall", help="encode all .json in folder")
    p_encodeall.add_argument("input", type=Path, help="input folder")
    p_encodeall.add_argument("output", nargs="?", type=Path, help="output folder")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if args.cmd == "decode":
        cmd_decode(args.input, args.output)
    elif args.cmd == "decodeall":
        cmd_decodeall(args.input, args.output)
    elif args.cmd == "encode":
        cmd_encode(args.input, args.output)
    elif args.cmd == "encodeall":
        cmd_encodeall(args.input, args.output)
    else:
        parser.error(f"Unknown command: {args.cmd}")


if __name__ == "__main__":
    main()
