#!/usr/bin/env python3
"""Icon round-trip toolkit for Dota 2 panorama item icons.

Pure standard library (this machine has neither PIL nor numpy).

Sub-commands
------------
  pnginfo   <file.png>
  crop      <in.png> <out.png> <new_width>
  vtexread  <in.vtex_c> <out.png>        decode a compiled texture to PNG
  diff      <a.png> <b.png>              report per-channel differences
  recolor   <in.png> <out.png> <preset>  HSV-based recolor (magma|cursed|indigo|purple)

Why YCoCg matters
-----------------
Official panorama icons are compiled with the ``ConvertToYCoCg`` image
processor, so the four channels coming out of DXT5 are not RGB + alpha:

    R = Co     G = Cg     B = scale (encoded)     A = Y (luma)

The decoder below applies Valve's reconstruction:

    scale = (B / 8) + 1
    co    = (R - 128) / (255 * scale)
    cg    = (G - 128) / (255 * scale)
    y     = A / 255
    R_out = y + co - cg
    G_out = y + cg
    B_out = y - co - cg
    A_out = 255

Skipping that step yields olive/green garbage -- this is very likely the root
cause of the "black background / pink-white blocks" artifacts that were seen
when an icon was rebuilt by hand earlier in this project.
"""
import os
import struct
import sys
import zlib

# ----------------------------------------------------------------- PNG codec


def png_read(path):
    """Return (width, height, bytearray RGBA). Supports 8-bit RGB/RGBA only."""
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: %s" % path)

    pos = 8
    width = height = depth = color = None
    idat = bytearray()
    while pos < len(blob):
        (length,) = struct.unpack_from(">I", blob, pos)
        tag = blob[pos + 4:pos + 8]
        data = blob[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", data[:10])
        elif tag == b"IDAT":
            idat += data
        elif tag == b"IEND":
            break

    if depth != 8 or color not in (2, 6):
        raise ValueError("unsupported PNG: depth=%s colourtype=%s" % (depth, color))
    channels = 3 if color == 2 else 4
    raw = zlib.decompress(bytes(idat))

    stride = width * channels
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        ftype = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError("bad PNG filter %d on row %d" % (ftype, y))

        for x in range(width):
            s = x * channels
            d = (y * width + x) * 4
            out[d] = line[s]
            out[d + 1] = line[s + 1]
            out[d + 2] = line[s + 2]
            out[d + 3] = line[s + 3] if channels == 4 else 255
        prev = line
    return width, height, out


def png_write(path, width, height, rgba):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)
    return len(png)


# ------------------------------------------------------------- vtex_c reader

VTexFormat = {1: "DXT1", 2: "DXT5", 4: "RGBA8888"}
BLOCK_BYTES = {"DXT1": 8, "DXT5": 16}


def _align16(n):
    return (n + 15) & ~15


