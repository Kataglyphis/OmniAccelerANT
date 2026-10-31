"""Exercise Windows provider configuration without building the application."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / "windows/runner/ort_device.cmake"
HEADER = ROOT / "windows/runner/ort_device.h"


class OrtDeviceTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT.parent / "_implementation"
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.manifest = self.path / "crates/inference/Cargo.toml"
        self.manifest.parent.mkdir(parents=True)
        self.script = self.path / "check.cmake"
        self.script.write_text(
            f'include("{MODULE.as_posix()}")\n'
            f'omni_windows_ort_device(selected "{self.path.as_posix()}")\n'
            'message(STATUS "selected=${selected}")\n', encoding="utf-8"
        )

    def configure(self, provider, arch="windows-x64", target=""):
        return subprocess.run(
            ["cmake", f"-DOMNI_WINDOWS_ORT_PROVIDER={provider}",
             f"-DFLUTTER_TARGET_PLATFORM={arch}", f"-DCMAKE_CXX_COMPILER_TARGET={target}",
             "-P", str(self.script)], capture_output=True, text=True, check=False
        )

    def test_cpu_needs_no_new_dependency_and_arm_cpu_is_unchanged(self):
        result = self.configure("cpu", "windows-arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("selected=cpu", result.stdout)

    def test_gpu_requires_correct_explicit_capability(self):
        self.manifest.write_text('[package]\nname = "test"\n', encoding="utf-8")
        self.assertNotEqual(self.configure("cuda").returncode, 0)
        self.manifest.write_text(
            '[package.metadata.kataglyphis]\nort-devices = ["cuda", "directml"]\n', encoding="utf-8"
        )
        for provider in ("cuda", "directml"):
            result = self.configure(provider)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"selected={provider}", result.stdout)
        self.assertNotEqual(self.configure("migraphx").returncode, 0)
        self.manifest.write_text(
            '[package.metadata.kataglyphis]\nname = "test"\n[other]\nort-devices = ["cuda"]\n',
            encoding="utf-8",
        )
        self.assertNotEqual(self.configure("cuda").returncode, 0)

    def test_gpu_rejects_arm_flutter_and_cross_compiler_targets(self):
        self.manifest.write_text(
            '[package.metadata.kataglyphis]\nort-devices = ["cuda", "directml"]\n', encoding="utf-8"
        )
        for provider in ("cuda", "directml"):
            for arch, target in (("windows-arm64", ""), ("windows-x64", "aarch64-pc-windows-msvc")):
                result = self.configure(provider, arch, target)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("x64 only", result.stderr)

    def test_runtime_device_allowlist(self):
        source = self.path / "test.cpp"
        binary = self.path / "test.exe"
        source.write_text(
            f'#include "{HEADER.as_posix()}"\n'
            'int main() {\n'
            '  if (!IsAllowedOrtDevice(L"cuda", L"cuda")) return 1;\n'
            '  if (!IsAllowedOrtDevice(L"CPU", L"cuda")) return 2;\n'
            '  if (!IsAllowedOrtDevice(L"auto", L"directml")) return 3;\n'
            '  if (!IsAllowedOrtDevice(L"DirectML", L"directml")) return 4;\n'
            '  if (IsAllowedOrtDevice(L"directml", L"cuda")) return 5;\n'
            '  if (IsAllowedOrtDevice(L"", L"cuda")) return 6;\n'
            '  const wchar_t *name = L"KATAGLYPHIS_ORT_DEVICE";\n'
            '  if (!SetEnvironmentVariableW(name, nullptr)) return 7;\n'
            '  if (!ConfigureOrtDevice(L"cuda")) return 8;\n'
            '  wchar_t value[32] = {};\n'
            '  if (GetEnvironmentVariableW(name, value, 32) != 4 || std::wstring(value) != L"cuda") return 9;\n'
            '  if (!SetEnvironmentVariableW(name, L"CPU") || !ConfigureOrtDevice(L"cuda")) return 10;\n'
            '  if (GetEnvironmentVariableW(name, value, 32) != 3 || std::wstring(value) != L"CPU") return 11;\n'
            '  if (!SetEnvironmentVariableW(name, L"directml") || ConfigureOrtDevice(L"cuda")) return 12;\n'
            '  return 0;\n}\n', encoding="utf-8"
        )
        subprocess.run(["g++", "-std=c++17", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, env=os.environ.copy())

    def test_gpu_marker_survives_optimization_and_stripping(self):
        runner_cmake = (ROOT / "windows/runner/CMakeLists.txt").read_text(encoding="utf-8")
        runner_main = (ROOT / "windows/runner/main.cpp").read_text(encoding="utf-8")
        self.assertIn("OMNI_ACCELERANT_GPU_VARIANT_${_ort_device}_V1", runner_cmake)
        self.assertIn("OutputDebugStringA(OMNI_WINDOWS_ORT_MARKER)", runner_main)
        source = self.path / "marker.cpp"
        binary = self.path / "marker.exe"
        source.write_text(
            '#include <windows.h>\n'
            'int main() { OutputDebugStringA("OMNI_ACCELERANT_GPU_VARIANT_directml_V1"); return 0; }\n',
            encoding="utf-8",
        )
        subprocess.run(["g++", "-std=c++17", "-O2", "-flto", "-s", str(source), "-o", str(binary)], check=True)
        self.assertIn(b"OMNI_ACCELERANT_GPU_VARIANT_directml_V1", binary.read_bytes())

    def test_actual_cmake_definitions_compile_a_runnable_gpu_marker(self):
        runner = (ROOT / "windows/runner/CMakeLists.txt").read_text(encoding="utf-8")
        definitions = [line.strip() for line in runner.splitlines() if 'target_compile_definitions(${BINARY_NAME} PRIVATE "OMNI_WINDOWS_ORT_' in line]
        self.assertEqual(len(definitions), 2)
        (self.path / "CMakeLists.txt").write_text(
            'cmake_minimum_required(VERSION 3.14)\nproject(marker LANGUAGES CXX)\n'
            'set(BINARY_NAME probe)\nset(_ort_device directml)\nadd_executable(probe probe.cpp)\n'
            + "\n".join(definitions) + "\n", encoding="utf-8"
        )
        (self.path / "probe.cpp").write_text(
            '#include <windows.h>\n#include <cwchar>\n'
            'int main() { OutputDebugStringA(OMNI_WINDOWS_ORT_MARKER); '
            'return std::wcscmp(OMNI_WINDOWS_ORT_DEVICE, L"directml"); }\n', encoding="utf-8"
        )
        build = self.path / "build"
        subprocess.run(["cmake", "-S", str(self.path), "-B", str(build), "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release"], check=True, capture_output=True)
        subprocess.run(["cmake", "--build", str(build)], check=True, capture_output=True)
        binary = build / "probe.exe"
        subprocess.run([str(binary)], check=True)
        self.assertIn(b"OMNI_ACCELERANT_GPU_VARIANT_directml_V1", binary.read_bytes())


if __name__ == "__main__":
    unittest.main()
