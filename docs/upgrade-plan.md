# 物品升级卷轴计划（基于 commit `04f0e8e`）

> **唯一数据源**：把 commit 前后的 `pak01_dir/scripts/npc/items.txt` 解析成 KV 结构后逐字段比对，忽略一切行尾空白/注释噪音。
> 生成方式可复现，见文末「附录：复核脚本」。

> **2026-08-29 实现调整**：`item_lv_kaya_and_sange`、`item_lv_sange_and_yasha`、
> `item_lv_yasha_and_kaya` 已从实际升级清单中取消；三者的目标属性改由
> `item_lv_trident` 集中承载。本页对应三种双剑的小节仅保留为 commit 差异记录，
> 不再代表当前生成结果。当前实现以 `scripts/item_upgrades.json` 为准。
>
> 同日追加调整：`item_lv_travel_boots` 和 `item_lv_travel_boots_2` 也已取消。
> 当前原生传送逻辑不会读取自定义飞鞋的 `tp_cooldown`，对应小节同样仅保留为
> commit 差异记录，不代表当前生成结果。
>
> `item_octarine_core` 也已从批量 Upgrade 清单取消，以消除与 `lv_items.txt` 中
> `item_lv_octarine_core` 的同名重复定义。实际保留的是 ID `10001/10002`、提供
> 600 施法距离并由 `item_lv_octarine_core.lua` 补充原生施法距离 modifier 的
> “玲珑心·精粹”版本。
>
> 2026-08-30：`item_trident` 不属于原物品加卷轴的批量升级，改为手工维护在
> `lv_items.txt`；`item_upgrades.json` 不再包含它。生成器为它保留 ID 槽位，
> 因此后续自动生成物品的 ID 不会漂移。
>
> 2026-08-31：取消 `item_lv_monkey_king_bar` 及其升级配方；普通金箍棒改为
> `item_lv_trident` 的额外合成材料。生成器继续为原升级金箍棒保留 ID 槽位。

## 一、commit 到底改了什么

| 项 | 数值 |
|---|---|
| 改动文件 | `pak01_dir/scripts/npc/items.txt`（+417 / −413） |
| **有实质变化的物品** | **49 个** |
| **变更字段总数** | **234 个** |
| 新增 / 删除物品 | 0（物品总数 544 前后一致） |
| 纯格式噪音占比 | 约 60%（行尾空格清理），**与数值无关，不要当改动项** |

### 相对上一版文档的修正

1. **数量修正**：旧版写"94 个物品 / 50 个纳入计划"。实际有实质变化的是 **49 个**。"94" 是把所有 diff hunk 里出现过的物品都算上了，其中绝大多数只有行尾空格变化。
2. **剔除误报 `item_consecrated_wraps`**：commit 给它**新增了一行 `"ItemPurchasable" "1"`，但该物品上方本来就有一行一模一样的 `"ItemPurchasable" "1"`** —— 是重复键、空操作，无任何效果，不应纳入计划。
3. **补全缺漏字段**（旧版漏了 3 处）：
   - `item_gungir` 漏 `bonus_aoe`: 75 → 375
   - `item_bfury` 漏 `cleave_starting_width.value`: 150 → 250
   - `item_gunpowder_gauntlets` 漏 `bonus_damage.value`: 120 → 10（**下调**，详见备注）
4. **消除歧义字段名**：旧版里的 `value`: 360 → 560 / 250 → 450 / 650 → 850 无法定位，本版统一写成完整路径（`cleave_ending_width.value` / `splash_radius.value` / `aura_radius.value`）。

## 二、改动的两类性质

| 类别 | 物品数 | 字段数 | 处理方式 |
|---|---|---|---|
| **A 类**：属性 / 机制数值增强 | 48 | 226 | ✅ **做成升级卷轴**（本文主体） |
| **B 类**：商店 / 掉落标志位 | 4 | 8 | ⚠️ 卷轴表达不了，建议**保留为直接修改** |

### B 类明细（4 个物品 / 8 个字段）

这些改的是"能不能买/能不能卖/是不是中立掉落"。**注意要分两种语义**，处理方式完全不同：

- **"升级后的物品可以卖"**（`ItemSellable` / `ItemPermanent`）→ 直接写在 `item_lv_xxx` 上即可，**不用碰原物品**；
- **"让原物品进商店 / 退出中立池"**（`ItemPurchasable` / `ItemIsNeutralActiveDrop`）→ 卷轴表达不了，**必须直接改 `items.txt` 里的原物品**。

| 物品 | 中文名 | 字段 | 原值 → 目标值 | 落地位置 |
|---|---|---|---|---|
| `item_rapier` | 圣剑 | `ItemSellable` | 0 → 1 | ✅ 写在 `item_lv_rapier` |
| `item_royale_with_cheese` | 皇家芝士堡 | `ItemPermanent` | 0 → 1 | ✅ 写在 `item_lv_royale_with_cheese` |
| `item_royale_with_cheese` | 皇家芝士堡 | `ItemPurchasable` | 0 → 1 | ⚠️ 改原物品 |
| `item_recipe_trident` | 三叉戟·配方 | `ItemPurchasable` | 0 → 1 | ⚠️ 改原物品 |
| `item_recipe_trident` | 三叉戟·配方 | `ItemSellable` | 0 → 1 | ⚠️ 改原物品（或写在升级品） |
| `item_trident` | 三叉戟 | `ItemPurchasable` | 0 → 1 | ⚠️ 改原物品 |
| `item_trident` | 三叉戟 | `ItemSellable` | 0 → 1 | ✅ 写在 `item_lv_trident` |
| `item_trident` | 三叉戟 | `ItemIsNeutralActiveDrop` | 1 → 0 | ⚠️ 改原物品（要把三叉戟移出中立掉落池） |

## 三、卷轴实现方式（沿用仓库既有范式）

参照 `docs/dota2-custom-items.md` 的「玲珑心·精粹」，不要另起炉灶：

```
原物品 item_xxx  +  升级配方 item_recipe_lv_xxx  →  升级物品 item_lv_xxx
```

