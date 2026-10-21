"""Generate ONLY legacy entry/localization files; shared resources are read in place."""
import argparse
import json
from pathlib import Path

from project_paths import ROOT, GAME, BASELINE, LV_DEFINITIONS, VPK_NPC_SOURCES
from kv_tools import merge_localization, read
from validate_addon import validate


def manifest_paths(path):
    paths = [s.strip() for s in Path(path).read_text(encoding='utf-8-sig').splitlines()
             if s.strip() and not s.lstrip().startswith('#')]
    seen = set()
    for value in paths:
        p = value.replace('\\', '/')
        if (p.startswith('/') or any(c in p for c in ':*?"<>|[]') or
                any(part in ('', '.', '..') for part in p.split('/'))):
            raise ValueError(f'Invalid manifest path: {value}')
        if p.lower() in seen:
            raise ValueError(f'Duplicate manifest path: {value}')
        seen.add(p.lower())
    if not paths:
        raise ValueError('Empty manifest')
    return [p.replace('\\', '/') for p in paths]


def prepare(output, manifest=ROOT / 'packaging/items.txt', all_files=False, profile='standard'):
    if profile == 'standard':
        validate()
    output = Path(output).resolve()
    if not output.is_relative_to(ROOT / 'bin'):
        raise ValueError('Generated adapters must be inside this repository bin directory')
    output.mkdir(parents=True, exist_ok=True)
    if output.is_symlink():
        raise ValueError('Generated adapter directory must not be a link')
    entries = manifest_paths(manifest)
    multiplayer = profile == 'multiplayer'
    if multiplayer:
        from multiplayer_profile import MULTIPLAYER_GAME
    source_root = MULTIPLAYER_GAME if multiplayer else GAME
    if multiplayer:
        from validate_equipment import validate_equipment
        validate_equipment(source_root)
    if multiplayer and all_files:
        raise ValueError('Multiplayer profile does not support full baseline packaging')
    npc_sources = {'scripts/npc/overforged_items.txt': 'scripts/npc/npc_items_custom.txt'} if multiplayer else VPK_NPC_SOURCES
    if all_files:
        entries = sorted(set(entries) | {
            p.relative_to(BASELINE).as_posix() for p in BASELINE.rglob('*')
            if p.is_file() and not p.name.startswith('.vpkedit-')})
    sources = {}
    for entry in entries:
        if entry in LV_DEFINITIONS or entry in ('addoninfo.txt', 'scripts/vscripts/addon_game_mode.lua'):
            raise ValueError(f'Addon entrypoint is not a legacy VPK payload: {entry}')
        candidate = source_root / npc_sources.get(entry, entry)
        if entry == 'scripts/npc/items.txt':
            baseline = (BASELINE / entry).read_text(encoding='utf-8-sig')
            if any(k == '#base' and ('lv/' in v or 'overforged' in v or '_custom' in v)
                   for k, v in read(BASELINE / entry)):
                raise ValueError('Baseline items.txt still contains LV overrides')
            candidate = output / entry
            candidate.parent.mkdir(parents=True, exist_ok=True)
            bases = ''.join(f'#base "{p.removeprefix("scripts/npc/")}"\n'
                            for p in npc_sources)
            candidate.write_text(bases + '\n' + baseline, encoding='utf-8', newline='\n')
        elif entry == 'scripts/shops.txt' and (source_root / entry).is_file():
            from merge_shops import merge_shops
            candidate = output / entry
            candidate.parent.mkdir(parents=True, exist_ok=True)
            candidate.write_text(merge_shops(BASELINE / entry, source_root / entry),
                                 encoding='utf-8', newline='\n')
        elif entry.startswith('resource/localization/abilities_'):
            lang = Path(entry).stem.removeprefix('abilities_')
            addon = source_root / f'resource/addon_{lang}.txt'
            candidate = output / entry
            candidate.parent.mkdir(parents=True, exist_ok=True)
            merged = merge_localization((BASELINE / entry).read_text(encoding='utf-8-sig'),
                                        addon.read_text(encoding='utf-8-sig'))
            candidate.write_text(merged, encoding='utf-8-sig', newline='\n')
        elif not candidate.is_file():
            if multiplayer:
                raise ValueError(f'Missing independent multiplayer source: {entry}')
            candidate = BASELINE / entry
        if not candidate.is_file():
            raise ValueError(f'Missing source for {entry}')
        sources[entry] = str(candidate.resolve())
    # Dependencies must not silently fall out of a user-supplied manifest.
    if 'scripts/npc/items.txt' in sources:
        for entry in npc_sources:
            if entry not in sources:
                raise ValueError(f'Missing generated items.txt dependency: {entry}')
    (output / 'file-map.json').write_text(json.dumps(sources, indent=2), encoding='utf-8')
    return sources


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'packaging/items.txt')
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--profile', choices=('standard', 'multiplayer'), default='standard')
    args = parser.parse_args()
    files = prepare(args.output, args.manifest, args.all, args.profile)
    print(f'Prepared {len(files)} source mappings; shared Lua/KV/textures were not copied.')
