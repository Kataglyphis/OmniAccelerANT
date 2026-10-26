#requires -Version 7.0
# This checks root selection wiring; it does not run a container build.

Import-Module (Join-Path $PSScriptRoot '..\..\..\third_party\ANTfrastructure\windows\scripts\tests\WindowsContainerInbound.Fixture.psm1') -ErrorAction Stop

Describe 'Windows container inbound reuse' {
    It 'lets the shared runner omit only local root output' {
        Assert-ContainerRootSelection -ScriptPath (Join-Path $PSScriptRoot '..\Build-Windows-Container.ps1') `
            -ExcludeEntries @('build', 'out', 'logs', '.dart_tool', '.venv')
    }
}
