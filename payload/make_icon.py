#!/usr/bin/env python3
"""Generate a PNG icon using only Python's standard library."""
import binascii
import struct
import sys
import zlib

SIZE = 300

def inside_round(x, y, r=55):
    cx = min(max(x, r), SIZE - r); cy = min(max(y, r), SIZE - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r ** 2

def pixel(x, y):
    if not inside_round(x, y): return (0, 0, 0, 0)
    mix = (x + y) / (SIZE * 2)
    bg = tuple(round(a * (1 - mix) + b * mix) for a, b in zip((56, 189, 248), (7, 89, 133)))
    blocks = ((61, 84, 104, 121), (111, 84, 154, 121), (161, 84, 204, 121), (111, 41, 154, 78))
    if any(l <= x <= r and t <= y <= b for l, t, r, b in blocks): return (255, 255, 255, 255)
    # Simple whale/container silhouette.
    if 44 <= x <= 221 and 132 <= y <= 176 and ((x - 128) / 92) ** 2 + ((y - 132) / 60) ** 2 <= 1.4:
        return (255, 255, 255, 255)
    if 206 <= x <= 250 and 118 <= y <= 161 and y >= 161 - (x - 206) * 0.75:
        return (255, 255, 255, 255)
    return (*bg, 255)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)

def main():
    if len(sys.argv) != 2: raise SystemExit('usage: make_icon.py OUTPUT')
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        for x in range(SIZE): raw.extend(pixel(x + .5, y + .5))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    with open(sys.argv[1], 'wb') as output: output.write(png)

if __name__ == '__main__': main()

