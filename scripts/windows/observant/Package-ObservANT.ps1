#requires -Version 7.0
<#
.SYNOPSIS
    Packages the Windows ObservANT: one self-contained install folder, a zip of it, and an MSI around it.
.DESCRIPTION
    Runs inside the family image (:winamd64, or its arm64 bundle with -Arch arm64). The folder holds kataglyphis_observant.exe, the DLLs it and its
    GStreamer plugins import (VC++ runtime included), the plugin subset in lib\gstreamer-1.0, the plugin scanner,
    the chain ONNX Runtime (proved by the hub's G6 census), the model and the web build. The exe finds all of it
    beside itself (OxidANT's install.rs). The MSI installs it per machine and starts it at every logon through
    the Startup folder; docs/source/camera-streaming.md § The Windows ObservANT has the rest.
.PARAMETER WebRoot
    The Flutter web build (the web lane's build\web). Required.
.PARAMETER Model
    An ONNX model to ship instead; default: what OxidANT's resources\models\models.lock names, fetched and checked.
.PARAMETER Producer
    A built kataglyphis_observant.exe; default: cargo build --release in third_party\OxidANT.
.PARAMETER Msix
    Also pack the same folder as an MSIX, with a logon startup task, its firewall rules and the omni-observant alias.
.PARAMETER MsixPfx
    The certificate that signs the MSIX (password in MSIX_PFX_PASSWORD); without it a test certificate signs, and its
    .cer lands beside the package for a tester to trust.
.PARAMETER MsixPublisher
    The MSIX publisher, which must equal the signing certificate's subject.
.PARAMETER Arch
    amd64 (default, or WINDOWS_TARGET_ARCH) or arm64: the producer is then cross-built for aarch64-pc-windows-msvc,
    and its DLLs, VC++ runtime included, come from the arm64 runtime and Visual Studio's arm64 redist.
#>
param(
    [Parameter(Mandatory)][string]$WebRoot,
    [string]$Model = '',
    [string]$Producer = '',
    [string]$OutDir = '',
    [string]$Version = '',
    [switch]$SkipMsi,
    [switch]$Msix,
    [string]$MsixPfx = '',
    [string]$MsixPublisher = 'CN=Kataglyphis',
    [string]$Arch = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsBuild.Common', 'WindowsTargetArch.Common', 'WindowsCrossBundle.Common',
    'WindowsOrtProvenance.Common', 'WindowsOrtPayload.Common', 'WindowsMsix.Common', 'WindowsAppInstallers.Common', 'WindowsMsiLicense.Common', 'WindowsOrtLicense.Common')

$package = 'omni-observant'
$modelsLock = Join-Path $repoRoot 'third_party\OxidANT\resources\models\models.lock'
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'out' }
if (-not (Test-Path -LiteralPath (Join-Path $WebRoot 'index.html'))) { throw "no index.html in $WebRoot" }
if ($Model -and -not (Test-Path -LiteralPath $Model)) { throw "model not found: $Model" }
if (-not $Version) { $Version = Get-PackageVersion -WorkspacePath $repoRoot -VersionFile 'pubspec.yaml' -Components 3 -Required }
$runtime = 'C:\runtime'
$arch = Get-WindowsTargetArch -Arch $Arch
$packageArch = Get-WindowsPackageArch -Arch $arch

if (-not $Producer) {
    # Container-local, never the mounted checkout: cargo's renames fail on a bind mount.
    $env:CARGO_TARGET_DIR = 'C:\observant-target'
    if (-not $env:OBSERVANT_VERSION) {
        # /healthz and the Camera page name the build; without git or .git, the version alone.
        $commit = $null
        try { $commit = git -C $repoRoot rev-parse --short HEAD 2>$null } catch { $commit = $null }
        $env:OBSERVANT_VERSION = if ($commit) { "$Version ($commit)" } else { $Version }
    }
    Push-Location (Join-Path $repoRoot 'third_party\OxidANT')
    try {
        $cargoArgs = @('build', '--release', '--locked', '-p', 'kataglyphis_observant')
        $releaseDir = 'release'
        if ($arch -eq 'arm64') {
            # The arm64 bundle's .pc files describe the target, which pkg-config refuses for a cross build unless told.
            $env:PKG_CONFIG_ALLOW_CROSS = '1'
            $cargoArgs += @('--target', 'aarch64-pc-windows-msvc')
            $releaseDir = 'aarch64-pc-windows-msvc\release'
        }
        cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
    $Producer = Join-Path $env:CARGO_TARGET_DIR "$releaseDir\kataglyphis_observant.exe"
}
if (-not (Test-Path -LiteralPath $Producer)) { throw "producer not found: $Producer" }

$stage = 'C:\observant-stage'
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
# isomp4 muxes the arrival clip; without it the service records none and says so.
$optional = 'vpx', 'd3d11', 'isomp4'
foreach ($name in $plugins + $optional) {
    $dll = Join-Path $runtime "lib\gstreamer-1.0\gst$name.dll"
    if (Test-Path -LiteralPath $dll) { Copy-Item -LiteralPath $dll -Destination $plugDir }
    elseif ($name -in $plugins) { throw "GStreamer plugin $name is not in the image ($dll)" }
    else { Write-Warning "optional plugin $name is not in the image" }
}
Copy-Item -LiteralPath (Join-Path $runtime 'libexec\gstreamer-1.0\gst-plugin-scanner.exe') -Destination $scanDir

# Before the closure: the producer loads ORT at run time, so only ORT's own imports name what it needs (msvcp140_1.dll).
Copy-ChainOrtBeside -OnnxRoot $env:ONNX_ROOT -Destination $stage | Out-Null
# Imports, transitively, from the image's runtime; plugins and the scanner resolve against the exe's folder too.
$roots = @(Get-ChildItem $stage -File | Where-Object Extension -In '.exe', '.dll' | ForEach-Object FullName) + @(Get-ChildItem $plugDir, $scanDir -File | ForEach-Object FullName)
# arm64 also searches Visual Studio's arm64 redist, since this x64 container's System32 holds x64 DLLs only.
$searchDirs = if ($arch -eq 'arm64') { @(Get-ProductDllSearchPath -Arch $arch) } else { @(Join-Path $runtime 'bin') }
$closure = Copy-PeImportClosure -Path $roots -SearchDirectory $searchDirs -Destination $stage -Arch $arch
Write-Host "DLL closure: $($closure.Count) file(s) from $runtime\bin"

# A clean Windows has no VC++ runtime, and the closure leaves System32's names to the OS.
$vcNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($bin in @(Get-ChildItem $stage -Recurse -Include '*.dll', '*.exe' -File)) {
    foreach ($name in @(Get-PeImportNames -Path $bin.FullName -IncludeDelayLoad)) {
        if ($name -match '^(vcruntime|msvcp|concrt)\d+(_\d+)?\.dll$') { $null = $vcNames.Add($name) }
    }
}
foreach ($name in $vcNames) {
    if ($arch -eq 'arm64') {
        # The closure took it from the arm64 redist; System32's would be x64.
        if (-not (Test-Path -LiteralPath (Join-Path $stage $name))) { throw "arm64 VC++ runtime $name is not in the redist the closure searched" }
        continue
    }
    $src = Join-Path $env:SystemRoot "System32\$name"
    if (-not (Test-Path -LiteralPath $src)) { throw "VC++ runtime $name is imported but not in System32" }
    Copy-Item -LiteralPath $src -Destination $stage
}
Write-Host "VC++ runtime: $(@($vcNames) -join ', ')"

$modelDir = Join-Path $stage 'models'
if ($Model) {
    Copy-Item -LiteralPath $Model -Destination $modelDir
    $modelName = Split-Path $Model -Leaf
    $modelNotice = 'It was chosen at package time (-Model) and carries its own license.'
} else {
    & (Join-Path $repoRoot 'third_party\OxidANT\scripts\windows\Get-Models.ps1') -Lock $modelsLock -Destination $modelDir
    $modelName = (Get-ChildItem -LiteralPath $modelDir -Filter '*.onnx' | Select-Object -First 1).Name
    $base = [IO.Path]::GetFileNameWithoutExtension($modelName)
    Move-Item -LiteralPath (Join-Path $modelDir "$base.LICENSE"), (Join-Path $modelDir "$base.NOTICE") -Destination $shareDir
    $modelNotice = "It is DEIM-D-FINE-N, licensed Apache-2.0; $base.LICENSE and $base.NOTICE beside this file`nname the license, its authors and what ModelANT changed."
}
Copy-Item -LiteralPath $WebRoot -Destination (Join-Path $stage 'web') -Recurse
$web = Join-Path $stage 'web'
# Only a loader config naming enableWimp or preferWebParagraph fetches those renderers, and no browser fetches *.symbols.
$bootstrap = @(Get-Content -LiteralPath (Join-Path $web 'flutter_bootstrap.js'))
$load = $bootstrap | Select-String -SimpleMatch '_flutter.loader.load(' | Select-Object -First 1
if ($load -and ($bootstrap[($load.LineNumber - 1)..($bootstrap.Count - 1)] -join "`n") -match 'enableWimp|preferWebParagraph') {
    throw 'flutter_bootstrap.js asks for the wimp or webparagraph renderer, which this package leaves out'
}
$webParagraph = Join-Path $web 'canvaskit\webparagraph'
if (Test-Path -LiteralPath $webParagraph) { Remove-Item -LiteralPath $webParagraph -Recurse -Force }
Get-ChildItem -LiteralPath (Join-Path $web 'canvaskit') -Filter 'wimp.*' -File | Remove-Item -Force
Get-ChildItem -LiteralPath $web -Recurse -Filter '*.symbols' -File | Remove-Item -Force
if ($arch -eq 'arm64') {
    Write-Host 'web: no zopfli .gz for arm64, whose producer cannot run on this amd64 host; the service gzips at run time'
} else {
    # Zopfli .gz beside each file the server gzips: smaller than its own gzip, and nothing to compress at run time.
    & $Producer --precompress $web
    if ($LASTEXITCODE -ne 0) { throw "$Producer --precompress failed with $LASTEXITCODE" }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'observant.toml') -Destination $shareDir
@"
models\$modelName is a separate work shipped beside the MIT-licensed OmniAccelerANT code.
$modelNotice
Replace it with a model of your choice through 'model' in %ProgramData%\omni-accelerant\observant.toml.
"@ | Set-Content -LiteralPath (Join-Path $shareDir 'NOTICE-model.txt') -Encoding utf8

# The copy G6 proves is the copy that ships.
$final = "C:\observant-out\$package"
$payload = New-OrtProvenPayload -ExePath (Join-Path $stage (Split-Path $Producer -Leaf)) -Destination $final `
    -IncludeDirectory @('lib', 'libexec', 'models', 'web', 'share')
$ortLicenses = Copy-OrtWheelLicenses -OrtDll (Join-Path $final 'onnxruntime.dll') -WheelDir (Get-OrtChainWheelStore) -Destination $final
$fileCount = @(Get-ChildItem $final -Recurse -File).Count
$sizeMb = [math]::Round((Get-ChildItem $final -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "bundle: $fileCount files, $sizeMb MB, ORT proved: $($payload.LoadsOrt)"

$null = New-Item -ItemType Directory -Force -Path $OutDir
$zip = Join-Path $OutDir "$package-$Version-windows-$packageArch.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $final -DestinationPath $zip
Assert-OrtWheelLicensesInPackage -Path $zip -LicenseDirectory $ortLicenses -Format archive -ArchivePrefix $package
Write-Host "wrote $zip"

$context = New-BuildContext -Workspace $repoRoot -LogDir (Join-Path $OutDir 'logs')
$msixBase = Join-Path $OutDir "$package-$Version-windows-$packageArch"
if (-not $SkipMsi) {
    $fragment = 'C:\observant-out\msi-payload-files.wxs'
    New-AppMsi -Context $context -AppDir $final -ExeName (Split-Path $payload.Exe -Leaf) -WxsFile (Join-Path $PSScriptRoot 'observant.wxs') `
        -LicenseFile (Join-Path $PSScriptRoot '..\installer\License.rtf') -ProductName 'ObservANT' -Version $Version -Arch $packageArch `
        -OutFile "$msixBase.msi" -FragmentPath $fragment -Extensions @('WixToolset.UI.wixext', 'WixToolset.Firewall.wixext')
    Assert-MsiPackageLicense -Path "$msixBase.msi" -FileName 'NOTICES' -LicensePath (Join-Path $repoRoot 'LICENSE')
    Assert-OrtWheelLicensesInPackage -Path "$msixBase.msi" -LicenseDirectory $ortLicenses -Format msi -WixPath $fragment
}
if (-not $Msix) { return }

Import-BuildModule @('WindowsMsix.Signing')
New-AppMsix -Context $context -AppDir $final -ManifestTemplate (Join-Path $PSScriptRoot 'AppxManifest.xml') -LogoPath (Join-Path $WebRoot 'icons\Icon-512.png') `
    -Version "$Version.0" -Arch $packageArch -OutFile "$msixBase.msix" -WorkDir 'C:\observant-out' -Publisher $MsixPublisher -Pfx $MsixPfx
Assert-PackageLicense -Path "$msixBase.msix" -Pattern '*web/assets/NOTICES' -LicensePath (Join-Path $repoRoot 'LICENSE')
Assert-OrtWheelLicensesInPackage -Path "$msixBase.msix" -LicenseDirectory $ortLicenses -Format archive
