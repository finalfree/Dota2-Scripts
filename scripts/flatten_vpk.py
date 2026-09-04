"""Fold VPKEdit's mapped additions into VPK v1's directory-file data section.

CLI Modify ignores --single-file. This relocates payload bytes, never extracts
resources, preserves raw tree strings/preload, and checks each CRC before writing.
"""
import argparse
from pathlib import Path
import struct
import zlib


def flatten(source, output):
    source, output = Path(source).resolve(), Path(output).resolve()
    if source == output or output.exists():
        raise ValueError('Output must be a new file, distinct from the input')
    with source.open('rb') as src:
        header = src.read(12)
        if len(header) != 12:
            raise ValueError('Truncated VPK header')
        magic, version, size = struct.unpack('<III', header)
        if magic != 0x55AA1234 or version != 1 or size > source.stat().st_size - 12:
            raise ValueError('Expected valid VPK v1 tree')
        tree = bytearray(src.read(size))
        pos, count, offset_out = 0, 0, 0

        def string():
            nonlocal pos
            end = tree.find(0, pos)
            if end < 0:
                raise ValueError('Unterminated tree string')
            word = tree[pos:end]
            pos = end + 1
            return word

        with output.open('xb') as dst:
            dst.write(header)
            dst.write(tree)
            while string():
                while string():
                    while string():
                        if pos + 18 > size:
                            raise ValueError('Truncated entry')
                        crc, preload, archive, offset, length, term = struct.unpack_from('<IHHIIH', tree, pos)
                        if term != 0xffff or pos + 18 + preload > size:
                            raise ValueError('Invalid entry/preload')
                        data_path = source if archive == 0x7fff else source.with_name(
                            source.stem.removesuffix('_dir') + f'_{archive:03d}.vpk')
                        if data_path.is_symlink():
                            raise ValueError('Linked VPK shard is not supported')
                        start = offset + (12 + size if archive == 0x7fff else 0)
                        if start + length > data_path.stat().st_size:
                            raise ValueError('Payload exceeds source bounds')
                        if 12 + size + offset_out + length >= 2**32:
                            raise ValueError('Single-file VPK exceeds 4 GiB')
                        check = zlib.crc32(tree[pos+18:pos+18+preload])
                        with data_path.open('rb') as payload:
                            payload.seek(start)
                            remaining = length
                            while remaining:
                                chunk = payload.read(min(remaining, 1024 * 1024))
                                if not chunk:
                                    raise ValueError('Truncated payload')
                                check = zlib.crc32(chunk, check)
                                dst.write(chunk)
                                remaining -= len(chunk)
                        if check & 0xffffffff != crc:
                            raise ValueError('CRC mismatch while folding VPK')
                        struct.pack_into('<HI', tree, pos + 6, 0x7fff, offset_out)
                        offset_out += length
                        pos += 18 + preload
                        count += 1
            if pos != size:
                raise ValueError('Unexpected tree ending')
            dst.seek(12)
            dst.write(tree)
    print(f'Folded {count} payloads into VPK v1 single file; all CRCs verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    flatten(args.source, args.output)
