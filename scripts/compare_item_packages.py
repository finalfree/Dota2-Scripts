"""Compare legacy item packages by effective NPC/localization data and raw assets."""
import argparse
from pathlib import Path, PurePosixPath
import struct
import zlib
from kv_tools import parse, tokens


def read_package(path):
    blob = Path(path).read_bytes()
    if len(blob) < 12:
        raise ValueError('Truncated VPK')
    magic, version, size = struct.unpack_from('<III', blob)
    if (magic, version) != (0x55aa1234, 1) or 12 + size > len(blob):
        raise ValueError('Expected VPK v1')
    end, pos, files = 12 + size, 12, {}
    def string():
        nonlocal pos
        stop = blob.index(b'\0', pos, end)
        value = blob[pos:stop].decode('utf-8')
        pos = stop + 1
        return value
    while extension := string():
        while directory := string():
            while name := string():
                crc, preload, archive, offset, length, term = struct.unpack_from('<IHHIIH', blob, pos)
                pos += 18
                if archive != 0x7fff or term != 0xffff or end + offset + length > len(blob) or pos + preload > end:
                    raise ValueError('Invalid single-file payload')
                data = blob[pos:pos+preload] + blob[end+offset:end+offset+length]
                pos += preload
                if zlib.crc32(data) & 0xffffffff != crc:
                    raise ValueError('CRC mismatch')
                path = ('' if directory == ' ' else directory + '/') + name + ('' if extension == ' ' else '.' + extension)
                if path in files:
                    raise ValueError('Duplicate VPK path')
                files[path] = data
    if pos != end:
        raise ValueError('Unexpected tree end')
    return files


def npc(files, path='scripts/npc/items.txt', stack=()):
    if path in stack:
        raise ValueError('Cyclic NPC includes')
    found = {}
    for key, value in parse(files[path].decode('utf-8-sig')):
        if key == '#base':
            added = npc(files, str(PurePosixPath(path).parent / value), (*stack, path))
        elif key == 'DOTAAbilities':
            added = dict(value)
        else:
            continue
        for name, fields in added.items():
            if name in found and name != 'Version':
                raise ValueError(f'Duplicate NPC definition: {name}')
            found[name] = fields
    return found


def compare(before, after):
    old, new = read_package(before), read_package(after)
    # Known migrations: private ability split, then two standard-file archive aliases.
    # Effective NPC equality below is mandatory even for these changed paths.
    npc_layout_paths = {'scripts/npc/lv/lv_items.txt', 'scripts/npc/lv/lv_upgrades.txt',
                        'scripts/npc/lv/lv_abilities.txt', 'scripts/npc/overforged_items.txt',
                        'scripts/npc/overforged_abilities.txt'}
    if (set(old) ^ set(new)) - npc_layout_paths:
        raise ValueError('Unexpected package file-set change')
    if npc(old) != npc(new):
        changed = set(npc(old)) ^ set(npc(new))
        changed |= {k for k in npc(old) if k in npc(new) and npc(old)[k] != npc(new)[k]}
        raise ValueError(f'NPC content changed: {changed}')
    counts = {}
    for lang in ('english', 'schinese'):
        path = f'resource/localization/abilities_{lang}.txt'
        first = {k.lower(): v for k, v in tokens(old[path].decode('utf-8-sig'))}
        second = {k.lower(): v for k, v in tokens(new[path].decode('utf-8-sig'))}
        if first != second:
            raise ValueError(f'Effective localization changed: {lang}')
        counts[lang] = len(second)
    adapted = npc_layout_paths | {'scripts/npc/items.txt',
               'resource/localization/abilities_english.txt', 'resource/localization/abilities_schinese.txt'}
    for path in set(old) - adapted:
        if old[path] != new[path]:
            raise ValueError(f'Unchanged asset differs: {path}')
    print(f'Equivalent NPC data; all effective localization tokens match ({counts}).')
    print(f'{len(set(old) - adapted)} unaffected payloads are byte-identical; only known NPC layout paths may differ.')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('before')
    p.add_argument('after')
    args = p.parse_args()
    compare(args.before, args.after)
