"""Extract original item icons for the static website; never edits or launches Dota."""
import argparse
import json
from pathlib import Path
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'website/dist'
sys.path.insert(0, str(ROOT / 'scripts'))
from icon_tool import png_write, vtex_read
from vpk_list import parse_tree, ARCHIVE_DIR_PACK
from vpk_extract import dir_pack_data_start, shard_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_vpk', type=Path)
    args = parser.parse_args()
    data = json.loads((DIST / 'data.js').read_text(encoding='utf-8').removeprefix('window.OVERFORGED_DATA = ').rstrip(';\n'))
    icons = sorted({item['icon'] for section in data.values() for item in section if item['icon'].startswith('assets/items/')})
    entries = {entry[0]: entry for entry in parse_tree(str(args.source_vpk))}
    manifest = []
    scratch = ROOT / 'bin/website-icons'
    scratch.mkdir(parents=True, exist_ok=True)
    for icon in icons:
        source_path = f'panorama/images/items/{Path(icon).stem}_png.vtex_c'
        _, crc, preload, archive, offset, length = entries[source_path]
        if preload:
            raise ValueError(f'Unexpected preload bytes: {source_path}')
        source_file = str(args.source_vpk) if archive == ARCHIVE_DIR_PACK else shard_path(str(args.source_vpk), archive)
        if archive == ARCHIVE_DIR_PACK:
            offset += dir_pack_data_start(str(args.source_vpk))
        with open(source_file, 'rb') as source:
            source.seek(offset)
            blob = source.read(length)
        assert len(blob) == length and zlib.crc32(blob) & 0xffffffff == crc, source_path
        structural_size, _, _, block_offset, block_count = struct.unpack_from('<IHHII', blob)
        for index in range(block_count):
            pos = 8 + block_offset + 12 * index
            if blob[pos:pos + 4] == b'DATA':
                header = pos + 4 + struct.unpack_from('<I', blob, pos + 4)[0]
                break
        else:
            raise ValueError(f'Missing DATA block: {source_path}')
        width, height, depth, format_id, mips = struct.unpack_from('<HHHBB', blob, header + 20)
        if format_id == 28 and mips == 1:
            pixels = bytearray(blob[structural_size:])
            assert len(pixels) == width * height * 4
            for index in range(0, len(pixels), 4):
                pixels[index], pixels[index + 2] = pixels[index + 2], pixels[index]
        else:
            compiled = scratch / (Path(icon).stem + '.vtex_c')
            compiled.write_bytes(blob)
            width, height, pixels, _ = vtex_read(str(compiled))
        output = DIST / icon
        output.parent.mkdir(parents=True, exist_ok=True)
        png_write(str(output), width, height, pixels)
        manifest.append({'file': icon, 'source': source_path, 'source_crc32': f'{crc:08x}', 'width': width, 'height': height})
    (ROOT / 'website/reference/item-icons.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Extracted {len(icons)} original icons, all source CRCs verified.')


if __name__ == '__main__':
    main()
