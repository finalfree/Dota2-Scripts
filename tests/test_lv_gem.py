"""Static resource integration checks; run with Python's standard library.

Lua behavior is tested separately by test_lv_gem.lua.  These checks do not
prove engine loading or in-game behavior.
"""
from pathlib import Path
import hashlib
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
        modifiers = dict(self.item["Modifiers"])
        pending = dict(modifiers["modifier_item_lv_gem_pending"])
        status = dict(modifiers["modifier_item_lv_gem_consumed_status"])
        self.assertEqual(pending["Passive"], "1")
        self.assertGreater(float(pending["ThinkInterval"]), 0)
        self.assertEqual(status, {
            "IsHidden": "0", "IsDebuff": "0", "IsPurgable": "0",
            "RemoveOnDeath": "0",
        })
        for event in ("OnCreated", "OnIntervalThink"):
            callback = dict(dict(pending[event])["RunScript"])
            path = callback["ScriptFile"]
            self.assertIn(path, self.manifest)
            source = (RESOURCE / path).read_text()
            self.assertIn("function " + callback["Function"] + "(keys)", source)
        self.assertNotIn("scripts/vscripts/lv/modifier_lv_gem_consumed.lua", self.manifest)
        self.assertFalse((RESOURCE / "scripts/vscripts/lv/modifier_lv_gem_consumed.lua").exists())
        source = (RESOURCE / "scripts/vscripts/lv/item_lv_gem.lua").read_text()
        self.assertIn('TRUESIGHT = "modifier_truesight"', source)
        self.assertIn('"npc_spawned"', source)
        self.assertIn('"npc_replaced"', source)
        self.assertIn("FIND_UNITS_EVERYWHERE", source)
        self.assertIn("AUDIT_INTERVAL = 2.0", source)
        self.assertIn('CONSUMED_STATUS = "modifier_item_lv_gem_consumed_status"', source)
        self.assertIn("ApplyDataDrivenModifier", source)
        self.assertIn("hero:TakeItem(item)", source)
        self.assertNotIn("hero:RemoveItem(item)", source)
        self.assertNotIn("UTIL_Remove(item)", source)
        self.assertNotIn("LinkLuaModifier", source)
        self.assertNotIn("modifier_lv_gem_consumed", source)
        for path in self.manifest:
            self.assertTrue((RESOURCE / path).is_file(), path)
        entry = (RESOURCE / "scripts/npc/items.txt").read_text(encoding="utf-8-sig")
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
        self.assertNotIn("dota_tooltip_modifier_lv_gem_consumed_description", localized[0])
        status_key = "dota_tooltip_modifier_item_lv_gem_consumed_status"
        self.assertIn(status_key, localized[0])
        self.assertIn(status_key + "_description", localized[0])
        self.assertIn("全地图", localized[1][status_key + "_description"])
        self.assertNotIn("%radius%", localized[0]["dota_tooltip_ability_item_lv_gem_description"])
        self.assertIn("全地图", localized[1]["dota_tooltip_ability_item_lv_gem_description"])

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

    def test_trident_is_hand_maintained_in_lv_items(self):
        lv_items = dict(read_kv(RESOURCE / "scripts/npc/lv/lv_items.txt"))["DOTAAbilities"]
        custom = dict(lv_items)
        self.assertIn("item_lv_trident", custom)
        self.assertIn("item_recipe_lv_trident", custom)
        trident = dict(custom["item_lv_trident"])
        recipe = dict(custom["item_recipe_lv_trident"])
        values = dict(trident["AbilityValues"])
        controller = dict(dict(trident["Modifiers"])["modifier_item_lv_trident_controller"])
        properties = dict(controller["Properties"])
        states = dict(controller["States"])
        self.assertEqual(values["pure_damage_attack"], "100")
        self.assertEqual(values["stackable_attack_range"], "200")
        self.assertEqual(values["bonus_attack_speed"], "100")
        self.assertNotIn("bonus_damage", values)
        self.assertNotIn("magic_damage_attack", values)
        self.assertNotIn("MODIFIER_PROPERTY_PROCATTACK_BONUS_DAMAGE_PURE", properties)
        self.assertEqual(controller["Attributes"], "MODIFIER_ATTRIBUTE_MULTIPLE")
        self.assertEqual(properties["MODIFIER_PROPERTY_ATTACK_RANGE_BONUS"],
                         "%stackable_attack_range")
        self.assertEqual(states["MODIFIER_STATE_CANNOT_MISS"],
                         "MODIFIER_STATE_VALUE_ENABLED")
        callback = dict(dict(controller["OnAttackLanded"])["RunScript"])
        self.assertEqual(callback["Function"], "LVTridentApplyPureAttackDamage")
        self.assertIn(callback["ScriptFile"], self.manifest)
        source = (RESOURCE / callback["ScriptFile"]).read_text()
        self.assertIn("function LVTridentApplyPureAttackDamage(keys)", source)
        self.assertIn("ApplyDamage({", source)
        self.assertIn("damage_type = DAMAGE_TYPE_PURE", source)
        self.assertNotIn("DOTA_DAMAGE_FLAG_", source)
        self.assertNotIn("IsIllusion", source)
        self.assertNotIn("IsBuilding", source)
        self.assertNotIn("modifier_monkey_king_fur_army_soldier", source)
        self.assertEqual(trident["ItemCost"], "11301")
        self.assertEqual(recipe["ItemCost"], "1")
        self.assertEqual(dict(recipe["ItemRequirements"]), {
            "01": "item_kaya;item_sange;item_yasha;item_monkey_king_bar;",
            "02": "item_kaya_and_sange;item_yasha;item_monkey_king_bar;",
            "03": "item_sange_and_yasha;item_kaya;item_monkey_king_bar;",
            "04": "item_yasha_and_kaya;item_sange;item_monkey_king_bar;",
        })
        upgrades = (RESOURCE / "scripts/npc/lv/lv_upgrades.txt").read_text(encoding="utf-8-sig")
        self.assertNotIn('"item_lv_trident"', upgrades)
        self.assertNotIn('"item_lv_monkey_king_bar"', upgrades)
        self.assertNotIn('"item_recipe_lv_monkey_king_bar"', upgrades)
        manifest = (ROOT / "scripts/item_upgrades.json").read_text(encoding="utf-8")
        self.assertNotIn('"item_trident"', manifest)
        self.assertNotIn('"item_monkey_king_bar"', manifest)
        generator = (ROOT / "scripts/gen_item_upgrades.py").read_text(encoding="utf-8")
        self.assertNotIn("def gen_trident", generator)
        self.assertIn("'item_trident'", generator)
        self.assertIn("'item_monkey_king_bar'", generator)

    def test_butterfly_daedalus_fusion_values_recipe_and_lua(self):
        item = dict(self.custom["item_lv_butterfly_crit"])
        recipe = dict(self.custom["item_recipe_lv_butterfly_crit"])
        values = dict(item["AbilityValues"])
        self.assertEqual(item["ID"], "10102")
        self.assertEqual(recipe["ID"], "10101")
        self.assertEqual(item["BaseClass"], "item_datadriven")
        self.assertEqual(item["AbilityTextureName"], "item_lv_butterfly_crit")
        self.assertEqual(item["ItemCost"], "10551")
        self.assertEqual(values, {
            "bonus_agility": "100",
            "bonus_attack_speed_pct": "30",
            "bonus_damage": "188",
            "butterfly_bonus_damage": "150",
            "bonus_evasion": "85",
            "crit_chance": "100",
            "crit_multiplier": "300",
        })
        self.assertEqual(recipe["ItemCost"], "1")
        self.assertEqual(recipe["ItemResult"], "item_lv_butterfly_crit")
        self.assertEqual(dict(recipe["ItemRequirements"]), {
            "01": "item_butterfly;item_greater_crit;",
        })

        controller = dict(dict(item["Modifiers"])[
            "modifier_item_lv_butterfly_crit_controller"])
        self.assertEqual(controller["Attributes"], "MODIFIER_ATTRIBUTE_MULTIPLE")
        self.assertEqual(dict(controller["Properties"]), {
            "MODIFIER_PROPERTY_STATS_AGILITY_BONUS": "%bonus_agility",
            "MODIFIER_PROPERTY_ATTACKSPEED_PERCENTAGE": "%bonus_attack_speed_pct",
            "MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE": "%butterfly_bonus_damage",
            "MODIFIER_PROPERTY_EVASION_CONSTANT": "%bonus_evasion",
        })
        callbacks = {
            event: dict(dict(controller[event])["RunScript"])
            for event in ("OnCreated", "OnDestroy")
        }
        self.assertEqual(callbacks["OnCreated"]["Function"],
                         "LVButterflyCritApplyModifier")
        self.assertEqual(callbacks["OnDestroy"]["Function"],
                         "LVButterflyCritRemoveModifier")
        source_path = callbacks["OnCreated"]["ScriptFile"]
        self.assertIn(source_path, self.manifest)
        source = (RESOURCE / source_path).read_text(encoding="utf-8")
        self.assertIn('NATIVE_CRIT_MODIFIER = "modifier_item_greater_crit"', source)
        self.assertIn("AddNewModifier", source)
        self.assertNotIn("LinkLuaModifier", source)
        self.assertNotIn("modifier_item_lv_butterfly_crit_effect", source)
        self.assertNotIn("class({})", source)
        self.assertTrue((ROOT / "artwork/item-icons/item_lv_butterfly_crit.png").is_file())
        self.assertTrue((ROOT / "artwork/item-icons/lv_butterfly_crit.png").is_file())
        texture = "panorama/images/items/lv_butterfly_crit_png.vtex_c"
        self.assertIn(texture, self.manifest)
        compiled_texture = (RESOURCE / texture).read_bytes()
        self.assertEqual(len(compiled_texture), 7748)
        self.assertEqual(
            hashlib.sha256(compiled_texture).hexdigest(),
            "a8337dec323fdc937278dbed91b7e007e1702f9c7f30502f0fb4112440572218")
        self.assertNotIn(
            "resource/flash3/images/items/item_lv_butterfly_crit.png",
            self.manifest)
        self.assertFalse((RESOURCE /
                          "resource/flash3/images/items/item_lv_butterfly_crit.png").exists())

    def test_replaced_butterfly_and_daedalus_upgrades_are_reserved(self):
        upgrades = (RESOURCE / "scripts/npc/lv/lv_upgrades.txt").read_text(
            encoding="utf-8-sig")
        manifest = (ROOT / "scripts/item_upgrades.json").read_text(encoding="utf-8")
        generator = (ROOT / "scripts/gen_item_upgrades.py").read_text(encoding="utf-8")
        for name in ("item_butterfly", "item_greater_crit"):
            self.assertNotIn(f'"item_lv_{name[5:]}"', upgrades)
            self.assertNotIn(f'"{name}"', manifest)
            self.assertIn(repr(name), generator)

        for language in ("english", "schinese"):
            root = dict(read_kv(RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            localized = [(key.lower(), value) for key, value in pairs
                         if "item_lv_butterfly_crit" in key.lower()]
            self.assertEqual(len(localized), len(dict(localized)))
            self.assertTrue(localized)
            self.assertFalse(any(
                "item_lv_butterfly" in key.lower()
                and "item_lv_butterfly_crit" not in key.lower()
                or "item_lv_greater_crit" in key.lower()
                for key, _ in pairs))

    def test_removed_monkey_king_bar_upgrade_has_no_localization(self):
        for language in ("english", "schinese"):
            root = dict(read_kv(RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            self.assertFalse(any("item_lv_monkey_king_bar" in key.lower()
                                 or "item_recipe_lv_monkey_king_bar" in key.lower()
                                 for key, _ in pairs))


if __name__ == "__main__":
    unittest.main(verbosity=2)
