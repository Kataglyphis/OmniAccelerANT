#!/usr/bin/env python3
"""Check the recorded submodules support GPU candidates before pulling an image."""

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

GPU_ROWS = {
    "nvidia-x64": {
        "vendor": "nvidia",
        "arch": "x64",
        "platform": "linux/amd64",
        "runner": "ubuntu-26.04",
        "runner-arch": "X64",
        "gpu-runner": "gpu-nvidia-cuda",
        "image-tag": "latest-nvidia",
        "provider": "cuda",
    },
    "nvidia-arm64": {
        "vendor": "nvidia",
        "arch": "arm64",
        "platform": "linux/arm64",
        "runner": "ubuntu-26.04-arm",
        "runner-arch": "ARM64",
        "gpu-runner": "gpu-nvidia-cuda",
        "image-tag": "latest-nvidia",
        "provider": "cuda",
    },
    "amd-x64": {
        "vendor": "amd",
        "arch": "x64",
        "platform": "linux/amd64",
        "runner": "ubuntu-26.04",
        "runner-arch": "X64",
        "gpu-runner": "gpu-amd-rocm",
        "image-tag": "latest-rocm",
        "provider": "migraphx",
    },
}
WINDOWS_GPU_ROWS = {
    "nvidia": {
        "vendor": "nvidia",
        "tag": "winamd64-nvidia",
        "provider": "cuda",
    },
    "amd": {
        "vendor": "amd",
        "tag": "winamd64-rocm",
        "provider": "directml",
    },
}


def gpu_matrix(selection: str) -> dict:
    """Select only requested, supported registry-image and runner tuples."""
    if selection == "all":
        rows = list(GPU_ROWS.values())
    elif selection in GPU_ROWS:
        rows = [GPU_ROWS[selection]]
    else:
        raise ValueError(
            "unsupported GPU tuple; expected all, nvidia-x64, nvidia-arm64 or amd-x64"
        )
    return {"include": rows}


def windows_gpu_matrix(selection: str) -> dict:
    """Select the supported Windows x64 GPU image and provider combinations."""
    if selection == "all":
        rows = list(WINDOWS_GPU_ROWS.values())
    elif selection in WINDOWS_GPU_ROWS:
        rows = [WINDOWS_GPU_ROWS[selection]]
    else:
        raise ValueError("unsupported Windows GPU vendor; expected all, nvidia or amd")
    return {"include": rows}


def validate_scope(scope: str) -> str:
    """Use the shared invocation-scope syntax with the current older hub pin."""
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,31}", scope):
        raise ValueError(
            "scope must start with a lowercase letter and contain at most 32 lowercase letters, digits or hyphens"
        )
    return scope


def require_text(path: Path, *markers: str) -> None:
    """Require the shared helper's capabilities in the checked-out pin."""
    try:
        contents = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"missing pinned GPU helper {path}") from error
    for marker in markers:
        if marker not in contents:
            raise ValueError(f"pinned GPU helper {path} lacks {marker}")


def validate_profile_contract(root: Path) -> None:
    """Require the paired bridge and shared checks before using a GPU runner."""
    oxidant = root / "third_party/OxidANT"
    require_text(oxidant / "src/api/onnx.rs", "pub fn profile_detector_image(")
    require_text(oxidant / "src/detector_profile.rs", "pub fn run(", "infer_rgba(")
    try:
        rust = (oxidant / "src/frb_generated.rs").read_text(encoding="utf-8")
        dart = (root / "lib/src/rust/frb_generated.dart").read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError("missing paired Flutter Rust Bridge bindings") from error
    rust_hash = re.findall(
        r"FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH: i32 = (-?\d+);", rust
    )
    dart_hash = re.findall(r"int get rustContentHash => (-?\d+);", dart)
    if len(rust_hash) != 1 or rust_hash != dart_hash:
        raise ValueError(
            "Rust and Dart bridge bindings are not the same generated pair"
        )
    hub = root / "third_party/ANTfrastructure"
    require_text(
        hub / "linux/scripts/lib/gpu-profile-env.sh", "gpu_without_migraphx_overrides()"
    )
    require_text(hub / "shared/python/verify_ort_profile.py", "--min-runs")
    require_text(hub / "shared/python/compare_detector_parity.py", "--pairwise")


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
    selections = parser.add_mutually_exclusive_group()
    selections.add_argument(
        "--matrix", help="select supported GPU tuples instead of checking pins"
    )
    selections.add_argument(
        "--windows-matrix",
        help="select supported Windows vendors instead of checking pins",
    )
    selections.add_argument(
        "--scope", help="validate an artifact and concurrency scope"
    )
    selections.add_argument(
        "--profile-contract",
        action="store_true",
        help="check paired profiling dependencies",
    )
    args = parser.parse_args()
    try:
        if args.matrix is not None:
            print(json.dumps(gpu_matrix(args.matrix), separators=(",", ":")))
            return 0
        if args.windows_matrix is not None:
            print(
                json.dumps(
                    windows_gpu_matrix(args.windows_matrix), separators=(",", ":")
                )
            )
            return 0
        if args.scope is not None:
            print(validate_scope(args.scope))
            return 0
        if args.profile_contract:
            validate_profile_contract(args.root)
            return 0
        repository = validate(args.root)
    except ValueError as error:
        print(f"GPU candidate preflight: {error}", file=sys.stderr)
        return 1
    print(repository)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
