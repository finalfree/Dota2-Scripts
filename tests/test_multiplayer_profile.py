"""Verify the playable profile excludes unrelated equipment and its dependencies."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from project_paths import ROOT, GAME
from kv_tools import read, tokens
from prepare_vpk import prepare
from multiplayer_profile import MULTIPLAYER_GAME
from unittest.mock import patch


class MultiplayerProfileTests(unittest.TestCase):
    def setUp(self):
        # CI starts from a clean checkout; ignored build directories do not exist.
        (ROOT / 'bin').mkdir(exist_ok=True)

    def test_isolated_package(self):
        original = (GAME / 'scripts/npc/npc_items_custom.txt').read_bytes()
        with tempfile.TemporaryDirectory(dir=ROOT / 'bin') as folder:
            sources = prepare(folder, ROOT / 'packaging/multiplayer.txt', profile='multiplayer')
            definitions = dict(dict(read(sources['scripts/npc/overforged_items.txt']))['DOTAAbilities'])
            self.assertTrue(any(isinstance(value, list) for value in definitions.values()))
            shops = dict(dict(read(sources['scripts/shops.txt']))['dota_shops'])
            self.assertIn(('item', 'item_lv_gem'), shops['consumables'])
            entry = Path(sources['scripts/npc/items.txt']).read_text(encoding='utf-8')
            self.assertIn('#base "overforged_items.txt"', entry)
            self.assertNotIn('overforged_abilities', entry)
            for lang in ('english', 'schinese'):
                localized = tokens(Path(sources[f'resource/localization/abilities_{lang}.txt']).read_text(encoding='utf-8-sig'))
                custom = [(k, v) for k, v in localized if 'lv_' in k.lower()]
                self.assertTrue(custom)
                self.assertTrue(all('item_lv_gem' in k.lower() for k, _ in custom))
            self.assertEqual(Path(sources['scripts/vscripts/lv/item_lv_gem.lua']).resolve(),
                             (MULTIPLAYER_GAME / 'scripts/vscripts/lv/item_lv_gem.lua').resolve())
            self.assertEqual(Path(sources['scripts/npc/overforged_items.txt']).resolve(),
                             (MULTIPLAYER_GAME / 'scripts/npc/npc_items_custom.txt').resolve())
        self.assertEqual((GAME / 'scripts/npc/npc_items_custom.txt').read_bytes(), original)

    def test_build_does_not_read_singleplayer_sources(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'bin') as folder:
            with patch('prepare_vpk.GAME', ROOT / 'missing-singleplayer'), patch('prepare_vpk.validate', side_effect=AssertionError('singleplayer validation')):
                prepare(folder, ROOT / 'packaging/multiplayer.txt', profile='multiplayer')


if __name__ == '__main__':
    unittest.main()