| 位置 | 内容 |
|---|---|
| `pak01_dir/scripts/npc/lv/lv_items.txt` | 每对新增两条：配方（`ItemRecipe=1` / `ItemResult` / `ItemRequirements`）+ 升级物品 |
| `ItemRequirements` | `"01" "item_xxx"` —— 用原物品当材料，天然做到"升级原物品" |
| `pak01_dir/scripts/vscripts/lv/` | 需要 lua 的行为（如主动技能）各写一个 `item_lv_xxx.lua` |
| `pak01_dir/resource/localization/abilities_schinese.txt` | `DOTA_Tooltip_Ability_item_lv_xxx` 等 |
| ID 分配 | 已占用 10001~10004，本批从 **10005** 起，每个物品占 2 个（配方在前、物品在后） |

### 实现方式：`BaseClass` 直接 override 原物品（不是 datadriven 重做）

**不需要 lua 复刻原技能。** ModDota 官方 Item KeyValues 文档明确说明：

> "Next is the BaseClass. It can be DataDriven, **or overriding an existing item from the default dota item_names**."
> （`moddota.com/abilities/item-keyvalues`）

也就是升级物品直接写 `"BaseClass" "item_sheepstick"`，引擎会沿用原物品的 C++ 实现：

```kv
"item_lv_sheepstick"
{
    "ID"                 "10006"
    "BaseClass"          "item_sheepstick"     // ← 继承原物品的全部行为
    "AbilityTextureName" "item_sheepstick"
    "ItemCost"           "6900"
    "ItemPurchasable"    "0"                   // 只由配方产出，不进商店
    "AbilityCooldown"    "10.0"                // 覆盖：原 20.0
    "AbilityManaCost"    "50"                  // 覆盖：原 250
    "AbilityCastRange"   "1800"                // 覆盖：原 800
    "AbilityValues"
    {
        "bonus_intellect"  "150"               // 覆盖：原 30
        "bonus_mana_regen" "18"                // 覆盖：原 8.5
        "sheep_duration"   "5"                 // 覆盖：原 2.8
    }
}
```

**为什么数值覆盖会生效**：这些值本来就是 V 社调平衡时改的东西 —— 他们每次版本更新就是
直接改 `items.txt` 里的 `AbilityValues`，说明 C++ 侧是走 `GetSpecialValueFor()` 从 KV 读的。
`AbilityCooldown` / `AbilityManaCost` / `AbilityCastRange` 同理，都是 ability 级字段，直接覆盖即可。

**相比 datadriven 重做的收益**：

| | override（`BaseClass` 指向原物品） | datadriven 重做 |
|---|---|---|
| 主动技能 | 白拿，零代码 | 要 lua 复刻 |
| 幻象 / break / 共享 CD / 物品栏位 | 引擎自动处理正确 | 每个边界都要自己兜 |
| 改 CD / 蓝耗 / 施法距离 / 触发参数 | 直接改 KV | **做不到** |
| 新增原物品没有的机制 | ❌ 做不到 | ✅ 可以 |

结论：**A 类 48 个物品里，47 个可以纯 KV 覆盖搞定，不需要写一行 lua。**

### ⚠️ 实测更正：`BaseClass` **不继承 KV 字段**

实测发现（代达罗斯之殇升级后竟能主动释放）：`BaseClass` 继承的是原物品的 **C++ 行为实现**，
**KV 字段一个都不继承**。所以上面那段"递归合并 vs 整体替换"的担心是多余的——
压根没有继承，只有默认值。

最典型的坑：

| 字段 | 原物品 | 升级品不写会怎样 |
|---|---|---|
| `AbilityBehavior` | `DOTA_ABILITY_BEHAVIOR_PASSIVE` | 默认 `DOTA_ABILITY_BEHAVIOR_UNIT_TARGET` → **被动变主动** |
| `AbilityUnitTargetTeam/Type` | 敌方单位 | 丢失目标筛选 |
| `ItemQuality` / `ItemShopTags` | epic / damage;crit | 商店显示异常 |

**修复**：生成器把原物品的标量字段全部显式复制过来（`AbilityValues` 单独做抄全+覆盖），
完全不依赖继承行为。复制时跳过 `ID`/`BaseClass`/`ItemCost`/`ItemPurchasable` 等由生成器决定的字段。

> 这也顺带说明：V 社自己调平衡能改数值，是因为 C++ 走 `GetSpecialValueFor()` 读 KV；
> 但 KV 本身的**结构**要靠我们自己复制。

### ⚠️ 剩下两个必须先验证的点

1. **"some values can't even be changed"** —— ModDota 的原话。
   指硬编码在 C++ 里、不从 KV 读的值。需要抽样实测，建议每个物品挑 1~2 个字段验证。

3. **`item_ethereal_blade` 的 `bonus_cast_range`（唯一的新增字段）**
   原物品 KV 里**根本没有这个 key**。override 模式下 C++ 不会去读一个它不认识的键，
   这一项**大概率无效**，只能改成 datadriven/lua 或放弃。这是 48 个物品里唯一需要特殊处理的。

### 分类说明（已按 override 方案修正）

- 🟢 **纯数值覆盖**（绝大多数）—— 改 KV 即可，先批量铺；
- 🔴 **需特殊处理**（1 个）—— `item_ethereal_blade` 的新增字段。

> 旧版文档曾按「🟢 纯属性 / 🔴 含机制字段」把物品分成 10 / 38 两批，并称 🔴 需要 lua 复刻。
> 那是基于「datadriven + `MODIFIER_PROPERTY_*`」前提的错误结论，在 override 方案下不成立，已作废。

### 产物已生成

48 个升级物品的 KV 已经按上面的方案生成好了：

| 文件 | 说明 |
|---|---|
| `scripts/item_upgrades.json` | 升级清单（48 物品 / 229 个覆盖字段），从 commit 前后 diff 自动提取 |
| `scripts/gen_item_upgrades.py` | 生成器，按清单产出 KV |
| `pak01_dir/scripts/npc/lv/lv_upgrades.txt` | 产出：48 个 `item_lv_xxx` + 48 个 `item_recipe_lv_xxx`，ID 10005~10100 |

重新生成 / 只看某一个：

