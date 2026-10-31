#!/usr/bin/env python3
"""Profile trusted same-run Windows MSI and MSIX payloads without installing them."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gpu_process import run_process

FLOOR = 15 * 1024**3 + 512 * 1024**2
CUSHION = 1024**3
MAX_EXPANDED = 4 * 1024**3


def require_space(directory: Path, size: int) -> None:
    if size <= 0 or size > MAX_EXPANDED:
        raise ValueError("expanded size is outside the 4 GiB limit")
    if shutil.disk_usage(directory).free - size < FLOOR + CUSHION:
        raise ValueError("insufficient disk space for payload and 15.5 GiB floor")


def installer_names(names: list[str], vendor: str) -> list[str]:
    if vendor not in {"nvidia", "amd"} or len(names) != 3:
        raise ValueError("expected three Windows GPU installer files")
    msi = [
        name
        for name in names
        if re.fullmatch(
            rf"omni-accelerant-[0-9]+\.[0-9]+\.[0-9]+-windows-x64-{vendor}\.msi", name
        )
    ]
    if len(msi) != 1:
        raise ValueError("expected one MSI for the selected GPU vendor")
    stem = msi[0][:-4]
    if set(names) != {msi[0], stem + ".msix", stem + "-testcert.cer"}:
        raise ValueError("MSI, MSIX and certificate names do not match")
    return sorted(names)


def inspect_zip(path: Path, directory: Path) -> tuple[list[str], int]:
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if not entries or any(
            item.filename.startswith("/")
            or "\\" in item.filename
            or ":" in item.filename
            or ".." in PurePosixPath(item.filename).parts
            for item in entries
        ):
            raise ValueError("unsafe or empty package ZIP")
        names = [item.filename for item in entries]
        if len({name.casefold() for name in names}) != len(names):
            raise ValueError("duplicate package ZIP entry")
        total = sum(item.file_size for item in entries)
    require_space(directory, total)
    return names, total


def payload_root(directory: Path) -> Path:
    executables = list(directory.rglob("omni_accelerant.exe"))
    if len(executables) != 1:
        raise ValueError("expected exactly one extracted application")
    return executables[0].parent


def run_verifier(
    root: Path, device: str, index: str, evidence: Path, repo: Path
) -> None:
    require_space(evidence.parent, 1)
    evidence.mkdir()
    env = os.environ.copy()
    env["RUNNER_TEMP"] = str(evidence)
    command = [
        sys.executable,
        "-I",
        str(repo / "scripts/windows/check_gpu_detector_parity.py"),
        str(payload_root(root)),
        "--device",
        device,
        "--directml-index",
        index,
    ]
    run_process(command, timeout=900, env=env)
    if shutil.disk_usage(evidence).free < FLOOR:
        raise ValueError("verifier output crossed the required disk floor")


def profile(
    packages: Path, vendor: str, device: str, index: str, repo: Path, evidence: Path
) -> None:
    if (
        device not in {"cuda", "directml"}
        or not re.fullmatch(r"0|[1-9][0-9]*", index)
        or int(index) > 2147483647
    ):
        raise ValueError("invalid GPU device or DirectML adapter index")
    if (vendor, device) not in {("nvidia", "cuda"), ("amd", "directml")}:
        raise ValueError("GPU provider does not match the selected vendor")
    names = installer_names([path.name for path in packages.iterdir()], vendor)
    msi = packages / next(name for name in names if name.endswith(".msi"))
    msix = packages / next(name for name in names if name.endswith(".msix"))
    powershell = shutil.which("pwsh")
    if not powershell:
        raise ValueError("PowerShell 7 is required on the GPU runner")
    size_script = repo / "scripts/windows/Get-MsiPayloadSize.ps1"
    size = int(
        subprocess.check_output(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(size_script),
                str(msi),
            ],
            text=True,
            timeout=30,
        ).strip()
    )
    require_space(evidence, size)
    with tempfile.TemporaryDirectory(prefix="omni-gpu-payload-", dir=evidence) as temp:
        root = Path(temp) / "msi"
        root.mkdir()
        msiexec = Path(os.environ["SystemRoot"]) / "System32/msiexec.exe"
        run_process(
            [str(msiexec), "/a", str(msi), f"TARGETDIR={root}", "/qn", "/norestart"],
            timeout=180,
        )
        run_verifier(root, device, index, evidence / "msi", repo)
    inspect_zip(msix, evidence)
    with tempfile.TemporaryDirectory(prefix="omni-gpu-payload-", dir=evidence) as temp:
        root = Path(temp) / "msix"
        root.mkdir()
        with zipfile.ZipFile(msix) as archive:
            archive.extractall(root)
        run_verifier(root, device, index, evidence / "msix", repo)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("plan", "profile"))
    parser.add_argument("path", type=Path)
    parser.add_argument("--vendor", choices=("nvidia", "amd"), required=True)
    parser.add_argument("--device", choices=("cuda", "directml"))
    parser.add_argument("--directml-index", default="0")
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if args.mode == "plan":
        names, size = inspect_zip(args.path, args.evidence)
        print(
            json.dumps(
                {"files": installer_names(names, args.vendor), "expanded_bytes": size}
            )
        )
    else:
        profile(
            args.path,
            args.vendor,
            args.device or "",
            args.directml_index,
            Path(__file__).resolve().parents[2],
            args.evidence,
        )


if __name__ == "__main__":
    main()
