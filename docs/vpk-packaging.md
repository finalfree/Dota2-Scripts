# VPKEdit 打包与部署

2026-08-28：项目改用已安装的 `vpkeditcli`，不再依赖仓库里的 `vpk.exe` 或 GCFScape；两个旧工具目录已删除，可从 Git 历史恢复。提取脚本也使用 `vpkeditcli`。

## 格式与依赖

本机测试版本为 VPKEdit CLI `v5.0.0-beta.4`，默认从 PATH 查找。也可传入 `-VpkEditCli 'C:\Program Files\VPKEdit\vpkeditcli.exe'`。

固定 `--type vpk --version 1 --single-file`。用户已确认 VPKEdit v1 包游戏内正常；相同实验的 v2 包在 Dota 启动时被报告损坏，即使包检查通过也不能使用它替代 v1。不要依赖 CLI 默认版本，也不要据此推断所有 Dota 官方包都不支持 v2。

## 按文件清单打包，不复制资源

编辑 `packaging/items.txt`，每行一个相对 `pak01_dir/` 的文件路径，支持空行和以 `#` 开头的注释。不能写目录、通配符、绝对路径或 `..`，路径有空格时也不要加引号。

`main` 默认只有 `scripts/npc/items.txt`，资源保持官方基线。功能分支应自行调整清单；玲珑心五文件清单见 [物品实践记录第 7 节](dota2-custom-items.md#7-本地打包与部署)。文件清单不会自动发现 `#base`、Lua 或纹理依赖，新增依赖必须列入清单。

```powershell
# 只打包与校验，不修改游戏目录
.\deploy_items_only.ps1 -PackageOnly

# 指定另一份清单、输出位置
.\deploy_items_only.ps1 -PackageOnly -Manifest .\packaging\items.txt -OutputPath .\bin\test.vpk

# 游戏完全退出且明确需要部署时
.\deploy_items_only.ps1
```

增量默认输出 `bin/pak01_dir.vpk`。默认部署目录为 `E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv`，可用 `-TargetDirectory` 指定另一目录；目标目录必须已存在。仅打包不需要安装游戏。

全量打包 `pak01_dir/` 内的全部文件：

```powershell
.\deploy_all.ps1 -PackageOnly
# 去掉 -PackageOnly 会继续部署
```

全量默认输出仓库根目录 `pak01_dir.vpk`。`Merge Mods.bat` 调用全量脚本的 `-PackageOnly` 模式，不部署。三个入口共用 `scripts/Build-Vpk.ps1`。

## 为什么仍有一个临时清单

VPKEdit 的 [response file 实现](https://github.com/craftablescience/VPKEdit/pull/268/files) 支持 `@文件清单`，清单行同时决定磁盘相对路径和包内路径，且**相对于清单所在目录**，而不是当前工作目录。其 [CLI 源码](https://github.com/craftablescience/VPKEdit/blob/main/src/cli/Main.cpp) 可用于核对版本差异。

因此脚本先验证用户维护的清单，再在 `pak01_dir/` 创建很小的 `.vpkedit-<随机ID>.rsp`（UTF-8 无 BOM、LF 换行、无空行/注释），直接打包这些原文件。只生成清单和候选 VPK，不复制资源。临时清单和未发布候选包在 `finally` 中删除；强制杀进程可能留下文件，临时清单已加入忽略规则且全量打包会排除它。旧 `bin/pak01_dir` 不再使用，也不会自动清理。

原生 response reader 不支持我们需要的注释规则，空行可能指向整个目录，且缺失文件可能只打印错误而仍返回 0；不要把带注释的维护清单直接传给 CLI。

## 校验与安全边界

脚本会：

- 拒绝空清单、重复路径、缺失文件、目录、路径越界和输入符号链接；输出须在资源目录外。
- 固定 v1 单文件；检查 CLI 退出码和文件 CRC 成功信息，不能仅信任退出码。
- 用 `scripts/Test-VpkPackage.ps1` 独立解析包目录，核对版本、完整文件集合及每个文件的 SHA256，与打包前源码对照；不解压到暂存目录。
- 校验通过后才替换输出包；打包或校验失败时保留旧输出。
- 部署前检查 Dota 是否运行，将已有部署包备份到 `bin/backups/` 并校验，复制后再核对 SHA256。文件锁等失败会报错，不会显示成功。

不自动终止游戏，不修改官方 `game/dota/pak01_dir.vpk`，不自动配置 `gameinfo.gi`。备份不会自动清理。输出包内容只保证与清单及源码一致，不保证游戏效果；启动模式、加载入口、属性和图标仍需用户实测。

## 脚本自测

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\test_packaging.ps1
```

使用实际 VPKEdit，在 `bin/` 下生成隔离测试目录，覆盖多文件、空格、UTF-8 内容、清单错误、旧输出保护及损坏包检查；不向真实游戏目录部署。测试产物保留便于排查。Windows PowerShell 5.1 与 PowerShell 7 均可运行。
