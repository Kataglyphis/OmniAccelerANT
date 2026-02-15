<#
.SYNOPSIS
  Configurable Windows build script for the Kataglyphis project with logging.

.DESCRIPTION
  Run with defaults or pass parameters to override workspace path and other options.
  Example:
    .\build-windows.ps1 -WorkspaceDir "D:\dev\kataglyphis" -SkipFlutterBuild
    .\build-windows.ps1 -LogDir "build_logs" -StopOnError
#>

[CmdletBinding()]
param(
    [string] $WorkspaceDir = $PWD.Path,
    [string] $BuildDirRelease = "build/windows/x64/runner",
    [string] $RustCrateDir = "ExternalLib\Kataglyphis-RustProjectTemplate",
    [string] $RustDllName = "kataglyphis_rustprojecttemplate.dll",
    [string] $CMakeGenerator = "Ninja",
    [string] $CMakeBuildType = "Release",
    [string] $LogDir = "logs",
    [switch] $SkipTests,
    [switch] $SkipFlutterBuild,
    [switch] $ContinueOnError,
    [switch] $StopOnError,
    [switch] $CodeQL
)

# ==================== FIX: RESOLVE WORKSPACE FIRST ====================
# Move this block from "Main Script" to here (top of execution)
try {
    $Workspace = (Resolve-Path -Path $WorkspaceDir -ErrorAction Stop).Path
} catch {
    Write-Host "Workspace path doesn't exist, creating: $WorkspaceDir"
    New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
    $Workspace = (Resolve-Path -Path $WorkspaceDir).Path
}
# ======================================================================

#region ==================== LOGGING INFRASTRUCTURE ====================

$script:LogWriter = $null
$script:LogPath = $null

# Results tracking

$script:Results = @{
    Succeeded = New-Object System.Collections.Generic.List[string]
    Failed    = New-Object System.Collections.Generic.List[string]
    Errors    = @{}
}

function Open-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parentDir = Split-Path -Parent $Path
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }

    $fileStream = New-Object System.IO.FileStream(
        $Path,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite
    )
    $script:LogWriter = New-Object System.IO.StreamWriter($fileStream, [System.Text.Encoding]::UTF8)
    $script:LogWriter.AutoFlush = $true
    $script:LogPath = $Path
}

function Close-Log {
    if ($script:LogWriter) {
        try {
            $script:LogWriter.Flush()
            $script:LogWriter.Dispose()
        } catch {
            # ignore
        } finally {
            $script:LogWriter = $null
        }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    Write-Host $Message
    if ($script:LogWriter) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        $script:LogWriter.WriteLine("[$timestamp] $Message")
    }
}

function Write-LogWarning {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ($Message) {
        Write-Warning $Message
        if ($script:LogWriter) {
            $timestamp = Get-Date -Format "HH:mm:ss"
            $script:LogWriter.WriteLine("[$timestamp] WARNING: $Message")
        }
    } else {
        Write-Host ""
        if ($script:LogWriter) {
            $script:LogWriter.WriteLine("")
        }
    }
}

function Write-LogError {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ($Message) {
        Write-Host $Message -ForegroundColor Red
        if ($script:LogWriter) {
            $timestamp = Get-Date -Format "HH:mm:ss"
            $script:LogWriter.WriteLine("[$timestamp] ERROR: $Message")
        }
    } else {
        Write-Host ""
        if ($script:LogWriter) {
            $script:LogWriter.WriteLine("")
        }
    }
}

