param(
    [switch]$PackageOnly,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'pak01_dir.vpk'),
    [string]$TargetDirectory = 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv',
    [string]$VpkEditCli = 'vpkeditcli'
)

$ErrorActionPreference = 'Stop'
$options = @{
    All = $true
    OutputPath = $OutputPath
    TargetDirectory = $TargetDirectory
    VpkEditCli = $VpkEditCli
    PackageOnly = $PackageOnly
}
& (Join-Path $PSScriptRoot 'scripts\Build-LvVpk.ps1') @options
