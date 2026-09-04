param(
    [switch]$PackageOnly,
    [switch]$All,
    [string]$Manifest = (Join-Path (Split-Path $PSScriptRoot -Parent) 'packaging/items.txt'),
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$TargetDirectory,
    [string]$VpkEditCli = 'vpkeditcli',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $PackageOnly -and (Get-Process -Name dota2 -ErrorAction SilentlyContinue)) {
    throw 'Please fully exit Dota 2 before deploying, or use -PackageOnly.'
}
$generated = Join-Path $repo ('bin/vpk-adapter-' + [guid]::NewGuid().ToString('N'))
$arguments = @((Join-Path $PSScriptRoot 'prepare_vpk.py'), '--output', $generated, '--manifest', $Manifest)
if ($All) { $arguments += '--all' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'VPK adapter generation failed. Previous package was not changed.' }
$map = @{}
$json = Get-Content -Raw -LiteralPath (Join-Path $generated 'file-map.json') -Encoding UTF8 | ConvertFrom-Json
foreach ($property in $json.PSObject.Properties) { $map[$property.Name] = [string]$property.Value }
$options = @{
    SourceRoot = Join-Path $repo 'game/dota_addons/overforged'
    Manifest = $Manifest
    FileMap = $map
    OutputPath = $OutputPath
    TargetDirectory = $TargetDirectory
    PackageOnly = $PackageOnly
    VpkEditCli = $VpkEditCli
    Python = $Python
}
if ($All) {
    # Still an explicit list: do not accidentally include addoninfo or bot scripts.
    $generatedManifest = Join-Path $generated 'files.txt'
    [IO.File]::WriteAllLines($generatedManifest, [string[]]($map.Keys | Sort-Object), [Text.UTF8Encoding]::new($false))
    $options.Manifest = $generatedManifest
}
& (Join-Path $PSScriptRoot 'Build-Vpk.ps1') @options
