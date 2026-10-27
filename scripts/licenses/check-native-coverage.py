#!/usr/bin/env python3
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
"""Fail when a shipped native binary has no entry in native-components.json; it does not check static or header-only code."""

from __future__ import annotations

import argparse
import fnmatch
import json
import sys
import zipfile
from pathlib import Path

TABLE = Path(__file__).resolve().parent / "native-components.json"
ELF = b"\x7fELF"


def is_native(name: str, head: bytes, platform: str) -> bool:
    lower = name.lower()
    if platform == "windows":
        return lower.endswith((".dll", ".exe", ".lib", ".pyd"))
    if platform == "android":
        return lower.endswith(".so")
    return head.startswith(ELF) or lower.endswith(".so") or ".so." in lower


def payload(path: Path, platform: str) -> list[str]:
    found: list[str] = []
    if path.is_dir():
        for item in sorted(path.rglob("*")):
            if item.is_file() and not item.is_symlink():
                with item.open("rb") as handle:
                    head = handle.read(4)
                if is_native(item.name, head, platform):
                    found.append(item.relative_to(path).as_posix())
        return found
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = info.filename
            if platform == "android" and not name.startswith("lib/"):
                continue
            with archive.open(info) as handle:
                head = handle.read(4)
            if is_native(Path(name).name, head, platform):
                found.append(name)
    return found


def uncovered(files: list[str], platform: str, table: dict) -> list[str]:
    patterns = [
        p for c in table["components"] for p in c.get("files", {}).get(platform, [])
    ]
    fold = platform == "windows"
    missing = []
    for name in files:
        base = Path(name).name
        base = base.lower() if fold else base
        if not any(
            fnmatch.fnmatchcase(base, p.lower() if fold else p) for p in patterns
        ):
            missing.append(name)
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--platform", required=True, choices=["linux", "windows", "android"]
    )
    parser.add_argument("--table", type=Path, default=TABLE)
    parser.add_argument(
        "payload", type=Path, help="bundle directory, or a ZIP, APK or MSIX"
    )
    args = parser.parse_args()
    try:
        table = json.loads(args.table.read_text(encoding="utf-8"))
        files = payload(args.payload, args.platform)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    if not files:
        print(
            f"FAIL: no native binaries found in {args.payload}; wrong path or platform",
            file=sys.stderr,
        )
        return 1
    missing = uncovered(files, args.platform, table)
    for name in missing:
        print(
            f"FAIL: {name} has no component in {args.table.name}; add it with its license text",
            file=sys.stderr,
        )
    if missing:
        return 1
    print(
        f"PASS: {len(files)} native files in {args.payload} have a license inventory entry"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