```bash
python scripts/gen_item_upgrades.py                                  # 全部
python scripts/gen_item_upgrades.py --item sheepstick --preview       # 只看羊刀
python scripts/gen_item_upgrades.py --item sheepstick --preview --no-full-copy
#   ↑ 这个变体只写覆盖键，用来实测「KV 继承是合并还是替换」
```

脚本默认抄全 `AbilityValues`（`--full-copy`），已经能正确处理 `cleave_ending_width.value`
这类嵌套字段 —— 只替换 `value`，保留同级的 `affected_by_aoe_increase` 等兄弟键。
跑完只剩 1 条警告，就是上文预测的那个：

```
! item_ethereal_blade 原物品缺少字段（override 下不会生效）: bonus_cast_range
```

### 启用需要两步（目前还没启用）

新文件**不在打包清单里，现在不会生效**，可以放心先验证。要启用：

1. **加载**：`pak01_dir/scripts/npc/npc_abilities.txt` 第 1 行已有 `#base "lv/lv_items.txt"`，
   在其后加一行 `#base "lv/lv_upgrades.txt"`。

2. **打包**：在 `packaging/items.txt` 里加一行 `scripts/npc/lv/lv_upgrades.txt`。

> ⚠️ **加载顺序是个待验证点**：`#base` 挂在 `npc_abilities.txt` 上，而 `items.txt` 是另一个文件。
> `BaseClass` 是**加载时**解析的，若 `items.txt` 后于 `npc_abilities.txt` 加载，可能找不到父定义。
> （现有的 `ItemRequirements` 是运行时解析，所以一直没有这个问题。）
> 若羊刀样板报 BaseClass 相关错误，改为在 `items.txt` 顶部加 `#base "lv/lv_upgrades.txt"` 即可。

## 四、逐物品计划表

`增量` 列 = 卷轴相对原物品需要补的数值。多段值（`达贡`）按 `L1…L5` 分等级列出。

### `item_abyssal_blade` — 深渊之刃（Abyssal Blade）

- 独立升级物品与配方已取消；原 ID `10005/10006` 保留不用。
- 原版深渊之刃现与原版斯嘉蒂之眼直接合成 `item_lv_abyssal_skadi`。

### `item_aether_lens` — 以太透镜（Aether Lens）

- 升级物品：`item_lv_aether_lens`（ID `10008`）　升级配方：`item_recipe_lv_aether_lens`（ID `10007`）
- 来源：商店　分类：🔴 含机制字段　字段数：1

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `cast_range_bonus` 🔴 | `225` | `800` | **+575** |  |

### `item_angels_demise` — 绝刃（Angel's Demise）

- 升级物品：`item_lv_angels_demise`（ID `10010`）　升级配方：`item_recipe_lv_angels_demise`（ID `10009`）
- 来源：商店　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `9` | `4` | **-5** |  |
| `bonus_mana_regen` | `3` | `38` | **+35** |  |
| `slow` 🔴 | `30` | `50` | **+20** |  |
| `slow_duration` 🔴 | `4` | `8` | **+4** |  |

### `item_arcane_blink` — 秘奥闪光（Arcane Blink）

- 升级物品：`item_lv_arcane_blink`（ID `10012`）　升级配方：`item_recipe_lv_arcane_blink`（ID `10011`）
- 来源：商店　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `9.0` | `5.0` | **-4** |  |
| `blink_damage_cooldown` 🔴 | `3.0` | `0` | **-3** |  |
| `bonus_intellect` | `25` | `200` | **+175** | 25→200，是本次单项增幅最大的属性之一 |
| `mana_amount` 🔴 | `100` | `300` | **+200** |  |

### `item_assault` — 强袭胸甲（Assault Cuirass）

- 升级物品：`item_lv_assault`（ID `10014`）　升级配方：`item_recipe_lv_assault`（ID `10013`）
- 来源：商店　分类：🔴 含机制字段　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `aura_attack_speed` 🔴 | `30` | `50` | **+20** |  |
| `aura_negative_armor` 🔴 | `-5` | `-15` | **-10** |  |
| `aura_positive_armor` 🔴 | `5` | `15` | **+10** |  |
| `bonus_armor` | `10` | `60` | **+50** |  |
| `bonus_attack_speed` | `30` | `130` | **+100** |  |

### `item_bfury` — 狂战斧（Battle Fury）

- 原升级物品 `item_lv_bfury`（ID `10016`）及其配方已移除。
- 现由 `item_lv_dragon_splash`（ID `10110`）承接升级路线，配方 `item_recipe_lv_dragon_splash`
  （ID `10109`）可用 `item_bfury` 或 `item_specialists_array` 加 100 金卷轴合成（物品标价
  4000，按狂战斧路线）；成品自动
  吸收并永久提供 500 范围攻击溅射。

原狂战斧的 6 项机制字段不再通过升级物品覆盖；普通 `item_bfury` 保持官方属性不变。

### `item_bloodthorn` — 血棘（Bloodthorn）

- 升级物品：`item_lv_bloodthorn`（ID `10018`）　升级配方：`item_recipe_lv_bloodthorn`（ID `10017`）
- 来源：商店　分类：🔴 含机制字段　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `15.0` | `7` | **-8** |  |
| `bonus_attack_speed` | `70` | `195` | **+125** |  |
| `bonus_health_regen` | `0` | `15` | **+15** |  |
| `bonus_intellect` | `25` | `50` | **+25** |  |
| `bonus_mana_regen` | `4` | `13` | **+9** |  |

### `item_butterfly` — 蝴蝶（Butterfly）

