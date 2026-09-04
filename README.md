# Overforged · 超限武装

锻造超限装备，迎战强化 AI。采用 Workshop-first，一份源码生成 addon 与兼容 VPK。

自定义资源只维护一份：

- `game/dota_addons/overforged/`：物品、能力、Lua、中英文本、编译纹理。
- `content/dota_addons/overforged/`：Workshop Tools 使用的 PNG/VTEX 源资源。
- `pak01_dir/`：官方提取基线；不得再添加 LV 自定义内容。
- `artwork/item-icons/item_lv_*.png`：独立高清设计原稿，不直接发布。
- `scripts/item_upgrades.json`：自动升级装备的生成配置；只更新 `npc_items_custom.txt` 的标记区，手工物品写在标记区之外。
- `scripts/npc/npc_items_custom.txt` / `npc_abilities_custom.txt`（addon 内）：直接存放物品/配方与能力，不再分拆 `npc/lv` 文件。
- `bin/`：生成的适配文件、VPK、测试和备份，不手工维护。

本地启动、物品资源显示及 OHA 机器人行动已由用户确认；仍不代表已发布 Workshop 的兼容性通过。
现在默认在策略阶段用 `Tutorial:AddBot()` 只补满真人对面的队伍，再请求开启 FretBots（启用作弊，保留难度投票）；两边都有真人时不加机器人。新流程待实测，依赖主机已安装的本地 OHA。
先阅读 [Workshop 开发与验收](docs/workshop-addon.md)。
本次改名与合并、产物哈希见 [Overforged 验收记录](docs/overforged-rename.md)；
首次 Workshop 迁移的历史信息见 [原迁移记录](docs/workshop-migration-acceptance.md)。

改名后的本地开局命令是 `dota_launch_custom_game overforged dota`，地图加载后再输入 `jointeam good`。
旧 `lv_upgraded_items` 名称仅保留在历史记录和迁移检测中；物品内部 `item_lv_*` 标识与 `lv_mode_status` 等命令不变。

## 常用命令

```powershell
# 静态检查与回归；无需启动游戏
python -X utf8 scripts/validate_addon.py
python -X utf8 -m unittest discover -s tests -p 'test_*.py' -v
python -X utf8 tests/run_lua_tests.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_packaging.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_mapped_packaging.ps1

# VPK 兼容发行目标：读取同一份 addon 源码
.\deploy_items_only.ps1 -PackageOnly
.\deploy_all.ps1 -PackageOnly
.\Merge-Pak02WithLvItems.ps1 -PackageOnly

# 游戏完全退出后，把标准 game/content addon 路径联接到仓库
.\Install-WorkshopAddon.ps1
```

需要 Python 3.10+、PowerShell 5.1/7 和 VPKEdit CLI。Lua 测试的可选依赖见测试脚本。
`deploy_items_only.ps1` / `deploy_all.ps1` 去掉 `-PackageOnly` 会备份并覆盖已配置的 `dota_lv/pak01_dir.vpk`，
不会发布 Workshop。开发目录联接也不会修改或停用现有 `dota_lv` 包。

Git 根目录可以在游戏安装目录外；不需要复制或手工同步第二份 addon。
通过 Tools 编辑联接目录就是编辑仓库源码，切换/清理分支前必须注意这一点。
