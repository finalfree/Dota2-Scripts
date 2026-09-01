# 真视宝石自动吸收实验

初版日期：2026-08-28。分支：`addons`。1800 范围 Lua 光环版曾在试玩中通过，但普通本地房间会因客户端无法加载自定义 Lua modifier 而崩溃。

## 当前方案：全图原生真视（2026-09-01）

```text
真视宝石 item_gem（900）
  + 真视宝石·永恒配方 item_recipe_lv_gem（800）
  → 真视宝石·永恒 item_lv_gem（总价 1700）
  → 进入存活英雄主装备栏后自动吸收
  → 为本队永久启用全图原生 modifier_truesight，物品格释放
  → 吸收者保留“永恒真视”状态图标
```

- 不再创建或链接 `modifier_lv_gem_consumed`；该文件已删除，也不进入打包清单。购买者只在服务器 Lua 表中登记，不向客户端同步自定义 Lua modifier。
- 吸收时使用 `FindUnitsInRadius(..., FIND_UNITS_EVERYWHERE, ...)` 扫描一次已有敌方单位；对英雄、普通单位、召唤物、幻象、建筑、信使和守卫使用引擎原生 `modifier_truesight`。中立和无队伍单位排除。
- 监听 `npc_spawned`，延迟 0.03 秒等待队伍初始化后处理新英雄、复活英雄、狼人小狼、幻象和新插的真假眼；监听 `npc_replaced` 处理实体替换。
- 每 2 秒全图巡检一次，作为事件缺失、原生 modifier 添加失败或特殊单位的兜底；已存在由本宝石来源施加的真视时不重复添加。
- 效果按队伍唯一：同队第二件成品保留、不吸收、可出售。购买者死亡不暂停全图效果。
- 只提供正常真视侦测，不调用 `AddFOWViewer`，不打开战争迷雾；敌人在己方普通视野之外时仍不可见，真视免疫机制仍按原版规则处理。
- data-driven 隐藏被动仍负责检测成品进入主栏并调用服务器脚本。吸收者身上的 `modifier_item_lv_gem_consumed_status` 是纯 KV 的显示状态，不含属性、光环或 Lua 类，使用原宝石图标，设置为不可驱散且死亡不移除。
- 脚本建立状态图标、初次扫描和周期巡检后，使用引擎 `TakeItem` 隐藏成品并释放物品格，而不是销毁其实体；这样显示状态始终关联一个客户端已知的 data-driven item。隐藏后的句柄只由服务器表保留，不落地也不进入其他栏位。任一初始化步骤失败则回滚并保留物品。

当前检查命令仍见下文。Lua 替身测试覆盖初次扫描、狼人/幻象/真假眼创建事件、实体替换、2 秒巡检、监听失败降级、原生 modifier 失败重试、状态图标或物品隐藏失败时的回滚、初始化失败保留物品和重复保护。替身不能证明本地房间事件投递、HUD 显示或真实反隐，必须由用户实测。

## 历史方案：1800 范围自定义 Lua 光环（2026-08-28）

## 目标与规则

```text
真视宝石 item_gem（900）
  + 真视宝石·永恒配方 item_recipe_lv_gem（800）
  → 真视宝石·永恒 item_lv_gem（总价 1700）
  → 进入存活英雄的主装备栏后自动吸收（不需要点击）
  → 永久 modifier_lv_gem_consumed，1800 范围真视，物品格释放
```

- 原宝石、玲珑心升级及官方商店列表保持不变；通过原宝石升级树购买卷轴。
- 永久效果不可驱散，死亡不移除；死亡期间暂停光环，复活后恢复。不保留宝石主动“现形”。
- 不增加普通视野、飞行视野，也不主动打开战争迷雾。使用原生 `modifier_truesight`，对敌方单位生效，目标类型包含守卫；真实视野规则仍须实测。
- 幻象、克隆体、天穹分身和信使不能吸收。只检查主装备栏 0–5；储藏处、地面、背包及中立物品栏不吸收。死亡时获得的物品等复活并进入主装备栏后再吸收。
- 每名英雄只能吸收一次。第二件合成品保留，不叠加效果、不再次销毁；允许出售。没有增加全局购买过滤器来阻止再次买卷轴，故仍应避免重复购买。
- 待吸收物品不继承原宝石被动，脚本失败时也不会假装已经拥有真视。以物品消失、增益图标和实际反隐一起判断成功。

## 实现与依赖

