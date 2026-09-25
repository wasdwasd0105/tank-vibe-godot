#!/usr/bin/env python3
"""Draws the game's own stage pictures, in place of the original's: the ten
stage intros (stage_intro_0..9, picked by the SI00..SI09 name each stage has in
Stage.dat), the stage-won backdrop (stage_win) and the stage-lost one
(stage_lose). 320x240 pixel art in dithered colour bands; the game shows them
at 4x over the playfield.

Run from the project root:  python3 tools/make_screens.py [--only NAME]
"""
import math
import os
import random
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_fonts  # noqa: E402  (its pixel-font reader, for the blueprint's labels)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "screens")
W, H = 320, 240

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def threshold(x, y):
    return (BAYER[y & 3][x & 3] + 0.5) / 16.0


class Canvas:
    def __init__(self, fill=(0, 0, 0)):
        self.px = [[fill] * W for _ in range(H)]

    # --- the basics -------------------------------------------------------------

    def put(self, x, y, colour):
        if 0 <= x < W and 0 <= y < H:
            self.px[y][x] = colour

    def dither(self, x, y, colour, alpha):
        """[colour] over the pixel with [alpha], as an ordered dither."""
        if 0 <= x < W and 0 <= y < H and alpha > threshold(x, y):
            self.px[y][x] = colour

    def gradient(self, y0, y1, stops, x0=0, x1=W):
        """Rows y0..y1 in bands through [stops] (colours, evenly spaced),
        dithered from one to the next."""
        n = len(stops) - 1
        for y in range(max(y0, 0), min(y1, H)):
            t = (y - y0) / max(y1 - y0 - 1, 1) * n
            i = min(int(t), n - 1)
            u = t - i
            for x in range(x0, x1):
                self.px[y][x] = stops[i + 1] if u > threshold(x, y) else stops[i]

    def rect(self, x0, y0, x1, y1, colour, alpha=1.0):
        for y in range(max(int(y0), 0), min(int(y1), H)):
            for x in range(max(int(x0), 0), min(int(x1), W)):
                if alpha >= 1.0:
                    self.px[y][x] = colour
                else:
                    self.dither(x, y, colour, alpha)

    def circle(self, cx, cy, r, colour, alpha=1.0):
        for y in range(max(int(cy - r - 1), 0), min(int(cy + r + 2), H)):
            for x in range(max(int(cx - r - 1), 0), min(int(cx + r + 2), W)):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    if alpha >= 1.0:
                        self.px[y][x] = colour
                    else:
                        self.dither(x, y, colour, alpha)

    def glow(self, cx, cy, r, colour, strength=1.0):
        """A soft round glow: [colour] dithered in, fading out to radius [r]."""
        for y in range(max(int(cy - r), 0), min(int(cy + r + 1), H)):
            for x in range(max(int(cx - r), 0), min(int(cx + r + 1), W)):
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / r
                if d < 1.0:
                    self.dither(x, y, colour, strength * (1.0 - d) ** 1.6)

    def polygon(self, points, colour, alpha=1.0):
        ys = [p[1] for p in points]
        for y in range(max(int(min(ys)), 0), min(int(math.ceil(max(ys))) + 1, H)):
            cy = y + 0.5
            xs = []
            for i in range(len(points)):
                ax, ay = points[i]
                bx, by = points[(i + 1) % len(points)]
                if (ay <= cy < by) or (by <= cy < ay):
                    xs.append(ax + (cy - ay) * (bx - ax) / (by - ay))
            xs.sort()
            for a, b in zip(xs[0::2], xs[1::2]):
                for x in range(max(int(math.ceil(a - 0.5)), 0), min(int(math.ceil(b - 0.5)), W)):
                    if alpha >= 1.0:
                        self.px[y][x] = colour
                    else:
                        self.dither(x, y, colour, alpha)

    def line(self, x0, y0, x1, y1, colour, alpha=1.0):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t))
            if alpha >= 1.0:
                self.put(x, y, colour)
            else:
                self.dither(x, y, colour, alpha)

    def ridge(self, heights, colour, bottom=H, top_colour=None):
        """Fills below a skyline ([heights][x] is its top row at x), with an
        optional one-pixel edge along the top."""
        for x in range(W):
            top = int(heights[x])
            for y in range(max(top, 0), min(bottom, H)):
                self.px[y][x] = colour
            if top_colour and 0 <= top < H:
                self.px[top][x] = top_colour

    def save(self, path):
        raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in self.px)

        def chunk(tag, body):
            return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
                    + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# --- scenery ------------------------------------------------------------------------

