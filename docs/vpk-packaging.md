# VPKEdit 打包与部署（Workshop-first）

自定义内容的唯一来源是 `game/dota_addons/overforged`；`pak01_dir` 是纯官方基线。
完整架构和首次 addon 验收见 [Workshop-first 开发说明](workshop-addon.md)。

## 入口与输出

### 联机轻量版（2026-10-21）

运行 `./deploy_multiplayer.ps1`，默认打包并部署，输出 `bin/multiplayer/pak03_dir.vpk`。
使用 `-PackageOnly` 可仅打包。默认部署目标为
`E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_schinese\pak03_dir.vpk`；
沿用退出游戏检查、旧包备份和部署哈希校验。可用 `-TargetDirectory` 指定其他目录。
支持 `-OutputPath`、`-VpkEditCli`、`-Python`。原来的全装备入口和源码定义不变。

当前只选择 `item_lv_gem`（兼容 ID 10004），成品 0 金币，在商店消耗品分类直接出售；
无需原版宝石或配方，进入存活本体英雄主栏后沿用原逻辑自动吸收。每队一次，重复物品保留可出售。
保留死亡不移除的状态图标和隐藏物品实体，去掉该状态的高空视野，只留下全队全图原生真视。
真视不揭开战争迷雾。脚本按购买者所在队伍启用，不额外限制购买者为主机。

联机稳定版源码独立维护在 `game/dota_addons/overforged_multiplayer`：

- `scripts/npc/npc_items_custom.txt`：仅宝石，手工维护 0 金价格和无高空视野的状态。
- `scripts/vscripts/lv/item_lv_gem.lua`：独立反隐逻辑，不自动同步单机版变化。
- `resource/addon_english.txt`、`resource/addon_schinese.txt`：独立说明。
- `scripts/shops.txt`：独立新增商店条目，构建时与官方商店合并。

`packaging/multiplayer.txt` 限定六个包内文件。物品 KV 和 Lua 直接映射联机源码，
不再读取单机装备或在构建时抽取/改写宝石。共用的只有通用打包工具和官方基线。
`items.txt` 加载入口、完整官方加联机本地化以及商店合并仍是必要的 VPK 适配产物。

**不能靠改名 Pak03 自动合并装备。** VPK 中同一路径的文件有覆盖关系，不会逐个合并 KV 条目。
本包包含完整的 `scripts/npc/items.txt`、`scripts/shops.txt` 和中英本地化；若 Pak02 也包含这些路径，
就会冲突。与旧超限武装包还共用宝石 ID、别名路径和 Lua 路径。要组合必须在构建时合并这些数据，
不能仅将两个包并排摆放来保证两套功能均生效。未检查任意外部 Pak02 的具体内容或验证其加载顺序。
联机轻量玩法应使用本包替换旧全装备自定义包；不要覆盖官方游戏基线。此入口不会自动替换任何已安装包。

本次六文件 VPK v1 单文件 CRC 和 payload SHA256 校验通过；专门的 profile 隔离测试通过。
用户反馈此前宝石吸收后仅显示 buff 时，未装补丁的玩家查看装备不会崩溃；崩溃来自其他装备。
新版本的商店入口、0 金购买、去掉高空视野、未装补丁队友共享及死亡复活效果仍待用户实测。
未部署、未启动游戏、未发布 Workshop。

```powershell
.\deploy_items_only.ps1 -PackageOnly     # 增量：bin/pak01_dir.vpk
.\deploy_all.ps1 -PackageOnly            # 全量：仓库根 pak01_dir.vpk
.\Merge-Pak02WithLvItems.ps1 -PackageOnly # 天地星合并：bin/pak01_merged_dir.vpk
```

去掉 `-PackageOnly` 会在确认 Dota 已退出后，备份并部署至已配置的
`E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_schinese\pak01_dir.vpk`。
仍支持 `-OutputPath`、`-TargetDirectory`、`-VpkEditCli`；增量支持 `-Manifest`。
不会自动终止游戏，不修改官方 `game/dota/pak01_dir.vpk` 或 `gameinfo.gi`。
不要用独立增量包覆盖需要保留的天地星合并版；这种情况下应使用合并入口。

