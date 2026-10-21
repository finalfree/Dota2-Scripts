"""Merge hand-maintained addon shop additions into an official/third-party shop."""
import argparse
from pathlib import Path
from kv_tools import read, render


def merge_shops(baseline, additions):
    shops = read(baseline)
    categories = dict(dict(shops)['dota_shops'])
    for category, items in dict(read(additions))['dota_shops']:
        if category not in categories:
            raise ValueError(f'Unknown shop category: {category}')
        for item in items:
            if item not in categories[category]:
                categories[category].append(item)
    return render(shops) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('additions', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_text(merge_shops(args.baseline, args.additions), encoding='utf-8')
