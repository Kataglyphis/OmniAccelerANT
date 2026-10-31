#!/usr/bin/env python3
"""Check the recorded submodules support GPU candidates before pulling an image."""

import argparse
import re
import sys
import tomllib
from pathlib import Path


def require_text(path: Path, *markers: str) -> None:
    """Require the shared helper's capabilities in the checked-out pin."""
    try:
        contents = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"missing pinned GPU helper {path}") from error
    for marker in markers:
        if marker not in contents:
            raise ValueError(f"pinned GPU helper {path} lacks {marker}")


def validate(root: Path) -> str:
    """Return the pinned image repository after checking both dependency contracts."""
    manifest = root / "third_party/OxidANT/crates/inference/Cargo.toml"
    try:
        with manifest.open("rb") as stream:
            metadata = tomllib.load(stream).get("package", {}).get("metadata", {})
        devices = metadata.get("kataglyphis", {}).get("ort-devices", [])
    except (OSError, tomllib.TOMLDecodeError, AttributeError) as error:
        raise ValueError(
            "pinned OxidANT has no readable GPU capability marker"
        ) from error
    if (
        not isinstance(devices, list)
        or not all(isinstance(value, str) for value in devices)
        or not {"cuda", "migraphx"}.issubset(devices)
    ):
        raise ValueError(
            "pinned OxidANT must advertise strict CUDA and MIGraphX selection"
        )

    hub = root / "third_party/ANTfrastructure/linux/scripts"
    packaging = hub / "06-packaging"
    require_text(
        packaging / "ort-runtime-bundle.sh",
        "ort_host_runtime_needed()",
        "ort_assert_no_bundled_host_runtime()",
    )
    require_text(packaging / "elf-closure.sh", "--direct-only", "--reject-source-root")
    require_text(packaging / "bundle-loader.sh", "--external-library-path")
    require_text(packaging / "stage-ort-wheel-licenses.py", "--require-unstripped")
    require_text(
        packaging / "verify-ort-appimage-payload.sh",
        "--require-unstripped",
        "ort_assert_no_bundled_host_runtime",
    )
    versions = hub / "01-core/versions.env"
    try:
        values = re.findall(
            r"(?m)^IMAGE_REGISTRY_PREFIX=(\S+)$", versions.read_text(encoding="utf-8")
        )
    except OSError as error:
        raise ValueError("pinned ANTfrastructure image registry is missing") from error
    if len(values) != 1 or not re.fullmatch(
        r"ghcr\.io/[a-z0-9_.-]+/[a-z0-9_.-]+", values[0]
    ):
        raise ValueError(
            "pinned ANTfrastructure image registry is invalid or ambiguous"
        )
    return values[0]


def main() -> int:
    """Print the image repository only after all pinned capabilities pass."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        repository = validate(args.root)
    except ValueError as error:
        print(f"GPU candidate preflight: {error}", file=sys.stderr)
        return 1
    print(repository)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
