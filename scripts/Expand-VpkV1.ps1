param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$source = (Get-Item -LiteralPath $Path -Force).FullName
$destinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
if (Test-Path -LiteralPath $destinationPath) { throw 'VPK extraction destination already exists.' }
New-Item -ItemType Directory -Path $destinationPath | Out-Null
$destinationPrefix = $destinationPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar

$utf8Strict = [Text.UTF8Encoding]::new($false, $true)
try {
    $legacyEncoding = [Text.Encoding]::GetEncoding(54936, [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback)
} catch {
    throw 'GB18030 filename decoding is unavailable in this PowerShell runtime.'
}

function Read-VpkTreeString([IO.BinaryReader]$Reader, [long]$TreeEnd) {
    $bytes = [System.Collections.Generic.List[byte]]::new()
    while ($Reader.BaseStream.Position -lt $TreeEnd) {
        $value = $Reader.ReadByte()
        if ($value -eq 0) {
            try { return $utf8Strict.GetString($bytes.ToArray()) }
            catch [Text.DecoderFallbackException] { return $legacyEncoding.GetString($bytes.ToArray()) }
        }
        $bytes.Add($value)
    }
    throw 'Unterminated VPK tree string.'
}

function Assert-SafeRelativePath([string]$RelativePath) {
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '[:*?"<>|\x00-\x1f]' -or
        @($RelativePath.Split('/') | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        throw "Unsafe path in VPK: $RelativePath"
    }
}

$stream = [IO.File]::OpenRead($source)
$reader = [IO.BinaryReader]::new($stream)
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$fileCount = 0
$totalBytes = 0L
try {
    if ($stream.Length -lt 12 -or $reader.ReadUInt32() -ne 0x55AA1234 -or $reader.ReadUInt32() -ne 1) {
        throw 'Expected a VPK version 1 package.'
    }
    $treeEnd = 12L + $reader.ReadUInt32()
    if ($treeEnd -gt $stream.Length) { throw 'VPK tree exceeds package size.' }

    while (($extension = Read-VpkTreeString $reader $treeEnd) -ne '') {
        while (($directory = Read-VpkTreeString $reader $treeEnd) -ne '') {
            while (($name = Read-VpkTreeString $reader $treeEnd) -ne '') {
                if ($stream.Position + 18 -gt $treeEnd) { throw 'Truncated VPK entry.' }
                $null = $reader.ReadUInt32() # Source CRCs are verified by VPKEdit before this script runs.
                $preloadSize = $reader.ReadUInt16()
                $archive = $reader.ReadUInt16()
                $offset = $reader.ReadUInt32()
                $length = $reader.ReadUInt32()
                if ($reader.ReadUInt16() -ne 0xFFFF) { throw 'Invalid VPK entry terminator.' }
                if ($archive -ne 0x7FFF) { throw 'The source uses external VPK chunks; only a single-file package is supported.' }
                if ($stream.Position + $preloadSize -gt $treeEnd -or
                    $treeEnd + [long]$offset + [long]$length -gt $stream.Length) {
                    throw 'VPK entry exceeds package bounds.'
                }

                $entryPath = $name
                if ($extension -ne ' ') { $entryPath += '.' + $extension }
                if ($directory -ne ' ') { $entryPath = $directory + '/' + $entryPath }
                Assert-SafeRelativePath $entryPath
                if (-not $seen.Add($entryPath)) { throw "Duplicate VPK entry: $entryPath" }
                $target = [IO.Path]::GetFullPath((Join-Path $destinationPath $entryPath))
                if (-not $target.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "VPK path escapes the extraction directory: $entryPath"
                }

                $preload = $reader.ReadBytes($preloadSize)
                if ($preload.Length -ne $preloadSize) { throw "Truncated preload data: $entryPath" }
                $nextEntry = $stream.Position
                $parent = [IO.Path]::GetDirectoryName($target)
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
                $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    if ($preload.Length -gt 0) { $output.Write($preload, 0, $preload.Length) }
                    $stream.Position = $treeEnd + [long]$offset
                    $remaining = [long]$length
                    $buffer = New-Object byte[] 65536
                    while ($remaining -gt 0) {
                        $count = $stream.Read($buffer, 0, [int][Math]::Min($remaining, $buffer.Length))
                        if ($count -eq 0) { throw "Truncated VPK data: $entryPath" }
                        $output.Write($buffer, 0, $count)
                        $remaining -= $count
                    }
                } finally {
                    $output.Dispose()
                    $stream.Position = $nextEntry
                }
                $fileCount++
                $totalBytes += [long]$preloadSize + [long]$length
            }
        }
    }
    if ($stream.Position -ne $treeEnd) { throw 'Unexpected VPK tree ending.' }
} catch {
    # The caller owns cleanup of the unique extraction directory.
    throw
} finally {
    $reader.Dispose()
    $stream.Dispose()
}

[pscustomobject]@{ FileCount = $fileCount; TotalBytes = $totalBytes; Destination = $destinationPath }
