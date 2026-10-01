#requires -Version 7.0
<#
.SYNOPSIS
    Starts the app from its tree and requires it alive after -Seconds; a missing DLL ends it at once (0xC0000135).
.DESCRIPTION
    Shared by windows-x64.yml and windows-arm64.yml, on the device itself, never in the build container.
.PARAMETER AppDir
    The runner folder that holds the exe.
.PARAMETER SearchPath
    Folders the app finds on PATH, as Start-Windows.ps1 prepends them (x64: runner\bin, which holds AccelerANTgine.dll).
.PARAMETER OrtStamp
    Re-prove the stamped chain ONNX Runtime with G6 first, as Start-Windows.ps1 does before every launch.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [string]$ExeName = 'omni_accelerant.exe',
    [string[]]$SearchPath = @(),
    [ValidateRange(1, 600)][int]$Seconds = 20,
    [switch]$OrtStamp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dir = (Resolve-Path -LiteralPath $AppDir).Path
$exe = Join-Path $dir $ExeName
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "No $ExeName in $dir." }

if ($OrtStamp) {
    . (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common', 'WindowsOrtRunner.Common')
    Assert-RunnerOrtStamp -RunnerDir $dir
    "G6: $dir holds exactly its stamped chain ONNX Runtime"
}

if ($SearchPath.Count) {
    $env:PATH = (@($SearchPath | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }) + $env:PATH) -join [IO.Path]::PathSeparator
}
$process = Start-Process -FilePath $exe -WorkingDirectory $dir -PassThru
try {
    Start-Sleep -Seconds $Seconds
    $process.Refresh()
    if ($process.HasExited) { throw ('{0} exited within {1} s with 0x{2:X8}' -f $ExeName, $Seconds, $process.ExitCode) }
    'alive after {0} s, working set {1:N0} MB' -f $Seconds, ($process.WorkingSet64 / 1MB)
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}
