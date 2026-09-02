#!/usr/bin/env python3
"""Pure-stdlib VPK v1/v2 directory-tree reader.

Why this exists: `vpkeditcli --file-tree` only draws a tree on this machine and
does not print full in-pack paths, so locating a single file needs a real parse.

Layout
------
VPK v1 header (12 bytes):  signature(4) version(4) treeSize(4)
VPK v2 header (28 bytes):  signature(4) version(4) treeSize(4)
                           fileDataSectionSize(4) archiveMD5SectionSize(4)
                           otherMD5SectionSize(4) signatureSectionSize(4)

Tree starts right after the header and is a three-level nesting of NUL-
terminated strings:  extension -> path -> filename.  Each level is terminated by
an empty string.  Every filename is followed by an 18-byte entry
(extra 4-byte "ext4" field is present only when archiveIndex == 0x7fff in some
v2 packs; we read it defensively when version >= 2)::

    crc(4) preloadBytes(2) archiveIndex(2) entryOffset(4) entryLength(4) term(2)

Usage
-----
    python vpk_list.py <pack.vpk> [needle]      # needle = case-insensitive substring
"""
import struct
import sys

SIGNATURE = 0x55AA1234
ENTRY_SIZE = 18
ARCHIVE_DIR_PACK = 0x7FFF


def read_header(path):
    with open(path, "rb") as fh:
        blob = fh.read(28)
    if len(blob) < 12:
        raise ValueError("file too small to be a VPK: %s" % path)
    signature, version, tree_size = struct.unpack("<III", blob[:12])
    if signature != SIGNATURE:
        raise ValueError("bad VPK signature 0x%08x in %s" % (signature, path))
    if version not in (1, 2):
        raise ValueError("unsupported VPK version %d in %s" % (version, path))
    header_size = 12 if version == 1 else 28
    if len(blob) < header_size:
        blob += b"\x00" * (header_size - len(blob))
    return version, tree_size, header_size


def parse_tree(path):
    """Yield (full_path, crc, preload_bytes, archive_index, entry_offset, entry_length)."""
    version, tree_size, header_size = read_header(path)
    with open(path, "rb") as fh:
        fh.seek(header_size)
        blob = fh.read(tree_size)
    pos = 0
    size = len(blob)

    def read_cstr():
        nonlocal pos
        end = blob.index(b"\x00", pos)
        text = blob[pos:end].decode("ascii", "replace")
        pos = end + 1
        return text

    while True:
        ext = read_cstr()
        if not ext:
            break  # end of extension list
        while True:
            directory = read_cstr()
            if not directory:
                break  # end of path list for this extension
            prefix = directory + "/" if directory else ""
            while True:
                filename = read_cstr()
                if not filename:
                    break  # end of file list for this path
                entry = blob[pos:pos + ENTRY_SIZE]
                if len(entry) < ENTRY_SIZE:
                    return
                crc, preload, archive_index, entry_offset, entry_length = struct.unpack(
                    "<IHHII", entry[:16]
                )
                pos += ENTRY_SIZE
                # In v2 packs an entry living in the directory pack carries an
                # extra 4-byte field before the preload data.
                if version >= 2 and archive_index == ARCHIVE_DIR_PACK:
                    pos += 4
                pos += preload
                yield (
                    "%s%s.%s" % (prefix, filename, ext),
                    crc,
                    preload,
                    archive_index,
                    entry_offset,
                    entry_length,
                )
    if pos > size:
        raise ValueError("tree parse overran by %d bytes" % (pos - size))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    pack = argv[1]
    needle = (argv[2] if len(argv) > 2 else "").lower()
    count = 0
    for full, crc, preload, archive, offset, length in parse_tree(pack):
        if needle and needle not in full.lower():
            continue
        print(
            "%-64s crc=%08x preload=%-5d archive=%-5d offset=%-12d length=%d"
            % (full, crc, preload, archive, offset, length)
        )
        count += 1
    print("matched: %d" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
