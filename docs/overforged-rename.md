# Overforged / 超限武装：改名与 NPC 合并验收

2026-09-03。此次是结构迁移，不修改物品数值、ID、配方或 AI 行为。

## 当前入口

- 运行源码：`game/dota_addons/overforged/`；资源源文件：`content/dota_addons/overforged/`。
- `scripts/npc/npc_items_custom.txt`：直接包含 82 个物品/配方；自动生成区之外手工维护。
- `scripts/npc/npc_abilities_custom.txt`：直接包含 1 个私有能力。
- 原 `scripts/npc/lv` 的三个 KV 文件已合并后移除；没有第二份维护副本。
- `scripts/vscripts/lv`、`item_lv_*`、本地化物品 token 和 `lv_mode_status` 等命令保持兼容。
- 游戏目录下 game/content 两个联接已更换，旧联接仅做非递归移除。

在 Workshop Tools 中打开 Overforged，执行 `dota_launch_custom_game overforged dota`；
地图加载后再输入 `jointeam good`。名称显示与改名后的实际开局仍待用户验收。

## 离线结果

- 迁移前后全部 83 个自定义定义（含完整字段、ID、配方）相等，中英文物品 token 相等；仅 addon 标题改名。
- 8 个物品 Lua、4 个编译纹理和 8 个源资源共 20 个文件逐字节相等。
- 44 项 Python 测试：40 通过；4 个图标大小断言仍失败（期望 7748，实际 7764），改名前也同样失败，未更改纹理或放宽断言。
- 8 个 Lua 替身套件和 12 个运行文件的 Lua 5.1 语法检查通过。
- 生成器完整重生成的幂等性、手工区保护、CRLF/LF 保留、异常标记拒写、部分生成拒写均通过。
- 映射打包回归及 Windows PowerShell 5.1 联接安装/重复运行通过。
- 增量、全量、天地星合并三种 VPK 均通过 v1 单文件、CRC 和 payload SHA256 校验，均未部署。
- 增量包全部生效 NPC 数据等于官方基线 + 当前 addon；包内两个别名直接读取标准文件。

| 未部署的产物 | 文件数 | SHA256 |
| --- | --- | --- |
| `bin/overforged-items.vpk` | 18 | `897FDFA35677E1DBDF3A4D9499D6CAC5F61502C99DA197903714048C1EB05015` |
| `bin/overforged-full.vpk` | 165 | `533D792FA114073D967CEB252E787AA5BFD08B1C7A2D45A3252BF16864C1C7CD` |
| `bin/overforged-merged.vpk` | 466 | `22789711CB7F4F600212572D0AFAE5767361DE83519EAC45B52453CE0051E667` |

## 备份与边界

迁移前 game/content 源码备份在 `bin/overforged-rename-before-2553e9b9d7d6433ea6be3ccf87453abb/`。
移除的三个 KV 可从其中恢复；它是一次性恢复备份，不参与构建。不要清空 `bin` 后再依赖该备份。
没有改官方基线、部署游戏 VPK、重新编译图标、启动游戏、上传 Workshop、提交或推送。
用户此前停用的 `dota_lv/pak01_dir.vpk.Backup` 保持原状。

信使、神符和偷塔保护的新开关仍待游戏内验收；插眼崩溃未在本次处理。
