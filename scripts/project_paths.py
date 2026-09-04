"""Canonical Workshop source roots. pak01_dir is the official baseline only."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
ADDON_NAME = 'overforged'
GAME = ROOT / 'game/dota_addons' / ADDON_NAME
CONTENT = ROOT / 'content/dota_addons' / ADDON_NAME
BASELINE = ROOT / 'pak01_dir'
LV_DEFINITIONS = ('scripts/npc/npc_items_custom.txt',
                  'scripts/npc/npc_abilities_custom.txt')
# Archive aliases prevent the base-game loader from discovering addon entrypoints.
# Both distribution targets read the same files, without staging a second KV copy.
VPK_NPC_SOURCES = json.loads((ROOT / 'packaging/npc-sources.json').read_text(encoding='utf-8'))
