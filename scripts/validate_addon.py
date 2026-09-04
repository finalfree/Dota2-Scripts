"""Offline checks only: this cannot prove map publishing or OpenHyperAI compatibility."""
from pathlib import Path
import re
from project_paths import GAME, BASELINE, CONTENT, LV_DEFINITIONS, VPK_NPC_SOURCES
from kv_tools import read, tokens, is_lv_token


def definitions(entry, stack=()):
    entry = Path(entry).resolve()
    if not entry.is_relative_to(GAME.resolve()) or entry in stack:
        raise ValueError(f'Unsafe or cyclic NPC include: {entry}')
    roots = read(entry)
    found = {}
    for key, value in roots:
        if key == '#base':
            if Path(value).is_absolute() or '..' in Path(value).parts:
                raise ValueError('Unsafe NPC #base')
            added = definitions(entry.parent / value, (*stack, entry))
        elif key == 'DOTAAbilities':
            added = {k: v for k, v in value if isinstance(v, list)}
            if len(added) != sum(isinstance(v, list) for _, v in value):
                raise ValueError('Duplicate definition in NPC file')
        else:
            continue
        collision = set(found) & set(added)
        if collision:
            raise ValueError(f'Duplicate NPC definitions: {collision}')
        found.update(added)
    return found


def validate():
    info = dict(dict(read(GAME / 'addoninfo.txt'))['AddonInfo'])
    assert info['maps'] == 'dota' and info['IsPlayable'] == '1'
    assert dict(info['dota'])['MaxPlayers'] == '10'
    assert (GAME / 'scripts/vscripts/addon_game_mode.lua').is_file()
    items = definitions(GAME / 'scripts/npc/npc_items_custom.txt')
    abilities = definitions(GAME / 'scripts/npc/npc_abilities_custom.txt')
    assert items and abilities and not set(items) & set(abilities)
    assert all(name.startswith('item_') for name in items)
    assert all(not name.startswith('item_') for name in abilities)
    ids = [dict(fields)['ID'] for fields in [*items.values(), *abilities.values()]]
    assert len(ids) == len(set(ids)), 'Duplicate custom IDs'
    assert set(VPK_NPC_SOURCES.values()) == set(LV_DEFINITIONS)
    assert len(VPK_NPC_SOURCES) == 2
    assert not (GAME / 'scripts/npc/lv').exists(), 'Use the two standard NPC files, not split LV copies'
    for relative in LV_DEFINITIONS:
        path = GAME / relative
        assert not any(k == '#base' for k, _ in read(path)), 'Standard NPC files must contain definitions directly'
        for lua in re.findall(r'"ScriptFile"\s*"([^"]+)"', path.read_text(encoding='utf-8-sig')):
            assert (GAME / lua).resolve().is_relative_to(GAME.resolve())
            assert (GAME / lua).is_file(), lua
    keys_by_language = []
    for language in ('english', 'schinese'):
        pairs = tokens((GAME / f'resource/addon_{language}.txt').read_text(encoding='utf-8-sig'))
        keys = [k.lower() for k, _ in pairs]
        assert len(keys) == len(set(keys)), 'Duplicate addon localization keys'
        assert all(is_lv_token(k) or k == 'addon_game_name' for k, _ in pairs)
        keys_by_language.append(set(keys))
        base = (BASELINE / f'resource/localization/abilities_{language}.txt').read_text(encoding='utf-8-sig')
        assert not any(is_lv_token(k) for k, _ in tokens(base)), 'Custom text leaked into baseline'
    assert keys_by_language[0] == keys_by_language[1]
    for root in (GAME, CONTENT):
        assert not any(p.is_symlink() for p in root.rglob('*')), 'Linked source file'
    for texture in (GAME / 'panorama/images/items').glob('*.vtex_c'):
        source = CONTENT / 'panorama/images/items' / texture.name.removesuffix('_c')
        assert source.is_file(), source
        for png in re.findall(r'"m_fileName"\s*"string"\s*"([^"]+)"', source.read_text(encoding='utf-8')):
            assert (CONTENT / png).is_file(), png
    for relative in (*VPK_NPC_SOURCES, 'scripts/npc/items.txt', 'scripts/npc/npc_heroes.txt', 'scripts/shops.txt',
                     'resource/localization/abilities_english.txt', 'scripts/vscripts/bots'):
        assert not (GAME / relative).exists(), 'Forbidden baseline/bot copy in addon: ' + relative
    return len(items), len(abilities), len(keys_by_language[0]) - 1


if __name__ == '__main__':
    items, abilities, keys = validate()
    print(f'Addon static checks passed: {items} items/recipes, {abilities} ability, {keys} LV tokens per language.')
    print('OFFLINE ONLY: this check does not verify automatic bot/FretBots startup or published Workshop compatibility.')