- 旧升级物品已取消；ID `10019` / `10020` 继续保留，避免后续自动生成 ID 漂移。
- 目标属性已并入手工维护的融合装备 `item_lv_butterfly_crit`（蝶翼之殇）。
- 来源：商店　分类：🟢 纯属性　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_agility` | `30` | `100` | **+70** |  |
| `bonus_attack_speed_pct` | `20` | `30` | **+10** |  |
| `bonus_damage` | `30` | `150` | **+120** |  |
| `bonus_evasion` | `35` | `85` | **+50** |  |

### `item_dagon` — 达贡之神力（1级模板）（Dagon）

- 升级物品：`item_lv_dagon`（ID `10022`）　升级配方：`item_recipe_lv_dagon`（ID `10021`）
- 来源：商店　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `27 24 21 18 15` | `27 24 21 18 5` | L5 **-10** | 多段值按等级 1→5 排列，**只有第 5 级被改** |
| `bonus_all_stats` | `6 7 8 9 10` | `6 7 8 9 100` | L5 **+90** | 多段值按等级 1→5 排列，**只有第 5 级被改** |
| `cast_range_bonus` 🔴 | `60 90 120 150 180` | `60 90 120 150 580` | L5 **+400** | 多段值按等级 1→5 排列，**只有第 5 级被改** |
| `damage` 🔴 | `400 500 600 700 800` | `400 500 600 700 1800` | L5 **+1000** | 多段值按等级 1→5 排列，**只有第 5 级被改** |

### `item_dagon_5` — 达贡之神力（5级模板）（Dagon Lv5）

- 升级物品：`item_lv_dagon_5`（ID `10024`）　升级配方：`item_recipe_lv_dagon_5`（ID `10023`）
- 来源：商店　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `27 24 21 18 15` | `27 24 21 18 5` | L5 **-10** | 同上；`item_dagon` 与 `item_dagon_5` 两个模板必须同步 |
| `bonus_all_stats` | `6 7 8 9 10` | `6 7 8 9 100` | L5 **+90** | 同上；`item_dagon` 与 `item_dagon_5` 两个模板必须同步 |
| `cast_range_bonus` 🔴 | `60 90 120 150 180` | `60 90 120 150 580` | L5 **+400** | 同上；`item_dagon` 与 `item_dagon_5` 两个模板必须同步 |
| `damage` 🔴 | `400 500 600 700 800` | `400 500 600 700 1800` | L5 **+1000** | 同上；`item_dagon` 与 `item_dagon_5` 两个模板必须同步 |

### `item_desolator` — 黯灭（Desolator）

- 升级物品：`item_lv_desolator`（ID `10026`）　升级配方：`item_recipe_lv_desolator`（ID `10025`）
- 来源：商店　分类：🔴 含机制字段　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_damage_per_assist` 🔴 | `1` | `5` | **+4** |  |
| `bonus_damage_per_kill` 🔴 | `2` | `10` | **+8** |  |
| `corruption_armor` 🔴 | `-6` | `-16` | **-10** |  |
| `corruption_duration` 🔴 | `7.0` | `17` | **+10** |  |
| `max_damage` 🔴 | `30` | `3000` | **+2970** | 30→3000，成长上限几乎等于无上限 |

### `item_devastator` — 圣斧（Devastator）

- 升级物品：`item_lv_devastator`（ID `10028`）　升级配方：`item_recipe_lv_devastator`（ID `10027`）
- 来源：中立　分类：🔴 含机制字段　字段数：8

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `7` | `2` | **-5** |  |
| `active_mres_reduction` 🔴 | `20` | `50` | **+30** |  |
| `bonus_armor` | `7` | `28` | **+21** |  |
| `bonus_attack_speed` | `40` | `100` | **+60** |  |
| `bonus_intellect` | `40` | `100` | **+60** |  |
| `bonus_mana_regen` | `1.5` | `10` | **+8.5** |  |
| `int_damage_multiplier` 🔴 | `0.75` | `1` | **+0.25** |  |
| `projectile_speed` 🔴 | `300` | `500` | **+200** |  |

### `item_disperser` — 散魂剑（Disperser）

- 升级物品：`item_lv_disperser`（ID `10030`）　升级配方：`item_recipe_lv_disperser`（ID `10029`）
- 来源：商店　分类：🔴 含机制字段　字段数：8

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `15.0` | `5.0` | **-10** |  |
| `AbilityManaCost` 🔴 | `75` | `5` | **-70** |  |
| `ally_effect_duration` 🔴 | `4.0` | `10.0` | **+6** |  |
| `bonus_agility` | `40` | `100` | **+60** |  |
| `bonus_intellect` | `10` | `100` | **+90** |  |
| `enemy_effect_duration` 🔴 | `4.0` | `10.0` | **+6** |  |
| `feedback_mana_burn` 🔴 | `40` | `100` | **+60** |  |
| `movement_speed_buff_rate` 🔴 | `4` | `5` | **+1** |  |

### `item_eternal_shroud` — 永世法衣（Eternal Shroud）

- 升级物品：`item_lv_eternal_shroud`（ID `10032`）　升级配方：`item_recipe_lv_eternal_shroud`（ID `10031`）
- 来源：商店　分类：🔴 含机制字段　字段数：2

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_spell_resist` | `20` | `40` | **+20** |  |
| `mana_restore_pct` 🔴 | `25` | `50` | **+25** |  |

### `item_ethereal_blade` — 虚灵之刃（Ethereal Blade）

- 升级物品：`item_lv_ethereal_blade`（ID `10034`）　升级配方：`item_recipe_lv_ethereal_blade`（ID `10033`）
- 来源：商店　分类：🔴 含机制字段　字段数：6

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `22.0` | `10.0` | **-12** |  |
| `blast_stat_multiplier` 🔴 | `1.0` | `3.0` | **+2** |  |
| `bonus_agility` | `24` | `50` | **+26** |  |
| `bonus_cast_range` 🔴 | `—` | `650` | **新增** | 全新字段，原版不存在 → 属"新增机制" |
| `bonus_intellect` | `24` | `50` | **+26** |  |
| `bonus_strength` | `24` | `50` | **+26** |  |

### `item_greater_crit` — 代达罗斯之殇（Daedalus）

- 旧升级物品已取消；ID `10035` / `10036` 继续保留，避免后续自动生成 ID 漂移。
- 目标属性已并入手工维护的融合装备 `item_lv_butterfly_crit`（蝶翼之殇）。
- 来源：商店　分类：🔴 含机制字段　字段数：3

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_damage` | `88` | `188` | **+100** |  |
| `crit_chance` 🔴 | `30` | `100` | **+70** |  |
| `crit_multiplier` 🔴 | `225` | `300` | **+75** |  |

