#!/usr/bin/env python3
"""Check the GPU candidate matrix and fail-closed pinned dependency preflight."""

import json
import re
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PREFLIGHT = ROOT / "scripts/linux/preflight-gpu-candidate.py"
MODULE = runpy.run_path(str(PREFLIGHT))
VALIDATE = MODULE["validate"]
VALIDATE_PROFILE = MODULE["validate_profile_contract"]
GPU_MATRIX = MODULE["gpu_matrix"]
WORKFLOW = ROOT / ".github/workflows/linux-gpu-candidates.yml"
WINDOWS_WORKFLOW = ROOT / ".github/workflows/windows-gpu-candidates.yml"
IDENTITY = (
    "${{ needs.preflight.outputs.selection }}-${{ needs.preflight.outputs.scope }}"
)


class CandidatePreflightTests(unittest.TestCase):
    def search(self, pattern: str, text: str) -> re.Match[str]:
        match = re.search(pattern, text)
        if match is None:
            self.fail(f"{pattern!r} has no match")
        return match

    """Only current GPU-capable dependencies can proceed to image pulls."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write(
            "third_party/OxidANT/crates/inference/Cargo.toml",
            '[package.metadata.kataglyphis]\nort-devices = ["cuda", "migraphx"]\n',
        )
        base = "third_party/ANTfrastructure/linux/scripts/"
        self.write(
            base + "06-packaging/ort-runtime-bundle.sh",
            "ort_host_runtime_needed()\nort_assert_no_bundled_host_runtime()",
        )
        self.write(
            base + "06-packaging/elf-closure.sh", "--direct-only --reject-source-root"
        )
        self.write(base + "06-packaging/bundle-loader.sh", "--external-library-path")
        self.write(
            base + "06-packaging/stage-ort-wheel-licenses.py", "--require-unstripped"
        )
        self.write(
            base + "06-packaging/verify-ort-appimage-payload.sh",
            "--require-unstripped ort_assert_no_bundled_host_runtime",
        )
        self.write(
            base + "01-core/versions.env",
            "IMAGE_REGISTRY_PREFIX=ghcr.io/kataglyphis/kataglyphis_beschleuniger\n",
        )

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def test_valid_capabilities(self):
        self.assertEqual(
            VALIDATE(self.root), "ghcr.io/kataglyphis/kataglyphis_beschleuniger"
        )

    def test_profile_contract_requires_the_generated_pair_and_shared_checks(self):
        self.write(
            "third_party/OxidANT/src/api/onnx.rs", "pub fn profile_detector_image("
        )
        self.write(
            "third_party/OxidANT/src/detector_profile.rs", "pub fn run( infer_rgba("
        )
        self.write(
            "third_party/OxidANT/src/frb_generated.rs",
            "FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH: i32 = 1413895636;",
        )
        dart = "lib/src/rust/frb_generated.dart"
        self.write(dart, "int get rustContentHash => 1413895636;")
        self.write(
            "third_party/ANTfrastructure/linux/scripts/lib/gpu-profile-env.sh",
            "gpu_without_migraphx_overrides()",
        )
        self.write(
            "third_party/ANTfrastructure/shared/python/verify_ort_profile.py",
            "--min-runs",
        )
        self.write(
            "third_party/ANTfrastructure/shared/python/compare_detector_parity.py",
            "--pairwise",
        )
        VALIDATE_PROFILE(self.root)
        for contents in (
            "int get rustContentHash => 7;",
            "int get rustContentHash => 1413895636;\nint get rustContentHash => 1413895636;",
            "",
        ):
            with self.subTest(contents=contents):
                self.write(dart, contents)
                with self.assertRaisesRegex(ValueError, "not the same generated pair"):
                    VALIDATE_PROFILE(self.root)
        self.write(dart, "int get rustContentHash => 1413895636;")
        self.write(
            "third_party/ANTfrastructure/shared/python/compare_detector_parity.py",
            "no pairwise support",
        )
        with self.assertRaisesRegex(ValueError, "--pairwise"):
            VALIDATE_PROFILE(self.root)

    def test_profile_uses_current_attempt_scope_and_selected_tuple(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        clean = text.split("\n  clean-host:\n", maxsplit=1)[1].split(
            "\n  gpu-profile:\n", maxsplit=1
        )[0]
        profile = text.split("\n  gpu-profile:\n", maxsplit=1)[1]
        self.assertIn("needs: [preflight, candidate, clean-host]", profile)
        self.assertIn("!cancelled() && inputs.verify-gpu", profile)
        self.assertIn("needs.preflight.result == 'success'", profile)
        self.assertIn("needs.candidate.result == 'failure'", profile)
        self.assertIn("needs.clean-host.result == 'failure'", profile)
        self.assertIn(
            "matrix: ${{ fromJSON(needs.preflight.outputs.matrix) }}", profile
        )
        self.assertIn("${{ matrix.runner-arch }}", profile)
        self.assertIn("${{ matrix.gpu-runner }}", profile)
        self.assertLess(
            profile.index("Check GPU runner package inspection tools"),
            profile.index("Download immutable candidate archive"),
        )
        self.assertIn("python3 dpkg-deb unsquashfs", profile)
        self.assertLess(
            profile.index("Check GPU runner package inspection tools"),
            profile.index("actions/checkout@"),
        )
        self.assertLess(
            profile.index("preflight-profile-packages.py download"),
            profile.index("Download immutable candidate archive"),
        )
        self.assertLess(
            profile.index("preflight-profile-packages.py stage"),
            profile.index("prepare_gpu_artifact.py"),
        )
        self.assertIn(
            f"name: unverified-omni-metadata-${{{{ matrix.vendor }}}}-linux-${{{{ matrix.arch }}}}-{IDENTITY}-attempt-${{{{ github.run_attempt }}}}",
            profile,
        )
        self.assertIn(
            "artifact-ids: ${{ steps.metadata.outputs.artifact_id }}", profile
        )
        self.assertIn("skip-decompress: true", profile)
        self.assertIn("prepare_gpu_artifact.py", profile)
        self.assertIn("--check before-check", profile)
        self.assertIn("--check gpu-model-inference", profile)
        self.assertIn("steps.profile_upload.outputs.artifact-digest", profile)
        self.assertIn("GPU_PROFILE_RECEIPT_SHA256", profile)
        for fragment in (
            "scripts/linux/gpu-profile-metadata.py resolve",
            "uses: ./third_party/ANTfrastructure/.github/actions/clean-host-package-check",
            "artifact-id: ${{ steps.clean_metadata.outputs.artifact_id }}",
            "artifact-digest: ${{ steps.clean_metadata.outputs.artifact_digest }}",
            "artifact-files: ${{ steps.clean_metadata.outputs.files }}",
            "gpu-receipt: ${{ runner.temp }}/omni-clean-receipt.json",
        ):
            self.assertIn(fragment, clean)
        self.assertLess(
            clean.index("Check immutable packages"),
            clean.index("Upload clean-host receipt"),
        )
        self.assertIn("--check clean-host-inference", profile)
        self.assertLess(
            profile.index("--check clean-host-inference"),
            profile.index("profile-gpu-packages.sh"),
        )
        self.assertIn("digest-mismatch: error", profile)
        self.assertIn("profile-gpu-packages.sh", profile)
        self.assertNotIn("inputs.caller-scope", profile)

    def test_old_or_partial_pins_fail_closed(self):
        manifest = "third_party/OxidANT/crates/inference/Cargo.toml"
        self.write(manifest, '[package]\nname="old"\n')
        with self.assertRaisesRegex(ValueError, "strict CUDA and MIGraphX"):
            VALIDATE(self.root)
        self.write(
            manifest,
            '[package.metadata.kataglyphis]\nort-devices = ["cuda", "migraphx"]\n',
        )
        self.write(
            "third_party/ANTfrastructure/linux/scripts/06-packaging/elf-closure.sh",
            "--direct-only",
        )
        with self.assertRaisesRegex(ValueError, "--reject-source-root"):
            VALIDATE(self.root)

    def test_registry_is_unique_and_fixed_to_ghcr(self):
        self.write(
            "third_party/ANTfrastructure/linux/scripts/01-core/versions.env",
            "IMAGE_REGISTRY_PREFIX=elsewhere/image\n",
        )
        with self.assertRaisesRegex(ValueError, "registry is invalid"):
            VALIDATE(self.root)

    def test_workflow_matrix_and_unverified_output(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        rows = [
            tuple(
                row[key]
                for key in (
                    "vendor",
                    "arch",
                    "platform",
                    "runner",
                    "image-tag",
                    "provider",
                )
            )
            for row in GPU_MATRIX("all")["include"]
        ]
        self.assertEqual(
            set(rows),
            {
                (
                    "nvidia",
                    "x64",
                    "linux/amd64",
                    "ubuntu-26.04",
                    "latest-nvidia",
                    "cuda",
                ),
                (
                    "nvidia",
                    "arm64",
                    "linux/arm64",
                    "ubuntu-26.04-arm",
                    "latest-nvidia",
                    "cuda",
                ),
                (
                    "amd",
                    "x64",
                    "linux/amd64",
                    "ubuntu-26.04",
                    "latest-rocm",
                    "migraphx",
                ),
            },
        )
        self.assertEqual(len(rows), 3)
        for part in (
            "needs: preflight",
            "ORT_LIB_LOCATION=/usr/local/lib/onnxruntime-gpu/lib",
            "--package-formats tar,deb,appimage",
            "verify-gpu-candidate.sh",
            f"name: unverified-omni-${{{{ matrix.vendor }}}}-linux-${{{{ matrix.arch }}}}-{IDENTITY}-attempt-${{{{ github.run_attempt }}}}",
        ):
            self.assertIn(part, text)
        self.assertNotIn("out/omni-accelerant-linux-", text)
        self.assertIn(
            f"name: unverified-omni-${{{{ matrix.vendor }}}}-linux-${{{{ matrix.arch }}}}-{IDENTITY}-attempt-${{{{ github.run_attempt }}}}\n          overwrite: false",
            text,
        )
        self.assertIn("options: [all, nvidia-x64, nvidia-arm64, amd-x64]", text)
        self.assertEqual(text.count("default: all"), 2)
        self.assertIn("GPU_TUPLE: ${{ inputs.gpu-tuple }}", text)
        self.assertIn('--matrix "$GPU_TUPLE"', text)
        self.assertEqual(
            text.count("matrix: ${{ fromJSON(needs.preflight.outputs.matrix) }}"), 3
        )
        self.assertNotRegex(text, r"(?m)^concurrency:")
        self.assertIn('--scope "$CALLER_SCOPE"', text)
        self.assertIn("caller-scope:", text)
        group = self.search(r"(?m)^      group: (.+)$", text)
        self.assertIn(IDENTITY, group.group(1))
        self.assertNotIn("inputs.", group.group(1))
        self.assertNotIn("push:", text)
        self.assertIn("free-disk-space: 'true'", text)
        self.assertIn("pull-first: 'false'", text)
        self.assertLess(
            text.index("check-gpu-image-runtime.sh"),
            text.index("ci-container-run-native-linux.sh"),
        )

    def test_clean_host_runs_inference_for_each_candidate(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        clean = text.split("\n  clean-host:\n", maxsplit=1)[1]
        self.assertIn("needs: [preflight, candidate]", clean)
        self.assertIn(
            "if: ${{ !cancelled() && needs.preflight.result == 'success' && (needs.candidate.result == 'success' || needs.candidate.result == 'failure') }}",
            clean,
        )
        self.assertIn("matrix: ${{ fromJSON(needs.preflight.outputs.matrix) }}", clean)
        self.assertIn(
            f"artifact: unverified-omni-${{{{ matrix.vendor }}}}-linux-${{{{ matrix.arch }}}}-{IDENTITY}-attempt-${{{{ github.run_attempt }}}}",
            clean,
        )
        for package in ("deb", "tarball", "appimage"):
            self.assertRegex(clean, rf"(?m)^          {package}: '\*\.")
            command = self.search(rf"(?m)^          {package}-command: (.+)$", clean)
            self.assertIn(
                "scripts/linux/check-packaged-onnx-runtime.sh", command.group(1)
            )
            self.assertIn("KATAGLYPHIS_ORT_DEVICE=cpu", command.group(1))
            self.assertIn("KATAGLYPHIS_ONNX_BACKEND=ort", command.group(1))
            for name in (
                "KATAGLYPHIS_ONNX_MODEL",
                "ORT_DYLIB_PATH",
                "ORT_LIB_LOCATION",
                "ONNX_ROOT",
                "LD_LIBRARY_PATH",
            ):
                self.assertEqual(command.group(1).count(f"-u {name}"), 1)

    def test_selector_exposes_only_requested_supported_tuples(self):
        full = GPU_MATRIX("all")["include"]
        self.assertEqual(len(full), 3)
        selections = [
            ("all", full),
            *[
                (name, [row])
                for name, row in zip(
                    ("nvidia-x64", "nvidia-arm64", "amd-x64"), full, strict=True
                )
            ],
        ]
        for selection, expected_rows in selections:
            with self.subTest(selection=selection):
                result = subprocess.run(
                    [sys.executable, str(PREFLIGHT), "--matrix", selection],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"include": expected_rows})
        for invalid in ("amd-arm64", "nvidia-x86", "", "all\nname=bad"):
            with self.subTest(selection=invalid):
                result = subprocess.run(
                    [sys.executable, str(PREFLIGHT), "--matrix", invalid],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_windows_selector_exposes_only_supported_x64_vendors(self):
        expected = {
            "nvidia": {
                "vendor": "nvidia",
                "tag": "winamd64-nvidia",
                "provider": "cuda",
            },
            "amd": {"vendor": "amd", "tag": "winamd64-rocm", "provider": "directml"},
        }
        for selection, rows in [
            ("all", list(expected.values())),
            *[(key, [row]) for key, row in expected.items()],
        ]:
            with self.subTest(selection=selection):
                result = subprocess.run(
                    [sys.executable, str(PREFLIGHT), "--windows-matrix", selection],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), {"include": rows})
        for invalid in ("nvidia-arm64", "amd-arm64", "", "all\nname=bad"):
            with self.subTest(selection=invalid):
                result = subprocess.run(
                    [sys.executable, str(PREFLIGHT), "--windows-matrix", invalid],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_clean_host_requires_the_current_attempt(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        upload = self.search(r"(?m)^          name: (unverified-omni-.+)$", text)
        download = self.search(r"(?m)^          artifact: (unverified-omni-.+)$", text)
        self.assertEqual(upload.group(1), download.group(1))
        first = upload.group(1).replace("${{ github.run_attempt }}", "1")
        retry = download.group(1).replace("${{ github.run_attempt }}", "2")
        self.assertNotEqual(first, retry)
        self.assertIn("overwrite: false", text)

    def test_scope_validation_and_isolated_artifact_names(self):
        for scope in ("default", "a", "a-", "a-1", "z" * 32):
            with self.subTest(scope=scope):
                result = subprocess.run(
                    [sys.executable, str(PREFLIGHT), "--scope", scope],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, scope + "\n")
        for scope in ("", "A", "-a", "1a", "a_b", "z" * 33, "a\nname=bad"):
            with self.subTest(scope=scope):
                result = subprocess.run(
                    [sys.executable, str(PREFLIGHT), "--scope", scope],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

        linux = WORKFLOW.read_text(encoding="utf-8")
        upload = self.search(r"(?m)^          name: (unverified-omni-.+)$", linux)
        download = self.search(r"(?m)^          artifact: (unverified-omni-.+)$", linux)
        self.assertEqual(upload.group(1), download.group(1))
        windows = WINDOWS_WORKFLOW.read_text(encoding="utf-8")
        windows_uploads = re.findall(
            r"(?m)^          name: (unverified-omni-windows-.+)$", windows
        )
        self.assertEqual(len(windows_uploads), 2)

        def artifact(template, selection, scope, attempt="1"):
            for token, value in {
                "${{ matrix.vendor }}": "nvidia",
                "${{ matrix.arch }}": "x64",
                "${{ needs.preflight.outputs.selection }}": selection,
                "${{ needs.preflight.outputs.scope }}": scope,
                "${{ github.run_attempt }}": attempt,
            }.items():
                template = template.replace(token, value)
            self.assertNotIn("${{", template)
            return template

        for template in [upload.group(1), *windows_uploads]:
            with self.subTest(template=template):
                single = "nvidia" if "windows" in template else "nvidia-x64"
                all_target = artifact(template, "all", "default")
                one_target = artifact(template, single, "default")
                self.assertNotEqual(all_target, one_target)
                self.assertNotEqual(one_target, artifact(template, single, "other"))
                self.assertNotEqual(
                    one_target, artifact(template, single, "default", "2")
                )
                self.assertEqual(one_target, artifact(template, single, "default"))

    def test_windows_scope_is_validated_before_job_concurrency(self):
        text = WINDOWS_WORKFLOW.read_text(encoding="utf-8")
        self.assertNotRegex(text, r"(?m)^concurrency:")
        self.assertIn("--windows-matrix $env:GPU_VENDOR", text)
        self.assertIn("--scope $env:CALLER_SCOPE", text)
        self.assertIn("caller-scope:", text)
        group = self.search(r"(?m)^      group: (.+)$", text)
        self.assertIn(IDENTITY, group.group(1))
        self.assertNotIn("inputs.", group.group(1))


if __name__ == "__main__":
    unittest.main()
