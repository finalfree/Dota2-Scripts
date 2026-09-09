# 商店入口调研：如何把一个全新物品放进商店

调研日期 2026-09-08。所有结论均来自本机实机文件与二进制取证，未启动游戏，未部署。

取证对象：`E:\SteamLibrary\steamapps\common\dota 2 beta`（`deploy_items_only.ps1` 的实际目标）。
`D:\dota2\dota2-BY jxsdw2` 是 2021 年的旧安装（VPK 时间戳 2021-09，物品图标只有 392 个），
**不要**再用它做资源侧结论。

## 1. 商店列表就是 `scripts/shops.txt`，由客户端 C++ 直接读

| 证据 | 位置 |
| --- | --- |
| 字符串 `scripts/shops.txt` 只出现一次 | `game/dota/bin/win64/client.dll`，文件偏移 `0x2688598` |
| 紧邻的字符串 | `shopdata`、`consumables`、`support`、`basics`、`weapons_armor`、`artifacts`、`weapons`、`defense`、`magics`、`BasicItems`、`UpgradeItems`、`ShopItemSection`、`ShopItemSectionItemList`、`section_name`、`#DOTA_SUBSHOP_%s` |
| `scripts/shops/%s_shops.txt` | 只在 `server.dll` 出现，`scripts/shops/` 目录在实机 VPK 中**不存在**，是遗留分支 |

结论：

- 商店界面**不是** Panorama 布局/JS 实现的（实机 VPK 里 `panorama/` 下没有任何 `hud_shop` 的
  layout 或 scripts，只有 `styles/hud/dota_hud_shop.vcss_c`）。UI 是 client.dll 里的自定义面板类
  `ShopItemSection` / `ShopItemSectionItemList`。
- 所以**改 KV 就够了**，不需要、也不可能靠 Panorama 脚本加入口。
- 2026-09-10 重新运行 `extract_latest.ps1` 后，仓库基线 `pak01_dir/scripts/shops.txt`
  与实机当前版本逐字节一致，可以直接作为合并基准。

## 2. 分类（商店页签）是 C++ 硬编码枚举，不能新增

- `client.dll` / `server.dll` 都有 `DOTA_SHOP_CATEGORY_*` 字符串表，共 15 个枚举 +
  `RECOMMENDED_ITEMS` / `SEARCH_RESULTS` / `NONE`。
- 实机 `resource/localization/dota_english.txt` 中只有 19 个 `#DOTA_SUBSHOP_*` 键：
  `ARTIFACTS`、`ATTRIBUTES`、`BASICS`、`CONSUMABLES`、`DEFENSE`、`MAGICS`、`MISC`、
  `RECIPE_ARTIFACTS`、`RECIPE_BASICS`、`RECIPE_DEFENSE`、`RECIPE_MAGICS`、`RECIPE_SUPPORT`、
  `RECIPE_WEAPONS`、`SECRETSHOP`、`SIDE_PAGE_1`、`SIDE_PAGE_2`、`SUPPORT`、`WEAPONS`、
  `WEAPONS_ARMOR`。
- 这些键**不在** `abilities_english.txt`（我们目前在打包的文件）里，而在 `dota_english.txt`。

结论：

- **加不了新页签**。写进 `dota_shops` 的新分类名不会被解析成页签。
- **能改页签名**：`#DOTA_SUBSHOP_<大写分类名>` 是普通本地化键，可以在 addon 的
  `resource/addon_english.txt` / `addon_schinese.txt` 里覆盖。
- **能换页签图标**：图标是 `materials/vgui/hud/dota_shop_*_off.vmat_c` / `_on.vmat_c`
  （`consumables`、`attributeboost`、`miscellaneous`、`secretshop`、`weaponsarmor`、
  `recipe_basic`、`recipe_support`、`recipe_magics`、`recipe_defense`、`recipe_weapons`、
  `recipe_ancient_weaponry`、`recipe_enchanted_artifacts`）。覆盖材质即可换图，
  这也是之前「新增商店分类图标」唯一可行的形态——换皮，不是新增。

