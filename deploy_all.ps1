param(
    [switch]$PackageOnly,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'bin\all\pak02_dir.vpk'),
    [string]$TargetDirectory = 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_schinese',
    [string]$VpkEditCli = 'vpkeditcli'
)

$ErrorActionPreference = 'Stop'
$options = @{
    All = $true
    OutputPath = $OutputPath
    TargetDirectory = $TargetDirectory
    TargetFileName = 'pak02_dir.vpk'
    VpkEditCli = $VpkEditCli
    PackageOnly = $PackageOnly
}
& (Join-Path $PSScriptRoot 'scripts\Build-LvVpk.ps1') @options