def vtex_read(path):
    """Return (width, height, bytearray RGBA) decoded from a compiled texture."""
    with open(path, "rb") as fh:
        blob = fh.read()

    file_size, hdr_ver, ver, block_off, block_count = struct.unpack_from("<IHHII", blob, 0)
    block_table = 8 + block_off          # BlockOffset is relative to its own field
    data_off = data_size = None
    for i in range(block_count):
        p = block_table + i * 12
        btype = blob[p:p + 4].rstrip(b"\x00").decode("ascii", "replace")
        off_rel, size = struct.unpack_from("<II", blob, p + 4)
        if btype == "DATA":
            data_off, data_size = p + 4 + off_rel, size

    if data_off is None:
        raise ValueError("no DATA block in %s" % path)

    (d_ver, d_flags, _r0, _r1, _r2, _r3,
     width, height, depth, fmt_id, mips,
     _picmip0, extra_off, extra_count) = struct.unpack_from("<HH4fHHHBBIII", blob, data_off)
    fmt = VTexFormat.get(fmt_id)
    if fmt not in BLOCK_BYTES:
        raise ValueError("unsupported format id %d in %s" % (fmt_id, path))

    # Extra data (FALLBACK_BITS etc.) lives between the header and the payload;
    # the pixel data starts at FileSize, which is what we trust here.
    payload = file_size
    bx = max(1, (width + 3) // 4)
    by = max(1, (height + 3) // 4)
    need = bx * by * BLOCK_BYTES[fmt]
    if payload + need > len(blob):
        raise ValueError("payload truncated: %d + %d > %d" % (payload, need, len(blob)))

    if fmt == "DXT5":
        pixels = _decode_dxt5(blob[payload:payload + need], width, height)
        pixels = _decode_ycocg(pixels)
    else:
        pixels = _decode_dxt1(blob[payload:payload + need], width, height)
    return width, height, pixels, dict(
        file_size=file_size, data_off=data_off, fmt=fmt,
        mips=mips, extra_count=extra_count, payload=payload)


def _rgb565(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def _decode_dxt5(data, width, height):
    bx, by = (width + 3) // 4, (height + 3) // 4
    out = bytearray(width * height * 4)
    pos = 0
    for ty in range(by):
        for tx in range(bx):
            a0, a1 = data[pos], data[pos + 1]
            abits = int.from_bytes(data[pos + 2:pos + 8], "little")
            if a0 > a1:
                alphas = [a0, a1] + [(a0 * (8 - k) + a1 * (k - 1)) // 7 for k in range(2, 8)]
            else:
                alphas = [a0, a1, (4 * a0 + a1) // 5, (3 * a0 + 2 * a1) // 5,
                          (2 * a0 + 3 * a1) // 5, (a0 + 4 * a1) // 5, 0, 255]
            c0, c1 = struct.unpack_from("<HH", data, pos + 8)
            cbits = struct.unpack_from("<I", data, pos + 12)[0]
            r0, g0, b0 = _rgb565(c0)
            r1, g1, b1 = _rgb565(c1)
            if c0 > c1:
                cols = [(r0, g0, b0), (r1, g1, b1),
                        ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3),
                        ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3)]
            else:
                cols = [(r0, g0, b0), (r1, g1, b1),
                        ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2), (0, 0, 0)]
            for py in range(4):
                y = ty * 4 + py
                if y >= height:
                    break
                for px in range(4):
                    x = tx * 4 + px
                    if x >= width:
                        continue
                    i = py * 4 + px
                    r, g, b = cols[(cbits >> (2 * i)) & 0x3]
                    o = (y * width + x) * 4
                    out[o] = r
                    out[o + 1] = g
                    out[o + 2] = b
                    out[o + 3] = alphas[(abits >> (3 * i)) & 0x7]
            pos += 16
    return out


def _decode_dxt1(data, width, height):
    bx, by = (width + 3) // 4, (height + 3) // 4
    out = bytearray(width * height * 4)
    pos = 0
    for ty in range(by):
        for tx in range(bx):
            c0, c1 = struct.unpack_from("<HH", data, pos)
            cbits = struct.unpack_from("<I", data, pos + 4)[0]
            r0, g0, b0 = _rgb565(c0)
            r1, g1, b1 = _rgb565(c1)
            if c0 > c1:
                cols = [(r0, g0, b0), (r1, g1, b1),
                        ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3),
                        ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3)]
                alphas = [255, 255, 255, 255]
            else:
                cols = [(r0, g0, b0), (r1, g1, b1),
                        ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2), (0, 0, 0)]
                alphas = [255, 255, 255, 0]
            for py in range(4):
                y = ty * 4 + py
                if y >= height:
                    break
                for px in range(4):
                    x = tx * 4 + px
                    if x >= width:
                        continue
                    r, g, b = cols[(cbits >> (2 * (py * 4 + px))) & 0x3]
                    o = (y * width + x) * 4
                    out[o] = r
                    out[o + 1] = g
                    out[o + 2] = b
                    out[o + 3] = alphas[(cbits >> (2 * (py * 4 + px))) & 0x3]
            pos += 8
    return out


