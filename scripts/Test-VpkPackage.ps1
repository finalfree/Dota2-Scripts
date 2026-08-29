param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$ExpectedFiles
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Independently check the V1 tree and payloads against pre-build SHA256s.
function Read-VpkString($Reader, [long]$TreeEnd) {
    $bytes = [System.Collections.Generic.List[byte]]::new()
    while ($Reader.BaseStream.Position -lt $TreeEnd) {
        $value = $Reader.ReadByte()
        if ($value -eq 0) { return [Text.Encoding]::UTF8.GetString($bytes.ToArray()) }
        $bytes.Add($value)
    }
    throw 'Unterminated VPK tree string.'
}

$stream = [IO.File]::OpenRead($Path)
$reader = [IO.BinaryReader]::new($stream)
try {
    if ($stream.Length -lt 12 -or $stream.Length -ge 4GB) { throw 'Invalid VPK size.' }
    if ($reader.ReadUInt32() -ne 0x55AA1234 -or $reader.ReadUInt32() -ne 1) {
        throw 'Expected a VPK version 1 package.'
    }
    $treeEnd = 12L + $reader.ReadUInt32()
    if ($treeEnd -gt $stream.Length) { throw 'VPK tree exceeds package size.' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while (($extension = Read-VpkString $reader $treeEnd) -ne '') {
        while (($directory = Read-VpkString $reader $treeEnd) -ne '') {
            while (($name = Read-VpkString $reader $treeEnd) -ne '') {
                if ($stream.Position + 18 -gt $treeEnd) { throw 'Truncated VPK entry.' }
                $null = $reader.ReadUInt32() # CRC is checked separately by VPKEdit.
                $preloadSize = $reader.ReadUInt16()
                $archive = $reader.ReadUInt16()
                $offset = $reader.ReadUInt32()
                $length = $reader.ReadUInt32()
                if ($reader.ReadUInt16() -ne 0xFFFF) { throw 'Invalid VPK entry terminator.' }
                if ($archive -ne 0x7FFF) { throw 'Unexpected external VPK chunk.' }
                if ($stream.Position + $preloadSize -gt $treeEnd -or
                    $treeEnd + [long]$offset + [long]$length -gt $stream.Length) {
                    throw 'VPK entry exceeds package bounds.'
                }
                $entryPath = $name
                if ($extension -ne ' ') { $entryPath += '.' + $extension }
                if ($directory -ne ' ') { $entryPath = $directory + '/' + $entryPath }
                if (-not $seen.Add($entryPath)) { throw "Duplicate VPK entry: $entryPath" }
                if (-not $ExpectedFiles.ContainsKey($entryPath)) { throw "Unexpected VPK entry: $entryPath" }

                $preload = $reader.ReadBytes($preloadSize)
                $nextEntry = $stream.Position
                $hasher = [Security.Cryptography.SHA256]::Create()
                try {
                    if ($preloadSize -gt 0) {
                        $null = $hasher.TransformBlock($preload, 0, $preload.Length, $preload, 0)
                    }
                    $stream.Position = $treeEnd + [long]$offset
                    $remaining = [long]$length
                    $buffer = New-Object byte[] 65536
                    while ($remaining -gt 0) {
                        $count = $stream.Read($buffer, 0, [int][Math]::Min($remaining, $buffer.Length))
                        if ($count -eq 0) { throw "Truncated VPK data: $entryPath" }
                        $null = $hasher.TransformBlock($buffer, 0, $count, $buffer, 0)
                        $remaining -= $count
                    }
                    $null = $hasher.TransformFinalBlock([byte[]]@(), 0, 0)
                    $hash = [BitConverter]::ToString($hasher.Hash).Replace('-', '')
                    if ($hash -ne $ExpectedFiles[$entryPath]) { throw "VPK payload mismatch: $entryPath" }
                } finally {
                    $hasher.Dispose()
                    $stream.Position = $nextEntry
                }
            }
        }
    }
    if ($stream.Position -ne $treeEnd -or $seen.Count -ne $ExpectedFiles.Count) {
        throw 'VPK tree or file count does not match the manifest.'
    }
    Write-Host "Verified VPK v1: $($seen.Count) files; all payload SHA256s match."
} finally {
    $reader.Dispose()
    $stream.Dispose()
}