function Write-LogSuccess {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ($Message) {
        Write-Host $Message -ForegroundColor Green
        if ($script:LogWriter) {
            $timestamp = Get-Date -Format "HH:mm:ss"
            $script:LogWriter.WriteLine("[$timestamp] SUCCESS: $Message")
        }
    } else {
        Write-Host ""
        if ($script:LogWriter) {
            $script:LogWriter.WriteLine("")
        }
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory)]
        [string]$File,
        [string[]]$Args = @(),
        [switch]$IgnoreExitCode
    )

    $cmdLine = if ($Args -and $Args.Count) { "$File $($Args -join ' ')" } else { $File }
    Write-Log "CMD: $cmdLine"

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $global:LASTEXITCODE = 0
    
    try {
        & $File @Args 2>&1 | ForEach-Object {
            $line = $_
            if ($null -eq $line) { return }
            Write-Log ([string]$line)
        }
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -and -not $IgnoreExitCode) {
            throw "Command failed with exit code ${exitCode}: $cmdLine"
        }
        return $exitCode
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)]
        [string]$StepName,
        [Parameter(Mandatory)]
        [scriptblock]$Script,
        [switch]$Critical
    )

    Write-Log ""
    Write-Log ">>> Starting: $StepName"
    Write-Log ("=" * 60)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        & $Script
        $stopwatch.Stop()
        $script:Results.Succeeded.Add($StepName) | Out-Null
        Write-LogSuccess "<<< Completed: $StepName (Duration: $($stopwatch.Elapsed.ToString('mm\:ss\.fff')))"
        return $true
    } catch {
        $stopwatch.Stop()
        $errorMessage = $_.Exception.Message
        $script:Results.Failed.Add($StepName) | Out-Null
        $script:Results.Errors[$StepName] = $errorMessage
        Write-LogError "<<< FAILED: $StepName (Duration: $($stopwatch.Elapsed.ToString('mm\:ss\.fff')))"
        Write-LogError "    Error: $errorMessage"

        if ($_.ScriptStackTrace) {
            Write-Log "    Stack: $($_.ScriptStackTrace)"
        }

        if ($StopOnError -and $Critical) {
            throw "Critical step '$StepName' failed: $errorMessage"
        }

        return $false
    }
}

function Invoke-Optional {
    param(
        [scriptblock]$Script,
        [string]$Name
    )

    try {
        & $Script
    } catch {
        Write-LogWarning "$Name failed, continuing. Details: $($_.Exception.Message)"
    }
}

function Write-Summary {
    Write-Log ""
    Write-Log ("=" * 60)
    Write-Log "=== BUILD PIPELINE SUMMARY ==="
    Write-Log ("=" * 60)
    Write-Log ""

    if ($script:Results.Succeeded.Count -gt 0) {
        Write-LogSuccess "SUCCEEDED ($($script:Results.Succeeded.Count)):"
        foreach ($step in $script:Results.Succeeded) {
            Write-LogSuccess "  [OK] $step"
        }
    }

    Write-Log ""

    if ($script:Results.Failed.Count -gt 0) {
        Write-LogError "FAILED ($($script:Results.Failed.Count)):"
        foreach ($step in $script:Results.Failed) {
            Write-LogError "  [X] $step"
            Write-LogError "      Error: $($script:Results.Errors[$step])"
        }
    }

    Write-Log ""
    $total = $script:Results.Succeeded.Count + $script:Results.Failed.Count
    $successRate = if ($total -gt 0) { [math]::Round(($script:Results.Succeeded.Count / $total) * 100, 1) } else { 0 }
    Write-Log "Total: $total steps, $($script:Results.Succeeded.Count) succeeded, $($script:Results.Failed.Count) failed ($($successRate)% success rate)"
    Write-Log ""

    if ($script:LogPath) {
        Write-Log "Full log available at: $script:LogPath"
    }

    if ($script:Results.Failed.Count -gt 0) {
        Write-LogWarning "Pipeline completed with errors!"
    } else {
        Write-LogSuccess "Pipeline completed successfully!"
    }
}

#endregion

#region ==================== CODEQL ORCHESTRATION ====================

