#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('cuda', 'directml')][string] $Provider)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsTargetArch.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common',
    'WindowsOrtLicense.Common', 'WindowsGpuBuild.Common')
Assert-WindowsGpuImage -Provider $Provider -Workspace $workspace -OxidantDir (Join-Path $workspace 'third_party\OxidANT') `
    -OnnxRoot "$env:ONNX_ROOT" -WheelDir (Get-OrtChainWheelStore)
Write-Host "Windows $Provider image inputs match their ORT wheel."
