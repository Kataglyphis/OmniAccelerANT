#!/usr/bin/env python3
"""Check CPU/GPU detector parity for an extracted Omni package on Windows."""

from __future__ import annotations

import argparse
import hashlib
import itertools
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gpu_process import run_process

FIXTURE_SHA256 = "6d375ac20fadfd400b3033084f8b0581dcc145f7c14e3b24b97975e379c52999"


def child_environment(stage: Path, device: str, index: str) -> dict[str, str]:
    """Select the package's runtime and isolate inherited detector overrides."""
    env = os.environ.copy()
    for key in list(env):
        if key.upper().startswith(("KATAGLYPHIS_", "ORT_", "MIGRAPHX_", "GST_")):
            del env[key]
    env["KATAGLYPHIS_ORT_DEVICE"] = device
    env["KATAGLYPHIS_ONNX_BACKEND"] = "ort"
    env["ORT_DYLIB_PATH"] = str(stage / "onnxruntime.dll")
    if device == "directml":
        env["KATAGLYPHIS_DIRECTML_DEVICE_ID"] = index
    if device == "cpu" and os.name == "nt":
        env["PATH"] = os.pathsep.join(
            (str(stage), str(Path(env["SYSTEMROOT"]) / "System32"))
        )
    return env


def run(
    command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None
) -> None:
    """Fail closed on a verifier failure, child failure or timeout."""
    run_process(command, timeout=180, cwd=cwd, env=env)


def verify_inputs(stage: Path, device: str, index: str, repo: Path):
    """Validate the packaged runtime, locked model, fixture and selected adapter."""
    if (
        device not in {"cuda", "directml"}
        or not re.fullmatch(r"0|[1-9][0-9]*", index)
        or int(index) > 2147483647
    ):
        raise ValueError("invalid GPU provider or DirectML adapter index")
    stage = stage.resolve(strict=True)
    repo = repo.resolve(strict=True)
    hub = repo / "third_party/ANTfrastructure"
    oxidant = repo / "third_party/OxidANT"
    fixture = oxidant / "crates/inference/tests/fixtures/two_cats.jpg"
    executable = stage / "omni_accelerant.exe"
    runtime = stage / "onnxruntime.dll"
    model_check = repo / "scripts/windows/verify_detector_model.py"
    fetcher = hub / "linux/scripts/lib/fetch-data-lock.py"
    comparator = hub / "shared/python/compare_detector_parity.py"
    intervals = hub / "shared/python/verify_ort_profile.py"
    dxgi = hub / "windows/scripts/diagnostics/verify-dxgi-adapter.py"
    lock = oxidant / "resources/models/models.lock"
    for path in (
        fixture,
        executable,
        runtime,
        model_check,
        fetcher,
        comparator,
        intervals,
        lock,
    ):
        if not path.is_file():
            raise ValueError(f"required packaged file or pinned helper missing: {path}")
    metadata = runtime.lstat()
    if (
        runtime.resolve(strict=True).parent != stage
        or runtime.is_symlink()
        or getattr(metadata, "st_file_attributes", 0) & 0x400
        or not stat.S_ISREG(metadata.st_mode)
    ):
        raise ValueError("ONNX Runtime escapes the extracted package")
    if hashlib.sha256(fixture.read_bytes()).hexdigest() != FIXTURE_SHA256:
        raise ValueError("two-cats fixture does not match its expected digest")
    py = [sys.executable, "-I"]
    run(
        py
        + [
            str(model_check),
            str(fetcher),
            str(lock),
            str(stage / "resources/models"),
            "--root",
            str(stage),
        ]
    )
    if device == "directml":
        if not dxgi.is_file():
            raise ValueError("pinned physical DXGI adapter verifier missing")
        run(py + [str(dxgi), "--vendor", "amd", "--index", index])
    return stage, fixture, executable, comparator, intervals


def check(stage: Path, device: str, index: str, repo: Path, temp_root: Path) -> Path:
    """Check locked model bytes, provider placement and repeated real-image outputs."""
    stage, fixture, executable, comparator, intervals = verify_inputs(
        stage, device, index, repo
    )
    py = [sys.executable, "-I"]
    work = Path(tempfile.mkdtemp(prefix="omni-windows-parity-", dir=temp_root))
    for label, selected in (("cpu", "cpu"), ("gpu1", device), ("gpu2", device)):
        output, repeat, profile = (
            work / f"{label}.json",
            work / f"{label}-repeat.json",
            work / f"{label}-profile",
        )
        run(
            [
                str(executable),
                "--onnx-profile-image",
                str(fixture),
                str(output),
                str(repeat),
                str(profile),
            ],
            cwd=stage,
            env=child_environment(stage, selected, index),
        )
        profiles = list(work.glob(f"{label}-profile*.json"))
        if len(profiles) != 1 or not output.is_file() or not repeat.is_file():
            raise ValueError(
                f"expected one {label} detector output and provider profile"
            )
        run(
            py
            + [
                str(intervals),
                str(profiles[0]),
                "--device",
                selected,
                "--min-runs",
                "2",
            ]
        )
    labels = ("cpu", "cpu-repeat", "gpu1", "gpu1-repeat", "gpu2", "gpu2-repeat")
    for left, right in itertools.combinations(labels, 2):
        mode = [] if left == "cpu" else ["--pairwise"]
        run(
            py
            + [str(comparator), str(work / f"{left}.json"), str(work / f"{right}.json")]
            + mode
        )
    return work


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("--device", choices=("cuda", "directml"), required=True)
    parser.add_argument("--directml-index", default="0")
    args = parser.parse_args()
    try:
        work = check(
            args.stage,
            args.device,
            args.directml_index,
            Path(__file__).resolve().parents[2],
            Path(os.environ["RUNNER_TEMP"]),
        )
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Windows detector parity failed: {error}\n")
    print(f"Windows extracted-payload detector parity passed; profiles: {work}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
