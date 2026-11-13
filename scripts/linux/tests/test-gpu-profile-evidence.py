#!/usr/bin/env python3
"""Synthetic tests for receipt, archive identity and real profile consumers."""

import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
META = REPO / "scripts/linux/gpu-profile-metadata.py"
SHARED = REPO / "third_party/ANTfrastructure/shared/python"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def profile(provider):
    events = []
    for start in (0, 20):
        events += [
            {
                "cat": "Session",
                "name": "model_run",
                "ph": "X",
                "pid": 7,
                "ts": start,
                "dur": 10,
            },
            {
                "cat": "Node",
                "name": "Conv",
                "ph": "X",
                "pid": 7,
                "ts": start + 1,
                "dur": 2,
                "args": {"provider": provider, "op_name": "Conv"},
            },
        ]
    return json.dumps(events).encode()


def detections():
    return json.dumps(
        {
            "schema_version": 1,
            "width": 100,
            "height": 100,
            "detections": [
                {"class": 15, "score": 0.95, "box": [5, 55, 35, 95]},
                {"class": 15, "score": 0.91, "box": [60, 55, 95, 95]},
            ],
        }
    ).encode()


def loader(fmt, vendor):
    variant = f"omni-accelerant-{vendor}"
    root = "/tmp/omni-gpu-packages.ABC12345"
    directory = {
        "tar": f"{root}/tar/{variant}-bundle/lib",
        "deb": f"{root}/deb/opt/{variant}/lib",
        "appimage": f"{root}/image-tmp/appimage_extracted_{'a' * 32}/usr/lib/{variant}/lib",
    }[fmt]
    return f"      99: calling init: {directory}/libonnxruntime.so.1\n".encode()


