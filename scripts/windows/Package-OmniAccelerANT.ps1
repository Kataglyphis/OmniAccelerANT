#requires -Version 7.0
<#
.SYNOPSIS
    Packages the OmniAccelerANT runner as an MSI and a signed MSIX, for x64 or arm64.
.DESCRIPTION
    The runner folder is the app as it ships: omni_accelerant.exe with AccelerANTgine.dll, the VC++ runtime, the
    chain ONNX Runtime, the GStreamer subset and data\ beside it. The MSI installs it per machine under Program Files
    with a Start menu shortcut; the MSIX carries the identity pubspec.yaml's msix_config names and its msix_version.
    Without -MsixPfx a throwaway test certificate signs the MSIX, and its .cer lands beside it. Needs WiX 7 (in
    $env:WIX or on PATH) and the Windows SDK's makeappx and signtool; Test-OmniAccelerANTInstallers.ps1 checks both.
.PARAMETER AppDir
    The runner folder: x64's runner\<preset>, arm64's build\windows\arm64\runner\Release.
.PARAMETER Arch
    x64 or arm64, the architecture of the runner's binaries.
.PARAMETER OutDir
    Where omni-accelerant-<version>-windows-<arch>.msi, .msix and -testcert.cer land; default: out\.
    GPU candidates require -OrtProvider and are written under an unverified candidate directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
    [string]$OutDir = '',
    [string]$MsixPfx = '',
    [string]$MsixPublisher = 'CN=Kataglyphis',
    [ValidateSet('cpu', 'cuda', 'directml')][string]$OrtProvider = 'cpu'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsBuild.Common', 'WindowsMsix.Common', 'WindowsMsix.Signing', 'WindowsAppInstallers.Common',
    'WindowsMsiLicense.Common', 'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common', 'WindowsOrtLicense.Common',
    'WindowsOrtRunner.Common', 'WindowsGpuBuild.Common', 'WindowsThirdPartyLicense.Common')

$AppDir = (Resolve-Path -LiteralPath $AppDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $AppDir 'omni_accelerant.exe') -PathType Leaf)) { throw "no omni_accelerant.exe in $AppDir" }
& (Join-Path $PSScriptRoot 'Stage-DetectorModel.ps1') -WorkspaceDir $repoRoot -RunnerDir $AppDir -VerifyOnly
Assert-WindowsInstallerCandidate -RunnerDir $AppDir -Provider $OrtProvider -Arch $Arch
# A runner from before 9f4438e kept AccelerANTgine.dll there, where the loader never looks.
if (Test-Path -LiteralPath (Join-Path $AppDir 'bin') -PathType Container) { throw "$AppDir has a bin\ folder; rebuild it, no installer may ship that layout" }
$version = Get-PackageVersion -WorkspacePath $repoRoot -VersionFile 'pubspec.yaml' -Components 3 -Required
$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^\s+msix_version:\s*(\d+\.\d+\.\d+\.\d+)') { throw 'pubspec.yaml names no msix_config.msix_version' }
$msixVersion = $Matches[1]

if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'out' }
$null = New-Item -ItemType Directory -Force -Path $OutDir
$outRoot = (Resolve-Path -LiteralPath $OutDir).Path
$gpuDestination = ''
if ($OrtProvider -ne 'cpu') {
    try { Import-Module (Resolve-BuildModule -Name 'WindowsPackageBinary.Common') -Global -DisableNameChecking -ErrorAction Stop }
    catch { throw "A GPU package needs ANTfrastructure's finished-package binary verifier. $($_.Exception.Message)" }
    & (Join-Path $PSScriptRoot 'Test-WindowsGpuCandidate.ps1') -RunnerDir $AppDir -Provider $OrtProvider
    $vendor = if ($OrtProvider -eq 'cuda') { 'nvidia' } else { 'amd' }
    $gpuDestination = Join-Path $outRoot "unverified-omni-windows-x64-$vendor-installers"
    if (Test-Path -LiteralPath $gpuDestination) { throw "Refusing to overwrite $gpuDestination" }
    $outRoot = Join-Path $outRoot ".pending-omni-$vendor-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $outRoot
}
$base = Join-Path $outRoot "omni-accelerant-$version-windows-$Arch"
$work = Join-Path ([IO.Path]::GetTempPath()) "omni-accelerant-installers-$Arch"
if ($OrtProvider -ne 'cpu') { $work = "$work-$OrtProvider-$([guid]::NewGuid().ToString('N'))" }
$null = New-Item -ItemType Directory -Force -Path $work
$context = New-BuildContext -Workspace $repoRoot -LogDir (Join-Path $OutDir 'logs')
$installer = Join-Path $PSScriptRoot 'installer'
# The host has no wheel store: the build matched the texts in the image and stamped them with the DLL.
$ortLicenses = Resolve-RunnerOrtLicense -RunnerDir $AppDir
$gpuFiles = @()
if ($OrtProvider -ne 'cpu') {
    $gpuFiles = @('omni_accelerant.exe', 'oxidant.dll', 'AccelerANTgine.dll', 'kataglyphis_native_inference_plugin.dll', 'onnxruntime.dll', 'onnxruntime_providers_shared.dll', 'ort-chain-stamp.json')
    $gpuFiles += @('resources/models/deim_dfine_n_coco.onnx', 'resources/models/deim_dfine_n_coco.LICENSE', 'resources/models/deim_dfine_n_coco.NOTICE')
    if ($OrtProvider -eq 'cuda') { $gpuFiles += 'onnxruntime_providers_cuda.dll' }
    if (Test-Path -LiteralPath (Join-Path $AppDir 'DirectML.dll') -PathType Leaf) { $gpuFiles += 'DirectML.dll' }
    $base = "$base-$vendor"
}
$fragment = Join-Path $work 'msi-payload-files.wxs'
Assert-NativeLicenseCoverage -Path $AppDir -RepoRoot $repoRoot
$licenseAssets = Get-ThirdPartyLicenseAsset -RepoRoot $repoRoot

