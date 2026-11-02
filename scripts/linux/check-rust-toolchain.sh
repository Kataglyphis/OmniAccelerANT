#!/usr/bin/env bash
# rustc stamps its version into .comment; a Cargokit that drifts to a floating `stable` shows only there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
crate_dir="$(cd "${SCRIPT_DIR}/../.." && pwd)/third_party/OxidANT"
expect=""
apk=""
abi="arm64-v8a"
files=()

# shellcheck source=scripts/linux/lib/entry-options.sh
source "${SCRIPT_DIR}/lib/entry-options.sh"
add_elf_argument() {
  case "$1" in
    -*) return 1 ;;
    *) files+=("$1") ;;
  esac
}
parse_entry_options '[--crate-dir DIR] [--expect VERSION] [--apk FILE [--abi ABI]] [ELF...]' add_elf_argument \
  '--crate-dir=crate_dir:a path' '--expect=expect:a version' '--apk=apk:a path' '--abi=abi:a value' -- "$@"

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
