#!/usr/bin/env bash
# An APK slice without the native plugin installs fine and then has no camera path, so only the plugin's ABI may ship.
set -euo pipefail

apk=""
abi="arm64-v8a"
while [ $# -gt 0 ]; do
  case "$1" in
    --apk) apk="${2:?--apk needs a path}"; shift 2 ;;
    --abi) abi="${2:?--abi needs a value}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s --apk FILE [--abi ABI]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$apk" ]; then
  printf 'Error: --apk is required\n' >&2
  exit 2
fi
if [ ! -f "$apk" ]; then
  printf 'Error: no APK at %s\n' "$apk" >&2
  exit 1
fi

mapfile -t libs < <(unzip -Z1 "$apk" | grep '^lib/' || true)
if [ "${#libs[@]}" -eq 0 ]; then
  printf 'FAIL %s holds no native library at all\n' "$apk" >&2
  exit 1
fi
printf '%s\n' "${libs[@]}"

rc=0
mapfile -t abis < <(printf '%s\n' "${libs[@]}" | cut -d/ -f2 | sort -u)
for found in "${abis[@]}"; do
  if [ "$found" != "$abi" ]; then
    printf 'FAIL lib/%s/ ships, but the native plugin is built for %s only\n' "$found" "$abi" >&2
    rc=1
  fi
done
for so in libflutter.so libapp.so liboxidant.so libkataglyphis_native_inference.so; do
  if ! printf '%s\n' "${libs[@]}" | grep -qx "lib/${abi}/${so}"; then
    printf 'FAIL lib/%s/%s is missing\n' "$abi" "$so" >&2
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  printf 'APK ABI OK: lib/%s/ only, %d native libraries\n' "$abi" "${#libs[@]}"
fi
exit "$rc"
