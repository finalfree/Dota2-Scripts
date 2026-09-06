# 普通房间体验、机器人控制与物品分发调查

2026-09-05。用户目标是普通本地房间中的 OpenHyperAI + 自定义物品，支持朋友联机，
尽量降低朋友安装和更新成本。本轮只做源码、安装文件和引擎二进制的只读调查，未启动或操作游戏，
未修改运行代码、游戏配置或部署包。

## 控制问题：服务器拒单不会恢复客户端选择

用户确认现有服务器订单过滤已阻止真人操作机器人，但左键查看敌方机器人后，右键仍向机器人发单，
不会按普通房间体验恢复自己的英雄。

`addon_game_mode.lua` 当前清除全员控制开关与玩家间共享位，之后由 `AllowExecuteOrder()` 拒绝真人
发给 fake-client 所属单位的订单。这个过滤点不能修复客户端已经形成的选择和发单对象。
当前 addon 没有 Panorama 鼠标过滤脚本。

本机 `client.dll` 的选择代码确实检查单位可控制位图：例如 `0x181af1220` 读取单位 `+0xbc8` 后
用玩家编号做 `bt`，再进入选择分支。这里只确认存在该判断，未通过运行时跟踪确定本轮鼠标具体经过的所有分支。

## 更优先的线索：自动 FretBots 流程持续开启作弊

现有 `EnableFretBotsOnce()` 入队：

```text
sv_cheats 1; dota_bot_allow_human_control 0; script_reload_code bots/fretbots
```

没有配套关闭作弊。当前服务器二进制中：

- `SetControllableByAllPlayers(bool)` 的脚本绑定指向 `0x1824e70e0`：写单位 `+0xee4` 的独立开关，
  然后进入控制权重算函数 `0x1824f7480`。传 `false` 是正确的布尔语义，但并非无条件清空最终控制位图。
- 重算函数先重新计算控制位图 `+0xed8`，再在 `0x1824f7a13` 检查单位控制玩家是否为 fake client。
  `0x1820bcce0` 已通过脚本绑定核实为 `PlayerResource:IsFakeClient`。
- fake client 分支在 `0x1824f7a29` 调用 `0x181828410`。该函数明确读取 `sv_cheats`，
  也考虑房间作弊标志、Tools/试玩等其他上下文，不可简化为只读取一个 convar。
- 该判断为真且另一会话条件 `0x1818711b0` 为假时，直接跳到 `0x1824f7a4f`，
  循环给有效玩家设置控制位。循环校验函数 `0x1820bd800` 已通过绑定核实为 `IsValidPlayer`。
- 其他路径才读取 `dota_bot_allow_human_control`。变量注册于 `0x1803edb9c`，
  对象 `0x185125eb8` 的值指针为 `0x185125ec0`，与 `0x1824f7a42` 的引用吻合。
- 最后才处理 `SetControllableByAllPlayers` 的独立开关；设为 false 不会抵消前一分支设置的位。

因此，**存在一条作弊状态导致机器人可被玩家控制、且不依赖 `dota_bot_allow_human_control=1` 的路径**。
这与当前源码和现象一致，是比“CUSTOM 模式一律如此”更具体的根因候选。
没有运行时分支记录，不能宣称已证明本次全部现象都由该路径引起。

二进制版本绑定：服务器 SHA256
`76908365d189e2ac12599c4083875cf2b5acace4a7d2dff1dfed0a0f1cdec694`；客户端 SHA256
`d83771b4f61c2b7d882a0fcfc06f83b8d59b11af6f3afd4a1f85d68a449cad78`。
所有地址只适用于本机本轮版本；没有修改 DLL 或运行进程。

## 修复候选与验证顺序

1. 优先避免持续开启作弊：研究从已经运行的 addon 服务器 Lua 加载主机 `bots/fretbots`，
   或只在控制台加载阶段临时开启并恢复先前状态。当前本地 OHA Lua 静态搜索没有发现
   `sv_cheats`、`IsCheatMode`、`SetControllableBy*` 引用，但这不保证所有间接引擎调用均无依赖。
