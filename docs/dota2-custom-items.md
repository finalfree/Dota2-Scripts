# Dota 2 新增可合成物品实践记录

基于本项目 `7.41e` 官方资源基线和本机 `dota_lv` 本地覆盖模组的实践。`main` 保存官方基线，自定义内容在功能分支维护。

## 合成路线

```text
原版玲珑心 item_octarine_core（4900）
  + 升级配方 item_recipe_lv_octarine_core（1000）
  → 玲珑心·精粹 item_lv_octarine_core（总价 5900）
```

保留原版玲珑心不修改，另定义新物品和新配方，通过合成树建立升级关系。不需要在 `shops.txt` 中添加独立条目。

## 文件清单

| 文件 | 用途 |
| --- | --- |
| `pak01_dir/scripts/npc/npc_abilities.txt` | 官方基线首行加 `#base "lv/lv_items.txt"`，其余不变。**这是普通本地房间中加载成功的关键入口。** |
| `pak01_dir/scripts/npc/lv/lv_items.txt` | 自定义物品和配方定义。 |
| `pak01_dir/scripts/vscripts/lv/item_lv_octarine_core.lua` | 生命周期脚本：附加/移除原生以太透镜 modifier。 |
| `pak01_dir/scripts/shops.txt` | 保持官方内容，不添加自定义条目。 |
| `pak01_dir/resource/localization/abilities_english.txt` | 官方完整文件 + 自定义键。 |
| `pak01_dir/resource/localization/abilities_schinese.txt` | 官方完整文件 + 自定义键。 |

打包清单见 `packaging/items.txt`，共 8 个文件。

## 物品定义

### 新物品 `item_lv_octarine_core`

关键字段：

| 字段 | 值 | 说明 |
| --- | --- | --- |
| `ID` | `10002` | 自定义分配，不与官方冲突。 |
| `BaseClass` | `item_datadriven` | 不直接继承原版玲珑心。 |
| `AbilityTextureName` | `item_octarine_core` | 复用原版图标。 |
| `AbilityBehavior` | `DOTA_ABILITY_BEHAVIOR_PASSIVE` | |
| `ItemCost` | `5900` | 成品总价。 |
| `ItemPurchasable` / `ItemSellable` | 均为 `1` | |

`AbilityValues`：

| 属性名 | 值 | 生效方式 |
| --- | --- | --- |
| `bonus_health` | `450` | data-driven `Properties` → `MODIFIER_PROPERTY_HEALTH_BONUS` |
| `bonus_health_regen` | `0` | data-driven `Properties` → `MODIFIER_PROPERTY_HEALTH_REGEN_CONSTANT` |
| `bonus_cooldown` | `80` | data-driven `Properties` → `MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE` |
| `bonus_mana` | `450` | 由原生 `modifier_item_aether_lens` 读取 |
| `bonus_mana_regen` | `20` | 由原生 `modifier_item_aether_lens` 读取 |
| `cast_range_bonus` | `600` | 由原生 `modifier_item_aether_lens` 读取 |

**属性分两条路径提供，不能重复：**

- 生命、生命恢复、冷却缩减 → 写在 data-driven `Modifiers` → `Properties` 块中，引擎直接处理。
- 魔法、魔法恢复、施法距离 → 由 Lua 附加的原生 `modifier_item_aether_lens` 从物品 `AbilityValues` 读取。**不能同时把这三项也放进 `Properties`**，否则会重复叠加。
- data-driven 的 `MODIFIER_PROPERTY_CAST_RANGE_BONUS` 经实测无效，施法距离必须走原生以太透镜 modifier。

### 新配方 `item_recipe_lv_octarine_core`

```text
"ID"                 "10001"
"BaseClass"          "item_datadriven"
"AbilityTextureName" "item_recipe_octarine_core"
"Model"              "models/props_gameplay/recipe.vmdl"
"ItemCost"           "1000"
"ItemPurchasable"    "1"
"ItemRecipe"         "1"
"ItemResult"         "item_lv_octarine_core"
"ItemRequirements"
{
    "01"             "item_octarine_core"
}
```

