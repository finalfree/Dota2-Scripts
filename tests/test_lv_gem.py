"""Static resource integration checks; run with Python's standard library.

Lua behavior is tested separately by test_lv_gem.lua.  These checks do not
prove engine loading or in-game behavior.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / "pak01_dir"


def read_kv(path):
    # Keep pairs so repeated keys can be checked rather than silently overwritten.
    token_re = re.compile(r'//[^\n]*|"((?:\\.|[^"\\])*)"|([{}])|([^\s"{}]+)')
    tokens = []
    for match in token_re.finditer(path.read_text(encoding="utf-8-sig")):
        if not match.group().startswith("//"):
            tokens.append(next(value for value in match.groups() if value is not None))
    cursor = 0

    def block(nested=False):
        nonlocal cursor
        result = []
        while cursor < len(tokens):
            key = tokens[cursor]
            cursor += 1
            if key == "}":
                if not nested:
                    raise ValueError("unexpected closing brace")
                return result
            if key == "{" or cursor >= len(tokens):
                raise ValueError("missing key/value")
            value = tokens[cursor]
            cursor += 1
            if value == "}":
                raise ValueError("missing value")
            result.append((key, block(True) if value == "{" else value))
        if nested:
            raise ValueError("unclosed block")
        return result

    return block()


class ItemResources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.custom_pairs = dict(read_kv(RESOURCE / "scripts/npc/lv/lv_items.txt"))["DOTAAbilities"]
        cls.custom = dict(cls.custom_pairs)
        cls.item = dict(cls.custom["item_lv_gem"])
        cls.recipe = dict(cls.custom["item_recipe_lv_gem"])
        cls.manifest = {
            line.strip() for line in (ROOT / "packaging/items.txt").read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        }

    def test_unique_names_keys_and_ids(self):
        def unique(pairs):
            self.assertEqual(len(pairs), len(dict(pairs)), "duplicate KV key")
            for _, value in pairs:
                if isinstance(value, list):
                    unique(value)
        unique(self.custom_pairs)
        ids = [dict(value)["ID"] for _, value in self.custom_pairs if isinstance(value, list)]
        self.assertEqual(len(ids), len(set(ids)))
        for filename in ("items.txt", "npc_abilities.txt", "npc_ability_ids.txt"):
            roots = dict(read_kv(RESOURCE / "scripts/npc" / filename))
            for pairs in roots.values():
                if not isinstance(pairs, list):
                    continue
                for name, value in pairs:
                    self.assertNotIn(name, ("item_lv_gem", "item_recipe_lv_gem",
                                            "item_lv_octarine_core", "item_recipe_lv_octarine_core"))
                    if isinstance(value, list):
                        fields = dict(value)
                        self.assertNotIn(fields.get("ID"), ids)
                        self.assertNotIn(fields.get("id"), ids)

    def test_recipe_and_total_price(self):
        official = dict(dict(read_kv(RESOURCE / "scripts/npc/items.txt"))["DOTAAbilities"])
        self.assertEqual(self.recipe["ItemResult"], "item_lv_gem")
        self.assertEqual(dict(self.recipe["ItemRequirements"]), {"01": "item_gem"})
        self.assertEqual(int(self.item["ItemCost"]),
                         int(self.recipe["ItemCost"]) + int(dict(official["item_gem"])["ItemCost"]))

    def test_passive_callbacks_and_packaged_dependencies(self):
        self.assertEqual(self.item["AbilityBehavior"], "DOTA_ABILITY_BEHAVIOR_PASSIVE")
        pending = dict(dict(self.item["Modifiers"])["modifier_item_lv_gem_pending"])
        self.assertEqual(pending["Passive"], "1")
        self.assertGreater(float(pending["ThinkInterval"]), 0)
        for event in ("OnCreated", "OnIntervalThink"):
            callback = dict(dict(pending[event])["RunScript"])
            path = callback["ScriptFile"]
            self.assertIn(path, self.manifest)
            source = (RESOURCE / path).read_text()
            self.assertIn("function " + callback["Function"] + "(keys)", source)
        self.assertIn("scripts/vscripts/lv/modifier_lv_gem_consumed.lua", self.manifest)
        for path in self.manifest:
            self.assertTrue((RESOURCE / path).is_file(), path)
        entry = (RESOURCE / "scripts/npc/npc_abilities.txt").read_text(encoding="utf-8-sig")
        self.assertIn('#base "lv/lv_items.txt"', entry)

    def test_matching_localization_without_duplicate_keys(self):
        localized = []
        for language in ("english", "schinese"):
            root = dict(read_kv(RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            gem = [(key.lower(), value) for key, value in pairs if "lv_gem" in key.lower()]
            self.assertEqual(len(gem), len(dict(gem)))
            self.assertTrue(all(value for _, value in gem))
            localized.append(dict(gem))
        self.assertEqual(localized[0].keys(), localized[1].keys())
        self.assertIn("dota_tooltip_modifier_lv_gem_consumed_description", localized[0])
        self.assertIn("%radius%", localized[0]["dota_tooltip_ability_item_lv_gem_description"])

    def test_octarine_recipe_and_preserved_stats(self):
        item = dict(self.custom["item_lv_octarine_core"])
        recipe = dict(self.custom["item_recipe_lv_octarine_core"])
        official = dict(dict(read_kv(RESOURCE / "scripts/npc/items.txt"))["DOTAAbilities"])
        self.assertEqual(recipe["ItemCost"], "1000")
        self.assertEqual(recipe["ItemResult"], "item_lv_octarine_core")
        self.assertEqual(dict(recipe["ItemRequirements"]), {"01": "item_octarine_core"})
        self.assertEqual(int(item["ItemCost"]),
                         int(recipe["ItemCost"]) + int(dict(official["item_octarine_core"])["ItemCost"]))
        self.assertEqual(dict(item["AbilityValues"]), {
            "bonus_cooldown": "80", "bonus_health": "450", "bonus_mana": "450",
            "bonus_health_regen": "0", "bonus_mana_regen": "20", "cast_range_bonus": "600",
        })

    def test_octarine_uses_engine_properties_and_native_range_modifier(self):
        item = dict(self.custom["item_lv_octarine_core"])
        self.assertEqual(item["BaseClass"], "item_datadriven")
        self.assertEqual(item["AbilityBehavior"], "DOTA_ABILITY_BEHAVIOR_PASSIVE")
        bridge = dict(dict(item["Modifiers"])["modifier_item_lv_octarine_core"])
        self.assertEqual(bridge["Passive"], "1")
        self.assertEqual(bridge["RemoveOnDeath"], "0")
        self.assertNotIn("ThinkInterval", bridge)
        self.assertEqual(dict(bridge["Properties"]), {
            "MODIFIER_PROPERTY_HEALTH_BONUS": "%bonus_health",
            "MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT": "%bonus_health_regen",
            "MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE": "%bonus_cooldown",
        })
        for event, function in (("OnCreated", "LVOctarineApplyNativeRange"),
                                ("OnDestroy", "LVOctarineRemoveNativeRange")):
            callback = dict(dict(bridge[event])["RunScript"])
            self.assertEqual(callback["Function"], function)
            self.assertIn(callback["ScriptFile"], self.manifest)
            source = (RESOURCE / callback["ScriptFile"]).read_text()
            self.assertIn("function " + function + "(keys)", source)
        source = (RESOURCE / "scripts/vscripts/lv/item_lv_octarine_core.lua").read_text()
        self.assertIn('NATIVE_RANGE_MODIFIER = "modifier_item_aether_lens"', source)
        self.assertIn("AddNewModifier", source)
        self.assertNotIn("SetContextThink", source)
        self.assertNotIn("SendBuffRefreshToClients", source)
        self.assertNotIn("scripts/vscripts/lv/modifier_lv_octarine_core.lua", self.manifest)
        self.assertNotIn("scripts/npc/npc_units.txt", self.manifest)

    def test_octarine_localization_matches_special_value(self):
        localized = []
        for language in ("english", "schinese"):
            root = dict(read_kv(RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            octarine = [(key.lower(), value) for key, value in pairs if "lv_octarine_core" in key.lower()]
            self.assertEqual(len(octarine), len(dict(octarine)))
            localized.append(dict(octarine))
            prefix = "dota_tooltip_ability_item_lv_octarine_core_"
            self.assertEqual(localized[-1][prefix + "cast_range_bonus"], "+$cast_range")
            self.assertIn("%cast_range_bonus%", localized[-1][prefix + "description"])
        self.assertEqual(localized[0].keys(), localized[1].keys())


if __name__ == "__main__":
    unittest.main(verbosity=2)
