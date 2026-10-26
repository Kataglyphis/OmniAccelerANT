#requires -Version 7.0

# This guards shared module wiring and byte validation; it does not install MSI or MSIX packages.
Describe 'Installer shared Windows checks' {
    . (Join-Path $PSScriptRoot '..\Resolve-BuildModule.ps1')
    Import-BuildModule @('WindowsTargetArch.Common', 'WindowsSmokeTest.Common')

    It 'parses and calls the shared target facts and PE reader' {
        $installer = Join-Path $PSScriptRoot '..\Test-OmniAccelerANTInstallers.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors | Where-Object { $_ }).Count | Should Be 0
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        @($commands | Where-Object { $_.GetCommandName() -eq 'Import-BuildModule' -and $_.Extent.Text -match "WindowsTargetArch\.Common" }).Count | Should Be 1
        @($commands | Where-Object { $_.GetCommandName() -eq 'Get-PeMachineType' }).Count | Should Be 1
        @($commands | Where-Object { $_.GetCommandName() -eq 'Get-PeFileMachine' }).Count | Should Be 1
        @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PeMachine' }, $true)).Count | Should Be 0
    }

    It 'reads x64 and arm64 target facts and rejects a malformed binary' {
        Get-PeMachineType -Arch x64 | Should Be 0x8664
        Get-PeMachineType -Arch arm64 | Should Be 0xAA64
        $bytes = [byte[]]::new(134)
        $bytes[0] = 0x4D
        $bytes[1] = 0x5A
        [BitConverter]::GetBytes([int]0x80).CopyTo($bytes, 0x3C)
        $bytes[0x80] = 0x50
        $bytes[0x81] = 0x45
        [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes, 0x84)
        $path = Join-Path $TestDrive 'fixture.exe'
        [IO.File]::WriteAllBytes($path, $bytes)
        Get-PeFileMachine -Path $path | Should Be 0x8664
        $bytes[0x80] = 0
        [IO.File]::WriteAllBytes($path, $bytes)
        $message = try { Get-PeFileMachine -Path $path | Out-Null; '' } catch { $_.Exception.Message }
        ($message -match 'not a PE file') | Should Be $true
    }

    It 'uses the hub assertion runner in all three installer checks' {
        foreach ($relative in 'Test-OmniAccelerANTInstallers.ps1', 'observant/Test-ObservANTWindows.ps1', 'observant/Test-ObservANTMsix.ps1') {
            $path = Join-Path $PSScriptRoot (Join-Path '..' $relative)
            $tokens = $null
            $errors = $null
            $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            @($errors | Where-Object { $_ }).Count | Should Be 0
            $commands = @($scriptAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
            @($commands | Where-Object { $_.GetCommandName() -eq 'Import-BuildModule' -and $_.Extent.Text -match 'WindowsSmokeTest\.Common' }).Count | Should Be 1
            @($commands | Where-Object { $_.GetCommandName() -eq 'Initialize-SmokeTestRun' }).Count | Should Be 1
            @($commands | Where-Object { $_.GetCommandName() -eq 'Assert-Test' }).Count -gt 0 | Should Be $true
            @($commands | Where-Object { $_.GetCommandName() -eq 'Get-SmokeTestSummary' }).Count -gt 0 | Should Be $true
            @($scriptAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-Check' }, $true)).Count | Should Be 0
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
