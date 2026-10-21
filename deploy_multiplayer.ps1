param(
    [switch]$PackageOnly,
    [string]$TargetDirectory = 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_schinese',
    [string]$OutputPath = (Join-Path $PSScriptRoot 'bin/multiplayer/pak03_dir.vpk'),
    [string]$VpkEditCli = 'vpkeditcli',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'scripts/Build-LvVpk.ps1') -PackageOnly:$PackageOnly -Profile multiplayer `
    -TargetDirectory $TargetDirectory -TargetFileName 'pak03_dir.vpk' `
    -Manifest (Join-Path $PSScriptRoot 'packaging/multiplayer.txt') `
    -OutputPath $OutputPath -VpkEditCli $VpkEditCli -Python $Python