if ($CodeQL) {
    Write-Log "=== CodeQL Mode Active ==="
    
    # 1. Setup CodeQL CLI
    $CodeQLUrl = "https://github.com/github/codeql-cli-binaries/releases/latest/download/codeql-win64.zip"
    $CodeQLDir = Join-Path $Workspace "codeql-cli"
    $CodeQLExe = Join-Path $CodeQLDir "codeql\codeql.exe"
    
    if (-not (Test-Path $CodeQLExe)) {
        Write-Log "Downloading CodeQL CLI..."
        New-Item -ItemType Directory -Force -Path $CodeQLDir | Out-Null
        $ZipPath = Join-Path $CodeQLDir "codeql.zip"
        Invoke-WebRequest -Uri $CodeQLUrl -OutFile $ZipPath
        Expand-Archive -Path $ZipPath -DestinationPath $CodeQLDir -Force
    }
    
    # 2. Define Paths
    $CodeQLDb = Join-Path $Workspace "codeql_db"
    $SarifOutput = Join-Path $Workspace "codeql-results.sarif"
    
    # 3. Construct the "Inner" Build Command
    # We recall this same script, but REMOVE the -CodeQL switch to avoid infinite loops
    $CurrentArgs = $MyInvocation.BoundParameters.GetEnumerator() | 
                   Where-Object { $_.Key -ne "CodeQL" } | 
                   ForEach-Object { "-$($_.Key) `"$($_.Value)`"" }
    
    $InnerCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" $CurrentArgs"
    
    # 4. Create Database (The "Trace")
    Write-Log "Initializing CodeQL Database and Tracing Build..."
    if (Test-Path $CodeQLDb) { Remove-Item -Recurse -Force $CodeQLDb }
    
    & $CodeQLExe database create $CodeQLDb `
        --language="cpp,rust" `
        --source-root=$Workspace `
        --command=$InnerCommand `
        --overwrite
        
    if ($LASTEXITCODE -ne 0) { throw "CodeQL Database creation failed" }

    # 5. Analyze Database
    Write-Log "Analyzing Database..."
    & $CodeQLExe database analyze $CodeQLDb $SarifOutput `
        --format=sarif-latest `
        --output=$SarifOutput
        
    if ($LASTEXITCODE -ne 0) { throw "CodeQL Analysis failed" }
    
    Write-LogSuccess "CodeQL Analysis Complete. Results at: $SarifOutput"
    exit 0 # Exit the outer "wrapper" script here
}

#endregion

#region ==================== HELPER FUNCTIONS ====================

function Remove-BuildRoot {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Log "Build root does not exist: $Path"
        return $true
    }

    Write-Log "Terminating potentially locking processes..."
    @("flutter", "dart", "msbuild", "devenv", "ninja", "cmake") | ForEach-Object {
        Get-Process $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 3

    for ($i = 1; $i -le 3; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Log "Build directory removed: $Path"
            return $true
        } catch {
            Write-LogWarning "Attempt $i/3 failed: $($_.Exception.Message)"
            if ($i -lt 3) { Start-Sleep -Seconds 2 }
        }
    }
    return $false
}

#endregion

#region ==================== MAIN SCRIPT ====================

# Error handling preference

if ($ContinueOnError) {
    $ErrorActionPreference = "Continue"
} else {
    $ErrorActionPreference = "Stop"
}

# Initialize logging

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDirPath = Join-Path $Workspace $LogDir
New-Item -ItemType Directory -Force $logDirPath | Out-Null
$logPath = Join-Path $logDirPath "build-windows-$timestamp.log"

Open-Log -Path $logPath

# Derived paths

$BuildRoot = Join-Path $Workspace "build"
$BuildDirFull = Join-Path $Workspace ($BuildDirRelease -replace '/','\')
$WindowsSrc = Join-Path $Workspace "windows"
$CMakeBuildDir = Join-Path $Workspace "build\windows\x64"
$RustDir = Join-Path $Workspace $RustCrateDir
$DllSource = Join-Path $RustDir "target\release\$RustDllName"
$DllDestDir = Join-Path $Workspace "build\windows\x64\plugins\$($RustDllName -replace '\.dll$','')"
$NativeAssetsDir = Join-Path $Workspace "build\native_assets\windows"

$env:BUILD_DIR_RELEASE = $BuildDirRelease

try {
    Write-Log "=== Kataglyphis Windows Build Script ==="
    Write-Log "Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Logging to: $logPath"
    Write-Log ""
    Write-Log "=== Configuration ==="
    Write-Log "Workspace:        $Workspace"
    Write-Log "BuildDirRelease:  $BuildDirRelease"
    Write-Log "BuildDirFull:     $BuildDirFull"
    Write-Log "CMakeBuildDir:    $CMakeBuildDir"
    Write-Log "CMakeGenerator:   $CMakeGenerator"
    Write-Log "CMakeBuildType:   $CMakeBuildType"
    Write-Log "RustDir:          $RustDir"
    Write-Log "Rust DLL source:  $DllSource"
    Write-Log "Rust DLL dest:    $DllDestDir"
    Write-Log "SkipTests:        $SkipTests"
    Write-Log "SkipFlutterBuild: $SkipFlutterBuild"
    Write-Log "ContinueOnError:  $ContinueOnError"
    Write-Log "StopOnError:      $StopOnError"
    Write-Log ("=" * 60)

    # --- Step 1: Environment Check ---
    Invoke-Step -StepName "Environment Check" -Script {
        Invoke-Optional -Name "cmake" -Script { 
            Invoke-External -File "cmake" -Args @("--version") 
        }
        Invoke-Optional -Name "clang-cl" -Script { 
            Invoke-External -File "clang-cl" -Args @("--version") 
        }
        Invoke-Optional -Name "flutter" -Script { 
            Invoke-External -File "flutter" -Args @("--version") 
        }
        Invoke-Optional -Name "cargo" -Script { 
            Invoke-External -File "cargo" -Args @("--version") 
        }
        Invoke-Optional -Name "ninja" -Script { 
            Invoke-External -File "ninja" -Args @("--version") 
        }
    }

    # --- Step 2: Git Configuration ---
    Invoke-Step -StepName "Git Configuration" -Script {
        Invoke-External -File "git" -Args @("config", "--global", "core.longpaths", "true") -IgnoreExitCode
    }

    # --- Step 3: Flutter Setup ---
    if (-not $SkipFlutterBuild) {
        Invoke-Step -StepName "Flutter Dependencies" -Critical -Script {
            Invoke-External -File "flutter" -Args @("pub", "get")
            Invoke-External -File "flutter" -Args @("config", "--enable-windows-desktop")
        }
    } else {
        Write-Log "Skipping Flutter dependency steps (SkipFlutterBuild set)."
    }

    # --- Step 4-6: Code Quality & Tests ---
    if (-not $SkipTests) {
        Invoke-Step -StepName "Dart Format Verification" -Script {
            # Only format Dart-relevant directories (exclude ExternalLib)
            $dartDirs = @("lib", "test", "bin", "integration_test") |
                Where-Object { Test-Path (Join-Path $Workspace $_) }

            if ($dartDirs.Count -eq 0) {
                Write-Log "No Dart directories found to format."
                return
            }

            Write-Log "Formatting directories: $($dartDirs -join ', ')"
            foreach ($dir in $dartDirs) {
                # We use Invoke-Optional here too, so formatting errors don't stop the build
                Invoke-Optional -Name "Format $dir" -Script {
                    Invoke-External -File "dart" -Args @("format", "--output=none", "--set-exit-if-changed", $dir)
                }
            }
        }

        Invoke-Step -StepName "Dart Analysis" -Script {
            Invoke-Optional -Name "Dart Analysis" -Script {
                Invoke-External -File "dart" -Args @("analyze")
            }
        }

        Invoke-Step -StepName "Flutter Tests" -Script {
            Invoke-Optional -Name "Flutter Tests" -Script {
                Invoke-External -File "flutter" -Args @("test")
            }
        }
    } else {
        Write-Log "Skipping format/analyze/tests (SkipTests set)."
    }

    # --- Step 7: Flutter Ephemeral Build ---
    if (-not $SkipFlutterBuild) {
        Invoke-Step -StepName "Flutter Ephemeral Build (C++ Headers)" -Script {
            Invoke-External -File "flutter" -Args @("build", "windows", "--release") -IgnoreExitCode
        }
    }

    # --- Step 8: Clean Build Directory ---
    Invoke-Step -StepName "Clean Build Directory" -Script {
        $removed = Remove-BuildRoot -Path $BuildRoot
        if (-not $removed -and -not $ContinueOnError) {
            throw "Failed to remove build root: $BuildRoot"
        }
    }

    # Patch permission_handler_windows for clang-cl compatibility
    $pluginFile = "windows\flutter\ephemeral\.plugin_symlinks\permission_handler_windows\windows\permission_handler_windows_plugin.cpp"
    if (Test-Path $pluginFile) {
        Write-Host "Patching permission_handler_windows..."
        (Get-Content $pluginFile) -replace 'result->Success\(requestResults\);', 'result->Success(flutter::EncodableValue(requestResults));' | Set-Content $pluginFile
    }

    # --- Step 9: CMake Configure ---
    Invoke-Step -StepName "CMake Configure" -Critical -Script {
        $cmakeArgs = @(
            $WindowsSrc
            "-B", $CMakeBuildDir
            "-G", $CMakeGenerator
            "-DCMAKE_BUILD_TYPE=$CMakeBuildType"
            "-DCMAKE_INSTALL_PREFIX=$BuildDirFull"
            "-DFLUTTER_TARGET_PLATFORM=windows-x64"
            "-DCMAKE_CXX_COMPILER=clang-cl"
            "-DCMAKE_C_COMPILER=clang-cl"
            "-DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc"
        )
        Invoke-External -File "cmake" -Args $cmakeArgs
    }

    # --- Step 10: Rust Build ---
    Invoke-Step -StepName "Rust Crate Build" -Script {
        if (-not (Test-Path $RustDir)) {
            throw "Rust crate directory not found: $RustDir"
        }
        
        Push-Location $RustDir
        try {
            Invoke-Optional -Name "flutter_rust_bridge_codegen install" -Script {
                Invoke-External -File "cargo" -Args @("install", "flutter_rust_bridge_codegen")
            }
            Invoke-External -File "cargo" -Args @("build", "--release")
        } finally {
            Pop-Location
        }
    }

    # --- Step 11: Copy Rust DLL ---
    Invoke-Step -StepName "Copy Rust DLL" -Script {
        if (-not (Test-Path $DllSource)) {
            throw "Rust DLL not found at $DllSource"
        }
        New-Item -ItemType Directory -Force -Path $DllDestDir | Out-Null
        Copy-Item -Path $DllSource -Destination $DllDestDir -Force
        Write-Log "Rust DLL copied to $DllDestDir"
    }

    # --- Step 12: Native Assets Fix ---
    Invoke-Step -StepName "Native Assets Directory Fix" -Script {
        if (Test-Path $NativeAssetsDir) {
            $item = Get-Item -LiteralPath $NativeAssetsDir -Force
            if (-not $item.PSIsContainer) {
                Write-Log "Path exists but is NOT a directory. Replacing: $NativeAssetsDir"
                Remove-Item -LiteralPath $NativeAssetsDir -Force
                New-Item -ItemType Directory -Path $NativeAssetsDir | Out-Null
            } else {
                Write-Log "Path is already a directory: $NativeAssetsDir"
            }
        } else {
            Write-Log "Creating directory: $NativeAssetsDir"
            New-Item -ItemType Directory -Path $NativeAssetsDir | Out-Null
        }
    }

    # --- Step 13: CMake Build & Install ---
    Invoke-Step -StepName "CMake Build & Install" -Critical -Script {
        Invoke-External -File "cmake" -Args @(
            "--build", $CMakeBuildDir,
            "--config", $CMakeBuildType,
            "--target", "install",
            "--verbose"
        )
    }

    Write-Log ""
    Write-LogSuccess "=== Build Complete ==="
    Write-Log "Build artifacts located at: $(Join-Path $Workspace $env:BUILD_DIR_RELEASE)"

} catch {
    Write-LogError "Unhandled critical error: $($_.Exception.Message)"
    if ($_.ScriptStackTrace) {
        Write-LogError "Stack trace: $($_.ScriptStackTrace)"
    }
} finally {
    Write-Summary
    Close-Log
    
    if ($script:Results.Failed.Count -gt 0) {
        exit 1
    }
}

#endregion
