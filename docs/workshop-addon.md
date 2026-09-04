# Overforged · 超限武装：Workshop-first 源码与双发行目标

## 唯一来源

标准运行目录：`game/dota_addons/overforged/`。
标准资源源目录：`content/dota_addons/overforged/`。

| 改什么 | 只编辑这里 |
| --- | --- |
| 手工融合装备及配方 | `game/dota_addons/overforged/scripts/npc/npc_items_custom.txt` 的生成标记区以外 |
| 自动生成的升级装备 | `scripts/item_upgrades.json`，运行 `scripts/gen_item_upgrades.py` 更新同一物品文件的标记区 |
| 私有隐藏能力 | `game/dota_addons/overforged/scripts/npc/npc_abilities_custom.txt` |
| 物品 Lua | `game/dota_addons/overforged/scripts/vscripts/lv/` |
| 手工名称/描述 | `game/dota_addons/overforged/resource/addon_english.txt`、`addon_schinese.txt` |
| 自动升级装备描述 | `scripts/gen_item_localization.py`，从官方基线生成 addon 中标记区块 |
| 88×64 左右的图标源图与 VTEX | `content/dota_addons/overforged/panorama/images/items/` |
| 现有已验证编译纹理 | `game/dota_addons/overforged/panorama/images/items/` |

自动生成文件/区块不手工改。普通打包不会自动重跑物品/描述生成器，以免无意覆盖调整过的生成结果。
物品文件仅有一个 `DOTAAbilities` 根块。生成器只替换 `BEGIN GENERATED UPGRADES` 与
`END GENERATED UPGRADES` 之间的内容，保留前后手工文本；标记缺失、重复或倒序时拒绝写入。
`--item` 仅允许与 `--preview` 一起使用，避免单物品生成意外清掉其他升级装备。
不再维护 `scripts/npc/lv`；`scripts/vscripts/lv` 是现有物品 Lua 路径，与此次 KV 合并无关，继续保留。
本次未重新编译纹理，保留迁移前 `.vtex_c` 的全部字节；新增两份 VTEX 源描述用于后续 Tools 编译。
重新编译后需重新做图标显示与哈希基线验收，不能认定新编译器输出必然与旧纹理一致。

## 加载入口

- `npc_items_custom.txt`：直接包含全部 82 个物品/配方定义，手工区与自动生成区共用一个根块，无 `#base`。
- `npc_abilities_custom.txt`：直接包含黑龙溅射私有能力，定义不变，无 `#base`。
- `addon_game_mode.lua`：初始化时通过 `lv_standard_rules.lua` 请求免费信使、默认神符逻辑和偷塔保护，再启用机器人思考；策略阶段按真人阵营用 `Tutorial:AddBot()` 只补满对手一方，再请求开启 FretBots。两边都有真人时不加机器人也不开 FretBots；保留 `lv_fill_bots` 作为防重复的手动后备。
- `addoninfo.txt`：原型声明 `maps = dota`，最多 10 人。依赖游戏自带地图，不携带/伪造一份地图文件。
- `resource/addon_*.txt`：只有自定义 token 和 `addon_game_name`，不包含全量官方文本。

本地 Tools 按 addon 名称引用 `dota` 地图启动已由用户实测成功，物品资源可见；已发布包中的引用仍须实测。
若发布器不接受基础地图引用，需要在 **content** 中建立真实地图资源并编译，而不是手工填写一个不存在的地图名。
当前不能宣称“已经具备所有可发布资源”。

## 本地开发：目录联接，不复制第二份源码

游戏退出后运行：

```powershell
.\Install-WorkshopAddon.ps1
# 非默认安装位置可加 -DotaRoot 'D:\SteamLibrary\steamapps\common\dota 2 beta'
```

