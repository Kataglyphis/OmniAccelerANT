#!/usr/bin/env bash
# The APK ABI gate on synthetic APKs: one green, and each way it must go red.
set -uo pipefail

# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
gate="${KATAGLYPHIS_REPO_ROOT}/scripts/linux/check-apk-abi.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"

good=(lib/arm64-v8a/libflutter.so lib/arm64-v8a/libapp.so lib/arm64-v8a/liboxidant.so
  lib/arm64-v8a/libkataglyphis_native_inference.so lib/arm64-v8a/libc++_shared.so classes.dex)

fixture_make_apk "${work}/good.apk" "${good[@]}"
t_case "arm64-v8a only, every library present"
t_assert_ok bash "$gate" --apk "${work}/good.apk"

fixture_make_apk "${work}/x86_64.apk" "${good[@]}" lib/x86_64/libflutter.so lib/x86_64/libapp.so
t_case "an extra x86_64 slice"
t_assert_fails bash "$gate" --apk "${work}/x86_64.apk"

fixture_make_apk "${work}/armv7.apk" "${good[@]}" lib/armeabi-v7a/liboxidant.so
t_case "an extra armeabi-v7a slice"
t_assert_fails bash "$gate" --apk "${work}/armv7.apk"

fixture_make_apk "${work}/noplugin.apk" lib/arm64-v8a/libflutter.so lib/arm64-v8a/libapp.so lib/arm64-v8a/liboxidant.so
t_case "the plugin library missing"
t_assert_fails bash "$gate" --apk "${work}/noplugin.apk"

fixture_make_apk "${work}/nolibs.apk" classes.dex
t_case "no native library at all"
t_assert_fails bash "$gate" --apk "${work}/nolibs.apk"

t_summary
