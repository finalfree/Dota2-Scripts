# 项目工作入口

## 独立联机版源码（用户明确要求，2026-10-21）

单机全装备版继续维护 `game/dota_addons/overforged`；联机稳定版独立维护
`game/dota_addons/overforged_multiplayer` 的物品 KV、Lua、中英本地化与商店条目。
这是下文“唯一自定义运行源码”规则的明确例外。联机版不从单机装备抽取、复制或改写生成定义，
两份玩法源码独立演进；只共享通用打包工具和官方基线。联机商店源文件只维护新增条目，构建时与官方商店合并。
`deploy_multiplayer.ps1` 默认打包 `bin/multiplayer/pak03_dir.vpk` 并部署到配置的
`dota_schinese/pak03_dir.vpk`，`-PackageOnly` 只打包。不要因修改单机版而自动同步联机版。

本项目采用 Workshop-first：`game/dota_addons/overforged` 是唯一自定义运行源码，`content/dota_addons/overforged` 是资源源文件。`pak01_dir` 只保留官方基线；`dota_lv` VPK 是由同一份 addon 源码适配生成的兼容发行目标。

名称：Overforged / 超限武装。物品及配方全部手工维护在 `scripts/npc/npc_items_custom.txt`，私有能力在 `npc_abilities_custom.txt`，不再创建 `scripts/npc/lv`、生成区或 `#base` 分拆源文件；`item_lv_*` ID、Lua 路径和本地化键保持兼容。VPK 的两个 NPC 包内别名由 `packaging/npc-sources.json` 映射至这两个标准文件，不另存源码副本。

- 涉及新增物品、配方、商店列表、本地化、资源提取或打包部署时，先阅读 [新增可合成物品实践记录](docs/dota2-custom-items.md)。
- 涉及源码位置、Workshop、VPK 构建或联接安装时，先阅读 [Workshop-first 开发说明](docs/workshop-addon.md)。不要把自定义副本放回 `pak01_dir`，不要手改 `bin` 生成物。
- `main` 保存官方提取基线；自定义内容在功能分支维护。不得把自定义物品文本混入官方基线。
- `extract_latest.ps1` 只同步官方 `scripts/npc/`、`scripts/shops.txt` 和中英文 `abilities_*.txt`。它先完整提取到 `bin`，校验关键文件后再替换 `pak01_dir`，以便 Git 同时记录官方新增、修改和删除；运行前先处理该目录中的未提交改动。
- 旧 custom 文件入口仅在试玩验证成功，普通本地房间中未显示；改为 `npc_abilities.txt` 的 `#base` 显式引入后，用户已确认房间中能获取新玲珑心，并确认配方图标修正有效。不要据此宣称全部属性或全部模式都已验证。官方基线 `shops.txt` 保持不变；单机和联机 addon 的商店片段分别维护新增条目，构建时合并到官方或 Pak02 商店。新增商店分类图标尚未验证成功。
- 打包使用 VPKEdit CLI，固定 VPK v1 单文件；本机 v2 覆盖包被游戏报告损坏。先阅读 [打包与部署说明](docs/vpk-packaging.md)。`packaging/items.txt` 是包内路径，构建器映射至 addon 源码/官方基线/生成的三个适配文件，不复制共享资源到暂存目录。Modify 产生的分块必须由 `flatten_vpk.py` 收拢并重新通过 CRC/SHA256 校验。旧 `vpk`、`GCFScape` 工具目录已废弃删除。
- addon 本地 Tools 按名启动 `dota` 地图、物品资源显示，以及旧 `BotPopulate()` 流程中显式开启思考后的 OHA 机器人行动已由用户确认；不扩大为所有 AI 行为均正常。当前实验用 `Tutorial:AddBot()` 只补真人对面的一队：每名真人选英雄后回应一个机器人，最后一名真人选完再补满余位；两边都有真人时不加机器人。addon 内的 `lv_bot_draft.lua` 适配 OHA 提交 `cb814c6` 的一至五号位权重与弱英雄上限，并尝试从主机 OHA 加载纯数据模块以加入克制/协同评分，失败时退回位置权重；为避免阵容固化，最终抽取由 OHA 前五扩大为前 30，前五合计权重 30%。补满后才自动启用 FretBots，未移植 OHA 行为脚本，MIT 声明在 addon 根目录。新流程会启用 `sv_cheats`，战斗行为依赖主机现有本地 OHA 安装，OHA 数据是否能从 addon 服务器 VM 加载、控制权和新阵容分路是否修复均待实测。已发布 Workshop ID、Arcade Bot Script 入口和朋友客户端均未验证。测试前须防止旧 `dota_lv` 包与 addon 重复加载同名同 ID 资源；未经要求不要自动停用用户现有包或公开发布。
- AP 启动实验未成功；当前使用原命令启动 CUSTOM addon，不再推荐 `dota_force_gamemode 1` / `exec lv_test_ap`。已参考 2026 年维护的 Windy10v10AI 与 ModDota API，在初始化请求免费信使、默认神符逻辑和偷塔保护；Lua 测试通过，游戏内效果待验收。2026-09-04 实测已确认定点预缓存 Smeevil Gold 模型及黄色粒子后，该守卫及用户抽查的其他守卫可正常放置。`dota_bot_allow_human_control=0` 加共享位兜底仍未阻止 Tools/CUSTOM 的真人控制；当前新增服务器订单过滤，拒绝真人对双方 fake-client 所属单位的命令而放行 OHA/引擎命令，待实测。`lv_mode_status` 使用独立日志避免 FretBots 静音，规则 `requested` 不是实际效果证明。详见 Workshop 开发说明。用户要求自行操作游戏，未经再次要求不要启动或操控游戏。
- `Install-WorkshopAddon.ps1` 在游戏安装目录创建两个指向源码的目录联接，不复制源码。不要递归删除这些联接路径的内容；这等同于删除仓库源码。
- 保留用户已有改动；没有要求时，不主动切换分支、重置、提交或推送。
- 用户已授权：明确确认的本地模组资源修改，完成检查后默认使用 `deploy_items_only.ps1` 直接部署到已配置的 `dota_schinese`，不再逐次询问；若当次要求只修改或只打包，则遵循当次要求。部署前仍须确认游戏完全退出、备份旧包，部署后校验哈希；游戏运行或文件锁定时停止并提醒用户，不擅自终止游戏。
- 打包成功不等于部署成功，更不等于游戏内验证成功。分别报告包内容检查、部署校验和用户实测结果。
