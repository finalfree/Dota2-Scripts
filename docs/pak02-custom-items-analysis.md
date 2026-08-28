# 天地星 pak02_dir.vpk 自定义物品分析

分析日期：2026-08-27。本记录仅基于用户提供的包和仓库 `main` 官方基线进行静态分析，没有部署或启动游戏验证。

2026-08-28 补记：本项目借鉴其 `#base` 入口后，用户确认本地房间可获取新玲珑心，详见 [实践记录](dota2-custom-items.md#9-显式加载入口最小实验2026-08-28房间中已确认可用)。这是我们自己最小改动的实测，不代表本报告中的天地星整包已由 Agent 实测。本文与其他文档纳入 `main`；参考包和分析产物不是官方资源基线。

## 1. 解包与校验

- 源包：`D:\learning\Dota2-Scripts\pak02_dir.vpk`，19,141,420 字节，VPK v1。
- SHA256：`2e4d405df94b12b070eee5f6c67201f6d7e517c2f9ab0d04443dee51109cd2ef`。
- 完整解包目录：`D:\learning\Dota2-Scripts\bin\pak02-analysis-20260827\extracted`。
- 共 451 个文件，内容合计 19,116,741 字节。VPKEdit 的文件校验通过；独立提取器也逐文件核对了包内 CRC32。
- VPKEdit 全量提取遇到文件名编码错误。独立提取器将不能按 UTF-8 解码的名称按 GB18030 解码，恢复了“待用资源”“旧文件”等名称，文件内容不转码。
- 提取脚本、包含原文件名编码记录的 `manifest.json`、物品结构化结果 `items-analysis.json` 均在上述分析目录的上一级。`unpacked` 是 VPKEdit 失败时留下的不完整目录，**查看内容请使用 `extracted`**。
- 分析当时分支为 `addons`；当轮没有切换分支、修改现有模组文件、执行包内 Lua、重新打包或部署。以上绝对路径记录当时位置，不保证切换分支后源包仍在工作目录。

下文源码路径均以完整解包目录为根，行号对应原样提取的文件。

## 2. 结论：注册、实现、获取是三个不同环节

该包不是简单把装备名称加入商店。它的设计链条是：

```text
覆盖 scripts/npc/npc_abilities.txt
  ├─ #base Fun/Fun_Items.txt   → 新物品定义
  ├─ #base Fun/Fun_Recipe.txt  → 新配方、材料和产物
  └─ #base Fun/Fun_BaseGameMode.txt → 游戏模式初始化及祝福 modifier

物品行为
  ├─ 原生 BaseClass + AbilityValues
  └─ item_datadriven + Modifiers / 事件 / RunScript → Lua

玩家获取
  shops.txt 的“祝福” → 使用道具 → Lua 发放卷轴
  → 购买原版材料 → 按 ItemRequirements / ItemResult 合成新物品

界面显示
  abilities_schinese.txt 新键 + panorama/images/items/ 编译图标
```

按实际 KV 条目统计（排除注释中的规划）：**30 个物品定义、21 个配方定义**。其中物品有 **18 个 `item_datadriven`、12 个原生物品类复用**。不是 30 个全部可买的成品；包括测试工具、AI 道具和未进入正常发放池的条目。

## 3. 注册入口：不是 npc_items_custom.txt

`scripts/npc/npc_abilities.txt:1` 开头：

```text
#base Fun/Fun_BaseGameMode.txt
#base Fun/Fun_Items.txt
#base Fun/Fun_Recipe.txt
"DOTAAbilities"
{
    ...
}
```

包内物品和配方文件也使用 `DOTAAbilities` 根节点。包中没有 `scripts/npc/items.txt`，也没有 `scripts/npc/npc_items_custom.txt`，它通过以上 `#base` 关系接入自定义条目。这里的结论是包内可见的加载设计，并非本次对引擎加载结果的实测。

物品使用 81500–81531 范围内的 ID，配方使用 81600–81621 范围内的 ID，中间有空位。所分析的 51 个物品/配方条目内部没有重复 ID；与 `main:pak01_dir/scripts/npc/items.txt` 对比，没有同名条目或 ID 冲突。此检查不代表与任意其他模组都不会冲突。

## 4. 两种物品实现方式

### A. 复用原生物品类：上古狂战斧

`scripts/npc/fun/fun_items.txt:1793` 的核心字段：

```text
"item_bfury_v2"
{
    "BaseClass"          "item_bfury"
    "AbilityTextureName" "item_bfury_v2"
    "ID"                 "81518"
    "ItemCost"           "7800"
    "ItemPurchasable"    "0"
    "AbilityValues"
    {
        "bonus_damage"          "105"
        "bonus_health_regen"    "7.5"
        "bonus_mana_regen"      "2.75"
        "cleave_damage_percent" "85"
        "cleave_distance"       "850"
        // 其余字段见原文件
    }
}
```

它保留 `item_bfury`，新增独立的 `item_bfury_v2`，复用原生类并提供自己的参数。这与本项目玲珑心升级品的核心思路一致；差别在加载入口、购买策略及图标。

同类还有上古黯灭、伊卡洛斯之殇、翡翠鞋、冰霜重铠、宝莲玄珠、德尊烟斗等。实际效果取决于对应原生类是否读取这些字段，不能只按配置值认定战斗效果已经验证。

### B. 数据驱动物品 + Lua：定海神针

`scripts/npc/fun/fun_items.txt:987`：

- 内部名 `item_fun_monkey_king_bar`，ID `81512`，`BaseClass = item_datadriven`。
- `Modifiers` 内定义被动 modifier；`Properties` 用 `%bonus_damage`、`%bonus_attack_speed` 关联 `AbilityValues`。
- `States` 设置 `MODIFIER_STATE_CANNOT_MISS`。
- `OnIntervalThink` 与 `OnAttackLanded` 经 `RunScript` 调用 `scripts/vscripts/Fun_Items/item_fun_monkey_king_bar.lua` 中的函数。

对应 Lua 的实现（文件第 2、18 行起）：

- 定时判断持有者是否为近战，添加或移除攻击距离 modifier。
- 普攻命中时读取 `bash_chance`、`bash_stun`、`pure_attack_damage`。
- 排除幻象、猴子士兵和建筑后，处理概率击晕、冷却，并用 `ApplyDamage` 施加纯粹伤害。

因此，这不是仅写一个新名称或描述，而是把 KV 的事件和 Lua 函数接起来。18 个数据驱动物品引用的脚本都能在包内找到（路径按大小写不敏感方式核对，并统一可选的 `scripts/vscripts/` 前缀）；没有把它们误算成 `item_lua`。

## 5. 配方与真正的获取入口

`scripts/npc/fun/fun_recipe.txt:296` 定义上古狂战斧卷轴：

```text
"item_recipe_bfury_v2"
{
    "BaseClass"       "item_datadriven"
    "ID"              "81611"
    "ItemCost"        "1"
    "ItemPurchasable" "0"
    "ItemRecipe"      "1"
    "ItemResult"      "item_bfury_v2"
    "ItemRequirements"
    {
        "01" "item_demon_edge;item_bfury"
    }
}
```

结构表达的是：**已有的上古狂战斧卷轴 + 恶魔刀锋 + 狂战斧 → 上古狂战斧**。卷轴 `ItemCost = 1` 不是玩家用 1 金购买的证据，因为它明确禁止购买。

### 祝福道具发放 19 种卷轴

- `scripts/npc/fun/fun_items.txt:87`：`item_fun_blessing` 价格 0、允许购买，`OnSpellStart` 调用 Lua，随后 `SpendCharge`。
- `scripts/vscripts/fun_items/item_fun_blessing.lua:37`：`items_table` 列出 19 种实际发放的配方。
- 同文件第 160、204 行：试玩分支、普通对局分支都调用 `target:AddItemByName(items_table[index_2].item)` 发放选中的卷轴。
- 普通对局按 `reset_times = 2` 保留三个随机候选，使用道具切换；出兵前允许更换，但需要能回收上次卷轴及相关金钱；开始后尚未领取者可以领取一次。
- 试玩分支按索引循环遍历所有卷轴。

这解释了为什么这些成品和 19 种发放卷轴可以设置 `ItemPurchasable = 0`。另外两个配方是 AI 神杖和万世金盘，均未进入该祝福池，且没有显式写 `ItemPurchasable`，不可把“全部配方都禁止购买”当作结论。

### 祝福还依赖游戏模式初始化

不能只复制祝福物品和它的一个 Lua 文件就认为已经迁移完整：

1. `scripts/npc/npc_units.txt:6199` 的 `dota_fountain` 给泉水设置 `Ability2 = Fun_BaseGameMode`（第 6213 行），另有 `Fun_Precacher`。
2. `scripts/npc/fun/fun_basegamemode.txt:39` 定义隐藏被动技能，其 modifier 在 `OnCreated` 中调用基础模式 Lua（第 98 行起）。
3. `scripts/vscripts/fun_basegamemode/modifier_fun_basegamemode.lua:38` 从天辉单位进入初始化；若没有 GameMode 实体，脚本尝试创建 `dota_base_game_mode`。
4. 同文件第 82–85 行设置 `GameRules.Fun_DataTable`、`GameModeCaster`、`GameModeAbility`。
5. 祝福脚本第 83 行直接访问 `GameRules.Fun_DataTable["GameModeAbility"]`，随后用它施加祝福 modifier。

基础模式还设置经验/金钱过滤器（第 292–293 行），所以整套复制会带入超出新增物品范围的改动。独立装备的事件脚本和整套祝福系统应区分处理。

## 6. 商店只增加三个入口，未看到额外 UI 代码

`scripts/shops.txt:23` 在 `consumables` 末尾增加：

```text
"item" "item_fun_harder"
"item" "item_fun_easier"
"item" "item_fun_blessing"
```

对照当前仓库的官方商店副本，除这三项、空白及末尾换行外没有其他差异；该副本与 `main` 一致。`magics`、`weapons`、`defense` 等分类没有逐件加入新装备。

包内 Panorama 内容仅有图像资源，没有商店布局、JavaScript 或 CSS 修改。因此本包没有提供“重写商店界面来展示全部自定义装备”的证据。

**不能据此认定我们之前重复血棘的问题已经找到原因或已解决。** 它使用不同的注册入口，且新增的是消耗品分类的三件工具。仅从这些文件不能证明它们在当前游戏版本的分类图标实际显示结果，也不能推出 `#base` 可以修复此前的问题。需要独立最小实验。

## 7. 本地化与图标

- 包内只有 `resource/localization/abilities_schinese.txt`，是含大量官方条目的完整简中文件并加入自定义内容；没有英文对应文件。
- “祝福”名称与说明从第 18888 行起；“定海神针”从第 18999 行起；“上古狂战斧”从第 19075 行起。
- 使用 `DOTA_Tooltip_ability_<内部名>`、`_Description`、`_Lore`、`_<属性名>` 等键，描述可引用 `%pure_attack_damage%` 等参数。
- `panorama/images/items/` 有 22 个编译纹理文件，其中包含备用旧图，不等于 22 个全部在用的新物品。
- 例如 `AbilityTextureName = item_bfury_v2` 对应包内 `panorama/images/items/bfury_v2_png.vtex_c`；定海神针使用 `item_sun_wukong_bar`，包内对应 `sun_wukong_bar_png.vtex_c`。
- 其他条目复用原有图标，不是每个新物品都必须有新图。

## 8. 对本项目可复用的部分与边界

| 需求 | 本包提供的参考 | 对本项目的处理 |
| --- | --- | --- |
| 原装备的加强版 | 原生 `BaseClass` + 新名/ID + `AbilityValues` | 旧 custom 入口仅试玩成功；后续已改为 `npc_abilities.txt` + `#base`，用户确认本地房间可获取 |
| 自定义触发效果 | `item_datadriven` + modifier + `RunScript` | 单独迁移所需 KV、Lua 及资源，并测试事件、伤害、丢弃/死亡后的清理 |
| 自定义配方 | `ItemRequirements` + `ItemResult` | 和我们现有路线相同；要商店购买就保留自己的购买开关和价格 |
| 随机发放配方 | 祝福道具的 `items_table` + `AddItemByName` | 需要初始化依赖，不能只复制一个道具文件 |
| 独立图标 | `AbilityTextureName` + `.vtex_c` | 需加入打包白名单，同时补中英文文本 |
| 商店分类图标 | 消耗品分类的三个入口 | 静态代码不能替代当前版本游戏内测试 |

不应整包覆盖当前模组：它包含完整的能力、单位、本地化覆盖文件以及模式初始化、AI、经验/金钱与资源改动。只提取目标物品及依赖，更容易保留本项目已有内容和官方基线。

## 9. 已检查与未检查

已检查：源包文件校验、完整解包、物品/配方 KV 解析、51 个条目内部 ID、与官方 `items.txt` 名称/ID 冲突、全部配方产物存在、数据驱动物品引用的 Lua 文件存在、商店文本差异。

未检查：Lua 在游戏中的执行、所有回调和资源依赖完整性、全部原生类参数兼容性、分类图标实际显示、物品合成/伤害/增益、任何在线模式可用性。此包有“旧文件”“待用资源”、未发放的万世金盘及注释规划条目，不能把包中每个文件都当作已经完成且正常启用的功能。

未部署、未进行游戏内实测。

## 10. 物品目录

以下由解析后的实际定义生成；完整参数与 21 个配方见 `D:\learning\Dota2-Scripts\bin\pak02-analysis-20260827\items-analysis.json`。

| ID | 内部名 | 中文名 | BaseClass | 祝福发卷轴 |
| --- | --- | --- | --- | --- |
| 81500 | item_fun_test | 未找到名称键 | item_datadriven | 否 |
| 81501 | item_fun_blessing | 祝福 | item_datadriven | 否 |
| 81502 | item_fun_Aghanims_Scepter_AI | AI的阿哈利姆神杖 | item_datadriven | 否 |
| 81503 | item_fun_tome_of_aghanim | 阿哈利姆之书 | item_datadriven | 否 |
| 81504 | item_fun_Aghanims_Robe | 阿哈利姆的长袍 | item_datadriven | 是 |
| 81505 | item_fun_Aghanims_Fake_Scepter | 阿哈利姆的赝品 | item_datadriven | 是 |
| 81506 | item_fun_poison | 毒药 | item_datadriven | 否 |
| 81507 | item_fun_book_of_strength | 刚毅之书 | item_book_of_strength | 否 |
| 81508 | item_fun_book_of_agility | 迅捷之书 | item_book_of_agility | 否 |
| 81509 | item_fun_book_of_intelligence | 洞察之书 | item_book_of_intelligence | 否 |
| 81510 | item_fun_greater_mango | 灵界芒果 | item_datadriven | 是 |
| 81511 | item_fun_Mercurys_gloves | 墨丘利的护手 | item_datadriven | 是 |
| 81512 | item_fun_monkey_king_bar | 定海神针 | item_datadriven | 是 |
| 81513 | item_fun_super_blink_dagger | 科勒的超级匕首 | item_datadriven | 是 |
| 81514 | item_fun_grandmasters_glaive_str | 大师之笛-力量 | item_datadriven | 是 |
| 81515 | item_fun_grandmasters_glaive_agi | 大师之笛-敏捷 | item_datadriven | 是 |
| 81516 | item_fun_grandmasters_glaive_int | 大师之笛-智力 | item_datadriven | 是 |
| 81518 | item_bfury_v2 | 上古狂战斧 | item_bfury | 是 |
| 81519 | item_desolator_v2 | 上古黯灭 | item_desolator | 是 |
| 81520 | item_greater_crit_v2 | 伊卡洛斯之殇 | item_greater_crit | 是 |
| 81521 | item_fun_trident_three_phase_power | 破泞之主的疏浚三叉戟 | item_trident | 是 |
| 81522 | item_fun_harder | 难度提升工具 | item_datadriven | 否 |
| 81523 | item_fun_easier | 难度降低工具 | item_datadriven | 否 |
| 81525 | item_fun_Jade_boots | 翡翠鞋 | item_tranquil_boots | 是 |
| 81526 | item_fun_shivas_guard_v2 | 冰霜重铠 | item_shivas_guard | 是 |
| 81527 | item_fun_lotus_orb_v2 | 宝莲玄珠 | item_lotus_orb | 是 |
| 81528 | item_fun_aeon_disk_v2 | 未找到名称键 | item_aeon_disk | 否 |
| 81529 | item_fun_spirit_vessel | 锢魂法器 | item_datadriven | 是 |
| 81530 | item_fun_pipe_v2 | 德尊烟斗 | item_pipe | 是 |
| 81531 | item_fun_assault_armor_v2 | 强袭盔甲 | item_datadriven | 是 |