### `item_gungir` — 缚灵索（Gungnir）

- 升级物品：`item_lv_gungir`（ID `10038`）　升级配方：`item_recipe_lv_gungir`（ID `10037`）
- 来源：商店　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `18` | `6` | **-12** |  |
| `AbilityManaCost` 🔴 | `150` | `50` | **-100** |  |
| `bonus_aoe` 🔴 | `75` | `375` | **+300** |  |
| `bonus_intellect` | `12` | `100` | **+88** |  |

### `item_gunpowder_gauntlets` — 火药拳套（Gunpowder Gauntlets）

- 升级物品：`item_lv_gunpowder_gauntlets`（ID `10040`）　升级配方：`item_recipe_lv_gunpowder_gauntlets`（ID `10039`）
- 来源：中立　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `10` | `0` | **-10** |  |
| `bonus_damage.value` | `120` | `10` | **-110** | **唯一的下调项**（120→10），本质是"砍攻击力换溅射"，不是升级 |
| `splash_pct` 🔴 | `50` | `100` | **+50** |  |
| `splash_radius.value` 🔴 | `250` | `500` | **+250** | 目标值由 450 上调为 500（用户指定） |

### `item_harpoon` — 鱼叉（Harpoon）

- 升级物品：`item_lv_harpoon`（ID `10042`）　升级配方：`item_recipe_lv_harpoon`（ID `10041`）
- 来源：商店　分类：🔴 含机制字段　字段数：12

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCastRange` 🔴 | `700` | `1700` | **+1000** | 与 `cast_range_enemy` 必须保持一致 |
| `AbilityCooldown` 🔴 | `19.0` | `9.0` | **-10** |  |
| `AbilityManaCost` 🔴 | `50` | `25` | **-25** |  |
| `bonus_agility` | `10` | `75` | **+65** |  |
| `bonus_damage` | `25` | `125` | **+100** |  |
| `bonus_intellect` | `10` | `100` | **+90** |  |
| `bonus_mana_regen` | `2.0` | `10` | **+8** |  |
| `bonus_strength` | `25` | `75` | **+50** |  |
| `cast_range_enemy` 🔴 | `700` | `1700` | **+1000** | 与 `AbilityCastRange` 必须保持一致 |
| `max_distance` 🔴 | `1000` | `2000` | **+1000** |  |
| `passive_cooldown` 🔴 | `5` | `2` | **-3** |  |
| `pull_distance_pct` 🔴 | `35` | `70` | **+35** |  |

### `item_heart` — 恐鳌之心（Heart of Tarrasque）

- 旧升级物品已取消；ID `10043` / `10044` 继续保留，避免后续自动生成 ID 漂移。
- 目标属性已并入手工维护的融合装备 `item_lv_satanic_heart`（不洁魔心）。
- 来源：商店　分类：🟢 纯属性　字段数：2

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_strength` | `40` | `100` | **+60** |  |
| `hp_regen` | `1` | `2` | **+1** |  |

### `item_hurricane_pike` — 飓风长戟（Hurricane Pike）

- 升级物品：`item_lv_hurricane_pike`（ID `10046`）　升级配方：`item_recipe_lv_hurricane_pike`（ID `10045`）
- 来源：商店　分类：🔴 含机制字段　字段数：11

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `19.0` | `10.0` | **-9** |  |
| `AbilityManaCost` 🔴 | `150` | `10` | **-140** |  |
| `base_attack_range` 🔴 | `130` | `750` | **+620** | 130→750 跨度极大，建议先降到 400~500 试水 |
| `bonus_agility` | `20` | `60` | **+40** |  |
| `bonus_intellect` | `15` | `55` | **+40** |  |
| `bonus_strength` | `15` | `55` | **+40** |  |
| `cast_range_enemy` 🔴 | `425` | `450` | **+25** |  |
| `enemy_length` 🔴 | `425` | `450` | **+25** |  |
| `max_attacks` 🔴 | `5` | `15` | **+10** |  |
| `push_length` 🔴 | `600` | `1600` | **+1000** |  |
| `range_duration` 🔴 | `5` | `16` | **+11** |  |

### `item_hydras_breath` — 怪蛇之息（Hydra's Breath）

- 升级物品：`item_lv_hydras_breath`（ID `10048`）　升级配方：`item_recipe_lv_hydras_breath`（ID `10047`）
- 来源：中立　分类：🔴 含机制字段　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `base_attack_range` 🔴 | `150` | `650` | **+500** |  |
| `count` 🔴 | `3` | `10` | **+7** |  |
| `proc_chance` 🔴 | `30` | `100` | **+70** |  |
| `proc_dmg_pct` 🔴 | `75` | `100` | **+25** |  |
| `secondary_target_angle` 🔴 | `120` | `360` | **+240** |  |

### `item_kaya_and_sange` — 散慧对剑（Kaya and Sange）

- 升级物品：`item_lv_kaya_and_sange`（ID `10050`）　升级配方：`item_recipe_lv_kaya_and_sange`（ID `10049`）
- 来源：商店　分类：🟢 纯属性　字段数：7

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_intellect` | `16` | `36` | **+20** |  |
| `bonus_strength` | `16` | `36` | **+20** |  |
| `hp_regen_amp` | `16` | `20` | **+4** |  |
| `mana_regen_multiplier` | `30` | `100` | **+70** |  |
| `manacost_reduction` | `25` | `75` | **+50** |  |
| `slow_resistance` | `25` | `50` | **+25** |  |
| `spell_amp` | `12` | `50` | **+38** |  |

### `item_lotus_orb` — 清莲宝珠（Lotus Orb）

- 升级物品：`item_lv_lotus_orb`（ID `10052`）　升级配方：`item_recipe_lv_lotus_orb`（ID `10051`）
- 来源：商店　分类：🔴 含机制字段　字段数：3

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `15.0` | `5.0` | **-10** |  |
| `AbilityManaCost` 🔴 | `175` | `25` | **-150** |  |
| `active_duration` 🔴 | `5` | `3600` | **+3595** | 5→3600 秒 ≈ 永续，建议改为 60~120 秒 |

### `item_manta` — 幻影斧（Manta Style）

- 升级物品：`item_lv_manta`（ID `10054`）　升级配方：`item_recipe_lv_manta`（ID `10053`）
- 来源：商店　分类：🟢 纯属性　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_agility` | `26` | `100` | **+74** |  |
| `bonus_attack_speed` | `15` | `30` | **+15** |  |
| `bonus_intellect` | `10` | `100` | **+90** |  |
| `bonus_movement_speed` | `10` | `25` | **+15** |  |
| `bonus_strength` | `10` | `100` | **+90** |  |

