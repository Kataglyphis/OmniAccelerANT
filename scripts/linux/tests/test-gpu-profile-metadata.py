#!/usr/bin/env python3
"""Check candidate identity, immutable archive and receipt failure boundaries."""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
META = ROOT / "scripts/linux/gpu-profile-metadata.py"
HUB = Path(os.environ.get("ANTFRASTRUCTURE_DIR", ROOT / "third_party/ANTfrastructure"))
SHARED = HUB / "shared/python"


class ProfileMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omni-profile-test-")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.output = self.root / "output"
        self.env = os.environ | {
            "GITHUB_REPOSITORY": "Kataglyphis/OmniAccelerANT",
            "GITHUB_SHA": "a" * 40,
            "GITHUB_RUN_ID": "123",
            "GITHUB_RUN_ATTEMPT": "2",
            "GITHUB_OUTPUT": str(self.output),
            "GPU_VENDOR": "nvidia",
            "GPU_ARCH": "x64",
            "GPU_ARTIFACT_ID": "456",
            "GPU_ARTIFACT_DIGEST": "sha256:" + "b" * 64,
        }
        self.names = [
            "omni-accelerant-nvidia-linux-x64.tar.gz",
            "omni-accelerant-nvidia_1_amd64.deb",
            "omni-accelerant-nvidia-1-x86_64.AppImage",
        ]
        self.env["GPU_ARTIFACT_FILES"] = "\n".join(self.names)

    def command(self, *args, env=None, success=True):
        result = subprocess.run(
            [sys.executable, "-I", *(str(arg) for arg in args)],
            env=env or self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result

    def test_selection_and_identity_reject_mutations(self):
        package = self.root / "package"
        package.mkdir()
        for name in self.names:
            (package / name).write_bytes(name.encode())
        self.command(META, "select", package)
        selected = self.output.read_text(encoding="utf-8")
        for name in self.names:
            self.assertIn(name, selected)
        metadata = self.root / "metadata.json"
        self.command(META, "create", metadata)
        self.command(META, "resolve", metadata)
        original = json.loads(metadata.read_text())
        for key, value in {
            "run_attempt": "3",
            "run_id": "124",
            "vendor": "amd",
            "arch": "arm64",
            "artifact_id": "0",
            "artifact_digest": "bad",
            "revision": "c" * 40,
            "files": [self.names[0], self.names[0], self.names[2]],
        }.items():
            metadata.write_text(json.dumps(original | {key: value}), encoding="utf-8")
            self.command(META, "resolve", metadata, success=False)
        metadata.write_text('{"run_id":"123","run_id":"123"}', encoding="utf-8")
        self.command(META, "resolve", metadata, success=False)
        (package / self.names[1]).unlink()
        self.command(META, "select", package, success=False)

    def test_evidence_identity_is_bound_to_candidate_and_run(self):
        env = self.env | {
            "GPU_PROFILE_ARTIFACT_ID": "789",
            "GPU_PROFILE_ARTIFACT_DIGEST": "sha256:" + "d" * 64,
            "GPU_PROFILE_RECEIPT_SHA256": "e" * 64,
        }
        metadata = self.root / "evidence-identity.json"
        candidate = self.root / "candidate-identity.json"
        self.command(META, "create", candidate, env=env)
        self.command(META, "evidence", metadata, env=env)
        self.command(
            META,
            "resolve-evidence",
            metadata,
            "--candidate-metadata",
            candidate,
            env=env,
        )
        self.command(META, "resolve-evidence", metadata, env=env, success=False)
        original = json.loads(metadata.read_text())
        for key, value in {
            "run_attempt": "3",
            "artifact_id": "999",
            "artifact_digest": "sha256:" + "a" * 64,
            "files": [
                self.names[0],
                "omni-accelerant-nvidia_2_amd64.deb",
                self.names[2],
            ],
            "profile_artifact_id": "0",
            "profile_artifact_digest": "bad",
            "receipt_sha256": "not-a-sha",
        }.items():
            metadata.write_text(json.dumps(original | {key: value}), encoding="utf-8")
            self.command(
                META,
                "resolve-evidence",
                metadata,
                "--candidate-metadata",
                candidate,
                env=env,
                success=False,
            )

    def test_all_supported_tuples_and_forbidden_arm_rocm(self):
        for vendor, arch, deb, machine in (
            ("nvidia", "x64", "amd64", "x86_64"),
            ("nvidia", "arm64", "arm64", "aarch64"),
            ("amd", "x64", "amd64", "x86_64"),
        ):
            prefix = f"omni-accelerant-{vendor}"
            files = [
                f"{prefix}-linux-{arch}.tar.gz",
                f"{prefix}_1_{deb}.deb",
                f"{prefix}-1-{machine}.AppImage",
            ]
            env = self.env | {
                "GPU_VENDOR": vendor,
                "GPU_ARCH": arch,
                "GPU_ARTIFACT_FILES": "\n".join(files),
            }
            metadata = self.root / f"{vendor}-{arch}.json"
            self.command(META, "create", metadata, env=env)
            self.command(META, "resolve", metadata, env=env)
        forbidden = self.env | {"GPU_VENDOR": "amd", "GPU_ARCH": "arm64"}
        self.command(
            META, "create", self.root / "unsupported.json", env=forbidden, success=False
        )

    def make_archive_identity(self):
        archive = self.root / "candidate.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            for name in self.names:
                zipped.writestr(name, name.encode())
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        identity = [
            "--repository",
            self.env["GITHUB_REPOSITORY"],
            "--revision",
            self.env["GITHUB_SHA"],
            "--run-id",
            "123",
            "--run-attempt",
            "2",
            "--artifact-id",
            "456",
            "--artifact-digest",
            digest,
            "--platform",
            "linux",
            "--vendor",
            "nvidia",
            "--arch",
            "x64",
        ]
        files = [arg for name in self.names for arg in ("--file", name)]
        return archive, digest, identity, files

    def test_immutable_archive_and_receipt_detect_changed_bytes(self):
        archive, digest, identity, files = self.make_archive_identity()
        dest, before = self.root / "packages", self.root / "before.json"
        prepare = SHARED / "prepare_gpu_artifact.py"
        receipt = SHARED / "gpu_artifact_receipt.py"
        self.command(
            prepare,
            "--archive",
            archive,
            "--output",
            dest,
            "--before-receipt",
            before,
            "--max-uncompressed-bytes",
            "100000",
            "--max-compression-ratio",
            "1000",
            *identity,
            *files,
        )
        base = [
            "--directory",
            dest,
            "--receipt",
            before,
            "--check",
            "before-check",
            *identity,
            *files,
        ]
        self.command(receipt, "verify", *base)
        passed = self.root / "gpu-profile.json"
        gpu = [
            "--directory",
            dest,
            "--receipt",
            passed,
            "--check",
            "gpu-model-inference",
            *identity,
            *files,
        ]
        self.command(receipt, "create", *gpu)
        self.command(receipt, "verify", *gpu)
        wrong_id = gpu.copy()
        wrong_id[wrong_id.index("456")] = "457"
        self.command(receipt, "verify", *wrong_id, success=False)
        (dest / self.names[0]).write_bytes(b"changed after profile")
        self.command(receipt, "verify", *base, success=False)
        self.command(receipt, "verify", *gpu, success=False)
        wrong = identity.copy()
        wrong[wrong.index(digest)] = "f" * 64
        self.command(
            prepare,
            "--archive",
            archive,
            "--output",
            self.root / "bad",
            "--before-receipt",
            self.root / "bad.json",
            "--max-uncompressed-bytes",
            "100000",
            "--max-compression-ratio",
            "1000",
            *wrong,
            *files,
            success=False,
        )


if __name__ == "__main__":
    unittest.main()