| 文件 | 用途 |
| --- | --- |
| `pak01_dir/scripts/npc/lv/lv_items.txt` | 新配方 ID 10003、新物品 ID 10004；保留原玲珑心条目 |
| `pak01_dir/scripts/vscripts/lv/item_lv_gem.lua` | 数据驱动被动事件触发、延迟吸收、持有者校验和重复保护 |
| `pak01_dir/scripts/vscripts/lv/modifier_lv_gem_consumed.lua` | 独立永久真视光环；半径保存在 modifier 中，不再引用已移除物品 |
| `pak01_dir/resource/localization/abilities_{english,schinese}.txt` | 完整原文件中各新增 9 个名称、说明和增益文本键 |
| `packaging/items.txt` | 原五文件加上两份 Lua，共七个文件 |

沿用已有的 `npc_abilities.txt` → `#base "lv/lv_items.txt"`，不改单位文件、不创建游戏模式实体、不引入天地星初始化、祝福或经济过滤器。

触发由数据驱动物品的被动 modifier `OnCreated` / `OnIntervalThink` 调用 `RunScript`。第一次检测后延迟 0.1 秒，避开合成过程中销毁物品；0.25 秒检查用于重试。执行前重新检查英雄、存活状态、持有者、主栏位置和已有效果。

成功创建永久 modifier 后才移除物品。半径无效、添加 modifier 报错或返回无效对象时保留物品并输出错误。创建效果时的 ability 参数为 `nil`，避免后续依赖已销毁的物品句柄。

