#!/usr/bin/env bash
# An APK slice without the native plugin installs fine and then has no camera path, so only the plugin's ABI may ship.
set -euo pipefail

apk=""
abi="arm64-v8a"
# shellcheck source=scripts/linux/lib/entry-options.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/entry-options.sh"
parse_entry_options '--apk FILE [--abi ABI]' '' \
  '--apk=apk:a path' '--abi=abi:a value' -- "$@"

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
