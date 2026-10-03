#requires -Version 7.0
# Copyright (c) 2025 Kataglyphis
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
    Copies the toolset's ASan runtime DLL beside the Debug runner the launch smoke starts.
.DESCRIPTION
    Runs inside the family image, whose VS carries Microsoft's ASan runtime; the runner host may not
    (the component is optional). The Debug preset links it, so a missing copy is a load failure, not a warn.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-BuildModule.ps1')
Import-BuildModule @('WindowsTesting.Common')

$asan = Get-AsanRuntimeDll -RuntimeFlavor Msvc
if (-not $asan) { throw 'no MSVC ASan runtime in the image; the Debug preset links it' }
$null = New-Item -ItemType Directory -Force -Path $Destination
Copy-Item -LiteralPath $asan -Destination (Join-Path $Destination 'clang_rt.asan_dynamic-x86_64.dll') -Force
Write-Host "staged $asan -> $Destination"
