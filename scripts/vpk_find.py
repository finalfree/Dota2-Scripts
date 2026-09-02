#!/usr/bin/env python3
"""Scan VPK v1 pack files for a filename substring, searching only the directory-tree region.

VPK v1 layout:
    header: signature(4) + version(4) + treeSize(4)
    tree starts at offset 12 and is treeSize bytes long.
Filenames are stored as NUL-terminated ASCII inside the tree, so a plain byte
search over [12, 12+treeSize) is sufficient and far faster than a full parse.

Usage:
    python vpk_find.py <needle> <vpk> [vpk ...]
"""
import struct
import sys


def tree_region(path):
    with open(path, "rb") as fh:
        header = fh.read(12)
        if len(header) < 12:
            return None
        signature, version, tree_size = struct.unpack("<IIi", header)
        if signature != 0x55AA1234:
            return None
        if version != 1:
            return None
        return fh.read(tree_size)


def find_in_pack(path, needle_bytes):
    blob = tree_region(path)
    if blob is None:
        return []
    return [blob.count(needle_bytes)]


def expand(arg):
    """A directory expands to pak01_dir.vpk plus every pak01_NNN.vpk shard."""
    import glob
    import os

    if os.path.isdir(arg):
        packs = [os.path.join(arg, "pak01_dir.vpk")]
        packs.extend(sorted(glob.glob(os.path.join(arg, "pak01_[0-9][0-9][0-9].vpk"))))
        return [p for p in packs if os.path.isfile(p)]
    return [arg]


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    needle = argv[1].encode("ascii")
    packs = []
    for arg in argv[2:]:
        packs.extend(expand(arg))
    hits = 0
    for pack in packs:
        try:
            counts = find_in_pack(pack, needle)
        except OSError as exc:
            print("SKIP %s (%s)" % (pack, exc))
            continue
        for count in counts:
            if count:
                print("%s  (%d hit(s))" % (pack, count))
                hits += count
    print("total hits: %d" % hits)
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