### `item_mjollnir` — 雷神之锤（Mjollnir）

- 升级物品：`item_lv_mjollnir`（ID `10056`）　升级配方：`item_recipe_lv_mjollnir`（ID `10055`）
- 来源：商店　分类：🔴 含机制字段　字段数：8

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `35.0` | `5.0` | **-30** |  |
| `AbilityManaCost` 🔴 | `50` | `5` | **-45** |  |
| `bonus_attack_speed` | `90` | `180` | **+90** |  |
| `chain_chance` 🔴 | `25` | `100` | **+75** |  |
| `chain_damage` 🔴 | `180` | `380` | **+200** |  |
| `static_chance` 🔴 | `20` | `100` | **+80** |  |
| `static_damage` 🔴 | `225` | `525` | **+300** |  |
| `static_duration` 🔴 | `15.0` | `360` | **+345** | 15→360 秒 ≈ 全程覆盖，建议降到 60 秒 |

### `item_monkey_king_bar` — 金箍棒（升级已取消，仅保留历史差异）

- 当前无升级物品或升级配方；普通金箍棒作为升级三叉戟的合成材料。
- 来源：商店　分类：🔴 含机制字段　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_attack_speed` | `50` | `150` | **+100** |  |
| `bonus_chance` 🔴 | `80` | `100` | **+20** |  |
| `bonus_chance_damage` 🔴 | `70` | `100` | **+30** |  |
| `bonus_damage` | `50` | `150` | **+100** |  |
| `melee_attack_range` 🔴 | `50` | `200` | **+150** |  |

### `item_moon_shard` — 银月之晶（Moon Shard）

- 升级物品：`item_lv_moon_shard`（ID `10060`）　升级配方：`item_recipe_lv_moon_shard`（ID `10059`）
- 来源：商店　分类：🔴 含机制字段　字段数：2

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `consumed_bonus` 🔴 | `60` | `200` | **+140** |  |
| `consumed_bonus_night_vision` 🔴 | `200` | `600` | **+400** |  |

### `item_nullifier` — 否决坠饰（Nullifier）

- 升级物品：`item_lv_nullifier`（ID `10062`）　升级配方：`item_recipe_lv_nullifier`（ID `10061`）
- 来源：商店　分类：🔴 含机制字段　字段数：3

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_regen` | `0` | `6` | **+6** |  |
| `mute_duration` 🔴 | `4.0` | `20` | **+16** | 4→20 秒控制超模，建议 8~10 秒 |
| `projectile_speed` 🔴 | `1800` | `4800` | **+3000** |  |

### `item_octarine_core` — 玲珑心（Octarine Core）

- 升级物品：`item_lv_octarine_core`（ID `10064`）　升级配方：`item_recipe_lv_octarine_core`（ID `10063`）
- 来源：商店　分类：🟢 纯属性　字段数：2

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_cooldown` | `25` | `80` | **+55** |  |
| `bonus_mana_regen` | `6` | `20` | **+14** |  |

### `item_overwhelming_blink` — 盛势闪光（Overwhelming Blink）

- 升级物品：`item_lv_overwhelming_blink`（ID `10066`）　升级配方：`item_recipe_lv_overwhelming_blink`（ID `10065`）
- 来源：商店　分类：🔴 含机制字段　字段数：3

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `15.0` | `7.0` | **-8** |  |
| `blink_damage_cooldown` 🔴 | `3.0` | `0` | **-3** |  |
| `bonus_strength` | `25` | `85` | **+60** |  |

### `item_radiance` — 辉耀（Radiance）

- 升级物品：`item_lv_radiance`（ID `10068`）　升级配方：`item_recipe_lv_radiance`（ID `10067`）
- 来源：商店　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `aura_damage` 🔴 | `60` | `160` | **+100** |  |
| `aura_damage_illusions` 🔴 | `35` | `100` | **+65** |  |
| `aura_radius.value` 🔴 | `650` | `850` | **+200** |  |
| `bonus_damage` | `55` | `100` | **+45** |  |

### `item_rapier` — 圣剑（Divine Rapier）

- 升级物品：`item_lv_rapier`（ID `10070`）　升级配方：`item_recipe_lv_rapier`（ID `10069`）
- 来源：商店　分类：🟢 纯属性　字段数：3

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_damage` | `250` | `550` | **+300** | 圣剑本身就 250→550，再叠加 `bonus_damage_base` 100→500，慎用 |
| `bonus_damage_base` | `100` | `500` | **+400** |  |
| `bonus_spell_amp` | `25` | `100` | **+75** |  |

### `item_revenants_brooch` — 英灵胸针（Revenant's Brooch）

- 升级物品：`item_lv_revenants_brooch`（ID `10072`）　升级配方：`item_recipe_lv_revenants_brooch`（ID `10071`）
- 来源：商店　分类：🔴 含机制字段　字段数：4

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_damage` | `35` | `135` | **+100** |  |
| `crit_chance` 🔴 | `30` | `45` | **+15** |  |
| `crit_multiplier` 🔴 | `80` | `150` | **+70** |  |
| `spell_lifesteal` 🔴 | `15` | `34` | **+19** |  |

### `item_royale_with_cheese` — 奶酪块（Royale with Cheese）

- 升级物品：`item_lv_royale_with_cheese`（ID `10074`）　升级配方：`item_recipe_lv_royale_with_cheese`（ID `10073`）
- 来源：中立　分类：🔴 含机制字段　字段数：3

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `duration` | `5` | `50` | **+45** | 同时 `idle` 5→0，取消了"静止才生效"的限制 |
| `idle` 🔴 | `5` | `0` | **-5** |  |
| `shield` | `500` | `1000` | **+500** |  |

### `item_sange_and_yasha` — 散夜对剑（Sange and Yasha）

- 升级物品：`item_lv_sange_and_yasha`（ID `10076`）　升级配方：`item_recipe_lv_sange_and_yasha`（ID `10075`）
- 来源：商店　分类：🟢 纯属性　字段数：8

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_agility` | `16` | `36` | **+20** |  |
| `bonus_attack_speed` | `20` | `60` | **+40** |  |
| `bonus_strength` | `16` | `36` | **+20** |  |
| `hp_regen_amp` | `16` | `20` | **+4** |  |
| `movement_speed_percent_bonus` | `12` | `24` | **+12** |  |
| `movement_speed_percent_bonus_melee` | `12` | `24` | **+12** |  |
| `slow_resistance` | `30` | `50` | **+20** |  |
| `status_resistance` | `16` | `36` | **+20** |  |

