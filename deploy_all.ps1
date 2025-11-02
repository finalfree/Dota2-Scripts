# ########## 用户配置 ##########
# 设置你的Dota 2 VPK目标路径，注意末尾不要加 \
$TARGET_DIR = "E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv"
# ############################

# 捕获当前目录
$CURRENT_DIR = Get-Location

# 1. 使用vpk.exe，打包当前目录下的 pak01_dir
Write-Host "[4/5] 正在执行 vpk.exe 打包..."
Write-Host ""
$vpkExe = Join-Path $CURRENT_DIR "vpk\vpk.exe"
if (Test-Path $vpkExe) {
    Start-Process -FilePath $vpkExe -ArgumentList "pak01_dir" -Wait
    Write-Host ""
    Write-Host "      打包操作已执行。"
} else {
    Write-Host "      错误：找不到 vpk.exe，请检查路径是否正确。"
    Set-Location -Path $CURRENT_DIR
    exit 1
}

# 5. 复制生成的VPK文件到目标目录
Write-Host "[5/5] 正在部署生成的 VPK 文件..."
$vpkFile = Join-Path $CURRENT_DIR "pak01_dir.vpk"
if (Test-Path $vpkFile) {
    Write-Host "      已成功生成 `"pak01_dir.vpk`"，准备复制..."
    try {
        Copy-Item -Path $vpkFile -Destination $TARGET_DIR -Force
        Write-Host "      文件已成功覆盖到: `"$TARGET_DIR`""
    } catch {
        Write-Host "      错误：文件复制失败！请检查目标路径是否正确或是否有写入权限。"
        Write-Host "      错误详情: $($_.Exception.Message)"
    }
} else {
    Write-Host "      错误：打包失败！未在 `"bin`" 目录中找到 `"pak01_dir.vpk`"。"
}

# 返回原始目录
Set-Location -Path $CURRENT_DIR
Write-Host ""
Write-Host "----------------------------------------"
Write-Host "脚本执行完毕。"
Write-Host "----------------------------------------"
Write-Host "按任意键退出..."
$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")