数据驱动被动事件机制参考[官方文档](https://www.dota2.com.cn/wiki/Dota_2_Workshop_Tools/Scripting/Abilities_Data_Driven.htm)；Lua 光环回调参考 [ModDota API 声明](https://github.com/ModDota/API/blob/master/examples/vscript/declarations/dota-modifier-properties.d.ts)。这些资料不能证明本地覆盖模式已经运行成功。

## 初版检查记录（900 范围）

- 4 项 Python 资源检查通过：KV 结构及名称/ID、配方和总价、事件与打包依赖、两种语言本地化。
- 12 项 Lua 5.1 逻辑测试通过：延迟与重复触发、不合格单位/栏位、延迟期间死亡或转移、复活重试、并发两件物品、添加效果失败保留、无效半径、移除物品兼容性、死亡期间光环开关及客户端不修改状态。
- Lua 通过 Lupa 2.8 的 Lua 5.1 运行时执行；测试中的 Dota 实体/API 是替身，不是真正的游戏引擎。没有验证 KV 事件实际触发、Lua modifier 客户端加载/同步、真视目标、地形遮挡、驱散、幻象或复活的实际行为。
- 包内容已检查：VPK v1 单文件，共七个清单文件；VPKEdit CRC 校验和独立逐文件源码 SHA256 比对通过。
- 现有打包回归测试 14 项通过（`tests/test_packaging.ps1`），未向游戏目录部署。
- 原物品、能力入口及商店无差异；移除新增的本地化键后文本与本轮开始时完全一致，原玲珑心定义保持不变。保留已有文本的 CRLF 换行。
- 最终实验包 SHA256：`BA845CA8FA7BA7E9A2A930A6ACEA59F32F1EF65CCE65E3B1514CF91FBBCD5669`。
- 初次实现与隔离打包时未部署：当时检测到 `dota2` 进程在运行，未修改原部署包。后续用户退出游戏并授权部署，见文末记录。未启动或关闭游戏、未提交或推送。

## 复现检查与打包

在仓库根目录执行；`python` 应替换为本机可用 Python 路径：

```powershell
python tests/test_lv_gem.py
# 有 Lua 5.1/LuaJIT 时：
lua tests/test_lv_gem.lua
# 本机测试依赖隔离在忽略目录 bin/lua-test-runtime，不写入游戏包：
python -c "import sys; sys.path.insert(0, 'bin/lua-test-runtime'); from lupa.lua51 import LuaRuntime; LuaRuntime().execute(open('tests/test_lv_gem.lua', encoding='utf-8').read())"

.\deploy_items_only.ps1 -PackageOnly -OutputPath .\bin\lv-gem-experiment.vpk
```

实验产物：`bin/lv-gem-experiment.vpk`。不覆盖已有的 `bin/pak01_dir.vpk`。包 SHA256 以每次构建输出为准。

用户授权部署并完全退出游戏后，可使用现有部署脚本（会备份旧包、检查进程并核验哈希）：

```powershell
.\deploy_items_only.ps1 -OutputPath .\bin\lv-gem-experiment.vpk
```

## 游戏内验收顺序

1. 完全重启游戏后直接开普通本地房间，不先进入试玩。购买原宝石，确认它的原功能未变，并在升级树中找到 800 金配方。
2. 活着且持有原宝石时购买配方，不点击新物品。观察合成后自动消失、物品格空出、英雄出现“永恒真视”增益。仅见图标不算成功。
3. 在正常己方视野内，用敌方隐身英雄及敌方守卫检查约 1800 范围内可见、范围外不再被该光环揭示；确认友军共享反隐结果。另检查减益免疫目标。
4. 用树林、高地及战争迷雾验证不额外开图；不能只用全图可见的试玩条件来验收。
5. 英雄死亡后，观察尸体附近不再提供真视，复活后重新提供；记录是否发生掉落、增益丢失或必须重新持有物品的问题。
6. 测试驱散、幻象、克隆体；重复购买不应再次吸收。检查储藏处/信使转交及死亡期间购买，确认只在存活本体的主栏中吸收。
7. 完全退出再启动，单独复测试玩。回归检查玲珑心升级和商店原有列表。

诊断输出均以 `[lv_gem]` 开头：

- `automatic absorption callback reached`：KV 已调用 Lua，但不代表后续吸收成功。
- `absorbed; permanent True Sight radius=1800`：新版脚本完成添加效果与移除物品；仍需观察真实反隐（初版日志为 900）。
- `permanent modifier failed; item retained`：Lua modifier 创建路径失败；物品应保留。
- `already absorbed; duplicate item retained`：已有永久效果，保留第二件物品。

若没有 callback 日志，优先排查被动/RunScript 是否在本地房间触发；若已吸收但无反隐，重点检查原生真视 modifier、Lua 光环注册与客户端同步。不要因脚本单测或包校验通过而记录“游戏内成功”。

## 授权部署记录（2026-08-28 12:56）

用户确认游戏已退出并要求部署，由用户负责随后游戏内测试。

- 已确认没有 `dota2` 进程，执行 `deploy_items_only.ps1 -OutputPath .\bin\lv-gem-experiment.vpk`（未加 `-PackageOnly`）。
- 七文件 VPK v1 单文件包重新生成，CRC 和逐文件源码 SHA256 校验通过，与前次实验产物哈希一致。
- 已部署到 `E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv\pak01_dir.vpk`。脚本校验后另行读取产物和目标 SHA256，再次确认一致：`BA845CA8FA7BA7E9A2A930A6ACEA59F32F1EF65CCE65E3B1514CF91FBBCD5669`。
- 旧包备份：`bin/backups/pak01-before-deploy-20260828-125613-81c0767b28734cd59a96ea41e8e14491.vpk`。回退需先完全退出游戏，再恢复该包；不自动回退源码。
- 包检查及部署校验完成；用户随后反馈“测试下来没有问题，功能都实现了”，据此记录初版整体功能实测通过。没有逐项提供所有模式及特殊单位的测试记录，不据此扩大验证范围。

## 用户实测后调整（2026-08-28）

用户确认初版正常，并要求去掉状态图标的 `900` 数字，将升级品真视范围改为 `1800`。

- 原因：初版用 `SetStackCount(radius)` 同步半径，客户端把它显示成增益层数。
- 修改：将半径存为 modifier 的独立字段，通过 `SetHasCustomTransmitterData`、`AddCustomTransmitterData` 和 `HandleCustomTransmitterData` 同步，参考 [ModDota 同步示例](https://moddota.com/abilities/server-to-client)。不设置层数，图标保持可见；悬停说明仍读取实际半径。
- 只将 `item_lv_gem` 的 `radius` 改为 1800；原 `item_gem` 的 900 范围、配方价格、自动吸收和死亡复活规则保持不变。
- 扩展现有 Lua 测试，检查半径与层数分离、物品销毁后数值保留，以及客户端同步的悬停说明。
- 本次开始时检测到游戏仍在运行，不覆盖部署包，不关闭游戏。新版需要重新部署、完全重启后复测图标无数字及 1800 范围。
- 新版检查结果：4 项资源检查、13 项 Lua 5.1 逻辑测试通过；单独确认升级品半径 1800、原宝石半径 900。七文件 VPK v1 的 CRC 和逐文件源码 SHA256 比对通过。
- 新版产物仍为 `bin/lv-gem-experiment.vpk`，SHA256 为 `BB821B806F90C34B615B6EDDDA860088AAE54FF15ED20F25E5C285EF314DA31D`。仅打包，未部署。
- 该轮结束时游戏目录里的包仍为用户实测通过的初版，SHA256 为 `BA845CA8FA7BA7E9A2A930A6ACEA59F32F1EF65CCE65E3B1514CF91FBBCD5669`。

## 配方降价与后续部署约定（2026-08-28）

用户说明用于一人对战五个电脑，要求升级卷轴价格减半，并明确要求本次部署。

- 卷轴从 1600 改为 800 金；原宝石仍为 900 金，成品总价相应从 2500 改为 1700 金。
- 包含前一轮已完成的 1800 真视范围和不显示状态图标层数的修改，其余行为不变。
- 用户同时授权以后明确确认的模组修改完成检查后直接部署。该约定已写入 `AGENTS.md`；仍遵守游戏退出、旧包备份及部署哈希检查，遇到游戏运行或文件锁停止并提醒。
- 4 项资源检查、13 项 Lua 逻辑测试通过；七文件 VPK v1 的 CRC 与逐文件源码 SHA256 校验通过。
- 13:03 使用 `deploy_items_only.ps1 -OutputPath .\bin\lv-gem-experiment.vpk` 部署成功。产物与 `game/dota_lv/pak01_dir.vpk` 的 SHA256 再次独立核对一致：`7ACAAA46A1A72EDF51BDF22B210983F237AB7410817ACBF40A06BF11E30D0BFF`。
- 部署前备份了用户实测通过的初版：`bin/backups/pak01-before-deploy-20260828-130320-0c4faf21348842e4b5a7d68e8ba2a4af.vpk`，SHA256 为 `BA845CA8FA7BA7E9A2A930A6ACEA59F32F1EF65CCE65E3B1514CF91FBBCD5669`。
- 用户随后明确反馈“测试通过，效果很完美”，据此记录 800 金价格、无数字图标及 1800 真视范围的组合版本游戏内复测通过，并要求提交所有修改。
- 验证边界：这是用户对当前本地模组版本的实测确认，不代表所有模式、所有特殊单位或所有边界情形均已逐项验证。本轮只补记结果并提交，不修改已实测的资源、不重新部署。

## 全图原生真视部署记录（2026-09-01）

- 用户要求实现并部署，部署前确认 `dota2` 进程不存在；未启动或终止游戏。
- 删除自定义 Lua 文件 `modifier_lv_gem_consumed.lua` 及其打包清单条目；候选包文件树确认该文件不存在。购买者状态只保存在服务器 Lua 表中，敌方目标只添加官方 `modifier_truesight`。
- 11 项 Python 资源集成检查、13 项 Lua 5.1 控制流测试和 14 项打包回归检查通过。测试替身不等于游戏引擎验证。
- 使用 `deploy_items_only.ps1 -OutputPath .\bin\lv-gem-global.vpk` 构建 VPK v1 单文件包，共 11 个清单文件；CRC、逐文件源码 SHA256 和部署目标哈希校验通过。
- 产物及部署目标 SHA256：`21BCD173E8358EC2F2CC8D5ED0143E4FEBB09E31606CFDD0F3679940D0E569F5`。
- 部署目标：`E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv\pak01_dir.vpk`。
- 旧包备份：`bin/backups/pak01-before-deploy-20260901-160041-e51d51bded30403a9a7fee4f8f9727c9.vpk`。
- 用户随后在普通本地房间确认“功能没问题”，据此记录全图原生真视版本能够加载、吸收并产生预期效果；未逐项确认所有单位类型、模式及边界，不扩大验证范围。

## 吸收者状态图标调整（2026-09-01）

- 用户在确认全图真视功能正常后，要求给消耗宝石的英雄增加一个状态图标，明确提示已经消耗宝石并拥有全图真实视野。
- 新增纯 data-driven 显示状态 `modifier_item_lv_gem_consumed_status`，名称“永恒真视”，使用 `item_gem` 图标；悬停说明明确全地图真视及不揭开战争迷雾。它不参与实际反隐，不恢复自定义 Lua modifier。
- 改用 `TakeItem` 隐藏已吸收物品并保留其 data-driven ability 实体，为状态图标提供稳定来源；物品格仍会释放。图标创建或隐藏失败会撤销已建立的状态和本轮原生真视，物品留在栏内。
- 11 项 Python 资源集成检查、14 项 Lua 5.1 控制流测试和 14 项打包回归检查通过。HUD 图标显示及死亡后保留仍需本轮游戏内复测。
- 部署前两次确认 `dota2` 进程不存在；16:15 使用 `deploy_items_only.ps1 -OutputPath .\bin\lv-gem-global.vpk` 构建并部署 VPK v1 单文件包，共 11 个清单文件。CRC、逐文件源码 SHA256 和目标哈希校验通过。
- 产物及部署目标 SHA256：`78E27A1B8E1539D624370E72910157788948FFB6AA3333D847DA4F45D72C9FF3`。部署目标仍为 `E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv\pak01_dir.vpk`。
- 旧包备份：`bin/backups/pak01-before-deploy-20260901-161528-eed030166ff344a2baac8a3a9d635f91.vpk`，SHA256 为 `21BCD173E8358EC2F2CC8D5ED0143E4FEBB09E31606CFDD0F3679940D0E569F5`；这是用户已确认全图真视功能正常、尚无新状态图标的版本。
- 用户完成本轮游戏内复测后反馈“没问题”，据此确认吸收者状态图标、悬停提示及死亡复活后的保留表现正常；这不代表所有游戏模式和特殊边界均已逐项验证。
