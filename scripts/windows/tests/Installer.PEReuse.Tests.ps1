#requires -Version 7.0

# This guards shared module wiring and byte validation; it does not install MSI or MSIX packages.
function Get-SiblingScriptAst([string] $Relative) {
    return Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot (Join-Path '..' $Relative))
}

function Get-ScriptCommandCount([object] $Ast, [string] $Name, [string] $TextPattern = '') {
    $commands = @(Get-TestAstCommands -Ast $Ast -Name $Name)
    return @($commands | Where-Object { -not $TextPattern -or $_.Extent.Text -match $TextPattern }).Count
}

function Get-ScriptFunctionCount([object] $Ast, [string] $Name) {
    return @(Get-TestFunctionNames -Ast $Ast | Where-Object { $_ -eq $Name }).Count
}

function Assert-InstallerChecksUseHubRunner {
    foreach ($relative in 'Test-OmniAccelerANTInstallers.ps1', 'observant/Test-ObservANTWindows.ps1', 'observant/Test-ObservANTMsix.ps1') {
        $scriptAst = Get-SiblingScriptAst $relative
        Get-ScriptCommandCount $scriptAst 'Import-BuildModule' 'WindowsSmokeTest\.Common' | Should Be 1
        Get-ScriptCommandCount $scriptAst 'Initialize-SmokeTestRun' | Should Be 1
        (Get-ScriptCommandCount $scriptAst 'Assert-Test') -gt 0 | Should Be $true
        (Get-ScriptCommandCount $scriptAst 'Get-SmokeTestSummary') -gt 0 | Should Be $true
        Get-ScriptFunctionCount $scriptAst 'Test-Check' | Should Be 0
    }
}

function Assert-PackagerLicenseWiring([string] $Relative, [string] $Notice, [string] $OrtSource, [string] $OrtText) {
    $ast = Get-SiblingScriptAst $Relative
    $plan = @(Get-TestAstCommands -Ast $ast -Name 'New-AppInstallerPlan')
    Get-CommandTextCount $plan -Contains "-Notice '$Notice'", '-RepoRoot $repoRoot', '-OrtLicenseDirectory $ortLicenses' | Should Be 1
    $source = @(Get-TestAstCommands -Ast $ast -Name $OrtSource)
    Get-CommandTextCount $source -Contains $OrtText | Should Be 1
    Get-ScriptCommandCount $ast 'Copy-OrtWheelLicenses' | Should Be ([int]($OrtSource -eq 'Copy-OrtWheelLicenses'))
    $checks = @(Get-TestAstCommands -Ast $ast -Name 'Assert-AppInstallerLicense')
    $checks.Count | Should Be 2
    foreach ($installer in 'Msi', 'Msix') {
        $built = @(Get-TestAstCommands -Ast $ast -Name "New-App$installer")
        $check = @($checks | Where-Object { $_.Extent.Text -ceq "Assert-AppInstallerLicense -Plan `$plan -Path `$plan.$installer" })
        "$($built.Count) $($check.Count)" | Should Be '1 1'
        Test-CommandAfter $check[0] $built[0] | Should Be $true
    }
    # Only the shared check verifies an installer; ObservANT's zip keeps its own ONNX Runtime check.
    foreach ($name in 'Assert-MsiPackageLicense', 'Assert-PackageLicense', 'Assert-ThirdPartyLicensePackage') { Get-ScriptCommandCount $ast $name | Should Be 0 }
    Get-ScriptCommandCount $ast 'Assert-OrtWheelLicensesInPackage' | Should Be ([int]($OrtSource -eq 'Copy-OrtWheelLicenses'))
}

function Assert-GpuPackageByteCheck {
    $ast = Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot '..\Package-OmniAccelerANT.ps1')
    $text = $ast.Extent.Text
    foreach ($name in 'onnxruntime.dll', 'onnxruntime_providers_shared.dll', 'onnxruntime_providers_cuda.dll', 'ort-chain-stamp.json', 'omni_accelerant.exe', 'oxidant.dll') {
        $text.Contains("'$name'") | Should Be $true
    }
    $text.Contains("[ValidateSet('cpu', 'cuda', 'directml')][string]`$OrtProvider = 'cpu'") | Should Be $true
    $text.Contains("Resolve-BuildModule -Name 'WindowsPackageBinary.Common'") | Should Be $true
    $text.Contains('"$base-$vendor"') | Should Be $true
    Get-ScriptCommandCount $ast 'Get-WixSourceFileId' | Should Be 1
    $checks = @(Get-TestAstCommands -Ast $ast -Name 'Assert-PackageBinary')
    $checks.Count | Should Be 2
    Get-CommandTextCount $checks -Contains '"$base.msi"', '-Member $gpuMsiIds', '-SourcePath $gpuPaths' | Should Be 1
    Get-CommandTextCount $checks -Contains '"$base.msix"', '-Member $gpuFiles', '-SourcePath $gpuPaths' | Should Be 1
    $inventories = @(Get-TestAstCommands -Ast $ast -Name 'Assert-PackageOrtProviderSet')
    $inventories.Count | Should Be 2
    Get-CommandTextCount $inventories -Contains '-RootDirectoryId APPLICATIONFOLDER' | Should Be 1
    $proofs = @(Get-TestAstCommands -Ast $ast -Name 'Assert-WindowsInstallerCandidate')
    $proofs.Count | Should Be 3
    Test-CommandAfter $proofs[1] $checks[0] | Should Be $true
    Test-CommandAfter $proofs[2] $checks[1] | Should Be $true
}

