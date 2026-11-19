#!/usr/bin/env python3
"""Check CPU/GPU detector parity for an extracted Omni package on Windows; the run is the hub's."""

from __future__ import annotations

import argparse
import importlib
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "third_party/ANTfrastructure/shared/python"))
from gpu_process import run_process

# ty resolves no import through the path above, so a static import fails the strict Python lane.
shared = importlib.import_module("check_detector_parity")


def run(
    command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None
) -> None:
    """Fail closed on a verifier failure, child failure or timeout."""
    run_process(command, timeout=180, cwd=cwd, env=env)


def verify_inputs(stage: Path, device: str, index: str, repo: Path):
    """Validate the packaged runtime, locked model, fixture and selected adapter."""
    shared.validate_device(device, index)
    stage = stage.resolve(strict=True)
    repo = repo.resolve(strict=True)
    hub = repo / "third_party/ANTfrastructure"
    oxidant = repo / "third_party/OxidANT"
    fixture = oxidant / "crates/inference/tests/fixtures/two_cats.jpg"
    executable = stage / "omni_accelerant.exe"
    model_check = repo / "scripts/windows/verify_detector_model.py"
    fetcher = hub / "linux/scripts/lib/fetch-data-lock.py"
    lock = oxidant / "resources/models/models.lock"
    for path in (fixture, executable, model_check, fetcher, lock):
        if not path.is_file():
            raise ValueError(f"required packaged file or pinned helper missing: {path}")
    shared.verify_runtime(stage)
    shared.verify_fixture(fixture)
    run(
        [
            sys.executable,
            "-I",
            str(model_check),
            str(fetcher),
            str(lock),
            str(stage / "resources/models"),
            "--root",
            str(stage),
        ]
    )
    shared.verify_adapter(hub, device, index, lambda *a, **k: run(*a, **k))
    return stage, fixture, executable, hub


def check(stage: Path, device: str, index: str, repo: Path, temp_root: Path) -> Path:
    """Check locked model bytes, provider placement and repeated real-image outputs."""
    stage, fixture, executable, hub = verify_inputs(stage, device, index, repo)
    work = shared.new_work("omni-windows-parity-", temp_root)
    return shared.check_parity(
        hub,
        stage,
        device,
        index,
        work,
        lambda _label, output, repeat, profile: [
            str(executable),
            "--onnx-profile-image",
            str(fixture),
            str(output),
            str(repeat),
            str(profile),
        ],
        lambda *a, **k: run(*a, **k),
        {"KATAGLYPHIS_ONNX_BACKEND": "ort"},
    )


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