def _decode_ycocg(pixels):
    """Valve's YCoCg -> RGB. Input/output are RGBA bytearrays."""
    out = bytearray(len(pixels))
    for i in range(0, len(pixels), 4):
        r, g, b, a = pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]
        scale = (b / 8.0) + 1.0
        co = (r - 128.0) / (255.0 * scale)
        cg = (g - 128.0) / (255.0 * scale)
        y = a / 255.0
        rr = y + co - cg
        gg = y + cg
        bb = y - co - cg
        out[i] = max(0, min(255, int(rr * 255.0)))
        out[i + 1] = max(0, min(255, int(gg * 255.0)))
        out[i + 2] = max(0, min(255, int(bb * 255.0)))
        out[i + 3] = 255
    return out


# ------------------------------------------------------------------- recolor

def _rgb_to_hsv(r, g, b):
    r, g, b = r / 255.0, g / 255.0, b / 255.0
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        h = 0.0
    elif mx == r:
        h = (60 * ((g - b) / d)) % 360
    elif mx == g:
        h = 60 * ((b - r) / d) + 120
    else:
        h = 60 * ((r - g) / d) + 240
    s = 0.0 if mx == 0 else d / mx
    return h, s, mx


def _hsv_to_rgb(h, s, v):
    h = h % 360.0
    c = v * s
    x = c * (1 - abs(((h / 60.0) % 2) - 1))
    m = v - c
    if h < 60:
        r, g, b = c, x, 0
    elif h < 120:
        r, g, b = x, c, 0
    elif h < 180:
        r, g, b = 0, c, x
    elif h < 240:
        r, g, b = 0, x, c
    elif h < 300:
        r, g, b = x, 0, c
    else:
        r, g, b = c, 0, x
    return (int((r + m) * 255), int((g + m) * 255), int((b + m) * 255))


# Presets: (hue target or None, hue mix, saturation factor, value factor, value gamma)
PRESETS = {
    # Keep the red/orange identity; just make it hotter and brighter.
    "magma": dict(hue=None, hue_mix=0.0, sat=1.55, sat_pow=0.85, val=1.14, gamma=0.92),
    "cursed": dict(hue=285.0, hue_mix=0.45, sat=1.30, sat_pow=1.0, val=1.05, gamma=1.0),
    "indigo": dict(hue=250.0, hue_mix=0.40, sat=1.25, sat_pow=1.0, val=1.05, gamma=1.0),
    "purple": dict(hue=300.0, hue_mix=0.35, sat=1.30, sat_pow=1.0, val=1.05, gamma=1.0),
}


def recolor(pixels, preset):
    cfg = PRESETS[preset]
    out = bytearray(len(pixels))
    for i in range(0, len(pixels), 4):
        r, g, b, a = pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]
        if a < 8:
            out[i:i + 4] = bytes((r, g, b, a))
            continue
        h, s, v = _rgb_to_hsv(r, g, b)
        if cfg["hue"] is not None and cfg["hue_mix"] > 0:
            # Shortest-arc hue blend towards the target hue.
            delta = ((cfg["hue"] - h + 540) % 360) - 180
            h = (h + delta * cfg["hue_mix"]) % 360
        s = min(1.0, (s ** cfg["sat_pow"]) * cfg["sat"])
        v = min(1.0, (v ** cfg["gamma"]) * cfg["val"])
        nr, ng, nb = _hsv_to_rgb(h, s, v)
        out[i] = nr
        out[i + 1] = ng
        out[i + 2] = nb
        out[i + 3] = a
    return out


# ---------------------------------------------------------------------- main

