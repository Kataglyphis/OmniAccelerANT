#!/usr/bin/env python3
"""Verify the bundled detector files against OxidANT's data lock."""

import argparse
import os
import runpy
import stat
import sys
from pathlib import Path

REQUIRED = {
    "deim_dfine_n_coco.onnx",
    "deim_dfine_n_coco.LICENSE",
    "deim_dfine_n_coco.NOTICE",
}


def is_link(path: Path, metadata: os.stat_result) -> bool:
    """Reject symbolic links and Windows junctions or other reparse points."""
    return path.is_symlink() or bool(getattr(metadata, "st_file_attributes", 0) & 0x400)


def verify_directory(
    root: Path, directory: Path, *, allow_missing: bool = False
) -> None:
    """Require an unlinked directory chain contained inside the package root."""
    root = Path(os.path.abspath(root))
    directory = Path(os.path.abspath(directory))
    try:
        relative = directory.relative_to(root)
    except ValueError as error:
        raise ValueError("detector directory escapes the package root") from error
    current = root
    for part in (None, *relative.parts):
        if part is not None:
            current = current / part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            if allow_missing and current != root:
                continue
            raise ValueError(f"detector directory is missing: {current}") from None
        if is_link(current, metadata) or not stat.S_ISDIR(metadata.st_mode):
            raise ValueError(
                f"detector directory is linked or not a directory: {current}"
            )


def verify_files(directory: Path, checksums: dict[str, str], matches) -> None:
    """Require each locked model and notice to be a regular unlinked file."""
    if not REQUIRED.issubset(checksums):
        raise ValueError("model lock is missing required model or notices")
    for name in sorted(REQUIRED):
        path = directory / name
        try:
            metadata = path.lstat()
        except FileNotFoundError:
            raise ValueError(f"bundled model file is missing: {path}") from None
        if (
            is_link(path, metadata)
            or not stat.S_ISREG(metadata.st_mode)
            or not matches(path, checksums[name])
        ):
            raise ValueError(
                f"bundled model file is linked, not regular or changed: {path}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fetcher", type=Path)
    parser.add_argument("lock", type=Path)
    parser.add_argument("models", type=Path)
    parser.add_argument("--root", type=Path, help="runner or extracted package root")
    parser.add_argument(
        "--check-directory",
        action="store_true",
        help="check the destination before staging",
    )
    args = parser.parse_args()
    try:
        verify_directory(
            args.root or args.models, args.models, allow_missing=args.check_directory
        )
        if args.check_directory:
            return 0
        fetcher = runpy.run_path(str(args.fetcher))
        rows = fetcher["read_lock"](args.lock)
        checksums = {name: sha for sha, name, _url in rows}
        verify_files(args.models, checksums, fetcher["matches"])
    except (OSError, ValueError, KeyError) as error:
        print(f"Detector model verification failed: {error}", file=sys.stderr)
        return 1
    print("Bundled detector model and notices match the locked SHA-256 values")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
