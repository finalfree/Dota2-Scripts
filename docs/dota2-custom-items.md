# Dota 2 新增可合成物品实践记录

> 2026-09-03 Workshop-first 迁移：下文的玩法实测结论和旧路径记录保留为历史证据。当前自定义 KV/Lua 已迁到 `game/dota_addons/overforged`，小图源资源迁到 `content/dota_addons/overforged`；`pak01_dir` 只维护官方基线。新路径、构建和验收以 [Workshop-first 说明](workshop-addon.md) 为准，不能再在旧官方文件内手加自定义内容。

基于本项目 `7.41e` 官方资源基线和本机 `dota_lv` 本地覆盖模组的实践。`main` 保存官方基线，自定义内容在功能分支维护。

## 玲珑心·精粹永久吸收改版（2026-09-08，游戏内待验收）

当前配方为原版 `item_octarine_core`（4900）+ `item_aether_lens`（2275）+
`item_chasm_stone`（900）+ `item_recipe_lv_octarine_core`（100），总价 **8175**。
物品与配方 ID 保持 `10002` / `10001`，标准 addon KV 的手工区维护。
2026-09-09 将升级卷轴从 1000 金降至 100 金，成品总价同步为 8175。确认 Dota 退出后
重新部署；19 项 VPK v1 的 CRC、包内源码 SHA256 与目标哈希通过。包/目标 SHA256：
`A44DC02EC0DE49B3ECB7DEC185CDBBC134FA914AD71663222C9D4DB67FE08593`。
前一版本备份：
`bin/backups/pak01-before-deploy-20260909-125106-07465facbecb49f2b94c20745745ebbf.vpk`。

合成后本体英雄主装备栏内自动吸收，释放物品格并显示不可驱散、死亡保留的永久状态。
沿用升级宝石的 `TakeItem` 隐藏物品实体方式，保留实体作为 KV/原生 modifier 的数值来源，
不删除物品句柄，不引入客户端自定义 Lua modifier。每名英雄只吸收一次，重复成品保留；
信使、幻象、克隆、天穹分身、背包、储藏处与中立槽不能吸收。死亡时等待复活再处理。

| 永久属性 | 数值 | 唯一提供方 |
| --- | --- | --- |
| 生命值 | +450 | 永久 KV 状态 `MODIFIER_PROPERTY_HEALTH_BONUS` |
| 魔法值 | +450 | 原生 `modifier_item_aether_lens` 读取 `bonus_mana` |
| 冷却缩减 | 80% | 手工施加的永久 KV 状态 `MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE` |
| 施法距离 | +600 | 原生 `modifier_item_aether_lens` |
| 魔法恢复 | +20/秒 | 同一原生以太透镜 modifier |
| 作用范围 | +400 | 原生 `modifier_rubick_curiosity` 基础层读取 `curiosity_aoe_bonus` |

用户随后要求保留原有生命与魔法加成，`bonus_health` / `bonus_mana` 已从 0 恢复为 450。
魔法值仍由以太透镜原生 modifier 提供；生命值由现有永久 KV 状态提供。奇心实验加入后，
原来用于生命和作用范围的 `modifier_item_chasm_stone` 已移除，400 作用范围改由奇心基础层的
`curiosity_aoe_bonus` 提供。当前引擎 `server.dll` 已核对注册
`MODIFIER_PROPERTY_HEALTH_BONUS`，因此不需要为这两项继续保留裂隙之石 modifier。

吸收延迟 0.1 秒并重新核对持有者与物品槽；任何来源挂载失败都保留成品并清理本次效果。
隐藏物品后再次确认并补挂效果，失败则恢复成品。永久状态每 0.25 秒在英雄存活时补回
缺失的原生 modifier，避免死亡后丢失距离、回蓝、范围或持续时间增强；清理仅针对本物品来源。

Lua 生命周期替身（双来源、隐藏清理、失败回滚、同帧重复合成、复活恢复、恢复失败重试、
其他物品来源保护）及全部 14 个运行 Lua 文件的 Lua 5.1 语法检查通过。
addon KV、ID、本地化与打包映射检查通过；Python 46 项中 42 项通过，4 项仍是既有图标
长度断言 `7764 != 7748`，本轮未修改纹理。仅精粹物品和配方定义改变。
以上为离线检查；吸收后实际冷却、距离、作用范围、回蓝、死亡复活及与其他装备的交互
仍须用户在游戏中验证，未启动或操控游戏。

首版（生命/魔法归零）确认游戏退出后通过 `deploy_items_only.ps1` 部署。VPK v1 单文件 19 项的 CRC、
全部包内文件源码 SHA256 及目标部署哈希通过。首版包/目标 SHA256：
`A9C011864AB460E8EE3C22FB69FC3E5879EB18222A1C7C489E8ABC8C60DAF37B`。
旧包备份：`bin/backups/pak01-before-deploy-20260908-232956-9805ae6edaa640fd9bc21018d2521f54.vpk`。
部署成功不代表游戏内验收通过，未上传 Workshop。

恢复 450 生命/450 魔法后的版本已通过 3 项精粹专项检查和 addon 静态检查；Lua 逻辑未改。
确认游戏退出后重新部署，19 项 VPK v1 CRC、源码 SHA256 和目标哈希通过。
当前包/目标 SHA256：`618A3AF84A3FA1B424EF3BC775564DE6BD256759CE23A9E78789AE0625D479FA`。
旧包备份：`bin/backups/pak01-before-deploy-20260908-233250-37dacf40226348bb8b80c9dade98f404.vpk`。
生命/魔法恢复及其他永久属性的游戏内效果仍待用户验收。

## 精粹：拉比克奇心原生持续时间增强（2026-09-09，游戏内待验收）

用户实测上一版 `SetModifierGainedFilter` 对多种普通增益有效，但龙骑士的古龙形态和
恐怖利刃的魔化均未延长。控制台中只出现魔化的 0.35 秒变身过渡和 0.1 秒光环施加者事件，
没有两个英雄的主体变身 modifier 事件，说明这类引擎内部状态没有走该过滤器的常规入口。

