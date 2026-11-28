#requires -Version 7.0

# Tests the Windows wrappers over scripts/licenses and the installer licence check on synthetic payloads; real MSI cabinets are the packagers' job.

BeforeAll {
    function New-LicenseFixtureZip([string] $Path, [hashtable] $Member) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        $archive = [IO.Compression.ZipFile]::Open($Path, 'Create')
        try { foreach ($name in $Member.Keys) { $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $Member[$name], $name) } }
        finally { $archive.Dispose() }
    }
}

Describe 'WindowsThirdPartyLicense.Common' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'OmniTestFixtures.psm1') -Force
        . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
        Import-BuildModule @('WindowsMsiLicense.Common', 'WindowsThirdPartyLicense.Common')
        $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:work = Join-Path ([IO.Path]::GetTempPath()) "third-party-license-$PID"
        $null = New-Item -ItemType Directory -Force -Path $script:work
        $script:assets = @(Get-ThirdPartyLicenseAsset -RepoRoot $script:repoRoot)
        Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue
        # The expected verifier failures must not become the runner step's exit code.
        $global:LASTEXITCODE = 0
    }

    It 'lists the index and its text files' {
        ($script:assets -contains 'assets/licenses/third-party-licenses.json') | Should -Be $true
        $script:assets.Count -gt 1 | Should -Be $true
    }

    It 'accepts a payload whose native files all have an entry, and refuses an unknown DLL' {
        $payload = Join-Path $script:work 'payload'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $payload 'gstreamer-1.0')
        Set-Content -LiteralPath (Join-Path $payload 'omni_accelerant.exe') -Value ''
        Set-Content -LiteralPath (Join-Path $payload 'gstreamer-1.0\gstapp.dll') -Value ''
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $script:repoRoot } | Should -Be ''
        Set-Content -LiteralPath (Join-Path $payload 'x264-164.dll') -Value ''
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $script:repoRoot } | Should -Match 'no third-party license entry'
    }

    It 'covers the DLL of every Flutter plugin the Windows runner builds (mutation)' {
        $cmake = Get-Content -LiteralPath (Join-Path $script:repoRoot 'windows\flutter\generated_plugins.cmake') -Raw
        if ($cmake -notmatch '(?s)list\(APPEND FLUTTER_PLUGIN_LIST\s+(.*?)\)') { throw 'generated_plugins.cmake has no FLUTTER_PLUGIN_LIST' }
        $plugins = @($Matches[1] -split '\s+' | Where-Object { $_ })
        $plugins.Count -gt 0 | Should -Be $true
        $payload = Join-Path $script:work 'plugins'
        $null = New-Item -ItemType Directory -Force -Path $payload
        foreach ($name in $plugins) { Set-Content -LiteralPath (Join-Path $payload "${name}_plugin.dll") -Value '' }
        Get-ThrowMessage { Assert-NativeLicenseCoverage -Path $payload -RepoRoot $script:repoRoot } | Should -Be ''
    }

    It 'requires every inventory file in an archive, byte for byte' {
        $good = Join-Path $script:work 'good.zip'
        $bare = Join-Path $script:work 'bare.zip'
        $all = @{}
        foreach ($asset in $script:assets) { $all["data/flutter_assets/$asset"] = Join-Path $script:repoRoot $asset }
        New-LicenseFixtureZip -Path $good -Member $all
        New-LicenseFixtureZip -Path $bare -Member @{ "data/flutter_assets/$($script:assets[0])" = (Join-Path $script:repoRoot $script:assets[0]) }
        Get-ThrowMessage { Assert-ThirdPartyLicensePackage -Path $good -RepoRoot $script:repoRoot -Asset $script:assets } | Should -Be ''
        Get-ThrowMessage { Assert-ThirdPartyLicensePackage -Path $bare -RepoRoot $script:repoRoot -Asset $script:assets } | Should -Match 'license verification failed'
    }

    Context 'the licence check every installer passes (WindowsAppInstallers.Common)' {
        BeforeAll {
            Import-BuildModule @('WindowsOrtLicense.Common', 'WindowsAppInstallers.Common')
            $script:ortDir = Join-Path $script:work 'ort'
            $null = New-Item -ItemType Directory -Force -Path $script:ortDir
            foreach ($name in 'LICENSE', 'ThirdPartyNotices.txt') { Set-Content -LiteralPath (Join-Path $script:ortDir $name) -Value "fixture ONNX Runtime $name" }
            $script:web = New-AppInstallerPlan -AppDir $script:work -Arch x64 -OutBase (Join-Path $script:work 'web-1.0.0-windows-x64') -WorkDir $script:work `
                -RepoRoot $script:repoRoot -Notice '*web/assets/NOTICES' -OrtLicenseDirectory $script:ortDir
            $script:license = Join-Path $script:repoRoot 'LICENSE'
        }

        It 'names both installers, the MSI fragment and the shipped inventory once' {
            "$($script:web.Msi)|$($script:web.Msix)|$($script:web.Fragment)" | Should -Be "$script:work\web-1.0.0-windows-x64.msi|$script:work\web-1.0.0-windows-x64.msix|$script:work\msi-payload-files.wxs"
            ($script:web.Asset -join ',') | Should -Be ($script:assets -join ',')
        }

        It 'accepts an archive with all three licence sets and refuses one without any of them (mutation)' {
            $members = @{ 'web/assets/NOTICES' = $script:license }
            foreach ($asset in $script:assets) { $members["web/assets/$asset"] = Join-Path $script:repoRoot $asset }
            foreach ($name in 'LICENSE', 'ThirdPartyNotices.txt') { $members["licenses/onnxruntime/$name"] = Join-Path $script:ortDir $name }
            $package = Join-Path $script:work 'fixture.msix'
            New-LicenseFixtureZip -Path $package -Member $members
            Get-ThrowMessage { Assert-AppInstallerLicense -Plan $script:web -Path $package } | Should -Be ''
            foreach ($missing in 'web/assets/NOTICES', "web/assets/$($script:assets[0])", 'licenses/onnxruntime/ThirdPartyNotices.txt') {
                $short = $members.Clone()
                $short.Remove($missing)
                New-LicenseFixtureZip -Path $package -Member $short
                Get-ThrowMessage { Assert-AppInstallerLicense -Plan $script:web -Path $package } | Should -Match 'license verification failed'
            }
        }

        It 'sends an MSI and an MSIX to the hub checks each needs (mutation)' {
            $module = 'WindowsAppInstallers.Common'
            foreach ($name in 'Assert-MsiPackageLicense', 'Assert-PackageLicense', 'Assert-ThirdPartyLicensePackage', 'Assert-OrtWheelLicensesInPackage') { Mock -ModuleName $module $name {} }
            $desktop = $script:web.PSObject.Copy()
            $desktop.Notice = '*flutter_assets/NOTICES.Z'
            Assert-AppInstallerLicense -Plan $desktop -Path $desktop.Msi
            Assert-AppInstallerLicense -Plan $script:web -Path $script:web.Msix
            Should -Invoke -CommandName Assert-MsiPackageLicense -ModuleName $module -Exactly -Times 1 -Scope It
            Should -Invoke -CommandName Assert-MsiPackageLicense -ModuleName $module -Exactly -Times 1 -Scope It -ParameterFilter { "$Path $FileName $LicensePath" -ceq "$($desktop.Msi) NOTICES.Z $script:license" }
            Should -Invoke -CommandName Assert-PackageLicense -ModuleName $module -Exactly -Times 1 -Scope It
            Should -Invoke -CommandName Assert-PackageLicense -ModuleName $module -Exactly -Times 1 -Scope It -ParameterFilter { "$Path $Pattern $LicensePath" -ceq "$($script:web.Msix) *web/assets/NOTICES $script:license" }
            Should -Invoke -CommandName Assert-ThirdPartyLicensePackage -ModuleName $module -Exactly -Times 1 -Scope It -ParameterFilter { "$Path $script:RepoRoot $MemberPrefix $Asset" -ceq "$($desktop.Msi) $script:repoRoot *flutter_assets/ $script:assets" }
            Should -Invoke -CommandName Assert-ThirdPartyLicensePackage -ModuleName $module -Exactly -Times 1 -Scope It -ParameterFilter { "$Path $script:RepoRoot $MemberPrefix $Asset" -ceq "$($script:web.Msix) $script:repoRoot *web/assets/ $script:assets" }
            Should -Invoke -CommandName Assert-OrtWheelLicensesInPackage -ModuleName $module -Exactly -Times 1 -Scope It -ParameterFilter { "$Path $LicenseDirectory $Format $WixPath" -ceq "$($desktop.Msi) $script:ortDir msi $($desktop.Fragment)" }
            Should -Invoke -CommandName Assert-OrtWheelLicensesInPackage -ModuleName $module -Exactly -Times 1 -Scope It -ParameterFilter { "$Path $LicenseDirectory $Format" -ceq "$($script:web.Msix) $script:ortDir archive" }
        }
    }

}
