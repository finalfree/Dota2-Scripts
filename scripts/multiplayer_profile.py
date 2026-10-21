"""Independent multiplayer sources; merge the shop fragment with Valve's shop."""
from kv_tools import read, render
from project_paths import BASELINE, ROOT

MULTIPLAYER_GAME = ROOT / 'game/dota_addons/overforged_multiplayer'


def shop_definition():
    shops = read(BASELINE / 'scripts/shops.txt')
    categories = dict(dict(shops)['dota_shops'])
    additions = dict(read(MULTIPLAYER_GAME / 'scripts/shops.txt'))['dota_shops']
    for category, items in additions:
        if category not in categories:
            raise ValueError(f'Unknown multiplayer shop category: {category}')
        categories[category].extend(items)
    return render(shops) + '\n'
