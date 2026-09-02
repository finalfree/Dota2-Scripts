#!/usr/bin/env python3
"""Dump the Source 2 resource block layout of a compiled texture (_c).

Usage:
    python scripts/vtex_inspect.py <file.vtex_c>

Source 2 resource header (16 bytes):
    u32 FileSize        -- "structural" size (excludes pixel payload)
    u16 HeaderVersion   -- 12 for disk resources
    u16 Version
    u32 BlockOffset     -- relative to the START of this header
    u32 BlockCount

Block table entry (12 bytes):
    char[4] BlockType
    u32     Offset      -- RELATIVE to the offset field's own position
    u32     Size

Texture DATA block (VRF 20.0 Texture.cs::Read):
    u16   Version
    u16   Flags
    f32x4 Reflectivity
    u16   Width
    u16   Height
    u16   Depth
    u8    Format        -- see VTexFormat
    u8    NumMipLevels
    u32   Picmip0Res
    u32   extraDataOffset  (relative to its own position)
    u32   extraDataCount

Extra data entry (8 bytes each):
    u32 Type     -- see VTexExtraData
    u32 Offset   -- RELATIVE to its own position
    u32 Size
    (note: VRF reads Type, then Offset, then Size => 12 bytes each)
"""

import os
import struct
import sys

VTexFormat = {
    0: "UNKNOWN",
    1: "DXT1",
    2: "DXT5",
    3: "I8",
    4: "RGBA8888",
    5: "A8",
    6: "RGB888",
    7: "BGR888",
    8: "R16",
    9: "D16",
    10: "D15S1",
    11: "D16F",
    12: "R16F",
    13: "RG1616",
    14: "RG1616F",
    15: "JPEG_RGBA8888",
    16: "PNG_RGBA8888",
    17: "JPEG_DXT5",
    18: "PNG_DXT5",
    19: "BC6H",
    20: "BC7",
    21: "ATI2N",
    22: "IA88",
    23: "ETC2",
    24: "ETC2_EAC",
    25: "R11_EAC",
    26: "RG11_EAC",
    27: "ATI1N",
    28: "BGRA8888",
    29: "WEBP_RGBA8888",
    30: "WEBP_DXT5",
}

VTexExtraData = {
    0: "UNKNOWN",
    1: "FALLBACK_BITS",
    2: "SHEET",
    3: "METADATA",
    4: "COMPRESSED_MIP_SIZE",
    5: "CUBEMAP_RADIANCE_SH",
}

# Compressed block formats: bytes per 4x4 block
BLOCK_BYTES = {"DXT1": 8, "DXT5": 16, "ATI1N": 8, "ATI2N": 16, "BC7": 16, "BC6H": 16}


def align16(n):
    return (n + 15) & ~15


def mip_size(fmt, width, height):
    """Size in bytes of a single mip level of a block-compressed texture."""
    per_block = BLOCK_BYTES.get(fmt)
    if per_block is None:
        return None
    bx = max(1, (width + 3) // 4)
    by = max(1, (height + 3) // 4)
    return bx * by * per_block


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    if not os.path.exists(path):
        print("no such file: %s" % path)
        return 1

    with open(path, "rb") as fh:
        blob = fh.read()

    file_size, hdr_ver, ver, block_off, block_count = struct.unpack_from("<IHHII", blob, 0)
    # BlockOffset is RELATIVE to its own field position (offset 8), same rule as
    # the per-block offsets. Empirically: field at 8, value 8 -> table at 16.
    block_table = 8 + block_off
    print("file                : %s" % path)
    print("disk size           : %d bytes" % len(blob))
    print("FileSize (struct)   : %d   (end of structural blocks)" % file_size)
    print("HeaderVersion       : %d   (12 expected on disk)" % hdr_ver)
    print("Version             : %d" % ver)
    print("BlockOffset         : %d -> block table abs %d" % (block_off, block_table))
    print("BlockCount          : %d" % block_count)
    print()

    data_block = None
    print("%-6s %-6s %-12s %-12s %-10s %s" % ("idx", "type", "rel_off", "abs_off", "size", "note"))
    print("-" * 72)
    for i in range(block_count):
        p = block_table + i * 12
        btype = blob[p:p + 4].rstrip(b"\x00").decode("ascii", "replace")
        off_rel, size = struct.unpack_from("<II", blob, p + 4)
        off_abs = p + 4 + off_rel
        note = ""
        if btype == "DATA":
            data_block = (off_abs, size)
            note = "<- texture header"
        print("%-6d %-6s %-12d %-12d %-10d %s"
              % (i, btype, off_rel, off_abs, size, note))

    if data_block is None:
        print("\nno DATA block found")
        return 0

    d_off, d_size = data_block
    print()
    (d_ver, d_flags,
     r0, r1, r2, r3,
     width, height, depth, fmt_id, mips,
     picmip0, extra_off, extra_count) = struct.unpack_from("<HH4fHHHBBIII", blob, d_off)

    fmt = VTexFormat.get(fmt_id, "?%d" % fmt_id)
    print("TEXTURE HEADER (at abs %d, %d bytes)" % (d_off, d_size))
    print("  Version           : %d" % d_ver)
    print("  Flags             : 0x%04x" % d_flags)
    print("  Reflectivity      : %.4f %.4f %.4f %.4f" % (r0, r1, r2, r3))
    print("  Width x Height    : %d x %d  (depth %d)" % (width, height, depth))
    print("  Format            : %d = %s" % (fmt_id, fmt))
    print("  NumMipLevels      : %d" % mips)
    print("  Picmip0Res        : %d" % picmip0)
    print("  extraDataOffset   : %d" % extra_off)
    print("  extraDataCount    : %d" % extra_count)

    if extra_count:
        print()
        print("EXTRA DATA")
        for i in range(extra_count):
            p = d_off + extra_off + i * 12
            etype, eoff, esize = struct.unpack_from("<III", blob, p)
            eabs = p + 4 + eoff
            print("  [%d] %-24s rel=%-6d abs=%-8d size=%d"
                  % (i, VTexExtraData.get(etype, "?%d" % etype), eoff, eabs, esize))

    # Locate the mip0 payload: first 16-byte-aligned region after the DATA block.
    payload_start = align16(d_off + d_size)
    print()
    print("MIP LAYOUT (block-compressed payload starts at abs %d, 16-aligned)" % payload_start)
    w, h = width, height
    cursor = payload_start
    for i in range(mips):
        sz = mip_size(fmt, w, h)
        if sz is None:
            print("  mip%-2d %3dx%-3d  (unknown size for %s)" % (i, w, h, fmt))
            break
        print("  mip%-2d %3dx%-3d  abs_off=%-8d size=%-7d end=%d"
              % (i, w, h, cursor, sz, cursor + sz))
        cursor = align16(cursor + sz)
        w = max(1, w // 2)
        h = max(1, h // 2)
    print("  -> payload ends at %d; file continues to %d (remainder %d bytes)"
          % (cursor, len(blob), len(blob) - cursor))
    return 0


if __name__ == "__main__":
    sys.exit(main())
