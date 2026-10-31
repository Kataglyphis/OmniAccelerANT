#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('cuda', 'directml')][string] $Provider,
    [Parameter(Mandatory)][string] $RunnerDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runner = (Resolve-Path -LiteralPath $RunnerDir).Path
& (Join-Path $PSScriptRoot 'Stage-DetectorModel.ps1') -WorkspaceDir $workspace -RunnerDir $runner -VerifyOnly
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsTargetArch.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common',
    'WindowsMsiLicense.Common', 'WindowsOrtRunner.Common', 'WindowsGpuBuild.Common', 'WindowsThirdPartyLicense.Common')
Assert-WindowsGpuDelivery -SourceDir $runner -DestinationDir $runner -Provider $Provider
$null = Assert-DirectoryTargetArch -Path $runner -Arch 'amd64' -MinCount 50 -Context 'Windows GPU candidate'
Assert-NativeLicenseCoverage -Path $runner -RepoRoot $workspace
Assert-PackageLicense -Path $runner -Pattern '*flutter_assets/NOTICES.Z' -LicensePath (Join-Path $workspace 'LICENSE')
foreach ($asset in @(Get-ThirdPartyLicenseAsset -RepoRoot $workspace)) {
    $source = Join-Path $workspace $asset
    $delivered = Join-Path (Join-Path $runner 'data\flutter_assets') $asset
    if (-not (Test-Path -LiteralPath $delivered -PathType Leaf) -or
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $delivered -Algorithm SHA256).Hash) {
        throw "GPU runner has missing or changed license inventory: $asset"
    }
}
Write-Host "Windows $Provider runner passed architecture, license and stamped ORT checks."