`Merge Mods.bat` 继续调用全量 `-PackageOnly`，不部署。
这些入口不上传 Workshop；addon 发布要在实际兼容性验收后另行操作。

## 源码映射：不复制共享资源

`packaging/items.txt` 列的是 **包内路径**，支持空行与 `#` 注释，不允许目录、通配符、绝对路径和 `..`。

构建过程：

1. `scripts/Build-LvVpk.ps1` 调用 `prepare_vpk.py`。
2. 在唯一的 `bin/vpk-adapter-<ID>` 内生成三个兼容文件：
   - 官方完整 `scripts/npc/items.txt`，前置两个 `#base`：`overforged_items.txt` 与 `overforged_abilities.txt`。
   - 官方完整 `resource/localization/abilities_english.txt` + addon 自定义 token。
   - 同样的简体中文本地化文件。
3. 生成 `file-map.json`，将包内路径映射到 addon 共享源码、只读官方文件或上述生成文件。
   `packaging/npc-sources.json` 指定两个 NPC 包内别名对应 addon 的标准 `npc_*_custom.txt`，不另存一份 KV。
4. `Build-Vpk.ps1 -FileMap` 直接读取这些文件：Lua/KV/纹理不复制到暂存目录。
5. 先用小型 response file 打包直接资源，再用 VPKEdit `--add-file` 加入映射资源。
6. VPKEdit 的 Modify 模式会生成外部分块，`--single-file` 在这个模式下无效。
   `flatten_vpk.py` 直接将 payload 收拢到单文件 v1 数据区，保留目录/预加载字节并逐项校验 CRC。
7. 重新进行 VPKEdit CRC 验证，以及独立的 `Test-VpkPackage.ps1` 文件集合、v1、单文件、payload SHA256 校验。
8. 全部通过才替换旧输出；部署时仍检查游戏进程、备份旧包、核对目标哈希。

固定 VPKEdit CLI `--version 1 --single-file`。本机 v2 覆盖包曾被游戏报告损坏，不能替代 v1。
本机版本 `v5.0.0-beta.4`；实现参考：[VPKEdit CLI](https://github.com/craftablescience/VPKEdit/blob/master/src/cli/Main.cpp)。
需要 Python 3.10+ 和 PowerShell 5.1/7；普通基线的低层直接打包仍可只用 `Build-Vpk.ps1`，不提供 `FileMap` 时不需要 Python 收拢。

## 保护与检查

- 不把 addoninfo、游戏模式 Lua 或 `npc_*_custom.txt` 带入普通 VPK。
- 私有能力直接维护在 `npc_abilities_custom.txt`，以 `overforged_abilities.txt` 的包内别名供 `items.txt` 引用；物品同理。不会把原名 `npc_*_custom.txt` 作为包内入口重复加载。
- 拒绝不安全路径、重复包内路径、缺文件、目录和输入符号链接；禁止输出覆盖输入。
- 文件清单需包含 `#base`、Lua 和纹理依赖；新增文件后修改清单并运行测试。
- 失败保留旧输出；临时 response、候选 VPK 和其分块自动清理；适配文本留在忽略目录便于排查。
- `bin` 内容都是生成物/备份，不手工维护，不自动大范围清空。
- `extract_latest.ps1` 仅同步官方 `scripts/npc/`、`scripts/shops.txt` 和中英文 `abilities_*.txt`；
  使用 `bin` 临时区完成校验后整体替换基线，从而让 Git 正确显示官方文件的新增、修改与删除。
- 本地开发联接在游戏的 `dota_addons` 下；打包始终从仓库真实路径读取，避免跟随游戏目录联接。

## 回归

```powershell
python -X utf8 -m unittest discover -s tests -p 'test_*.py' -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_packaging.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_mapped_packaging.ps1
```

旧测试覆盖直接清单、空行注释、路径/目录/缺文件、损坏包、原输出保护等；映射测试覆盖跨目录、空格、
预加载种子、纯映射构建、确定性重建、缺映射源、自覆盖拒绝和分块清理。测试不部署到游戏。

包校验通过不等于部署成功，更不等于游戏内验证成功；三者必须分别记录。
