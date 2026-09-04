[CmdletBinding(DefaultParameterSetName = 'Manifest')]
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true, ParameterSetName = 'Manifest')][string]$Manifest,
    [Parameter(Mandatory = $true, ParameterSetName = 'All')][switch]$All,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$TargetDirectory,
    [switch]$PackageOnly,
    [hashtable]$FileMap = @{},
    [string]$Python = 'python',
    [string]$VpkEditCli = 'vpkeditcli'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NoReparsePoint([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Symbolic links/junctions are not supported in input paths: $Path"
        }
        if ($item -is [IO.FileInfo]) { $item = $item.Directory } else { $item = $item.Parent }
    }
}

function Invoke-VpkEdit([string[]]$CliArguments) {
    # Native stderr handling differs between Windows PowerShell 5.1 and 7.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $messages = @(& $script:cliPath @CliArguments 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    foreach ($message in $messages) { Write-Host ([string]$message) }
    if ($code -ne 0) { throw "VPKEdit failed (exit code $code)." }
    # This CLI version can report checksum errors and still return exit code 0.
    if ($CliArguments -contains '--verify-checksums' -and
        ($messages -join "`n") -notmatch '(?m)^All file checksums match their expected values\.\s*$') {
        throw 'VPKEdit did not confirm successful file checksum verification.'
    }
}

