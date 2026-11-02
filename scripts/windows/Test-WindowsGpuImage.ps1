#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('cuda', 'directml')][string] $Provider)

. (Join-Path $PSScriptRoot 'Initialize-EntryScript.ps1')
$workspace = Get-EntryRepoRoot
Import-BuildModule @('WindowsTargetArch.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common',
    'WindowsOrtLicense.Common', 'WindowsGpuBuild.Common')
Assert-WindowsGpuImage -Provider $Provider -Workspace $workspace -OxidantDir (Join-Path $workspace 'third_party\OxidANT') `
    -OnnxRoot "$env:ONNX_ROOT" -WheelDir (Get-OrtChainWheelStore)
Write-Host "Windows $Provider image inputs match their ORT wheel."
