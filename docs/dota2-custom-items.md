# Dota 2 新增可合成物品：玲珑心实践记录

记录日期：2026-08-27。基于本项目 `7.41e` 官方资源基线和本机 `dota_lv` 本地覆盖模组的测试，不是适用于所有版本、所有物品或所有运行模式的通用保证。

## 1. 最终验证成功的路线

保留原版玲珑心，另外定义一个新物品“玲珑心·精粹”，用新配方把两者连接起来：

```text
原版玲珑心 item_octarine_core（4900）
    + 新配方 item_recipe_lv_octarine_core（3000）
    → 玲珑心·精粹 item_lv_octarine_core（总价 7900）
```

新物品可以通过原版玲珑心的升级合成树发现、购买和合成，不需要出现在商店“法器”分类的独立图标列表中。

用户实测最终方案没有问题。保留原物品、独立新物品、升级关系及本地化是这次采用的路线；不要因此声称所有物品的原生行为都能同样继承，或已逐项测量验证每个战斗数值。

## 2. 文件职责

| 文件 | 本次用途 |
| --- | --- |
| `pak01_dir/scripts/npc/items.txt` | 官方原物品参考。本次不修改原版玲珑心，也不将这个文件加入增量包。 |
| `pak01_dir/scripts/npc/npc_items_custom.txt` | 定义新物品和新配方。现有文件就是可复用的完整示例。 |
| `pak01_dir/scripts/shops.txt` | 商店分类列表。最终与官方基线一致，不添加新玲珑心条目。 |
| `pak01_dir/resource/localization/abilities_english.txt` | 官方英文能力/物品本地化完整文件，加上自定义键。 |
| `pak01_dir/resource/localization/abilities_schinese.txt` | 官方简体中文能力/物品本地化完整文件，加上自定义键。 |
| `extract_latest.ps1` | 从官方 VPK 提取 NPC 脚本、商店列表和上述两份本地化。 |
| `deploy_items_only.ps1` | 复制白名单文件到临时目录、打包并部署到 `dota_lv`。 |

详细实现以仓库实际文件为准，避免只复制文档中的片段而漏掉外围 KV 结构或已有物品。

## 3. 新物品与配方如何定义

在 `npc_items_custom.txt` 的 `DOTAAbilities` 根节点中增加两个独立条目，不改写官方 `item_octarine_core` 条目。

### 新物品

本次 `item_lv_octarine_core` 使用以下关键字段：

| 字段 | 本次设置与含义 |
| --- | --- |
| `ID` | `10002`。是本次分配值，不是可以重复使用的模板常量。 |
| `BaseClass` | `item_octarine_core`，复用原玲珑心的原生物品类。 |
| `AbilityTextureName` | `item_octarine_core`，复用原图标；不等于继承其本地化。 |
| `AbilityBehavior` | `DOTA_ABILITY_BEHAVIOR_PASSIVE`。 |
| `ItemCost` | `7900`，成品总价，不是升级卷轴价格。 |
| `ItemPurchasable` / `ItemSellable` | 均为 `1`。不加入分类列表不等于要禁止购买。 |
| `AbilityValues` | 使用原物品类识别的属性名，设置新物品自己的数值。 |

当前配置：`bonus_cooldown = 80`、`bonus_health = 450`、`bonus_mana = 450`、`bonus_health_regen = 0`、`bonus_mana_regen = 20`。这些是实验数值，不代表平衡性建议。

新增其他装备时，为物品和配方分别选择不冲突的内部名及 ID，保留已有自定义条目。换一种 `BaseClass` 后，需重新测试行为与属性是否生效，不能只凭图标和描述正确就认定功能正确。

### 新配方

本次 `item_recipe_lv_octarine_core` 的关键内容：

```text
"ID"                 "10001"
"BaseClass"          "item_datadriven"
"Model"              "models/props_gameplay/recipe.vmdl"
"ItemCost"           "3000"
"ItemPurchasable"    "1"
"ItemRecipe"         "1"
"ItemResult"         "item_lv_octarine_core"
"ItemRequirements"
{
    "01"             "item_octarine_core"
}
```

`ItemRequirements` 和 `ItemResult` 建立原版物品到新物品的升级关系。本次通过合成树购买成功，并没有依靠 `shops.txt` 中的独立商品条目。

## 4. 本地化：为什么新物品最初是空白描述

新物品使用新的内部名，界面需要对应的新本地化键。继承 `BaseClass` 和复用图标并不会自动获得原玲珑心的名称、属性标签和说明。

我们从官方 `pak01_dir.vpk` 提取的是 `resource/localization/abilities_*.txt`，不是此前排查时看到的 `items_*.txt`。本次确认原玲珑心的游戏内名称及属性标签位于 `abilities` 文件中。

在中英文文件各自现有的 `lang` → `Tokens` 内添加新键。简体中文核心示例：

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

另外添加了 `_Lore` 背景文本。属性标签后缀必须和 `AbilityValues` 中的属性名对应；使用官方格式的变量标签，不要仅在说明中硬编码数值来假装属性已经生效。

英文文件也需要相同的键和对应英文文本。当前两个文件相对官方基线各新增 10 行，包含名称、配方名、搜索别名、说明、四项属性标签、背景文本及空行。

本次部署的是“官方完整本地化文件 + 自定义键”，这样不会丢掉其他物品和技能的原有文本。不要把同路径文件换成只含自定义键的小文件；任意新增本地化文件能否自动加载，在本项目没有验证。

## 5. 商店列表失败实验：不要重复踩坑

尝试过的顺序与结果：

