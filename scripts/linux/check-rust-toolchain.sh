#!/usr/bin/env bash
# rustc stamps its version into .comment; a Cargokit that drifts to a floating `stable` shows only there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
crate_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)/third_party/OxidANT"
expect=""
apk=""
abi="arm64-v8a"
files=()

while [ $# -gt 0 ]; do
  case "$1" in
    --crate-dir) crate_dir="${2:?--crate-dir needs a path}"; shift 2 ;;
    --expect) expect="${2:?--expect needs a version}"; shift 2 ;;
    --apk) apk="${2:?--apk needs a path}"; shift 2 ;;
    --abi) abi="${2:?--abi needs a value}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--crate-dir DIR] [--expect VERSION] [--apk FILE [--abi ABI]] [ELF...]\n' "$0"
      exit 0
      ;;
    -*) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    *) files+=("$1"); shift ;;
  esac
done

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

if [ -n "$apk" ]; then
  [ -f "$apk" ] || { printf 'Error: no APK at %s\n' "$apk" >&2; exit 1; }
  unzip -p "$apk" "lib/${abi}/liboxidant.so" > "${work}/liboxidant.so" 2>/dev/null || {
    printf 'FAIL %s holds no lib/%s/liboxidant.so\n' "$apk" "$abi" >&2
    exit 1
  }
  files+=("${work}/liboxidant.so")
  apk_member="${apk}:lib/${abi}/liboxidant.so"
fi
if [ "${#files[@]}" -eq 0 ]; then
  printf 'Error: name at least one ELF, or --apk\n' >&2
  exit 2
fi

# The toolchain rustup resolves for the crate, which is the one Cargokit builds it with.
if [ -z "$expect" ]; then
  expect="$(cd "$crate_dir" && rustc -V | awk '{print $2}')"
fi
[ -n "$expect" ] || { printf 'Error: no rustc version to expect\n' >&2; exit 2; }

fails=0
for f in "${files[@]}"; do
  label="$f"
  [ "$f" = "${work}/liboxidant.so" ] && label="${apk_member}"
  if [ ! -f "$f" ]; then
    printf 'FAIL %s: no such file\n' "$label" >&2
    fails=$((fails + 1))
    continue
  fi
  stamps="$(readelf -p .comment "$f" 2>/dev/null | grep -Eo 'rustc version [0-9][^ ]*' | awk '{print $3}' | sort -u | tr '\n' ' ')"
  stamps="${stamps% }"
  if [ -z "$stamps" ]; then
    printf 'FAIL %s carries no rustc stamp\n' "$label" >&2
    fails=$((fails + 1))
  elif [ "$stamps" != "$expect" ]; then
    printf 'FAIL %s was built by rustc %s, not the toolchain %s resolves to (%s)\n' "$label" "$stamps" "$crate_dir" "$expect" >&2
    fails=$((fails + 1))
  else
    printf 'OK   %s: rustc %s\n' "$label" "$expect"
  fi
done
[ "$fails" -eq 0 ]
