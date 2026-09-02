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

### Data-driven 纯粹攻击附伤

2026-08-31 曾在 `item_lv_trident` 的 data-driven modifier `Properties` 中直接使用
`MODIFIER_PROPERTY_PROCATTACK_BONUS_DAMAGE_PURE`。用户在福王岛实测未生效，战斗日志只有
普通攻击伤害，没有纯粹伤害记录。当前改用 `OnAttackLanded` 调用服务器端 Lua，并由
`ApplyDamage` 显式指定 `DAMAGE_TYPE_PURE`。不要只根据 KV 能被解析或打包成功认定该
modifier property 在普通房间运行时可用。

当前三叉戟实现不设置 `damage_flags`，也不排除幻象、猴子猴孙或建筑，伤害增强、吸血
及目标适用性均交给引擎默认伤害规则处理；实际交互仍需逐项在游戏中验证。

同日用户在福王岛完成当前三叉戟版本的试玩验证：普通攻击距离 `+200` 及装备间叠加
表现正常；`MODIFIER_STATE_CANNOT_MISS` 能消除低地攻击高地英雄的落空，但不能消除
低地攻击高地防御塔的落空；加入普通金箍棒后的四条合成路线、100 攻速，以及取消升级
金箍棒后的当前版本均测试无问题。该结果不等于所有英雄、幻象、建筑和伤害修正交互均已覆盖。

### 蝶翼之殇：蝴蝶与代达罗斯之殇融合

`item_lv_butterfly_crit` 由原版 `item_butterfly` 和 `item_greater_crit` 加 1 金卷轴合成，
总价 10551。旧的两件独立升级版不再生成，但 `10019/10020` 与 `10035/10036` ID 槽位
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

高清 3D 图标原稿位于 `artwork/item-icons/item_lv_butterfly_crit.png`，蝴蝶与代达罗斯之殇
作为两个完整、独立的物体交叉叠放，不再采用融合造型。当前构图专门面向 88×64 缩略图：
两件武器放大填满画面，红色晶体使用明显的大色块，背景简化为明亮黄绿色。

运行图使用 `panorama/images/items/lv_butterfly_crit_png.vtex_c`，物品字段保持
`AbilityTextureName = item_lv_butterfly_crit`。2026-08-31 15:58 的游戏内截图已确认这一版能够
显示两件装备；其画面背景偏黑，但比此前的粉白像素块版本稳定。后续尝试把 88×64 PNG 直接
放进 `resource/flash3/images/items/`，在 `dota_lv` 基础覆盖模式中只显示黑色，因此已经回退。

这份 `.vtex_c` 直接从 16:03:56 的部署前备份恢复，SHA256 为
`A8337DEC323FDC937278DBED91B7E007E1702F9C7F30502F0FB4112440572218`。不要重新用手写 `.vtex`
覆盖它；不同编译尝试曾分别造成黑色空白、粉白像素块和明显色偏。

旧高清原稿本身所有像素均为完全不透明，但背景接近纯黑；首次缩放到 88×64 时，重采样还在
边缘产生了 Alpha 221–254 的半透明像素。游戏用黑色物品面板合成这些像素后，视觉上会像
透明素材直接漂在背景上。当前原稿改为左侧翡翠绿、右侧橄榄金黄的较明亮渐变背景；运行时
图在编译前仍强制 Alpha 为 255，避免继续依赖界面底色。

### 不洁魔心：撒旦之邪力与恐鳌之心融合

`item_lv_satanic_heart` 由原版 `item_satanic` 和 `item_heart` 加 1 金卷轴合成，总价
10251（5050 + 5200 + 1）。旧的两件独立升级版不再生成，但 `10043/10044` 与
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

图标沿用官方撒旦图标换色（magma 岩浆红）而非重画，源图
`artwork/item-icons/lv_satanic_heart.png`（87×64），运行图
`panorama/images/items/lv_satanic_heart_png.vtex_c`，SHA256
`7666F5F422A42BDF4DCB8391C17F18212B185C8841FAE07FE526022F186BACEE`。
官方 panorama 图标是 **YCoCg-DXT5**，但本机新版 `resourcecompiler` 不再生成该编码
（有 `ConvertToYCoCg` 字符串却不执行，实测输出直 RGB DXT5），因此这份 `.vtex_c` 由
`scripts/icon_tool.py` 自研编码器把 mip0 编码后 splice 回编译模板。详见
`scripts/icon_tool.py` 与 `scripts/vtex_inspect.py`。

**游戏内验证进度（2026-09-02 自定义房间实测）：** 150 力量、30% 吸血、主动后 175%
吸血、6 秒时长、5 秒冷却、2% 最大生命恢复、1.5% 缺失生命恢复**全部正确**，且自定义
房间未崩溃客户端。

首轮实测漏了弱驱散和音效（根因见上表），已于同日补齐并重新部署。用户随后复测确认：
开启时能清除自身沉默、减速等可弱驱散负面效果，不清眩晕和自身正面 buff；原版撒旦启动
音效及 `particles/items2_fx/satanic_buff.vpcf` 粒子均正常。以上结论来自当前自定义房间测试，
不扩展为全部英雄、全部模式和全部 modifier 交互均已验证。

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
- [ ] 基础覆盖物品不得给英雄挂载自定义 Lua modifier；使用原生 modifier、KV modifier
      或纯服务器端 Lua，并在普通自定义房间验证客户端不会报 `Filename ... was not found`。
- [ ] 获得部署授权、确认游戏退出，核验包内容与部署哈希。
- [ ] 由用户在游戏中检查升级树、配方购买、合成、描述和图标。
- [ ] 分别检查实际属性数值生效；不要把文本显示当作行为验证。
