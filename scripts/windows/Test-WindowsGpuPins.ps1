#requires -Version 7.0
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'Initialize-EntryScript.ps1')
$workspace = Get-EntryRepoRoot
Import-BuildModule @('WindowsOrtPayload.Common', 'WindowsOrtLicense.Common', 'WindowsMsiLicense.Common', 'WindowsPackageBinary.Common', 'WindowsGpuBuild.Common')
foreach ($command in 'Assert-PackageBinary', 'Get-PackageOrtProviderNames', 'Get-WixSourceFileId') { $null = Get-Command $command -ErrorAction Stop }
foreach ($provider in 'cuda', 'directml') {
    Assert-WindowsGpuDependencies -Provider $provider -Workspace $workspace -OxidantDir (Join-Path $workspace 'third_party\OxidANT')
}
Write-Host 'Recorded dependencies support the Windows x64 GPU candidates.'
