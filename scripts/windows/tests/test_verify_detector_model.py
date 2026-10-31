#!/usr/bin/env python3
"""Exercise locked model containment without building the application."""

import hashlib
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/windows/verify_detector_model.py"
spec = importlib.util.spec_from_file_location("model_verifier", SCRIPT)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class ModelVerificationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / "package"
        self.models = self.package / "resources/models"
        self.models.mkdir(parents=True)
        self.fetcher = self.root / "fetcher.py"
        self.fetcher.write_text(
            "import hashlib\n"
            "def read_lock(path):\n"
            "    return [line.split() for line in path.read_text().splitlines()]\n"
            "def matches(path, digest):\n"
            "    return hashlib.sha256(path.read_bytes()).hexdigest() == digest\n"
        )
        self.lock = self.root / "models.lock"
        rows = []
        for name in sorted(verifier.REQUIRED):
            data = name.encode()
            (self.models / name).write_bytes(data)
            rows.append(
                f"{hashlib.sha256(data).hexdigest()} {name} https://example.invalid/{name}\n"
            )
        self.lock.write_text("".join(rows))

    def run_verifier(self, models=None, *extra):
        return subprocess.run(
            [
                sys.executable,
                "-I",
                str(SCRIPT),
                str(self.fetcher),
                str(self.lock),
                str(models or self.models),
                "--root",
                str(self.package),
                *extra,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_correct_payload_and_incomplete_or_changed_lock(self):
        self.assertEqual(self.run_verifier().returncode, 0)
        target = self.models / "deim_dfine_n_coco.NOTICE"
        target.write_bytes(b"changed")
        self.assertNotEqual(self.run_verifier().returncode, 0)
        target.write_bytes(target.name.encode())
        self.lock.write_text("\n".join(self.lock.read_text().splitlines()[:-1]))
        self.assertNotEqual(self.run_verifier().returncode, 0)

    def test_missing_destination_is_only_allowed_for_preflight(self):
        target = self.package / "new/models"
        self.assertNotEqual(self.run_verifier(target).returncode, 0)
        self.assertEqual(self.run_verifier(target, "--check-directory").returncode, 0)
        self.assertFalse(target.exists())
        self.assertNotEqual(
            self.run_verifier(self.root / "outside", "--check-directory").returncode, 0
        )
        (self.package / "new").write_text("not a directory")
        self.assertNotEqual(
            self.run_verifier(target, "--check-directory").returncode, 0
        )

    @unittest.skipIf(
        os.name == "nt", "creating symbolic links may require Windows privileges"
    )
    def test_file_and_ancestor_symlinks_are_rejected_even_inside_root(self):
        target = self.models / "deim_dfine_n_coco.LICENSE"
        saved = self.models / "saved"
        target.rename(saved)
        target.symlink_to(saved.name)
        self.assertNotEqual(self.run_verifier().returncode, 0)
        target.unlink()
        saved.rename(target)
        models = self.package / "resources/models"
        saved_dir = self.package / "resources/saved-models"
        models.rename(saved_dir)
        models.symlink_to(saved_dir.name, target_is_directory=True)
        self.assertNotEqual(self.run_verifier().returncode, 0)
        self.assertNotEqual(
            self.run_verifier(
                self.package / "resources/models/new", "--check-directory"
            ).returncode,
            0,
        )

    def test_reparse_point_metadata_fails_for_directory_and_file(self):
        fake = SimpleNamespace(st_file_attributes=0x400)
        self.assertTrue(verifier.is_link(self.models, fake))
        original = verifier.is_link
        for flagged in (self.models, self.models / "deim_dfine_n_coco.onnx"):
            with (
                self.subTest(flagged=flagged),
                patch.object(
                    verifier,
                    "is_link",
                    side_effect=lambda path, metadata, target=flagged: (
                        path == target or original(path, metadata)
                    ),
                ),
                self.assertRaises(ValueError),
            ):
                verifier.verify_directory(self.package, self.models)
                verifier.verify_files(
                    self.models,
                    {
                        name: hashlib.sha256(name.encode()).hexdigest()
                        for name in verifier.REQUIRED
                    },
                    lambda path, digest: (
                        hashlib.sha256(path.read_bytes()).hexdigest() == digest
                    ),
                )

    def test_preflight_precedes_writes_in_windows_staging(self):
        source = (ROOT / "scripts/windows/Stage-DetectorModel.ps1").read_text()
        self.assertLess(
            source.index("--root $runner --check-directory"),
            source.index("Copy-Item -Destination $models"),
        )
        self.assertIn("$models --root $runner", source)


if __name__ == "__main__":
    unittest.main()
