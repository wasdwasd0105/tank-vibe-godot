#!/usr/bin/env python3
"""Builds the game's three bitmap fonts from open-licensed pixel fonts, painted
like the Tank.exe fonts they replace (whose own glyphs aren't ours to ship).

Each glyph of Jersey 10 / Jersey 15 (SIL Open Font License 1.1, see
assets/ui/fonts/src/) is filled on the font's own design-pixel grid, scaled by
a whole number, and coloured row by row with the old font's colours:

  gold_font   Jersey 10 x2, 36 px lines: the metallic gold face with its bronze
              bevel (titles, menus, the stage screens, the pickup words)
  white_font  Jersey 15 x1, 24 px lines: steel over khaki, a dark drop shadow
              (the stage caption)
  tiny_font   Jersey 10 x1, 16 px lines: blue into green under a navy edge
              (the results panels, the small pickup words)

The fonts are proportional; each glyph advances by its own width.

Chinese, for the menus in Chinese, comes from Fusion Pixel Font's 12 px zh_hans
cut (SIL Open Font License 1.1, see assets/ui/fonts/licenses/), a BDF bitmap
font, so its pixels are taken as drawn. Only the characters the project uses are
baked: every CJK character in localization/*.csv and in scripts/.
  gold_font   gets them x2 in its gold, with a 1 px bevel (the menus' big text)
  cjk_font    has only them, x1 in plain white: the fallback of the default
              font, which the rest of the menus' text uses, so the labels' own
              colours tint them. Its size is 12, its pixel size, and it scales
              by whole steps only (its import's scaling_mode=1), so the menus'
              18-29 px text gets them at exactly 2x

Run from the project root after changing the translations:
  python3 tools/make_fonts.py
"""
import gzip
import math
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "ui", "fonts", "src")
OUT = os.path.join(ROOT, "assets", "ui", "fonts")
FIRST, LAST = 32, 126  # printable ASCII, as the old fonts had
CJK_SRC = "fusion-pixel-12px-proportional-zh_hans.bdf.gz"
## Where the text lives whose CJK characters get baked.
TEXT_DIRS = ["localization", "scripts"]


# --- colours, per pixel row, measured from the old fonts ------------------------

def _hexes(text):
    return [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in text.split()]

# The gold face runs pale orange, amber, bright yellow, then down to bronze;
# the bevel on its right and lower edges is a dark bronze.
GOLD_FACE = _hexes("fecc81 fec061 fdb845 f0b236 e8b231 f4bf2f f4c633 f5d134 fbde3d fae236 "
                   "f8e934 faf036 faf630 f7f42e f7f438 f8f535 faf734 f9f033 fae936 fce239 "
                   "fad835 f4ca2b fbca3a e4ae26 bb8f2d a67e32 927232")
GOLD_EDGE = _hexes("d79029 a6752e 9f6f32 926a32 987331 977632 957832 987f31 988231 968632 "
                   "988c32 948c32 989432 989531 949332 959532 979732 989232 978d32 958931 "
                   "99852f 9f842d 9c7c2a 93732a 967432 926e32")
# Steel white over khaki (a chrome sky over ground), a dark grey shadow.
WHITE_FACE = _hexes("c8e1f2 c3dced bcd2e1 c4dbea c8dbe8 c9dae7 d4dfe7 dfe6ea e5e9ea dadddd "
                    "ab9a57 b3a35e c1ae5f ceb85c c6b15f bba860 b9ac70 8e865f")
WHITE_SHADOW = (0x34, 0x34, 0x34)
# Blue through cyan into green, a navy edge along the top.
TINY_FACE = _hexes("0b48f2 106cf3 108cf4 0aaffa 07d5fd 02f5fd 01fff6 00ffdd 00ffbd 00ff9a "
                   "00ff7d 00ff5b 12bf35")
TINY_EDGE = (0x17, 0x29, 0x92)

