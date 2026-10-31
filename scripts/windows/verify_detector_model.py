#!/usr/bin/env python3
"""Verify the bundled detector files against OxidANT's data lock."""

import argparse
import runpy
import sys
from pathlib import Path

REQUIRED = {
    "deim_dfine_n_coco.onnx",
    "deim_dfine_n_coco.LICENSE",
    "deim_dfine_n_coco.NOTICE",
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fetcher", type=Path)
    parser.add_argument("lock", type=Path)
    parser.add_argument("models", type=Path)
    args = parser.parse_args()
    try:
        fetcher = runpy.run_path(str(args.fetcher))
        rows = fetcher["read_lock"](args.lock)
        checksums = {name: sha for sha, name, _url in rows}
        if not REQUIRED.issubset(checksums):
            raise ValueError("model lock is missing required model or notices")
        for name in sorted(REQUIRED):
            path = args.models / name
            if path.is_symlink() or not fetcher["matches"](path, checksums[name]):
                raise ValueError(f"bundled model file is missing, symlinked or changed: {path}")
    except (OSError, ValueError, KeyError) as error:
        print(f"Detector model verification failed: {error}", file=sys.stderr)
        return 1
    print("Bundled detector model and notices match the locked SHA-256 values")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
