#requires -Version 7.0

# PROJECT-SPECIFIC: one lane at a time against this checkout (AGENTS.md § 5). The generated
# files at the root (android/local.properties, .dart_tool, pubspec.lock, the ephemeral plugin
# symlinks) are per-host, and two lanes running together overwrite each other mid-build while
# the failure names the innocent lane. Both drivers ask here, so the guard is two-sided:
#   Invoke-LinuxLane.ps1           refuses while another Linux lane or a Windows build runs
#   Build-Windows-Container.ps1    refuses while a Linux lane runs
#
# The two lanes live on two engines. Linux lanes are Rancher Desktop containers
# (nerdctl, named kataglyphis-linux-lane-*); the Windows build is Stevedore's docker.exe, whose
# reusable container idles on `ping` between builds (WindowsContainerBuild.Reuse), so "it is
# up" is not "it is building": a build is a pwsh process inside it.

Set-StrictMode -Version Latest

$script:LinuxLanePattern = 'kataglyphis-linux-lane-*'
$script:WindowsBuildContainer = 'omniaccelerant-agentic-build'

function Resolve-NerdctlExe {
    # nerdctl on PATH, else Rancher Desktop's copy; $null when neither exists.
    $onPath = (Get-Command 'nerdctl' -ErrorAction SilentlyContinue)?.Source
    if ($onPath) { return $onPath }
    $candidate = Join-Path $env:ProgramFiles 'Rancher Desktop\resources\resources\win32\bin\nerdctl.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

function Select-LinuxLaneConflict {
    # The running Linux lane containers other than -Self. Pure: the caller lists the names.
    param(
        [AllowEmptyCollection()][string[]] $RunningNames = @(),
        [string] $Self = ''
    )
    return @($RunningNames | Where-Object { $_ -like $script:LinuxLanePattern -and $_ -ne $Self })
}

function Test-ActiveBuildProcess {
    # Whether a `docker top` listing shows a build: any pwsh process. The idle reusable
    # container runs cmd.exe and PING.EXE only. Pure: the caller passes the lines.
    param([AllowEmptyCollection()][string[]] $ProcessLines = @())
    return [bool](@($ProcessLines | Where-Object { $_ -match '(?i)(^|[\s\\/])pwsh(\.exe)?(\s|$)' }).Count)
}

function Get-RunningLinuxLane {
    # Running Linux lane containers other than -Self; empty when nerdctl is missing or its
    # VM is down, since then no Linux lane can be running.
    param([string] $Self = '', [string] $Nerdctl = '')
    if (-not $Nerdctl) { $Nerdctl = Resolve-NerdctlExe }
    if (-not $Nerdctl) { return @() }
    $names = & $Nerdctl 'ps' '--format' '{{.Names}}' 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @(Select-LinuxLaneConflict -RunningNames @($names) -Self $Self)
}

function Test-WindowsBuildActive {
    # Whether the reusable Windows build container is running a build. Stevedore absent or the
    # container not running: no. Running but its process list unreadable: yes, because a guard
    # that cannot see must not wave a lane through (-Force exists for that).
    param([string] $DockerExe = '', [string] $Name = $script:WindowsBuildContainer)
    if (-not $DockerExe) {
        $DockerExe = @(
            $env:DOCKER_EXE,
            (Join-Path $env:ProgramFiles 'Stevedore\bin\docker.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
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

Export-ModuleMember -Function Resolve-NerdctlExe, Select-LinuxLaneConflict, Test-ActiveBuildProcess,
    Get-RunningLinuxLane, Test-WindowsBuildActive, Get-LaneConflictMessage