它仅创建两个 NTFS Junction：安装目录下的 `game/dota_addons/overforged` 和
`content/dota_addons/overforged`，分别指向仓库中的同名目录。
已有目录不是本仓库的同一个联接时会拒绝覆盖。重复执行正确的联接是幂等的。
它不终止游戏、不改 `gameinfo.gi`、不部署 VPK，也不上传 Workshop。

从旧名升级时，先完成源码改名，再执行 `.\Install-WorkshopAddon.ps1 -RemoveLegacyLinks`。
它先核验两处新路径和旧路径：只有指向本仓库旧位置的 `lv_upgraded_items` Junction 才允许移除，
普通文件夹或其他目标的联接会拒绝操作。新联接创建成功后，非递归删除旧联接本身，绝不清空其指向内容。
本机两处联接已迁移到 `overforged`；无需重新复制资源。改名后的 Tools 启动与标题显示待用户实测。

注意：联接指向源码。不要对游戏目录中的这个 addon 使用递归删除/清空操作；应只移除联接本身。
Tools 已通过联接成功启动 addon；后续重新编译出的资源仍须单独验收。

## 本地验收顺序

1. 完全退出 Dota。先记录/备份并**暂时停用当前 `dota_lv` 自定义覆盖包**，不要删除。
   原包与 addon 同时加载可能出现重复物品 ID，或让旧资源遮蔽新资源，造成崩溃/假通过。
   本次没有自动停用它，也没有修改 `gameinfo.gi`。
2. 启动 Dota 2 Workshop Tools，选择 `overforged`。若未显示，先检查上述目录联接。
3. 控制台进行本地开发启动：

   ```text
   dota_launch_custom_game overforged dota
   jointeam good
   ```

4. 检查控制台 `[LV] overforged addon loaded`，没有缺 KV、Lua、纹理等加载错误。
5. 先验证原版地图/英雄选择/兵线/防御塔/胜负规则，再验证强化装备的升级树、购买、合成、图标和属性。
6. 真人完成选人、进入策略阶段后，应只在真人对面用 `Tutorial:AddBot()` 补至 5 个机器人，并出现
   FretBots 欢迎/语言/难度投票提示，无需手输命令。真人在两边时应完全不加机器人，也不启用 FretBots。
   `Tutorial:AddBot()` 负责创建指定英雄，不代表选择了 OpenHyperAI；`.OHA` 名称、行为和控制权仍须本轮实测。
7. OpenHyperAI 独立验证：保留主机的本地 bot 安装；观察实际房间是否提供 Bot Script 选择、脚本加载日志、
   `.OHA` 名称，以及真实对线/施法/出装行为。**此前对 Arcade 房间直接选择 Local Dev Script 的描述未实测。**
   没有入口或机器人站着不动时记录日志，不要在 addon 中直接 `require(bot_generic)`。
8. 本地通过后才考虑“仅好友可见”的 Workshop 发布。发布后以 Workshop ID 再测，再邀请未装 VPK 的朋友下载验证。

不用为机器人增加强化装备购买逻辑；它们继续用原版出装。此处不复制或修改 OHA 源码。

## 普通地图规则补齐（2026-09-03，待游戏内验收）

仍然是 CUSTOM Workshop addon，不把界面改名伪装为原生 AP。当前只补齐三个已定位的引擎开关：

| 机制 | `CDOTABaseGameMode` 调用 | 实现边界 |
| --- | --- | --- |
| 每位玩家的免费信使 | `SetFreeCourierModeEnabled(true)` | 由引擎创建和管理，不手造信使或写升级定时器 |
| 当前版本默认神符逻辑 | `SetUseDefaultDOTARuneSpawnLogic(true)` | 不覆盖刷新间隔，不写死旧版神符种类/时间/坐标 |
| 防御塔偷塔保护 | `SetTowerBackdoorProtectionEnabled(true)` | 由引擎处理，不手动添加保护 modifier |