$script:cliPath = (Get-Command $VpkEditCli -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$sourceItem = Get-Item -LiteralPath $SourceRoot -Force
if (-not $sourceItem.PSIsContainer -or $null -eq $sourceItem.Parent) { throw 'SourceRoot must be a resource directory, not a drive root.' }
Assert-NoReparsePoint $sourceItem.FullName
$sourcePath = $sourceItem.FullName.TrimEnd('\', '/')
$sourcePrefix = $sourcePath + [IO.Path]::DirectorySeparatorChar
$outputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([IO.Path]::GetExtension($outputFile) -ne '.vpk' -or
    $outputFile.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputPath must be a .vpk file outside SourceRoot.'
}
if (Test-Path -LiteralPath $outputFile -PathType Container) { throw 'OutputPath must be a file, not a directory.' }
if (-not $PackageOnly) {
    if ([string]::IsNullOrWhiteSpace($TargetDirectory) -or -not (Test-Path -LiteralPath $TargetDirectory -PathType Container)) {
        throw 'Deployment target directory does not exist. Use -PackageOnly to just build.'
    }
    Assert-NoReparsePoint $TargetDirectory
    $targetFile = Join-Path ((Get-Item -LiteralPath $TargetDirectory).FullName) 'pak01_dir.vpk'
    if ($targetFile -eq $outputFile) { throw 'Build output and deployment target must be different files.' }
    if (Test-Path -LiteralPath $targetFile) {
        if (Test-Path -LiteralPath $targetFile -PathType Container) { throw 'Deployment target is a directory, not a file.' }
        Assert-NoReparsePoint $targetFile
    }
    if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) { throw 'Please fully exit Dota 2 before deploying, or use -PackageOnly.' }
}

if ($All) {
    $entries = @(Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force |
        Where-Object { $_.Name -notlike '.vpkedit-*.rsp' } |
        ForEach-Object { $_.FullName.Substring($sourcePrefix.Length).Replace('\', '/') })
} else {
    # Our manifest supports comments/blank lines; the native response file does not.
    $entries = @(Get-Content -LiteralPath $Manifest -Encoding UTF8 |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}
if ($entries.Count -eq 0) { throw 'The package file list is empty.' }
# VPK paths are case-insensitive, but must not use culture-sensitive comparison:
# legacy mod filenames can contain characters that a culture-aware Hashtable treats as equivalent.
$expected = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$resolvedInputs = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$directEntries = [System.Collections.Generic.List[string]]::new()
$normalized = [System.Collections.Generic.List[string]]::new()
$totalBytes = 0L
foreach ($entry in $entries) {
    $relative = $entry.Replace('\', '/')
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '[:*?"<>|\[\]\x00-\x1f]' -or
        @($relative.Split('/') | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0 -or
        [IO.Path]::GetFileName($relative) -like '.vpkedit-*.rsp') {
        throw "Invalid manifest path (use explicit relative file paths): $entry"
    }
    if ($expected.ContainsKey($relative)) { throw "Duplicate manifest path: $entry" }
    $sourceFile = if ($FileMap.ContainsKey($relative)) { $FileMap[$relative] } else { Join-Path $sourcePath $relative }
    $inputFile = Get-Item -LiteralPath $sourceFile -Force
    if ($inputFile.PSIsContainer) { throw "Manifest entries must be files, not directories: $entry" }
    Assert-NoReparsePoint $inputFile.FullName
    if ($inputFile.FullName -eq $outputFile -or
        (-not $PackageOnly -and $inputFile.FullName -eq $targetFile)) {
        throw 'Input, build output and deployment files must be different files.'
    }
    $resolvedInputs[$relative] = $inputFile.FullName
    if ($inputFile.FullName -eq (Join-Path $sourcePath $relative)) { $directEntries.Add($relative) }
    $expected[$relative] = (Get-FileHash -Algorithm SHA256 -LiteralPath $inputFile.FullName).Hash
    $normalized.Add($relative)
    $totalBytes += $inputFile.Length
}
if ($totalBytes -ge (4GB - 1MB)) { throw 'Input is too large for a single-file VPK (<4 GiB required).' }

$outputDirectory = [IO.Path]::GetDirectoryName($outputFile)
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$buildId = [guid]::NewGuid().ToString('N')
$candidate = Join-Path $outputDirectory ('.vpkedit-' + $buildId + '.vpk')
$singleCandidate = Join-Path $outputDirectory ('.vpkedit-' + $buildId + '-single.vpk')
# Response entries are relative to the response file's directory.
# Only this tiny UTF-8/LF file lives in SourceRoot; no resources are copied.
$responsePath = Join-Path $sourcePath ('.vpkedit-' + $buildId + '.rsp')
$seedPath = $null
if ($directEntries.Count -eq 0) {
    # A mapped-only package uses one real input as a temporary seed; no payload copy.
    $seedInput = Get-Item -LiteralPath $resolvedInputs[$normalized[0]]
    $seedPath = $seedInput.Name
    $responsePath = Join-Path $seedInput.Directory.FullName ('.vpkedit-' + $buildId + '.rsp')
    $directEntries.Add($seedPath)
}
try {
    $responseEntries = [string[]]$directEntries
    [Array]::Sort($responseEntries, [StringComparer]::Ordinal)
    [IO.File]::WriteAllText($responsePath, ($responseEntries -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Packing $($normalized.Count) files from mapped source paths (VPK v1, single file; no resource staging)."
    Invoke-VpkEdit @('--no-progress', '--type', 'vpk', '--version', '1', '--single-file', '--output', $candidate, ('@' + $responsePath))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'VPKEdit did not create the output package.' }
    if ($null -ne $seedPath) {
        Invoke-VpkEdit @('--no-progress', '--single-file', '--remove-file', $seedPath, $candidate)
    }
    $mappedArguments = [System.Collections.Generic.List[string]]::new()
    $mappedArguments.Add('--no-progress')
    $mappedArguments.Add('--single-file')
    foreach ($relative in $normalized) {
        if ($null -eq $seedPath -and $directEntries.Contains($relative)) { continue }
        $mappedArguments.Add('--add-file')
        $mappedArguments.Add($resolvedInputs[$relative])
        $mappedArguments.Add($relative)
        # Keep below the Windows command-line length limit.
        if (($mappedArguments -join ' ').Length -gt 12000) {
            $mappedArguments.Add($candidate)
            Invoke-VpkEdit ([string[]]$mappedArguments)
            $mappedArguments.Clear()
            $mappedArguments.Add('--no-progress')
            $mappedArguments.Add('--single-file')
        }
    }
    if ($mappedArguments.Count -gt 2) {
        $mappedArguments.Add($candidate)
        Invoke-VpkEdit ([string[]]$mappedArguments)
    }
    if ($FileMap.Count -gt 0) {
        & $Python (Join-Path $PSScriptRoot 'flatten_vpk.py') $candidate $singleCandidate
        if ($LASTEXITCODE -ne 0) { throw 'Failed to fold mapped payloads into a single-file VPK.' }
        [IO.File]::Replace($singleCandidate, $candidate, [NullString]::Value)
    }
    Invoke-VpkEdit @('--no-progress', '--verify-checksums', 'files', $candidate)
    & (Join-Path $PSScriptRoot 'Test-VpkPackage.ps1') -Path $candidate -ExpectedFiles $expected
    # Publish only after validation, preserving any previous output on build failure.
    if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
        # Windows PowerShell 5.1 converts plain $null to an invalid empty path.
        [IO.File]::Replace($candidate, $outputFile, [NullString]::Value)
    } else {
        Move-Item -LiteralPath $candidate -Destination $outputFile -ErrorAction Stop
    }
} finally {
    # Scratch files only. Some hosts hook Remove-Item (e.g. safe-delete guards) and
    # throw a terminating error even when the file is gone; that must never abort a
    # build whose package was already created and verified.
    $shards = @(Get-ChildItem -LiteralPath $outputDirectory -File -Force |
        Where-Object { $_.Name -match ('^\.vpkedit-' + $buildId + '_\d+\.vpk$') } |
        ForEach-Object { $_.FullName })
    foreach ($scratch in @($responsePath, $candidate, $singleCandidate) + $shards) {
        if (-not (Test-Path -LiteralPath $scratch -PathType Leaf)) { continue }
        try { Remove-Item -LiteralPath $scratch -Force -ErrorAction Stop } catch { }
        if (Test-Path -LiteralPath $scratch -PathType Leaf) {
            Write-Warning "Could not remove scratch file: $scratch"
        }
    }
}

$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputFile).Hash
Write-Host "Package: $outputFile"
Write-Host "SHA256: $packageHash"
if ($PackageOnly) {
    Write-Host 'Package verified; not deployed (-PackageOnly).'
    return
}
if (Get-Process -Name dota2 -ErrorAction SilentlyContinue) { throw 'Package built, but Dota 2 is running. Deployment was skipped.' }
if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
    $backupDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\backups'
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    $backup = Join-Path $backupDirectory ('pak01-before-deploy-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $buildId + '.vpk')
    Copy-Item -LiteralPath $targetFile -Destination $backup -ErrorAction Stop
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $targetFile).Hash) {
        throw 'Backup verification failed; deployment was skipped.'
    }
    Write-Host "Previous deployment backup: $backup"
}
Copy-Item -LiteralPath $outputFile -Destination $targetFile -Force -ErrorAction Stop
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $targetFile).Hash -ne $packageHash) { throw 'Deployment hash mismatch.' }
Write-Host "Deployed and hash-verified: $targetFile"
Write-Host 'In-game verification is still required.'
