# 发布版本地房间的 OHA 加载调查（2026-09-05）

## 结论与边界

**11:14 新增实测：** 用户在正式版执行 `dota_launch_custom_game 3795453776 dota`，
确认成功加载 OHA。新日志同时证明双方使用本地 `game/dota/scripts/vscripts/bots`，
加载 `hero_selection.lua` 并创建五名 `.OHA` 机器人。下面的 `UGC: 0` 结论只适用于
从界面创建的本轮 Arcade 房间，不能扩大成发布包或正式版一概不能加载 OHA。
无需仅因该加载问题就决定重写 AI 或完整移植 OHA；界面房间的脚本选择仍待解决。

用户从正式版界面创建 Workshop 项目 `3795453776`（超限武装）的本地房间，比赛
`8983189884`。当前证据定位到 Bot Script 初始化被房间的脚本 ID `0` 提前跳过，
并非本地服务器完全无法读取 OHA 文件。FretBots 服务器模块能执行；Bot Script VM
是另一条加载链。尚未找到、也未实测一个能从当前 Arcade 房间可靠切换到 OHA 的公开接口。
不能把“复制完整 bots 到 addon”或“require bot_generic”当作已验证解决办法。

本次未启动/操控游戏，未修改 addon 运行代码、本地 OHA、引擎文件或发布包，未部署/发布。

## 本轮日志

游戏目录：`E:/SteamLibrary/steamapps/common/dota 2 beta/game/dota/`。

- `console.log:48`：正式版启动参数含 `-console -condebug`，不含 `-tools`。
- `console.log:1383`：挂载 addon `3795453776`。
- `console.log:1423`、`:1424`：`Initscripting Team 2, UGC: 0`、Team 3 同值。
- 后续连接为 `loopback`，确认本地服务器。
- 11:00:14 分配比赛 ID 后日志切换到 `console.8983189884.log`，必须两份一起读。
- 对局日志 `:505`：`matchups=loaded`，但 `bots/FunLib/aba_matchups` 不存在，退回位置权重。
- `:507` 起：五名 fake client 创建成功，分别为 Kez、Necrophos、Pudge、Silencer、Oracle。
- `:548`：FretBots 欢迎信息；`:671` 手动状态显示 `couriers=6 heroes=6 fretbots_initialized=true`。
- 两份日志均未出现 OHA `hero_selection.lua`、`bot_generic.lua` 等 Bot VM 加载记录。

本机当前 OHA 确实没有 `FunLib/aba_matchups.lua`，存在 `FuncLib/data/matchups.lua`。
这是版本路径兼容问题，但不能只改文件名就认定两者接口一致；也不能把选人评分修复当作
战斗行为接管。此次未改变其回退逻辑。

日志备份位于 `%TEMP%/overforged-oha-20260905-8983189884/`，避免后续开局覆盖证据。
启动日志 SHA256：`8de87ed783116d43bea88ee7f8ee7271a2389915cc850983b3e452632d3e1a4c`。
对局日志 SHA256：`519183743445de3e1649eaae6ce474e66cde8d3e404814ab4b979cf87e56c1ff`。

## 当前引擎的只读检查

对象：`game/dota/bin/win64/server.dll`，SHA256
`76908365d189e2ac12599c4083875cf2b5acace4a7d2dff1dfed0a0f1cdec694`。
使用 PE 节区映射与 x64 反汇编核对日志字符串的引用和控制流，没有修改二进制或进程内存。
下列地址是本构建 RVA，不是可跨版本复用的偏移。

Bot 初始化函数 RVA `0x2345380` 的相关逻辑可概括为：

```text
如果提供了显式脚本目录：使用该目录
否则，如果取得了房间对象：
    读取该阵营的 Bot Script UGC ID 并打印日志
    ID == 0：直接返回，不继续检查本地 bots 目录
    ID == 1：解析 GAME 搜索路径下的 scripts\vscripts\bots
    其他 ID：请求 Steam Workshop 脚本详情
否则：
    读取 dota_bot_practice_script
    非零：请求对应 Workshop 脚本详情
    零：检查本地 scripts\vscripts\bots 目录
```

证据点：

- RVA `0x23453f6` 调用房间查询；非空后读取阵营 ID。
- `0x2345419` 引用 `Initscripting Team %d, UGC: %llu`。
- `0x2345436` 检查 ID，`0x2345439` 在零值时跳到 `0x2352007` 的函数退出段。
- `0x234543f` 比较 ID `1`，对应路径字符串引用在 `0x234546c`。
- `dota_bot_practice_script` 的读取在无房间对象分支 `0x23454ed` 之后。
- 阵营 ID getter RVA `0x2549220` 从房间数据读出天辉/夜魇值；并非从 addoninfo 读取。

因此，本轮 `UGC: 0` 可以解释没有任何 OHA Bot VM 加载尝试。单纯把 OHA 放进包中，
不会改变这条已观察到的提前返回分支。Tools 旧日志中的本地脚本加载，与无房间时的本地
目录回退路径相符；旧对局未抓取该分支的实时调用栈，因此这是控制流与日志结合的推断。