New-AppMsi -Context $context -AppDir $AppDir -ExeName 'omni_accelerant.exe' -WxsFile (Join-Path $installer 'omni-accelerant.wxs') `
    -LicenseFile (Join-Path $installer 'License.rtf') -ProductName 'OmniAccelerANT' -Version $version -Arch $Arch `
    -OutFile "$base.msi" -FragmentPath $fragment
Assert-MsiPackageLicense -Path "$base.msi" -FileName 'NOTICES.Z' -LicensePath (Join-Path $repoRoot 'LICENSE')
Assert-ThirdPartyLicensePackage -Path "$base.msi" -RepoRoot $repoRoot -Asset $licenseAssets
Assert-OrtWheelLicensesInPackage -Path "$base.msi" -LicenseDirectory $ortLicenses -Format msi -WixPath $fragment
if ($gpuFiles.Count -gt 0) {
    $gpuPaths = @($gpuFiles | ForEach-Object { Join-Path $AppDir $_ })
    $gpuMsiIds = @('exe0') + @($gpuPaths | Select-Object -Skip 1 | ForEach-Object { Get-WixSourceFileId -WixPath $fragment -SourcePath $_ })
    $gpuProviders = @($gpuFiles | Where-Object { $_ -clike 'onnxruntime_providers_*.dll' } | Sort-Object)
    Assert-PackageBinary -Path "$base.msi" -Member $gpuMsiIds -SourcePath $gpuPaths
    & (Join-Path $PSScriptRoot 'Stage-DetectorModel.ps1') -WorkspaceDir $repoRoot -RunnerDir $AppDir -VerifyOnly
    $msiProviders = @(Get-PackageOrtProviderNames -Path "$base.msi" -Directory '' -RootDirectoryId APPLICATIONFOLDER -RootDirectoryName OmniAccelerANT)
    if (($gpuProviders -join ',') -cne ($msiProviders -join ',')) { throw 'MSI ORT provider set differs from the proven runner.' }
    Assert-WindowsInstallerCandidate -RunnerDir $AppDir -Provider $OrtProvider -Arch $Arch
}
New-AppMsix -Context $context -AppDir $AppDir -ManifestTemplate (Join-Path $installer 'AppxManifest.xml') `
    -LogoPath (Join-Path $repoRoot 'web\icons\Icon-512.png') -Version $msixVersion -Arch $Arch -OutFile "$base.msix" `
    -WorkDir $work -Publisher $MsixPublisher -Pfx $MsixPfx
Assert-PackageLicense -Path "$base.msix" -Pattern '*flutter_assets/NOTICES.Z' -LicensePath (Join-Path $repoRoot 'LICENSE')
Assert-ThirdPartyLicensePackage -Path "$base.msix" -RepoRoot $repoRoot -Asset $licenseAssets
Assert-OrtWheelLicensesInPackage -Path "$base.msix" -LicenseDirectory $ortLicenses -Format archive
if ($gpuFiles.Count -gt 0) {
    Assert-PackageBinary -Path "$base.msix" -Member $gpuFiles -SourcePath $gpuPaths
    & (Join-Path $PSScriptRoot 'Stage-DetectorModel.ps1') -WorkspaceDir $repoRoot -RunnerDir $AppDir -VerifyOnly
    $msixProviders = @(Get-PackageOrtProviderNames -Path "$base.msix" -Directory '')
    if (($gpuProviders -join ',') -cne ($msixProviders -join ',')) { throw 'MSIX ORT provider set differs from the proven runner.' }
    Assert-WindowsInstallerCandidate -RunnerDir $AppDir -Provider $OrtProvider -Arch $Arch
    Move-Item -LiteralPath $outRoot -Destination $gpuDestination
    Write-Host "Unverified GPU installer candidate: $gpuDestination"
}