用户随后确认拉比克 7.41e 先天技能“奇心”能延长龙骑士、恐怖利刃等主体变身。改为直接
挂载官方 `modifier_rubick_curiosity`，不用自行声明 `MODIFIER_PROPERTY_BUFF_AMPLIFICATION`。
私有物品数值把奇心的攻击力、按英雄等级增长、附近敌人施法临时层数和击杀永久层数全部
设为 0；保留原生 modifier 自带的一层基础奇心，并令该层读取
`curiosity_modifier_amp = 100` 与 `curiosity_aoe_bonus = 400`。现有 0.25 秒永久状态回调只检查永久属性是否丢失，
不扫描或修改任何技能 buff，也不改写奇心层数。

奇心原生 modifier 同时声明 `MODIFIER_PROPERTY_BUFF_AMPLIFICATION` 与
`MODIFIER_PROPERTY_STATUS_RESISTANCE_CASTER`。因此本轮实验会同时给予持有者身上的限时增益
+100% 持续时间，以及持有者对敌人施加的、受状态抗性影响的负面状态 +100% 持续时间。
这条机制按拉比克自身生效，不再承诺延长持有者施加给未拥有奇心效果的队友的增益。

已删除所有 `SetModifierGainedFilter` 注册、事件改写、modifier 查询和诊断去重代码。
没有轮询增益、`SetDuration`、逐实例记录、英雄/技能/modifier 白名单。固定时长、无视状态
抗性的效果仍可能不受影响，因此须重新实测古龙形态、魔化、普通增益与敌方负面状态；离线
KV/Lua 检查不能证明引擎交互。

上一事件版已部署包/目标 SHA256：
`2F5EF36C8D60A23C30CEB97E56E27694756342CD7EA96A43F9E6421CFB0BA51B`。
旧包备份：`bin/backups/pak01-before-deploy-20260909-001853-750e5e40c04a4714b8498eb70cb132b9.vpk`。

`ACAA3CBF8E90B233A3CBCA2085CE3FD02ACB14242E73D35CD410E135660676D6` 是已废弃的直接属性
实验包，未部署。奇心版完成检查和打包后在下方补记新哈希。

奇心版通过 20 项资源检查中的 16 项；4 项仍是既有纹理长度断言 `7764 != 7748`。
全部 Lua 替身套件与 14 个运行 Lua 文件的 Lua 5.1 语法检查通过。Dota 退出后已打包并部署；
19 项 VPK v1 单文件 CRC、包内源码 SHA256 和目标哈希全部通过。包/目标 SHA256：
`FEDF482F7A265DF7174FC88896C0FEC68CC2478B02599427E93FA1D6E709D408`。
旧包备份：`bin/backups/pak01-before-deploy-20260909-121011-c6ea544a437342d686329800d4bb1ac4.vpk`。
用户实测此包对普通增益及变身均生效，但总时长成为 3 倍。结果说明原生奇心已经建立一层
基础效果，Lua 再调用 `SetStackCount(1)` 实际又增加了一层；每层 100% 时产生了总计 +200%。

修正版删除所有奇心层数写入，只使用原生基础层；所有额外叠层来源仍为 0。再次确认 Dota
退出后完成部署；VPK v1 单文件共 19 项，CRC、包内源码 SHA256 和目标哈希均通过。
包/目标 SHA256：
`2B2FAEDCA5A198C46D915530C246CDBCACE3D4524B02F3F1FFB402878CD4C0B4`。
被替换的 3 倍实测版备份：
`bin/backups/pak01-before-deploy-20260909-122250-493b479269da439c8f1276795e5419ec.vpk`。
用户实测修正版为 +100%，即总时长 2 倍。

随后将原先由 `modifier_item_chasm_stone` 提供的 400 作用范围合并到奇心基础层：
`curiosity_aoe_bonus = 400`。裂隙之石 modifier 同时承担的 450 生命改由现有永久 KV 状态的
`MODIFIER_PROPERTY_HEALTH_BONUS` 提供，数值保持不变；当前只需挂载以太透镜和奇心两个原生
modifier。确认 Dota 退出后重新部署，19 项 VPK v1 的 CRC、包内源码 SHA256 与目标哈希通过。
包/目标 SHA256：
`DC4317EC8D364A288761055468203A48E720387C8599D9FCFAE1A0B016457726`。
被替换的独立裂隙之石 modifier 版本备份：
`bin/backups/pak01-before-deploy-20260909-122920-0288d2bfdc974622aea2e7af7d22cafe.vpk`。
用户游戏内实测奇心基础层同时提供 400 作用范围和 100% 持续时间，结果正常。
随后精简物品与已吸收状态的中英文说明，只显示实际属性，不显示实现来源或实验措辞。
重新部署后的包/目标 SHA256：
`F8CA9412680D864167EE5DDFCD2CE0516BF2D43B466DB74E5B8FE79ABCB10260`；
前一功能相同版本备份：
`bin/backups/pak01-before-deploy-20260909-123548-a9b5e57a37af4b14821002c82e9efd57.vpk`。

## 精粹：增益持续时间 +100% 轮询实验（2026-09-08，历史，已由奇心原生版替代）

在现有 `item_lv_octarine_core` 上增加 `AbilityValues.buff_duration_bonus = 100`，
配方、价格和原有永久属性不变。采用**接受者规则**：吸收精粹的本体英雄自身获得的
友方限时增益延长，包含自己施加的技能和物品增益；给未吸收精粹的队友施法不因此延长。
按用户要求不设英雄或技能/modifier 白名单，也不按隐藏、可驱散、物品来源或光环分类排除。
只处理 `duration > 0`、剩余时间大于 0、`IsDebuff() == false` 且施法者存在并同队的状态。
没有施法者的状态、敌方来源、负面效果和永久状态不处理。

沿用永久 KV 状态的服务器 `RunScript`，检查周期从 0.25 改为 0.1 秒。
遍历本体 `FindAllModifiers()`，通过通用 `CDOTA_Buff:SetDuration(..., true)`
追加一次原始时长；例如 20 秒效果在经过 0.1 秒后被发现，剩余 19.9 秒改为 39.9 秒。
用 modifier 实例和 `GetLastAppliedTime()` 跟踪应用，写入后读取时间戳防止自触发；
刷新时间戳但时长和到期时间未变时不追加，避免仅更新层数造成倍增。失效实例随扫描清理，
不重新施加被驱散的效果；死亡期间暂停，复活继续。首次扫描遇到已有增益也追加一份原始时长。
每种成功修改的 modifier 首次记录 `[lv_octarine_core] buff timer`，用于用户定位生效对象。
不注册全局 modifier filter，不增加客户端自定义 Lua modifier，不重写原生英雄技能。

