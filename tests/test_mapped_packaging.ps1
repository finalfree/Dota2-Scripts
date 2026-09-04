param([string]$VpkEditCli='vpkeditcli')
$ErrorActionPreference='Stop'
$repo = Split-Path $PSScriptRoot -Parent
$root = Join-Path $repo ('bin/mapped-test-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$external = Join-Path $root 'other inputs'
New-Item -ItemType Directory -Path $source, $external -Force | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $source 'seed.txt'), 'seed', $utf8)
[IO.File]::WriteAllText((Join-Path $external 'material.vmt'), ('long material ' * 300), $utf8)
$manifest = Join-Path $root 'files.txt'
$output = Join-Path $root 'out.vpk'
$builder = Join-Path $repo 'scripts/Build-Vpk.ps1'
$verifier = Join-Path $repo 'scripts/Test-VpkPackage.ps1'
$map = @{ 'materials/with space.vmt' = Join-Path $external 'material.vmt' }
$expected = @{ 'materials/with space.vmt' = (Get-FileHash -LiteralPath $map['materials/with space.vmt']).Hash }
$options = @{SourceRoot=$source; Manifest=$manifest; OutputPath=$output; FileMap=$map; PackageOnly=$true; VpkEditCli=$VpkEditCli}
[IO.File]::WriteAllText($manifest, "seed.txt`nmaterials/with space.vmt`n", $utf8)
$expected['seed.txt'] = (Get-FileHash -LiteralPath (Join-Path $source 'seed.txt')).Hash
& $builder @options
& $verifier -Path $output -ExpectedFiles $expected
$hash = (Get-FileHash $output).Hash
& $builder @options
if ((Get-FileHash $output).Hash -ne $hash) { throw 'Mapped build is not deterministic' }
Write-Host 'PASS: mixed roots, spaces, exact bytes and deterministic rebuild'

# No entry exists under SourceRoot; seed must not remain as an extra archive entry.
[IO.File]::WriteAllText($manifest, "materials/with space.vmt`n", $utf8)
$expected.Remove('seed.txt')
& $builder @options
& $verifier -Path $output -ExpectedFiles $expected
Write-Host 'PASS: mapped-only package, preloaded seed and temporary seed removal'

$hash = (Get-FileHash $output).Hash
$map['materials/with space.vmt'] = Join-Path $external 'missing.txt'
$failed = $false
try { & $builder @options } catch { $failed = $true }
if (-not $failed -or (Get-FileHash $output).Hash -ne $hash) { throw 'Missing mapped input damaged output' }
$map['materials/with space.vmt'] = $output
$failed = $false
try { & $builder @options } catch { $failed = $true }
if (-not $failed -or (Get-FileHash $output).Hash -ne $hash) { throw 'Self-overwrite was not rejected' }
if (@(Get-ChildItem $root -Recurse -File -Force | Where-Object Name -like '.vpkedit-*').Count) {
    throw 'Leaked temporary VPK/response/shard file'
}
Write-Host 'PASS: missing mapped input, self-overwrite rejection, scratch cleanup; no deployment'