### `item_satanic` — 撒旦之邪力（Satanic）

- 旧升级物品已取消；ID `10077` / `10078` 继续保留，避免后续自动生成 ID 漂移。
- 目标属性已并入手工维护的融合装备 `item_lv_satanic_heart`（不洁魔心）。
- 来源：商店　分类：🔴 含机制字段　字段数：2

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `40.0` | `5.0` | **-35** |  |
| `bonus_strength` | `25` | `75` | **+50** |  |

### `item_sheepstick` — 邪恶镰刀（Scythe of Vyse）

- 升级物品：`item_lv_sheepstick`（ID `10080`）　升级配方：`item_recipe_lv_sheepstick`（ID `10079`）
- 来源：商店　分类：🔴 含机制字段　字段数：6

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCastRange` 🔴 | `800` | `1800` | **+1000** |  |
| `AbilityCooldown` 🔴 | `20.0` | `10.0` | **-10** |  |
| `AbilityManaCost` 🔴 | `250` | `50` | **-200** |  |
| `bonus_intellect` | `30` | `150` | **+120** |  |
| `bonus_mana_regen` | `8.5` | `18` | **+9.5** |  |
| `sheep_duration` 🔴 | `2.8` | `5` | **+2.2** |  |

### `item_shivas_guard` — 希瓦的守护（Shiva's Guard）

- 升级物品：`item_lv_shivas_guard`（ID `10082`）　升级配方：`item_recipe_lv_shivas_guard`（ID `10081`）
- 来源：商店　分类：🔴 含机制字段　字段数：1

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_aoe` 🔴 | `75` | `375` | **+300** |  |

### `item_silver_edge` — 白银之锋（Silver Edge）

- 升级物品：`item_lv_silver_edge`（ID `10084`）　升级配方：`item_recipe_lv_silver_edge`（ID `10083`）
- 来源：商店　分类：🔴 含机制字段　字段数：9

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `22.0` | `10` | **-12** |  |
| `backstab_duration` 🔴 | `5` | `16` | **+11** |  |
| `bonus_attack_speed` | `35` | `90` | **+55** |  |
| `bonus_damage` | `70` | `140` | **+70** |  |
| `bonus_intellect` | `0` | `30` | **+30** |  |
| `bonus_mana_regen` | `0` | `10` | **+10** |  |
| `bonus_strength` | `0` | `30` | **+30** |  |
| `windwalk_duration` 🔴 | `17.0` | `60` | **+43** | 17→60 秒 ≈ 全程隐身，建议 25~30 秒 |
| `windwalk_movement_speed` 🔴 | `22` | `25` | **+3** |  |

### `item_skadi` — 斯嘉蒂之眼（Eye of Skadi）

- 独立升级物品与配方已取消；原 ID `10085/10086` 保留不用。
- 原版斯嘉蒂之眼现与原版深渊之刃直接合成 `item_lv_abyssal_skadi`。

### `item_sphere` — 林肯法球（Linken's Sphere）

- 升级物品：`item_lv_sphere`（ID `10088`）　升级配方：`item_recipe_lv_sphere`（ID `10087`）
- 来源：商店　分类：🔴 含机制字段　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `14.0` | `7.0` | **-7** |  |
| `block_cooldown` 🔴 | `14.0` | `5.0` | **-9** |  |
| `bonus_all_stats` | `16` | `56` | **+40** |  |
| `bonus_health_regen` | `6.5` | `15` | **+8.5** |  |
| `bonus_mana_regen` | `4.25` | `10` | **+5.75** |  |

### `item_swift_blink` — 迅疾闪光（Swift Blink）

- 升级物品：`item_lv_swift_blink`（ID `10090`）　升级配方：`item_recipe_lv_swift_blink`（ID `10089`）
- 来源：商店　分类：🔴 含机制字段　字段数：3

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `15.0` | `7.0` | **-8** |  |
| `blink_damage_cooldown` 🔴 | `3.0` | `0` | **-3** |  |
| `bonus_agility` | `25` | `85` | **+60** |  |

### `item_travel_boots` — 远行鞋（Boots of Travel）

- 升级物品：`item_lv_travel_boots`（ID `10092`）　升级配方：`item_recipe_lv_travel_boots`（ID `10091`）
- 来源：商店　分类：🔴 含机制字段　字段数：1

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `tp_cooldown` 🔴 | `40` | `20` | **-20** |  |

### `item_travel_boots_2` — 远行鞋 II（Boots of Travel II）

- 升级物品：`item_lv_travel_boots_2`（ID `10094`）　升级配方：`item_recipe_lv_travel_boots_2`（ID `10093`）
- 来源：商店　分类：🔴 含机制字段　字段数：1

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `tp_cooldown` 🔴 | `40` | `5` | **-35** |  |

### `item_trident` — 三元重戟（Trident）

