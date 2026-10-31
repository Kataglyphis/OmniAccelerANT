#requires -Version 7.0
<#
.SYNOPSIS
    Stage or verify the locked detector model and its notices beside a Windows runner.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunnerDir,
    [string]$WorkspaceDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path -LiteralPath $WorkspaceDir).Path
$runner = (Resolve-Path -LiteralPath $RunnerDir).Path
$fetcher = Join-Path $workspace 'third_party\ANTfrastructure\linux\scripts\lib\fetch-data-lock.py'
$lock = Join-Path $workspace 'third_party\OxidANT\resources\models\models.lock'
$models = Join-Path $runner 'resources\models'
$verifier = Join-Path $PSScriptRoot 'verify_detector_model.py'
foreach ($file in $fetcher, $lock, $verifier) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing model staging input: $file" }
}
if (-not $VerifyOnly) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $staged = [IO.Path]::GetFullPath((Join-Path $tempRoot "omni-detector-$([guid]::NewGuid().ToString('N'))"))
    if (-not $staged.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid model staging path.' }
    try {
        & python -I $fetcher --lock $lock --dest $staged
        if ($LASTEXITCODE -ne 0) { throw "Locked model fetch failed (exit $LASTEXITCODE)." }
        & python -I $verifier $fetcher $lock $staged
        if ($LASTEXITCODE -ne 0) { throw "Staged model verification failed (exit $LASTEXITCODE)." }
        New-Item -ItemType Directory -Force -Path $models | Out-Null
        Get-ChildItem -LiteralPath $staged -File | Copy-Item -Destination $models -Force
    } finally {
        if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Recurse -Force }
    }
}
& python -I $verifier $fetcher $lock $models
if ($LASTEXITCODE -ne 0) { throw "Bundled model verification failed (exit $LASTEXITCODE)." }