def cmd_diff(a_path, b_path):
    aw, ah, a = png_read(a_path)
    bw, bh, b = png_read(b_path)
    if (aw, ah) != (bw, bh):
        print("size mismatch: %dx%d vs %dx%d" % (aw, ah, bw, bh))
        return 1
    total = aw * ah
    maxd = [0, 0, 0, 0]
    sumd = [0, 0, 0, 0]
    over8 = 0
    for i in range(0, len(a), 4):
        row_max = 0
        for c in range(4):
            d = abs(a[i + c] - b[i + c])
            sumd[c] += d
            if d > maxd[c]:
                maxd[c] = d
            if c < 3:
                row_max = max(row_max, d)
        if row_max > 8:
            over8 += 1
    print("size            : %dx%d (%d px)" % (aw, ah, total))
    print("mean |delta|    : R=%.2f G=%.2f B=%.2f A=%.2f"
          % (sumd[0] / total, sumd[1] / total, sumd[2] / total, sumd[3] / total))
    print("max  |delta|    : R=%d G=%d B=%d A=%d" % tuple(maxd))
    print("px with RGB d>8 : %d (%.2f%%)" % (over8, 100.0 * over8 / total))
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]

    if cmd == "pnginfo":
        for p in argv[2:]:
            w, h, px = png_read(p)
            print("%-56s %dx%d" % (p, w, h))
        return 0

    if cmd == "crop":
        src, dst, nw = argv[2], argv[3], int(argv[4])
        w, h, px = png_read(src)
        if nw > w:
            raise ValueError("cannot widen: %d > %d" % (nw, w))
        out = bytearray(nw * h * 4)
        for y in range(h):
            out[y * nw * 4:(y + 1) * nw * 4] = px[y * w * 4:y * w * 4 + nw * 4]
        png_write(dst, nw, h, out)
        print("OK %s -> %s  %dx%d -> %dx%d" % (src, dst, w, h, nw, h))
        return 0

    if cmd == "vtexread":
        src, dst = argv[2], argv[3]
        w, h, px, meta = vtex_read(src)
        png_write(dst, w, h, px)
        print("OK %s -> %s  %dx%d  fmt=%s mips=%d extra=%d payload@%d FileSize=%d"
              % (src, dst, w, h, meta["fmt"], meta["mips"],
                 meta["extra_count"], meta["payload"], meta["file_size"]))
        return 0

    if cmd == "diff":
        return cmd_diff(argv[2], argv[3])

    if cmd == "recolor":
        src, dst, preset = argv[2], argv[3], argv[4]
        if preset not in PRESETS:
            print("unknown preset %r; choose from %s" % (preset, ", ".join(PRESETS)))
            return 1
        w, h, px = png_read(src)
        out = recolor(px, preset)
        png_write(dst, w, h, out)
        print("OK %s -> %s  preset=%s  %dx%d" % (src, dst, preset, w, h))
        return 0

    print(__doc__)
    return 2


# ----------------------------------------------------------------- encoders

def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return int((c * 12.92) * 255.0 + 0.5) if c <= 0.0031308 else int((1.055 * (c ** (1.0 / 2.4)) - 0.055) * 255.0 + 0.5)


def rgba_srgb_to_ycocg_bytes(rgba):
    """Convert sRGB RGBA bytearray to the YCoCg byte stream stored in a
    YCoCg-flagged DXT5 block (Co, Cg, scale, Y packed in the four bytes).

    Output bytes (per pixel):
        R'  Co_byte   ((co / scale) * 255 + 128)
        G'  Cg_byte   ((cg / scale) * 255 + 128)
        B'  scale_byte ((scale - 1) * 8)
        A'  Y_byte    (Y * 255)

    This is the exact inverse of ``_decode_ycocg``.
    """
    out = bytearray(len(rgba))
    for i in range(0, len(rgba), 4):
        r = srgb_to_linear(rgba[i])
        g = srgb_to_linear(rgba[i + 1])
        b = srgb_to_linear(rgba[i + 2])
        y = (r + 2.0 * g + b) / 4.0
        co = (r - b) / 2.0
        cg = (2.0 * g - r - b) / 4.0
        scale = max(1.0, abs(co), abs(cg))
        co_b = int((co / scale) * 255.0 + 128.0)
        cg_b = int((cg / scale) * 255.0 + 128.0)
        scale_b = int((scale - 1.0) * 8.0 + 0.5)
        y_b = int(y * 255.0 + 0.5)
        out[i]     = max(0, min(255, co_b))
        out[i + 1] = max(0, min(255, cg_b))
        out[i + 2] = max(0, min(255, scale_b))
        out[i + 3] = max(0, min(255, y_b))
    return out