Describe 'Installer shared Windows checks' {
    Import-Module (Join-Path $PSScriptRoot 'OmniTestFixtures.psm1') -Force
    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsTargetArch.Common', 'WindowsSmokeTest.Common')
    Import-Module (Join-Path $PSScriptRoot '..\..\..\third_party\ANTfrastructure\windows\scripts\tests\TestHarness.psm1') -Function Get-TestScriptAst, Get-TestAstCommands, Assert-TestAstCommand, Get-TestFunctionNames, New-TestPeFile -ErrorAction Stop

    It 'parses and calls the shared target facts and PE reader' {
        $ast = Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot '..\Test-OmniAccelerANTInstallers.ps1')
        Get-ScriptCommandCount $ast 'Import-BuildModule' 'WindowsTargetArch\.Common' | Should Be 1
        Get-ScriptCommandCount $ast 'Get-PeMachineType' | Should Be 1
        Get-ScriptCommandCount $ast 'Get-PeFileMachine' | Should Be 1
        Get-ScriptFunctionCount $ast 'Get-PeMachine' | Should Be 0
    }

    It 'reads x64 and arm64 target facts and rejects a malformed binary' {
        Get-PeMachineType -Arch x64 | Should Be 0x8664
        Get-PeMachineType -Arch arm64 | Should Be 0xAA64
        $path = Join-Path $TestDrive 'fixture.exe'
        New-TestPeFile -Path $path -Machine 0x8664
        Get-PeFileMachine -Path $path | Should Be 0x8664
        $bytes = [IO.File]::ReadAllBytes($path)
        $bytes[0x40] = 0
        [IO.File]::WriteAllBytes($path, $bytes)
        $message = try { Get-PeFileMachine -Path $path | Out-Null; '' } catch { $_.Exception.Message }
        ($message -match 'not a PE file') | Should Be $true
    }

    It 'uses the hub assertion runner in all three installer checks' { Assert-InstallerChecksUseHubRunner }

    It 'reads both MSIX manifests through the shared archive reader' {
        @(Get-Command Get-MsixArchiveInfo -ErrorAction SilentlyContinue).Count | Should Be 1
        foreach ($relative in 'Test-OmniAccelerANTInstallers.ps1', 'observant/Test-ObservANTMsix.ps1') {
            $ast = Get-SiblingScriptAst $relative
            Get-ScriptCommandCount $ast 'Get-CheckedMsixView' | Should Be 1
            ($ast.Extent.Text -match 'ZipFile\]::OpenRead') | Should Be $false
        }
        $module = Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot '..\modules\WindowsInstallerCheck.Common.psm1')
        Get-ScriptCommandCount $module 'Get-MsixArchiveInfo' | Should Be 1
    }

    It 'uses the shared directory reset for MSIX signing and staging' {
        Import-BuildModule 'WindowsAppInstallers.Common'
        $source = & (Get-Module WindowsAppInstallers.Common) { (Get-Command Initialize-BuildDirectory -ErrorAction Stop).Source }
        $source | Should Be 'WindowsScripts.Shared'
        $modulePath = if ($env:OMNI_APP_INSTALLERS_SOURCE) { $env:OMNI_APP_INSTALLERS_SOURCE } else { Join-Path $PSScriptRoot '..\modules\WindowsAppInstallers.Common.psm1' }
        $ast = Get-TestScriptAst -ScriptPath $modulePath
        $calls = @(Get-TestAstCommands -Ast $ast -Name 'Initialize-BuildDirectory')
        Assert-TestAstCommand -Command $calls -Text 'Initialize-BuildDirectory -Path @($signing, $stage) -Empty'
    }

    It 'checks both installers of both packagers through one plan and the shared licence check (mutation)' {
        # The host-side app packager takes the texts the image build matched and stamped; ObservANT packs in the image.
        Assert-PackagerLicenseWiring -Relative 'Package-OmniAccelerANT.ps1' -Notice '*flutter_assets/NOTICES.Z' -OrtSource 'Resolve-RunnerOrtLicense' -OrtText '-RunnerDir $AppDir'
        Assert-PackagerLicenseWiring -Relative 'observant/Package-ObservANT.ps1' -Notice '*web/assets/NOTICES' -OrtSource 'Copy-OrtWheelLicenses' -OrtText 'Get-OrtChainWheelStore'
        $zip = @(Get-TestAstCommands -Ast (Get-SiblingScriptAst 'observant/Package-ObservANT.ps1') -Name 'Assert-OrtWheelLicensesInPackage')
        Assert-TestAstCommand -Command $zip -Text 'Assert-OrtWheelLicensesInPackage -Path $zip -LicenseDirectory $ortLicenses -Format archive -ArchivePrefix $package'
    }

    It 'gives the x64 host packager a real Python before its native-license gate (mutation)' {
        $yaml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\..\.github\workflows\windows-x64.yml'))
        Test-TextOrder -Text $yaml -Marker 'uses: actions/setup-python@', 'Package-OmniAccelerANT.ps1 -AppDir $env:BUILD_DIR_RELEASE' | Should Be $true
    }

    It 'checks GPU runtime and app bytes in both installers using their real package mappings' { Assert-GpuPackageByteCheck }

    It 'continues after false and thrown assertions and reports both failures' {
        Initialize-SmokeTestRun
        $value = 'visible'
        Assert-Test -Name caller-state -Condition { $value -eq 'visible' }
        Assert-Test -Name false-result -Condition { $false }
        Assert-Test -Name thrown-result -Condition { throw 'fixture error' }
        $summary = Get-SmokeTestSummary
        $summary.Passed | Should Be 1
        $summary.Failed | Should Be 2
        $summary.Aborted | Should Be $false
    }
}
