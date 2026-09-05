Set-StrictMode -Version Latest

$script:KataglyphisWindowsBuildConfig = @{
    BuildRootDir          = "build"
    RustDllName           = "kataglyphis_rustprojecttemplate.dll"
    RustPluginSubDir      = "kataglyphis_rustprojecttemplate"
    PluginRelativeDir     = "build/windows/x64/plugins"
    RunnerExeName         = "kataglyphis_inference_engine.exe"
    RunnerExeRelativePath = "build/windows/x64/runner/x64-ClangCL-Windows-Release/kataglyphis_inference_engine.exe"
    RunLogRelativePath    = "run_output.txt"
    CMakeConfiguration    = "x64-ClangCL-Windows-Release"
}

function Get-KataglyphisWindowsBuildConfig {
    return $script:KataglyphisWindowsBuildConfig
}
