"""The single NPC source must retain manual edits when regenerating upgrades."""
import contextlib
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import gen_item_upgrades as gen
from kv_tools import parse


class UpgradeGeneration(unittest.TestCase):
    def setUp(self):
        self.source = gen.OUT_FILE.read_text(encoding='utf-8')

    def test_current_manual_and_generated_sections_are_disjoint(self):
        prefix, body, suffix = gen.split_generated(self.source)
        generated = dict(dict(parse('"DOTAAbilities" {\n' + body + '\n}'))['DOTAAbilities'])
        manual = dict(dict(parse(prefix + '\n' + suffix))['DOTAAbilities'])
        self.assertIn('item_lv_trident', manual)
        self.assertIn('item_lv_octarine_core', manual)
        self.assertNotIn('item_lv_trident', generated)
        self.assertEqual(len(generated), len(gen.UPGRADES) * 2)
        self.assertFalse(set(generated) & set(manual))

    def test_replacement_preserves_both_manual_sides_and_line_endings(self):
        for newline in ('\n', '\r\n'):
            text = newline.join(['manual before', '\t' + gen.BEGIN_GENERATED,
                                 'old', '\t' + gen.END_GENERATED, 'manual after'])
            updated = gen.replace_generated(text, 'new\nbody')
            self.assertEqual(updated, text.replace('old', 'new' + newline + 'body'))

    def test_bad_markers_fail_closed(self):
        invalid = ['', self.source.replace(gen.BEGIN_GENERATED, '// missing'),
                   self.source + '\n' + gen.END_GENERATED,
                   gen.END_GENERATED + '\n' + gen.BEGIN_GENERATED]
        for text in invalid:
            with self.subTest(text=text[:30]), self.assertRaises(ValueError):
                gen.replace_generated(text, 'anything')

    def test_full_generation_is_idempotent_and_preserves_manual_bytes(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'bin') as folder:
            output = Path(folder) / 'npc_items_custom.txt'
            output.write_bytes(self.source.encode('utf-8'))
            with patch.object(gen, 'OUT_FILE', output), patch.object(sys, 'argv', ['generator']), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                gen.main()
                first = output.read_bytes()
                gen.main()
                self.assertEqual(first, output.read_bytes())
            prefix, _, suffix = gen.split_generated(first.decode('utf-8'))
            old_prefix, _, old_suffix = gen.split_generated(self.source)
            self.assertEqual((prefix, suffix), (old_prefix, old_suffix))
            pairs = dict(parse(first.decode('utf-8')))['DOTAAbilities']
            self.assertEqual(len([v for _, v in pairs if isinstance(v, list)]), 82)

    def test_partial_write_is_rejected_without_touching_source(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'npc_items_custom.txt'
            output.write_text(self.source, encoding='utf-8')
            before = output.read_bytes()
            with patch.object(gen, 'OUT_FILE', output), \
                    patch.object(sys, 'argv', ['generator', '--item', 'sheepstick']), \
                    contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                gen.main()
            self.assertEqual(before, output.read_bytes())


if __name__ == '__main__':
    unittest.main()
