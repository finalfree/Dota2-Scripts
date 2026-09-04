from pathlib import Path
import sys
import tempfile
import unittest
import struct
import zlib
import contextlib
import io

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from validate_addon import validate, definitions
from project_paths import GAME, BASELINE, VPK_NPC_SOURCES
from prepare_vpk import prepare, manifest_paths
from kv_tools import parse, tokens, merge_localization
from flatten_vpk import flatten
from compare_item_packages import read_package
import gen_item_localization


class WorkshopLayout(unittest.TestCase):
    def test_static_addon_contract(self):
        count, abilities, keys = validate()
        self.assertGreater(count, 50)
        self.assertEqual(abilities, 1)
        self.assertGreater(keys, 300)

    def test_shared_sources_are_not_staged(self):
        (ROOT / 'bin').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / 'bin') as folder:
            mapping = prepare(Path(folder))
            for path, source in mapping.items():
                if path in VPK_NPC_SOURCES:
                    self.assertEqual(Path(source), GAME / VPK_NPC_SOURCES[path])
                if '/lv/' in path or path.endswith('.vtex_c'):
                    self.assertEqual(Path(source), GAME / path)
            files = {p.relative_to(folder).as_posix() for p in Path(folder).rglob('*') if p.is_file()}
            self.assertEqual(files, {'file-map.json', 'scripts/npc/items.txt',
                'resource/localization/abilities_english.txt', 'resource/localization/abilities_schinese.txt'})
            self.assertNotIn('addoninfo.txt', mapping)
            self.assertNotIn('cfg/lv_test_ap.cfg', mapping)
            self.assertNotIn('scripts/vscripts/lv_mode_probe.lua', mapping)
            self.assertNotIn('scripts/vscripts/lv_standard_rules.lua', mapping)
            self.assertNotIn('scripts/vscripts/lv_log.lua', mapping)
            self.assertNotIn('scripts/vscripts/addon_game_mode.lua', mapping)
            self.assertNotIn('scripts/npc/npc_items_custom.txt', mapping)
            self.assertNotIn('scripts/npc/npc_abilities_custom.txt', mapping)

    def test_standard_npc_files_are_self_contained(self):
        self.assertEqual(GAME.name, 'overforged')
        self.assertFalse((GAME / 'scripts/npc/lv').exists())
        self.assertEqual(len(definitions(GAME / 'scripts/npc/npc_items_custom.txt')), 82)
        self.assertEqual(len(definitions(GAME / 'scripts/npc/npc_abilities_custom.txt')), 1)
        for source in VPK_NPC_SOURCES.values():
            self.assertNotIn('#base', (GAME / source).read_text(encoding='utf-8'))
        for language, title in [('english', 'Overforged'), ('schinese', '超限武装')]:
            pairs = tokens((GAME / f'resource/addon_{language}.txt').read_text(encoding='utf-8'))
            self.assertEqual(dict(pairs)['addon_game_name'], title)

    def test_vpk_rejects_addon_entrypoints(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'bin') as folder:
            path = Path(folder) / 'bad-manifest.txt'
            for entry in VPK_NPC_SOURCES.values():
                path.write_text(entry, encoding='utf-8')
                with self.subTest(entry=entry), self.assertRaisesRegex(ValueError, 'Addon entrypoint'):
                    prepare(Path(folder), path)

    def test_vpk_requires_both_npc_aliases(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'bin') as folder:
            path = Path(folder) / 'bad-manifest.txt'
            path.write_text('scripts/npc/items.txt\nscripts/npc/overforged_items.txt', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'dependency'):
                prepare(Path(folder), path)

    def test_historical_ap_experiment_is_not_default(self):
        cfg = (GAME / 'cfg/lv_test_ap.cfg').read_text(encoding='utf-8')
        commands = [line.strip() for line in cfg.splitlines()
                    if line.strip() and not line.lstrip().startswith('//')]
        self.assertEqual(commands[1:], ['dota_force_gamemode 1',
                                       'dota_launch_custom_game overforged dota'])
        entry = (GAME / 'scripts/vscripts/addon_game_mode.lua').read_text(encoding='utf-8')
        self.assertNotIn('dota_force_gamemode', entry)
        self.assertIn('StandardRules.Apply(mode)', entry)
        self.assertNotIn('lv_test_ap', entry)

    def test_baseline_is_read_only_for_generation(self):
        tracked = list(BASELINE.rglob('*.txt'))
        before = {p: p.read_bytes() for p in tracked}
        with tempfile.TemporaryDirectory(dir=ROOT / 'bin') as folder:
            prepare(Path(folder), all_files=True)
        self.assertTrue(all(p.read_bytes() == content for p, content in before.items()))

    def test_safe_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'manifest.txt'
            for bad in ('../out', '/tmp/a', 'C:/a', 'a/*', 'a//b', 'a\na', ''):
                path.write_text(bad, encoding='utf-8')
                with self.subTest(bad=bad), self.assertRaises(ValueError):
                    manifest_paths(path)

    def test_localization_braces_in_values(self):
        baseline = '"lang" { "Tokens" { "official" "brace } // not a comment" } }'
        addon = '"lang" { "Tokens" { "addon_game_name" "LV" "item_lv_x" "{x}" } }'
        merged = dict(tokens(merge_localization(baseline, addon)))
        self.assertEqual(merged, {'official': 'brace } // not a comment', 'item_lv_x': '{x}'})

    def test_duplicate_localization_fails(self):
        baseline = '"lang" { "Tokens" {} }'
        addon = '"lang" { "Tokens" { "item_lv_x" "a" "ITEM_LV_X" "b" } }'
        with self.assertRaises(ValueError):
            merge_localization(baseline, addon)

    def test_parser_rejects_truncated_values(self):
        for bad in ('"a" {', '"a" "unterminated', '}'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                parse(bad)

    def test_fold_external_with_preload(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'candidate.vpk'
            output = Path(folder) / 'single.vpk'
            preload, payload = b'PRELOAD', b'payload\x00\xff'
            tree = b'vmt\0materials\0example\0' + struct.pack('<IHHIIH',
                zlib.crc32(preload+payload), len(preload), 0, 0, len(payload), 0xffff) + preload + b'\0\0\0'
            source.write_bytes(struct.pack('<III', 0x55aa1234, 1, len(tree)) + tree)
            source.with_name('candidate_000.vpk').write_bytes(payload)
            flatten(source, output)
            self.assertEqual(read_package(output), {'materials/example.vmt': preload+payload})

    def test_fold_rejects_corrupt_chunk(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'candidate.vpk'
            tree = b'txt\0 \0a\0' + struct.pack('<IHHIIH', 0, 0, 0, 0, 3, 0xffff) + b'\0\0\0'
            source.write_bytes(struct.pack('<III', 0x55aa1234, 1, len(tree)) + tree)
            source.with_name('candidate_000.vpk').write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'CRC'):
                flatten(source, Path(folder) / 'out.vpk')

    def test_localization_generator_writes_addon_only_and_is_idempotent(self):
        baseline = BASELINE / 'resource/localization/abilities_english.txt'
        before = baseline.read_bytes()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'addon_english.txt'
            path.write_bytes((GAME / 'resource/addon_english.txt').read_bytes())
            with contextlib.redirect_stdout(io.StringIO()):
                gen_item_localization.process(path, 'english')
                once = path.read_bytes()
                gen_item_localization.process(path, 'english')
            self.assertEqual(once, path.read_bytes())
            keys = [k.lower() for k, _ in tokens(path.read_text(encoding='utf-8-sig'))]
            self.assertEqual(len(keys), len(set(keys)))
        self.assertEqual(before, baseline.read_bytes())


if __name__ == '__main__':
    unittest.main(verbosity=2)
