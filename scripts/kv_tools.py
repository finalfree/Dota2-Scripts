"""Small, strict KeyValues reader used by the two distribution targets.

Values retain their escaped spelling; render() does not reinterpret backslashes.
Pairs (rather than dicts) preserve duplicate keys and source order for validation.
"""
from pathlib import Path
import re

TOKEN = re.compile(r'\s+|//[^\n]*|/\*[\s\S]*?\*/|"((?:\\.|[^"\\])*)"|([{}])|([^\s"{}]+)')


def parse(text):
    tokens = []
    end = 0
    for match in TOKEN.finditer(text.lstrip('\ufeff')):
        if match.start() != end:
            raise ValueError('Invalid KeyValues syntax')
        end = match.end()
        if match.group().isspace() or match.group().startswith(('//', '/*')):
            continue
        tokens.append(next(v for v in match.groups() if v is not None))
    if end != len(text.lstrip('\ufeff')):
        raise ValueError('Unterminated KeyValues string')
    index = 0

    def block(nested=False):
        nonlocal index
        pairs = []
        while index < len(tokens):
            key = tokens[index]
            index += 1
            if key == '}':
                if not nested:
                    raise ValueError('Unexpected closing brace')
                return pairs
            if key == '{' or index == len(tokens):
                raise ValueError('Missing KeyValues value')
            value = tokens[index]
            index += 1
            if value == '}':
                raise ValueError('Missing KeyValues value')
            pairs.append((key, block(True) if value == '{' else value))
        if nested:
            raise ValueError('Unclosed KeyValues block')
        return pairs

    return block()


def read(path):
    return parse(Path(path).read_text(encoding='utf-8-sig'))


def render(pairs, indent=0):
    lines = []
    pad = '\t' * indent
    for key, value in pairs:
        if isinstance(value, list):
            lines.extend([f'{pad}"{key}"', pad + '{', render(value, indent + 1), pad + '}'])
        else:
            lines.append(f'{pad}"{key}"\t\t"{value}"')
    return '\n'.join(lines)


def tokens(text):
    return dict(dict(parse(text))['lang'])['Tokens']


def is_lv_token(key):
    return bool(re.search(r'item_(?:recipe_)?lv_|modifier_lv_|ability_lv_', key, re.I))


def token_close(text):
    """Locate the Tokens closing brace without counting braces inside strings."""
    found = False
    depth = 0
    for match in TOKEN.finditer(text.lstrip('\ufeff')):
        word, brace, bare = match.groups()
        if not found:
            if word and word.lower() == 'tokens':
                found = True
            continue
        if brace == '{':
            depth += 1
        elif brace == '}':
            depth -= 1
            if depth == 0:
                return match.start() + (1 if text.startswith('\ufeff') else 0)
    raise ValueError('No complete Tokens block')


def merge_localization(baseline, addon):
    """Add LV tokens only, failing on duplicates/collisions. Preserve baseline text."""
    base_pairs = tokens(baseline)
    addon_pairs = [(k, v) for k, v in tokens(addon) if is_lv_token(k)]
    if not addon_pairs:
        raise ValueError('No LV localization tokens')
    occupied = {k.lower() for k, _ in base_pairs}
    for key, value in addon_pairs:
        if not isinstance(value, str) or key.lower() in occupied:
            raise ValueError(f'Duplicate/colliding localization token: {key}')
        occupied.add(key.lower())
    close = token_close(baseline)
    addition = '\n\t\t// Generated from Workshop addon; do not edit this output.\n'
    addition += render(addon_pairs, 2) + '\n\t'
    return baseline[:close] + addition + baseline[close:]