## 3. 两条进入路径（本次调研最重要的结论）

| 物品类型 | 入口 | 要不要改 `shops.txt` |
| --- | --- | --- |
| **升级物品**（有 `ItemRequirements` 指向原版父物品） | 父物品的**商店升级树**自动出现 | **不要**。这也是 AGENTS.md 现行策略，已实测 |
| **全新物品**（没有父物品） | 升级树里没有它的位置 | **必须**，把物品名写进某个已有分类的 `"item"` 列表 |

升级树的三个前提（2026-08-28 实测，见 `.workbuddy/memory/2026-08-28.md`）：
`ItemPurchasable "1"`、`ItemCost` = 原价 + 卷轴价、配方名 `item_recipe_<结果物品名>`。

### 上次 `magics` 实验失败的推断

`docs/dota2-custom-items.md:568` 记录：在 `magics` 里加自定义条目后出现「重复血棘」。

对比第三方 pak02 包（`docs/pak02-custom-items-analysis.md:166`）的做法，差异只有一点：

- pak02 加进 `consumables` 的三件（`item_fun_harder` / `item_fun_easier` / `item_fun_blessing`）
  全是**没有父物品的全新工具**；
- 我们当时加进 `magics` 的是**有父物品的升级品**。

即：升级品被同时登记进「升级树」和「分类格子表」两套机制 → 重复渲染。
`magics` 现有 20 个条目（`weapons` / `artifacts` 也是 20，`basics` / `support` / `defense` 是 16），
4 列网格正好铺满，溢出也可能是叠加因素。

这是**推断，不是实测**。要坐实必须重新做最小实验（第 6 节）。

## 4. 落到本仓库：怎么改

现状约束：

- `scripts/validate_addon.py:77` 明确断言 addon 目录里**不允许**存在 `scripts/shops.txt`
  （与 items.txt、npc_heroes.txt 同列），防止把官方基线整份复制进 addon 造成漂移。
- `AGENTS.md` 也禁止把自定义内容写进 `pak01_dir` 官方基线。
- `packaging/items.txt` **已经**包含 `scripts/shops.txt`，不需要改清单。
- `scripts/prepare_vpk.py:45` 的解析顺序是 `GAME = game/dota_addons/overforged` 优先，
  找不到才回落到 `BASELINE = pak01_dir`。

建议走和 `items.txt`、本地化一样的**生成式路线**（不破坏上面两条禁令）：

1. 新增 addon 侧增量文件，例如 `game/dota_addons/overforged/scripts/lv_shops.txt`，只写要加的条目：

   ```text
   "dota_shops"
   {
       "misc"
       {
           "item"      "item_lv_xxx"
       }
   }
   ```

2. `prepare_vpk.py` 增加一条分支：`scripts/shops.txt` = 官方基线 + 增量合并后生成到
   `bin/vpk-adapter-*/`，写进 `file-map.json`（与 `resource/localization/abilities_*` 的
   `merge_localization` 完全同构）。
3. `validate_addon.py` 的禁令**保留**，只把新增量文件名加入允许列表。
4. `packaging/items.txt` 不动。

如果只想先验证而不改构建流程，可以临时手工改 `pak01_dir/scripts/shops.txt` 跑一次
`deploy_items_only.ps1 -PackageOnly`，但**验证完必须还原**，`main` 分支不得带自定义改动。

## 5. 图标

### 规则

- 不写 `AbilityTextureName` 时，图标 = `panorama/images/items/<内部名去掉 item_ 前缀>_png.vtex_c`。
- 写 `"AbilityTextureName" "item_foo"` → 找 `panorama/images/items/foo_png.vtex_c`。
- addon 内的 `.vtex_c` 必须有 `content/dota_addons/overforged` 下同名 `.vtex` 源文件，
  且 `.vtex` 里引用的 png 存在（`validate_addon.py` 会检查）。

