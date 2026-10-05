#!/usr/bin/env bash
# The rustc-stamp gate on synthetic ELFs whose .comment is written by objcopy: one green, and each way it must go red.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="${SCRIPT_DIR}/../check-rust-toolchain.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

printf 'int f(void) { return 0; }\n' > "${work}/f.c"
cc -shared -fPIC -o "${work}/base.so" "${work}/f.c"

# make_elf <out> <comment string>...: base.so with exactly these NUL-separated .comment entries.
make_elf() {
  local out="$1"
  shift
  : > "${work}/comment"
  local s
  for s in "$@"; do printf '%s\0' "$s" >> "${work}/comment"; done
  objcopy --remove-section .comment --add-section .comment="${work}/comment" "${work}/base.so" "$out"
}

# make_apk <out> <member=file>...: a zip holding each file under its member name.
make_apk() {
  local out="$1"
  shift
  python3 - "$out" "$@" <<'EOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for spec in sys.argv[2:]:
        member, path = spec.split("=", 1)
        z.write(path, member)
EOF
}

passed=0
expect() {
  local want="$1" name="$2" got=0
  shift 2
  bash "$gate" "$@" >/dev/null 2>&1 || got=$?
  if [ "$want" = pass ] && [ "$got" -ne 0 ]; then
    printf 'FAIL %s: the gate refused a correct binary (rc %s)\n' "$name" "$got" >&2
    return 1
  fi
  if [ "$want" != pass ] && [ "$got" -ne "$want" ]; then
    printf 'FAIL %s: expected rc %s, got %s\n' "$name" "$want" "$got" >&2
    return 1
  fi
  passed=$((passed + 1))
  printf 'ok   %s\n' "$name"
}

make_elf "${work}/pinned.so" "GCC: (GNU) 16.2.0" "rustc version 1.98.1 (48a229cea 2026-09-01)"
make_elf "${work}/floating.so" "rustc version 1.99.0 (b940084d7 2026-09-28)"
make_elf "${work}/mixed.so" "rustc version 1.98.1 (48a229cea 2026-09-01)" "rustc version 1.99.0 (b940084d7 2026-09-28)"
make_elf "${work}/c-only.so" "GCC: (GNU) 16.2.0"

expect pass "built by the expected rustc" --expect 1.98.1 "${work}/pinned.so"
expect 1 "built by a floating stable" --expect 1.98.1 "${work}/floating.so"
expect 1 "objects from two rustc versions" --expect 1.98.1 "${work}/mixed.so"
expect 1 "no rustc stamp at all" --expect 1.98.1 "${work}/c-only.so"
expect 1 "a missing file" --expect 1.98.1 "${work}/absent.so"
expect 1 "one bad binary among good ones" --expect 1.98.1 "${work}/pinned.so" "${work}/floating.so"
expect 2 "nothing to check" --expect 1.98.1

# Without --expect: the rustc that resolves in the crate dir, as Cargokit's build does.
mkdir -p "${work}/bin" "${work}/crate"
printf '#!/usr/bin/env bash\nprintf "rustc 1.98.1 (48a229cea 2026-09-01)\\n"\n' > "${work}/bin/rustc"
chmod +x "${work}/bin/rustc"
PATH="${work}/bin:${PATH}" expect pass "the crate's resolved rustc, matched" --crate-dir "${work}/crate" "${work}/pinned.so"
PATH="${work}/bin:${PATH}" expect 1 "the crate's resolved rustc, missed" --crate-dir "${work}/crate" "${work}/floating.so"

make_apk "${work}/good.apk" "lib/arm64-v8a/liboxidant.so=${work}/pinned.so" "classes.dex=${work}/f.c"
make_apk "${work}/drifted.apk" "lib/arm64-v8a/liboxidant.so=${work}/floating.so"
make_apk "${work}/norust.apk" "lib/arm64-v8a/libflutter.so=${work}/c-only.so"
expect pass "an APK whose liboxidant matches" --expect 1.98.1 --apk "${work}/good.apk"
expect 1 "an APK whose liboxidant drifted" --expect 1.98.1 --apk "${work}/drifted.apk"
expect 1 "an APK without liboxidant" --expect 1.98.1 --apk "${work}/norust.apk"

printf '  %d assertion(s) passed\n' "$passed"
