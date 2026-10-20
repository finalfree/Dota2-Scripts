# 超限武装静态网站

纯 HTML、CSS、JavaScript，无前端框架、依赖安装或服务端逻辑。`dist/` 是可以直接部署的完整网站，图片随站点提供，不依赖外部字体或图片服务。

## 本地预览

在仓库根目录运行：

```powershell
python -m http.server 8788 --bind 127.0.0.1 --directory website/dist
```

打开 <http://127.0.0.1:8788>。也可直接打开 `dist/index.html`，交互不依赖服务端请求。

## 更新装备内容

网站的完整说明与升级图鉴来自根目录 README，四张原画来自 `artwork/item-icons/`。更新这些内容后执行：

```powershell
python website/sync-content.py
```

该操作更新 `dist/data.js` 并同步四张原画。页面中的主视觉文案、永久能力摘要和四件装备的重点数值分别维护在 `dist/index.html`、`dist/app.js`；调整相关装备后应同步检查这些摘要。

装备详情优先展示有效能力，例如蝶翼之殇的 1.2 秒基础攻击间隔；完整原始效果与叠加、目标限制合并到可展开的使用说明中。能力摘要在 `sync-content.py` 的 `HIGHLIGHTS` 维护，原始说明仍来自 README。

升级图鉴的 31 个条目均带本地游戏原始图标，永久能力及其他融合装备也已补齐。新增装备后，可在内容同步后从自己安装的官方游戏 VPK 提取缺少的图标：

```powershell
python website/extract-icons.py 'E:/SteamLibrary/steamapps/common/dota 2 beta/game/dota/pak01_dir.vpk'
```

请将参数替换为本机实际官方 VPK 路径。脚本仅提取并解码原始图标，逐项核对 CRC；不会启动游戏或修改安装目录。提取结果保存在 `dist/assets/items/`，来源和尺寸记录在 `reference/item-icons.json`。已提取图标随网站一起部署，不需要访问外部图片服务。

首页的三元重戟主视觉为基于本机游戏原始图标的 ImageGen 高清重绘，独立保存在 `dist/assets/trident-hero.png`，不会修改游戏里的图标。原始图标与重绘说明见 `reference/`。首页状态抗性采用当前配置的 80%。

下载补丁区域展示用户指定的安装目录 `X:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_schinese`，并说明盘符替换及同名文件备份。

交互包括重点装备详情弹窗、31 行升级图鉴的类别筛选和全文搜索、展开/收起、键盘快捷键 `/` 与 Escape。界面支持手机布局与减少动态效果偏好。

## 部署到 Cloudflare Workers

进入 `website` 目录，使用 Wrangler 的静态资源部署：

```powershell
cd website
npx wrangler deploy
```

`wrangler.jsonc` 只声明静态资源目录，不含 Worker 服务端入口。构建命令留空，部署命令为 `npx wrangler deploy`。若使用 Git 集成，项目根目录选择 `website`。

Git 集成的生产分支请选择 `addons`，网站源码在此分支，`main` 是官方资源基线。Cloudflare Worker 名称应为 `overforged`，与配置文件一致。

若部署平台提供“安装命令 / 构建命令 / 静态资源目录”这类表单（如 ESA Pages），安装与构建命令都留空；若不允许留空，可分别填 `echo skip`。根目录选择 `website`，静态资源目录填 `dist`，函数文件路径和环境变量留空。此站点没有 `package.json`，不应使用默认的 `npm install` 或 `npm run build`。

下载按钮直接指向 `https://github.com/finalfree/Dota2-Scripts/releases/latest/download/pak02_dir.vpk`，朋友无需先打开版本列表。下载区域采用单栏，安装说明在下载按钮上方展示。VPK 仍由 GitHub Release 分发，不放入站点。

当前为本地设计预览，未创建云端 Site、部署 Workers 或修改发布工作流。
