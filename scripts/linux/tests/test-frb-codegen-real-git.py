#!/usr/bin/env python3
"""Exercise FRB preflight against real Git indexes without running codegen."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def fixture_environment(source):
    env = {key: value for key, value in source.items() if not key.startswith("GIT_")}
    env.update(
        GIT_CONFIG_NOSYSTEM="1",
        GIT_CONFIG_GLOBAL="/dev/null",
        GIT_CONFIG_SYSTEM="/dev/null",
    )
    return env


@unittest.skipIf(os.name == "nt", "the real-Git fixture runs in Linux CI")
class RealGitPreflightTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.sub = self.root / "third_party/OxidANT"
        self.sub.mkdir(parents=True)
        self.env = fixture_environment(os.environ)
        template = Path(self.temp.name) / "empty-template"
        template.mkdir()
        self.git(self.root, "init", "-q", f"--template={template}")
        self.git(self.sub, "init", "-q", f"--template={template}")
        self.write(
            self.sub / ".gitignore",
            "/target/\n**/target/\n/build/\n/resources/models/\n*.log\n*.ignore.rs\n",
        )
        self.write(self.sub / "src/api/onnx.rs", "pub fn original() {}\n")
        self.write(self.sub / "src/frb_generated.rs", "original Rust binding\n")
        self.write(self.sub / "crates/core/src/lib.rs", "pub fn core() {}\n")
        self.write(
            self.sub / "Cargo.toml", "[package]\nname='fixture'\nversion='0.1.0'\n"
        )
        self.git(self.sub, "add", ".")
        self.commit(self.sub)
        sha = self.git(self.sub, "rev-parse", "HEAD").stdout.strip()
        self.write(
            self.root / "lib/src/rust/frb_generated.dart", "original Dart binding\n"
        )
        target = self.root / "scripts/linux"
        target.mkdir(parents=True)
        for name in ("generate-frb-bindings.sh", "verify-frb-bindings.py"):
            shutil.copyfile(ROOT / "scripts/linux" / name, target / name)
        self.git(self.root, "add", "lib/src/rust")
        self.git(
            self.root,
            "update-index",
            "--add",
            "--cacheinfo",
            f"160000,{sha},third_party/OxidANT",
        )
        self.commit(self.root)
        bindir = self.root / "fake-bin"
        bindir.mkdir()
        cargo = bindir / "cargo"
        self.write(cargo, '#!/bin/sh\ntouch "$CARGO_SENTINEL"\nexit 73\n')
        cargo.chmod(0o755)
        self.marker = self.root / "cargo-reached"
        self.env["PATH"] = str(bindir) + os.pathsep + self.env["PATH"]
        self.env["CARGO_SENTINEL"] = str(self.marker)

    @staticmethod
    def write(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def git(self, cwd, *args):
        return subprocess.run(
            [
                "git",
                "-c",
                "core.hooksPath=/dev/null",
                "-c",
                "commit.gpgsign=false",
                *args,
            ],
            cwd=cwd,
            env=self.env,
            text=True,
            capture_output=True,
            check=True,
        )

    def commit(self, cwd):
        self.git(
            cwd,
            "-c",
            "user.name=FRB fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "fixture",
        )

    def run_wrapper(self):
        return subprocess.run(
            ["bash", str(self.root / "scripts/linux/generate-frb-bindings.sh")],
            cwd=self.root,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def assert_blocked(self, expected):
        result = self.run_wrapper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(expected, result.stderr)
        self.assertFalse(
            self.marker.exists(), "cargo ran before unsafe input was rejected"
        )

    def test_tracked_source_edit_is_rejected(self):
        self.write(self.sub / "src/api/onnx.rs", "changed API\n")
        self.assert_blocked("source checkout has tracked or untracked changes")

    def test_untracked_workspace_source_is_rejected(self):
        self.write(self.sub / "crates/core/src/new.rs", "untracked module\n")
        self.assert_blocked("source checkout has tracked or untracked changes")

    def test_ignored_workspace_source_is_rejected(self):
        self.write(self.sub / "crates/core/src/hidden.ignore.rs", "ignored module\n")
        self.assert_blocked("source inputs contain ignored files")

    def test_ignored_cargo_target_is_allowed(self):
        self.write(
            self.sub / "crates/core/target/debug/build/cache.rs", "ordinary cache\n"
        )
        self.write(self.sub / "build/generated.rs", "ordinary build output\n")
        self.write(
            self.sub / "resources/models/model.onnx", "downloaded runtime model\n"
        )
        self.write(self.sub / "crates/core/worker.log", "ordinary log\n")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 73, result.stderr)
        self.assertTrue(self.marker.exists(), "valid checkout did not reach metadata")

    def test_hidden_source_flags_are_rejected(self):
        for flag in ("--assume-unchanged", "--skip-worktree"):
            with self.subTest(flag=flag):
                self.git(self.sub, "update-index", flag, "src/api/onnx.rs")
                self.write(self.sub / "src/api/onnx.rs", "hidden API change\n")
                self.assert_blocked("assume-unchanged or skip-worktree")
                self.git(
                    self.sub,
                    "update-index",
                    flag.replace("--", "--no-"),
                    "src/api/onnx.rs",
                )
                self.write(self.sub / "src/api/onnx.rs", "pub fn original() {}\n")

    def test_hidden_dart_binding_flags_are_rejected(self):
        for flag in ("--assume-unchanged", "--skip-worktree"):
            with self.subTest(flag=flag):
                relative = "lib/src/rust/frb_generated.dart"
                self.git(self.root, "update-index", flag, relative)
                self.write(self.root / relative, "hidden binding change\n")
                self.assert_blocked("assume-unchanged or skip-worktree")
                self.git(
                    self.root, "update-index", flag.replace("--", "--no-"), relative
                )
                self.write(self.root / relative, "original Dart binding\n")

    def test_linked_oxidant_root_is_rejected(self):
        moved = self.root / "elsewhere"
        self.sub.rename(moved)
        self.sub.symlink_to(moved, target_is_directory=True)
        self.assert_blocked("directory is linked or not a directory")

    def test_git_environment_isolation_and_override_rejection(self):
        poisoned = dict(
            os.environ,
            GIT_DIR=str(self.sub / ".git"),
            GIT_CONFIG_COUNT="1",
            GIT_OBJECT_DIRECTORY="/wrong",
        )
        clean = fixture_environment(poisoned)
        self.assertNotIn("GIT_DIR", clean)
        self.assertNotIn("GIT_CONFIG_COUNT", clean)
        self.assertNotIn("GIT_OBJECT_DIRECTORY", clean)
        self.assertEqual(clean["GIT_CONFIG_GLOBAL"], "/dev/null")
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=self.root,
            env=clean,
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(Path(result.stdout.strip()).resolve(), self.root.resolve())
        self.assertEqual(
            (self.sub / "src/api/onnx.rs").read_text(encoding="utf-8"),
            "pub fn original() {}\n",
        )
        for variable in (
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_INDEX_FILE",
            "GIT_COMMON_DIR",
            "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_NAMESPACE",
            "GIT_PREFIX",
        ):
            with self.subTest(variable=variable):
                self.env[variable] = str(self.sub / ".git")
                self.assert_blocked("Refusing Git repository override")
                del self.env[variable]


if __name__ == "__main__":
    unittest.main()
