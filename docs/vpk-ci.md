# GitHub Actions 打包与发布

[Build VPK 工作流](../.github/workflows/build-vpk.yml) 在 Ubuntu 24.04 构建机上执行，直接复用项目现有的 Python 与 PowerShell 打包脚本。

## 构建环境

不需要自建 Docker 镜像。GitHub 的 Ubuntu 24.04 构建机已预装 PowerShell；工作流用 `actions/setup-python` 配置 Python 3.12，然后下载 VPKEdit 官方 Linux x86_64 独立发行包。

2026-10-20 将官方 Action 升级为使用 Node.js 24 的版本，并按大版本引用，跟随官方维护的版本标签获得同一大版本内的更新：

| Action | 版本 | 内置运行时 |
| --- | --- | --- |
| `actions/checkout` | `v7` | Node.js 24 |
| `actions/setup-python` | `v7` | Node.js 24 |
| `actions/upload-artifact` | `v7` | Node.js 24 |
| `actions/download-artifact` | `v8` | Node.js 24 |

Node.js 是这些 Action 自身的运行时，不需要给打包流程额外安装 Node.js。Node.js 24 Action 要求 Actions Runner 至少为 `2.327.1`，此前云端日志中的 `2.337.0` 满足要求。当前使用的输入参数与 Artifact ID 输出在上述版本中仍受支持；上传继续按默认归档格式保存内部 Artifact，Release 分发两份 VPK 及各自的校验和构建信息，共六个独立文件。

VPKEdit 固定到 `v5.0.0.4`（应用版本 5.0.0 beta 4），下载文件为 `VPKEdit-Linux-Standalone-gcc-Release.zip`。工作流先比对固定 SHA256，再解压使用其中的 `vpkeditcli`，无需安装 GUI。

更新 CLI 时需要同时更新工作流中的 `VPKEDIT_TAG` 和对应 Linux ZIP 的 `VPKEDIT_SHA256`，并重新检查打包兼容性。

## 手动构建与测试版发布

1. 将工作流及相关源码提交并推送到 GitHub。普通分支推送不会自动打包或发布。
2. 进入仓库 **Actions → Build VPK → Run workflow**，选择分支。默认勾选“发布为测试版 Release”，构建成功后会自动发布测试版；取消勾选则只生成 Artifact。手动运行按钮要求工作流已经存在于默认分支。
3. 测试版使用唯一标签 `test-运行编号-重跑次数`，例如 `test-123456789-1`，指向本次实际构建的提交。发布说明使用该提交的 README，不需要 CHANGELOG；标记为预发布，不占用正式版 latest，也不会再次触发 `v*` 标签工作流。
4. 从 Release 附件直接下载 VPK 即可测试，无需解压。无论是否发布测试版，工作流也会保留 Artifact，供后续正式版直接复用。

Release 与 Artifact 均包含以下六个文件：

| 文件 | 内容 |
| --- | --- |
| `pak02_dir.vpk` | 单机全装备版，`packaging/items.txt`，VPK v1 单文件 |
| `pak02_dir.vpk.sha256` | 完整 VPK 文件的 SHA256 |
| `pak02_dir.vpk.build-info.json` | 单机版源码提交、构建时间、工作流地址、工具版本、文件大小与哈希 |
| `pak03_dir.vpk` | 独立联机版，仅免费宝石，`packaging/multiplayer.txt`，VPK v1 单文件 |
| `pak03_dir.vpk.sha256` | 联机 VPK 的 SHA256 |
| `pak03_dir.vpk.build-info.json` | 联机版源码提交、构建时间、工作流地址、工具版本、文件大小与哈希 |

Release 分别上传这六个原始文件，不上传 ZIP。VPK 最先上传；各版本的三个附件使用共同前缀，使 GitHub 按文件名排序时 VPK 位于第一位，发布说明顶部也提供按 VPK、校验、构建信息排列的下载链接。GitHub 自带的 Source code ZIP/TAR 是平台生成的源码快照，不是本工作流上传的分发包。

Artifact 保留 14 天，网页下载仍由 GitHub 打成 ZIP，下载通常需要登录并具有仓库访问权限；需要直接下载单个 VPK 时使用 Release。记下 `pak02_dir.vpk.build-info.json` 的 `commit`，安装并自行完成游戏内测试。

## v0.1.1 发布检查