- 升级物品：`item_lv_trident`（ID `10096`）　升级配方：`item_recipe_lv_trident`（ID `10095`）
- 当前合成：1 金可购买卷轴 + 三把单剑，或卷轴 + 任意双剑 + 剩余单剑；不再以原版 `item_trident` 为材料
- 实现：原版已有的 10 项属性由原生 `modifier_item_trident` 提供；新增 3 项由 data-driven `Properties` 提供
- 来源：商店合成树　分类：手工重做物品　字段数：13

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_agility` | `30` | `100` | **+70** |  |
| `bonus_attack_speed` | `30` | `60` | **+30** |  |
| `bonus_intellect` | `30` | `200` | **+170** |  |
| `bonus_strength` | `30` | `100` | **+70** |  |
| `hp_regen_amp` | `30` | `100` | **+70** |  |
| `magic_damage_attack` | `30` | `100` | **+70** |  |
| `mana_regen_multiplier` | `30` | `100` | **+70** |  |
| `movement_speed_percent_bonus` | `10` | `33` | **+23** |  |
| `spell_amp` | `30` | `100` | **+70** |  |
| `status_resistance` | `30` | `66` | **+36** |  |
| `slow_resistance` | 不存在 | `100` | 新增 | Lua：`MODIFIER_PROPERTY_SLOW_RESISTANCE_STACKING` |
| `manacost_reduction` | 不存在 | `75` | 新增 | Lua：`MODIFIER_PROPERTY_MANACOST_PERCENTAGE_STACKING` |
| `cast_speed_pct` | 不存在 | `50` | 新增 | Lua：`MODIFIER_PROPERTY_CASTTIME_PERCENTAGE` |

### `item_wind_waker` — 风之杖（Wind Waker）

- 升级物品：`item_lv_wind_waker`（ID `10098`）　升级配方：`item_recipe_lv_wind_waker`（ID `10097`）
- 来源：商店　分类：🔴 含机制字段　字段数：5

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `AbilityCooldown` 🔴 | `19.0` | `7.0` | **-12** |  |
| `AbilityManaCost` 🔴 | `175` | `25` | **-150** |  |
| `bonus_intellect` | `35` | `200` | **+165** |  |
| `bonus_mana_regen` | `3.0` | `10.0` | **+7** |  |
| `bonus_movement_speed` | `30` | `60` | **+30** |  |

### `item_yasha_and_kaya` — 慧夜对剑（Yasha and Kaya）

- 升级物品：`item_lv_yasha_and_kaya`（ID `10100`）　升级配方：`item_recipe_lv_yasha_and_kaya`（ID `10099`）
- 来源：商店　分类：🟢 纯属性　字段数：7

| 字段 | 原值 | 目标值 | 增量 | 备注 |
|---|---|---|---|---|
| `bonus_agility` | `16` | `36` | **+20** |  |
| `bonus_attack_speed` | `20` | `60` | **+40** |  |
| `bonus_intellect` | `16` | `36` | **+20** |  |
| `mana_regen_multiplier` | `30` | `40` | **+10** |  |
| `movement_speed_percent_bonus` | `12` | `24` | **+12** |  |
| `movement_speed_percent_bonus_melee` | `12` | `24` | **+12** |  |
| `spell_amp` | `12` | `50` | **+38** |  |

## 五、需要你先拍板

| # | 问题 | 影响 |
|---|---|---|
| 1 | **KV 继承是合并还是替换**？做样板实测：只写要覆盖的 3 个 `AbilityValues` 键，看游戏内另外 3 个键是否还在 | 若是替换语义，就改用脚本抄全整块（已备好，成本一样） |
| 2 | **卷轴成本**：统一价（如 1000）还是按物品分档？ | 影响 `ItemCost` 一列 |
| 3 | **达贡**改的是 1-5 级模板，但只有第 5 级数值变了 —— 升级后是全等级都变，还是只有满级变？ | `item_dagon` / `item_dagon_5` 两个模板要一致 |
| 4 | **火药拳套** `bonus_damage` 是 120→10（下调），本质是重做不是升级。要不要剔除？ | 从 49 个变 48 个 |
| 5 | **中立物品**（毁灭者/火药拳套/海德拉之息/三叉戟/皇家芝士堡）不进商店，配方怎么获得？ | 可能需要改成 Boss 掉落或额外商店页 |
| 6 | **平衡红线**：圣剑 250→550、三叉戟全属性 30→100、林肯 `active_duration` 5→3600 等极端值，是原样保留还是先收敛？ | 备注列共 29 处提示，其中 5 处给了具体建议值 |
| 7 | **能否叠加**：一件物品吃 1 张卷轴，还是可多级升级？ | 决定 ID 数量是否翻倍 |

## 六、建议排期

| 阶段 | 内容 | 规模 |
|---|---|---|
| P0 | 回滚 commit 对 49 个物品的直接修改（保留 B 类 5 项必须改原物品的标志位） | 1 次 revert + 手工补 5 行 |
| P1 | **做羊刀样板验证**：`item_lv_sheepstick` 只写 3 个覆盖键，进游戏看 tooltip 与实战效果，定论「合并 vs 替换」 | 2 个新条目，约 10 分钟 |
| P2 | 定论后用脚本批量生成其余 46 个（含全量 `AbilityValues` 抄写，规避语义风险） | 46 个物品 = 92 条，脚本一次跑完 |
| P3 | 单独处理 `item_ethereal_blade` 的新增字段 `bonus_cast_range` | 1 个物品，需 lua 或放弃 |
| P4 | 平衡收敛 + 实测 | — |

> P1 是关键节点：一个样板就能把「合并 vs 替换」和「数值覆盖是否生效」两个未知数同时验证掉。
> 别跳过它直接批量生成，否则可能要返工 48 次。

## 附录：复核脚本

本次结论由脚本对 commit 前后两版 items.txt 做 KV 结构化解析后逐字段比对得出，并额外做了重复键审计（确认只有 `item_consecrated_wraps` 存在重复键，即上文剔除的误报）。后续若 items.txt 再有变动，重跑同一套比对即可刷新本表。

```python
# 1) 导出两版
git show <commit>^:pak01_dir/scripts/npc/items.txt > items_old.txt
git show <commit>:pak01_dir/scripts/npc/items.txt  > items_new.txt
# 2) 解析成 {item_name: {字段路径: 值}} 后逐键比对（忽略空白差异）
# 3) 额外检查每个物品是否存在重复叶子键 —— 重复键会让"逐键比对"漏报，必须单独审计
```