接口参考：[ModDota 的 CDOTA_Buff API](https://docs.moddota.com/lua_server/docs)。
`SetDuration` 是通用 modifier 接口，不能据此推断技能内部的独立计时、模型、子效果、引导或
召唤物寿命会同步延长。小于扫描间隔的状态可能漏检，光环和其他持续刷新状态可能被引擎重设。
这些均交由用户大胆实测，未启动或操控游戏，也未宣称全部变身兼容。

离线验证：新增时长替身覆盖自身/友方增益、延迟补偿、重复扫描、同实例重施、仅层数刷新、
负面/敌方/永久/零时长排除、驱散后重施、死亡复活及单个接口异常隔离；原有生命周期测试和
全部 14 个运行 Lua 文件语法检查通过。addon 静态检查通过。Python 46 项中 42 项通过，
其余 4 项仍是既有纹理长度断言 `7764 != 7748`，本次未修改纹理。

确认 Dota 已退出后通过 `deploy_items_only.ps1` 部署；19 项 VPK v1 单文件的 CRC、
全部 payload 源码 SHA256 和目标部署哈希通过。包及目标 SHA256：
`39939817F70E30434F0DC88BC005BCB1A11CF54B18FAFEC73D39770FD8F88625`。
旧包备份：`bin/backups/pak01-before-deploy-20260908-234545-4b7c165f04df43ba8925f046bb829801.vpk`。
部署校验通过，游戏内验收待用户进行，未上传 Workshop。

## 初版合成路线与实现（历史，已由上面的永久吸收版取代）

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

### Data-driven 纯粹攻击附伤

2026-08-31 曾在 `item_lv_trident` 的 data-driven modifier `Properties` 中直接使用
`MODIFIER_PROPERTY_PROCATTACK_BONUS_DAMAGE_PURE`。用户在斧王岛实测未生效，战斗日志只有
普通攻击伤害，没有纯粹伤害记录。当前改用 `OnAttackLanded` 调用服务器端 Lua，并由
`ApplyDamage` 显式指定 `DAMAGE_TYPE_PURE`。不要只根据 KV 能被解析或打包成功认定该
modifier property 在普通房间运行时可用。

当前三叉戟实现不设置 `damage_flags`，也不排除幻象、猴子猴孙或建筑，伤害增强、吸血
及目标适用性均交给引擎默认伤害规则处理；实际交互仍需逐项在游戏中验证。

### Data-driven 减速抗性（2026-09-06 取证结论）

**`MODIFIER_PROPERTY_SLOW_RESISTANCE` / `MODIFIER_PROPERTY_SLOW_RESISTANCE_STACKING` 在引擎里不存在**，
不能写进 data-driven `Properties`，也不能在 Lua 的 `DeclareFunctions` 里声明。取证：

- `server.dll` 与 `client.dll` 全文（55 MB + 61 MB）中 `SLOW_RESISTANCE` 子串出现 **0 次**；
- 引擎 modifier 属性注册表（`server.dll` `0x182975660`，**169 条**，每条 32 字节
  `{name*, index, 1, meta*}`）里没有任何减速抗性条目；对照 `CASTTIME_PERCENTAGE` 是 index 117、
  `ATTACK_RANGE_BONUS` 是 104、`MANACOST_PERCENTAGE_STACKING` 是 120，都在表内；
- 引擎导出的 176 个 `GetModifier*` 回调名里有 `GetModifierPercentageCasttime`、
  `GetModifierPercentageManacostStacking`、`GetModifierAttackRangeBonus`，但**没有**
  `GetModifierSlowResistance` 或 `GetModifierSlowResistanceStacking`。

减速抗体由原生 C++ modifier 逐件读取 KV 键 `slow_resistance` 提供（官方 `item_sange` 25、
`item_kaya_and_sange` 25、`item_sange_and_yasha` 30、`item_abyssal_blade` 30）。所以：

- `item_lv_abyssal_skadi` 的减速抗性生效，是因为它的 `AbilityValues.slow_resistance` 是给原生
  `modifier_item_abyssal_blade` 读的，与 data-driven `Properties` 完全无关；
- `item_lv_trident` 把减速抗性写进控制器 `Properties` 必然静默丢失。要修就得改用原生载体
  （如 `modifier_item_kaya_and_sange`，同时读 `slow_resistance` 与 `manacost_reduction`），
  并按「借用原生 modifier」的规则用独立隐藏能力作来源、把不需要的键写 `0`，避免与
  `modifier_item_trident` 的三维/法强等重复叠加。

> 注意：KV 键名本身（`slow_resistance`、`cast_speed_pct`）在 dll 里也搜不到——它们走编译期
> 哈希符号。**不能用"dll 里没有该字符串"推断 C++ 不读该键**；只有 `MODIFIER_PROPERTY_*`
> 这种真实指针表里的缺席，才能作为"键不可识别"的证据。

同日用户在斧王岛完成当前三叉戟版本的试玩验证：普通攻击距离 `+200` 及装备间叠加
表现正常；`MODIFIER_STATE_CANNOT_MISS` 能消除低地攻击高地英雄的落空，但不能消除
低地攻击高地防御塔的落空；加入普通金箍棒后的四条合成路线、100 攻速，以及取消升级
金箍棒后的当前版本均测试无问题。该结果不等于所有英雄、幻象、建筑和伤害修正交互均已覆盖。

### 三叉戟补充属性接入（2026-09-07，游戏内已验证）

保留 `modifier_item_trident`，另以顶层私有隐藏能力 `lv_trident_extras`（ID `10112`）
为来源挂载原生 `modifier_item_kaya_and_sange`。补充能力只提供 `slow_resistance = 100`、
`manacost_reduction = 75`；力量、智力、魔法恢复增强、法强、生命恢复增强均显式设为 `0`。
修正此前 extras 误嵌套在黑龙溅射能力中的括号层级，两项能力现在同属 `DOTAAbilities`。

物品控制器移除上述减速抗性及减蓝耗 `Properties`，物品同名 `AbilityValues` 保留给 tooltip，
静态检查要求其与补充能力数值一致。`MANACOST_PERCENTAGE_STACKING` 在引擎注册表中存在，
不能把它的 data-driven 支持问题等同于减速抗性常量不存在。

同一英雄持有多件三叉戟时，只挂一份补充 modifier；通过物品句柄集合管理生命周期，重复回调
不会重复计数。最后一件卸下时，仅清理本私有来源的 modifier 和本脚本创建的能力，保留普通
慧夜对剑效果。补充效果不按三叉戟件数叠加；与其他原生物品的叠加规则由引擎处理。

隐藏能力不自动继承物品的背包/禁用规则，控制器每 `0.25` 秒检查主装备栏、物品及英雄禁用状态，
仅在需要时挂卸补充效果；死亡期间不补挂，复活后缺失时恢复。状态切换最多有一个检查周期的延迟。
没有 `LinkLuaModifier` 或客户端自定义 Lua modifier；来源创建失败会输出 `[lv_trident] extras failed`，
不回退到直接用三叉戟作来源，以免重复增加属性。

本轮六项 Lua 替身场景与全部 Lua 5.1 语法检查通过；Python 45 项检查中 41 项通过，
四项旧图标长度断言失败（预期 7748，HEAD 与工作区均为 7764 字节，纹理未改动）。三叉戟、
ID、能力顶层结构与共享打包映射检查通过。以上不证明原生 modifier 接受隐藏能力来源后在
游戏中实际生效。由用户验证：无其他减耗来源时，100 蓝技能实扣 25；减速下实际移速；
三维/法强没有重复增加；背包切换、禁用、死亡复活、多件逐一卸下及与普通慧夜对剑同持，
游戏内均确认无问题。

本轮已确认 Dota 退出后使用 `deploy_items_only.ps1` 部署：VPK v1 单文件包含 18 项，
CRC、包内各文件源码 SHA256 与目标部署哈希全部通过。包及目标 SHA256 为
`A8FBA3F71305531CA8602CF25A025091E78977190AA1E557C67D99BA2B026731`；旧包备份为
`bin/backups/pak01-before-deploy-20260906-233650-e1ec39a8e9f542eeb62ff36cc8114201.vpk`。
未上传 Workshop；本次游戏内验证由用户完成，结论只覆盖上述场景。

### 蝶翼之殇：蝴蝶与代达罗斯之殇融合

`item_lv_butterfly_crit` 由原版 `item_butterfly` 和 `item_greater_crit` 加 1 金卷轴合成，
总价 10551。旧的两件独立升级版不再定义，但 `10019/10020` 与 `10035/10036` ID 槽位
继续保留；融合物品使用新 ID `10102`，配方使用 `10101`。

融合属性为两件旧升级版目标值的完整组合：100 敏捷、30% 攻击速度、338 攻击力、
85% 闪避，以及对非建筑单位 100% 触发的 300% 致命一击。

首版曾用 `LinkLuaModifier` 创建 `modifier_item_lv_butterfly_crit_effect`，并把全部属性放在
这个自定义 Lua modifier 中。用户在斧王岛测试正常，但在普通自定义房间合成装备时，
客户端于 2026-08-31 13:49 和 13:53 两次崩溃。两个 access-violation 转储中都有同一条
直接证据：

```text
Filename lv/item_lv_butterfly_crit of modifier modifier_item_lv_butterfly_crit_effect was not found!
```

结论：`dota_lv` 基础覆盖包中的服务器端 `RunScript` 能执行，不代表普通自定义房间的
客户端也能从当前地图的 addon VScript 搜索路径加载该文件。持久 modifier 一旦同步到
客户端，找不到 `LinkLuaModifier` 指定的 Lua 文件可能直接造成客户端崩溃。斧王岛通过
不能代替普通自定义房间验证。

此类基础覆盖物品禁止再向英雄挂载需要客户端加载的自定义 Lua modifier。优先使用：

- 游戏内置 C++ modifier，例如 `modifier_item_greater_crit`；
- 直接写在物品 KV `Modifiers` 中的 data-driven modifier；
- 只在服务器端完成一次性逻辑的 Lua 回调，例如 `ApplyDamage` 或挂载原生 modifier。

蝶翼之殇现已按安全方案重写：原生 `modifier_item_greater_crit` 提供 188 攻击力、100% 暴击
与 300% 倍率；KV modifier 另行提供 150 攻击力、100 敏捷、30% 攻速和 85% 闪避。
不能同时直接挂载原生蝴蝶与原生代达罗斯 modifier，因为两者会从同一物品读取同名
`bonus_damage`，导致攻击力重复或错算。重写版不再包含 `LinkLuaModifier` 或任何自定义
Lua modifier；是否解决普通自定义房间崩溃以及全部属性是否生效，仍须重新实测。

高清图标原稿位于 `artwork/item-icons/item_lv_butterfly_crit.png`。2026-09-02 依据用户选定的
构图参考重绘：蝴蝶在前、代达罗斯之殇在后，两件完整武器对角交叉；蝴蝶保留绿色宝石、
叶翼护手和发光长刃，代达罗斯之殇保留白金弓臂、红色晶体和深色握柄。背景使用左侧翡翠绿、
右侧暖金色的简洁烟雾渐变，使两件武器缩到 88×64 后仍能靠轮廓与色块分开辨认。

运行图使用 `panorama/images/items/lv_butterfly_crit_png.vtex_c`，物品字段保持
`AbilityTextureName = item_lv_butterfly_crit`。高清原稿先用 Lanczos 缩放，再以 `gamma=1.25`、
`brightness=0.04`、`contrast=1.05`、`saturation=1.15` 做轻度预补偿，并强制 Alpha 为 255；
随后通过 `scripts/icon_tool.py vtexreplace` 复用已知可用的 Source 2 纹理结构，只替换 mip0 的
YCoCg-DXT5 图像数据。对最终 `.vtex_c` 回读得到的 88×64 PNG 已完成目视检查，SHA256 为
`6578AE2F1B2FF8FEB5ACDC2CB9F6F94CC663C59A6646034885DDF64F4A630698`。

2026-08-31 15:58 的游戏内截图只验证了上一版图标能够显示两件装备；2026-09-02 的本次重绘
尚需游戏内实测，不能把纹理解码检查或部署成功视为显示效果已经确认。此前把 88×64 PNG 直接
放进 `resource/flash3/images/items/` 的做法在 `dota_lv` 基础覆盖模式中只显示黑色，仍不采用。

### 蝶翼之殇 BAT 实验（2026-09-08，Constant 版本待实测）

用户在同为 700 攻速时实测此前 `BASE_ATTACK_TIME_CONSTANT_ADJUST = -0.2` 的 KV
原型，装备前后面板攻击间隔未改变。本机 `server.dll` 的 Data-Driven 分派函数
`0x180c65440` 对 `CONSTANT_ADJUST`（index 39）及 `PERCENTAGE`（index 40）进入
`Unhandled data-driven modifier function %s.` 分支；`CONSTANT`（index 38）有对应处理。
以上地址对应 DLL SHA256 `76908365d189e2ac12599c4083875cf2b5acace4a7d2dff1dfed0a0f1cdec694`，
不能把新版 Lua 枚举存在等同于 Data-Driven 支持。

按用户要求，将失败的 ADJUST 项替换为 `MODIFIER_PROPERTY_BASE_ATTACK_TIME_CONSTANT`，
读取物品 `AbilityValues.base_attack_time = 1.2`。含义是固定 BAT 为 1.2 秒，
不是减少 1.2 秒；用户接受炼金、巨魔等其他 BAT 来源的优先级交互。本轮沿用既有纯 KV
控制器与原生暴击 modifier，不添加客户端 Lua modifier，不修改银月之晶。
无其他 BAT 修正时，700 攻速的理论攻击间隔为 `1.2 / 7 ≈ 0.1714` 秒。
实测生效。

### 不洁魔心：撒旦之邪力与恐鳌之心融合

`item_lv_satanic_heart` 由原版 `item_satanic` 和 `item_heart` 加 1 金卷轴合成，总价
10251（5050 + 5200 + 1）。旧的两件独立升级版不再定义，但 `10043/10044` 与
`10077/10078` ID 槽位继续保留；融合物品使用新 ID `10104`，配方使用 `10103`。

数值采用「顺水推舟」方案：`AbilityValues` 里的 `bonus_strength` 只写 `75`，因为
`modifier_item_heart` 和 `modifier_item_satanic` 会从同一个物品各读一次这个键，合计
**150 力量**。这是刻意设计，不是重复计数的 bug——不要为了"修正"而把它改成 150 或 37.5。
其余数值按来源分工：

| 键 | 值 | 读取方 |
|---|---|---|
| `bonus_strength` | `75` | heart + satanic（各一次 → 150） |
| `hp_regen` / `missing_health_regen` | `2` / `1.5` | `modifier_item_heart` |
| `bonus_damage` / `lifesteal_percent` | `25` / `30` | `modifier_item_satanic` |
| `unholy_lifesteal_percent` | `145` | `modifier_item_satanic_unholy` |
| `unholy_lifesteal_total_tooltip` | `175` | 仅悬停说明 |
| `unholy_duration` | `6.0` | 需由 Lua 显式传给 buff |

主动技能必须自己重建——**而且不止是 duration**。原生撒旦的
`CDOTA_Item_Satanic::OnSpellStart`（`server.dll` 中 `0x1549d90`，250 字节，共引用
`unholy_duration` / `duration` / `modifier_item_satanic_unholy` /
`DOTA_Item.Satanic.Activate` 四个字符串）一次做了三件事，而 `item_datadriven`
**不会执行那个 C++ 函数**，三件都得在 `OnSpellStart` 的 Lua 回调里重做：

| 原生 C++ 做的事 | Lua 重建方式 | 漏掉的后果 |
|---|---|---|
| 读取 `unholy_duration` 设置 buff 时长 | 显式 `AddNewModifier(..., { duration = ... })` | buff 永不到期 |
| 对施法者施加**弱驱散** | `hero:Purge(false, true, false, false, false)` | tooltip 承诺了弱驱散却不生效 |
| 播放 `DOTA_Item.Satanic.Activate` | `hero:EmitSound(...)` | 开启动静全无 |

顺序也有讲究：原版是**先驱散、后上 buff**（Liquipedia：*"The basic dispel
activates on CAST before the lifesteal boost begins"*）。反过来会让刚上的 buff
被残留 debuff 顶掉。

### `Purge` 的 Lua 签名是 5 个 bool，不是文档里那套

`server.dll` 里的 Lua 绑定描述原文：

```
(bool RemovePositiveBuffs, bool RemoveDebuffs, bool BuffsCreatedThisFrameOnly,
 bool RemoveStuns, bool RemoveExceptions)
Purge
Script_Purge
```

网上流传的 `Purge(bool, bool, handle, float, bool)` 是**过时的**。照它写会踩坑：
第 4 参是 float 时长，传 `0` 在 Lua 里是 **truthy**，等于把弱驱散升级成连眩晕一起
解掉，和原版语义不符。弱驱散（只清负面、不清正面、不清眩晕）的正确调用是
`hero:Purge(false, true, false, false, false)`。

> 通用排查法：任何「原生物品主动技能转成 datadriven 后少效果」的问题，先去
> `server.dll` 里 grep 该物品的 `CDOTA_Item_Xxx`，用 RIP-relative `lea` 建 xref
> 反查表定位 `OnSpellStart`，再看它引用了哪些字符串。字符串只覆盖音效/粒子/
> KV 键名，**驱散这类纯函数调用不留字符串痕迹**，得靠 wiki 交叉验证。

控制器 `modifier_item_lv_satanic_heart_controller` 不提供任何 `Properties`，只负责用
`RunScript` 挂/卸两个原生 modifier，规避 datadriven `Properties` 只有约 94/409 个键真正
生效的坑。Lua 文件同样不含 `LinkLuaModifier` 或任何自定义 Lua modifier。

2026-09-02 图标重绘为两个清晰主体：巨兽之心位于中央前景，完整的银黑色撒旦月牙刃从
后方环抱。高清原稿为 `artwork/item-icons/item_lv_satanic_heart.png`（1470×1070），运行时
源图为 `artwork/item-icons/lv_satanic_heart.png`（87×64）。缩放后采用 `gamma=1.45`、
`brightness=0.08`、`contrast=1.08`、`saturation=1.28` 做显示预补偿并强制 Alpha 为 255。

运行图 `panorama/images/items/lv_satanic_heart_png.vtex_c` 通过
`scripts/icon_tool.py vtexreplace` 复用已知可用的 Source 2 纹理结构并替换 mip0 的
YCoCg-DXT5 数据；回读图已完成目视检查，SHA256 为
`028F3C6CDF3AC700D761C32AEC58BC064D3246B893F3D1D60CE9225D62874228`。用户随后自行部署并
完成游戏内测试，确认本次重绘显示正常、未发现问题；该结论只覆盖当前图标版本的显示效果。

**游戏内验证进度（2026-09-02 自定义房间实测）：** 150 力量、30% 吸血、主动后 175%
吸血、6 秒时长、5 秒冷却、2% 最大生命恢复、1.5% 缺失生命恢复**全部正确**，且自定义
房间未崩溃客户端。

首轮实测漏了弱驱散和音效（根因见上表），已于同日补齐并重新部署。用户随后复测确认：
开启时能清除自身沉默、减速等可弱驱散负面效果，不清眩晕和自身正面 buff；原版撒旦启动
音效及 `particles/items2_fx/satanic_buff.vpcf` 粒子均正常。以上结论来自当前自定义房间测试，
不扩展为全部英雄、全部模式和全部 modifier 交互均已验证。

### 无间神镜盾：林肯法球与清莲宝珠的可消耗融合

`item_lv_mirror_shield` 由原版 `item_sphere` 和 `item_lotus_orb` 加 1 金卷轴合成，总价
8651（4800 + 3850 + 1）；物品与配方使用 ID `10106/10105`。成品进入存活本体英雄的
主装备栏后自动吸收，释放物品格；两件材料的属性和主动技能均不保留。

永久效果直接使用游戏内置 C++ `modifier_item_mirror_shield`，由成品的 `AbilityValues`
提供 `reflect_chance = 100` 与 `block_cooldown = 0`。服务器端一次性 Lua 只负责挂载原生
modifier、建立纯 KV 状态图标并调用 `TakeItem` 隐藏成品；不包含 `LinkLuaModifier`、
自定义 Lua modifier 类或客户端需要解析的 Lua 文件名。

和永恒真视宝石相同，吸收后的物品实体不会销毁，而由服务器表保留隐藏句柄。这样原生镜盾
modifier 仍有稳定的 AbilityValues 来源，状态图标也关联客户端已知的 data-driven item。
挂载、状态图标或隐藏任一步失败都会销毁本轮效果并尝试把成品放回装备栏；同一英雄已经成功
吸收后，第二件成品不会再次吸收。

静态检查、Lua 替身测试、VPK 包校验和部署哈希均不能证明零冷却原生镜盾在真实游戏中的
行为。必须在普通自定义房间验证：合成树、自动吸收、死亡复活、不可驱散、连续多个指向性
技能、同一帧多个技能，以及原版明确不触发法术抵挡/反弹的例外技能。未完成实测前不得记录
为游戏内成功。

**首次部署记录（2026-09-02 14:51）：** 部署前确认 `dota2` 进程不存在；6 项 ID 检查、
14 项资源集成检查、新镜盾 Lua 控制流替身测试、原有宝石/撒旦回归与 14 项打包回归均通过。
VPKEdit v1 单文件包共 14 个清单文件，CRC、逐文件源码 SHA256 与部署目标哈希校验通过；产物及
`dota_lv/pak01_dir.vpk` 的 SHA256 均为
`5351C65FA3964DF4D122301B849516BAC548D2E69DAC8D58B7C34A64B9C26BE5`。部署前备份为
`bin/backups/pak01-before-deploy-20260902-145130-8f671af173bb4eb4907de1d032ce5665.vpk`。
用户随后在普通本地房间反馈“没问题”，据此确认当前组合版本能够完成合成、吸收并产生预期的
零冷却镜盾效果；未逐项覆盖所有技能、同帧多次施法、英雄和游戏模式，不扩大验证范围。

### 龙息溅射：狂战斧与升级卷轴的可消耗融合

`item_lv_dragon_splash` 由原版 `item_bfury` 或 `item_specialists_array` 和 100 金升级卷轴合成，
物品标价 4000（按狂战斧路线），物品与配方
使用 ID `10110/10109`。成品进入存活本体英雄的主装备栏后自动吸收，不保留狂战斧属性，也不
占用物品格；吸收后永久提供 50 点攻击力、10 点生命恢复和 5 点魔法恢复。

为避免修改官方 `npc_abilities.txt`，新增私有隐藏能力 `lv_black_dragon_splash_attack`（ID
`10111`）。名称保留兼容，但溅射不再使用黑龙原生 modifier；服务器端 Lua 将该能力添加到英雄，
然后挂载 Valve 的原生 `modifier_item_gunpowder_gauntlets`。私有能力提供
`splash_radius = 500`、`splash_pct = 100`，因此沿用火药手套的原生溅射路径：每个单位按原始攻击
伤害独立进行一次护甲结算，不会把主目标已经减甲后的实际伤害再次减甲。龙息原有的 50 点攻击力
通过独立的 `dragon_bonus_damage` 状态属性提供，避免被原生火药手套的额外魔法伤害字段重复计算。
状态栏图标不使用 `LinkLuaModifier` 或客户端自定义 Lua 类；若当前游戏构建不接受私有能力作为
原生 modifier 的来源，脚本会回退为使用隐藏成品物品作为来源，因此仍不需要打包官方
`npc_abilities.txt`。

新图标为黑龙利爪与橙色冲击火花的组合：ImageGen 高分辨率原稿位于
`artwork/item-icons/item_lv_dragon_splash.png`（1254×1254），88×64 运行源图位于
`artwork/item-icons/lv_dragon_splash.png`，游戏资源为
`panorama/images/items/lv_dragon_splash_png.vtex_c`。成品与私有被动技能的
`AbilityTextureName` 均指向 `item_lv_dragon_splash`，因此同一图标会显示在物品栏和永久溅射
状态栏中。运行图使用 `scripts/icon_tool.py vtexreplace` 编码为 YCoCg-DXT5 单 mip，并强制
Alpha 为 255。

状态 modifier 设置为 `RemoveOnDeath = 0`；Lua 每 `0.25` 秒检查并在死亡复活后补回
`modifier_item_gunpowder_gauntlets`。如果私有能力创建失败，脚本会回退为使用隐藏成品物品作为
原生 modifier 的来源。

当前已完成 KV/Lua 静态检查与 VPK v1 包校验（18 个清单文件）；切换到火药手套原生 modifier
路径后，私有能力加载、近战/远程触发、范围 500、死亡复活后的持续性以及“每个单位一次护甲结算”
仍需在普通自定义房间实测后再记录为已验证。

### 深渊冰眼：两件升级装备的二次融合

`item_lv_abyssal_skadi` 由原版 `item_abyssal_blade` 和 `item_skadi` 加 1 金卷轴合成，
总价 12151（6250 + 5900 + 1）；物品与配方使用 ID `10108/10107`。旧升级物品
`item_lv_abyssal_blade`、`item_lv_skadi` 及其配方不再定义；对应的 `10005/10006`、
`10085/10086` ID 保持空置，避免复用已发布过的标识。

成品为 `item_datadriven`，服务器端控制器挂载引擎内置的
`modifier_item_abyssal_blade` 与 `modifier_item_skadi`。前者继续提供 105 攻击力、20% 生命
恢复增强、重击和减速抗性；后者继续提供三维属性及霜冻攻击。`bonus_strength` 特意写成 `0`，
由 `bonus_all_stats = 100` 统一提供力量、敏捷、智力各 100；否则深渊 modifier 会在冰眼的
100 全属性之上再增加力量。`slow_resistance` 单独提升到 100。

原版 `CDOTA_Item_AbyssalBlade::OnSpellStart` 不会被 `item_datadriven` 自动执行，因此主动
强击由纯服务器端 Lua 重建。对本机 2026-08-30 的 `server.dll` 反查确认，该函数依次涉及：

- 先进行目标法术抵挡检查；被抵挡时直接结束；
- 播放 `particles/items_fx/abyssal_blink_start.vpcf` 与
  `particles/items_fx/abyssal_blade.vpcf`；
- 读取 `stun_duration`，向目标施加内置 `modifier_bashed`；
- 播放 `DOTA_Item.AbyssalBlade.Activate`。

当前 Lua 按以上语义重建，不含 `LinkLuaModifier` 或自定义 Lua modifier 类。静态 KV/ID/资源
集成检查及 Lua 控制流替身测试已通过；这些检查不能证明两个原生 modifier 的全部属性、
减益免疫交互、法术抵挡/反弹、粒子附着及合成树在普通本地房间中均正确，部署后仍须实测。

新图标把完整斯嘉蒂之眼置于后层，完整深渊之刃斜向叠放在前层，以青色冰光和暗红火光
区分两件装备。ImageGen 高分辨率原稿位于
`artwork/item-icons/item_lv_abyssal_skadi.png`，88×64 运行源图位于
`artwork/item-icons/lv_abyssal_skadi.png`，游戏资源为
`panorama/images/items/lv_abyssal_skadi_png.vtex_c`，SHA256 为
`0F8644A1ED923E2CA50DED0E7799D297076F95E1334A8BB3E6D038E7751E3C96`。运行图使用
`scripts/icon_tool.py vtexreplace` 编码成 YCoCg-DXT5，并强制 Alpha 为 255；该命令复用现有 88×64 单 mip
编译纹理的 Source 2 结构块，只替换像素 payload。

### 怪蛇之息自动吸收（2026-09-08，待游戏内验收）

`item_lv_hydras_breath` 保留 ID `10048`、配方 ID `10047`、原怪蛇之息加 1000 金
卷轴的合成路线（总价 6900）。定义和中英文说明均直接维护在标准 addon 文件中，
保留原 ID，不依赖额外生成步骤。

成品改为 `item_datadriven`，沿用宝石/镜盾的延迟吸收与 `TakeItem` 隐藏实体方式。
存活本体英雄的主装备栏可吸收；幻象、克隆、天穹分身、信使及储藏处排除。每英雄一次，
重复物品保留可售；判重依据已吸收的隐藏物品，不依赖死亡时可能消失的原生 modifier。
挂载失败或隐藏后丢失效果时清理本物品来源的 modifier 并恢复物品。

服务器挂载 `modifier_hydras_breath`，保留 15 力量、30 敏捷、25 攻击力、
100% 触发、360 度、最多 10 个额外目标、100% 分裂攻击伤害、20 固定触发附伤，
以及持续 3 秒、每秒 2.5% 最大生命值的瘴毒。没有自行实现攻击事件或客户端 Lua modifier。
原生 `base_attack_range` 归零，纯 KV 永久状态通过
`MODIFIER_PROPERTY_ATTACK_RANGE_BONUS = %permanent_attack_range%` 单独提供 800 射程，
避免和原生距离重复。状态不可驱散、死亡不移除，每 0.25 秒在英雄存活时补回缺失的原生被动。

Lua 生命周期替身（含隐藏清理、失败回滚、同帧重复合成、复活恢复）和 14 个运行 Lua
文件的 5.1 语法检查通过。Python 46 项中 42 项通过；4 项为既有图标长度断言
`7764 != 7748`，本轮没有修改图标。KV、ID 与源码映射检查通过。
这些检查不能证明引擎原生被动接受隐藏 data-driven 来源后的实际攻击行为。
用户需在普通本地房间验证吸收、属性不重复、800 射程及与三叉戟叠加、远程分裂及瘴毒、
近战不触发分裂、死亡复活及重复合成。未启动游戏，未上传 Workshop。

逐项比较发现银月之晶运行定义已有 1000 夜间视野，而旧清单记录仍为 600；
本轮确认直接维护的运行定义保持为 1000。最终语义比较确认仅怪蛇之息物品定义改变，
配方及所有其他物品定义/ID 不变。

本轮已确认 Dota 退出并通过 `deploy_items_only.ps1` 部署。VPK v1 单文件包含 19 项，
CRC、逐文件源码 SHA256 与目标部署哈希均通过。包和目标 SHA256：
`3403E74D26F0B376728B759BC2BCCABD5FCF224BF1BF319FF4D9D2F49F0D4C79`。
旧包备份：`bin/backups/pak01-before-deploy-20260908-134602-198cf38724fe435dbfd5428e5f287d5f.vpk`。
以上是离线检查和首版部署结果。

用户实测首版未吸收。2026-09-08 14:07:17 的 `console.log` 明确报
`Attempted to create unknown modifier type modifier_item_hydras_breath!`，随后脚本输出
`initialization failed; item retained`。因此回调已执行，但原生挂载失败，物品按回滚规则保留。
首版把 C++ 类 `CDOTA_Modifier_Item_HydrasBreath` 的名称错误地推导为带 `item_` 的
modifier 名；本机 `server.dll` 和 `client.dll` 实际包含的完整注册名是
`modifier_hydras_breath`。本轮修正运行脚本和替身中的错误名称；替身测试通过本身
不能验证引擎是否注册某个名称，今后须单独核对引擎。

已对照狂战升级版 `item_lv_dragon_splash`：它优先用隐藏能力作为原生火药手套 modifier
的来源，失败时回退隐藏物品；怪蛇目前直接使用隐藏物品，两者均用 `TakeItem` 释放格子，
由永久 KV 状态在复活后补回原生被动。当前故障发生在隐藏物品之前，修正注册名即可
处理已证实的失败点，无需为此迁移到隐藏能力方案。修正版吸收及攻击效果仍需游戏实测。

修正版于 2026-09-08 21:51 确认游戏退出后重新部署；生命周期替身、addon 静态检查、
19 项 VPK v1 CRC/源码 SHA256 和部署哈希通过。当前包 SHA256：
`FE7CA032D91B828D5C7A5C410E64C210D362F5EE60FB2EFD0E2F3A421A90BBA6`。
被替换首版备份：`bin/backups/pak01-before-deploy-20260908-215108-9924f0a916e64a3194eeafc039e57290.vpk`。

## 辉耀与希瓦融合：霜阳神铠

新增手工物品 `item_lv_radiance_shivas_guard`（ID 10114）及 1 金配方
`item_recipe_lv_radiance_shivas_guard`（ID 10113），不替换现有的
`item_lv_radiance` 与 `item_lv_shivas_guard`。三条配方路径同时保留，并按下列顺序定义：

1. `item_radiance;item_shivas_guard;`；成品标价 9201。
2. `item_lv_radiance`。
3. `item_lv_shivas_guard`。

替代路径按其实际材料价合成，不强行补齐总价值。物品通过 data-driven 控制器挂载原生
`modifier_item_radiance` 和 `modifier_item_shivas_guard`，保留两套属性与被动；辉耀没有开关入口，
灼烧保持常开。物品现为纯被动，不提供希瓦冲击波主动。

融合物品提供 100 攻击力、90% 闪避、50 护甲、400 作用范围加成；灼烧与霜冷光环
基础半径统一为 1200。原升级希瓦的 `bonus_aoe` 同步调整为 400，其余既有强化
（50 护甲、-140 攻速光环、10 秒减速、1200 冲击半径、600 扩张速度）直接保留在物品定义中。
Lua 替身只能验证原生 modifier 的挂载与清理流程，
常开灼烧、双被动实际属性及三条路线的游戏内选择优先级仍需实测。

2026-09-09 确认 Dota 已退出后通过 `deploy_items_only.ps1` 部署。VPK v1 单文件包含 20 项，
CRC、逐文件源码 SHA256 与目标部署哈希均通过。包和目标 SHA256：
`0938A739DA3B00B335EA0E04DFFA08B0F023827C3AF1BED6CE417184AA7F9918`。
旧包备份：`bin/backups/pak01-before-deploy-20260909-200214-cbfe682d900942788eaae10815814988.vpk`。
以上仅为离线检查与部署结果，不视为游戏内行为验证。

用户随后实测属性与被动均生效，但按下主动后游戏严重卡顿且英雄消失。同期
`console.log` 未记录 Lua 运行错误，却在异常时刻记录 `Entities =`、`Num entities = 0`。
这与把原生 `modifier_item_shivas_guard_thinker` 直接挂到英雄后，其 thinker 生命周期处理父实体
相符。为避免再次删除英雄或造成帧阻塞，已移除 `OnSpellStart`、冷却、耗蓝和主动 Lua 路径，
物品改为 `DOTA_ABILITY_BEHAVIOR_PASSIVE`；全部属性、常开灼烧与霜冷光环保持不变。
修正版确认 Dota 退出后重新部署；清理临时生成器后再次构建并部署，20 项 VPK v1 校验和
目标哈希均通过。当前包 SHA256：
`92FBE985F64261010ADC67A77D84BACEAC326C751161DFB6D0A366EDC5A9B349`；被替换包备份为
`bin/backups/pak01-before-deploy-20260909-202154-de668e97a4164126b94aae8c2ce2a9e6.vpk`。

## 本地化

当前在 addon 的 `resource/addon_*.txt` 的 `Tokens` 块中添加自定义键；VPK 构建器自动合入官方完整本地化。简体中文核心示例：

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

`extract_latest.ps1` 从官方 VPK 同步完整 `scripts/npc/`、`scripts/shops.txt` 和中英文
`abilities_*.txt`。前者覆盖物品、能力 ID、英雄/单位定义及全量兼容包输入；后两类覆盖商店和物品文本。
不提取整个官方 `scripts/`，避免把无关 Lua、UI 等内容长期纳入仓库。

脚本先提取到被忽略的 `bin` 临时目录，确认关键文件齐全后再替换 `pak01_dir`，因此官方新增、修改和删除
都会成为可审查的 Git diff；提取失败则保留旧基线。运行前先处理该目录中的未提交改动，提取后检查差异、
运行测试并单独提交一次官方基线更新。

## 下次新增装备检查清单

- [ ] 检查当前分支、未提交改动及已有自定义物品，避免覆盖。
- [ ] 新物品与新配方分别使用独立内部名及不冲突的 ID。
- [ ] 保留原物品；核对属性字段、配方材料、产物和两种价格。
- [ ] 在 addon 中英文 `addon_*.txt` 增加对应键；由 VPK 构建器生成完整覆盖文本，不直接修改官方基线。
- [ ] 默认不改 `shops.txt`；通过合成关系树提供购买入口。
- [ ] 核对打包清单，避免漏掉 `#base` 引入的文件或 Lua 依赖。
- [ ] 基础覆盖物品不得给英雄挂载自定义 Lua modifier；使用原生 modifier、KV modifier
      或纯服务器端 Lua，并在普通自定义房间验证客户端不会报 `Filename ... was not found`。
- [ ] 获得部署授权、确认游戏退出，核验包内容与部署哈希。
- [ ] 由用户在游戏中检查升级树、配方购买、合成、描述和图标。
- [ ] 分别检查实际属性数值生效；不要把文本显示当作行为验证。
