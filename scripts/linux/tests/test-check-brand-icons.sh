#!/usr/bin/env bash
# Copyright (c) 2026 Kataglyphis
# SPDX-License-Identifier: MIT
# Tests that every committed launcher icon must derive from the repo logo; the SVG-to-PNG render is not checked.
set -uo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${script_dir}/../../.." && pwd)"
source "${script_dir}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
check="${repo}/scripts/linux/check-brand-icons.py"

fresh_tree() {
  rm -rf "$work/tree"
  mkdir -p "$work/tree/android/app/src/main" "$work/tree/assets" "$work/tree/windows/runner"
  cp -a "${repo}/images" "${repo}/web" "$work/tree/"
  cp -a "${repo}/assets/icons" "$work/tree/assets/"
  cp -a "${repo}/android/app/src/main/res" "$work/tree/android/app/src/main/"
  cp -a "${repo}/windows/runner/resources" "$work/tree/windows/runner/"
}

t_case 'the committed icons derive from the logo'
t_assert_ok python3 "$check"
fresh_tree
t_assert_ok python3 "$check" --repo-root "$work/tree"

t_case 'a foreign launcher icon fails'
t_write_png "$work/tree/android/app/src/main/res/mipmap-mdpi/ic_launcher.png" 48 48
t_assert_fails python3 "$check" --repo-root "$work/tree"

t_case 'a mirrored logo fails'
fresh_tree
python3 - "$check" "$work/tree/web/icons/Icon-512.png" <<'PY'
import importlib.util
import struct
import sys
import zlib
from pathlib import Path

spec = importlib.util.spec_from_file_location("icons", sys.argv[1])
icons = importlib.util.module_from_spec(spec)
spec.loader.exec_module(icons)
width, height, rows = icons.decode_png(Path(sys.argv[2]).read_bytes())
raw = b"".join(b"\x00" + b"".join(bytes(row[x * 4:x * 4 + 4]) for x in reversed(range(width))) for row in rows)


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
Path(sys.argv[2]).write_bytes(png)
PY
t_assert_fails python3 "$check" --repo-root "$work/tree"

t_case 'a drifted SVG copy fails'
fresh_tree
printf '<!-- drift -->\n' >> "$work/tree/assets/icons/kataglyphis_app_icon.svg"
t_assert_fails python3 "$check" --repo-root "$work/tree"

t_case 'ObservANT packages the logo itself'
t_assert_contains "$(cat "${repo}/scripts/linux/observant/package-observant.sh")" 'install -m 644 "${repo_root}/images/logo.svg"'

t_summary
