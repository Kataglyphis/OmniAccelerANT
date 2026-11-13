#!/usr/bin/env python3
"""Exercise trusted installer selection and profiling without running an app."""
# suite-lane-only: 16.5 GiB free in the temp directory, more than a tmpfs /tmp holds

import hashlib
import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "profile_gpu_installers", ROOT / "scripts/windows/profile_gpu_installers.py"
)
if SPEC is None or SPEC.loader is None:
    raise ImportError("cannot load installer profiler")
PROFILE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROFILE)


class ProfileInstallers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.packages = self.root / "packages"
        self.packages.mkdir()
        self.stem = "omni-accelerant-1.2.3-windows-x64-amd"
        self.names = [
            self.stem + suffix for suffix in (".msi", ".msix", "-testcert.cer")
        ]
        (self.packages / self.names[0]).write_bytes(b"MSI fixture")
        (self.packages / self.names[2]).write_bytes(b"certificate")
        with zipfile.ZipFile(self.packages / self.names[1], "w") as package:
            package.writestr("resources/", b"")
            package.writestr("omni_accelerant.exe", b"MSIX fixture")

    def test_selected_vendor_names_and_measured_space(self):
        self.assertEqual(PROFILE.installer_names(self.names, "amd"), sorted(self.names))
        for vendor, names in (
            ("nvidia", self.names),
            ("amd", [name.replace("x64", "arm64") for name in self.names]),
        ):
            with self.subTest(vendor=vendor), self.assertRaises(ValueError):
                PROFILE.installer_names(names, vendor)
        archive = self.root / "candidate.zip"
        with zipfile.ZipFile(archive, "w") as output:
            for name in self.names:
                output.write(self.packages / name, name)
        names, size = PROFILE.inspect_zip(archive, self.root)
        self.assertEqual(set(names), set(self.names))
        self.assertGreater(size, 0)
        with (
            mock.patch.object(
                PROFILE.shutil,
                "disk_usage",
                return_value=mock.Mock(free=PROFILE.FLOOR + PROFILE.CUSHION),
            ),
            self.assertRaises(ValueError),
        ):
            PROFILE.inspect_zip(archive, self.root)

    def test_msi_and_msix_profile_sequentially_and_cleanup(self):
        seen = []
        evidence = self.root / "evidence"
        evidence.mkdir()

        def fake_extract(command, **_kwargs):
            target = Path(
                next(
                    value.split("=", 1)[1]
                    for value in command
                    if value.startswith("TARGETDIR=")
                )
            )
            (target / "omni_accelerant.exe").write_bytes(b"fixture")

        def fake_profile(root, device, index, output, repo):
            self.assertTrue((root / "omni_accelerant.exe").is_file())
            self.assertEqual((device, index, repo), ("directml", "2", ROOT))
            self.assertEqual(output.name, root.name)
            self.assertEqual(len(list(evidence.glob("omni-gpu-payload-*"))), 1)
            seen.append(root.name)

        with (
            mock.patch.object(PROFILE.shutil, "which", return_value="pwsh.exe"),
            mock.patch.object(PROFILE.subprocess, "check_output", return_value="100"),
            mock.patch.object(PROFILE, "run_process", side_effect=fake_extract),
            mock.patch.object(PROFILE, "run_verifier", side_effect=fake_profile),
            mock.patch.dict(os.environ, {"SystemRoot": str(self.root)}),
        ):
            PROFILE.profile(self.packages, "amd", "directml", "2", ROOT, evidence)
        self.assertEqual(seen, ["msi", "msix"])
        self.assertEqual(list(evidence.glob("omni-gpu-payload-*")), [])

    def test_rejects_wrong_provider_and_index(self):
        for vendor, device, index in (
            ("amd", "cuda", "0"),
            ("nvidia", "directml", "0"),
            ("amd", "directml", "-1"),
        ):
            with (
                self.subTest(vendor=vendor, index=index),
                self.assertRaises(ValueError),
            ):
                PROFILE.profile(self.packages, vendor, device, index, ROOT, self.root)

    def test_workflow_profiles_selected_same_run_artifact_only_when_requested(self):
        workflow = (ROOT / ".github/workflows/windows-gpu-candidates.yml").read_text(
            encoding="utf-8"
        )
        job = workflow.split("\n  gpu-profile:", 1)[1]
        self.assertIn("!cancelled() && inputs.verify-gpu", job)
        self.assertIn("needs.candidate.result == 'failure'", job)
        self.assertIn("needs: [preflight, candidate]", job)
        self.assertIn(
            "runs-on: [self-hosted, Windows, X64, '${{ matrix.gpu-runner }}']", job
        )
        self.assertIn("attempt-${{ github.run_attempt }}", job)
        self.assertIn("artifact-ids: ${{ steps.artifact.outputs.id }}", job)
        self.assertIn("digest-mismatch: error", job)
        self.assertIn("prepare_gpu_artifact.py", job)
        self.assertIn("--check before-check", job)
        self.assertIn("--check gpu-model-inference", job)
        self.assertNotIn("run: throw", job)

    @unittest.skipUnless(os.name == "nt", "requires Windows PowerShell")
    def test_actual_workflow_step_checks_candidate_and_detects_mutation(self):
        workflow = (ROOT / ".github/workflows/windows-gpu-candidates.yml").read_text(
            encoding="utf-8"
        )
        job = workflow.split("      - name: Profile MSI and MSIX payloads\n", 1)[1]
        block = job.split("        run: |\n", 1)[1].split("\n      - name:", 1)[0]
        script = self.root / "step.ps1"
        script.write_text(
            "\n".join(line[10:] for line in block.splitlines()) + "\n", encoding="utf-8"
        )
        shared = self.root / "third_party/ANTfrastructure/shared/python"
        shared.mkdir(parents=True)
        source = ROOT / "third_party/ANTfrastructure/shared/python"
        for name in (
            "prepare_gpu_artifact.py",
            "stage_gpu_artifact.py",
            "gpu_artifact_receipt.py",
        ):
            shutil.copyfile(source / name, shared / name)
        windows = self.root / "scripts/windows"
        windows.mkdir(parents=True)
        shutil.copyfile(
            ROOT / "scripts/windows/profile_gpu_installers.py",
            windows / "profile_impl.py",
        )
        shutil.copyfile(
            ROOT / "scripts/windows/gpu_process.py", windows / "gpu_process.py"
        )
        (windows / "profile_gpu_installers.py").write_text(
            "import os,pathlib,runpy,sys\n"
            "if sys.argv[1] == 'plan': runpy.run_path('scripts/windows/profile_impl.py', run_name='__main__')\n"
            "else:\n"
            " p=pathlib.Path(sys.argv[2]); e=pathlib.Path(sys.argv[sys.argv.index('--evidence')+1])\n"
            " (e/'mock-profile.json').write_text('ok')\n"
            " if os.environ.get('MUTATE'): (p/os.environ['MUTATE']).write_bytes(b'changed')\n",
            encoding="utf-8",
        )
        for mutate in (False, True):
            with self.subTest(mutate=mutate):
                scratch = self.root / ("changed" if mutate else "valid")
                (scratch / "archive").mkdir(parents=True)
                archive = scratch / "archive/candidate.zip"
                with zipfile.ZipFile(archive, "w") as output:
                    for name in self.names:
                        output.write(self.packages / name, name)
                env = os.environ | {
                    "PROFILE_ROOT": str(scratch),
                    "ARTIFACT_ID": "7",
                    "ARTIFACT_DIGEST": hashlib.sha256(archive.read_bytes()).hexdigest(),
                    "GPU_VENDOR": "amd",
                    "PROVIDER": "directml",
                    "DIRECTML_INDEX": "2",
                    "GITHUB_REPOSITORY": "Owner/Repo",
                    "GITHUB_SHA": "a" * 40,
                    "GITHUB_RUN_ID": "8",
                    "GITHUB_RUN_ATTEMPT": "1",
                }
                if mutate:
                    env["MUTATE"] = self.names[0]
                shell = os.environ.get("OMNI_TEST_PWSH", "powershell.exe")
                result = subprocess.run(
                    [
                        shell,
                        "-NoProfile",
                        "-NonInteractive",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        str(script),
                    ],
                    cwd=self.root,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode == 0, not mutate, result.stderr)
                self.assertEqual(
                    (scratch / "evidence/receipt.json").exists(), not mutate
                )

    @unittest.skipUnless(
        os.environ.get("OMNI_TEST_PWSH") and os.environ.get("OMNI_TEST_MSI_VALID"),
        "requires synthetic MSI and PowerShell",
    )
    def test_real_msi_file_table_size_without_installation(self):
        result = subprocess.run(
            [
                os.environ["OMNI_TEST_PWSH"],
                "-NoProfile",
                "-File",
                str(ROOT / "scripts/windows/Get-MsiPayloadSize.ps1"),
                os.environ["OMNI_TEST_MSI_VALID"],
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(int(result.stdout.strip()), 595)


if __name__ == "__main__":
    unittest.main()
