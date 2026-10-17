# GitHub Actions 打包与发布

[Build VPK 工作流](../.github/workflows/build-vpk.yml) 在 Ubuntu 24.04 构建机上执行，直接复用项目现有的 Python 与 PowerShell 打包脚本。

## 构建环境

不需要自建 Docker 镜像。GitHub 的 Ubuntu 24.04 构建机已预装 PowerShell；工作流用 `actions/setup-python` 配置 Python 3.12，然后下载 VPKEdit 官方 Linux x86_64 独立发行包。

VPKEdit 固定到 `v5.0.0.4`（应用版本 5.0.0 beta 4），下载文件为 `VPKEdit-Linux-Standalone-gcc-Release.zip`。工作流先比对固定 SHA256，再解压使用其中的 `vpkeditcli`，无需安装 GUI。

更新 CLI 时需要同时更新工作流中的 `VPKEDIT_TAG` 和对应 Linux ZIP 的 `VPKEDIT_SHA256`，并重新检查打包兼容性。

## 先手动构建，再测试

1. 将工作流及相关源码提交并推送到 GitHub。普通分支推送不会自动打包或发布。
2. 进入仓库 **Actions → Build VPK → Run workflow**，选择分支后手动运行。手动运行按钮要求工作流已经存在于默认分支。
3. 构建成功后，打开该次运行，在 **Artifacts** 中下载 `overforged-vpk-…`，解压后得到：

| 文件 | 内容 |
| --- | --- |
| `pak01_dir.vpk` | `packaging/items.txt` 指定的装备资源包，VPK v1 单文件 |
| `SHA256SUMS` | 完整 VPK 文件的 SHA256 |
| `build-info.json` | 源码提交、构建时间、工作流地址、工具版本、文件大小与哈希 |

产物保留 14 天。下载通常需要登录并具有仓库访问权限。记下 `build-info.json` 的 `commit`，安装这个 Artifact 中的 VPK 并自行完成游戏内测试；手动构建本身不会创建 Release。

## 测试通过后，推送版本标签

给测试通过的 **同一个 commit** 打标签并推送。首版使用 `v0.1.0`，发布说明直接读取该提交的 `README.md`，现在不需要创建 `CHANGELOG.md`。

例如在 PowerShell 中，先将下面的提交值替换为 `build-info.json` 中的完整 `commit`，再执行：

```powershell
$testedCommit = '替换为测试通过的完整提交 SHA'
git tag -a v0.1.0 $testedCommit -m 'Overforged v0.1.0'
git push origin v0.1.0
```

推送 `v*` 标签后，工作流会：

1. 检出标签指向的提交，读取对应发布说明。
2. 找到该提交最近一次成功的手动构建，下载它的 Artifact。
3. 再次核对 VPK 版本、源码提交、文件大小与 SHA256。
4. 创建 Release 草稿，附上说明与 `pak01_dir.vpk`、`SHA256SUMS`、`build-info.json`；附件上传完成后自动正式发布。

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

工作流依次执行源码静态检查、映射打包回归和装备包构建。沿用现有流程收拢 VPK 分块，并核对 CRC、包内文件清单和各文件源码 SHA256；全部通过后才上传产物。

手动构建调用的是 `scripts/Build-LvVpk.ps1 -PackageOnly`，不需要安装 Dota 2，不会向本地游戏目录部署。只有推送版本标签才会发布 GitHub Release；不会上传 Workshop 或发布网站。构建成功仍需独立进行游戏内验证。

首次 Linux 云端运行结果需在推送后确认；本机 Windows 检查不能代替 Linux 构建成功记录。

## 官方资料

- [GitHub 构建机与 Docker 的区别](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners)
- [Ubuntu 24.04 预装工具](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)
- [VPKEdit 安装说明](https://github.com/craftablescience/VPKEdit/blob/main/INSTALL.md)
- [固定版本发行文件](https://github.com/craftablescience/VPKEdit/releases/tag/v5.0.0.4)
