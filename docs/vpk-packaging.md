# VPKEdit 打包与部署（Workshop-first）

自定义内容的唯一来源是 `game/dota_addons/overforged`；`pak01_dir` 是纯官方基线。
完整架构和首次 addon 验收见 [Workshop-first 开发说明](workshop-addon.md)。

## 入口与输出

```powershell
.\deploy_items_only.ps1 -PackageOnly     # 增量：bin/pak01_dir.vpk
.\deploy_all.ps1 -PackageOnly            # 全量：仓库根 pak01_dir.vpk
.\Merge-Pak02WithLvItems.ps1 -PackageOnly # 天地星合并：bin/pak01_merged_dir.vpk
```

去掉 `-PackageOnly` 会在确认 Dota 已退出后，备份并部署至已配置的
`E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv\pak01_dir.vpk`。
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
