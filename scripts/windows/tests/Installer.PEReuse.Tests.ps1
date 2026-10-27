#requires -Version 7.0

# This guards shared module wiring and byte validation; it does not install MSI or MSIX packages.
Describe 'Installer shared Windows checks' {
    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsTargetArch.Common', 'WindowsSmokeTest.Common')
    Import-Module (Join-Path $PSScriptRoot '..\..\..\third_party\ANTfrastructure\windows\scripts\tests\TestHarness.psm1') -Function Get-TestScriptAst, Get-TestAstCommands, New-TestPeFile -ErrorAction Stop

    It 'parses and calls the shared target facts and PE reader' {
        $installer = Join-Path $PSScriptRoot '..\Test-OmniAccelerANTInstallers.ps1'
        $ast = Get-TestScriptAst -ScriptPath $installer
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        @($commands | Where-Object { $_.GetCommandName() -eq 'Import-BuildModule' -and $_.Extent.Text -match "WindowsTargetArch\.Common" }).Count | Should Be 1
        @($commands | Where-Object { $_.GetCommandName() -eq 'Get-PeMachineType' }).Count | Should Be 1
        @($commands | Where-Object { $_.GetCommandName() -eq 'Get-PeFileMachine' }).Count | Should Be 1
        @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PeMachine' }, $true)).Count | Should Be 0
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

    It 'uses the hub assertion runner in all three installer checks' {
        foreach ($relative in 'Test-OmniAccelerANTInstallers.ps1', 'observant/Test-ObservANTWindows.ps1', 'observant/Test-ObservANTMsix.ps1') {
            $path = Join-Path $PSScriptRoot (Join-Path '..' $relative)
            $scriptAst = Get-TestScriptAst -ScriptPath $path
            $commands = @($scriptAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
            @($commands | Where-Object { $_.GetCommandName() -eq 'Import-BuildModule' -and $_.Extent.Text -match 'WindowsSmokeTest\.Common' }).Count | Should Be 1
            @($commands | Where-Object { $_.GetCommandName() -eq 'Initialize-SmokeTestRun' }).Count | Should Be 1
            @($commands | Where-Object { $_.GetCommandName() -eq 'Assert-Test' }).Count -gt 0 | Should Be $true
            @($commands | Where-Object { $_.GetCommandName() -eq 'Get-SmokeTestSummary' }).Count -gt 0 | Should Be $true
            @($scriptAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-Check' }, $true)).Count | Should Be 0
        }
    }

    It 'reads both MSIX manifests through the shared archive reader' {
        @(Get-Command Get-MsixArchiveInfo -ErrorAction SilentlyContinue).Count | Should Be 1
        foreach ($relative in 'Test-OmniAccelerANTInstallers.ps1', 'observant/Test-ObservANTMsix.ps1') {
            $ast = Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot (Join-Path '..' $relative))
            $calls = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Get-MsixArchiveInfo' }, $true))
            $calls.Count | Should Be 1
            ($ast.Extent.Text -match 'ZipFile\]::OpenRead') | Should Be $false
        }
    }

    It 'uses the shared directory reset for MSIX signing and staging' {
        Import-BuildModule 'WindowsAppInstallers.Common'
        $source = & (Get-Module WindowsAppInstallers.Common) { (Get-Command Initialize-BuildDirectory -ErrorAction Stop).Source }
        $source | Should Be 'WindowsScripts.Shared'
        $modulePath = if ($env:OMNI_APP_INSTALLERS_SOURCE) { $env:OMNI_APP_INSTALLERS_SOURCE } else { Join-Path $PSScriptRoot '..\modules\WindowsAppInstallers.Common.psm1' }
        $ast = Get-TestScriptAst -ScriptPath $modulePath
        $calls = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Initialize-BuildDirectory' }, $true))
        $calls.Count | Should Be 1
        $parameters = @($calls[0].CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object ParameterName)
        @($parameters | Where-Object { $_ -eq 'Path' }).Count | Should Be 1
        @($parameters | Where-Object { $_ -eq 'Empty' }).Count | Should Be 1
    }

    It 'checks the project license in the built MSI and MSIX through the hub' {
        foreach ($case in @(
                @{ Path = 'Package-OmniAccelerANT.ps1'; Msi = 'NOTICES.Z'; Msix = 'flutter_assets/NOTICES.Z' },
                @{ Path = 'observant/Package-ObservANT.ps1'; Msi = 'NOTICES'; Msix = 'web/assets/NOTICES' }
            )) {
            $ast = Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot (Join-Path '..' $case.Path))
            $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
            $msi = @($commands | Where-Object { $_.GetCommandName() -eq 'Assert-MsiPackageLicense' })
            $msix = @($commands | Where-Object { $_.GetCommandName() -eq 'Assert-PackageLicense' })
            $msi.Count | Should Be 1
            $msix.Count | Should Be 1
            $msi[0].Extent.Text.Contains($case.Msi) | Should Be $true
            $msix[0].Extent.Text.Contains($case.Msix) | Should Be $true
            $msi[0].Extent.Text.Contains("'LICENSE'") | Should Be $true
            $msix[0].Extent.Text.Contains("'LICENSE'") | Should Be $true
        }
    }

    It 'copies wheel-matched ONNX texts and checks every Windows package' {
        # The host-side app packager takes the texts the image build matched and stamped; ObservANT packs in the image.
        foreach ($case in @(
                @{ Path = 'Package-OmniAccelerANT.ps1'; Checks = 2; Name = 'Resolve-RunnerOrtLicense'; Text = '-RunnerDir $AppDir' },
                @{ Path = 'observant/Package-ObservANT.ps1'; Checks = 3; Name = 'Copy-OrtWheelLicenses'; Text = 'Get-OrtChainWheelStore' }
            )) {
            $ast = Get-TestScriptAst -ScriptPath (Join-Path $PSScriptRoot (Join-Path '..' $case.Path))
            $commands = @(Get-TestAstCommands -Ast $ast -Name $case.Name)
            $checks = @(Get-TestAstCommands -Ast $ast -Name 'Assert-OrtWheelLicensesInPackage')
            $commands.Count | Should Be 1
            $commands[0].Extent.Text.Contains($case.Text) | Should Be $true
            @(Get-TestAstCommands -Ast $ast -Name 'Copy-OrtWheelLicenses').Count | Should Be ([int]($case.Name -eq 'Copy-OrtWheelLicenses'))
            $checks.Count | Should Be $case.Checks
            @($checks | Where-Object { $_.Extent.Text.Contains('-Format msi') -and $_.Extent.Text.Contains('-WixPath $fragment') }).Count | Should Be 1
            @($checks | Where-Object { $_.Extent.Text.Contains('-Format archive') }).Count | Should Be ($case.Checks - 1)
        }
    }

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
