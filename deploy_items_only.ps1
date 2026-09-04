param(
    [switch]$PackageOnly,
    [string]$Manifest = (Join-Path $PSScriptRoot 'packaging\items.txt'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'bin\pak01_dir.vpk'),
    [string]$TargetDirectory = 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv',
    [string]$VpkEditCli = 'vpkeditcli'
)

$ErrorActionPreference = 'Stop'
$options = @{
    Manifest = $Manifest
    OutputPath = $OutputPath
    TargetDirectory = $TargetDirectory
    VpkEditCli = $VpkEditCli
    PackageOnly = $PackageOnly
}
& (Join-Path $PSScriptRoot 'scripts\Build-LvVpk.ps1') @options
