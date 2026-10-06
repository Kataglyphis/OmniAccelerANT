#requires -Version 7.0
<#
.SYNOPSIS
    Packages the Windows cat cam: one self-contained install folder, a zip of it, and an MSI around it.
.DESCRIPTION
    Runs inside the family image (:winamd64). The folder holds kataglyphis_cat_webrtc.exe, the DLLs it and its
    GStreamer plugins import (VC++ runtime included), the plugin subset in lib\gstreamer-1.0, the plugin scanner,
    the chain ONNX Runtime (proved by the hub's G6 census), the model and the web build. The exe finds all of it
    beside itself (OxidANT's install.rs). The MSI installs it per machine and starts it at every logon through
    the Startup folder; docs/source/camera-streaming.md § The Windows cat cam has the rest.
.PARAMETER WebRoot
    The Flutter web build (the web lane's build\web). Required.
.PARAMETER Producer
    A built kataglyphis_cat_webrtc.exe; default: cargo build --release in third_party\OxidANT.
.PARAMETER Msix
    Also pack the same folder as an MSIX, with a logon startup task, its firewall rules and the omni-catcam alias.
.PARAMETER MsixPfx
    The certificate that signs the MSIX (password in MSIX_PFX_PASSWORD); without it a test certificate signs, and its
    .cer lands beside the package for a tester to trust.
.PARAMETER MsixPublisher
    The MSIX publisher, which must equal the signing certificate's subject.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'a throwaway password for the per-build test certificate')]
param(
    [Parameter(Mandatory)][string]$WebRoot,
    [string]$Model = '',
    [string]$Producer = '',
    [string]$OutDir = '',
    [string]$Version = '',
    [switch]$SkipMsi,
    [switch]$Msix,
    [string]$MsixPfx = '',
    [string]$MsixPublisher = 'CN=Kataglyphis'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsBuild.Common', 'WindowsTargetArch.Common', 'WindowsCrossBundle.Common',
    'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common', 'WindowsMsix.Common')

$package = 'omni-accelerant-catcam'
if (-not $Model) { $Model = Join-Path $repoRoot 'third_party\AccelerANTgine\models\yolo26n.onnx' }
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'out' }
if (-not (Test-Path -LiteralPath (Join-Path $WebRoot 'index.html'))) { throw "no index.html in $WebRoot" }
if (-not (Test-Path -LiteralPath $Model)) { throw "model not found: $Model" }
if (-not $Version) {
    $line = Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
    if (-not $line) { throw 'no version in pubspec.yaml' }
    $Version = $line.Matches[0].Groups[1].Value
}
$runtime = 'C:\runtime'
$arch = Get-WindowsTargetArch
$packageArch = Get-WindowsPackageArch -Arch $arch

if (-not $Producer) {
    # Container-local, never the mounted checkout: cargo's renames fail on a bind mount.
    $env:CARGO_TARGET_DIR = 'C:\catcam-target'
    Push-Location (Join-Path $repoRoot 'third_party\OxidANT')
    try {
        cargo build --release --locked -p kataglyphis_cat_webrtc
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
    $Producer = Join-Path $env:CARGO_TARGET_DIR 'release\kataglyphis_cat_webrtc.exe'
}
if (-not (Test-Path -LiteralPath $Producer)) { throw "producer not found: $Producer" }

$stage = 'C:\catcam-stage'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$plugDir = Join-Path $stage 'lib\gstreamer-1.0'
$scanDir = Join-Path $stage 'libexec\gstreamer-1.0'
$shareDir = Join-Path $stage "share\$package"
foreach ($d in $plugDir, $scanDir, (Join-Path $stage 'models'), $shareDir) { $null = New-Item -ItemType Directory -Force -Path $d }
Copy-Item -LiteralPath $Producer -Destination $stage

# The service's pipelines and webrtcsink's own; mediafoundation/winks are the cameras, openh264 the only codec (no vpx here).
$plugins = 'coreelements', 'app', 'videoconvertscale', 'videorate', 'videofilter', 'videotestsrc', 'rawparse',
'videoparsersbad', 'debugutilsbad', 'jpeg', 'png', 'multifile', 'mediafoundation', 'winks', 'rswebrtc', 'rsrtp',
'webrtc', 'nice', 'dtls', 'srtp', 'sctp', 'rtpmanager', 'rtp', 'openh264'
$optional = 'vpx', 'd3d11'
foreach ($name in $plugins + $optional) {
    $dll = Join-Path $runtime "lib\gstreamer-1.0\gst$name.dll"
    if (Test-Path -LiteralPath $dll) { Copy-Item -LiteralPath $dll -Destination $plugDir }
    elseif ($name -in $plugins) { throw "GStreamer plugin $name is not in the image ($dll)" }
    else { Write-Warning "optional plugin $name is not in the image" }
}
Copy-Item -LiteralPath (Join-Path $runtime 'libexec\gstreamer-1.0\gst-plugin-scanner.exe') -Destination $scanDir

# Imports, transitively, from the image's runtime; plugins and the scanner resolve against the exe's folder too.
$roots = @(Join-Path $stage (Split-Path $Producer -Leaf)) + @(Get-ChildItem $plugDir, $scanDir -File | ForEach-Object FullName)
$closure = Copy-PeImportClosure -Path $roots -SearchDirectory @(Join-Path $runtime 'bin') -Destination $stage -Arch $arch
Write-Host "DLL closure: $($closure.Count) file(s) from $runtime\bin"

# A clean Windows has no VC++ runtime, and the closure leaves System32's names to the OS.
$vcNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($bin in @(Get-ChildItem $stage -Recurse -Include '*.dll', '*.exe' -File)) {
    foreach ($name in @(Get-PeImportNames -Path $bin.FullName -IncludeDelayLoad)) {
        if ($name -match '^(vcruntime|msvcp|concrt)\d+(_\d+)?\.dll$') { $null = $vcNames.Add($name) }
    }
}
foreach ($name in $vcNames) {
    $src = Join-Path $env:SystemRoot "System32\$name"
    if (-not (Test-Path -LiteralPath $src)) { throw "VC++ runtime $name is imported but not in System32" }
    Copy-Item -LiteralPath $src -Destination $stage
}
Write-Host "VC++ runtime: $(@($vcNames) -join ', ')"

Copy-ChainOrtBeside -OnnxRoot $env:ONNX_ROOT -Destination $stage | Out-Null
Copy-Item -LiteralPath $Model -Destination (Join-Path $stage 'models')
Copy-Item -LiteralPath $WebRoot -Destination (Join-Path $stage 'web') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'catcam.toml') -Destination $shareDir
@"
$(Split-Path $Model -Leaf) is an Ultralytics YOLO model, licensed AGPL-3.0
(https://www.gnu.org/licenses/agpl-3.0.html; https://ultralytics.com/license).
It is a separate work shipped beside the MIT-licensed OmniAccelerANT code; replace it
with a model of your choice through 'model' in %ProgramData%\omni-accelerant\catcam.toml.
"@ | Set-Content -LiteralPath (Join-Path $shareDir 'NOTICE-model.txt') -Encoding utf8

# The copy G6 proves is the copy that ships.
$final = "C:\catcam-out\$package"
$payload = New-OrtProvenPayload -ExePath (Join-Path $stage (Split-Path $Producer -Leaf)) -Destination $final `
    -IncludeDirectory @('lib', 'libexec', 'models', 'web', 'share')
$fileCount = @(Get-ChildItem $final -Recurse -File).Count
$sizeMb = [math]::Round((Get-ChildItem $final -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "bundle: $fileCount files, $sizeMb MB, ORT proved: $($payload.LoadsOrt)"

$null = New-Item -ItemType Directory -Force -Path $OutDir
$zip = Join-Path $OutDir "$package-$Version-windows-$packageArch.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $final -DestinationPath $zip
Write-Host "wrote $zip"

$context = New-BuildContext -Workspace $repoRoot -LogDir (Join-Path $OutDir 'logs')
if (-not $SkipMsi) {
    $payloadFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem $final -Recurse -File)) {
        if ($file.FullName -eq $payload.Exe) { continue }
        $sub = [System.IO.Path]::GetRelativePath($final, $file.DirectoryName)
        $payloadFiles.Add([pscustomobject]@{ Source = $file.FullName; Subdirectory = $(if ($sub -eq '.') { '' } else { $sub }) })
    }
    $msi = Join-Path $OutDir "$package-$Version-windows-$packageArch.msi"
    Invoke-MsiPackage -Context $context -WxsFile (Join-Path $PSScriptRoot 'catcam.wxs') -LicenseFile (Join-Path $PSScriptRoot 'License.rtf') `
        -ProductName 'OmniAccelerANT Cat Cam' -Manufacturer 'Kataglyphis' -ExeSource $payload.Exe -Version $Version `
        -OutFile $msi -Arch $packageArch -PayloadFiles $payloadFiles.ToArray() -FragmentPath 'C:\catcam-out\msi-payload-files.wxs' `
        -Extensions @('WixToolset.UI.wixext', 'WixToolset.Firewall.wixext') | Out-Null
    Write-Host "wrote $msi ($([math]::Round((Get-Item $msi).Length / 1MB)) MB)"
}
if (-not $Msix) { return }

Import-BuildModule @('WindowsMsix.Signing')
$msixBase = Join-Path $OutDir "$package-$Version-windows-$packageArch"
$signing = 'C:\catcam-out\msix-signing'
foreach ($d in $signing, 'C:\catcam-out\msix-stage') { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
$null = New-Item -ItemType Directory -Force -Path $signing
$passwordBefore = $env:MSIX_PFX_PASSWORD
if ($MsixPfx) {
    Copy-Item -LiteralPath $MsixPfx -Destination $signing
} else {
    $cert = New-SelfSignedCertificate -Type Custom -Subject $MsixPublisher -KeyUsage DigitalSignature -FriendlyName "$package test signing" `
        -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    $env:MSIX_PFX_PASSWORD = [Guid]::NewGuid().ToString('N')
    $null = Export-PfxCertificate -Cert $cert -FilePath (Join-Path $signing 'test.pfx') -Password (ConvertTo-SecureString $env:MSIX_PFX_PASSWORD -AsPlainText -Force)
    $null = Export-Certificate -Cert $cert -FilePath "$msixBase-testcert.cer"
    Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($cert.Thumbprint)"
}
$msixFile = "$msixBase.msix"
try {
    Invoke-MsixPackage -Context $context -StagingDir 'C:\catcam-out\msix-stage' -ManifestTemplatePath (Join-Path $PSScriptRoot 'AppxManifest.xml') `
        -TokenMap @{ '__PUBLISHER__' = $MsixPublisher; '__VERSION__' = "$Version.0"; '__ARCH__' = $packageArch } `
        -ResourcesDir $final -LogoPath (Join-Path $WebRoot 'icons\Icon-512.png') -OutputPath $msixFile -Sign -SigningRoot $signing | Out-Null
} finally {
    $env:MSIX_PFX_PASSWORD = $passwordBefore
    Remove-Item -LiteralPath $signing -Recurse -Force -ErrorAction SilentlyContinue
}
# Invoke-MsixSign only warns when signing fails, and an unsigned MSIX does not install.
$signer = (Get-AuthenticodeSignature -LiteralPath $msixFile).SignerCertificate
if (-not $signer -or $signer.Subject -ne $MsixPublisher) { throw "$msixFile is not signed by $MsixPublisher" }
Write-Host "wrote $msixFile ($([math]::Round((Get-Item $msixFile).Length / 1MB)) MB), signed by $($signer.Subject)"
