<#
.SYNOPSIS
  Configure GStreamer environment variables and PATH on Windows.

.DESCRIPTION
  - Updates current session PATH to include GStreamer bin.
  - Optionally persists environment variables (User or Machine).
  - Sets GSTREAMER_ROOT_X86 or GSTREAMER_ROOT_X86_64 depending on Architecture param.
  - Optional plugin path settings.
  - Backs up existing PATH before persisting.
  - Removes old GStreamer bin entries to avoid duplicates.
#>

param(
    [string]$GStreamerRoot = $env:GSTREAMER_ROOT,
    [ValidateSet("x86","x86_64","both")]
    [string]$Architecture = "x86_64",
    [ValidateSet("None","User","Machine")]
    [string]$PersistScope = "Machine",    # "None", "User", or "Machine"
    [string[]]$PluginPaths = @(),     # Additional plugin folders to add to GST_PLUGIN_PATH
    [string]$PluginSystemPath = $null, # If set, sets GST_PLUGIN_SYSTEM_PATH to this value
    [switch]$RemoveOldGStreamerBins = $false, # Remove older GStreamer bin entries from PATH before adding
    [switch]$Force                     # Force overwrite without extra prompts (not used interactively here)
)

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Default GStreamer root if not provided (keep your CMake default)
if (-not $GStreamerRoot) {
    $GStreamerRoot = "C:\Program Files\gstreamer\1.0\msvc_x86_64"
}

# Resolve full path (suppress error output)
try {
    $resolved = Resolve-Path -Path $GStreamerRoot -ErrorAction Stop
    $GStreamerRoot = $resolved.ProviderPath
} catch {
    Write-Error "GStreamer root not found or not resolvable. Check the -GStreamerRoot parameter. Error: $($_.Exception.Message)"
    exit 1
}

# Determine which roots to set
$rootsToSet = @()
switch ($Architecture) {
    "x86"      { $rootsToSet += @{Name="GSTREAMER_ROOT_X86"; Path=Join-Path $GStreamerRoot ""} }
    "x86_64"   { $rootsToSet += @{Name="GSTREAMER_ROOT_X86_64"; Path=Join-Path $GStreamerRoot ""} }
    "both"     {
        $rootsToSet += @{Name="GSTREAMER_ROOT_X86_64"; Path=Join-Path $GStreamerRoot ""}
        $x86Candidate = $GStreamerRoot -replace 'msvc_x86_64','msvc_x86'
        if (Test-Path $x86Candidate) { $rootsToSet += @{Name="GSTREAMER_ROOT_X86"; Path=$x86Candidate} }
    }
}

# Pick primary bin to add (prefer x86_64 bin)
$primaryBin = $null
if ($rootsToSet) {
    $preferred = $rootsToSet | Where-Object { $_.Path -like '*msvc_x86_64*' } | Select-Object -First 1
    if (-not $preferred) { $preferred = $rootsToSet[0] }
    $primaryBin = Join-Path $preferred.Path "bin"
}

if (-not (Test-Path $primaryBin)) {
    Write-Error "GStreamer bin folder not found: $primaryBin"
    exit 1
}

function Remove-GStreamerBinsFromPath([string]$path) {
    if (-not $path) { return $path }
    $parts = $path -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
    # Match typical gstreamer install bin folders
    $filtered = $parts | Where-Object {
        -not ($_ -match '(?i)gstreamer.*\\msvc.*\\bin') -and -not ($_ -match '(?i)gstreamer.*\\1\.0.*\\bin')
    }
    return ($filtered -join ';')
}

# 1) Update current session PATH (no duplicates)
$sessionPathParts = $env:PATH -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
if ($RemoveOldGStreamerBins) {
    $sessionPath = Remove-GStreamerBinsFromPath($env:PATH)
    $sessionPathParts = $sessionPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}
if ($sessionPathParts -notcontains $primaryBin) {
    $env:PATH = "$primaryBin;$($sessionPathParts -join ';')"
    Write-Host "Updated PATH for this session with: $primaryBin"
} else {
    Write-Host "Session PATH already contains: $primaryBin"
}

