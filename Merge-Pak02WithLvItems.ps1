param(
    [switch]$PackageOnly,
    [string]$BasePak = (Join-Path $PSScriptRoot 'pak02_dir.vpk'),
    [string]$Manifest = (Join-Path $PSScriptRoot 'packaging\pak02-lv-files.txt'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'bin\pak01_merged_dir.vpk'),
    [string]$TargetDirectory = 'E:\SteamLibrary\steamapps\common\dota 2 beta\game\dota_lv',
    [string]$VpkEditCli = 'vpkeditcli'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-VpkEdit([string[]]$Arguments) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $messages = @(& $script:cliPath @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    foreach ($message in $messages) { Write-Host ([string]$message) }
    if ($code -ne 0) { throw "VPKEdit failed (exit code $code)." }
    if ($Arguments -contains '--verify-checksums' -and
        ($messages -join "`n") -notmatch '(?m)^All file checksums match their expected values\.\s*$') {
        throw 'VPKEdit did not confirm successful file checksum verification.'
    }
}

function Get-MaintainedPaths([string]$Path) {
    $paths = @(Get-Content -LiteralPath $Path -Encoding UTF8 |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($paths.Count -eq 0) { throw 'The pak02 merge file list is empty.' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $paths) {
        $relative = $entry.Replace('\', '/')
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '[:*?"<>|\[\]\x00-\x1f]' -or
            @($relative.Split('/') | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
            throw "Invalid merge manifest path: $entry"
        }
        if (-not $seen.Add($relative)) { throw "Duplicate merge manifest path: $entry" }
        $source = Get-Item -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'pak01_dir') $relative) -Force
        if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Merge inputs must be regular files: $entry"
        }
        $relative
    }
}

function Get-LvDefinitionInfo([string[]]$Paths) {
    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $duplicateNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $duplicateIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $Paths | Where-Object { $_ -like 'scripts/npc/*.txt' -or $_ -like 'scripts/npc/*/*.txt' }) {
        $text = [IO.File]::ReadAllText((Join-Path (Join-Path $PSScriptRoot 'pak01_dir') $path))
        foreach ($match in [regex]::Matches($text, '(?m)^\s*"(?<name>item_(?:recipe_)?lv_[^"]+)"\s*\r?\n\s*\{')) {
            $name = $match.Groups['name'].Value
            if (-not $names.Add($name)) { $null = $duplicateNames.Add($name) }
        }
        foreach ($match in [regex]::Matches($text, '(?m)^\s*"ID"\s*"(?<id>\d+)"')) {
            $id = $match.Groups['id'].Value
            if (-not $ids.Add($id)) { $null = $duplicateIds.Add($id) }
        }
    }
    if ($names.Count -eq 0 -or $ids.Count -eq 0) { throw 'No LV item definitions were found in the merge inputs.' }
    if ($duplicateNames.Count -gt 0 -or $duplicateIds.Count -gt 0) {
        Write-Warning ('The LV source itself has repeated definitions/IDs; merge order is preserved: names [{0}], IDs [{1}]' -f
            (($duplicateNames | Sort-Object) -join ', '), (($duplicateIds | Sort-Object) -join ', '))
    }
    [pscustomobject]@{ Names = $names; Ids = $ids; DuplicateNames = $duplicateNames; DuplicateIds = $duplicateIds }
}