### 方案 A：直接复用官方图标（零新资源，最安全）

把 `AbilityTextureName` 指到任意官方图标即可，不需要新增任何文件。
可优先挑已退出商店但仍有 KV 定义的「退役物品」：`poor_mans_shield`、`iron_talon`、
`philosophers_stone`、`necronomicon`、`ring_of_aquila`、`demonicon`、`heavy_blade`、
`slippers_of_halcyon`、`band_of_elvenskin`、`gem_of_true_sight`、`ghost_scepter`、`salve`。

### 方案 B：官方「没有对应物品定义」的图标

实机 VPK 中 `panorama/images/items/*_png.vtex_c` 共 **601** 个，`items.txt` 中有 **544** 个物品，
其中 **186** 个图标在 `items.txt` 里找不到对应物品。剔除 arcana 变体、瓶身状态、`ofrenda_xx`
编号图、`*_active` / `*_inactive` 之后，可直接使用的一批：

```text
aegis_heart        ambient_sorcery     band_of_elvenskin   bear_cloak
bogduggs_baldric   bogduggs_cudgel     bogduggs_lucky_femur
carapace_of_qaldin corrupting_blade    crimson_robe        creed_of_omniscience
cyclone_2          echo_stone          flask2              gem_of_true_sight
ghost_scepter      glimmerdark_shield  gloves_of_haste     gravel_foot
greater_clarity    greater_salve       guardian_shell      ice_dragon_maw
lifestone          longclaws_amulet    mage_loop           oblivions_locket
paw_of_lucius      pelt_of_the_old_wolf precious_egg       preserved_skull
salve              sign_of_the_arachnid slippers_of_halcyon slippers_of_the_abyss
stonework_pendant  stony_coat          tombstone           tome_of_shadow_wave
tome_of_torrents   treads_of_ermacor   unhallowed_icon     wand_of_the_brine
watchers_gaze      world_chasm_artifact
```

完整 186 条可由 `bin` 下的探针输出重算（脚本见本次会话，未固化到 `scripts/`）。

### 方案 C：自制 / 换色

沿用 `scripts/icon_tool.py` 的官方图标换色路线，产出
`content/dota_addons/overforged/panorama/images/items/<name>.vtex` + 编译后的 `_png.vtex_c`。
项目已有的 4 个融合物品图标就是这条路线，已验证可用。

## 6. 建议的最小实验（验证可行性与失败原因）

一次只改一个变量，按现有「四段分别报告」的规矩独立记录：

1. 挑一个**没有父物品的全新**测试物品（不要拿现成的 `item_lv_*` 升级品），
   图标先用 `AbilityTextureName` 指向官方现成图标（零新资源）。
2. 只在 `misc`（15 条，基础分类）末尾加 1 条 `"item"`。
3. `-PackageOnly` 打包 → 校验 → 部署 → 用户进游戏只做三件事：
   该页签末尾是否出现、图标是否正确、能否正常购买。
4. 通过后再做第二次：同一个物品改成写进 `magics`，对比是否复现「重复血棘」，
   以此判定失败原因到底是「分类」还是「升级品重复登记」。

不要一次改多个分类，也不要一次加多个物品。

## 7. 未验证项

- 新条目在客户端页签中的实际排版（网格是否会溢出/重复）。
- 通过 addon 本地化覆盖 `#DOTA_SUBSHOP_*` 是否真的生效（这些键原在 `dota_english.txt`，
  而我们目前只打包 `abilities_*.txt`）。
- 覆盖 `dota_shop_*_off/_on.vmat_c` 换页签图标是否生效。
- Workshop addon 模式（非 VPK）下 `scripts/shops.txt` 是否同样被 addon 目录遮蔽——
  按搜索路径规则应当生效，但未实测。
