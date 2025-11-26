param(
  [string]$GStreamerVersion = "1.26.6"
)

# Force TLS1.2 for download
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$baseUrl = "https://gstreamer.freedesktop.org/data/pkg/windows/$GStreamerVersion/msvc"
$runtimeMsiUrl = "$baseUrl/gstreamer-1.0-msvc-x86_64-$GStreamerVersion.msi"
$develMsiUrl = "$baseUrl/gstreamer-1.0-devel-msvc-x86_64-$GStreamerVersion.msi"

$runtimeMsi = Join-Path $env:TEMP "gstreamer-runtime.msi"
$develMsi = Join-Path $env:TEMP "gstreamer-devel.msi"

# Download runtime MSI
Write-Host "Downloading runtime from $runtimeMsiUrl to $runtimeMsi"
try {
  Invoke-WebRequest -Uri $runtimeMsiUrl -OutFile $runtimeMsi -ErrorAction Stop
} catch {
  Write-Error "Runtime download failed: $_"
  exit 1
}

# Download devel MSI
Write-Host "Downloading devel from $develMsiUrl to $develMsi"
try {
  Invoke-WebRequest -Uri $develMsiUrl -OutFile $develMsi -ErrorAction Stop
} catch {
  Write-Error "Devel download failed: $_"
  exit 1
}

# Install runtime MSI first with COMPLETE option
Write-Host "Installing runtime MSI with COMPLETE option..."
$runtimeArgs = "/i `"$runtimeMsi`" /qn /norestart ADDLOCAL=ALL"
$p = Start-Process -FilePath "msiexec.exe" -ArgumentList $runtimeArgs -Wait -PassThru

if ($p.ExitCode -ne 0) {
  Write-Error "Runtime msiexec failed with exit code $($p.ExitCode)"
  exit $p.ExitCode
}

# Install devel MSI
Write-Host "Installing devel MSI..."
$develArgs = "/i `"$develMsi`" /qn /norestart"
$p = Start-Process -FilePath "msiexec.exe" -ArgumentList $develArgs -Wait -PassThru

if ($p.ExitCode -ne 0) {
  Write-Error "Devel msiexec failed with exit code $($p.ExitCode)"
  exit $p.ExitCode
}

# Common default install root for the official MSIs:
$groot = "C:\Program Filesgstreamer\1.0\x86_64"

# If default path doesn't exist, try to discover gst-launch-1.0
if (-not (Test-Path $groot)) {
  $cmd = Get-Command gst-launch-1.0 -ErrorAction SilentlyContinue
  if ($cmd) {
    $groot = Split-Path $cmd.Path -Parent -Parent
  } else {
    $found = Get-ChildItem -Path 'C:\' -Filter 'gst-launch-1.0.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $groot = Split-Path $found.Directory.FullName -Parent }
  }
}

if (-not (Test-Path $groot)) {
  Write-Error "Could not locate GStreamer install folder after MSI install."
  exit 1
}

Write-Host "GStreamer root: $groot"

# Export variables for GitHub Actions (if running in GH Actions)
if ($env:GITHUB_ENV) {
  "GSTREAMER_1_0_ROOT_X86_64=$groot" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  $newPath = "$groot\bin;$env:PATH"
  "PATH=$newPath" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
} else {
  # For local runs: set PATH for this process
  [Environment]::SetEnvironmentVariable('GSTREAMER_1_0_ROOT_X86_64', $groot, 'Process')
  $env:PATH = "$groot\bin;$env:PATH"
}

Write-Host "GStreamer installed and environment prepared."