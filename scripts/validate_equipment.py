"""Validate equipment structure and references, not balance values or recipe prices."""
from pathlib import Path
import re

from kv_tools import read, tokens
from project_paths import BASELINE


def unique(pairs, context):
    keys = [key for key, _ in pairs]
    if len(keys) != len(set(keys)):
        raise ValueError(f'Duplicate KV key: {context}')
    for key, value in pairs:
        if isinstance(value, list):
            unique(value, f'{context}/{key}')


def validate_equipment(root):
    root = Path(root).resolve()
    official = {}
    for name in ('items.txt', 'npc_abilities.txt', 'npc_ability_ids.txt'):
        for _, entries in read(BASELINE / 'scripts/npc' / name):
            if isinstance(entries, list):
                official.update((key, value) for key, value in entries if isinstance(value, list))
    official_ids = {str(value) for fields in official.values() for key, value in fields
                    if key.lower() == 'id' and isinstance(value, str)}
    definitions = {}
    identifiers = set()
    for path in sorted((root / 'scripts/npc').glob('npc_*_custom.txt')):
        pairs = read(path)
        unique(pairs, str(path))
        entries = dict(pairs).get('DOTAAbilities')
        if not isinstance(entries, list):
            raise ValueError(f'Missing DOTAAbilities: {path}')
        for name, fields in entries:
            if not isinstance(fields, list):
                continue
            if name in definitions:
                raise ValueError(f'Duplicate definition: {name}')
            data = dict(fields)
            identifier = data.get('ID', '')
            if not identifier.isdigit() or int(identifier) <= 0:
                raise ValueError(f'Invalid ID: {name}')
            if identifier in identifiers or identifier in official_ids:
                raise ValueError(f'Duplicate/colliding ID: {name}')
            identifiers.add(identifier)
            definitions[name] = data
        for script in re.findall(r'"ScriptFile"\s*"([^"]+)"', path.read_text(encoding='utf-8-sig')):
            resolved = (root / script).resolve()
            if not resolved.is_relative_to(root) or not resolved.is_file():
                raise ValueError(f'Missing/unsafe script: {script}')
    if not definitions:
        raise ValueError('No equipment definitions')
    known = set(official) | set(definitions)
    for name, data in definitions.items():
        if 'ItemResult' in data and data['ItemResult'] not in known:
            raise ValueError(f'Unknown recipe result: {name}')
        for _, route in data.get('ItemRequirements', []):
            if not isinstance(route, str):
                raise ValueError(f'Invalid recipe route: {name}')
            for component in re.findall(r'item_[A-Za-z0-9_]+', route):
                if component not in known:
                    raise ValueError(f'Unknown recipe component: {component}')
    locales = []
    for language in ('english', 'schinese'):
        pairs = tokens((root / f'resource/addon_{language}.txt').read_text(encoding='utf-8-sig'))
        keys = [key.lower() for key, _ in pairs]
        if len(keys) != len(set(keys)):
            raise ValueError('Duplicate localization key')
        locales.append(set(keys))
    if locales[0] != locales[1]:
        raise ValueError('Localization keys do not match')
    shop = root / 'scripts/shops.txt'
    if shop.exists():
        for _, items in dict(read(shop))['dota_shops']:
            for _, name in items:
                if name not in known:
                    raise ValueError(f'Unknown shop item: {name}')
    return len(definitions)
