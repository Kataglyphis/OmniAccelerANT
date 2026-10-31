#!/usr/bin/env python3
"""Check the GPU candidate matrix and fail-closed pinned dependency preflight."""

import re
import runpy
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VALIDATE = runpy.run_path(str(ROOT / "scripts/linux/preflight-gpu-candidate.py"))[
    "validate"
]
WORKFLOW = ROOT / ".github/workflows/linux-gpu-candidates.yml"


class CandidatePreflightTests(unittest.TestCase):
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
        rows = re.findall(
            r"(?m)^          - vendor: (\S+)\n            arch: (\S+)\n            platform: (\S+)\n            runner: (\S+)\n            image-tag: (\S+)\n            provider: (\S+)$",
            text,
        )
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
            "workflow_dispatch:",
            "needs: preflight",
            "ORT_LIB_LOCATION=/usr/local/lib/onnxruntime-gpu/lib",
            "--package-formats tar,deb,appimage",
            "verify-gpu-candidate.sh",
            "name: unverified-omni-${{ matrix.vendor }}-linux-${{ matrix.arch }}",
        ):
            self.assertIn(part, text)
        self.assertNotIn("out/omni-accelerant-linux-", text)
        self.assertIn(
            "name: unverified-omni-${{ matrix.vendor }}-linux-${{ matrix.arch }}\n          overwrite: true",
            text,
        )
        self.assertNotIn("workflow_call:", text)
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
        clean_rows = re.findall(
            r"(?m)^          - vendor: (\S+)\n            arch: (\S+)\n            runner: (\S+)$",
            clean,
        )
        self.assertEqual(
            set(clean_rows),
            {
                ("nvidia", "x64", "ubuntu-26.04"),
                ("nvidia", "arm64", "ubuntu-26.04-arm"),
                ("amd", "x64", "ubuntu-26.04"),
            },
        )
        self.assertEqual(len(clean_rows), 3)
        self.assertIn("needs: candidate", clean)
        self.assertIn(
            "artifact: unverified-omni-${{ matrix.vendor }}-linux-${{ matrix.arch }}",
            clean,
        )
        for package in ("deb", "tarball", "appimage"):
            self.assertRegex(clean, rf"(?m)^          {package}: '\*\.")
            command = re.search(rf"(?m)^          {package}-command: (.+)$", clean)
            self.assertIsNotNone(command)
            self.assertIn("KATAGLYPHIS_ORT_DEVICE=cpu", command.group(1))
            self.assertIn("KATAGLYPHIS_ONNX_BACKEND=ort", command.group(1))
            self.assertIn("--onnx-check", command.group(1))


if __name__ == "__main__":
    unittest.main()
