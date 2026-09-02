#!/usr/bin/env python3
"""Extract a single file out of a VPK v1/v2 pack set, verifying its CRC32.

The directory pack (`pak01_dir.vpk`) holds the tree; the payload usually lives in
a numbered shard (`pak01_<archive>.vpk`) at the recorded offset.  An archive
index of 0x7fff means the payload is inside the directory pack itself, positioned
after the tree + MD5 sections.

Usage:
    python vpk_extract.py <dir_pack.vpk> <in-pack-path> <output-file>
"""
import os
import struct
import sys
import zlib

from vpk_list import ARCHIVE_DIR_PACK, read_header, parse_tree


def dir_pack_data_start(pack):
    """Offset where the file payload begins inside a directory pack."""
    with open(pack, "rb") as fh:
        blob = fh.read(28)
    version = struct.unpack("<I", blob[4:8])[0]
    if version == 1:
        return struct.unpack("<I", blob[8:12])[0] + 12
    tree_size, file_data_size, archive_md5_size, other_md5_size = struct.unpack("<IIII", blob[8:24])
    # v2: tree comes first, then archive MD5s, then "other" MD5s, then data.
    return 28 + tree_size + archive_md5_size + other_md5_size


def shard_path(dir_pack, archive):
    return os.path.join(os.path.dirname(dir_pack), "pak01_%03d.vpk" % archive)


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2
    dir_pack, wanted, output = argv[1], argv[2].lower(), argv[3]

    entry = None
    for full, crc, preload, archive, offset, length in parse_tree(dir_pack):
        if full.lower() == wanted:
            entry = (full, crc, preload, archive, offset, length)
            break
    if entry is None:
        print("not found in pack: %s" % argv[2])
        return 1
    full, crc, preload, archive, offset, length = entry

    if archive == ARCHIVE_DIR_PACK:
        source, absolute = dir_pack, dir_pack_data_start(dir_pack) + offset
    else:
        source, absolute = shard_path(dir_pack, archive), offset

    with open(source, "rb") as fh:
        fh.seek(absolute)
        data = fh.read(length)
        if preload:
            # Preload bytes live in the tree, immediately before the entry; the
            # payload in the shard follows them.  Re-read is not needed here
            # because parse_tree already consumed them.
            pass
    if len(data) != length:
        print("short read: got %d of %d bytes from %s" % (len(data), length, source))
        return 1

    actual = zlib.crc32(data) & 0xFFFFFFFF
    if actual != crc:
        print("CRC mismatch: expected %08x got %08x" % (crc, actual))
        return 1

    os.makedirs(os.path.dirname(os.path.abspath(output)) or ".", exist_ok=True)
    with open(output, "wb") as fh:
        fh.write(data)
    print(
        "OK %s -> %s (%d bytes, crc=%08x verified, archive=%d offset=%d)"
        % (full, output, length, actual, archive, offset)
    )
    return 0


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    sys.exit(main(sys.argv))
