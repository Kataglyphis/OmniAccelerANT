"""Run trusted GPU checks and clean up their Windows process tree on timeout."""

import os
import subprocess
from pathlib import Path


def run_process(
    command: list[str],
    *,
    timeout: float,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> None:
    process = subprocess.Popen(command, cwd=cwd, env=env)
    try:
        status = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        cleanup_failed = False
        if os.name == "nt":
            taskkill = Path(os.environ["SystemRoot"]) / "System32/taskkill.exe"
            try:
                subprocess.run(
                    [str(taskkill), "/PID", str(process.pid), "/T", "/F"],
                    check=True,
                    timeout=30,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except (OSError, subprocess.SubprocessError):
                cleanup_failed = True
        if process.poll() is None:
            process.kill()
        process.wait(timeout=30)
        if cleanup_failed:
            raise RuntimeError(
                "timed-out GPU process tree could not be fully terminated"
            ) from error
        raise
    if status:
        raise subprocess.CalledProcessError(status, command)
