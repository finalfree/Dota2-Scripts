# Workshop-first 迁移验收记录

> 本文保留第一次迁移时的目录名与产物哈希。后续已重命名为 `overforged`（Overforged / 超限武装），
> 并合并至两个标准 NPC 文件；当前启动与维护位置以 [开发说明](workshop-addon.md) 为准。

完成时间：2026-09-03 凌晨（北京时间）。

## 结论

已完成源码目录迁移、双目标构建和离线回归。现在只维护一份自定义内容，VPK 从 addon 源码生成。
这是 **待游戏内验收的 addon 原型**，不是已经验证可发布、可联机、可运行 OpenHyperAI 的成品。
本次没有启动游戏、重新编译纹理、上传 Workshop，或替换现有 `dota_lv` VPK。

## 明早先做什么

1. 完全退出 Dota，记录并备份、暂时停用当前 `dota_lv` 自定义覆盖包，不要删除。
   旧包与 addon 同时加载可能造成重复 ID、资源遮蔽或崩溃；本次没有替你停用旧包。
2. 启动 Workshop Tools，选择 `lv_upgraded_items`；游戏目录下的开发联接已经建立。
3. 按 [Workshop 开发说明](workshop-addon.md#明天的最小验收顺序) 启动本地游戏，先看加载日志，再测地图、英雄、购买和合成。
4. 最后独立测试 OpenHyperAI。当前 `lv_fill_bots` 用 `Tutorial:AddBot()` 只补真人对面的一队；两边都有真人时不加机器人。该命令仍不会自动安装或选择 OHA。
5. 本地通过后，再决定是否仅好友可见发布，并用 Workshop ID 和朋友客户端重新验证。

若 Tools 不接受直接引用基础 `dota` 地图，或没有 Bot Script 入口，保留控制台错误继续排查。
不要把离线测试通过理解为这些问题已经解决。

## 改动与维护位置

- `game/dota_addons/lv_upgraded_items/`：唯一自定义运行源码，含 82 个物品/配方定义、1 个私有能力、Lua、中英文文本和编译纹理。
- `content/dota_addons/lv_upgraded_items/`：四个图标的 PNG/VTEX 源资源。
- `pak01_dir/`：恢复为 `main` 的官方基线；与 `main` 比较无文件差异。
- `deploy_items_only.ps1`、`deploy_all.ps1`、`Merge-Pak02WithLvItems.ps1`：读取上述同一份源码，继续支持 `-PackageOnly`。
- 构建器只生成三个兼容适配文件，不复制 KV/Lua/纹理到另一套需要维护的源码树。
- 八个原有物品 Lua 和四个已编译图标字节不变。私有溅射能力仅从物品文件分离，定义不变。
- 本地化只保留自定义键，每种语言 371 个；旧 nullifier 的大小写重复 Lore 键按最后定义生效规则归一，最终文本不变。

开发联接（不是复制）：

```text
E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_addons\lv_upgraded_items
  -> D:\learning\Dota2-Scripts\game\dota_addons\lv_upgraded_items
E:\SteamLibrary\steamapps\common\dota 2 beta\content\dota_addons\lv_upgraded_items
  -> D:\learning\Dota2-Scripts\content\dota_addons\lv_upgraded_items
```

不要递归清空游戏目录里的联接；那会删除仓库源码。

## 已通过的检查

| 检查 | 结果 |
| --- | --- |
| Python 回归 | 35 项通过：资源、ID、目录、适配器、本地化、VPK 收拢与生成器 |
| Lua | 5 个替身测试套件通过，9 个运行文件通过 Lua 5.1 语法检查 |
| 原打包回归 | 14 项通过 |
| 映射打包回归 | 跨目录/空格路径、纯映射、预加载、确定性、输入保护和临时文件清理通过 |
| 兼容入口 | Windows PowerShell 5.1 与 PowerShell 7 构建检查通过 |
| 增量 VPK | 19 文件；v1 单文件、CRC、源码 payload SHA256 检查通过 |
| 全量 VPK | 166 文件；包内容检查通过 |
| 天地星合并 VPK | 原 451 文件，合并后 467 文件；包与注入内容检查通过 |
| 迁移前后对比 | 生效 NPC 定义一致；全部英文 15972 / 中文 15917 个最终文本键值一致；14 个未转换 payload 字节一致 |

详细测试输出在 `bin/verification/`。这些是静态、替身及文件校验，不能证明游戏引擎内的玩法正确。
官方基线保留原有 EOF 空行；忽略该既有空行规则后的 Git whitespace 检查通过。

## 可验收的构建产物

以下均未部署；使用时注意独立增量包不能替代需要保留天地星内容的合并包。

| 文件 | SHA256 |
| --- | --- |
| `bin/workshop-migration-before.vpk`（迁移前） | `E033C16D0D3AD20A6D156AA8F7427F9628ED69E7734D8C2ED6233C95147A4E44` |
| `bin/workshop-migration-after.vpk`、`bin/pak01_dir.vpk`（迁移后增量） | `80DB97FE9DB5FA158EEDDCF603FC7DD476E37EFD31954FDEF7A4E5B1E20D1474` |
| `bin/workshop-migration-full.vpk` | `8D5F7C36F7D88AC9B5C1022F07A8FDBCD6481CA421A5BB4C94FFC66C3719FC09` |
| `bin/workshop-migration-merged.vpk` | `176A253AA0271993676E9D59C17EDDB7B1E751AE4E95F287A9C94EE5220761B2` |

本次结束时，未替换的 `E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv\pak01_dir.vpk`
哈希为 `8B8A2E64195D119110E2EAB8BE506A6BBF87B4DE7025163C731A7FF786731D80`。

## 保留与恢复

- 仍在 `addons` 分支，没有切换分支、提交、推送或拉取；全部迁移改动留在工作区供验收。
- 开始时工作区干净，起点提交为 `8918f7a778e023f5e3c01a7c5a32639301471395`。
- 分支原本比远端领先 2 个、落后 1 个提交，本次未处理同步问题。
- 迁移前源码及哈希清单保存在 `bin/workshop-migration-source-backup/`，旧构建包也保留。
- `bin/` 被 Git 忽略，重要备份如需长期保存应另行归档；不要运行一键清空 `bin`。
- 游戏内验证失败时先保存日志，不要覆盖官方基线或运行提取脚本来回退自定义源码。
