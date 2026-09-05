Set-StrictMode -Version Latest

$script:KataglyphisWindowsBuildConfig = @{
    BuildRootDir          = "build"
    RustDllName           = "oxidant.dll"
    RustPluginSubDir      = "oxidant"
    PluginRelativeDir     = "build/windows/x64/plugins"
    RunnerExeName         = "omni_accelerant.exe"
    RunnerExeRelativePath = "build/windows/x64/runner/x64-ClangCL-Windows-Release/omni_accelerant.exe"
    RunLogRelativePath    = "run_output.txt"
    CMakeConfiguration    = "x64-ClangCL-Windows-Release"
}

function Get-KataglyphisWindowsBuildConfig {
    return $script:KataglyphisWindowsBuildConfig
}
