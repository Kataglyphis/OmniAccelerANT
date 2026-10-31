#!/usr/bin/env python3
"""Check generated bridge loader, versions and Rust/Dart content hashes."""

import argparse
import re
import sys
import tomllib
from pathlib import Path


def verify(manifest: dict, dart: str, rust: str, version: str) -> None:
    """Reject an incomplete or incompatible generated bridge pair."""
    expected = manifest["lib"]["name"]
    stems = re.findall(r"\bstem:\s*'([^']+)'", dart)
    if not expected or stems != [expected]:
        raise ValueError(
            f"generated FRB loader does not match Rust library: {stems!r} != {expected!r}"
        )
    dart_versions = re.findall(r"\bString get codegenVersion => '([^']+)'", dart)
    rust_versions = re.findall(
        r'\bFLUTTER_RUST_BRIDGE_CODEGEN_VERSION: &str = "([^"]+)"', rust
    )
    if dart_versions != [version] or rust_versions != [version]:
        raise ValueError(
            f"generated FRB version mismatch: Dart {dart_versions!r}, Rust {rust_versions!r}, expected {version!r}"
        )
    dart_hashes = re.findall(r"\bint get rustContentHash => (-?\d+)", dart)
    rust_hashes = re.findall(
        r"\bFLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH: i32 = (-?\d+)", rust
    )
    if len(dart_hashes) != 1 or dart_hashes != rust_hashes:
        raise ValueError(
            f"generated FRB content hash mismatch: Dart {dart_hashes!r}, Rust {rust_hashes!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--print-version", action="store_true")
    parser.add_argument("--dart", type=Path)
    parser.add_argument("--rust", type=Path)
    args = parser.parse_args()
    try:
        manifest = tomllib.loads(args.manifest.read_text(encoding="utf-8"))
        pin = manifest["workspace"]["dependencies"]["flutter_rust_bridge"]
        if not isinstance(pin, str) or not re.fullmatch(r"=\d+\.\d+\.\d+", pin):
            raise ValueError("FRB runtime must have an exact workspace version pin")
        version = pin[1:]
        if args.print_version:
            print(version)
            return 0
        if args.dart is None or args.rust is None:
            raise ValueError("both Dart and Rust generated files are required")
        verify(
            manifest,
            args.dart.read_text(encoding="utf-8"),
            args.rust.read_text(encoding="utf-8"),
            version,
        )
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"FRB bindings verification failed: {error}", file=sys.stderr)
        return 1
    print("Generated Rust and Dart bridge bindings agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
