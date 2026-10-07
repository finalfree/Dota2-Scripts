param(
    [string]$SourceVpk = $(if ($env:DOTA_PAK01_VPK) { $env:DOTA_PAK01_VPK } else { 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota\pak01_dir.vpk' }),
    [string]$VpkEditCli = 'vpkeditcli',
    [switch]$AllowDirtyBaseline
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$binRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'bin'))
$baselineRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'pak01_dir'))
$stageRoot = Join-Path $binRoot ('official-extract-' + [guid]::NewGuid().ToString('N'))
$payloadRoot = Join-Path $stageRoot 'pak01_dir'
$backupRoot = Join-Path $binRoot ('official-extract-backup-' + [guid]::NewGuid().ToString('N'))
$source = Get-Item -LiteralPath $SourceVpk -Force
if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'SourceVpk must be a regular VPK file.'
}
$script:cliPath = (Get-Command $VpkEditCli -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source

function Assert-UnderBin([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $binRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Temporary path escaped bin: $full"
    }
}

function Invoke-VpkEdit([string[]]$Arguments) {
    & $script:cliPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "VPKEdit failed with exit code $LASTEXITCODE."
    }
}

if (-not $AllowDirtyBaseline) {
    $baselineChanges = @(git -C $repoRoot status --porcelain -- pak01_dir)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the pak01_dir Git status.' }
    if ($baselineChanges.Count -gt 0) {
        throw 'pak01_dir has uncommitted changes. Commit/revert them first, or pass -AllowDirtyBaseline deliberately.'
    }
}

Assert-UnderBin $stageRoot
Assert-UnderBin $backupRoot
New-Item -ItemType Directory -Path (Join-Path $payloadRoot 'scripts/npc') -Force | Out-Null
try {
    Invoke-VpkEdit @('--extract', 'scripts/npc/', '-o', (Join-Path $payloadRoot 'scripts/npc'), $source.FullName)
    foreach ($entry in @(
        'scripts/shops.txt',
        'resource/localization/abilities_english.txt',
        'resource/localization/abilities_schinese.txt'
    )) {
        $target = Join-Path $payloadRoot $entry
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Invoke-VpkEdit @('--extract', $entry, '-o', $target, $source.FullName)
    }

    foreach ($required in @(
        'scripts/npc/items.txt',
        'scripts/npc/npc_abilities.txt',
        'scripts/npc/npc_ability_ids.txt',
        'scripts/npc/npc_heroes.txt',
        'scripts/npc/npc_units.txt',
        'scripts/shops.txt',
        'resource/localization/abilities_english.txt',
        'resource/localization/abilities_schinese.txt'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $payloadRoot $required) -PathType Leaf)) {
            throw "Required official file was not extracted: $required"
        }
    }
    if (Get-ChildItem -LiteralPath $payloadRoot -Recurse -Force -Attributes ReparsePoint) {
        throw 'Extracted baseline unexpectedly contains a reparse point.'
    }
    if (Test-Path -LiteralPath $baselineRoot) {
        $baseline = Get-Item -LiteralPath $baselineRoot -Force
        if (-not $baseline.PSIsContainer -or ($baseline.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'pak01_dir must be a regular directory.'
        }
        [IO.Directory]::Move($baselineRoot, $backupRoot)
    }
    try {
        [IO.Directory]::Move($payloadRoot, $baselineRoot)
    } catch {
        if ((Test-Path -LiteralPath $backupRoot) -and -not (Test-Path -LiteralPath $baselineRoot)) {
            [IO.Directory]::Move($backupRoot, $baselineRoot)
        }
        throw
    }
    $count = @(Get-ChildItem -LiteralPath $baselineRoot -Recurse -File -Force).Count
    Write-Host "Updated tracked official baseline from $($source.FullName): $count files."
} finally {
    if (Test-Path -LiteralPath $stageRoot) { [IO.Directory]::Delete($stageRoot, $true) }
    if (Test-Path -LiteralPath $backupRoot) { [IO.Directory]::Delete($backupRoot, $true) }
}
