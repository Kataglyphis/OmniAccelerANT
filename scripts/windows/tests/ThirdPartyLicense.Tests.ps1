#requires -Version 7.0

# Tests the Windows wrappers over scripts/licenses and the installer licence check on synthetic payloads; real MSI cabinets are the packagers' job. Pester 3.4.0 dialect.

function New-LicenseFixtureZip([string] $Path, [hashtable] $Member) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    $archive = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try { foreach ($name in $Member.Keys) { $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $Member[$name], $name) } }
    finally { $archive.Dispose() }
}

Describe 'WindowsThirdPartyLicense.Common' {

    Import-Module (Join-Path $PSScriptRoot 'OmniTestFixtures.psm1') -Force

    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsMsiLicense.Common', 'WindowsThirdPartyLicense.Common')
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $work = Join-Path ([IO.Path]::GetTempPath()) "third-party-license-$PID"
    $null = New-Item -ItemType Directory -Force -Path $work
    $assets = @(Get-ThirdPartyLicenseAsset -RepoRoot $repoRoot)

    It 'lists the index and its text files' {
        ($assets -contains 'assets/licenses/third-party-licenses.json') | Should Be $true
        $assets.Count -gt 1 | Should Be $true
    }

    It 'accepts a payload whose native files all have an entry, and refuses an unknown DLL' {
        $payload = Join-Path $work 'payload'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $payload 'gstreamer-1.0')
        Set-Content -LiteralPath (Join-Path $payload 'omni_accelerant.exe') -Value ''
        Set-Content -LiteralPath (Join-Path $payload 'gstreamer-1.0\gstapp.dll') -Value ''
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $repoRoot } | Should Be ''
        Set-Content -LiteralPath (Join-Path $payload 'x264-164.dll') -Value ''
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $repoRoot } | Should Match 'no third-party license entry'
    }

    It 'covers the DLL of every Flutter plugin the Windows runner builds (mutation)' {
        $cmake = Get-Content -LiteralPath (Join-Path $repoRoot 'windows\flutter\generated_plugins.cmake') -Raw
        if ($cmake -notmatch '(?s)list\(APPEND FLUTTER_PLUGIN_LIST\s+(.*?)\)') { throw 'generated_plugins.cmake has no FLUTTER_PLUGIN_LIST' }
        $plugins = @($Matches[1] -split '\s+' | Where-Object { $_ })
        $plugins.Count -gt 0 | Should Be $true
        $payload = Join-Path $work 'plugins'
        $null = New-Item -ItemType Directory -Force -Path $payload
        foreach ($name in $plugins) { Set-Content -LiteralPath (Join-Path $payload "${name}_plugin.dll") -Value '' }
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $repoRoot } | Should Be ''
    }

    It 'requires every inventory file in an archive, byte for byte' {
        $good = Join-Path $work 'good.zip'
        $bare = Join-Path $work 'bare.zip'
        $all = @{}
        foreach ($asset in $assets) { $all["data/flutter_assets/$asset"] = Join-Path $repoRoot $asset }
        New-LicenseFixtureZip -Path $good -Member $all
        New-LicenseFixtureZip -Path $bare -Member @{ "data/flutter_assets/$($assets[0])" = (Join-Path $repoRoot $assets[0]) }
        Get-ThrowMessage { Assert-ThirdPartyLicensePackage -Path $good -RepoRoot $repoRoot -Asset $assets } | Should Be ''
        Get-ThrowMessage { Assert-ThirdPartyLicensePackage -Path $bare -RepoRoot $repoRoot -Asset $assets } | Should Match 'license verification failed'
    }

    Context 'the licence check every installer passes (WindowsAppInstallers.Common)' {
        Import-BuildModule @('WindowsOrtLicense.Common', 'WindowsAppInstallers.Common')
        $ortDir = Join-Path $work 'ort'
        $null = New-Item -ItemType Directory -Force -Path $ortDir
        foreach ($name in 'LICENSE', 'ThirdPartyNotices.txt') { Set-Content -LiteralPath (Join-Path $ortDir $name) -Value "fixture ONNX Runtime $name" }
        $web = New-AppInstallerPlan -AppDir $work -Arch x64 -OutBase (Join-Path $work 'web-1.0.0-windows-x64') -WorkDir $work `
            -RepoRoot $repoRoot -Notice '*web/assets/NOTICES' -OrtLicenseDirectory $ortDir
        $license = Join-Path $repoRoot 'LICENSE'

        It 'names both installers, the MSI fragment and the shipped inventory once' {
            "$($web.Msi)|$($web.Msix)|$($web.Fragment)" | Should Be "$work\web-1.0.0-windows-x64.msi|$work\web-1.0.0-windows-x64.msix|$work\msi-payload-files.wxs"
            ($web.Asset -join ',') | Should Be ($assets -join ',')
        }

        It 'accepts an archive with all three licence sets and refuses one without any of them (mutation)' {
            $members = @{ 'web/assets/NOTICES' = $license }
            foreach ($asset in $assets) { $members["web/assets/$asset"] = Join-Path $repoRoot $asset }
            foreach ($name in 'LICENSE', 'ThirdPartyNotices.txt') { $members["licenses/onnxruntime/$name"] = Join-Path $ortDir $name }
            $package = Join-Path $work 'fixture.msix'
            New-LicenseFixtureZip -Path $package -Member $members
            Get-ThrowMessage { Assert-AppInstallerLicense -Plan $web -Path $package } | Should Be ''
            foreach ($missing in 'web/assets/NOTICES', "web/assets/$($assets[0])", 'licenses/onnxruntime/ThirdPartyNotices.txt') {
                $short = $members.Clone()
                $short.Remove($missing)
                New-LicenseFixtureZip -Path $package -Member $short
                Get-ThrowMessage { Assert-AppInstallerLicense -Plan $web -Path $package } | Should Match 'license verification failed'
            }
        }

        It 'sends an MSI and an MSIX to the hub checks each needs (mutation)' {
            $module = 'WindowsAppInstallers.Common'
            foreach ($name in 'Assert-MsiPackageLicense', 'Assert-PackageLicense', 'Assert-ThirdPartyLicensePackage', 'Assert-OrtWheelLicensesInPackage') { Mock -ModuleName $module $name {} }
            $desktop = $web.PSObject.Copy()
            $desktop.Notice = '*flutter_assets/NOTICES.Z'
            Assert-AppInstallerLicense -Plan $desktop -Path $desktop.Msi
            Assert-AppInstallerLicense -Plan $web -Path $web.Msix
            Assert-MockCalled Assert-MsiPackageLicense -ModuleName $module -Exactly 1 -Scope It
            Assert-MockCalled Assert-MsiPackageLicense -ModuleName $module -Exactly 1 -Scope It -ParameterFilter { "$Path $FileName $LicensePath" -ceq "$($desktop.Msi) NOTICES.Z $license" }
            Assert-MockCalled Assert-PackageLicense -ModuleName $module -Exactly 1 -Scope It
            Assert-MockCalled Assert-PackageLicense -ModuleName $module -Exactly 1 -Scope It -ParameterFilter { "$Path $Pattern $LicensePath" -ceq "$($web.Msix) *web/assets/NOTICES $license" }
            Assert-MockCalled Assert-ThirdPartyLicensePackage -ModuleName $module -Exactly 1 -Scope It -ParameterFilter { "$Path $RepoRoot $MemberPrefix $Asset" -ceq "$($desktop.Msi) $repoRoot *flutter_assets/ $assets" }
            Assert-MockCalled Assert-ThirdPartyLicensePackage -ModuleName $module -Exactly 1 -Scope It -ParameterFilter { "$Path $RepoRoot $MemberPrefix $Asset" -ceq "$($web.Msix) $repoRoot *web/assets/ $assets" }
            Assert-MockCalled Assert-OrtWheelLicensesInPackage -ModuleName $module -Exactly 1 -Scope It -ParameterFilter { "$Path $LicenseDirectory $Format $WixPath" -ceq "$($desktop.Msi) $ortDir msi $($desktop.Fragment)" }
            Assert-MockCalled Assert-OrtWheelLicensesInPackage -ModuleName $module -Exactly 1 -Scope It -ParameterFilter { "$Path $LicenseDirectory $Format" -ceq "$($web.Msix) $ortDir archive" }
        }
    }

    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    # The expected verifier failures must not become the runner step's exit code.
    $global:LASTEXITCODE = 0
}
