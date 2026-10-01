#!/usr/bin/env bash
# The APK ABI gate on synthetic APKs: one green, and each way it must go red.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="${SCRIPT_DIR}/../check-apk-abi.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Writes an APK (a zip) holding the given members, each a one-byte file.
make_apk() {
  local out="$1"
  shift
  python3 - "$out" "$@" <<'EOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for name in sys.argv[2:]:
        z.writestr(name, b"\0")
EOF
}

good=(lib/arm64-v8a/libflutter.so lib/arm64-v8a/libapp.so lib/arm64-v8a/liboxidant.so
  lib/arm64-v8a/libkataglyphis_native_inference.so lib/arm64-v8a/libc++_shared.so classes.dex)

passed=0
expect() {
  local want="$1" name="$2" apk="$3" got=0
  bash "$gate" --apk "$apk" >/dev/null 2>&1 || got=1
  if [ "$want" = pass ] && [ "$got" -ne 0 ]; then
    printf 'FAIL %s: the gate refused a correct APK\n' "$name" >&2
    return 1
  fi
  if [ "$want" = fail ] && [ "$got" -eq 0 ]; then
    printf 'FAIL %s: the gate passed a wrong APK\n' "$name" >&2
    return 1
  fi
  passed=$((passed + 1))
  printf 'ok   %s\n' "$name"
}

make_apk "${work}/good.apk" "${good[@]}"
expect pass "arm64-v8a only, every library present" "${work}/good.apk"

make_apk "${work}/x86_64.apk" "${good[@]}" lib/x86_64/libflutter.so lib/x86_64/libapp.so
expect fail "an extra x86_64 slice" "${work}/x86_64.apk"

make_apk "${work}/armv7.apk" "${good[@]}" lib/armeabi-v7a/liboxidant.so
expect fail "an extra armeabi-v7a slice" "${work}/armv7.apk"

make_apk "${work}/noplugin.apk" lib/arm64-v8a/libflutter.so lib/arm64-v8a/libapp.so lib/arm64-v8a/liboxidant.so
expect fail "the plugin library missing" "${work}/noplugin.apk"

make_apk "${work}/nolibs.apk" classes.dex
expect fail "no native library at all" "${work}/nolibs.apk"

printf '  %d assertion(s) passed\n' "$passed"
