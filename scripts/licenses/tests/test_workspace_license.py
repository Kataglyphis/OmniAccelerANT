#!/usr/bin/env python3
"""The copied Cargo workspace must retain a single, truthful MIT license."""
# suite-runner: scripts/linux/tests/test-third-party-licenses.sh

import importlib.util
import os
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
        self.workspace = {
            "path": "crate",
            "license": "LICENSE",
            "roots": [],
            "targets": [],
        }

    def stage(self, license_line):
        content = '[package]\nname = "example"\nversion = "1.0.0"\n' + license_line
        (self.source / "Cargo.toml").write_text(content, encoding="utf-8")
        with (
            mock.patch.object(generator, "ROOT", self.root),
            mock.patch.object(generator, "CARGO_TEXTS", self.texts),
            mock.patch.object(generator.subprocess, "run") as cargo,
        ):
            generator.stage_workspace(self.workspace, self.scratch, {}, {})
        cargo.assert_called_once_with(
            ["cargo", "fetch", "--locked"],
            cwd=self.scratch / "crate",
            check=True,
            env=os.environ.copy(),
        )
        copied = (self.scratch / "crate" / "Cargo.toml").read_text(encoding="utf-8")
        self.assertEqual(tomllib.loads(copied)["package"]["license"], "MIT")
        self.assertEqual(
            (self.scratch / "crate" / "LICENSE").read_text(encoding="utf-8"),
            "MIT fixture\n",
        )
        self.assertEqual(
            (self.source / "Cargo.toml").read_text(encoding="utf-8"), content
        )
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
        self.assert_rejected("license.workspace = true\n")

    def test_workspace_caches_and_offline_propagate_to_fetch_and_stager(self):
        (self.source / "Cargo.toml").write_text(
            '[package]\nname="example"\nversion="1"\n', encoding="utf-8"
        )
        other = self.root / "other"
        other.mkdir()
        (other / "Cargo.toml").write_text(
            '[package]\nname="other"\nversion="1"\nlicense="MIT"\n', encoding="utf-8"
        )
        caches = {"crate": self.root / "cache-one", "other": self.root / "cache-two"}
        for path in caches.values():
            path.mkdir()
        workspace = self.workspace | {"roots": ["example"], "targets": ["test-target"]}
        other_workspace = {
            "path": "other",
            "license": None,
            "roots": ["other"],
            "targets": ["test-target"],
        }
        with (
            mock.patch.object(generator, "ROOT", self.root),
            mock.patch.object(generator, "CARGO_TEXTS", self.texts),
            mock.patch.object(generator, "load_json", return_value={"packages": []}),
            mock.patch.object(generator.subprocess, "run") as run,
            mock.patch.dict(
                os.environ, {"CARGO_HOME": "inherited", "CARGO_NET_OFFLINE": "false"}
            ),
        ):
            generator.stage_workspace(workspace, self.scratch, {}, {}, caches, True)
            generator.stage_workspace(
                other_workspace, self.scratch, {}, {}, caches, True
            )
            self.assertEqual(os.environ["CARGO_HOME"], "inherited")
            self.assertEqual(os.environ["CARGO_NET_OFFLINE"], "false")
        self.assertEqual(run.call_count, 4)
        for number, call in enumerate(run.call_args_list):
            expected = caches["crate"] if number < 2 else caches["other"]
            self.assertEqual(call.kwargs["env"]["CARGO_HOME"], str(expected))
            self.assertEqual(call.kwargs["env"]["CARGO_NET_OFFLINE"], "true")
        self.assertEqual(run.call_args_list[0].args[0], ["cargo", "fetch", "--locked"])
        self.assertEqual(run.call_args_list[1].args[0][1], str(generator.STAGER))

    def test_cache_map_accepts_only_known_unique_absolute_directories(self):
        first, second = self.root / "first cache", self.root / "second cache"
        first.mkdir()
        second.mkdir()
        one, two = (spec["path"] for spec in generator.WORKSPACES)
        self.assertEqual(
            generator.parse_cargo_homes([f"{one}={first}", f"{two}={second}"]),
            {one: first.resolve(), two: second.resolve()},
        )
        for values in (
            ["unknown=" + str(first)],
            [one + "=relative"],
            [one + "="],
            [one + "=" + str(self.root / "missing")],
            [f"{one}={first}", f"{one}={second}"],
        ):
            with self.subTest(values=values), self.assertRaises(ValueError):
                generator.parse_cargo_homes(values)

    def test_cache_options_require_write_and_invalid_cache_never_writes(self):
        for args in (
            ["generator", "--check", "--offline"],
            ["generator", "--write", "--offline", "--cargo-home", "unknown=relative"],
        ):
            with (
                self.subTest(args=args),
                mock.patch.object(generator.sys, "argv", args),
                mock.patch.object(generator, "write") as write,
                mock.patch("sys.stderr"),
            ):
                self.assertEqual(generator.main(), 1)
                write.assert_not_called()

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
        self.assertEqual(
            (self.source / "Cargo.toml").read_text(encoding="utf-8"), content
        )


if __name__ == "__main__":
    unittest.main()
