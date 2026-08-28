param(
    [switch]$PackageOnly,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'pak01_dir.vpk'),
    [string]$TargetDirectory = 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv',
    [string]$VpkEditCli = 'vpkeditcli'
)

$ErrorActionPreference = 'Stop'
$options = @{
    SourceRoot = Join-Path $PSScriptRoot 'pak01_dir'
    All = $true
    OutputPath = $OutputPath
    TargetDirectory = $TargetDirectory
    VpkEditCli = $VpkEditCli
    PackageOnly = $PackageOnly
}
& (Join-Path $PSScriptRoot 'scripts\Build-Vpk.ps1') @options