`AbilityTextureName` 显式引用原版玲珑心配方图标名，用户已确认商店和背包中图标正常。

### Lua 生命周期

`item_lv_octarine_core.lua` 只做两件事：

- `OnCreated` → `LVOctarineApplyNativeRange`：以精粹为 ability 给英雄附加 `modifier_item_aether_lens`。
- `OnDestroy` → `LVOctarineRemoveNativeRange`：只销毁由本物品实例附加的那个原生 modifier。

没有轮询、延迟定时器、`ForceRefresh` 或自定义发送数据。原生 modifier 的客户端 HUD 刷新由引擎处理。

## 本地化

在官方 `abilities_*.txt` 的 `Tokens` 块中添加自定义键，简体中文核心示例：

```text
"DOTA_Tooltip_Ability_item_lv_octarine_core"              "玲珑心·精粹"
"DOTA_Tooltip_Ability_item_recipe_lv_octarine_core"       "玲珑心·精粹配方"
"DOTA_SearchAlias_Ability_item_lv_octarine_core"          "linglongxin;jingcui;玲珑心;精粹"
"DOTA_Tooltip_ability_item_lv_octarine_core_Description"  "<h1>被动：冷却时间减少</h1>减少所有技能和物品的冷却时间。"
"DOTA_Tooltip_ability_item_lv_octarine_core_bonus_health" "+$health"
"DOTA_Tooltip_ability_item_lv_octarine_core_bonus_mana"   "+$mana"
"DOTA_Tooltip_ability_item_lv_octarine_core_bonus_mana_regen" "+$mana_regen"
"DOTA_Tooltip_ability_item_lv_octarine_core_bonus_cooldown"   "%+$cooldown_reduction"
```

属性标签后缀必须与 `AbilityValues` 中的属性名对应。部署的是"官方完整文件 + 自定义键"，不要替换成只含自定义键的小文件。

## 商店列表

`shops.txt` 保持官方内容。曾尝试在 `magics` 分类中添加自定义条目，导致重复血棘等显示异常；恢复官方内容后问题消失。默认策略：只增加物品定义、配方和本地化，通过合成树提供购买入口，不改商店列表。

## 打包与部署

详见 [打包与部署说明](vpk-packaging.md)。要点：

- 使用 VPKEdit CLI，固定 `--version 1 --single-file`。v2 包在本机被游戏报告损坏。
- 按 `packaging/items.txt` 清单直接打包，不复制资源到暂存目录。
- 部署前确认游戏完全退出，备份旧包，部署后校验 SHA256。

```powershell
.\deploy_items_only.ps1              # 打包并部署
.\deploy_items_only.ps1 -PackageOnly # 只打包校验
```

## 官方基线与提取

`extract_latest.ps1` 从官方 VPK 提取 NPC 脚本、商店列表和本地化文件。脚本会覆盖目标文件，更新基线时先检查 Git 状态，在干净的 `main` 分支提取、检查、提交，再同步到功能分支。不要在有自定义改动的分支运行提取脚本。

## 下次新增装备检查清单

- [ ] 检查当前分支、未提交改动及已有自定义物品，避免覆盖。
- [ ] 新物品与新配方分别使用独立内部名及不冲突的 ID。
- [ ] 保留原物品；核对属性字段、配方材料、产物和两种价格。
- [ ] 在中英文官方本地化基线上增加对应键，不替换成仅含自定义键的文件。
- [ ] 默认不改 `shops.txt`；通过合成关系树提供购买入口。
- [ ] 核对打包清单，避免漏掉 `#base` 引入的文件或 Lua 依赖。
- [ ] 获得部署授权、确认游戏退出，核验包内容与部署哈希。
- [ ] 由用户在游戏中检查升级树、配方购买、合成、描述和图标。
- [ ] 分别检查实际属性数值生效；不要把文本显示当作行为验证。
