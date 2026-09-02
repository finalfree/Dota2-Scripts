"""Static item-resource integration checks; run with Python's standard library.

Gem Lua behavior is tested separately by test_lv_gem.lua.  These checks do not
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
            "6578ae2f1b2ff8feb5acdc2cb9f6f94cc663c59a6646034885ddf64f4a630698")
        self.assertNotIn(
            "resource/flash3/images/items/item_lv_butterfly_crit.png",
            self.manifest)
        self.assertFalse((RESOURCE /
                          "resource/flash3/images/items/item_lv_butterfly_crit.png").exists())

    def test_satanic_heart_fusion_values_recipe_and_lua(self):
        item = dict(self.custom["item_lv_satanic_heart"])
        recipe = dict(self.custom["item_recipe_lv_satanic_heart"])
        values = dict(item["AbilityValues"])
        self.assertEqual(item["ID"], "10104")
        self.assertEqual(recipe["ID"], "10103")
        self.assertEqual(item["BaseClass"], "item_datadriven")
        self.assertEqual(item["AbilityTextureName"], "item_lv_satanic_heart")
        self.assertEqual(item["ItemCost"], "10251")
        self.assertEqual(item["AbilityCooldown"], "5.0")
        # bonus_strength is read by BOTH modifier_item_heart and
        # modifier_item_satanic, so 75 is granted twice.
        self.assertEqual(values, {
            "bonus_strength": "75",
            "bonus_damage": "25",
            "lifesteal_percent": "30",
            "hp_regen": "2",
            "missing_health_regen": "1.5",
            "unholy_lifesteal_percent": "145",
            "unholy_lifesteal_total_tooltip": "175",
            "unholy_duration": "6.0",
        })
        self.assertEqual(recipe["ItemCost"], "1")
        self.assertEqual(recipe["ItemResult"], "item_lv_satanic_heart")
        self.assertEqual(dict(recipe["ItemRequirements"]), {
            "01": "item_satanic;item_heart;",
        })

        controller = dict(dict(item["Modifiers"])[
            "modifier_item_lv_satanic_heart_controller"])
        self.assertEqual(controller["Attributes"], "MODIFIER_ATTRIBUTE_MULTIPLE")
        self.assertNotIn("Properties", controller)
        callbacks = {
            event: dict(dict(controller[event])["RunScript"])
            for event in ("OnCreated", "OnDestroy")
        }
        self.assertEqual(callbacks["OnCreated"]["Function"],
                         "LVSatanicHeartApplyModifiers")
        self.assertEqual(callbacks["OnDestroy"]["Function"],
                         "LVSatanicHeartRemoveModifiers")
        spell = dict(dict(item["OnSpellStart"])["RunScript"])
        self.assertEqual(spell["Function"], "LVSatanicHeartUnholyRage")

        source_path = callbacks["OnCreated"]["ScriptFile"]
        self.assertEqual(source_path, spell["ScriptFile"])
        self.assertIn(source_path, self.manifest)
        source = (RESOURCE / source_path).read_text(encoding="utf-8")
        for native in ("modifier_item_satanic", "modifier_item_heart",
                       "modifier_item_satanic_unholy"):
            self.assertIn('"%s"' % native, source)
        self.assertIn("AddNewModifier", source)
        self.assertIn("duration", source)

        # Vanilla Satanic's C++ OnSpellStart also applies a basic dispel and
        # plays a sound. item_datadriven never runs that C++, so the Lua has to
        # redo both.
        self.assertIn("DOTA_Item.Satanic.Activate", source)
        purge = re.search(r"hero:Purge\(([^)]*)\)", source)
        self.assertIsNotNone(purge, "Unholy Rage must apply a basic dispel")
        # Exact argument list, not just a substring: the outdated signature
        # (bool, bool, handle, float, bool) would put 0 in slot 4, and 0 is
        # truthy in Lua, which would turn a basic dispel into one that also
        # purges stuns.
        self.assertEqual([a.strip() for a in purge.group(1).split(",")],
                         ["false", "true", "false", "false", "false"])

        # The dispel/sound helpers must actually be CALLED from OnSpellStart.
        # Checking the whole file is not enough -- leaving the helper defined but
        # uncalled would still satisfy every assert above.
        body = source.split("function LVSatanicHeartUnholyRage", 1)[1]
        body = body.split("\nend", 1)[0]
        self.assertIn("basic_dispel(hero)", body, "dispel is never called")
        self.assertIn("EmitSound", body, "sound is never played")
        self.assertIn("AddNewModifier", body)
        self.assertLess(body.index("basic_dispel(hero)"),
                        body.index("AddNewModifier"),
                        "dispel must fire before the buff, as vanilla does")

        self.assertNotIn("LinkLuaModifier", source)
        self.assertNotIn("modifier_item_lv_satanic_heart_effect", source)
        self.assertNotIn("class({})", source)
        self.assertTrue((ROOT / "artwork/item-icons/item_lv_satanic_heart.png").is_file())
        self.assertTrue((ROOT / "artwork/item-icons/lv_satanic_heart.png").is_file())
        texture = "panorama/images/items/lv_satanic_heart_png.vtex_c"
        self.assertIn(texture, self.manifest)
        compiled_texture = (RESOURCE / texture).read_bytes()
        self.assertEqual(len(compiled_texture), 7748)
        self.assertEqual(
            hashlib.sha256(compiled_texture).hexdigest(),
            "028f3c6cdf3ac700d761c32aec58bc064d3246b893f3d1d60ce9225d62874228")

    def test_abyssal_skadi_fusion_values_recipe_and_lua(self):
        item = dict(self.custom["item_lv_abyssal_skadi"])
        recipe = dict(self.custom["item_recipe_lv_abyssal_skadi"])
        values = dict(item["AbilityValues"])

        self.assertEqual(item["ID"], "10108")
        self.assertEqual(recipe["ID"], "10107")
        self.assertEqual(item["BaseClass"], "item_datadriven")
        self.assertEqual(item["AbilityTextureName"], "item_lv_abyssal_skadi")
        self.assertEqual(item["AbilityBehavior"], "DOTA_ABILITY_BEHAVIOR_UNIT_TARGET")
        self.assertEqual(item["AbilityCooldown"], "15")
        self.assertEqual(item["AbilityManaCost"], "5")
        self.assertEqual(item["ItemCost"], "12151")
        self.assertEqual(values, {
            "bonus_damage": "105",
            # Skadi supplies +100 Strength through bonus_all_stats. The native
            # Abyssal modifier must not add its old +56 Strength on top.
            "bonus_strength": "0",
            "slow_resistance": "100",
            "hp_regen_amp": "20",
            "bash_chance_melee": "25",
            "bash_chance_ranged": "25",
            "bash_duration": "1.2",
            "bash_cooldown": "0",
            "bonus_chance_damage": "120",
            "bonus_all_stats": "100",
            "bonus_health": "0",
            "bonus_mana": "0",
            "cold_slow_melee": "-25",
            "cold_attack_slow_melee": "-25",
            "cold_slow_ranged": "-50",
            "cold_attack_slow_ranged": "-25",
            "cold_duration": "3.0",
            "restoration_reduction": "50",
            "stun_duration": "1.6",
        })
        self.assertEqual(recipe["ItemCost"], "1")
        self.assertEqual(recipe["ItemResult"], "item_lv_abyssal_skadi")
        self.assertEqual(dict(recipe["ItemRequirements"]), {
            "01": "item_abyssal_blade;item_skadi;",
        })

        controller = dict(dict(item["Modifiers"])[
            "modifier_item_lv_abyssal_skadi_controller"])
        self.assertEqual(controller["Attributes"], "MODIFIER_ATTRIBUTE_MULTIPLE")
        self.assertNotIn("Properties", controller)
        callbacks = {
            event: dict(dict(controller[event])["RunScript"])
            for event in ("OnCreated", "OnDestroy")
        }
        self.assertEqual(callbacks["OnCreated"]["Function"],
                         "LVAbyssalSkadiApplyModifiers")
        self.assertEqual(callbacks["OnDestroy"]["Function"],
                         "LVAbyssalSkadiRemoveModifiers")
        spell = dict(dict(item["OnSpellStart"])["RunScript"])
        self.assertEqual(spell["Function"], "LVAbyssalSkadiOverwhelm")
        self.assertEqual(spell["ScriptFile"], callbacks["OnCreated"]["ScriptFile"])

        source_path = spell["ScriptFile"]
        self.assertIn(source_path, self.manifest)
        source = (RESOURCE / source_path).read_text(encoding="utf-8")
        for native in ("modifier_item_abyssal_blade", "modifier_item_skadi",
                       "modifier_bashed"):
            self.assertIn('"%s"' % native, source)
        self.assertIn("TriggerSpellAbsorb", source)
        self.assertIn("DOTA_Item.AbyssalBlade.Activate", source)
        self.assertIn("particles/items_fx/abyssal_blink_start.vpcf", source)
        self.assertIn("particles/items_fx/abyssal_blade.vpcf", source)
        self.assertNotIn("LinkLuaModifier", source)
        self.assertNotIn("class({})", source)

        self.assertTrue((ROOT / "artwork/item-icons/item_lv_abyssal_skadi.png").is_file())
        self.assertTrue((ROOT / "artwork/item-icons/lv_abyssal_skadi.png").is_file())
        texture = "panorama/images/items/lv_abyssal_skadi_png.vtex_c"
        self.assertIn(texture, self.manifest)
        compiled_texture = RESOURCE / texture
        self.assertTrue(compiled_texture.is_file())
        self.assertEqual(compiled_texture.stat().st_size, 7748)
        self.assertEqual(
            hashlib.sha256(compiled_texture.read_bytes()).hexdigest(),
            "0f8644a1ed923e2ca50ded0e7799d297076f95e1334a8bb3e6d038e7751e3c96")

        localized = []
        for language in ("english", "schinese"):
            root = dict(read_kv(
                RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            fusion = [(key.lower(), value) for key, value in pairs
                      if "item_lv_abyssal_skadi" in key.lower()]
            self.assertEqual(len(fusion), len(dict(fusion)))
            self.assertTrue(all(value for _, value in fusion))
            localized.append(dict(fusion))
        self.assertEqual(localized[0].keys(), localized[1].keys())

    def test_replaced_abyssal_and_skadi_upgrades_are_reserved(self):
        upgrades = (RESOURCE / "scripts/npc/lv/lv_upgrades.txt").read_text(
            encoding="utf-8-sig")
        manifest = (ROOT / "scripts/item_upgrades.json").read_text(encoding="utf-8")
        generator = (ROOT / "scripts/gen_item_upgrades.py").read_text(encoding="utf-8")
        for name in ("item_abyssal_blade", "item_skadi"):
            short = name[5:]
            self.assertNotIn(f'"item_lv_{short}"', upgrades)
            self.assertNotIn(f'"item_recipe_lv_{short}"', upgrades)
            self.assertNotIn(f'"{name}"', manifest)
            self.assertIn(repr(name), generator)

        for language in ("english", "schinese"):
            root = dict(read_kv(
                RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            stale = [key for key, _ in pairs
                     if "item_lv_abyssal_blade" in key.lower()
                     or "item_recipe_lv_abyssal_blade" in key.lower()
                     or "item_lv_skadi" in key.lower()
                     or "item_recipe_lv_skadi" in key.lower()]
            self.assertEqual([], stale)

    def test_consumable_zero_cooldown_mirror_shield(self):
        item = dict(self.custom["item_lv_mirror_shield"])
        recipe = dict(self.custom["item_recipe_lv_mirror_shield"])
        official = dict(dict(read_kv(
            RESOURCE / "scripts/npc/items.txt"))["DOTAAbilities"])

        self.assertEqual(item["ID"], "10106")
        self.assertEqual(recipe["ID"], "10105")
        self.assertEqual(item["BaseClass"], "item_datadriven")
        self.assertEqual(item["AbilityTextureName"], "item_mirror_shield")
        self.assertEqual(item["AbilityBehavior"], "DOTA_ABILITY_BEHAVIOR_PASSIVE")
        self.assertEqual(dict(item["AbilityValues"]), {
            "reflect_chance": "100",
            "block_cooldown": "0",
        })
        self.assertEqual(recipe["ItemCost"], "1")
        self.assertEqual(recipe["ItemResult"], "item_lv_mirror_shield")
        self.assertEqual(dict(recipe["ItemRequirements"]), {
            "01": "item_sphere;item_lotus_orb;",
        })
        material_cost = sum(int(dict(official[name])["ItemCost"])
                            for name in ("item_sphere", "item_lotus_orb"))
        self.assertEqual(int(item["ItemCost"]), material_cost + 1)

        modifiers = dict(item["Modifiers"])
        pending = dict(modifiers["modifier_item_lv_mirror_shield_pending"])
        status = dict(modifiers[
            "modifier_item_lv_mirror_shield_consumed_status"])
        self.assertEqual(status, {
            "IsHidden": "0", "IsDebuff": "0", "IsPurgable": "0",
            "RemoveOnDeath": "0",
        })
        self.assertEqual(pending["Passive"], "1")
        self.assertGreater(float(pending["ThinkInterval"]), 0)
        callbacks = {
            event: dict(dict(pending[event])["RunScript"])
            for event in ("OnCreated", "OnIntervalThink")
        }
        self.assertEqual(callbacks["OnCreated"], callbacks["OnIntervalThink"])
        self.assertEqual(callbacks["OnCreated"]["Function"],
                         "LVMirrorShieldTryAbsorb")
        source_path = callbacks["OnCreated"]["ScriptFile"]
        self.assertIn(source_path, self.manifest)
        source = (RESOURCE / source_path).read_text(encoding="utf-8")
        self.assertIn('NATIVE_MODIFIER = "modifier_item_mirror_shield"', source)
        self.assertIn("hero:AddNewModifier", source)
        self.assertIn("hero:TakeItem(item)", source)
        self.assertIn("ApplyDataDrivenModifier", source)
        self.assertIn("state.items[hero:entindex()] = item", source)
        self.assertNotIn("hero:RemoveItem(item)", source)
        self.assertNotIn("UTIL_Remove(item)", source)
        self.assertNotIn("LinkLuaModifier", source)
        self.assertNotIn("class({})", source)

        localized = []
        for language in ("english", "schinese"):
            root = dict(read_kv(
                RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            mirror = [(key.lower(), value) for key, value in pairs
                      if "lv_mirror_shield" in key.lower()]
            self.assertEqual(len(mirror), len(dict(mirror)))
            self.assertTrue(all(value for _, value in mirror))
            localized.append(dict(mirror))
        self.assertEqual(localized[0].keys(), localized[1].keys())
        status_key = "dota_tooltip_modifier_item_lv_mirror_shield_consumed_status"
        self.assertIn(status_key, localized[0])
        self.assertIn(status_key + "_description", localized[0])
        self.assertIn("没有冷却时间", localized[1][status_key + "_description"])

    def test_private_dragon_splash_consumable(self):
        item = dict(self.custom["item_lv_dragon_splash"])
        recipe = dict(self.custom["item_recipe_lv_dragon_splash"])
        skill = dict(self.custom["lv_black_dragon_splash_attack"])
        official = dict(dict(read_kv(
            RESOURCE / "scripts/npc/items.txt"))["DOTAAbilities"])

        self.assertEqual(item["ID"], "10110")
        self.assertEqual(recipe["ID"], "10109")
        self.assertEqual(skill["ID"], "10111")
        self.assertEqual(item["BaseClass"], "item_datadriven")
        self.assertEqual(recipe["ItemResult"], "item_lv_dragon_splash")
        self.assertEqual(dict(recipe["ItemRequirements"]), {
            "01": "item_bfury",
            "02": "item_specialists_array",
        })
        self.assertEqual(recipe["ItemCost"], "100")
        self.assertEqual(int(item["ItemCost"]),
                         int(recipe["ItemCost"]) + int(dict(official["item_bfury"])["ItemCost"]))
        self.assertEqual(dict(dict(item["AbilityValues"])["range"])["value"], "500")
        self.assertEqual(dict(dict(skill["AbilityValues"])["range"])["value"], "500")
        self.assertEqual(dict(skill["AbilityValues"])["damage_percent"], "100")
        for values in (dict(item["AbilityValues"]), dict(skill["AbilityValues"])):
            self.assertEqual(values["bonus_damage"], "50")
            self.assertEqual(values["bonus_health_regen"], "10")
            self.assertEqual(values["bonus_mana_regen"], "5")
        self.assertEqual(item["AbilityTextureName"], "item_lv_dragon_splash")
        self.assertEqual(skill["AbilityTextureName"], "item_lv_dragon_splash")
        texture = "panorama/images/items/lv_dragon_splash_png.vtex_c"
        self.assertIn(texture, self.manifest)
        compiled_texture = RESOURCE / texture
        self.assertTrue(compiled_texture.is_file())
        self.assertEqual(compiled_texture.stat().st_size, 7748)
        self.assertEqual(
            hashlib.sha256(compiled_texture.read_bytes()).hexdigest(),
            "e2c0ba64be8aeb091614828e489ba903425206e865637a0eec43d41091d3f76f",
        )
        self.assertTrue((ROOT / "artwork/item-icons/item_lv_dragon_splash.png").is_file())
        self.assertTrue((ROOT / "artwork/item-icons/lv_dragon_splash.png").is_file())

        modifiers = dict(item["Modifiers"])
        pending = dict(modifiers["modifier_item_lv_dragon_splash_pending"])
        status = dict(modifiers["modifier_lv_black_dragon_splash_status"])
        self.assertEqual(status["IsHidden"], "0")
        self.assertEqual(status["ThinkInterval"], "0.25")
        restore_callback = dict(dict(status["OnIntervalThink"])["RunScript"])
        self.assertEqual(restore_callback["Function"], "LVDragonSplashEnsureActive")
        self.assertIn(restore_callback["ScriptFile"], self.manifest)
        self.assertEqual(dict(status["Properties"]), {
            "MODIFIER_PROPERTY_PREATTACK_BONUS_DAMAGE": "%bonus_damage",
            "MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT": "%bonus_health_regen",
            "MODIFIER_PROPERTY_MANA_REGEN_CONSTANT": "%bonus_mana_regen",
        })
        self.assertEqual(pending["Passive"], "1")
        self.assertGreater(float(pending["ThinkInterval"]), 0)
        callback = dict(dict(pending["OnCreated"])["RunScript"])
        self.assertEqual(callback["Function"], "LVDragonSplashTryAbsorb")
        self.assertIn(callback["ScriptFile"], self.manifest)
        source = (RESOURCE / callback["ScriptFile"]).read_text(encoding="utf-8")
        self.assertIn('SKILL_NAME = "lv_black_dragon_splash_attack"', source)
        self.assertIn('NATIVE_MODIFIER = "modifier_black_dragon_splash_attack"', source)
        self.assertIn("function LVDragonSplashEnsureActive(keys)", source)
        self.assertIn("hero:IsAlive()", source)
        self.assertIn("hero:AddAbility", source)
        self.assertIn("hero:AddNewModifier", source)
        self.assertIn("hero:TakeItem(item)", source)
        self.assertNotIn("LinkLuaModifier", source)
        self.assertNotIn("scripts/npc/npc_abilities.txt", self.manifest)

        for language in ("english", "schinese"):
            root = dict(read_kv(
                RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            localized = dict(pairs)
            for key in (
                "DOTA_Tooltip_Ability_item_lv_dragon_splash",
                "DOTA_Tooltip_Ability_item_recipe_lv_dragon_splash",
                "DOTA_Tooltip_ability_item_lv_dragon_splash_Description",
                "DOTA_Tooltip_modifier_lv_black_dragon_splash_status",
                "DOTA_Tooltip_modifier_lv_black_dragon_splash_status_Description",
            ):
                self.assertTrue(localized.get(key), (language, key))

    def test_old_bfury_upgrade_is_removed(self):
        upgrades = (RESOURCE / "scripts/npc/lv/lv_upgrades.txt").read_text(
            encoding="utf-8-sig")
        self.assertNotIn('"item_lv_bfury"', upgrades)
        self.assertNotIn('"item_recipe_lv_bfury"', upgrades)

        upgrade_manifest = (ROOT / "scripts/item_upgrades.json").read_text(
            encoding="utf-8")
        self.assertNotIn('"item_bfury"', upgrade_manifest)
        generator = (ROOT / "scripts/gen_item_upgrades.py").read_text(
            encoding="utf-8")
        self.assertIn("'item_bfury'", generator)

        for language in ("english", "schinese"):
            root = dict(read_kv(
                RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            keys = {key for key, _ in pairs}
            self.assertNotIn("DOTA_Tooltip_Ability_item_lv_bfury", keys)
            self.assertNotIn("DOTA_Tooltip_Ability_item_recipe_lv_bfury", keys)

    def test_replaced_satanic_and_heart_upgrades_are_reserved(self):
        upgrades = (RESOURCE / "scripts/npc/lv/lv_upgrades.txt").read_text(
            encoding="utf-8-sig")
        manifest = (ROOT / "scripts/item_upgrades.json").read_text(encoding="utf-8")
        generator = (ROOT / "scripts/gen_item_upgrades.py").read_text(encoding="utf-8")
        for name in ("item_satanic", "item_heart"):
            self.assertNotIn(f'"item_lv_{name[5:]}"', upgrades)
            self.assertNotIn(f'"item_recipe_lv_{name[5:]}"', upgrades)
            self.assertNotIn(f'"{name}"', manifest)
            self.assertIn(repr(name), generator)

        # The fusion item legitimately contains "item_lv_satanic" as a prefix,
        # so the stale-key check has to exclude it.
        stale = re.compile(r"item_(?:recipe_)?lv_(?:satanic|heart)(?!_heart)",
                           re.IGNORECASE)
        for language in ("english", "schinese"):
            root = dict(read_kv(RESOURCE / f"resource/localization/abilities_{language}.txt"))
            pairs = dict(root["lang"])["Tokens"]
            localized = [(key.lower(), value) for key, value in pairs
                         if "item_lv_satanic_heart" in key.lower()]
            self.assertEqual(len(localized), len(dict(localized)))
            self.assertEqual(len(localized), 11)
            self.assertFalse(any(stale.search(key) for key, _ in pairs))

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
