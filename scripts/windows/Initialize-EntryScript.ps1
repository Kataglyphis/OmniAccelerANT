#requires -Version 7.0
# Dot-sourced first by entry scripts, so the strict settings and the module resolver land in the caller's scope.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')

function Get-EntryRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
