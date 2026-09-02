#!/usr/bin/env python3
"""Decode the mip-0 DXT5 payload of a compiled Valve texture (.vtex_c) to PNG.

Pure standard library - this machine has neither PIL nor numpy.

The .vtex_c container is Valve's resource format.  For the small panorama item
icons (88x64, DXT5, single mip) the layout we observe is:

    offset 0   uint32  size of everything preceding the pixel payload
    offset 4   uint16  header version (12)
    offset 6   uint16  file version (1)
    ...        RED2 / DATA blocks holding NTRO schema and metadata
    offset N   raw DXT5 blocks, row-major, 16 bytes per 4x4 block

Because the metadata length varies slightly between textures we do not hardcode
N; we read the first dword and fall back to a scan when it does not look right.

Usage:
    python vtex_decode.py <input.vtex_c> <output.png> [width] [height] [offset]
"""
import struct
import sys
import zlib


# ---------------------------------------------------------------- PNG writer
def write_png(path, width, height, rgba):
    """rgba: bytearray of width*height*4, already filtered rows are built here."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type 0 (None) for every scanline
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as fh:
        fh.write(png)
    return len(png)


# --------------------------------------------------------------- DXT5 decode
def _rgb565(value):
    r = (value >> 11) & 0x1F
    g = (value >> 5) & 0x3F
    b = value & 0x1F
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def decode_dxt5(data, width, height):
    """Return a bytearray of RGBA pixels for a DXT5 image."""
    blocks_x = (width + 3) // 4
    blocks_y = (height + 3) // 4
    need = blocks_x * blocks_y * 16
    if len(data) < need:
        raise ValueError("need %d bytes of DXT5 data, have %d" % (need, len(data)))

    out = bytearray(width * height * 4)
    pos = 0
    for by in range(blocks_y):
        for bx in range(blocks_x):
            # ---- alpha: 2 endpoints + 48 bits of 3-bit indices
            a0, a1 = data[pos], data[pos + 1]
            abits = int.from_bytes(data[pos + 2:pos + 8], "little")
            if a0 > a1:
                alphas = [a0, a1] + [
                    (a0 * (8 - k) + a1 * (k - 1)) // 7 for k in range(2, 8)
                ]
            else:
                alphas = [a0, a1, (4 * a0 + a1) // 5, (3 * a0 + 2 * a1) // 5,
                          (2 * a0 + 3 * a1) // 5, (a0 + 4 * a1) // 5, 0, 255]

            # ---- colour: 2 RGB565 endpoints + 32 bits of 2-bit indices
            c0 = struct.unpack_from("<H", data, pos + 8)[0]
            c1 = struct.unpack_from("<H", data, pos + 10)[0]
            cbits = struct.unpack_from("<I", data, pos + 12)[0]
            r0, g0, b0 = _rgb565(c0)
            r1, g1, b1 = _rgb565(c1)
            if c0 > c1:
                colors = [(r0, g0, b0), (r1, g1, b1),
                          ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3),
                          ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3)]
            else:
                colors = [(r0, g0, b0), (r1, g1, b1),
                          ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2),
                          (0, 0, 0)]

            for py in range(4):
                y = by * 4 + py
                if y >= height:
                    break
                for px in range(4):
                    x = bx * 4 + px
                    idx = py * 4 + px
                    cidx = (cbits >> (2 * idx)) & 0x3
                    aidx = (abits >> (3 * idx)) & 0x7
                    r, g, b = colors[cidx]
                    base = (y * width + x) * 4
                    out[base] = r
                    out[base + 1] = g
                    out[base + 2] = b
                    out[base + 3] = alphas[aidx]
            pos += 16
    return out


def score(pixels):
    """Heuristic: a real icon has plenty of distinct colours and mixed alpha."""
    colors = set()
    opaque = 0
    for i in range(0, len(pixels), 4):
        colors.add(bytes(pixels[i:i + 4]))
        if pixels[i + 3] > 8:
            opaque += 1
    total = len(pixels) // 4
    coverage = opaque / total
    return len(colors), coverage


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    src, dst = argv[1], argv[2]
    width = int(argv[3]) if len(argv) > 3 else 88
    height = int(argv[4]) if len(argv) > 4 else 64
    with open(src, "rb") as fh:
        blob = fh.read()

    need = ((width + 3) // 4) * ((height + 3) // 4) * 16

    if len(argv) > 5:
        candidates = [int(argv[5], 0)]
    else:
        declared = struct.unpack_from("<I", blob, 0)[0]
        candidates = []
        if 0 < declared <= len(blob) - need:
            candidates.append(declared)
        # Fall back: scan every 4-byte aligned start that leaves room for mip0.
        candidates.extend(range(0, len(blob) - need + 1, 4))

    best = None
    for off in candidates:
        try:
            pixels = decode_dxt5(blob[off:off + need], width, height)
        except (ValueError, struct.error, IndexError):
            continue
        colors, coverage = score(pixels)
        # An icon is neither fully transparent nor fully opaque.
        if 0.02 <= coverage <= 0.999:
            best = (off, pixels, colors, coverage)
            break
    if best is None:
        print("could not locate a plausible DXT5 payload")
        return 1

    off, pixels, colors, coverage = best
    size = write_png(dst, width, height, pixels)
    print(
        "OK %s -> %s  %dx%d  payload@%d  colours=%d  alpha coverage=%.1f%%  png=%dB"
        % (src, dst, width, height, off, colors, coverage * 100, size)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
