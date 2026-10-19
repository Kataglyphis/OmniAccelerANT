#requires -Version 7.0

# One lane at a time per checkout (AGENTS.md § 5), across nerdctl and Stevedore; callers import the hub's WindowsContainerBuild.Reuse.

Set-StrictMode -Version Latest

$script:LinuxLanePattern = 'kataglyphis-linux-lane-*'
$script:WindowsBuildContainer = 'omniaccelerant-agentic-build'

function Select-LinuxLaneConflict {
    # The running Linux lane containers other than -Self. Pure: the caller lists the names.
    param(
        [AllowEmptyCollection()][string[]] $RunningNames = @(),
        [string] $Self = ''
    )
    return @($RunningNames | Where-Object { $_ -like $script:LinuxLanePattern -and $_ -ne $Self })
}

function Test-ActiveBuildProcess {
    # A build is any pwsh process: the idle reusable container runs only cmd.exe and PING.EXE.
    param([AllowEmptyCollection()][string[]] $ProcessLines = @())
    return [bool](@($ProcessLines | Where-Object { $_ -match '(?i)(^|[\s\\/])pwsh(\.exe)?(\s|$)' }).Count)
}

function Get-RunningLinuxLane {
    # Empty when nerdctl is missing or its VM is down: then no Linux lane can be running.
    param([string] $Self = '', [string] $Nerdctl = '')
    if (-not $Nerdctl) { $Nerdctl = Resolve-NerdctlExe -AllowMissing }
    if (-not $Nerdctl) { return @() }
    $names = & $Nerdctl 'ps' '--format' '{{.Names}}' 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @(Select-LinuxLaneConflict -RunningNames @($names) -Self $Self)
}

function Test-WindowsBuildActive {
    # An unreadable process list counts as building: a guard that cannot see must not wave a lane through.
    param([string] $DockerExe = '', [string] $Name = $script:WindowsBuildContainer)
    if (-not $DockerExe) { $DockerExe = try { Resolve-DockerExe } catch { '' } }
    if (-not $DockerExe) { return $false }
    $running = & $DockerExe 'inspect' '-f' '{{.State.Running}}' $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or "$running".Trim() -ne 'true') { return $false }
    $top = & $DockerExe 'top' $Name 2>$null
    if ($LASTEXITCODE -ne 0) { return $true }
    return (Test-ActiveBuildProcess -ProcessLines @($top))
}

function Get-LaneConflictMessage {
    param([Parameter(Mandatory)][string[]] $Busy)
    return ("Another lane is running: $($Busy -join ', '). Two lanes on one checkout overwrite " +
        "each other's generated files (AGENTS.md § 5). Wait for it to exit, or pass -Force when " +
        'you know it is idle.')
}

Export-ModuleMember -Function Select-LinuxLaneConflict, Test-ActiveBuildProcess,
    Get-RunningLinuxLane, Test-WindowsBuildActive, Get-LaneConflictMessage
