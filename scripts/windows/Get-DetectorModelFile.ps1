#requires -Version 7.0
<#
.SYNOPSIS
    The default detector's file names from OxidANT's models.lock: its ONNX model, LICENSE and NOTICE, in that order.
#>
[CmdletBinding()]
param(
    [string]$Lock = (Join-Path $PSScriptRoot '..\..\third_party\OxidANT\resources\models\models.lock')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# A CMD or Windows-container caller has no Bash, and a test job may lack the pinned Python the verifier needs.
if (-not (Test-Path -LiteralPath $Lock -PathType Leaf)) { throw "Missing model lock: $Lock" }
$names = @(Get-Content -LiteralPath $Lock | Where-Object { $_ -notmatch '^\s*(#|$)' } | ForEach-Object { (-split $_)[1] })
$model = @($names | Where-Object { $_ -like '*.onnx' }) | Select-Object -First 1
if (-not $model) { throw "Model lock names no .onnx model: $Lock" }
$stem = [IO.Path]::GetFileNameWithoutExtension($model)
foreach ($notice in "$stem.LICENSE", "$stem.NOTICE") {
    if ($names -cnotcontains $notice) { throw "Model lock is missing $notice`: $Lock" }
}
return @($model, "$stem.LICENSE", "$stem.NOTICE")