def skyline(rng, base, amplitude, roughness=1.0):
    """A hill or mountain line: a few sine waves and some noise, [base] its mean."""
    waves = [(rng.uniform(0.004, 0.012) * roughness, rng.uniform(0, 6.3), amplitude * rng.uniform(0.5, 1.0)),
             (rng.uniform(0.015, 0.04) * roughness, rng.uniform(0, 6.3), amplitude * rng.uniform(0.2, 0.45)),
             (rng.uniform(0.06, 0.12) * roughness, rng.uniform(0, 6.3), amplitude * rng.uniform(0.05, 0.15))]
    return [base - sum(a * math.sin(f * x + p) for f, p, a in waves) for x in range(W)]


def stars(c, rng, count, colours, y_max):
    for _ in range(count):
        x, y = rng.randrange(W), rng.randrange(int(y_max))
        c.put(x, y, rng.choice(colours))
    for _ in range(max(count // 25, 1)):  # a few twinkle crosses
        x, y = rng.randrange(8, W - 8), rng.randrange(4, int(y_max * 0.8))
        col = colours[-1]
        c.put(x, y, col)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c.put(x + dx, y + dy, colours[0])


def moon(c, cx, cy, r, light, sky, crescent=True):
    """A moon with a soft halo: a crescent (its dark side showing the sky) or full."""
    c.glow(cx, cy, r * 3.2, mix(sky, light, 0.35), 0.7)
    dark_x, dark_y, dark_r = cx + r * 0.5, cy - r * 0.25, r * 0.92
    for y in range(int(cy - r - 1), int(cy + r + 2)):
        for x in range(int(cx - r - 1), int(cx + r + 2)):
            inside = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r
            shaded = crescent and (x + 0.5 - dark_x) ** 2 + (y + 0.5 - dark_y) ** 2 <= dark_r * dark_r
            if inside and not shaded:
                c.put(x, y, light)
    if not crescent:
        for dx, dy, cr in ((-0.35, 0.3, 0.2), (0.25, -0.35, 0.16), (0.3, 0.35, 0.12)):
            c.circle(cx + r * dx, cy + r * dy, r * cr, mix(light, sky, 0.3))


def sun(c, cx, cy, r, core, rim, sky, glow_r=3.0):
    c.glow(cx, cy, r * glow_r, rim, 0.85)
    c.circle(cx, cy, r + 1, rim)
    c.circle(cx, cy, r, core)


def clouds(c, rng, count, y_range, colour, lit=None, lit_side=1, size=(18, 40)):
    """Flat-bottomed pixel clouds; [lit] edges them on the side the light comes
    from (lit_side +1 below, -1 above)."""
    for _ in range(count):
        cx, cy = rng.uniform(-20, W + 20), rng.uniform(*y_range)
        length = rng.uniform(*size)
        blobs = [(cx + (k - 2) * length / 5 + rng.uniform(-3, 3), cy - rng.uniform(0, length / 8),
                  length / 6 + rng.uniform(1, 4)) for k in range(5)]
        mask = set()
        for bx, by, br in blobs:
            for y in range(int(by - br), int(cy) + 1):
                for x in range(int(bx - br), int(bx + br) + 1):
                    if (x + 0.5 - bx) ** 2 + (y + 0.5 - by) ** 2 <= br * br and 0 <= x < W and 0 <= y < H:
                        mask.add((x, y))
        for x, y in mask:
            c.px[y][x] = colour
        if lit:
            for x, y in mask:
                if (x, y + lit_side) not in mask:
                    c.put(x, y, lit)


def smoke(c, rng, x, y, height, colour, alpha=0.6, lean=0.25):
    for k in range(int(height / 4)):
        t = k / max(height / 4 - 1, 1)
        c.circle(x + lean * k * 4 + rng.uniform(-2, 2), y - k * 4, 3 + t * 9, colour, alpha * (1.0 - 0.6 * t))


def searchlight(c, x, y, angle, length, spread, colour, alpha=0.32):
    """A beam from (x, y) up at [angle] degrees from vertical, fading as it goes."""
    a = math.radians(angle)
    ux, uy = math.sin(a), -math.cos(a)
    for py in range(max(int(y - length), 0), min(int(y) + 1, H)):
        for px in range(W):
            dx, dy = px + 0.5 - x, py + 0.5 - y
            along = dx * ux + dy * uy
            if along <= 0 or along >= length:
                continue
            across = abs(dx * uy - dy * ux)
            if across <= spread * along / length:
                c.dither(px, py, colour, alpha * (1.0 - along / length) ** 0.8)


def tank(c, x, ground, length, facing, colour, rim=None, wheel=None, light_side=0, antenna=True):
    """A tank seen from the side, standing on row [ground], [length] px long,
    facing +1 right or -1 left, filled with [colour]; [rim] lights its top edge
    (and the [light_side] edge: -1 left, +1 right)."""
    L, f = length, facing
    mask = set()

    def poly(points):
        pts = [(x + f * px * L, ground - py * L) for px, py in points]
        before = {k for k in mask}
        _fill_mask(pts, mask)
        return mask - before

    # tracks, hull, turret, barrel, hatch, antenna (the tank's own proportions)
    poly([(-0.5, 0.03), (-0.44, 0.0), (0.44, 0.0), (0.5, 0.03), (0.52, 0.12), (0.47, 0.17), (-0.47, 0.17), (-0.52, 0.12)])
    poly([(-0.5, 0.16), (0.36, 0.16), (0.52, 0.2), (0.5, 0.25), (0.3, 0.28), (-0.46, 0.28), (-0.5, 0.24)])
    poly([(-0.26, 0.27), (0.14, 0.27), (0.24, 0.31), (0.2, 0.38), (-0.18, 0.39), (-0.28, 0.35)])
    poly([(0.2, 0.325), (0.78, 0.325), (0.78, 0.35), (0.2, 0.355)])
    poly([(0.72, 0.318), (0.8, 0.318), (0.8, 0.362), (0.72, 0.362)])
    poly([(-0.14, 0.38), (-0.02, 0.38), (-0.03, 0.42), (-0.12, 0.42)])
    if antenna:
        for i in range(int(0.3 * L)):
            mask.add((int(round(x - f * 0.22 * L)), int(round(ground - 0.38 * L - i))))
    if colour is not None:
        for (px, py) in mask:
            c.put(px, py, colour)
    if wheel:
        for k in range(6):
            wx = x + (-0.38 + k * 0.152) * L
            c.circle(wx, ground - 0.085 * L, 0.055 * L, wheel)
            c.circle(wx, ground - 0.085 * L, 0.02 * L, colour)
    if rim:
        for (px, py) in mask:
            if (px, py - 1) not in mask or (light_side and (px + light_side, py) not in mask):
                c.put(px, py, rim)
    return mask


def _fill_mask(points, mask):
    ys = [p[1] for p in points]
    for y in range(int(min(ys)), int(math.ceil(max(ys))) + 1):
        cy = y + 0.5
        xs = []
        for i in range(len(points)):
            ax, ay = points[i]
            bx, by = points[(i + 1) % len(points)]
            if (ay <= cy < by) or (by <= cy < ay):
                xs.append(ax + (cy - ay) * (bx - ax) / (by - ay))
        xs.sort()
        for a, b in zip(xs[0::2], xs[1::2]):
            for xx in range(int(math.ceil(a - 0.5)), int(math.ceil(b - 0.5))):
                if 0 <= xx < W and 0 <= y < H:
                    mask.add((xx, y))


def wire(c, rng, y, colour, posts=7):
    """Barbed wire along the foreground: posts and sagging strands."""
    xs = [int(i * W / (posts - 1)) + rng.randint(-6, 6) for i in range(posts)]
    for px in xs:
        c.rect(px, y - 14, px + 2, y + 2, colour)
    for strand in (y - 11, y - 5):
        for a, b in zip(xs, xs[1:]):
            for x in range(a, b + 1):
                t = (x - a) / max(b - a, 1)
                sy = strand + int(3 * math.sin(math.pi * t))
                c.put(x, sy, colour)
                if (x - a) % 6 == 3:
                    c.put(x, sy - 1, colour)
                    c.put(x, sy + 1, colour)


def tufts(c, rng, y0, y1, colour, count=60):
    for _ in range(count):
        x, y = rng.randrange(W), rng.randrange(y0, y1)
        for dx in (-1, 0, 1):
            c.line(x, y, x + dx * 2, y - rng.randint(2, 4), colour)


# --- the pictures ---------------------------------------------------------------------
# The intro's "Stage NN" drops into the sky (rows 75..111) and its caption sits
# over the horizon (from row 140), so the pictures keep those areas calm and put
# the tanks low in the frame.

def intro_midnight(c, rng):
    sky = [hexc(h) for h in ("05070f", "0a1024", "121a3a", "1c2a52", "2a3b66")]
    c.gradient(0, 170, sky)
    stars(c, rng, 140, [hexc("3a4a78"), hexc("8a9ad0"), hexc("e8f0ff")], 150)
    moon(c, 252, 48, 13, hexc("e9ecf5"), sky[1])
    for ang, x in ((-28, 70), (18, 118), (-12, 214)):
        searchlight(c, x, 168, ang, 190, 16, hexc("9ab8ff"))
    c.ridge(skyline(rng, 150, 16), hexc("141c38"), top_colour=hexc("24325e"))
    c.ridge(skyline(rng, 168, 9, 1.5), hexc("0b1024"), top_colour=hexc("1a2446"))
    c.gradient(186, H, [hexc("0a0e1e"), hexc("05070f")])
    tank(c, 96, 212, 92, 1, hexc("04050b"), rim=hexc("5b73b8"), wheel=hexc("0c1122"), light_side=1)
    tank(c, 236, 204, 64, -1, hexc("06080f"), rim=hexc("3d5190"), wheel=hexc("0c1122"), light_side=1)
    wire(c, rng, 234, hexc("1a2240"))


def intro_dawn(c, rng):
    sky = [hexc(h) for h in ("1b1440", "3b1f5c", "6e2e6e", "b0476a", "e0735a", "f5a55a", "fcd27a")]
    c.gradient(0, 172, sky)
    sun(c, 200, 166, 20, hexc("fff2c4"), hexc("ffd27a"), sky[-1], 3.4)
    clouds(c, rng, 4, (30, 64), hexc("4a2462"), hexc("9a4a78"), size=(40, 70))
    clouds(c, rng, 3, (104, 134), hexc("b0476a"), hexc("fcb070"), size=(50, 90))
    c.ridge(skyline(rng, 158, 18), hexc("5a2a58"), top_colour=hexc("8e4a6a"))
    c.ridge(skyline(rng, 172, 10, 1.4), hexc("2e1838"), top_colour=hexc("5c2e4c"))
    c.gradient(184, H, [hexc("1c0f24"), hexc("0f0814")])
    tank(c, 120, 214, 100, 1, hexc("0d0712"), rim=hexc("f0a060"), wheel=hexc("1c1022"), light_side=1)
    tank(c, 262, 200, 54, -1, hexc("160b1c"), rim=hexc("b86a5a"), wheel=hexc("241428"), light_side=-1)
    tufts(c, rng, 200, H, hexc("2a1830"))


def intro_desert(c, rng):
    sky = [hexc(h) for h in ("3a78b0", "6ea0c8", "a8c4d0", "e0d0a8", "f0c078")]
    c.gradient(0, 160, sky)
    sun(c, 70, 44, 15, hexc("fffbe8"), hexc("fff0b0"), sky[1], 3.0)
    for y in (132, 140, 147, 153):  # heat shimmer over the far dunes
        for x in range(W):
            if (x // 3 + y) % 7 == 0:
                c.dither(x, y, hexc("f8e0a8"), 0.6)
    c.ridge(skyline(rng, 150, 10, 0.7), hexc("d8a868"), top_colour=hexc("f0c888"))
    c.ridge(skyline(rng, 166, 14, 0.6), hexc("c08850"), top_colour=hexc("e0b070"))
    c.ridge(skyline(rng, 190, 12, 0.5), hexc("a06a3a"), top_colour=hexc("c8905a"))
    c.gradient(200, H, [hexc("8a5a30"), hexc("6a4424")])
    for i, x in enumerate((58, 150, 236)):
        smoke(c, rng, x - 38 + i * 4, 196 - i * 6, 26, hexc("d8b888"), 0.45, -0.4)
    tank(c, 74, 206, 70, 1, hexc("3a2614"), rim=hexc("f0d098"), wheel=hexc("52361c"), light_side=-1)
    tank(c, 166, 198, 58, 1, hexc("48301a"), rim=hexc("e8c890"), wheel=hexc("5a3c20"), light_side=-1)
    tank(c, 250, 191, 46, 1, hexc("583c22"), rim=hexc("e0c088"), wheel=hexc("6a4828"), light_side=-1)


def intro_red_dusk(c, rng):
    sky = [hexc(h) for h in ("140610", "2e0a18", "5a1020", "8e1c24", "c8342a", "f06a30")]
    c.gradient(0, 172, sky)
    sun(c, 244, 146, 26, hexc("ffd0a0"), hexc("ff8a48"), sky[-1], 2.6)
    clouds(c, rng, 4, (40, 80), hexc("3a0c1c"), hexc("8e1c24"), size=(30, 60))
    for _ in range(9):  # birds
        bx, by = rng.uniform(40, 280), rng.uniform(30, 100)
        c.line(bx - 3, by - 2, bx, by, hexc("1a0610"))
        c.line(bx, by, bx + 3, by - 2, hexc("1a0610"))
    # the ruins of a town along the horizon
    x = 0
    while x < W:
        w, h = rng.randint(10, 26), rng.randint(10, 38)
        top = 164 - h
        c.rect(x, top, x + w, 172, hexc("2a0812"))
        if rng.random() < 0.6:  # a broken roofline
            c.polygon([(x, top), (x + w, top), (x + w, top + rng.randint(3, 9))], sky[3])
        for wy in range(top + 4, 164, 6):
            for wx in range(x + 2, x + w - 2, 5):
                if rng.random() < 0.18:
                    c.rect(wx, wy, wx + 2, wy + 3, hexc("f06a30"))
        x += w + rng.randint(0, 6)
    c.ridge(skyline(rng, 182, 8, 1.2), hexc("1a050c"), top_colour=hexc("3a0a16"))
    c.gradient(190, H, [hexc("12040a"), hexc("080206")])
    tank(c, 110, 218, 96, 1, hexc("080205"), rim=hexc("ff7a40"), wheel=hexc("1a0610"), light_side=1)
    c.rect(214, 176, 216, 216, hexc("080205"))  # a flag on the ridge
    c.polygon([(216, 177), (236, 181), (216, 187)], hexc("c8342a"))


def intro_storm(c, rng):
    sky = [hexc(h) for h in ("0e1414", "1a2424", "263434", "344646", "3e5454")]
    c.gradient(0, 168, sky)
    bolt = [(212, 0)]
    while bolt[-1][1] < 150:
        x, y = bolt[-1]
        bolt.append((x + rng.randint(-10, 8), y + rng.randint(10, 22)))
    for (ax, ay), (bx, by) in zip(bolt, bolt[1:]):
        c.glow((ax + bx) / 2, (ay + by) / 2, 22, hexc("8ab8c8"), 0.35)
    for (ax, ay), (bx, by) in zip(bolt, bolt[1:]):
        c.line(ax, ay, bx, by, hexc("f0ffff"))
        c.line(ax + 1, ay, bx + 1, by, hexc("c8f0ff"))
    clouds(c, rng, 8, (0, 50), hexc("0a1010"), hexc("3e5454"), -1, size=(40, 80))
    c.ridge(skyline(rng, 150, 20), hexc("1a2622"), top_colour=hexc("5a7870"))
    c.ridge(skyline(rng, 172, 10, 1.3), hexc("0e1612"), top_colour=hexc("2a3a34"))
    c.gradient(186, H, [hexc("0c120f"), hexc("060a08")])
    for _ in range(320):  # rain
        x, y = rng.randrange(W), rng.randrange(H)
        c.line(x, y, x - 2, y + 5, hexc("4a6464"), 0.7)
    tank(c, 90, 214, 92, 1, hexc("050807"), rim=hexc("b8f0ff"), wheel=hexc("0e1612"), light_side=1)
    tank(c, 240, 206, 70, -1, hexc("070b09"), rim=hexc("8ac8d8"), wheel=hexc("0e1612"), light_side=1)


def intro_snow(c, rng):
    sky = [hexc(h) for h in ("0a1420", "10202e", "18303e", "22404e", "2e505e")]
    c.gradient(0, 160, sky)
    moon(c, 64, 42, 11, hexc("f0f8ff"), sky[1], crescent=False)
    stars(c, rng, 60, [hexc("3a5a6a"), hexc("a8c8d8")], 120)
    c.ridge(skyline(rng, 146, 22, 0.8), hexc("8aa8b8"), top_colour=hexc("e0f0f8"))
    heights = skyline(rng, 168, 10, 1.2)
    c.ridge(heights, hexc("c8dce6"), top_colour=hexc("f4fbff"))
    for _ in range(14):  # pines on the near slope
        px = rng.randrange(W)
        base = int(heights[px]) + rng.randint(0, 6)
        h = rng.randint(10, 20)
        c.polygon([(px, base - h), (px - h * 0.35, base), (px + h * 0.35, base)], hexc("12303a"))
        c.put(px, base - h, hexc("e0f0f8"))
    c.gradient(190, H, [hexc("b0c8d4"), hexc("8ea8b6")])
    tank(c, 110, 218, 96, 1, hexc("1a2a30"), rim=hexc("f4fbff"), wheel=hexc("2a3e46"))
    tank(c, 250, 206, 60, -1, hexc("22343a"), rim=hexc("f4fbff"), wheel=hexc("32484e"))
    for _ in range(260):  # falling snow
        c.put(rng.randrange(W), rng.randrange(H), hexc("f4fbff") if rng.random() < 0.7 else hexc("a8c8d8"))


def intro_aurora(c, rng):
    sky = [hexc(h) for h in ("03060c", "060e1a", "0a1826", "0e2232")]
    c.gradient(0, 170, sky)
    stars(c, rng, 110, [hexc("24405a"), hexc("7aa0c0"), hexc("e8f4ff")], 160)
    for band, (colour, base, amp) in enumerate(((hexc("2ad890"), 18, 10), (hexc("1ab0a8"), 34, 8))):
        phase = rng.uniform(0, 6.3)
        for x in range(W):
            top = base + amp * math.sin(x * 0.018 + phase) + 4 * math.sin(x * 0.05 + phase * 2)
            length = 26 + 10 * math.sin(x * 0.04 + phase)
            for y in range(int(top), int(top + length)):
                t = (y - top) / length
                c.dither(x, y, colour, (0.38 - band * 0.1) * (1 - t) ** 1.5 * (0.75 + 0.25 * math.sin(x * 0.12 + phase)))
    c.ridge(skyline(rng, 146, 26, 0.9), hexc("1a2e3a"), top_colour=hexc("6a9aa8"))
    c.ridge(skyline(rng, 170, 10, 1.4), hexc("0a141c"), top_colour=hexc("24485a"))
    c.gradient(184, H, [hexc("08121a"), hexc("03070c")])
    tank(c, 104, 214, 94, 1, hexc("02050a"), rim=hexc("5af0b0"), wheel=hexc("0a141c"), light_side=-1)
    tank(c, 244, 204, 62, -1, hexc("04080e"), rim=hexc("3ac8a0"), wheel=hexc("0a141c"), light_side=-1)


def intro_front(c, rng):
    sky = [hexc(h) for h in ("0c0606", "1c0c08", "32140a", "52200c", "7a300e")]
    c.gradient(0, 166, sky)
    for x in (40, 118, 196, 282):  # fires along the front, their smoke rising
        smoke(c, rng, x, 150, 120, hexc("2a1612"), 0.7, rng.uniform(0.1, 0.5))
    c.ridge(skyline(rng, 156, 12), hexc("24100a"), top_colour=hexc("4a200e"))
    for x in (40, 118, 196, 282):
        c.glow(x, 156, 26, hexc("ff8a30"), 0.6)
        for k in range(7):
            fx = x + rng.randint(-8, 8)
            fh = rng.randint(6, 14)
            c.polygon([(fx - 3, 158), (fx, 158 - fh), (fx + 3, 158)], hexc("ffb040") if k % 2 else hexc("ff6a20"))
    c.ridge(skyline(rng, 176, 8, 1.5), hexc("140806"), top_colour=hexc("3a1a0e"))
    c.gradient(188, H, [hexc("0e0604"), hexc("060302")])
    tank(c, 96, 216, 96, 1, hexc("050202"), rim=hexc("ff9a40"), wheel=hexc("160a06"), light_side=1)
    tank(c, 234, 206, 66, -1, hexc("070303"), rim=hexc("e87a30"), wheel=hexc("160a06"), light_side=-1)
    for _ in range(90):  # embers
        c.put(rng.randrange(W), rng.randrange(20, 200), rng.choice([hexc("ffb040"), hexc("ff6a20"), hexc("ffe080")]))


def intro_twilight(c, rng):
    sky = [hexc(h) for h in ("0c1a2e", "1a3450", "3a5470", "8a6a8a", "d88a8a", "f0b098")]
    c.gradient(0, 170, sky)
    stars(c, rng, 50, [hexc("3a5470"), hexc("c8d8f0")], 80)
    clouds(c, rng, 5, (60, 110), hexc("5a4a70"), hexc("f0b098"), size=(30, 64))
    # a ruined skyline: towers with broken tops and a crane
    x = 6
    while x < W:
        w, h = rng.randint(14, 30), rng.randint(18, 60)
        top = 166 - h
        c.rect(x, top, x + w, 172, hexc("1a1a2a"))
        c.polygon([(x, top), (x + w * rng.uniform(0.3, 0.7), top - rng.randint(0, 8)), (x + w, top + rng.randint(2, 10))],
                  hexc("1a1a2a"))
        for wy in range(top + 5, 166, 7):
            for wx in range(x + 3, x + w - 3, 6):
                if rng.random() < 0.12:
                    c.rect(wx, wy, wx + 2, wy + 3, hexc("f0c070"))
        x += w + rng.randint(2, 12)
    c.line(262, 96, 262, 166, hexc("12121e"))
    c.line(262, 98, 300, 98, hexc("12121e"))
    c.line(262, 106, 280, 98, hexc("12121e"))
    c.line(298, 98, 298, 114, hexc("12121e"))
    c.ridge(skyline(rng, 180, 6, 1.3), hexc("0e0e18"), top_colour=hexc("2a2a40"))
    c.gradient(188, H, [hexc("0c0c16"), hexc("06060c")])
    tank(c, 104, 216, 94, 1, hexc("05050a"), rim=hexc("f0a090"), wheel=hexc("12121e"), light_side=1)
    tank(c, 240, 206, 62, 1, hexc("07070e"), rim=hexc("c88890"), wheel=hexc("12121e"), light_side=1)


def intro_golden(c, rng):
    sky = [hexc(h) for h in ("3a4a7a", "7a7a8a", "c89a6a", "f0b858", "f8d890")]
    c.gradient(0, 164, sky)
    sun(c, 250, 128, 18, hexc("fffae0"), hexc("ffe0a0"), sky[-1], 3.6)
    clouds(c, rng, 6, (30, 100), hexc("a07a6a"), hexc("ffd890"), size=(34, 70))
    c.ridge(skyline(rng, 150, 14, 0.8), hexc("8a7a4a"), top_colour=hexc("d8c078"))
    heights = skyline(rng, 172, 12, 1.1)
    c.ridge(heights, hexc("4a4a22"), top_colour=hexc("a89848"))
    c.gradient(188, H, [hexc("343418"), hexc("1e1e0c")])
    tufts(c, rng, 188, H, hexc("5a5a28"), 90)
    tank(c, 104, 214, 96, 1, hexc("1a1a0c"), rim=hexc("ffe090"), wheel=hexc("2e2e16"), light_side=1)
    tank(c, 226, 202, 64, -1, hexc("24240f"), rim=hexc("f0d080"), wheel=hexc("34341a"), light_side=1)
    c.rect(282, int(heights[282]) - 30, 284, int(heights[282]) + 2, hexc("1a1a0c"))  # a flag on the hill
    c.polygon([(284, heights[282] - 29), (302, heights[282] - 25), (284, heights[282] - 20)], hexc("f0d080"))


INTROS = [intro_midnight, intro_dawn, intro_desert, intro_red_dusk, intro_storm,
          intro_snow, intro_aurora, intro_front, intro_twilight, intro_golden]


# --- the stage won: a blueprint of the tank ------------------------------------------------

BLUE = hexc("0a1a2e")
GRID = hexc("122a44")
GRID_MAJOR = hexc("1c3c5c")
INK = hexc("f0c060")
INK_DIM = hexc("a8843c")


def text(c, font, string, x, baseline, colour):
    """[string] in a pixel font from make_fonts, its baseline on row [baseline]."""
    for ch in string:
        code = ord(ch)
        if code in font.cmap:
            rows, left, top = font.pixels(code)
            for yy, row in enumerate(rows):
                for xx, v in enumerate(row):
                    if v:
                        c.put(x + left + xx, baseline - top + yy, colour)
            x += font.advance(code)
        else:
            x += 3
    return x


def text_width(font, string):
    return sum(font.advance(ord(ch)) if ord(ch) in font.cmap else 3 for ch in string)


def arrow_line(c, x0, x1, y, colour):
    """A dimension line with arrowheads and end ticks."""
    c.line(x0, y, x1, y, colour)
    for x, d in ((x0, 1), (x1, -1)):
        c.line(x, y - 4, x, y + 4, colour)
        c.line(x, y, x + 3 * d, y - 2, colour)
        c.line(x, y, x + 3 * d, y + 2, colour)


def outline(c, mask, colour):
    for (x, y) in mask:
        if any((x + dx, y + dy) not in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            c.put(x, y, colour)


def stage_win(c, rng):
    font = make_fonts.PixelFont(os.path.join(make_fonts.SRC, "Jersey10-Regular.ttf"))
    for y in range(H):
        for x in range(W):
            c.px[y][x] = GRID_MAJOR if (x % 32 == 0 or y % 32 == 0) else GRID if (x % 8 == 0 or y % 8 == 0) else BLUE
    c.glow(160, 130, 170, hexc("16324e"), 0.5)
    # the tank's side elevation, in outline
    x, ground, length = 150, 176, 200
    mask = tank(c, x, ground, length, 1, None, antenna=False)
    outline(c, mask, INK)
    for k in range(6):
        wx = x + (-0.38 + k * 0.152) * length
        for a in range(0, 360, 6):
            c.put(int(wx + 0.055 * length * math.cos(math.radians(a))),
                  int(ground - 0.085 * length + 0.055 * length * math.sin(math.radians(a))), INK)
        c.put(int(wx), int(ground - 0.085 * length), INK)
    c.line(x - 0.47 * length, ground - 0.17 * length, x + 0.47 * length, ground - 0.17 * length, INK_DIM)
    c.line(x - 0.5 * length, ground + 2, x + 0.8 * length, ground + 2, INK_DIM)  # the ground line
    # its measurements
    arrow_line(c, int(x - 0.52 * length), int(x + 0.8 * length), 188, INK)
    label = "9.87 m"
    text(c, font, label, int(x + 0.14 * length - text_width(font, label) / 2), 203, INK)
    c.line(int(x - 0.62 * length), int(ground), int(x - 0.62 * length), int(ground - 0.42 * length), INK)
    for yy, d in ((int(ground), -1), (int(ground - 0.42 * length), 1)):
        c.line(int(x - 0.62 * length) - 4, yy, int(x - 0.62 * length) + 4, yy, INK)
    label = "2.4 m"
    text(c, font, label, int(x - 0.62 * length) - text_width(font, label) // 2, int(ground - 0.42 * length) - 6, INK)
    # a front view, small, in the corner
    fx, fy = 268, 36
    c.rect(fx - 20, fy + 10, fx + 20, fy + 12, INK)
    for yy in range(fy - 6, fy + 10):
        c.put(fx - 20, yy, INK)
        c.put(fx + 20, yy, INK)
    c.line(fx - 20, fy - 6, fx + 20, fy - 6, INK)
    for px, py in ((fx - 12, fy - 6), (fx + 12, fy - 6)):
        c.line(px, py, px + (4 if px < fx else -4), py - 10, INK)
    c.line(fx - 8, fy - 16, fx + 8, fy - 16, INK)
    c.circle(fx, fy - 11, 2, INK)
    text(c, font, "FRONT", fx - text_width(font, "FRONT") // 2, fy + 26, INK_DIM)
    # the title block
    title = "BT-1"  # a small plate: "Mission Complete" rises to just below it
    right = 8 + text_width(font, title) + 10
    c.rect(8, 8, right, 28, BLUE)
    for yy in (8, 28):
        c.line(8, yy, right, yy, INK)
    for xx in (8, right):
        c.line(xx, 8, xx, 28, INK)
    text(c, font, title, 13, 22, INK)
    # corner marks
    for cx, cy, dx, dy in ((4, 4, 1, 1), (315, 4, -1, 1), (4, 235, 1, -1), (315, 235, -1, -1)):
        c.line(cx, cy, cx + 10 * dx, cy, INK_DIM)
        c.line(cx, cy, cx, cy + 10 * dy, INK_DIM)


# --- the stage lost: the base burning at night ------------------------------------------------

def stage_lose(c, rng):
    sky = [hexc(h) for h in ("040102", "0e0304", "220608", "40100a", "6a1c0c", "8e2c10")]
    c.gradient(0, 178, sky)
    for x, h in ((70, 150), (160, 175), (250, 140)):  # columns of smoke over the base
        smoke(c, rng, x, 170, h, hexc("1a0a08"), 0.8, rng.uniform(-0.3, 0.3))
    c.glow(160, 196, 170, hexc("c8401a"), 0.32)
    # flames all along the wall
    for _ in range(46):
        fx = rng.uniform(10, 310)
        fh = rng.uniform(10, 34) * (1.4 if abs(fx - 160) < 60 else 1.0)
        for k, colour in enumerate((hexc("b8200a"), hexc("ff6a1a"), hexc("ffb040"), hexc("fff0a0"))):
            s = 1 - k * 0.24
            c.polygon([(fx - 6 * s, 182), (fx + rng.uniform(-3, 3), 182 - fh * s), (fx + 6 * s, 182)], colour)
    # the base's brick wall, broken, in silhouette against the fire
    y = 182
    x = 0
    while x < W:
        h = rng.choice((0, 8, 16, 16, 24, 24, 32))
        w = 16
        if h:
            c.rect(x, y - h, x + w, H, hexc("180808"))
            for by in range(y - h, H, 8):  # brick joints lit by the fire
                off = 0 if (by // 8) % 2 == 0 else 8
                c.line(x, by, x + w - 1, by, hexc("3a1208"))
                c.line(x + off, by, x + off, by + 7, hexc("3a1208"))
            if rng.random() < 0.5:  # a broken top
                c.polygon([(x, y - h), (x + w, y - h), (x + w, y - h + rng.randint(3, 8))], sky[4])
        x += w
    c.rect(0, 206, W, H, hexc("0e0404"))
    # the base's flag, its pole snapped and the flag torn
    c.line(150, 206, 158, 150, hexc("0a0303"))
    c.line(151, 206, 159, 150, hexc("0a0303"))
    c.polygon([(158, 150), (182, 158), (174, 162), (180, 170), (156, 166)], hexc("7a1a14"))
    c.line(158, 150, 182, 158, hexc("c8342a"))
    for _ in range(140):  # embers on the wind
        c.put(rng.randrange(W), rng.randrange(0, 200), rng.choice([hexc("ffb040"), hexc("ff6a1a"), hexc("ffe080")]))


def build(name, draw, seed):
    c = Canvas()
    draw(c, random.Random(seed))
    path = os.path.join(OUT, name + ".png")
    c.save(path)
    print("wrote", os.path.relpath(path, ROOT))
    return c


def contact_sheet(canvases, path, columns=4):
    """All the pictures side by side, for looking them over (--sheet PATH)."""
    rows = (len(canvases) + columns - 1) // columns
    sheet = [[(0, 0, 0)] * (W * columns) for _ in range(H * rows)]
    for i, c in enumerate(canvases):
        ox, oy = (i % columns) * W, (i // columns) * H
        for y in range(H):
            sheet[oy + y][ox: ox + W] = c.px[y]
    raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in sheet)

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W * columns, H * rows, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    if "--out" in sys.argv:
        OUT = sys.argv[sys.argv.index("--out") + 1]
    os.makedirs(OUT, exist_ok=True)
    pictures = [("stage_intro_%d" % i, draw) for i, draw in enumerate(INTROS)]
    pictures += [("stage_win", stage_win), ("stage_lose", stage_lose)]
    made = []
    for seed, (name, draw) in enumerate(pictures):
        if only in (None, name):
            made.append(build(name, draw, 1000 + seed))
    if "--sheet" in sys.argv:
        contact_sheet(made, sys.argv[sys.argv.index("--sheet") + 1])