2. 作弊状态变化后重算现有机器人控制权；不能假定输入 `sv_cheats 0` 就立即刷新已有单位的选择行为。
   同时核实房间作弊标志；Tools 与正式版的结果分开记录。保持服务器拒单兜底，直到正常选择与 OHA 行为都通过。
3. 若仍需客户端补偿，Panorama 提供 `GameUI.SetMouseCallback`、`GameUI.SelectUnit`、
   `Players.GetSelectedEntities`、`Players.GetQueryUnit`。可以在普通右键下单前恢复自己的英雄或原有可控选择，
   保留左键查看敌人。必须处理技能瞄准取消、Shift 排队、信使/召唤物、共享单位与 UI 区域，不能简单把所有右键都强制移动。
   这是可实现的适配方向，尚未实现或游戏内验证。

API 来源：[ModDota Panorama 声明](https://github.com/ModDota/TypeScriptDeclarations/blob/master/packages/panorama-types/types/api.d.ts)。
注意 `SetControllableByPlayer(playerID, bool)` 的第二参数是 `bSkipAdjustingPosition`，
不能把 `false` 当作撤销该玩家控制权的开关。
来源：[ModDota 服务器 API](https://docs.moddota.com/lua_server/)。

## 分发路线评估

- **普通本地房间 + 兼容 VPK** 最符合用户的原生规则与操作目标。现有构建流程继续从同一份 addon
  物品源码生成 `dota_lv` 覆盖包，排除 addon 游戏模式入口；不需要回迁或复制源码。
  已有部分普通房间物品实测不等于五人联机、全部物品和所有模式已通过。
- OHA 作者列出 AP、RD、CM 支持，README 推荐 Custom Lobby + Local Host。
  这里的 Custom Lobby 是普通自建房间，不等于 Arcade CUSTOM 游戏模式。
  来源：[OHA 模式支持表](https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/72)、
  [OHA README](https://github.com/forest0xia/dota2bot-OpenHyperAI)。
- **Workshop addon** 解决专属游戏内容的分发，但当前核实的启动入口指定 `gamemode=15`。
  尚未找到受支持且已验证的“加载该 Workshop addon，同时进入原生 AP/RD/CM 房间”的入口。
  不能把 `dota_force_gamemode` 的请求值当成成功，也不能把 `dota` 地图名当成规则模式。
- **订阅不等于普通房间自动挂载**。Steam 下载条目后仍由游戏决定如何读取、使用内容。
  本机 `dota_lv/gameinfo.gi` 的搜索路径为 `dota_lv`、`dota`、`core`；Workshop 下载目录不在这组路径中。
  来源：[Steamworks Workshop 实现指南](https://partner.steamgames.com/doc/features/workshop/implementation)。
- **朋友安装器/更新器** 是建议投入方向：预构建 VPK，不要求朋友装 Python、VPKEdit、Tools 或仓库；
  自动发现 Steam 库、安装挂载配置、检查版本/哈希、备份和恢复，提供启用/停用。
  当前 `deploy_items_only.ps1` 是开发机打包部署入口，硬编码默认目标，不是现成朋友安装器。
  先以压缩包分发做小规模联机验收，再选择更新来源。用户尚未选择此实现，本轮没有创建安装器或发布文件。
- Workshop 下载后由外部工具转换/安装为普通覆盖包是另一个尚未验证的设计，但仍需要第一次安装工具，
  且已发布 addon VPK 不能直接等同于兼容覆盖 VPK。对五人固定小组不宜优先增加这层复杂度。

建议将“完整原生房间体验”作为优先目标，评估普通房间 VPK 的便捷分发；保留 Workshop 源码与产物，
不因本轮调查删除已完成工作。若仍尝试 Workshop，先验证作弊状态与控制权，不继续无边界地补齐全部原生规则。
