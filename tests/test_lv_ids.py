"""Ability/item ID uniqueness gate; run with Python's standard library.

A duplicated `"ID"` in a shipped npc KV file makes Dota 2 abort at startup with
`FATAL ERROR: Encountered N errors generating AbilityIDs!`. Packing, CRC and
payload checks all pass happily in that state, so it has to be checked here.

This is a static gate only. It proves nothing about in-game behaviour.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / "pak01_dir"

# Custom content lives above the official range (npc_ability_ids.txt tops out
# at 9999) so that an engine update can never collide with us.
MIN_CUSTOM_ID = 10001
MAX_CUSTOM_ID = 10199

CUSTOM_FILES = (
    "scripts/npc/lv/lv_items.txt",
    "scripts/npc/lv/lv_upgrades.txt",
)


def ability_entries(path):
    """Yield (name, id) for every top-level block in a DOTAAbilities file.

    Imported lazily so this module also works when run directly.
    """
    from test_item_resources import read_kv

    root = dict(read_kv(path))["DOTAAbilities"]
    for name, block in root:
        if not isinstance(block, list):
            continue
        ids = [value for key, value in block if key == "ID"]
        yield name, ids


class AbilityIds(unittest.TestCase):
    def collect(self):
        seen = {}
        for relative in CUSTOM_FILES:
            for name, ids in ability_entries(RESOURCE / relative):
                seen.setdefault(name, []).extend((relative, value) for value in ids)
        return seen

    def test_parser_finds_entries_and_ids(self):
        # A silent parser regression would make every other check vacuous.
        total = 0
        for relative in CUSTOM_FILES:
            entries = list(ability_entries(RESOURCE / relative))
            self.assertTrue(entries, "no ability blocks parsed from %s" % relative)
            self.assertTrue(all(ids for _, ids in entries),
                            "block without an ID in %s" % relative)
            total += len(entries)
        self.assertGreater(total, 50)

    def test_ids_are_unique(self):
        by_id = {}
        for name, entries in self.collect().items():
            for relative, value in entries:
                by_id.setdefault(value, []).append((relative, name))
        duplicates = {key: value for key, value in by_id.items() if len(value) > 1}
        self.assertEqual({}, duplicates,
                         "duplicate ability IDs crash the game at startup")

    def test_ability_names_are_unique(self):
        by_name = {}
        for name, entries in self.collect().items():
            by_name.setdefault(name, []).extend(entries)
        duplicates = {key: value for key, value in by_name.items() if len(value) > 1}
        self.assertEqual({}, duplicates, "duplicate ability names")

    def test_each_block_has_exactly_one_id(self):
        for name, entries in self.collect().items():
            self.assertEqual(1, len(entries), "%s has %d ID entries" % (name, len(entries)))

    def test_ids_stay_in_the_custom_range(self):
        for name, entries in self.collect().items():
            for _, value in entries:
                self.assertTrue(value.isdigit(), "%s has a non-numeric ID %r" % (name, value))
                identifier = int(value)
                self.assertTrue(
                    MIN_CUSTOM_ID <= identifier <= MAX_CUSTOM_ID,
                    "%s ID %s is outside the custom range %d-%d"
                    % (name, value, MIN_CUSTOM_ID, MAX_CUSTOM_ID))

    def test_no_collision_with_official_ability_ids(self):
        text = (RESOURCE / "scripts/npc/npc_ability_ids.txt").read_text(encoding="utf-8-sig")
        official = set()
        for line in text.splitlines():
            parts = line.split('"')
            if len(parts) >= 4 and parts[3].isdigit():
                official.add(int(parts[3]))
        self.assertTrue(official, "no official IDs parsed")
        self.assertLessEqual(max(official), MIN_CUSTOM_ID - 1)
        for name, entries in self.collect().items():
            for _, value in entries:
                self.assertNotIn(int(value), official,
                                 "%s reuses official ID %s" % (name, value))


if __name__ == "__main__":
    unittest.main(verbosity=2)