FONTS = [
    # name, source, scale, line height, baseline row, face colours, effect, and
    # whether the project's CJK characters go in too
    dict(name="gold_font", face="BattleTank Gold", src="Jersey10-Regular.ttf", scale=2,
         height=36, base=25, colours=GOLD_FACE, effect="bevel", edge=GOLD_EDGE, cjk=True),
    dict(name="white_font", face="BattleTank White", src="Jersey15-Regular.ttf", scale=1,
         height=24, base=18, colours=WHITE_FACE, effect="shadow", edge=[WHITE_SHADOW]),
    dict(name="tiny_font", face="BattleTank Tiny", src="Jersey10-Regular.ttf", scale=1,
         height=16, base=13, colours=TINY_FACE, effect="top_edge", edge=[TINY_EDGE]),
    dict(name="cjk_font", face="BattleTank CJK", src=None, scale=1, size=12,
         height=14, base=12, colours=[(255, 255, 255)], effect="none", edge=[], cjk=True),
]


# --- TrueType pixel fonts ---------------------------------------------------------

class PixelFont:
    """A TrueType pixel font read straight from its outlines. Pixel fonts draw
    every glyph on a grid, so filling the grid cells whose centres lie inside
    the outline gives the designer's pixels exactly, at any whole scale."""

    def __init__(self, path):
        self.data = data = open(path, "rb").read()
        count = struct.unpack(">H", data[4:6])[0]
        self.tables = {}
        for i in range(count):
            tag, _, offset, length = struct.unpack(">4sIII", data[12 + 16 * i: 28 + 16 * i])
            self.tables[tag.decode("latin-1")] = offset
        head = self.tables["head"]
        self.units_per_em = struct.unpack(">H", data[head + 18: head + 20])[0]
        long_offsets = struct.unpack(">h", data[head + 50: head + 52])[0] == 1
        glyphs = struct.unpack(">H", data[self.tables["maxp"] + 4: self.tables["maxp"] + 6])[0]
        loca = self.tables["loca"]
        if long_offsets:
            self.offsets = [struct.unpack(">I", data[loca + 4 * i: loca + 4 * i + 4])[0] for i in range(glyphs + 1)]
        else:
            self.offsets = [struct.unpack(">H", data[loca + 2 * i: loca + 2 * i + 2])[0] * 2 for i in range(glyphs + 1)]
        hhea = self.tables["hhea"]
        metrics = struct.unpack(">H", data[hhea + 34: hhea + 36])[0]
        hmtx = self.tables["hmtx"]
        self.advances = [struct.unpack(">H", data[hmtx + 4 * i: hmtx + 4 * i + 2])[0] for i in range(metrics)]
        self.cmap = self._read_cmap()
        self.grid = self._find_grid()

    def _read_cmap(self):
        data, base = self.data, self.tables["cmap"]
        for i in range(struct.unpack(">H", data[base + 2: base + 4])[0]):
            platform, _, offset = struct.unpack(">HHI", data[base + 4 + 8 * i: base + 12 + 8 * i])
            sub = base + offset
            if struct.unpack(">H", data[sub: sub + 2])[0] != 4 or platform not in (0, 3):
                continue
            seg2 = struct.unpack(">H", data[sub + 6: sub + 8])[0]
            segs = seg2 // 2
            ends = struct.unpack(">%dH" % segs, data[sub + 14: sub + 14 + seg2])
            starts = struct.unpack(">%dH" % segs, data[sub + 16 + seg2: sub + 16 + 2 * seg2])
            deltas = struct.unpack(">%dh" % segs, data[sub + 16 + 2 * seg2: sub + 16 + 3 * seg2])
            range_base = sub + 16 + 3 * seg2
            ranges = struct.unpack(">%dH" % segs, data[range_base: range_base + seg2])
            chars = {}
            for s in range(segs):
                for code in range(max(starts[s], FIRST), min(ends[s], LAST) + 1):
                    if ranges[s] == 0:
                        glyph = (code + deltas[s]) & 0xFFFF
                    else:
                        at = range_base + 2 * s + ranges[s] + 2 * (code - starts[s])
                        glyph = struct.unpack(">H", data[at: at + 2])[0]
                        glyph = (glyph + deltas[s]) & 0xFFFF if glyph else 0
                    if glyph:
                        chars[code] = glyph
            return chars
        raise ValueError("no Unicode cmap")

    def contours(self, glyph):
        """The glyph's outlines in font units, composites flattened."""
        data = self.data
        start, end = self.offsets[glyph], self.offsets[glyph + 1]
        if end <= start:
            return []
        p = self.tables["glyf"] + start
        count = struct.unpack(">h", data[p: p + 2])[0]
        if count < 0:  # a composite: its parts, each moved
            outlines, q = [], p + 10
            while True:
                flags, part = struct.unpack(">HH", data[q: q + 4])
                q += 4
                if flags & 1:
                    dx, dy = struct.unpack(">hh", data[q: q + 4])
                    q += 4
                else:
                    dx, dy = struct.unpack(">bb", data[q: q + 2])
                    q += 2
                q += 2 if flags & 8 else 4 if flags & 0x40 else 8 if flags & 0x80 else 0
                outlines += [[(x + dx, y + dy) for x, y in c] for c in self.contours(part)]
                if not flags & 0x20:
                    return outlines
        p += 10
        ends = struct.unpack(">%dH" % count, data[p: p + 2 * count])
        p += 2 * count
        points = ends[-1] + 1 if count else 0
        p += 2 + struct.unpack(">H", data[p: p + 2])[0]  # skip the hinting
        flags = []
        while len(flags) < points:
            flag = data[p]
            p += 1
            flags.append(flag)
            if flag & 8:
                flags += [flag] * data[p]
                p += 1
        coords = []
        for short, same in ((2, 16), (4, 32)):
            value, axis = 0, []
            for flag in flags:
                if flag & short:
                    value += data[p] if flag & same else -data[p]
                    p += 1
                elif not flag & same:
                    value += struct.unpack(">h", data[p: p + 2])[0]
                    p += 2
                axis.append(value)
            coords.append(axis)
        outlines, first = [], 0
        for last in ends:
            outlines.append(list(zip(coords[0][first: last + 1], coords[1][first: last + 1])))
            first = last + 1
        return outlines

    def _find_grid(self):
        """The design pixel in font units: the step every letter and digit sits on."""
        grid = 0
        for code in list(range(48, 58)) + list(range(65, 91)) + list(range(97, 123)):
            for contour in self.contours(self.cmap[code]):
                for x, y in contour:
                    grid = math.gcd(math.gcd(grid, abs(x)), abs(y))
        return grid

    def advance(self, code):
        glyph = self.cmap[code]
        return self.advances[min(glyph, len(self.advances) - 1)] // self.grid

    def pixels(self, code):
        """The glyph's design pixels: (rows top-down of 0/1, left, top), with left
        from the pen position and top above the baseline, in design pixels."""
        outlines = [[(x / self.grid, y / self.grid) for x, y in c] for c in self.contours(self.cmap[code])]
        if not outlines:
            return [], 0, 0
        xs = [x for c in outlines for x, _ in c]
        ys = [y for c in outlines for _, y in c]
        left, right = math.floor(min(xs)), math.ceil(max(xs))
        bottom, top = math.floor(min(ys)), math.ceil(max(ys))
        rows = []
        for py in range(top - 1, bottom - 1, -1):
            row = []
            for px in range(left, right):
                cx, cy = px + 0.5, py + 0.5
                winding = 0
                for contour in outlines:
                    for i, (ax, ay) in enumerate(contour):
                        bx, by = contour[(i + 1) % len(contour)]
                        if (ay <= cy < by or by <= cy < ay) and ax + (cy - ay) * (bx - ax) / (by - ay) > cx:
                            winding += 1 if by > ay else -1
                row.append(1 if winding else 0)
            rows.append(row)
        return rows, left, top


