#!/usr/bin/env python3
"""Exercise the workflow's package commands against the checked-out hub action.

This fixture tests wiring and failure propagation, not real package installation,
ONNX inference, or GPU execution.
"""

import io
import os
import re
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/linux-gpu-candidates.yml"
ACTION = (
    ROOT
    / "third_party/ANTfrastructure/.github/actions/clean-host-package-check/clean-host-package-check.sh"
)


def executable(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def inputs():
    text = WORKFLOW.read_text(encoding="utf-8").split("\n  clean-host:\n", 1)[1]
    match = re.search(
        r"(?m)^        uses: Kataglyphis/ANTfrastructure/\.github/actions/clean-host-package-check@[^\n]+\n        with:\n((?:          .+\n)+)",
        text,
    )
    if match is None:
        raise AssertionError("clean-host shared action and inputs not found")
    values = {}
    for line in match.group(1).splitlines():
        key, value = line.strip().split(": ", 1)
        values[key] = (
            value[1:-1] if value.startswith("'") and value.endswith("'") else value
        )
    return values


class CleanHostWorkflowTests(unittest.TestCase):
    def prepare(self, root, values):
        bin_dir = root / "bin"
        packages = root / "packages"
        workspace = root / "workspace"
        packages.mkdir()
        launch = """#!/bin/sh
[ "$KATAGLYPHIS_ORT_DEVICE" = cpu ] && [ "$KATAGLYPHIS_ONNX_BACKEND" = ort ] && [ "$LD_BIND_NOW" = 1 ] || exit 17
for var in KATAGLYPHIS_ONNX_MODEL ORT_DYLIB_PATH ORT_LIB_LOCATION ONNX_ROOT LD_LIBRARY_PATH; do eval "value=\\${$var+x}"; [ -z "$value" ] || exit 18; done
printf 'launch:%s\\n' "$(basename "$0")" >> "$PROOF_LOG"
[ "${FAIL_LAUNCH:-}" = "$(basename "$0")" ] && exit 0
exit 124
"""
        executable(bin_dir / "omni-accelerant-nvidia", launch)
        executable(bin_dir / "sudo", "#!/bin/sh\nexit 0\n")
        executable(bin_dir / "dpkg-deb", "#!/bin/sh\necho omni-accelerant-nvidia\n")
        executable(bin_dir / "dpkg", "#!/bin/sh\nexit 0\n")
        executable(
            bin_dir / "xvfb-run", '#!/bin/sh\n[ "$1" = -a ] && shift\nexec "$@"\n'
        )
        executable(bin_dir / "timeout", '#!/bin/sh\nshift\nexec "$@"\n')
        executable(
            workspace / "scripts/linux/check-packaged-onnx-runtime.sh",
            """#!/bin/sh
printf 'check:%s:%s\\n' "$1" "$2" >> "$PROOF_LOG"
[ "${FAIL_CHECK:-}" != "$2" ]
""",
        )
        (packages / "candidate.deb").write_bytes(b"fixture")
        executable(packages / "candidate.AppImage", launch)
        with tarfile.open(packages / "candidate.tar.gz", "w:gz") as tar:
            data = launch.encode()
            info = tarfile.TarInfo("bundle/omni_accelerant")
            info.size = len(data)
            info.mode = 0o755
            tar.addfile(info, io.BytesIO(data))
        env = os.environ | {
            "PATH": f"{bin_dir}:/usr/bin:/bin",
            "PROOF_LOG": str(root / "proof.log"),
            "GITHUB_WORKSPACE": str(workspace),
            "PACKAGES_DIR": str(packages),
            "SCAN_ELVES": values["scan-elves"],
            "APT_PACKAGES": values["apt-packages"],
            "KATAGLYPHIS_ONNX_MODEL": "poison",
            "ORT_DYLIB_PATH": "poison",
            "ORT_LIB_LOCATION": "poison",
            "ONNX_ROOT": "poison",
            "LD_LIBRARY_PATH": "poison",
        }
        for package in ("deb", "tarball", "appimage"):
            env[package.upper() + "_GLOB"] = values[package]
            env[package.upper() + "_COMMAND"] = values[package + "-command"].replace(
                "${{ matrix.vendor }}", "nvidia"
            )

        return packages, env

    def test_commands_propagate_failures(self):
        values = inputs()
        self.assertEqual(values["scan-elves"], "false")
        with tempfile.TemporaryDirectory(prefix="omni-clean-host-") as temp:
            root = Path(temp)
            packages, env = self.prepare(root, values)

            def run(extra=None):
                return subprocess.run(
                    ["bash", str(ACTION)],
                    env=env | (extra or {}),
                    text=True,
                    capture_output=True,
                    check=False,
                )

            result = run()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            lines = (root / "proof.log").read_text().splitlines()
            self.assertEqual(sum(line.startswith("check:") for line in lines), 3, lines)
            self.assertEqual(
                sum(line.startswith("launch:") for line in lines), 3, lines
            )
            for target in (
                "/opt/omni-accelerant-nvidia",
                ".",
                str(packages / "candidate.AppImage"),
            ):
                result = run({"FAIL_CHECK": target})
                self.assertNotEqual(
                    result.returncode, 0, f"checker failure ignored for {target}"
                )
            for target in (
                "omni-accelerant-nvidia",
                "omni_accelerant",
                "candidate.AppImage",
            ):
                result = run({"FAIL_LAUNCH": target})
                self.assertNotEqual(
                    result.returncode, 0, f"early process exit accepted for {target}"
                )
            result = run({"TARBALL_GLOB": "missing.tar.gz"})
            self.assertNotEqual(result.returncode, 0, "missing tarball accepted")


if __name__ == "__main__":
    unittest.main()