function Assert-NoPak02DefinitionCollision([string]$NpcAbilitiesPath, $LvInfo) {
    $npcText = [IO.File]::ReadAllText($NpcAbilitiesPath)
    if ($npcText -match '(?im)^\s*#base\s+"?lv/') {
        throw 'BasePak already contains an lv #base entry. Use a fresh author pak02 package, not an earlier merged output.'
    }
    $baseMatches = [regex]::Matches($npcText, '(?im)^\s*#base\s+(?:"(?<quoted>[^"]+)"|(?<plain>\S+))')
    foreach ($baseMatch in $baseMatches) {
        $relative = if ($baseMatch.Groups['quoted'].Success) { $baseMatch.Groups['quoted'].Value } else { $baseMatch.Groups['plain'].Value }
        $relative = $relative.Replace('\', '/')
        if ([IO.Path]::IsPathRooted($relative) -or $relative.Split('/') -contains '..') { throw "Unsafe #base path in pak02: $relative" }
        $include = Join-Path ([IO.Path]::GetDirectoryName($NpcAbilitiesPath)) $relative
        if (-not (Test-Path -LiteralPath $include -PathType Leaf)) { throw "Missing pak02 #base file: $relative" }
        $text = [IO.File]::ReadAllText($include)
        foreach ($match in [regex]::Matches($text, '(?m)^\s*"(?<name>item_[^"]+)"\s*\r?\n\s*\{')) {
            if ($LvInfo.Names.Contains($match.Groups['name'].Value)) { throw "Item name conflict with pak02: $($match.Groups['name'].Value)" }
        }
        foreach ($match in [regex]::Matches($text, '(?m)^\s*"ID"\s*"(?<id>\d+)"')) {
            if ($LvInfo.Ids.Contains($match.Groups['id'].Value)) { throw "Item/ability ID conflict with pak02: $($match.Groups['id'].Value)" }
        }
    }
}

function Add-LvBaseLines([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $prefix = '#base "lv/lv_items.txt"' + $newline + '#base "lv/lv_upgrades.txt"' + $newline
    [IO.File]::WriteAllText($Path, $prefix + $text, [Text.UTF8Encoding]::new($false))
}

function Test-IsLvLocalizationKey([string]$Key, $LvInfo) {
    if ($Key.StartsWith('DOTA_Tooltip_modifier_lv_', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    foreach ($name in $LvInfo.Names) {
        if ($Key.IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Find-TokensClose([string]$Text) {
    $tokensMatch = [regex]::Match($Text, '(?i)"Tokens"\s*\{')
    if (-not $tokensMatch.Success) { throw 'Localization file has no Tokens block.' }
    $open = $Text.IndexOf('{', $tokensMatch.Index)
    $depth = 0; $inString = $false; $escaped = $false; $lineComment = $false; $blockComment = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]; $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        if ($lineComment) { if ($c -eq "`n") { $lineComment = $false }; continue }
        if ($blockComment) { if ($c -eq '*' -and $next -eq '/') { $blockComment = $false; $i++ }; continue }
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            continue
        }
        if ($c -eq '/' -and $next -eq '/') { $lineComment = $true; $i++; continue }
        if ($c -eq '/' -and $next -eq '*') { $blockComment = $true; $i++; continue }
        if ($c -eq '"') { $inString = $true; continue }
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $i } }
    }
    throw 'Localization Tokens block is not closed.'
}

function Merge-LvLocalization([string]$SourcePath, [string]$TargetPath, $LvInfo) {
    $sourceText = [IO.File]::ReadAllText($SourcePath)
    $tokenPattern = '(?m)^[ \t]*"(?<key>(?:\\.|[^"])*)"[ \t]+"(?<value>(?:\\.|[^"])*)"[^\r\n]*'
    $tokens = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $duplicateCount = 0
    foreach ($match in [regex]::Matches($sourceText, $tokenPattern)) {
        $key = $match.Groups['key'].Value
        if (Test-IsLvLocalizationKey $key $LvInfo) {
            if ($tokens.ContainsKey($key)) {
                $duplicateCount++
                # Assignment keeps the first key's casing. Remove it so the last definition
                # controls both spelling (_Lore) and value, matching KV load order.
                $null = $tokens.Remove($key)
            }
            $tokens.Add($key, $match.Groups['value'].Value)
        }
    }
    if ($tokens.Count -eq 0) { throw "No LV localization tokens found in $SourcePath" }

    $baseText = if (Test-Path -LiteralPath $TargetPath -PathType Leaf) { [IO.File]::ReadAllText($TargetPath) } else { $sourceText }
    # Remove any existing LV token lines, then add one canonical definition per key inside Tokens.
    $baseText = [regex]::Replace($baseText, $tokenPattern, {
        param($match)
        if (Test-IsLvLocalizationKey $match.Groups['key'].Value $LvInfo) { return '' }
        return $match.Value
    })
    $newline = if ($baseText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("`t`t// BEGIN dota_lv merged item localization")
    $sortedKeys = [string[]]$tokens.Keys
    [Array]::Sort($sortedKeys, [StringComparer]::Ordinal)
    foreach ($key in $sortedKeys) {
        $lines.Add("`t`t`"$key`"`t`t`"$($tokens[$key])`"")
    }
    $lines.Add("`t`t// END dota_lv merged item localization")
    $insertion = ($lines -join $newline) + $newline
    $close = Find-TokensClose $baseText
    $merged = $baseText.Insert($close, $insertion)
    $parent = [IO.Path]::GetDirectoryName($TargetPath)
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [IO.File]::WriteAllText($TargetPath, $merged, [Text.UTF8Encoding]::new($true))
    [pscustomobject]@{ Tokens = $tokens.Count; SourceDuplicatesResolved = $duplicateCount }
}

function Assert-InjectedPayloads([string]$Package, [hashtable]$Expected, [string]$WorkDirectory) {
    foreach ($entry in $Expected.Keys) {
        $extracted = Join-Path $WorkDirectory ([guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($entry))
        Invoke-VpkEdit @('--no-progress', '--extract', $entry, '-o', $extracted, $Package)
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $extracted).Hash
        if ($actual -ne $Expected[$entry]) { throw "Merged payload mismatch: $entry" }
    }
}

$script:cliPath = (Get-Command $VpkEditCli -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$baseFile = Get-Item -LiteralPath $BasePak -Force
if ($baseFile.PSIsContainer -or ($baseFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'BasePak must be a regular VPK file.' }
$baseHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $baseFile.FullName).Hash
$paths = @(Get-MaintainedPaths $Manifest)
$lvInfo = Get-LvDefinitionInfo $paths

$outputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([IO.Path]::GetExtension($outputFile) -ne '.vpk' -or $outputFile -eq $baseFile.FullName) {
    throw 'OutputPath must be a different .vpk file from BasePak.'
}
if (-not $PackageOnly) {
    if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) { throw 'Please fully exit Dota 2 before building for deployment, or use -PackageOnly.' }
    $targetDirectoryItem = Get-Item -LiteralPath $TargetDirectory -Force
    if (-not $targetDirectoryItem.PSIsContainer -or ($targetDirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Deployment target must be a real directory, not a file or reparse point.'
    }
    $targetFile = Join-Path $targetDirectoryItem.FullName 'pak01_dir.vpk'
    if ($targetFile -eq $outputFile -or $targetFile -eq $baseFile.FullName) { throw 'Build, base, and deployment files must be different paths.' }
}
$workRoot = Join-Path (Join-Path $PSScriptRoot 'bin') ('pak02-merge-' + [guid]::NewGuid().ToString('N'))
$staging = Join-Path $workRoot 'staging'
$candidate = Join-Path $workRoot 'candidate.vpk'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
try {
    Invoke-VpkEdit @('--no-progress', '--verify-checksums', 'files', $baseFile.FullName)
    $expanded = & (Join-Path $PSScriptRoot 'scripts\Expand-VpkV1.ps1') -Path $baseFile.FullName -Destination $staging
    Write-Host "Expanded base pak02: $($expanded.FileCount) files."

    $npcAbilities = Join-Path $staging 'scripts/npc/npc_abilities.txt'
    if (-not (Test-Path -LiteralPath $npcAbilities -PathType Leaf)) { throw 'BasePak has no scripts/npc/npc_abilities.txt.' }
    Assert-NoPak02DefinitionCollision $npcAbilities $lvInfo
    Add-LvBaseLines $npcAbilities

    foreach ($relative in $paths) {
        $source = Join-Path (Join-Path $PSScriptRoot 'pak01_dir') $relative
        $target = Join-Path $staging $relative
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    foreach ($language in 'schinese','english') {
        $source = Join-Path $PSScriptRoot "pak01_dir/resource/localization/abilities_$language.txt"
        $target = Join-Path $staging "resource/localization/abilities_$language.txt"
        $result = Merge-LvLocalization $source $target $lvInfo
        Write-Host "Localization ${language}: $($result.Tokens) LV tokens; resolved $($result.SourceDuplicatesResolved) duplicate source definitions."
    }

    & (Join-Path $PSScriptRoot 'scripts\Build-Vpk.ps1') -SourceRoot $staging -All -PackageOnly -OutputPath $candidate -VpkEditCli $script:cliPath
    $expected = @{}
    foreach ($relative in @($paths + 'scripts/npc/npc_abilities.txt' + 'resource/localization/abilities_schinese.txt' + 'resource/localization/abilities_english.txt')) {
        $expected[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $staging $relative)).Hash
    }
    Assert-InjectedPayloads $candidate $expected $workRoot
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $baseFile.FullName).Hash -ne $baseHashBefore) { throw 'BasePak changed during the build.' }

    $outputDirectory = [IO.Path]::GetDirectoryName($outputFile)
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $outputFile -PathType Leaf) { [IO.File]::Replace($candidate, $outputFile, [NullString]::Value) }
    else { Move-Item -LiteralPath $candidate -Destination $outputFile }
    $outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFile).Hash
    Write-Host "Merged package: $outputFile"
    Write-Host "SHA256: $outputHash"
    if ($PackageOnly) { Write-Host 'Merged package verified; not deployed (-PackageOnly).'; return }

    if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) { throw 'Merged package built, but Dota 2 is running. Deployment was skipped.' }
    if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
        $backupDirectory = Join-Path $PSScriptRoot 'bin/backups'
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        $backup = Join-Path $backupDirectory ('pak01-before-pak02-merge-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.vpk')
        Copy-Item -LiteralPath $targetFile -Destination $backup
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $targetFile).Hash) { throw 'Backup verification failed.' }
        Write-Host "Previous deployment backup: $backup"
    }
    Copy-Item -LiteralPath $outputFile -Destination $targetFile -Force
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $targetFile).Hash -ne $outputHash) { throw 'Deployment hash mismatch.' }
    Write-Host "Deployed as pak01_dir.vpk and hash-verified: $targetFile"
    Write-Host 'In-game verification is still required.'
} finally {
    if (Test-Path -LiteralPath $workRoot -PathType Container) {
        $resolvedWork = (Get-Item -LiteralPath $workRoot).FullName
        $resolvedBin = (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'bin')).FullName.TrimEnd('\') + '\'
        if (-not $resolvedWork.StartsWith($resolvedBin, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolvedWork) -notlike 'pak02-merge-*') {
            throw "Refusing to clean unexpected work directory: $resolvedWork"
        }
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
