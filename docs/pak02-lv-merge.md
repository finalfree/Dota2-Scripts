# 将 dota_lv 自定义物品合入天地星 pak02

这套流程面向作者持续更新的 `pak02_dir.vpk`。每次都以作者的新包为只读底包重新生成，不在上次合并产物上继续叠加，也不修改官方 `game/dota` 目录。

## 结论

合并后的包可以作为 `dota_lv` 的单一覆盖包使用。构建产物默认是 `bin/pak01_merged_dir.vpk`；部署时脚本将它复制为：

```text
E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv\pak01_dir.vpk
```

这依赖现有 `dota_lv/gameinfo.gi` 已正确把 `dota_lv` 放在 `dota` 前面的配置。作者要求把原 `pak02` 放到语言目录，是原包自己的安装方式；合并产物使用本项目已经验证的 `dota_lv` 覆盖路径。两者的游戏内效果是否完全相同仍需实测。

## 合并内容

脚本保留天地星包内的商店、基础游戏模式、物品、配方、Lua、图标和其他资源，再做三类改动：

1. 在天地星 `scripts/npc/npc_abilities.txt` 最前面加入：

   ```text
   #base "lv/lv_items.txt"
   #base "lv/lv_upgrades.txt"
   ```

   天地星原有的三个 `#base Fun/...` 紧随其后。不会复制本项目的完整 `scripts/npc/items.txt`。

2. 按 `packaging/pak02-lv-files.txt` 注入本项目的 LV KV、Lua 和以后列入清单的独立资源。不会用本项目的官方 `shops.txt` 覆盖天地星版本，因此“祝福”和难度工具入口得以保留。

3. 将本项目自定义物品对应的中英文 token 合并到 `abilities_*.txt` 的 `Tokens` 块。不是追加在整个文件的最后；追加到根节点之外不会成为 token。脚本会移除目标中同名的 LV token，再在 `Tokens` 结束前写入一份规范化结果。

本地化键由 `lv_items.txt`、`lv_upgrades.txt` 中的实际内部名自动识别，也包含 `DOTA_Tooltip_modifier_lv_*`。源本地化存在重复键时按文件中的最后一个定义取值并报告数量。天地星以后如果新增了与 LV 同名的物品或重复 ID，脚本会停止，不会静默决定使用哪一方。

## 使用方法

把作者最新版保存为仓库根目录的 `pak02_dir.vpk`，先只构建：

```powershell
.\Merge-Pak02WithLvItems.ps1 -PackageOnly
```

确认游戏完全退出后，构建并部署：

```powershell
.\Merge-Pak02WithLvItems.ps1
```

也可以显式指定输入、输出或目标目录：

```powershell
.\Merge-Pak02WithLvItems.ps1 `
  -PackageOnly `
  -BasePak D:\downloads\pak02_dir.vpk `
  -OutputPath .\bin\pak01_merged_dir.vpk
```

每次作者更新后都重新以新 `pak02_dir.vpk` 构建。不要把 `pak01_merged_dir.vpk` 再作为 `-BasePak`；脚本检测到已有 LV `#base` 时会拒绝，以免重复合并。

## 构建与安全检查

- 源包先由 VPKEdit 校验全部文件 CRC，且必须是 VPK v1 单文件。
- 由于作者包含有非 UTF-8 的旧中文文件名，VPKEdit 不能直接全量解包或修改。`scripts/Expand-VpkV1.ps1` 对 UTF-8 失败的文件名使用 GB18030 解码，并检查路径越界、重复条目、数据边界和外部块。
- 展开目录使用 `bin/pak02-merge-<随机ID>`，构建结束自动删除；源 `pak02_dir.vpk` 的 SHA256 在构建前后必须一致。
- 使用现有 `scripts/Build-Vpk.ps1` 重新打成 VPK v1 单文件，并独立核对全部输出文件的 SHA256。
- 再从候选包提取 `npc_abilities.txt`、两份本地化和清单内全部 LV 文件，逐项核对 SHA256。
- 输出成功后才替换旧构建产物。部署前检测 Dota 2 进程，备份旧 `pak01_dir.vpk`，复制后核对 SHA256。
- 不会自动结束游戏，不会修改或部署到官方 `game/dota`。

## LV 源内重复检查

脚本会检查 LV 源自身的重复内部名和 ID，发现时报警并保留清单与 `#base` 的现有顺序，不会静默删除定义。2026-08-29 已将重复的玲珑心和配方定义从 `lv_upgrades.txt` 删除，只保留 `lv_items.txt` 中的专用实现；当前 88 个定义没有重复内部名。

## 当前离线验证结果

2026-08-29 使用当时的作者包执行 `-PackageOnly`：

- 底包 447 个文件，全部 CRC 校验通过。
- 合并产物 454 个文件，VPK v1 单文件。
- 中英文分别合并 381 个唯一 LV token，并各自规范化 1 个仅大小写不同的 `item_lv_nullifier` Lore 源定义；最后出现的标准 `_Lore` 拼写和值生效。
- 全部 454 个输出 payload 的 SHA256 与打包前文件一致；9 个注入或合并路径重新提取后也逐项一致。
- 产物：`bin/pak01_merged_dir.vpk`。
- 构建日志会打印当次 SHA256；部署时使用同一哈希核对目标文件。

以上结构已完成离线构建校验；部署状态和游戏内验证结果应按每次运行单独记录。
