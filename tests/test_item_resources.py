"""Equipment source legality checks; balance values are intentionally not frozen."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from kv_tools import read as read_kv
from validate_equipment import validate_equipment


class ItemResources(unittest.TestCase):
    def test_singleplayer_sources_are_legal(self):
        validate_equipment(ROOT / 'game/dota_addons/overforged')

    def test_multiplayer_sources_are_legal(self):
        validate_equipment(ROOT / 'game/dota_addons/overforged_multiplayer')


if __name__ == '__main__':
    unittest.main()
