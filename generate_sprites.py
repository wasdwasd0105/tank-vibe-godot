#!/usr/bin/env python3
"""Generate placeholder pixel art sprites for Battle City clone."""
import struct
import zlib
import os

def create_png(width, height, pixels):
    """Create a PNG file from pixel data. pixels is a list of (r,g,b,a) tuples."""
    def chunk(chunk_type, data):
        c = chunk_type + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack('>I', len(data)) + c + crc

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'  # filter byte
        for x in range(width):
            idx = y * width + x
            r, g, b, a = pixels[idx]
            raw_data += struct.pack('BBBB', r, g, b, a)

    idat = chunk(b'IDAT', zlib.compress(raw_data))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend

def make_color_pixels(width, height, color):
    """Fill with a solid color."""
    return [color] * (width * height)

def make_tank_pixels(size=32, color=(200, 200, 0, 255)):
    """Create a tank sprite (facing up)."""
    pixels = [(0, 0, 0, 0)] * (size * size)  # transparent
    r, g, b, a = color
    dark = (r//2, g//2, b//2, a)

    for y in range(size):
        for x in range(size):
            idx = y * size + x
            # Tank body (center rectangle)
            if 6 <= x <= 25 and 6 <= y <= 27:
                pixels[idx] = color
            # Treads (left and right sides)
            if (2 <= x <= 5 or 26 <= x <= 29) and 4 <= y <= 29:
                if y % 4 < 2:
                    pixels[idx] = dark
                else:
                    pixels[idx] = color
            # Turret (center top)
            if 13 <= x <= 18 and 2 <= y <= 14:
                pixels[idx] = color
            # Gun barrel
            if 14 <= x <= 17 and 0 <= y <= 6:
                pixels[idx] = dark
            # Body detail
            if 10 <= x <= 21 and 12 <= y <= 22:
                pixels[idx] = dark
    return pixels

def make_bullet_pixels(size=8, color=(255, 255, 200, 255)):
    """Create a bullet sprite."""
    pixels = [(0, 0, 0, 0)] * (size * size)
    for y in range(size):
        for x in range(size):
            dx = x - size // 2
            dy = y - size // 2
            if dx * dx + dy * dy <= (size // 2 - 1) ** 2:
                pixels[y * size + x] = color
    return pixels

def make_tile_pixels(size=32, tile_type='brick'):
    """Create tile sprites."""
    pixels = [(0, 0, 0, 0)] * (size * size)

    if tile_type == 'brick':
        brick_color = (178, 34, 34, 255)
        mortar = (139, 90, 43, 255)
        for y in range(size):
            for x in range(size):
                if y % 8 == 0 or y % 8 == 7:
                    pixels[y * size + x] = mortar
                elif (y < 8 or 16 <= y < 24) and (x % 16 == 0):
                    pixels[y * size + x] = mortar
                elif (8 <= y < 16 or 24 <= y) and ((x + 8) % 16 == 0):
                    pixels[y * size + x] = mortar
                else:
                    pixels[y * size + x] = brick_color

    elif tile_type == 'steel':
        steel_color = (192, 192, 192, 255)
        highlight = (224, 224, 224, 255)
        shadow = (128, 128, 128, 255)
        for y in range(size):
            for x in range(size):
                if x < 2 or y < 2:
                    pixels[y * size + x] = highlight
                elif x >= size - 2 or y >= size - 2:
                    pixels[y * size + x] = shadow
                else:
                    pixels[y * size + x] = steel_color

    elif tile_type == 'water':
        for y in range(size):
            for x in range(size):
                wave = int(abs(((x + y) % 8) - 4))
                b = 150 + wave * 20
                pixels[y * size + x] = (0, 50, min(b, 255), 255)

    elif tile_type == 'ice':
        for y in range(size):
            for x in range(size):
                v = 200 + ((x + y) % 4) * 10
                pixels[y * size + x] = (min(v, 255), min(v, 255), 255, 255)

    elif tile_type == 'tree':
        for y in range(size):
            for x in range(size):
                if ((x + y * 3) * 7) % 5 < 3:
                    pixels[y * size + x] = (0, 100 + (x * y) % 56, 0, 255)
                else:
                    pixels[y * size + x] = (0, 80 + (x * y) % 40, 0, 255)

    elif tile_type == 'brick_top':
        # Top half of brick
        brick_color = (178, 34, 34, 255)
        mortar = (139, 90, 43, 255)
        for y in range(size):
            for x in range(size):
                if y >= size // 2:
                    pixels[y * size + x] = (0, 0, 0, 0)
                elif y % 8 == 0 or y % 8 == 7:
                    pixels[y * size + x] = mortar
                else:
                    pixels[y * size + x] = brick_color

    elif tile_type == 'brick_bottom':
        brick_color = (178, 34, 34, 255)
        mortar = (139, 90, 43, 255)
        for y in range(size):
            for x in range(size):
                if y < size // 2:
                    pixels[y * size + x] = (0, 0, 0, 0)
                elif y % 8 == 0 or y % 8 == 7:
                    pixels[y * size + x] = mortar
                else:
                    pixels[y * size + x] = brick_color

    elif tile_type == 'brick_left':
        brick_color = (178, 34, 34, 255)
        mortar = (139, 90, 43, 255)
        for y in range(size):
            for x in range(size):
                if x >= size // 2:
                    pixels[y * size + x] = (0, 0, 0, 0)
                elif y % 8 == 0 or y % 8 == 7:
                    pixels[y * size + x] = mortar
                else:
                    pixels[y * size + x] = brick_color

    elif tile_type == 'brick_right':
        brick_color = (178, 34, 34, 255)
        mortar = (139, 90, 43, 255)
        for y in range(size):
            for x in range(size):
                if x < size // 2:
                    pixels[y * size + x] = (0, 0, 0, 0)
                elif y % 8 == 0 or y % 8 == 7:
                    pixels[y * size + x] = mortar
                else:
                    pixels[y * size + x] = brick_color

    return pixels

def make_eagle_pixels(size=32):
    """Create eagle/base sprite."""
    pixels = [(0, 0, 0, 0)] * (size * size)
    for y in range(size):
        for x in range(size):
            dx = x - size // 2
            dy = y - size // 2
            # Eagle body shape
            if abs(dx) + abs(dy) < size // 2 - 2:
                if abs(dx) < 4 and dy < -2:
                    # Head
                    pixels[y * size + x] = (255, 215, 0, 255)
                elif abs(dx) > 6 and dy > 0:
                    # Wings
                    pixels[y * size + x] = (139, 69, 19, 255)
                else:
                    # Body
                    pixels[y * size + x] = (200, 150, 50, 255)
    return pixels

def make_powerup_pixels(size=32, color=(255, 0, 0, 255)):
    """Create a powerup sprite."""
    pixels = [(0, 0, 0, 0)] * (size * size)
    for y in range(size):
        for x in range(size):
            dx = x - size // 2
            dy = y - size // 2
            if dx * dx + dy * dy <= (size // 2 - 2) ** 2:
                if dx * dx + dy * dy <= (size // 4) ** 2:
                    pixels[y * size + x] = (255, 255, 255, 255)
                else:
                    pixels[y * size + x] = color
    return pixels

def make_shield_pixels(size=36):
    """Create shield overlay."""
    pixels = [(0, 0, 0, 0)] * (size * size)
    center = size // 2
    for y in range(size):
        for x in range(size):
            dx = x - center
            dy = y - center
            dist = (dx * dx + dy * dy) ** 0.5
            if abs(dist - center + 2) < 2:
                pixels[y * size + x] = (100, 100, 255, 180)
    return pixels

def save_png(filepath, width, height, pixels):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, 'wb') as f:
        f.write(create_png(width, height, pixels))
    print(f"Created {filepath}")

def main():
    base = '/Users/wasdwasd0105/tank_godot/assets/sprites'

    # Tank sprites
    save_png(f'{base}/tanks/tank.png', 32, 32, make_tank_pixels(32, (200, 200, 0, 255)))

    # Bullet
    save_png(f'{base}/bullets/bullet.png', 8, 8, make_bullet_pixels(8))

    # Tileset - create as atlas (6 tiles wide, 2 rows)
    # Row 0: brick(0,0), steel(1,0), water(2,0), ice(3,0)
    # Row 1: brick_top(0,1), brick_bottom(0,2), brick_left(0,3), brick_right(1,1)
    atlas_w = 4 * 32
    atlas_h = 4 * 32
    atlas_pixels = [(0, 0, 0, 0)] * (atlas_w * atlas_h)

    tile_types = [
        ('brick', 0, 0), ('steel', 1, 0), ('water', 2, 0), ('ice', 3, 0),
        ('brick_top', 0, 1), ('brick_bottom', 0, 2), ('brick_left', 0, 3), ('brick_right', 1, 1),
        ('tree', 2, 1),
    ]

    for tile_type, tx, ty in tile_types:
        tile_pixels = make_tile_pixels(32, tile_type)
        for y in range(32):
            for x in range(32):
                ax = tx * 32 + x
                ay = ty * 32 + y
                atlas_pixels[ay * atlas_w + ax] = tile_pixels[y * 32 + x]

    save_png(f'{base}/tiles/tileset.png', atlas_w, atlas_h, atlas_pixels)

    # Eagle
    save_png(f'{base}/tiles/eagle.png', 32, 32, make_eagle_pixels(32))

    # Powerup
    save_png(f'{base}/powerups/powerup.png', 32, 32, make_powerup_pixels(32))

    # Shield
    save_png(f'{base}/effects/shield.png', 36, 36, make_shield_pixels(36))

    # Tree overlay for TileMapLayer
    save_png(f'{base}/tiles/tree.png', 32, 32, make_tile_pixels(32, 'tree'))

    print("\nAll sprites generated!")

if __name__ == '__main__':
    main()