本版更新日志已维护在根目录 `CHANGELOG.md` 的 `## v0.1.1` 章节。
先提交推送本版代码，手动构建同一提交，验收 Pak02/Pak03 后，将下面示例中的版本替换为 `v0.1.1`。
发布校验必须同时找到两份包及各自元数据，缺少或改动 Pak03 也会阻止发布。
旧的仅含 Pak02 的 Artifact 不能用于本次发布，需要运行更新后的工作流。
网站静态文件已更新，但此工作流不部署网站；网站仍通过现有静态托管流程更新。

## 测试通过后，推送版本标签

给测试通过的 **同一个 commit** 打标签并推送。首版使用 `v0.1.0`，发布说明直接读取该提交的 `README.md`，现在不需要创建 `CHANGELOG.md`。

例如在 PowerShell 中，先将下面的提交值替换为 `pak02_dir.vpk.build-info.json` 中的完整 `commit`，再执行：

```powershell
$testedCommit = '替换为测试通过的完整提交 SHA'
git tag -a v0.1.0 $testedCommit -m 'Overforged v0.1.0'
git push origin v0.1.0
```

推送 `v*` 标签后，工作流会：

1. 检出标签指向的提交，读取对应发布说明。
2. 找到该提交最近一次成功的手动构建，下载它的 Artifact。
3. 再次核对 VPK 版本、源码提交、文件大小与 SHA256。
4. 创建 Release 草稿，附上说明与上述六个独立文件；附件上传完成后自动正式发布。

发布阶段不重新打包，确保发布的是已供测试的同一份文件。若同一提交有多次手动构建，请测试最近一次成功构建的 Artifact。找不到成功构建、产物过期或文件校验不符时会停止发布；需要重新构建并测试，再重跑失败的标签工作流。

使用 `v0.2.0-rc.1` 这样的标签会发布为预发布版本，不标记为 latest。常规 `v0.2.0` 则发布为正式版本。已有同名 Release 不会被覆盖；若上传中断留下未完成草稿，可在 GitHub 删除该草稿后重跑，保留原标签。

工作流使用仓库自动提供的 `GITHUB_TOKEN`，发布任务拥有 `contents: write` 和 `actions: read` 权限，无需另填个人访问令牌。若仓库或组织策略禁止 Actions 创建 Release，需要先调整该策略。

## 后续版本的更新日志

从 `v0.1.1` 或 `v0.2.0` 起，在仓库根目录维护 `CHANGELOG.md`，每个版本一个二级标题。例如：

```markdown
# 更新日志

## v0.2.0

### 调整
- 在这里记录这次实际完成的装备调整。

### 修复
- 在这里记录这次实际修复的问题。
```

先把代码和对应日志一起提交、推送，再手动构建测试，最后给那个提交打标签。工作流只提取标签对应章节；缺失、重复或空白章节均会阻止发布，不会把首版 README 作为后续版本的兜底说明。

首版 README 中的图片和相对链接会自动转换为指向发布提交的完整地址，确保 Release 正文也能显示专属图标。

## 检查范围

装备检查已按 [消融记录](equipment-test-ablation.md) 精简：只检查单机／联机配置结构、ID 和引用合法性，
不固定价格、属性或合成材料组合。打包完整性和发布产物匹配检查保留。

工作流依次执行源码静态检查、映射打包回归和装备包构建。沿用现有流程收拢 VPK 分块，并核对 CRC、包内文件清单和各文件源码 SHA256；全部通过后才上传产物。

手动构建分别调用 `scripts/Build-LvVpk.ps1 -PackageOnly` 和 `deploy_multiplayer.ps1 -PackageOnly`，不需要安装 Dota 2，不会向本地游戏目录部署。手动勾选发布会创建测试版 Release，推送版本标签则发布对应正式版或预发布版；不会上传 Workshop 或发布网站。CI 分发产物分别命名为 `pak02_dir.vpk`、`pak03_dir.vpk`。本地部署目录统一为 `game/dota_schinese`；CI 始终显式传入 `-PackageOnly`，不会访问游戏目录。

用户已确认前一版 Linux 云端构建的 VPK 可正常使用；本轮新增的手动测试版发布与附件命名仍需推送后运行验收。

## 官方资料

- [GitHub 构建机与 Docker 的区别](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners)
- [Ubuntu 24.04 预装工具](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)
- [VPKEdit 安装说明](https://github.com/craftablescience/VPKEdit/blob/main/INSTALL.md)
- [固定版本发行文件](https://github.com/craftablescience/VPKEdit/releases/tag/v5.0.0.4)