def _pack_rgb565(r, g, b):
    return (max(0, min(31, r >> 3)) << 11) | (max(0, min(63, g >> 2)) << 5) | max(0, min(31, b >> 3))


def _unpack_rgb565(v):
    r = ((v >> 11) & 0x1F) << 3
    g = ((v >> 5) & 0x3F) << 2
    b = (v & 0x1F) << 3
    return r, g, b


def _dxt5_color_palette(c0, c1):
    if c0 > c1:
        return [
            _unpack_rgb565(c0),
            _unpack_rgb565(c1),
            ((2 * _unpack_rgb565(c0)[0] +     _unpack_rgb565(c1)[0]) // 3,
             (2 * _unpack_rgb565(c0)[1] +     _unpack_rgb565(c1)[1]) // 3,
             (2 * _unpack_rgb565(c0)[2] +     _unpack_rgb565(c1)[2]) // 3),
            ((    _unpack_rgb565(c0)[0] + 2 * _unpack_rgb565(c1)[0]) // 3,
             (    _unpack_rgb565(c0)[1] + 2 * _unpack_rgb565(c1)[1]) // 3,
             (    _unpack_rgb565(c0)[2] + 2 * _unpack_rgb565(c1)[2]) // 3),
        ]
    else:
        return [
            _unpack_rgb565(c0),
            _unpack_rgb565(c1),
            ((_unpack_rgb565(c0)[0] + _unpack_rgb565(c1)[0]) // 2,
             (_unpack_rgb565(c0)[1] + _unpack_rgb565(c1)[1]) // 2,
             (_unpack_rgb565(c0)[2] + _unpack_rgb565(c1)[2]) // 2),
            (0, 0, 0),
        ]


def _dxt5_alpha_palette(a0, a1):
    if a0 > a1:
        return [a0, a1] + [(a0 * (8 - k) + a1 * (k - 1)) // 7 for k in range(2, 8)]
    else:
        return [a0, a1, (4 * a0 + a1) // 5, (3 * a0 + 2 * a1) // 5,
                (2 * a0 + 3 * a1) // 5, (a0 + 4 * a1) // 5, 0, 255]


def _encode_dxt5_block(block_rgba):
    """block_rgba: bytearray of 16 pixels (64 bytes) in YCoCg-byte layout
    (R=Co, G=Cg, B=scale, A=Y).  Returns 16-byte DXT5 block."""
    # --- alpha channel: encode the Y values (byte 3 of each pixel)
    alphas = [block_rgba[i * 4 + 3] for i in range(16)]
    best_alpha = (0, 0, 1 << 30)
    for a0 in range(0, 256, 17):
        for a1 in range(0, 256, 17):
            palette = _dxt5_alpha_palette(a0, a1)
            err = 0
            for v in alphas:
                best = min(range(8), key=lambda k: abs(palette[k] - v))
                err += abs(palette[best] - v)
            if err < best_alpha[2]:
                best_alpha = (a0, a1, err)
    a0, a1, _ = best_alpha
    alpha_pal = _dxt5_alpha_palette(a0, a1)
    alpha_indices = [min(range(8), key=lambda k: abs(alpha_pal[k] - v)) for v in alphas]

    # --- color channels: store (Co, Cg, scale) bytes.
    # The DXT5 color block uses RGB565 endpoints, so we optimise in the
    # (Co, Cg, scale) byte space: pick the two RGB565 endpoints whose
    # 4 derived byte triplets most closely match the per-pixel target.
    cos = [block_rgba[i * 4]     for i in range(16)]
    cgs = [block_rgba[i * 4 + 1] for i in range(16)]
    scales = [block_rgba[i * 4 + 2] for i in range(16)]

    def pack_err(c0, c1):
        palette = _dxt5_color_palette(c0, c1)
        err = 0
        for i in range(16):
            best = min(range(4), key=lambda k: (
                abs(palette[k][0] - cos[i]) +
                abs(palette[k][1] - cgs[i]) +
                abs(palette[k][2] - scales[i])))
            err += (abs(palette[best][0] - cos[i])
                    + abs(palette[best][1] - cgs[i])
                    + abs(palette[best][2] - scales[i]))
        return err, palette

    best_color = (0, 0, None, 1 << 30)
    # Build a small set of candidate RGB565 endpoints derived from the
    # 16 pixels in this block (plus min/max along each axis).  This keeps
    # the search at ~10x10 = 100 endpoint pairs per block instead of
    # 1024x1024 from a global grid.
    pix = list(zip(cos, cgs, scales))
    candidates = set()
    for (co, cg, sc) in pix:
        candidates.add(_pack_rgb565(co, cg, sc))
    # Also add a few anchor points (extremes and the dark case)
    candidates.add(_pack_rgb565(min(cos), min(cgs), min(scales)))
    candidates.add(_pack_rgb565(max(cos), max(cgs), max(scales)))
    candidates.add(_pack_rgb565(0, 0, 0))
    candidates.add(_pack_rgb565(255, 255, 255))
    # And a few mid-axis samples for blocks with wide dynamic range.
    for t in (0.25, 0.5, 0.75):
        candidates.add(_pack_rgb565(int(min(cos) + t * (max(cos) - min(cos))),
                                    int(min(cgs) + t * (max(cgs) - min(cgs))),
                                    int(min(scales) + t * (max(scales) - min(scales)))))
    rgb565_samples = list(candidates)
    for c0 in rgb565_samples:
        for c1 in rgb565_samples:
            err, palette = pack_err(c0, c1)
            if err < best_color[3]:
                best_color = (c0, c1, palette, err)
    c0, c1, color_pal, _ = best_color
    color_indices = []
    for i in range(16):
        best = min(range(4), key=lambda k: (
            abs(color_pal[k][0] - cos[i]) +
            abs(color_pal[k][1] - cgs[i]) +
            abs(color_pal[k][2] - scales[i])))
        color_indices.append(best)

    # --- pack the 16-byte block
    alpha_bits = 0
    for i in range(16):
        alpha_bits |= alpha_indices[i] << (3 * i)
    color_bits = 0
    for i in range(16):
        color_bits |= color_indices[i] << (2 * i)
    return struct.pack("<BBIHHHI",
                       a0, a1,
                       alpha_bits & 0xFFFFFFFF, (alpha_bits >> 32) & 0xFFFF,
                       c0, c1,
                       color_bits)


def encode_dxt5(width, height, ycocg_rgba):
    """Encode an 87x64 (or other) image from YCoCg-byte layout to DXT5 blocks."""
    blocks_x = (width + 3) // 4
    blocks_y = (height + 3) // 4
    out = bytearray(blocks_x * blocks_y * 16)
    pos = 0
    for by in range(blocks_y):
        for bx in range(blocks_x):
            block = bytearray(64)
            for py in range(4):
                y = by * 4 + py
                if y >= height:
                    break
                for px in range(4):
                    x = bx * 4 + px
                    if x >= width:
                        continue
                    src = (y * width + x) * 4
                    dst = (py * 4 + px) * 4
                    block[dst:dst + 4] = ycocg_rgba[src:src + 4]
            out[pos:pos + 16] = _encode_dxt5_block(block)
            pos += 16
    return out


if __name__ == "__main__":
    sys.exit(main(sys.argv))
