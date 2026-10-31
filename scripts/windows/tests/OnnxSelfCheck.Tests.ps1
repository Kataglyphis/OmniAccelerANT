#requires -Version 7.0

Describe 'Windows packaged ONNX self-check' {
    $check = Join-Path $PSScriptRoot '..\Test-OnnxSelfCheck.ps1'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $source = @'
using System;
using System.IO;
using System.Threading;
class Probe {
    static int Main(string[] args) {
        if (args.Length != 1 || args[0] != "--onnx-check") return 2;
        if (Environment.GetEnvironmentVariable("KATAGLYPHIS_ORT_DEVICE") != "cpu" ||
            Environment.GetEnvironmentVariable("KATAGLYPHIS_ONNX_BACKEND") != "ort") return 3;
        if (Environment.GetEnvironmentVariable("KATAGLYPHIS_ONNX_MODEL") != null ||
            Environment.GetEnvironmentVariable("ONNX_ROOT") != null ||
            Environment.GetEnvironmentVariable("ORT_DYLIB_PATH") != Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "onnxruntime.dll")) return 4;
        if (Directory.GetCurrentDirectory() != AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\')) return 5;
        string windows = Environment.GetEnvironmentVariable("SystemRoot");
        if (Environment.GetEnvironmentVariable("PATH") != Path.Combine(windows, "System32") + ";" + windows) return 6;
        switch (Environment.GetEnvironmentVariable("OMNI_FIXTURE_MODE")) {
            case "fail": return 17;
            case "hang": Thread.Sleep(30000); return 0;
            default: return 0;
        }
    }
}
'@
    BeforeEach {
        $script:oldMode = $env:OMNI_FIXTURE_MODE
        $script:oldDevice = $env:KATAGLYPHIS_ORT_DEVICE
        $script:oldBackend = $env:KATAGLYPHIS_ONNX_BACKEND
        $script:oldModel = $env:KATAGLYPHIS_ONNX_MODEL
        $script:oldOrt = $env:ORT_DYLIB_PATH
        $script:oldOnnxRoot = $env:ONNX_ROOT
        $script:dir = Join-Path $TestDrive 'candidate'
        New-Item -ItemType Directory -Force -Path $script:dir | Out-Null
        $models = Join-Path $script:dir 'resources\models'
        New-Item -ItemType Directory -Force -Path $models | Out-Null
        Set-Content -LiteralPath (Join-Path $models 'deim_dfine_n_coco.onnx') -Value 'fixture'
        Set-Content -LiteralPath (Join-Path $script:dir 'onnxruntime.dll') -Value 'fixture'
        $fixture = Join-Path $script:dir 'probe.cs'
        Set-Content -LiteralPath $fixture -Value $source
        & $compiler /nologo "/out:$(Join-Path $script:dir 'omni_accelerant.exe')" $fixture
        if ($LASTEXITCODE -ne 0) { throw 'Could not compile standalone process fixture.' }
        $env:KATAGLYPHIS_ORT_DEVICE = 'cuda'
        $env:KATAGLYPHIS_ONNX_BACKEND = 'tract'
        $env:KATAGLYPHIS_ONNX_MODEL = 'external-model.onnx'
        $env:ORT_DYLIB_PATH = 'external-ort.dll'
        $env:ONNX_ROOT = 'external-runtime'
        Remove-Item Env:\OMNI_FIXTURE_MODE -ErrorAction SilentlyContinue
    }
    AfterEach {
        $env:OMNI_FIXTURE_MODE = $script:oldMode
        $env:KATAGLYPHIS_ORT_DEVICE = $script:oldDevice
        $env:KATAGLYPHIS_ONNX_BACKEND = $script:oldBackend
        $env:KATAGLYPHIS_ONNX_MODEL = $script:oldModel
        $env:ORT_DYLIB_PATH = $script:oldOrt
        $env:ONNX_ROOT = $script:oldOnnxRoot
    }
    It 'passes the argument and isolated CPU environment without changing the parent' {
        { & $check -AppDir $script:dir } | Should Not Throw
        $env:KATAGLYPHIS_ORT_DEVICE | Should Be 'cuda'
        $env:KATAGLYPHIS_ONNX_MODEL | Should Be 'external-model.onnx'
        $env:ORT_DYLIB_PATH | Should Be 'external-ort.dll'
        $env:ONNX_ROOT | Should Be 'external-runtime'
    }
    It 'rejects a nonzero self-check exit' {
        $env:OMNI_FIXTURE_MODE = 'fail'
        $message = try { & $check -AppDir $script:dir; '' } catch { $_.Exception.Message }
        $message | Should Match 'exit code 17'
    }
    It 'requires the model in the package before starting' {
        Remove-Item -LiteralPath (Join-Path $script:dir 'resources\models\deim_dfine_n_coco.onnx')
        $message = try { & $check -AppDir $script:dir; '' } catch { $_.Exception.Message }
        $message | Should Match 'No bundled ONNX model'
    }
    It 'requires the ONNX Runtime in the package even when a host runtime is configured' {
        Remove-Item -LiteralPath (Join-Path $script:dir 'onnxruntime.dll')
        $message = try { & $check -AppDir $script:dir; '' } catch { $_.Exception.Message }
        $message | Should Match 'No bundled ONNX Runtime'
    }
    It 'terminates a self-check that does not finish' {
        $env:OMNI_FIXTURE_MODE = 'hang'
        $message = try { & $check -AppDir $script:dir -TimeoutSeconds 1; '' } catch { $_.Exception.Message }
        $message | Should Match 'did not finish'
    }
    It 'checks the installed MSIX path and records a failed self-check' {
        # The actual installer conditional runs against the fixture, not an installed package.
        $installer = Join-Path $PSScriptRoot '..\Test-OmniAccelerANTInstallers.ps1'
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
        $errors.Count | Should Be 0
        $conditional = @($ast.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.IfStatementAst] -and
                    $node.Clauses[0].Item1.Extent.Text -eq '$CheckOnnx' -and
                    $node.Extent.Text.Contains('the installed MSIX runs the bundled model')
                }, $true))
        $conditional.Count | Should Be 1
        $run = [scriptblock]::Create($conditional[0].Extent.Text)
        Set-Variable -Name selfCheck -Value $check
        Set-Variable -Name installed -Value ([pscustomobject]@{ InstallLocation = $script:dir })
        Set-Variable -Name CheckOnnx -Value $true
        $script:assertionCount = 0
        $script:assertionPassed = 0
        $script:assertionFailed = 0
        $script:assertionError = ''
        function Assert-Test {
            param([string]$Name, [scriptblock]$Condition)
            $script:assertionCount++
            try {
                if (& $Condition) { $script:assertionPassed++ }
                else { $script:assertionFailed++ }
            } catch {
                $script:assertionFailed++
                $script:assertionError = $_.Exception.Message
            }
        }
        & $run
        $script:assertionCount | Should Be 1
        $script:assertionPassed | Should Be 1
        $env:OMNI_FIXTURE_MODE = 'fail'
        & $run
        $script:assertionCount | Should Be 2
        $script:assertionFailed | Should Be 1
        $script:assertionError | Should Match 'exit code 17'
        Set-Variable -Name CheckOnnx -Value $false
        & $run
        $script:assertionCount | Should Be 2
    }
    It 'checks the runner and installed packages before publishing candidates' {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $workflow = Get-Content (Join-Path $root '.github\workflows\windows-gpu-candidates.yml') -Raw
        $workflow | Should Match 'Test-OnnxSelfCheck\.ps1'
        $workflow | Should Match 'Test-OmniAccelerANTInstallers\.ps1[^\r\n]+-CheckOnnx'
        (Get-Content (Join-Path $root 'scripts\windows\Test-OmniAccelerANTInstallers.ps1') -Raw) | Should Match 'Test-OnnxSelfCheck\.ps1'
    }
}
