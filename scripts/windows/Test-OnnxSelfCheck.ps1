#requires -Version 7.0
<#
.SYNOPSIS
    Run the packaged model through ONNX Runtime CPU without a camera.
.DESCRIPTION
    A zero exit proves the self-check completed, not that a GPU executed operators.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dir = (Resolve-Path -LiteralPath $AppDir).Path
$exe = Join-Path $dir 'omni_accelerant.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "No omni_accelerant.exe in $dir." }
$model = Join-Path $dir 'resources\models\deim_dfine_n_coco.onnx'
if (-not (Test-Path -LiteralPath $model -PathType Leaf)) { throw "No bundled ONNX model in $dir." }
$ort = Join-Path $dir 'onnxruntime.dll'
if (-not (Test-Path -LiteralPath $ort -PathType Leaf)) { throw "No bundled ONNX Runtime in $dir." }

$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = $exe
$start.WorkingDirectory = $dir
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.ArgumentList.Add('--onnx-check')
$start.Environment['KATAGLYPHIS_ORT_DEVICE'] = 'cpu'
$start.Environment['KATAGLYPHIS_ONNX_BACKEND'] = 'ort'
$null = $start.Environment.Remove('KATAGLYPHIS_ONNX_MODEL')
$start.Environment['ORT_DYLIB_PATH'] = $ort
$null = $start.Environment.Remove('ONNX_ROOT')
$windows = [Environment]::GetEnvironmentVariable('SystemRoot')
if (-not $windows) { throw 'SystemRoot is required to isolate the self-check PATH.' }
$start.Environment['PATH'] = @((Join-Path $windows 'System32'), $windows) -join [IO.Path]::PathSeparator
$process = [Diagnostics.Process]::Start($start)
try {
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw "ONNX self-check did not finish within $TimeoutSeconds seconds."
    }
    if ($process.ExitCode -ne 0) { throw "ONNX self-check failed with exit code $($process.ExitCode)." }
    Write-Host 'ONNX model inference passed on the CPU; GPU placement was not checked.'
} finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}
