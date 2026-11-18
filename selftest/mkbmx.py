#!/usr/bin/env python3
"""Test pictures for selftest/run_pictest.sh (no dependencies): BMX v1 files in <dir>.

PIC8.BMX  320 x 240, 8 bpp, 64-colour palette: sky gradient, sun, hills (shown 320 x 120, 15 lines)
PIC4.BMX   64 x  48, 4 bpp, 16 colours: diagonal stripes                 (64 x 24, 3 lines)
PIC1.BMX  128 x  64, 1 bpp, 2 colours: checkerboard with a ring          (128 x 32, 4 lines)
BAD.BMX   a file that isn't a BMX
"""
import struct
import sys
from pathlib import Path


def bmx(bpp, w, h, pal, rows):
    n = len(pal)
    hdr = struct.pack("<3sBBBHHBBHBB16s", b"BMX", 1, bpp, {1: 0, 2: 1, 4: 2, 8: 3}[bpp], w, h, n % 256, 0,
                      32 + 2 * n, 0, 0, b"\0" * 16)
    p = b"".join(bytes([(g << 4) | b, r]) for r, g, b in pal)     # 4-bit components
    return hdr + p + b"".join(rows)


def pack(px, bpp):
    per = 8 // bpp
    out = bytearray()
    for i in range(0, len(px), per):
        v = 0
        for k in range(per):
            v = (v << bpp) | px[i + k]
        out.append(v)
    return bytes(out)


def main(d: Path):
    d.mkdir(parents=True, exist_ok=True)
    # 8 bpp: palette 0-31 sky (dark blue -> light), 32 sun, 33-40 greens, 41 house, 42 roof
    pal = [(2 + i // 4, 3 + i // 3, 9 + i // 5) for i in range(32)]
    pal += [(15, 13, 3)] + [(2 + i // 2, 8 + i // 2, 3) for i in range(8)] + [(12, 4, 3), (7, 2, 2)]
    rows = []
    for y in range(240):
        px = []
        for x in range(320):
            c = min(31, y * 32 // 150)
            if (x - 255) ** 2 + (y - 65) ** 2 < 35 ** 2:
                c = 32
            hill = 160 - abs((x % 160) - 80) // 2 + (x // 160) * 10
            if y > hill:
                c = 33 + min(7, (y - hill) // 12)
            if 40 <= x < 90 and 180 <= y < 225:
                c = 41
            if 155 + abs(x - 65) <= y < 180 and 35 <= x < 95:
                c = 42
            px.append(c)
        rows.append(bytes(px))
    (d / "PIC8.BMX").write_bytes(bmx(8, 320, 240, pal, rows))
    pal = [(i, 15 - i, (i * 5) % 16) for i in range(16)]
    rows = [pack([((x // 4) + (y // 6)) % 16 for x in range(64)], 4) for y in range(48)]
    (d / "PIC4.BMX").write_bytes(bmx(4, 64, 48, pal, rows))
    rows = []
    for y in range(64):
        rows.append(pack([int((800 < (x - 64) ** 2 + (y - 32) ** 2 * 4 < 1000) ^ ((x // 8 + y // 8) % 2 == 0))
                          for x in range(128)], 1))
    (d / "PIC1.BMX").write_bytes(bmx(1, 128, 64, [(1, 1, 5), (15, 14, 7)], rows))
    (d / "BAD.BMX").write_bytes(b"this is not a picture\n" * 4)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
