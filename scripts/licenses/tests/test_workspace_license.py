#!/usr/bin/env python3
"""The copied Cargo workspace must retain a single, truthful MIT license."""

import importlib.util
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest import mock

GENERATOR = Path(__file__).resolve().parents[1] / "generate-third-party-licenses.py"
spec = importlib.util.spec_from_file_location("omni_license_generator", GENERATOR)
assert spec and spec.loader
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class WorkspaceLicenseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "crate"
        self.source.mkdir()
        (self.root / "LICENSE").write_text("MIT fixture\n", encoding="utf-8")
        self.texts = self.root / "texts"
        self.texts.mkdir()
        self.scratch = self.root / "scratch"
        self.scratch.mkdir()
        self.workspace = {"path": "crate", "license": "LICENSE", "roots": [], "targets": []}

    def stage(self, license_line):
        content = '[package]\nname = "example"\nversion = "1.0.0"\n' + license_line
        (self.source / "Cargo.toml").write_text(content, encoding="utf-8")
        with (
            mock.patch.object(generator, "ROOT", self.root),
            mock.patch.object(generator, "CARGO_TEXTS", self.texts),
            mock.patch.object(generator.subprocess, "run") as cargo,
        ):
            generator.stage_workspace(self.workspace, self.scratch, {}, {})
        cargo.assert_called_once_with(["cargo", "fetch", "--locked"], cwd=self.scratch / "crate", check=True)
        copied = (self.scratch / "crate" / "Cargo.toml").read_text(encoding="utf-8")
        self.assertEqual(tomllib.loads(copied)["package"]["license"], "MIT")
        self.assertEqual((self.scratch / "crate" / "LICENSE").read_text(encoding="utf-8"), "MIT fixture\n")
        self.assertEqual((self.source / "Cargo.toml").read_text(encoding="utf-8"), content)
        return copied, content

    def test_legacy_manifest_gets_one_mit_declaration(self):
        copied, _ = self.stage("")
        self.assertEqual(copied.count('license = "MIT"'), 1)

    def test_existing_mit_declaration_is_preserved(self):
        copied, original = self.stage('license = "MIT"\n')
        self.assertEqual(copied, original)

    def test_other_license_is_rejected_before_cargo(self):
        self.assert_rejected('license = "Apache-2.0"\n')

    def test_license_file_is_rejected_before_cargo(self):
        self.assert_rejected('license-file = "OTHER-LICENSE"\n')

    def test_inherited_license_is_rejected_before_cargo(self):
        self.assert_rejected('license.workspace = true\n')

    def assert_rejected(self, license_line):
        content = '[package]\nname = "example"\nversion = "1.0.0"\n' + license_line
        (self.source / "Cargo.toml").write_text(content, encoding="utf-8")
        with (
            mock.patch.object(generator, "ROOT", self.root),
            mock.patch.object(generator, "CARGO_TEXTS", self.texts),
            mock.patch.object(generator.subprocess, "run") as cargo,
            self.assertRaisesRegex(ValueError, "expected MIT package license"),
        ):
            generator.stage_workspace(self.workspace, self.scratch, {}, {})
        cargo.assert_not_called()
        self.assertEqual((self.source / "Cargo.toml").read_text(encoding="utf-8"), content)


if __name__ == "__main__":
    unittest.main()