# 2) Persist environment variables (User or Machine) if requested
if ($PersistScope -ne "None") {
    if ($PersistScope -eq "Machine" -and -not (Test-IsAdmin)) {
        Write-Warning "Persisting to Machine scope requires elevation. Attempting to continue may fail."
    }

    # Backup existing PATH for chosen scope
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupFile = Join-Path $env:TEMP "path-backup-$PersistScope-$timestamp.txt"
    try {
        $oldPath = [Environment]::GetEnvironmentVariable("PATH", $PersistScope)
        $oldPath | Out-File -FilePath $backupFile -Encoding UTF8
        Write-Host "Backed up existing $PersistScope PATH to: $backupFile"
    } catch {
        # <-- FIXED: wrap PersistScope in subexpression so colon after var doesn't confuse parser
        Write-Warning "Failed to back up existing PATH for scope $($PersistScope): $($_.Exception.Message)"
    }

    # Prepare new persistent PATH: remove old gstreamer bins and prepend primaryBin
    $cleanPath = Remove-GStreamerBinsFromPath($oldPath)
    $newPath = $primaryBin + ";" + $cleanPath.Trim(';')
    $newPathParts = $newPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Select-Object -Unique
    $newPathFinal = ($newPathParts -join ';')

    try {
        [Environment]::SetEnvironmentVariable("PATH", $newPathFinal, $PersistScope)
        Write-Host "Persisted GStreamer bin in $PersistScope PATH: $primaryBin"
    } catch {
        Write-Error "Failed to set PATH in $PersistScope scope: $($_.Exception.Message)"
    }

    # Persist the root variables
    foreach ($r in $rootsToSet) {
        try {
            [Environment]::SetEnvironmentVariable($r.Name, $r.Path, $PersistScope)
            Write-Host "Set $($r.Name) = $($r.Path) in $PersistScope scope"
        } catch {
            Write-Error "Failed to set $($r.Name) in $PersistScope scope: $($_.Exception.Message)"
        }
    }

    # Persist plugin variables if requested
    if ($PluginPaths -and $PluginPaths.Count -gt 0) {
        try {
            $existingPluginPath = [Environment]::GetEnvironmentVariable("GST_PLUGIN_PATH", $PersistScope)
        } catch {
            $existingPluginPath = $null
        }
        $merged = @()
        if ($existingPluginPath) { $merged += ($existingPluginPath -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } }
        $merged += $PluginPaths
        $merged = $merged | Select-Object -Unique
        $mergedFinal = ($merged -join ';')
        try {
            [Environment]::SetEnvironmentVariable("GST_PLUGIN_PATH", $mergedFinal, $PersistScope)
            Write-Host "Set GST_PLUGIN_PATH in $PersistScope scope to: $mergedFinal"
        } catch {
            Write-Error "Failed to set GST_PLUGIN_PATH in $PersistScope scope: $($_.Exception.Message)"
        }
    }

    if ($PluginSystemPath) {
        try {
            [Environment]::SetEnvironmentVariable("GST_PLUGIN_SYSTEM_PATH", $PluginSystemPath, $PersistScope)
            Write-Host "Set GST_PLUGIN_SYSTEM_PATH in $PersistScope scope to: $PluginSystemPath"
        } catch {
            Write-Error "Failed to set GST_PLUGIN_SYSTEM_PATH in $PersistScope scope: $($_.Exception.Message)"
        }
    }

    Write-Host "Note: Applications and new shells will pick up new environment variables after restart or logoff/login."
}

# Final summary
Write-Host "---- Summary ----"
Write-Host "Session PATH starts with: $primaryBin"
if ($PersistScope -ne "None") {
    Write-Host "Persisted to: $PersistScope (backup at $backupFile)"
} else {
    Write-Host "No persistence requested (session-only change)."
}
if ($PluginPaths -and $PluginPaths.Count -gt 0) { Write-Host "GST_PLUGIN_PATH updated with: $($PluginPaths -join ', ')" }
if ($PluginSystemPath) { Write-Host "GST_PLUGIN_SYSTEM_PATH set to: $PluginSystemPath" }
# build a readable string for printing
$rootsStr = ($rootsToSet | ForEach-Object { "{0}={1}" -f $_.Name, $_.Path }) -join '; '
Write-Host "GStreamer roots set: $rootsStr"
Write-Host "-----------------"

# Return object for programmatic use
[PSCustomObject]@{
    PrimaryBin = $primaryBin
    PersistScope = $PersistScope
    Roots = $rootsToSet
    PluginPaths = $PluginPaths
    PluginSystemPath = $PluginSystemPath
    BackupFile = $backupFile
}
