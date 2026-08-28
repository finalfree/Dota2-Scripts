param([string]$VpkEditCli = 'vpkeditcli')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$builder = Join-Path $repo 'scripts\Build-Vpk.ps1'
$verifier = Join-Path $repo 'scripts\Test-VpkPackage.ps1'
$testRoot = Join-Path $repo ('bin\packaging-test-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $testRoot 'source with spaces'
$output = Join-Path $testRoot 'output with spaces\test.vpk'
$manifest = Join-Path $testRoot 'files.txt'
$utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path (Join-Path $source 'scripts'), (Join-Path $source 'resource') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $source 'scripts\first.txt'), 'first', $utf8)
# Non-ASCII payload without relying on PowerShell 5.1 script encoding detection.
[IO.File]::WriteAllText((Join-Path $source 'resource\second file.txt'), ([string][char]0x73B2 + [char]0x73D1), $utf8)
[IO.File]::WriteAllText((Join-Path $source 'excluded.txt'), 'not in selective package', $utf8)
$options = @{ SourceRoot = $source; Manifest = $manifest; OutputPath = $output; PackageOnly = $true; VpkEditCli = $VpkEditCli }
$script:passed = 0

function Assert-True([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}
function Expect-Failure([string]$Name, [scriptblock]$Action, [string]$MessagePattern) {
    $caught = $null
    try { & $Action } catch { $caught = $_ }
    Assert-True ($null -ne $caught) "Expected failure: $Name"
    Assert-True ($caught.Exception.Message -match $MessagePattern) "Unexpected error for ${Name}: $caught"
    Assert-True ((Get-FileHash -LiteralPath $output).Hash -eq $script:goodHash) "Previous output changed: $Name"
    Assert-True (@(Get-ChildItem -LiteralPath $source -Filter '.vpkedit-*.rsp' -Force).Count -eq 0) "Leaked response file: $Name"
    $script:passed++
    Write-Host "PASS: $Name"
}

$validManifest = "# comments and blank lines are filtered`r`n`r`nscripts/first.txt`r`nresource/second file.txt`r`n"
[IO.File]::WriteAllText($manifest, $validManifest, $utf8)
# The response file location, not CWD, must control source paths.
Push-Location $testRoot
try {
    $relativeOptions = $options.Clone()
    $relativeOptions.OutputPath = 'output with spaces\test.vpk'
    & $builder @relativeOptions
} finally { Pop-Location }
$expected = @{}
foreach ($relative in @('scripts/first.txt', 'resource/second file.txt')) {
    $expected[$relative] = (Get-FileHash -LiteralPath (Join-Path $source $relative)).Hash
}
& $verifier -Path $output -ExpectedFiles $expected
$script:goodHash = (Get-FileHash -LiteralPath $output).Hash
$script:passed++
Write-Host 'PASS: exact selective file set, spaces, UTF-8 payload, comments, CRLF, different CWD'

# Rebuilding exercises replacement of an existing verified output.
& $builder @options
Assert-True ((Get-FileHash -LiteralPath $output).Hash -eq $script:goodHash) 'Repeat build changed content.'
$script:passed++

$invalid = @(
    @{ Name = 'missing file'; Text = 'scripts/missing.txt'; Pattern = 'missing\.txt' },
    @{ Name = 'duplicate'; Text = "scripts/first.txt`nSCRIPTS/FIRST.TXT"; Pattern = 'Duplicate manifest' },
    @{ Name = 'traversal'; Text = '../files.txt'; Pattern = 'Invalid manifest path' },
    @{ Name = 'absolute path'; Text = (Join-Path $source 'excluded.txt'); Pattern = 'Invalid manifest path' },
    @{ Name = 'directory'; Text = 'scripts'; Pattern = 'must be files' },
    @{ Name = 'wildcard'; Text = 'scripts/*.txt'; Pattern = 'Invalid manifest path' },
    @{ Name = 'empty'; Text = "# no files`n`n"; Pattern = 'file list is empty' }
)
foreach ($case in $invalid) {
    [IO.File]::WriteAllText($manifest, $case.Text, $utf8)
    Expect-Failure $case.Name { & $builder @options } $case.Pattern
}
[IO.File]::WriteAllText($manifest, $validManifest, $utf8)
$badOutput = $options.Clone()
$badOutput.OutputPath = Join-Path $source 'bad.vpk'
Expect-Failure 'output inside source' { & $builder @badOutput } 'outside SourceRoot'
$sameTarget = $options.Clone()
$sameTarget.PackageOnly = $false
$sameTarget.TargetDirectory = Split-Path $output -Parent
$sameTarget.OutputPath = Join-Path $sameTarget.TargetDirectory 'pak01_dir.vpk'
Expect-Failure 'output equals deployment' { & $builder @sameTarget } 'must be different files'
Assert-True (-not (Test-Path -LiteralPath $sameTarget.OutputPath)) 'Unsafe target was written before rejection.'

# Independent verifier must reject a changed payload, without touching good output.
$corrupt = Join-Path $testRoot 'corrupt.vpk'
$bytes = [IO.File]::ReadAllBytes($output)
$bytes[$bytes.Length - 1] = $bytes[$bytes.Length - 1] -bxor 1
[IO.File]::WriteAllBytes($corrupt, $bytes)
Expect-Failure 'corrupt payload' { & $verifier -Path $corrupt -ExpectedFiles $expected } 'payload mismatch'
$bytes[4] = 2
[IO.File]::WriteAllBytes($corrupt, $bytes)
Expect-Failure 'V2 rejected' { & $verifier -Path $corrupt -ExpectedFiles $expected } 'version 1'

$allOutput = Join-Path $testRoot 'all.vpk'
& $builder -SourceRoot $source -All -OutputPath $allOutput -PackageOnly -VpkEditCli $VpkEditCli
$expected['excluded.txt'] = (Get-FileHash -LiteralPath (Join-Path $source 'excluded.txt')).Hash
& $verifier -Path $allOutput -ExpectedFiles $expected
Assert-True (@(Get-ChildItem -LiteralPath $source -Filter '.vpkedit-*.rsp' -Force).Count -eq 0) 'Leaked final response file.'
$script:passed++
Write-Host "PASS: $script:passed checks; artifacts retained in $testRoot. No game deployment."
