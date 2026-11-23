#!/usr/bin/env python3
"""Convert an XWD dump (Xvfb -fbdir, 32bpp TrueColor) from stdin to PNG on stdout."""
import struct, sys, zlib
d = sys.stdin.buffer.read()
h = struct.unpack(">25I", d[:100])
hdr, w, ht, bpl, bpp, order = h[0], h[4], h[5], h[12], h[11], h[7]
rm, gm, bm = h[14], h[15], h[16]
assert bpp == 32, f"unsupported bpp {bpp}"
px = d[hdr + h[19] * 12:]
sh = lambda m: (m & -m).bit_length() - 1
rs, gs, bs = sh(rm), sh(gm), sh(bm)
colours = len({px[i:i + 4] for i in range(0, min(len(px), 4 * w * ht), 4 * 7)})
sys.stderr.write(f"distinct colours: {colours}\n")
if colours < 3:
    sys.exit(3)  # a blank screen is not a rendered application
raw = bytearray()
fmt = "<I" if order == 0 else ">I"
for y in range(ht):
    raw.append(0)
    row = px[y * bpl:y * bpl + w * 4]
    for (v,) in struct.iter_unpack(fmt, row):
        raw += bytes(((v & rm) >> rs, (v & gm) >> gs, (v & bm) >> bs))
def chunk(t, b):
    c = struct.pack(">I", len(b)) + t + b
    return c + struct.pack(">I", zlib.crc32(t + b))
sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, ht, 8, 2, 0, 0, 0))
                        + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
