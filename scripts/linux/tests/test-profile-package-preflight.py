#!/usr/bin/env python3
"""Exercise trusted package measurement and scratch-space checks."""

import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import textwrap
import unittest
import zipfile
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "preflight-profile-packages.py"
SPEC = importlib.util.spec_from_file_location("profile_package_preflight", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load profile package preflight")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def archive(name, data=b"ok", link=None):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as output:
        member = tarfile.TarInfo(name)
        if link is None:
            member.size = len(data)
            output.addfile(member, io.BytesIO(data))
        else:
            member.type = tarfile.SYMTYPE
            member.linkname = link
            output.addfile(member)
    stream.seek(0)
    return stream


class ProfilePackagePreflightTests(unittest.TestCase):
    def test_minimum_floor_cannot_be_lowered(self):
        with (
            mock.patch.dict(MODULE.os.environ, {"PROFILE_DISK_FLOOR_BYTES": "1"}),
            self.assertRaisesRegex(ValueError, "at least 15.5"),
        ):
            MODULE.floor()

    def test_artifact_metadata_binds_size_to_run_and_revision(self):
        metadata = {
            "id": 42,
            "expired": False,
            "size_in_bytes": 12345,
            "workflow_run": {"id": 77, "head_sha": "a" * 40},
        }
        env = {
            "GITHUB_REPOSITORY": "Kataglyphis/OmniAccelerANT",
            "GITHUB_RUN_ID": "77",
            "GITHUB_SHA": "a" * 40,
            "GH_TOKEN": "fixture-token",
        }
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps(
            metadata
        ).encode()
        opener = mock.Mock()
        opener.open.return_value = response
        with (
            mock.patch.dict(MODULE.os.environ, env),
            mock.patch.object(
                MODULE.urllib.request, "build_opener", return_value=opener
            ) as build,
        ):
            self.assertEqual(MODULE.artifact_size("42"), 12345)
            self.assertIsInstance(build.call_args.args[0], MODULE.NoRedirect)
            self.assertEqual(
                opener.open.call_args.args[0].full_url,
                "https://api.github.com/repos/Kataglyphis/OmniAccelerANT/actions/artifacts/42",
            )
            metadata["workflow_run"]["head_sha"] = "b" * 40
            response.__enter__.return_value.read.return_value = json.dumps(
                metadata
            ).encode()
            with self.assertRaisesRegex(ValueError, "does not match"):
                MODULE.artifact_size("42")

    def test_artifact_api_redirect_is_rejected(self):
        handler = MODULE.NoRedirect()
        self.assertIsNone(
            handler.redirect_request(None, None, 302, "", {}, "https://example.invalid")
        )

    def test_outer_zip_expanded_size_and_count(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "packages.zip"
            with zipfile.ZipFile(path, "w") as output:
                for name in ("a", "b", "c"):
                    output.writestr(name, b"12345")
            self.assertEqual(MODULE.outer_size(path), 15)
            with (
                mock.patch.object(MODULE, "MAX_BYTES", 4),
                self.assertRaises(ValueError),
            ):
                MODULE.outer_size(path)
            with zipfile.ZipFile(path, "a") as output:
                output.writestr("d", b"x")
            with self.assertRaises(ValueError):
                MODULE.outer_size(path)

    def test_tar_measure_and_reject_path_and_link_escape(self):
        self.assertEqual(MODULE.tar_size(archive("bundle/data", b"hello")), 5)
        for stream in (
            archive("../escape"),
            archive("bundle/link", link="../../escape"),
        ):
            with self.subTest(stream=stream), self.assertRaises(ValueError):
                MODULE.tar_size(stream)
        self.assertEqual(MODULE.tar_size(archive("bundle/link", link="data")), 0)

    def test_expanded_size_and_entry_caps(self):
        with (
            mock.patch.object(MODULE, "MAX_BYTES", 4),
            self.assertRaisesRegex(ValueError, "expanded-size cap"),
        ):
            MODULE.tar_size(archive("bundle/data", b"12345"))
        with (
            mock.patch.object(MODULE, "MAX_ENTRIES", 0),
            self.assertRaisesRegex(ValueError, "too many"),
        ):
            MODULE.tar_size(archive("bundle/data"))

    def test_stage_reserve_and_disk_floor(self):
        plan = {"tar": 10, "deb": 20, "image": 30, "image_file": 40}
        with mock.patch.dict(
            MODULE.os.environ, {"PROFILE_DISK_FLOOR_BYTES": str(MODULE.DEFAULT_FLOOR)}
        ):
            sizes = {
                "initial": 130,
                "tar": 10,
                "deb": 20,
                "image": 130,
                "extract": 90,
                "runtime": 0,
                "launch": 60,
            }
            for stage, size in sizes.items():
                need = MODULE.DEFAULT_FLOOR + MODULE.CUSHION + size
                with (
                    self.subTest(stage=stage),
                    mock.patch.object(
                        MODULE.shutil, "disk_usage", return_value=mock.Mock(free=need)
                    ),
                ):
                    MODULE.check(plan, stage, Path("."))
                with (
                    self.subTest(stage=stage),
                    mock.patch.object(
                        MODULE.shutil,
                        "disk_usage",
                        return_value=mock.Mock(free=need - 1),
                    ),
                    self.assertRaisesRegex(ValueError, "insufficient scratch"),
                ):
                    MODULE.check(plan, stage, Path("."))

    def test_missing_squashfs_tool_fails_before_image_access(self):
        with (
            mock.patch.object(MODULE.shutil, "which", return_value=None),
            self.assertRaisesRegex(ValueError, "unsquashfs is required"),
        ):
            MODULE.image_size(Path("missing.AppImage"))

    def test_ambiguous_squashfs_listing_and_size_are_rejected(self):
        def process(lines):
            result = mock.Mock()
            result.stdout = iter(lines)
            result.wait.return_value = 0
            return result

        row = "-rw-r--r-- 0/0 5 2026-01-01 00:00 squashfs-root/file\n"
        with (
            mock.patch.object(
                MODULE.shutil, "which", return_value="/usr/bin/unsquashfs"
            ),
            mock.patch.object(MODULE, "image_offset", return_value=64),
            mock.patch.object(MODULE.subprocess, "Popen", return_value=process([row])),
        ):
            self.assertEqual(MODULE.image_size(Path("x")), 5)
        with (
            mock.patch.object(
                MODULE.shutil, "which", return_value="/usr/bin/unsquashfs"
            ),
            mock.patch.object(MODULE, "image_offset", return_value=64),
            mock.patch.object(
                MODULE.subprocess, "Popen", return_value=process([row, "name\n"])
            ),
            self.assertRaisesRegex(ValueError, "ambiguous"),
        ):
            MODULE.image_size(Path("x"))
        with (
            mock.patch.object(
                MODULE.shutil, "which", return_value="/usr/bin/unsquashfs"
            ),
            mock.patch.object(MODULE, "image_offset", return_value=64),
            mock.patch.object(MODULE, "MAX_BYTES", 4),
            mock.patch.object(MODULE.subprocess, "Popen", return_value=process([row])),
            self.assertRaisesRegex(ValueError, "expanded-size cap"),
        ):
            MODULE.image_size(Path("x"))


@unittest.skipUnless(sys.platform.startswith("linux"), "GNU df guard runs on Linux")
class RunnerDiskGuardTests(unittest.TestCase):
    def test_actual_workflow_guard_uses_gnu_df(self):
        root = SCRIPT.parents[2]
        workflow = (root / ".github/workflows/linux-gpu-candidates.yml").read_text(
            encoding="utf-8"
        )
        step = workflow.split(
            "      - name: Check GPU runner package inspection tools\n", 1
        )[1]
        step = step.split("      - uses: actions/checkout@", 1)[0]
        command = textwrap.dedent(step.split("        run: |\n", 1)[1])
        with tempfile.TemporaryDirectory() as temp:
            bin_dir = Path(temp)
            for tool in ("python3", "dpkg-deb", "unsquashfs"):
                stub = bin_dir / tool
                stub.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                stub.chmod(0o755)
            env = os.environ.copy()
            env.update(
                {
                    "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
                    "PROFILE_DISK_FLOOR_BYTES": "16642998272",
                    "RUNNER_TEMP": str(root),
                    "GITHUB_WORKSPACE": str(root),
                }
            )
            result = subprocess.run(
                ["bash", "-c", command],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            if shutil.disk_usage(root).free >= 16642998272 + 1073741824:
                self.assertEqual(result.returncode, 0, result.stderr)
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Insufficient free space", result.stderr)
            env["PROFILE_DISK_FLOOR_BYTES"] = "1"
            result = subprocess.run(
                ["bash", "-c", command],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Disk floor must be at least", result.stderr)
            env["PROFILE_DISK_FLOOR_BYTES"] = "999999999999999999"
            result = subprocess.run(
                ["bash", "-c", command],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Insufficient free space", result.stderr)


if __name__ == "__main__":
    unittest.main()
