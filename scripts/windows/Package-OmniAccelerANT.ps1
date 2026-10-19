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
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppDir,
    [Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch,
    [string]$OutDir = '',
    [string]$MsixPfx = '',
    [string]$MsixPublisher = 'CN=Kataglyphis'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsBuild.Common', 'WindowsMsix.Common', 'WindowsMsix.Signing', 'WindowsAppInstallers.Common')

$AppDir = (Resolve-Path -LiteralPath $AppDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $AppDir 'omni_accelerant.exe') -PathType Leaf)) { throw "no omni_accelerant.exe in $AppDir" }
# A runner from before 9f4438e kept AccelerANTgine.dll there, where the loader never looks.
if (Test-Path -LiteralPath (Join-Path $AppDir 'bin') -PathType Container) { throw "$AppDir has a bin\ folder; rebuild it, no installer may ship that layout" }
$version = Get-PackageVersion -WorkspacePath $repoRoot -VersionFile 'pubspec.yaml' -Components 3 -Required
$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^\s+msix_version:\s*(\d+\.\d+\.\d+\.\d+)') { throw 'pubspec.yaml names no msix_config.msix_version' }
$msixVersion = $Matches[1]

if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'out' }
$null = New-Item -ItemType Directory -Force -Path $OutDir
$base = Join-Path (Resolve-Path -LiteralPath $OutDir).Path "omni-accelerant-$version-windows-$Arch"
$work = Join-Path ([IO.Path]::GetTempPath()) "omni-accelerant-installers-$Arch"
$null = New-Item -ItemType Directory -Force -Path $work
$context = New-BuildContext -Workspace $repoRoot -LogDir (Join-Path $OutDir 'logs')
$installer = Join-Path $PSScriptRoot 'installer'

New-AppMsi -Context $context -AppDir $AppDir -ExeName 'omni_accelerant.exe' -WxsFile (Join-Path $installer 'omni-accelerant.wxs') `
    -LicenseFile (Join-Path $installer 'License.rtf') -ProductName 'OmniAccelerANT' -Version $version -Arch $Arch `
    -OutFile "$base.msi" -FragmentPath (Join-Path $work 'msi-payload-files.wxs')
New-AppMsix -Context $context -AppDir $AppDir -ManifestTemplate (Join-Path $installer 'AppxManifest.xml') `
    -LogoPath (Join-Path $repoRoot 'web\icons\Icon-512.png') -Version $msixVersion -Arch $Arch -OutFile "$base.msix" `
    -WorkDir $work -Publisher $MsixPublisher -Pfx $MsixPfx