`dota_bot_reload_scripts` 的命令回调 RVA `0x22e7a40` 只调用双方重载函数。
重载函数 `0x2359a20` 在 Bot VM 指针为空时直接返回到 `0x2359bc5`，不重新执行
上述初始化，也不读取额外脚本路径参数。输出 `Bot scripts reloaded` 本身不能证明激活成功。

`bot_script_ugc_radiant/dire` 字符串的引用位于比赛信息输出代码，不能据此把它们当作
可设置的控制台变量。未找到可据以推荐的 Arcade Bot Script 切换命令。

## 发布包核对

检查实际订阅文件 `steamapps/workshop/content/570/3795453776/3795453776.vpk`：

- 共 25 个文件，逐项 CRC 校验通过；包含 addon 启动及选人模块，没有 `scripts/vscripts/bots/`。
- SHA256：`0ab41d3a225332fd4617f83eff8c830bec5e90e3ad3d10b8a34f2dfaf1f7bf0a`。
- 这是 Workshop 发布器生成的 VPK v2，已经由正式版成功加载；不要混同于本项目
  `dota_lv` 覆盖包必须使用 VPK v1 的既有部署限制。
- 旧 `scripts/vpk_list.py` 对这份标准 v2 包错误地跳过额外 4 字节，首次读取失败。
  本次改用标准 18 字节目录项、preload 与 CRC 校验做只读核对，没有修改该旧工具。

## 外部资料与适用范围

- [OHA #66](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/66)：作者于
  2025-05-14 回复曾尝试 addon 集成，遇到其认为难以用合理工作量解决的严重问题。
  回复通过 GitHub API `/issues/66/comments` 核对；这是历史经验，不是当前引擎的绝对不可能证明。
- [Valve #3725](https://github.com/ValveSoftware/Dota2-Gameplay/issues/3725)：旧报告中
  是已经请求 Workshop Bot Script 后得到空目录，再加载文件失败。本轮尚未进入该流程，
  不能将它直接判为同一个故障。
- [Valve #13919](https://github.com/ValveSoftware/Dota2-Gameplay/issues/13919)：报告了
  按本地 addon 名与按 Workshop ID 启动的差异；不能承诺改用控制台按 ID 启动一定有效。

## 直接启动对照（已执行，OHA 加载成功）

用户确认使用下述按 Workshop ID 启动的命令成功加载 OHA；未另外确认是否输入过
`dota_bot_practice_script 0`，不能把它记录为成功必需条件。

新 `console.log`（11:14:02 开始）关键证据：

- `:48`：正式版参数，无 `-tools`。
- `:622`、`:626`：双方 `bot scripting using script path` 明确指向主机本地 OHA。
- `:623`、`:627`：双方 `hero_selection.lua` 进入 HeroSelectionScriptScope。
- `:847` 起：五名 `.OHA` 机器人创建；`:888` FretBots 欢迎信息，`:941` 初始化标志为 true。
- 没有前一轮的 `Initscripting Team ..., UGC: 0` 记录，与直接启动走本地目录回退的解释一致。
- `:902` 起有十条 `Script Runtime Error: error in error handling`，随后重复消息被限流。
  缺少栈信息，暂不能归因给 OHA、addon 预缓存或其他模块；加载成功不等于全部行为正常。
- 旧选人评分路径 `bots/FunLib/aba_matchups` 缺失仍存在。

读取时 Dota 仍在运行；已将当时日志快照保存到
`%TEMP%/overforged-oha-20260905-direct/console.snapshot.log`，不是完整退出日志。
用户确认范围为 OHA 加载成功，未扩大为全部英雄行为、朋友联机或远程服务器已通过。

以下保留对照操作与最初判断标准，待验证项以本节上方结果为准。

保持正式版和 `-console -condebug`。退出当前房间，回到主菜单，不进入 Workshop Tools，
在控制台启动同一个已发布项目：

```text
dota_bot_practice_script 0
dota_launch_custom_game 3795453776 dota
```

若需要手动加入天辉，地图加载后输入 `jointeam good`。选择英雄，让机器人进入地图，
执行 `lv_mode_status`，观察行为并退出。

`dota_bot_practice_script 0` 只为将无房间时的对照分支固定为本地目录回退，不是 Arcade
房间的修复命令，也不写入持久 cfg。此轮仍可能走 `UGC: 0`，必须以新日志判定。

正式版 `dota_launch_custom_game` 回调确实设置 `gamemode=15` 和 `customgamemode`，
传给引擎启动接口；没有直接在该回调中指定双方 Bot Script ID。因此本对照只用于区分
“界面房间路径”与“直接启动路径”，不能提前宣称能够绕过房间限制。

如果直接启动出现完整 OHA 加载和实际行为，只能先确认为正式版本地调试入口可用；
仍不代表 Arcade 房间、朋友加入或远程服务器可用。若继续 `UGC: 0`，无需反复尝试
复制脚本、切换思考或重载；后续需要新的可用房间接口证据，或另行评估 addon 原生 AI 适配。
