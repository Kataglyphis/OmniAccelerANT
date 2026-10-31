#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsOrtPayload.Common', 'WindowsOrtLicense.Common', 'WindowsMsiLicense.Common', 'WindowsPackageBinary.Common', 'WindowsGpuBuild.Common')
foreach ($command in 'Assert-PackageBinary', 'Get-PackageOrtProviderNames', 'Get-WixSourceFileId') { $null = Get-Command $command -ErrorAction Stop }
foreach ($provider in 'cuda', 'directml') {
    Assert-WindowsGpuDependencies -Provider $provider -Workspace $workspace -OxidantDir (Join-Path $workspace 'third_party\OxidANT')
}
Write-Host 'Recorded dependencies support the Windows x64 GPU candidates.'
