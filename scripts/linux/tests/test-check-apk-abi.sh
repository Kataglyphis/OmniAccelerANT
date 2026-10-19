#!/usr/bin/env bash
# The APK ABI gate on synthetic APKs: one green, and each way it must go red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
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

make_apk "${work}/good.apk" "${good[@]}"
t_case "arm64-v8a only, every library present"
t_assert_ok bash "$gate" --apk "${work}/good.apk"

make_apk "${work}/x86_64.apk" "${good[@]}" lib/x86_64/libflutter.so lib/x86_64/libapp.so
t_case "an extra x86_64 slice"
t_assert_fails bash "$gate" --apk "${work}/x86_64.apk"

make_apk "${work}/armv7.apk" "${good[@]}" lib/armeabi-v7a/liboxidant.so
t_case "an extra armeabi-v7a slice"
t_assert_fails bash "$gate" --apk "${work}/armv7.apk"

make_apk "${work}/noplugin.apk" lib/arm64-v8a/libflutter.so lib/arm64-v8a/libapp.so lib/arm64-v8a/liboxidant.so
t_case "the plugin library missing"
t_assert_fails bash "$gate" --apk "${work}/noplugin.apk"

make_apk "${work}/nolibs.apk" classes.dex
t_case "no native library at all"
t_assert_fails bash "$gate" --apk "${work}/nolibs.apk"

t_summary