class BdfFont:
    """A BDF bitmap font, gzipped or not: each glyph's pixels as drawn, read
    through the same calls as PixelFont."""

    def __init__(self, path, wanted):
        self.glyphs = {}
        opener = gzip.open if path.endswith(".gz") else open
        code, rows = None, None
        with opener(path, "rt", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if not parts:
                    continue
                key = parts[0]
                if rows is not None and key != "ENDCHAR":
                    rows.append(parts[0])
                elif key == "ENCODING":
                    code = int(parts[1])
                elif key == "DWIDTH":
                    advance = int(parts[1])
                elif key == "BBX":
                    box = tuple(int(v) for v in parts[1:5])
                elif key == "BITMAP" and code in wanted:
                    rows = []
                elif key == "ENDCHAR":
                    if rows is not None:
                        self.glyphs[code] = (advance, box, rows)
                    code, rows = None, None

    def has(self, code):
        return code in self.glyphs

    def advance(self, code):
        return self.glyphs[code][0]

    def pixels(self, code):
        """(rows top-down of 0/1, left from the pen, top above the baseline)."""
        _, (width, height, left, bottom), hex_rows = self.glyphs[code]
        if width == 0 or height == 0:
            return [], 0, 0
        rows = []
        for text in hex_rows:
            bits, value = len(text) * 4, int(text, 16)
            rows.append([(value >> (bits - 1 - x)) & 1 for x in range(width)])
        return rows, left, bottom + height


def is_cjk(code):
    """CJK punctuation, kana, ideographs and fullwidth forms."""
    return 0x2E80 <= code <= 0x9FFF or 0xF900 <= code <= 0xFAFF or 0xFE30 <= code <= 0xFE4F \
        or 0xFF00 <= code <= 0xFFEF


def cjk_codes():
    """Every CJK character in the project's translations and scripts."""
    found = set()
    for folder in TEXT_DIRS:
        for directory, _, files in os.walk(os.path.join(ROOT, folder)):
            for name in files:
                if name.endswith((".csv", ".gd")):
                    with open(os.path.join(directory, name), encoding="utf-8") as f:
                        found.update(ord(c) for c in f.read() if is_cjk(ord(c)))
    return sorted(found)


# --- painting -----------------------------------------------------------------------

def _colour_at(colours, row, top, height):
    """The colour for line row [row] of a face spanning rows top..top+height:
    the old font's colours stretched over it, the last one below it."""
    t = (row - top + 0.5) / height
    index = min(max(int(t * len(colours)), 0), len(colours) - 1)
    return colours[index]


def paint(spec, font, code, cap_top, cap_height):
    """(RGBA rows, x offset from the pen, y offset from the line top, advance)."""
    k = spec["scale"]
    design, left, top = font.pixels(code)
    advance = font.advance(code) * k
    if not design:
        return [], 0, 0, advance + (2 if spec["effect"] == "bevel" else 0)
    ink = [[v for v in row for _ in range(k)] for row in design for _ in range(k)]
    width, height = len(ink[0]), len(ink)
    line_top = spec["base"] - top * k  # the ink's top row in line coordinates
    # Room for the effect around the ink.
    grow_left, grow_right, grow_up, grow_down = {
        "bevel": (0, 2, 0, 2), "bevel_thin": (0, 1, 0, 1), "shadow": (0, 1, 0, 1),
        "top_edge": (0, 0, 1, 0), "none": (0, 0, 0, 0)}[spec["effect"]]
    w, h = width + grow_left + grow_right, height + grow_up + grow_down
    face = [[False] * w for _ in range(h)]
    for y in range(height):
        for x in range(width):
            face[y + grow_up][x + grow_left] = bool(ink[y][x])
    image = [[(0, 0, 0, 0)] * w for _ in range(h)]
    first_row = line_top - grow_up  # line row of image row 0

    def set_edge(x, y, colour):
        if 0 <= x < w and 0 <= y < h and not face[y][x] and image[y][x][3] == 0:
            image[y][x] = colour + (255,)

    for y in range(h):
        for x in range(w):
            if not face[y][x]:
                continue
            row = first_row + y
            image[y][x] = _colour_at(spec["colours"], row, cap_top, cap_height) + (255,)
            if spec["effect"] == "bevel":  # pushed out 2 px down and to the right
                edge = _colour_at(spec["edge"], row, cap_top, cap_height)
                set_edge(x + 1, y + 1, edge)
                set_edge(x + 2, y + 2, edge)
            elif spec["effect"] == "bevel_thin":  # 1 px: ideographs' gaps are only 2
                set_edge(x + 1, y + 1, _colour_at(spec["edge"], row, cap_top, cap_height))
            elif spec["effect"] == "shadow":
                set_edge(x + 1, y + 1, spec["edge"][0])
            elif spec["effect"] == "top_edge":
                set_edge(x, y - 1, spec["edge"][0])
    # The face goes over the edge pixels it overlaps (set_edge never covers face).
    return image, left * k - grow_left, first_row, advance + grow_right


def build(spec, cjk=None):
    k = spec["scale"]
    glyphs = {}
    cap_height = 0
    if spec["src"]:
        font = PixelFont(os.path.join(SRC, spec["src"]))
        _, _, cap_top_design = font.pixels(ord("H"))
        cap_height = len(font.pixels(ord("H"))[0]) * k
        cap_top = spec["base"] - cap_top_design * k
        glyphs = {code: paint(spec, font, code, cap_top, cap_height) for code in range(FIRST, LAST + 1)}
        # Tabular digits: all as wide as the widest, each centred in that width, so
        # numbers counting up don't shuffle.
        digits = range(ord("0"), ord("9") + 1)
        digit_advance = max(glyphs[c][3] for c in digits)
        for c in digits:
            image, xoff, yoff, advance = glyphs[c]
            glyphs[c] = (image, xoff + (digit_advance - advance) // 2, yoff, digit_advance)
    if spec.get("cjk") and cjk:
        # The colours run over an ideograph's full box, as over the Latin capitals.
        box, box_top = cjk.pixels(ord("中"))[0], cjk.pixels(ord("中"))[2]
        cjk_top, cjk_height = spec["base"] - box_top * k, len(box) * k
        # A 2 px bevel would fill the 2 px gaps between an ideograph's strokes.
        cjk_spec = dict(spec, effect="bevel_thin") if spec["effect"] == "bevel" else spec
        for code in cjk.glyphs:
            glyphs[code] = paint(cjk_spec, cjk, code, cjk_top, cjk_height)
    # Shelf-pack the glyph images into one page, a pixel apart.
    page_w, x, y, shelf = (512 if len(glyphs) > 200 else 256), 1, 1, 0
    places = {}
    for code in sorted(glyphs, key=lambda c: -len(glyphs[c][0])):
        image = glyphs[code][0]
        gw, gh = (len(image[0]), len(image)) if image else (0, 0)
        if x + gw + 1 > page_w:
            x, y, shelf = 1, y + shelf + 1, 0
        places[code] = (x, y, gw, gh)
        x += gw + 1
        shelf = max(shelf, gh)
    page_h = 1
    while page_h < y + shelf + 1:
        page_h *= 2
    page = [[(0, 0, 0, 0)] * page_w for _ in range(page_h)]
    for code, (px, py, gw, gh) in places.items():
        image = glyphs[code][0]
        for yy in range(gh):
            page[py + yy][px: px + gw] = image[yy]
    write_png(os.path.join(OUT, spec["name"] + ".png"), page)
    lines = [
        'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 '
        'padding=0,0,0,0 spacing=1,1 outline=0' % (spec["face"], spec.get("size", spec["height"])),
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 "
        "redChnl=4 greenChnl=4 blueChnl=4" % (spec["height"], spec["base"], page_w, page_h),
        'page id=0 file="%s.png"' % spec["name"],
        "chars count=%d" % len(glyphs),
    ]
    for code in sorted(glyphs):
        _, xoff, yoff, advance = glyphs[code]
        px, py, gw, gh = places[code]
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                     % (code, px, py, gw, gh, xoff, yoff, advance))
    with open(os.path.join(OUT, spec["name"] + ".fnt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    widths = [glyphs[c][3] for c in range(65, 91) if c in glyphs] or [0]
    cjk_count = sum(1 for c in glyphs if is_cjk(c))
    print("%s: %s x%d, %d px lines, capitals %d px, advances %d..%d, %d CJK, page %dx%d" % (
        spec["name"], spec["src"], k, spec["height"], cap_height, min(widths), max(widths), cjk_count,
        page_w, page_h))


def write_png(path, rows):
    height, width = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(v for pixel in row for v in pixel) for row in rows)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        SRC, OUT = sys.argv[1], sys.argv[2]  # (for trying fonts out elsewhere)
    wanted = cjk_codes()
    cjk_font = BdfFont(os.path.join(SRC, CJK_SRC), set(wanted) | {ord("中")})  # 中 sets the colour box
    missing = [chr(c) for c in wanted if not cjk_font.has(c)]
    if missing:
        print("not in %s, left out: %s" % (CJK_SRC, "".join(missing)))
    for spec in FONTS:
        build(spec, cjk_font)
