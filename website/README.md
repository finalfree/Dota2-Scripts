# 超限武装网站

网站使用 Astro 构建，保留原有深色装备展示风格。Astro 组件接近 HTML；只有图鉴筛选、弹窗等交互需要浏览器 JavaScript，没有 React/Vue 运行时、数据库或服务端函数。构建结果仍是纯静态文件。

## 开始开发

需要 Node.js 22.22+（建议 Node.js 24 LTS）。在仓库根目录运行：

```powershell
cd website
npm ci
npm run dev
```

打开终端打印的本地地址。修改 `src/` 后页面会自动刷新。

```powershell
npm run build
npm run preview
```

`build` 重新生成 `dist/`；`preview` 预览这份实际产物。先构建再预览，不要手改 `dist/`。依赖版本由 `package-lock.json` 锁定。首次安装或依赖有变化时运行 `npm ci`，日常修改页面不需要重新安装。

## 目录和修改示例

| 位置 | 用途 |
| --- | --- |
| `src/pages/index.astro` | 单机版页面，将各章节组件组合起来 |
| `src/pages/multiplayer.astro` | 独立联机版页面 |
| `src/layouts/SiteLayout.astro` | 页面标题、描述、公共页头和页脚 |
| `src/components/Header.astro` | 居中导航、显示当前版本的一键切换按钮 |
| `src/components/Hero.astro` | 首页标题与三元重戟主视觉 |
| `src/components/Ascension.astro` | 永久能力卡片 |
| `src/components/Arsenal.astro`、`WeaponCard.astro` | 融合装备展示与可复用卡片 |
| `src/components/Catalog.astro` | 装备图鉴、筛选与搜索入口 |
| `src/components/ItemDialog.astro` | 装备详情弹窗 |
| `src/components/Download.astro`、`MultiplayerDownload.astro` | 两个版本各自的下载与安装说明 |
| `src/data/equipment.json` | 从项目说明同步的装备详情、价格、升级图鉴 |
| `src/data/weapons.js` | 四件融合装备的展示文案与重点数值 |
| `src/scripts/equipment.js` | 搜索、筛选、展开、弹窗、键盘交互 |
| `src/scripts/navigation.js` | 随章节滚动更新导航状态 |
| `src/styles/global.css` | 全站样式和响应式布局 |
| `public/` | 随站点复制的图片、图标与静态响应头 |
| `dist/` | 构建生成的完整网站，沿用仓库已有的发行产物目录 |

例如，修改首页标题时，编辑 `Hero.astro` 的 `<h1>`；调整导航文字或顺序时，修改 `Header.astro` 顶部的 `links`。新增页面时，在 `src/pages/` 创建 `.astro` 文件并复用 `SiteLayout` 即可。

组件顶部 `---` 内的代码在构建时执行，后面的 HTML 描述界面。`WeaponCard` 通过参数接收装备数据，在构建时生成卡片，无需等 JavaScript 才显示。图鉴也有完整的静态 HTML，浏览器脚本启动后再接管筛选和折叠。

## 更新装备内容

完整说明与升级图鉴来自根目录 README，图标映射读取单机 addon 的 KV 与本地化。更新相关内容后执行：

```powershell
npm run sync:content
npm run build
```

同步脚本更新 `src/data/equipment.json` 和 `public/assets/` 的四张原画，不直接修改构建产物。普通 `npm run build` 不需要 Python，也不会访问游戏安装目录。

能力摘要维护在 `sync-content.py` 的 `HIGHLIGHTS`；首页和永久能力卡片的精选文案、`src/data/weapons.js` 的展示数值目前仍需人工核对。它们尚未完全从游戏配置自动生成，避免误以为修改任意一处就会同步所有摘要。

需要补齐官方图标时：

```powershell
python extract-icons.py 'E:/SteamLibrary/steamapps/common/dota 2 beta/game/dota/pak01_dir.vpk'
```

替换为本机实际路径。该脚本只提取资源，验证 CRC，将图标写入 `public/assets/items/`；来源记录在 `reference/item-icons.json`。首页三元重戟重绘原画为 `public/assets/trident-hero.png`，说明见 `reference/`。

## ESA Pages 静态部署

在平台配置：

| 配置 | 值 |
| --- | --- |
| Git 生产分支 | `addons`（`main` 是官方资源基线） |
| 根目录 | `website` |
| Node.js | 24 |
| 安装命令 | `npm ci` |
| 构建命令 | `npm run build` |
| 静态资源目录 | `dist` |
| 函数入口、环境变量 | 留空 |

输出保留 `index.html`、`multiplayer.html` 的既有入口，任何普通静态托管都可访问，无需 SPA 路由回退。原先安装/构建命令留空的配置应按上表更新。本次只做本地预览，尚未修改 ESA 控制台或发布线上版本。

如继续使用已有 Cloudflare 配置，先 `npm run build`，再执行 `npx wrangler deploy`。`wrangler.jsonc` 仍只托管静态资源。

下载按钮沿用 ESA 加速地址，对应 GitHub Release 的 `pak02_dir.vpk`（单机）和 `pak03_dir.vpk`（联机）。VPK 不进入网站构建，不运行游戏或模组部署脚本。

## 交互验收

- 单机/联机版本互跳、当前版本高亮和章节锚点。
- 搜索、分类筛选、无结果提示、展开/收起 31 条图鉴。
- 装备详情、完整使用说明、关闭按钮和 Escape；`/` 聚焦搜索。
- 桌面导航居中；窄屏导航和版本选择都保留，卡片不挤压文字。
- 两个下载按钮分别指向 Pak02/Pak03，安装路径与版本一致。

官方参考：[Astro 配置说明](https://docs.astro.build/en/reference/configuration-reference/)、[项目结构](https://docs.astro.build/en/basics/project-structure/)。