class EvidenceTests(unittest.TestCase):
    VENDOR = "nvidia"
    ARCH = "x64"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omni-consumer-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = os.environ | {
            "GITHUB_REPOSITORY": "Kataglyphis/OmniAccelerANT",
            "GITHUB_SHA": "a" * 40,
            "GITHUB_RUN_ID": "123",
            "GITHUB_RUN_ATTEMPT": "2",
            "GITHUB_OUTPUT": str(self.root / "out"),
            "GPU_VENDOR": self.VENDOR,
            "GPU_ARCH": self.ARCH,
            "GPU_ARTIFACT_ID": "456",
        }
        deb = "amd64" if self.ARCH == "x64" else "arm64"
        machine = "x86_64" if self.ARCH == "x64" else "aarch64"
        prefix = f"omni-accelerant-{self.VENDOR}"
        self.names = [
            f"{prefix}-linux-{self.ARCH}.tar.gz",
            f"{prefix}_1_{deb}.deb",
            f"{prefix}-1-{machine}.AppImage",
        ]
        self.env["GPU_ARTIFACT_FILES"] = "\n".join(self.names)
        packages = self.root / "packages"
        packages.mkdir()
        for name in self.names:
            (packages / name).write_bytes(name.encode())
        self.candidate = self.root / "candidate.zip"
        with zipfile.ZipFile(self.candidate, "w") as z:
            for name in self.names:
                z.write(packages / name, name)
        self.env["GPU_ARTIFACT_DIGEST"] = "sha256:" + sha(self.candidate)
        self.candidate_meta = self.root / "candidate.json"
        self.call(META, "create", self.candidate_meta)
        self.prepare_evidence(packages)

    def prepare_evidence(self, packages):
        ident = [
            "--repository",
            self.env["GITHUB_REPOSITORY"],
            "--revision",
            "a" * 40,
            "--run-id",
            "123",
            "--run-attempt",
            "2",
            "--artifact-id",
            "456",
            "--artifact-digest",
            sha(self.candidate),
            "--platform",
            "linux",
            "--arch",
            self.ARCH,
            "--vendor",
            self.VENDOR,
        ]
        files = [arg for name in self.names for arg in ("--file", name)]
        self.entries = {}
        for name, check in (
            ("clean-host-receipt.json", "clean-host-inference"),
            ("receipt.json", "gpu-model-inference"),
        ):
            receipt = self.root / name
            self.call(
                SHARED / "gpu_artifact_receipt.py",
                "create",
                "--directory",
                packages,
                "--receipt",
                receipt,
                "--check",
                check,
                *ident,
                *files,
            )
            self.entries[name] = receipt.read_bytes()
        for fmt in ("tar", "deb", "appimage"):
            gpu = "CUDAExecutionProvider" if self.VENDOR == "nvidia" else "MIGraphX"
            for mode, provider in (("cpu", "CPUExecutionProvider"), ("gpu", gpu)):
                self.entries[f"{fmt}/{mode}-profile_1.json"] = profile(provider)
                self.entries[f"{fmt}/{mode}-loader.9"] = loader(fmt, self.VENDOR)
                for n in (1, 2):
                    self.entries[f"{fmt}/{mode}-{n}.json"] = detections()
        self.profile = self.root / "evidence.zip"
        self.evidence_meta = self.root / "evidence.json"
        self.build_evidence()

    def call(self, *args, ok=True, env=None):
        result = subprocess.run(
            [sys.executable, "-I", *(str(arg) for arg in args)],
            env=env or self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def build_evidence(self, receipt_hash=None):
        self.profile.unlink(missing_ok=True)
        self.evidence_meta.unlink(missing_ok=True)
        with zipfile.ZipFile(self.profile, "w", compression=zipfile.ZIP_DEFLATED) as z:
            for name, content in self.entries.items():
                z.writestr(name, content)
        env = self.env | {
            "GPU_PROFILE_ARTIFACT_ID": "789",
            "GPU_PROFILE_ARTIFACT_DIGEST": "sha256:" + sha(self.profile),
            "GPU_PROFILE_RECEIPT_SHA256": receipt_hash
            or hashlib.sha256(self.entries["receipt.json"]).hexdigest(),
        }
        self.call(META, "evidence", self.evidence_meta, env=env)

    def verify(self, ok=True, **override):
        args = {
            "--repo": REPO,
            "--candidate-metadata": self.candidate_meta,
            "--evidence-metadata": self.evidence_meta,
            "--candidate-archive": self.candidate,
            "--profile-archive": self.profile,
            "--candidate-id": "456",
            "--candidate-digest": self.env["GPU_ARTIFACT_DIGEST"],
            "--profile-id": "789",
            "--profile-digest": sha(self.profile),
        }
        args.update(override)
        self.call(
            REPO / "scripts/linux/verify-gpu-profile-evidence.py",
            *(item for pair in args.items() for item in pair),
            ok=ok,
        )

    def refresh_archive_digest(self):
        data = json.loads(self.evidence_meta.read_text())
        data["profile_artifact_digest"] = "sha256:" + sha(self.profile)
        self.evidence_meta.write_text(json.dumps(data))

    def test_valid_and_independent_identity(self):
        self.verify()
        for key, value in (
            ("--candidate-id", "999"),
            ("--profile-id", "999"),
            ("--candidate-digest", "a" * 64),
            ("--profile-digest", "b" * 64),
        ):
            self.verify(ok=False, **{key: value})

    def test_evidence_metadata_must_match_separate_candidate_and_attempt(self):
        original = json.loads(self.evidence_meta.read_text())
        for key, value in (
            ("artifact_id", "999"),
            ("artifact_digest", "a" * 64),
            ("run_id", "124"),
            ("run_attempt", "3"),
            ("revision", "b" * 40),
            ("files", [self.names[0], self.names[1], "changed.AppImage"]),
        ):
            self.evidence_meta.write_text(json.dumps(original | {key: value}))
            self.verify(ok=False)
        self.evidence_meta.write_text('{"run_id":"123","run_id":"123"}')
        self.verify(ok=False)

    def test_expected_run_and_tuple_must_match(self):
        original = self.env.copy()
        for key, value in (
            ("GITHUB_REPOSITORY", "Kataglyphis/other"),
            ("GITHUB_SHA", "b" * 40),
            ("GITHUB_RUN_ID", "124"),
            ("GITHUB_RUN_ATTEMPT", "3"),
            ("GPU_VENDOR", "amd" if self.VENDOR == "nvidia" else "nvidia"),
            ("GPU_ARCH", "arm64" if self.ARCH == "x64" else "x64"),
        ):
            self.env = original | {key: value}
            self.verify(ok=False)
        self.env = original

    def test_gpu_receipt_must_cover_all_original_packages(self):
        data = json.loads(self.entries["receipt.json"])
        data["files"].pop(self.names[0])
        self.entries["receipt.json"] = json.dumps(data).encode()
        self.build_evidence()
        self.verify(ok=False)

    def test_receipt_and_candidate_bytes_are_bound(self):
        self.build_evidence(receipt_hash="f" * 64)
        self.verify(ok=False)
        self.build_evidence()
        original = self.candidate.read_bytes()
        self.candidate.write_bytes(original + b"changed")
        self.verify(ok=False)

    def test_profile_fallback_and_detector_mutation_are_rejected(self):
        self.entries["deb/gpu-profile_1.json"] = profile("CPUExecutionProvider")
        self.build_evidence()
        self.verify(ok=False)
        self.entries["deb/gpu-profile_1.json"] = profile(
            "CUDAExecutionProvider" if self.VENDOR == "nvidia" else "MIGraphX"
        )
        self.entries["tar/gpu-2.json"] = b"{}"
        self.build_evidence()
        self.verify(ok=False)

    def test_missing_ambiguous_and_unsafe_evidence_are_rejected(self):
        del self.entries["tar/gpu-loader.9"]
        self.build_evidence()
        self.verify(ok=False)
        self.entries["tar/gpu-loader.9"] = loader("tar", self.VENDOR)
        self.entries["tar/gpu-profile_2.json"] = profile(
            "CUDAExecutionProvider" if self.VENDOR == "nvidia" else "MIGraphX"
        )
        self.build_evidence()
        self.verify(ok=False)
        del self.entries["tar/gpu-profile_2.json"]
        self.entries["../escape"] = b"bad"
        self.build_evidence()
        self.verify(ok=False)

    def test_symlink_evidence_and_mismatched_receipt_are_rejected(self):
        original = json.loads(self.entries["clean-host-receipt.json"])
        original["identity"]["run_attempt"] = "3"
        self.entries["clean-host-receipt.json"] = json.dumps(original).encode()
        self.build_evidence()
        self.verify(ok=False)
        del self.entries["clean-host-receipt.json"]
        self.build_evidence()
        symlink = zipfile.ZipInfo("clean-host-receipt.json")
        symlink.create_system = 3
        symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(self.profile, "a") as z:
            z.writestr(symlink, "receipt.json")
        self.refresh_archive_digest()
        self.verify(ok=False)

    def test_duplicate_evidence_entry_is_rejected(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.profile, "a") as z:
                z.writestr("receipt.json", self.entries["receipt.json"])
        self.refresh_archive_digest()
        self.verify(ok=False)

    def test_windows_aliases_and_control_paths_are_rejected(self):
        for name in (
            "C:/evil",
            "tar/CON.txt",
            "tar/aux.",
            "tar/file ",
            "tar/control\x01.txt",
            "tar/bad|name",
            "tar//double",
        ):
            self.entries[name] = b"extra"
            self.build_evidence()
            self.verify(ok=False)
            del self.entries[name]

    def test_loader_evidence_rejects_empty_wrong_and_mixed_paths(self):
        original = self.entries["tar/gpu-loader.9"]
        for replacement in (
            b"",
            b"nothing was loaded\n",
            b"99: calling init: /usr/lib/libonnxruntime.so.1\n",
            loader("deb", self.VENDOR),
            loader("tar", "amd" if self.VENDOR == "nvidia" else "nvidia"),
            original + b"99: calling init: /usr/lib/libonnxruntime.so.1\n",
        ):
            self.entries["tar/gpu-loader.9"] = replacement
            self.build_evidence()
            self.verify(ok=False)


class NvidiaArmEvidenceTests(EvidenceTests):
    ARCH = "arm64"


class AmdX64EvidenceTests(EvidenceTests):
    VENDOR = "amd"


if __name__ == "__main__":
    unittest.main()