在 `Activate()` 中先设置，再开启思考、填机器人和请求 FretBots。每项独立捕获错误，缺 API 时明确输出
`failed`，不会因此跳过其他设置和机器人启动。重复初始化只重新设置布尔值，不额外生成单位或定时器。
不修改工资、经验、死亡掉钱、买活、等级上限、加速信使或 OHA 出装。TP 和中立掉落等其他机制不据此宣称已验收。

### 当前资料与取舍

2026-09-03 核对了近期源码与 API，而非直接移植两年前的整套游戏模式：

- [Windy10v10AI GameConfig.ts（固定提交）](https://github.com/windy10v10ai/game/blob/4ad97be901ee81aafba4ff24401f3d995b7e48ed/src/vscripts/modules/GameConfig.ts)：
  该文件最近提交日期为 2026-08-23，实际使用了上述三个开关。它是 10v10 项目，其经济、选人、经验、属性等配置不适用于本项目，未导入。
  仅参考引擎 API 的使用方式，未引入该 GPL 项目的模块、依赖或其他代码。
- [ModDota 当前 API 声明（固定提交）](https://github.com/ModDota/TypeScriptDeclarations/blob/fc093638c0a3813384e30d86b0418e0a193d0a46/packages/dota-lua-types/types/api.generated.d.ts)：
  文件更新于 2026-04-26；同日发布的 `@moddota/dota-lua-types` 4.38.2 是本次查询 npm 的最新版本。
  三个接口及 `Msg` 仍在声明中。免费信使注释中的“7.23”指机制引入版本，不代表该 API 文档停在 7.23。
  默认神符接口说明保留自定义刷新间隔，因此本项目不额外设置这些间隔；它也不能证明每一种当前地图神符均已正确出现。
- 本机当前 `server.dll` 的只读检查与开局日志作为补充：CUSTOM 默认未开启这三个开关；信使缺失还会使本地
  FretBots 的信使检查继续等待。启用免费信使可能解除这段等待，但欢迎信息/初始化标志仍不证明增强逻辑全部工作。

这里采用可验证的小范围引擎配置；不能凭“项目近期维护”或“API 调用成功”推断所有普通 Dota 机制完整可用。

### 重开验收

游戏操作由用户完成。完全退出 Dota 与 Tools 后重新打开 addon；保持旧 `dota_lv` 覆盖包停用，使用原来的命令：

```text
dota_launch_custom_game overforged dota
```

地图加载后输入 `jointeam good`，正常选人；不再执行 `dota_force_gamemode 1` 或 `exec lv_test_ap`。
源码通过现有联接加载，不需要部署 VPK。这次没有改游戏启动参数、持久 cfg 或 OHA 源码。

1. 启动日志有三行 `[LV-RULES] ...=requested`，无 `failed`。界面仍写“自定义游戏模式”是预期。
2. 英雄进入地图后确认个人信使存在，购买普通物品测试运送；观察双方机器人信使是否出现，不只看一个空闲信使模型。
3. 观察开局及后续神符刷新、拾取与效果。尤其分别记录赏金、河道和经验神符；本轮没有另写任何缺失神符的补丁。
   若某类缺失，记录游戏时间、位置、日志再定位，不预先叠加手工刷符定时器。
4. 检查适用防御塔的偷塔保护及有/无兵线时的行为；单凭 getter 为 true 不算行为验收。
5. 确认强化装备购买、OHA 对线/施法、FretBots 投票与实际加成没有回归。机器人无需购买强化装备。
6. 进入泉水后输入 `lv_mode_status`，购买强化装备后可再执行一次并保存输出。
   守卫测试按下方“守卫饰品预缓存实验”单独进行，不能把 Lua 调用成功当作崩溃已修复。
7. 尝试框选、右键命令或施法控制一名友方机器人和一名敌方机器人；两边都应只能查看，不能下达命令。

`lv_mode_status` 不需要 `script` 前缀，也不切换模式、给钱、生成信使或创建物品。
启动/状态变化也会自动输出 `[LV-MODE]`。`lv_log.lua` 优先使用预先保存的引擎 `Msg`，
避免本地 FretBots 将全局 `print` 替换成默认静音版本后吞掉诊断；不改 OHA 的 Debug 配置。

- `addon=overforged`：本 addon Lua 已执行。
- `requested_force_mode`：仅是控制台变量，**不是实际比赛模式的证明**。
- `actual_game_mode`：有读取 API 时显示数字；不支持时显示 `unavailable`，不拿请求值冒充。
- `free_couriers` / `default_runes` / `tower_backdoor`：`requested` 仅表示 setter 无报错；`failed` 表示调用失败；
  `not_requested` 表示没有本次初始化记录。不是实际效果的读取值。
- `tower_backdoor_enabled`：独立调用引擎 getter 的结果；缺 API 显示 `unavailable`。
- `couriers` / `heroes`：当前实体数量。选人前为 0 正常，必须在英雄进入地图后检查；计数不能证明归属和运送正常。
- `fretbots_initialized`：服务器增强脚本标志，不等于全部机器人行为/加成通过。
- `bot_human_control`：应为 `false`；这是引擎的机器人可被真人控制开关，不代表共享控制兜底一定执行成功。
- `lv_items_in_inventory`：英雄物品栏/背包/储藏处读到的 `item_lv_` 数量；仍须玩家确认商店与购买。

## 守卫饰品预缓存实验（定点对照待游戏内验收）

两次旧名 addon 的崩溃转储均记录了
`models/items/wards/smeevil_ward/smeevil_ward_gold.vmdl` 未进入资源系统，随后在网络序列化时发生访问冲突。
官方 VPK 中存在该模型，因此没有把官方资源复制进 addon。

`Precache(context)` 同步登记三个守卫物品，以及默认侦察守卫、岗哨守卫和信使单位。玩家的真实英雄首次生成后，
`npc_spawned` 监听器使用该英雄的 `PlayerID`，分别对这三个单位调用一次 `PrecacheUnitByNameAsync`；同一玩家复活
不会重复排队。2026-09-04 的新转储已完成这次通用预缓存消融：0–9 号玩家全部出现排队日志，默认守卫与信使也进入
spawn group，但插眼时仍出现同一条 `Serialized nonresident asset`，随后访问冲突。因此已确认该通用接口不足，
不能再把“已排队”当成具体饰品已驻留。

当前进入定点对照组：`Precache(context)` 显式登记 Smeevil's Penance Gold 的模型
`models/items/wards/smeevil_ward/smeevil_ward_gold.vmdl` 及其 style 4 黄色环境粒子
`particles/econ/wards/smeevil/smeevil_ward/smeevil_ward_yellow_ambient.vpcf`。这只是引用官方现有资源，不复制模型。
保持 Gold 样式先插侦察守卫，再开新局插岗哨守卫，并保存日志；两者都通过前仍不能宣称崩溃已修复。

## AP 原生模式复用实验（历史，不再作为当前路线）

用户重开测试后仍显示自定义模式。只读检查本机 `client.dll` 中的 `dota_launch_custom_game` 回调，
发现其启动参数明确设置 `gamemode=15`（CUSTOM）并设置 `customgamemode`；预先设置 AP 请求未改变这一入口。
服务器启动分支对 addon 的处理也不能作为 AP + addon 同时成立的依据。目前没有核实到支持此组合的公开启动方式。

`cfg/lv_test_ap.cfg` 仅保留历史复现，不是正常入口，且当前已加入规则补齐，因此也不再是原来的无补齐对照实验。
没有写入 autoexec。使用原命令重开即可；不应再用请求值为 1 宣称原生 AP 已生效。

## 单边对抗机器人与 FretBots

开局流程：`Activate()` 请求上述三个默认规则、关闭真人控制机器人并开启思考 → 等待
`game_rules_state_change` 到策略阶段 → 统计两队真人 → 若真人仅在一边，则用 `Tutorial:AddBot()` 将另一边补至 5 人 →
`SendToServerConsole("sv_cheats 1; dota_bot_allow_human_control 0; script_reload_code bots/fretbots")`。
如果两边都有真人，则不添加任何机器人，也不请求 FretBots；如果还没有真人，则等待后续状态/手动后备重试。
在玩家选队和选英雄阶段都不填槽，避免提前占用朋友的位置或英雄；进入 PRE_GAME 后不再自动初始化。
机器人创建与 FretBots 请求每局各一次，重复事件、重复 `Activate()` 或误输后备命令不会重复加载。
手动提前启用过 FretBots 时，检测到服务器 Lua 中的 `Flags.isFretBotsInitialized` 也会跳过重载。

这等价于用户已成功使用的手动开启流程，并遵循 [OHA 作者的增强模式说明](https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/68)。
本机 `bots/fretbots.lua` 在选人之前会直接返回，因此不能在最早的 `Activate()` 阶段直接加载它。
难度与队友加成仍保留原投票，不替用户选择难度 10，也不修改 OHA 的配置文件。

注意：自动开启增强模式会将服务器的 `sv_cheats` 设为 1；不会自动关闭，不写入 cfg，也不影响 VPK 打包内容。
`addon_game_mode.lua` 顶部两个开关可分别设为 `false` 并重开对局：

```lua
local AUTO_FILL_BOTS = true
local AUTO_ENABLE_FRETBOTS = true
```

`lv_fill_bots` 现在与自动流程共用 `Tutorial:AddBot()`：只补真人对面的一队；两边都有真人时不做任何事。
该 API 必须明确指定英雄，因此当前按大致 1–5 号位顺序从候选池选择，并跳过已经被真人选择的英雄。
用户旧日志中，引擎曾从 `game/dota/scripts/vscripts/bots` 加载 OHA；因此出现 `.OHA` 仍不是本命令自带 OHA。
主机本地 OHA 安装必须保留；这里没有自动下载、打包或移植机器人。
换一台主机、远程服务器或发布 Workshop 后，不保证还能找到这个外部路径，必须另行验证。

引擎原本提供 `dota_bot_allow_human_control` 控制真人能否操作机器人；当前 addon 在激活、填槽完成及 FretBots
命令链中都显式保持为 `0`。此外每次真实英雄生成时，对机器人英雄调用
`SetControllableByAllPlayers(false)`，并清除从机器人 PlayerID 指向真人 PlayerID 的英雄/单位共享位。
2026-09-04 实测表明上述控制权标志仍不足以阻止 Tools/CUSTOM 中的真人订单。当前再由服务器执行订单过滤：
若订单签发者是真人，而被命令单位属于 fake client，则拒绝整条订单；机器人自己、引擎脚本及真人自己的单位
均放行。这同时覆盖友方和敌方，不修改 OHA 的决策代码。该修正已通过 Lua 引擎替身测试，仍需游戏内确认；
日志最多记录前三次 `[LV] Blocked human order to bot-owned unit`，便于确认过滤器实际命中。

`[LV] FretBots enable command queued ...` 只证明命令入队，不证明脚本执行成功。
若没有 FretBots 欢迎/投票，检查同一段控制台里的命令拒绝、缺文件、Lua 报错，保留日志。
`lv_fill_bots` 后备命令仅允许选人至 PRE_GAME 之前使用；自动流程正常时不需要输入。命令发送成功后不会自动反复重载来重置投票。

### 机器人不动的当前排查

用户日志已确认双方加载本地 OHA 的 `hero_selection.lua`、创建 `.OHA` 机器人，并进入正式对局；
FretBots 欢迎与难度投票也运行，但机器人不行动。这不能证明英雄行为回调已执行。
原入口只调用 `BotPopulate()`，没有显式启用思考；后来在 `Activate()` 中加入启用调用，用户实测机器人恢复行动。
当前又把整队填充替换为 `Tutorial:AddBot()` 单边创建实验，是否仍加载完整 OHA、是否消除真人控制权以及
OHA 分路/出装是否保持正常，均须重新开局验证，不能沿用旧 `BotPopulate()` 对局的结论。
用户随后实测确认：显式启用思考后机器人恢复行动，看起来正常；尚不代表全部英雄/技能或发布模式通过。
新增加的自动填槽和 FretBots 流程需要重新开局验证，与上述手动流程实测结论分开记录。
当前用户控制台不识别 `script`，不要再要求粘贴 `script GameRules:...` 来启用。

Valve 曾收到“本地按 addon 名启动可思考、发布后按 Workshop ID 启动不思考”的报告；当前本机不动已通过显式开启思考解决，不能认定同源，
但足以要求单独测试：[Valve #13919](https://github.com/ValveSoftware/Dota2-Gameplay/issues/13919)。

## VPK 兼容目标

`deploy_items_only.ps1` → `Build-LvVpk.ps1` → `prepare_vpk.py` → `Build-Vpk.ps1`。

- `pak01_dir` 保留纯官方基线；生成器不会写回它。
- 只在 `bin/vpk-adapter-<ID>` 生成完整 `items.txt`、两份完整官方+LV 本地化，以及映射清单。
- `items.txt` 引入 `overforged_items.txt` 与 `overforged_abilities.txt` 两个包内别名，保留旧版通过物品入口加载私有能力的方式；不覆盖官方 `npc_abilities.txt`。
- `packaging/npc-sources.json` 将两个包内别名分别映射至 addon 的 `npc_items_custom.txt` 和 `npc_abilities_custom.txt`。这是同一文件的打包路径映射，不是复制/生成第二套 KV 源码。
- Lua、KV、纹理直接读取 addon 源码，不复制到资源暂存树。
- VPK 不能带入 `addoninfo.txt`、`addon_game_mode.lua`、`npc_*_custom.txt`，避免在普通房间改变模式。
- 增量清单为 `packaging/items.txt`；`deploy_all.ps1` 将官方全量基线与同一份自定义覆盖合并为全量兼容包。
- 天地星合并脚本同步改为读取 addon KV/Lua/纹理与 addon 文本；仍保留作者包的商店/官方数据。

VPKEdit Modify 模式追加文件时不遵守 `--single-file`（[CLI 实现](https://github.com/craftablescience/VPKEdit/blob/master/src/cli/Main.cpp)）。
因此映射构建后由 `flatten_vpk.py` 直接收拢 archive payload 到 v1 单文件数据区，不解包成文件树。
它保持目录字符串、预加载数据和 CRC；随后再次用 VPKEdit 校验 CRC，并用独立 PowerShell 校验全部 payload SHA256。
失败不会替换旧输出；临时 VPK/分块被清理，适配文件保留在忽略目录便于排查。

## 验证命令

```powershell
python -X utf8 scripts/validate_addon.py
python -X utf8 -m unittest discover -s tests -p 'test_*.py' -v
python -X utf8 tests/run_lua_tests.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_packaging.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_mapped_packaging.ps1
.\deploy_items_only.ps1 -PackageOnly
.\deploy_all.ps1 -PackageOnly
.\Merge-Pak02WithLvItems.ps1 -PackageOnly
```

本次迁移的旧产物：`bin/workshop-migration-before.vpk`。
与新产物做语义对比：

```powershell
python -X utf8 scripts/compare_item_packages.py bin/workshop-migration-before.vpk bin/pak01_dir.vpk
```

对比定义及全部最终生效文本；Lua/纹理等无关转换的 payload 必须字节一致。
旧包中的 nullifier `lore`/`Lore` 大小写重复已按原先“最后定义生效”规范化为单键，值不变。
