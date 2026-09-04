[CmdletBinding()]
param(
    [string]$DotaRoot = 'E:\SteamLibrary\steamapps\common\dota 2 beta',
    [switch]$RemoveLegacyLinks
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$addonName = 'overforged'
$installation = (Get-Item -LiteralPath $DotaRoot).FullName
if (-not (Test-Path -LiteralPath (Join-Path $installation 'game/dota/gameinfo.gi') -PathType Leaf)) {
    throw 'DotaRoot must be a Dota 2 installation containing game/dota/gameinfo.gi.'
}
if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) {
    throw 'Please fully exit Dota 2 before linking the development addon.'
}
$links = @()
$legacyLinks = @()
foreach ($kind in 'game', 'content') {
    $relative = "$kind/dota_addons/$addonName"
    $source = (Get-Item -LiteralPath (Join-Path $PSScriptRoot $relative)).FullName
    $target = Join-Path $installation $relative
    if ($source -eq $target) { throw 'Repository must be outside the game installation for this linker.' }
    $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        if (-not ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            $existing.LinkType -ne 'Junction' -or
            [string]$existing.Target -ne $source) {
            throw "Refusing to replace existing addon directory: $target"
        }
    }
    $links += [pscustomobject]@{ Source=$source; Target=$target }
    if ($RemoveLegacyLinks) {
        $legacyRelative = "$kind/dota_addons/lv_upgraded_items"
        $legacyTarget = [IO.Path]::GetFullPath((Join-Path $installation $legacyRelative))
        $legacySource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $legacyRelative))
        # Get-Item also sees a dangling junction after the source directory rename.
        $legacy = Get-Item -LiteralPath $legacyTarget -Force -ErrorAction SilentlyContinue
        if ($null -ne $legacy) {
            if (-not $legacyTarget.StartsWith($installation.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
                -not ($legacy.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                $legacy.LinkType -ne 'Junction' -or [string]$legacy.Target -ne $legacySource) {
                throw "Refusing to remove foreign legacy addon directory: $legacyTarget"
            }
            $legacyLinks += $legacyTarget
        }
    }
}
# Check all destinations/legacy links before mutations. No source copies.
foreach ($link in $links) {
    if (-not (Test-Path -LiteralPath $link.Target)) {
        New-Item -ItemType Directory -Path (Split-Path $link.Target -Parent) -Force | Out-Null
        New-Item -ItemType Junction -Path $link.Target -Target $link.Source | Out-Null
    }
    $verified = Get-Item -LiteralPath $link.Target -Force
    if ([string]$verified.Target -ne $link.Source) { throw 'Junction verification failed.' }
    Write-Host "Linked $($link.Target) -> $($link.Source)"
}
foreach ($legacyTarget in $legacyLinks) {
    # Nonrecursive Windows junction removal: never follow it into repository sources.
    [IO.Directory]::Delete($legacyTarget, $false)
    Write-Host "Removed legacy junction only: $legacyTarget"
}
Write-Host 'Development links ready. No VPK deployment, game launch or Workshop upload was performed.'
Write-Host 'Local test command: dota_launch_custom_game overforged dota'
Write-Host 'Base-map loading and OpenHyperAI compatibility still require an in-game test.'