1. 在 `shops.txt` 的 `magics` 分类、原玲珑心后面加入 `item_lv_octarine_core`。该分类从官方 20 件变成 21 件。
2. 用户看到新物品可在合成树购买，但分类列表没有正常显示新物品，反而出现两个血棘。
3. 曾怀疑是分类容量或界面索引问题，将 `item_aether_lens`（以太之镜）移到 `misc`，使法器回到 20 件；用户反馈重复血棘仍存在。
4. 最后删除自定义商店条目、将以太之镜移回原分类，使整个 `shops.txt` 恢复官方内容。重新打包部署后，用户确认问题消失。

**结论：恢复官方商店列表有效；“法器固定最多 20 件”不是本次已证实的根因。** 不应把容量猜测写成引擎规则，也不应声称分类图标注入已经成功。若以后确实需要新图标出现在分类列表，应单独立项调查界面加载与索引行为，逐次实测。

当前默认策略：只增加物品定义、配方和本地化，保持 `shops.txt` 官方内容。不要把以太之镜再次移到其他分类，也不要关闭新物品的 `ItemPurchasable`。

## 6. 官方基线与提取流程

`main` 保存未经自定义修改的官方资源；功能分支在其上维护自定义差异。相关历史：

- `0febdd7`：`7.41e` 原始基线。
- `4b390b6`：加入官方 `shops.txt` 并更新提取脚本。
- `9c9f672`：加入官方中英文 `abilities` 文件并更新提取脚本。
- `f60b53e`：当前玲珑心实验实现提交。

`extract_latest.ps1` 目前提取：

```text
scripts/npc/
scripts/shops.txt
resource/localization/abilities_english.txt
resource/localization/abilities_schinese.txt
```

从项目根目录运行脚本，确认脚本中的 `$SourceVPK` 指向本机官方包。当前配置为 `E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota\pak01_dir.vpk`，其他机器需自行调整。

脚本会覆盖提取目标，且没有自动保护自定义文本或处理版本升级合并。更新基线时先检查 Git 状态，在干净的基线工作区提取、检查、提交，再将基线同步到功能分支并保留自定义差异。不要直接在有自定义改动的功能分支运行提取脚本。

官方文件原有的格式和尾随空白也属于基线内容；不要为了清理格式制造整文件差异。主分支提交与远程推送是两件事，只有用户要求时才推送。

## 7. 本地打包与部署

本项目测试环境是 `dota_lv` 覆盖模组，而非直接修改官方 VPK，也不是普通创意工坊自定义游戏工程。本机 `dota_lv/gameinfo.gi` 使用 `LayeredOnMod dota`，并把 `Game dota_lv` 放在 `Game dota` 前；启动环境必须实际加载该模组。该配置位于游戏安装目录，不在仓库内，换机器时不能只复制项目文件就假定环境已就绪。

经用户授权部署时，在项目根目录运行：

```powershell
.\deploy_items_only.ps1
```

该脚本当前只打包以下四个路径，包内不能多套一层 `pak01_dir/`：

```text
scripts/npc/npc_items_custom.txt
scripts/shops.txt
resource/localization/abilities_english.txt
resource/localization/abilities_schinese.txt
```

输出为 `bin/pak01_dir.vpk`，部署到脚本配置的 `game/dota_lv/pak01_dir.vpk`。不要误用仓库根目录另一个旧 `pak01_dir.vpk`。虽然最终商店文件未改动，目前打包脚本仍包含其官方副本。

检查包内容和部署一致性，例如：

```powershell
vpkeditcli --file-tree .\bin\pak01_dir.vpk
Get-FileHash -Algorithm SHA256 -LiteralPath '.\bin\pak01_dir.vpk'
Get-FileHash -Algorithm SHA256 -LiteralPath 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv\pak01_dir.vpk'
```

两处 VPK 哈希必须一致。脚本的打包阶段仍主要依赖输出文件存在，没有全面检查打包进程的退出状态，因此不能仅凭“打包操作已执行”就认定产物正确。

遇到过的部署问题：Dota 2 进程运行时锁定目标 VPK，Windows 拒绝覆盖。原脚本因 PowerShell 非终止错误而误报成功；现已给部署 `Copy-Item` 加上 `-ErrorAction Stop`，失败时退出。遇到文件锁应请用户完全退出游戏，不要擅自终止进程，也不要声称旧包已更新。

重新启动游戏后再验证。仅关闭商店面板或返回主菜单，不能作为资源已重新加载的证据。本记录不证明这些改动适用于官方在线匹配。

## 8. 下次新增装备的检查清单

- [ ] 阅读本记录，检查当前分支、未提交改动及已有自定义物品，避免覆盖。
- [ ] 新物品与新配方分别使用独立内部名及不冲突的 ID。
- [ ] 保留原物品；核对原生类、属性字段、配方材料、产物和两种价格。
- [ ] 在中英文官方本地化基线上增加对应键，不替换成仅含自定义键的文件。
- [ ] 默认不改 `shops.txt`；通过合成关系树提供购买入口。
- [ ] 核对部署白名单，避免误打包对原版 `items.txt` 的无关改动。
- [ ] 获得部署授权、确认目标路径和游戏退出状态，核验包内文件与部署哈希。
- [ ] 由用户在游戏中检查升级树、配方购买、合成、中文/英文描述、原物品和血棘列表。
- [ ] 分别检查实际生命值、魔法值、回蓝及冷却效果；不要把文本显示当作行为验证。
- [ ] 如实记录失败尝试与尚未验证的假设，再决定是否扩大到下一件装备。
