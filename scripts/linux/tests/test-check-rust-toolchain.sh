#!/usr/bin/env bash
# The rustc-stamp gate on synthetic ELFs whose .comment is written by objcopy: one green, and each way it must go red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${SCRIPT_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
gate="${SCRIPT_DIR}/../check-rust-toolchain.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

printf 'int f(void) { return 0; }\n' > "${work}/f.c"
cc -shared -fPIC -o "${work}/base.so" "${work}/f.c" || exit 1

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

make_elf "${work}/pinned.so" "GCC: (GNU) 16.2.0" "rustc version 1.98.1 (48a229cea 2026-09-01)"
make_elf "${work}/floating.so" "rustc version 1.99.0 (b940084d7 2026-09-28)"
make_elf "${work}/mixed.so" "rustc version 1.98.1 (48a229cea 2026-09-01)" "rustc version 1.99.0 (b940084d7 2026-09-28)"
make_elf "${work}/c-only.so" "GCC: (GNU) 16.2.0"

t_case "built by the expected rustc"
t_assert_rc 0 bash "$gate" --expect 1.98.1 "${work}/pinned.so"
t_case "built by a floating stable"
t_assert_rc 1 bash "$gate" --expect 1.98.1 "${work}/floating.so"
t_case "objects from two rustc versions"
t_assert_rc 1 bash "$gate" --expect 1.98.1 "${work}/mixed.so"
t_case "no rustc stamp at all"
t_assert_rc 1 bash "$gate" --expect 1.98.1 "${work}/c-only.so"
t_case "a missing file"
t_assert_rc 1 bash "$gate" --expect 1.98.1 "${work}/absent.so"
t_case "one bad binary among good ones"
t_assert_rc 1 bash "$gate" --expect 1.98.1 "${work}/pinned.so" "${work}/floating.so"
t_case "nothing to check"
t_assert_rc 2 bash "$gate" --expect 1.98.1

# Without --expect: the rustc that resolves in the crate dir, as Cargokit's build does.
mkdir -p "${work}/bin" "${work}/crate"
printf '#!/usr/bin/env bash\nprintf "rustc 1.98.1 (48a229cea 2026-09-01)\\n"\n' > "${work}/bin/rustc"
chmod +x "${work}/bin/rustc"
t_case "the crate's resolved rustc, matched"
PATH="${work}/bin:${PATH}" t_assert_rc 0 bash "$gate" --crate-dir "${work}/crate" "${work}/pinned.so"
t_case "the crate's resolved rustc, missed"
PATH="${work}/bin:${PATH}" t_assert_rc 1 bash "$gate" --crate-dir "${work}/crate" "${work}/floating.so"

make_apk "${work}/good.apk" "lib/arm64-v8a/liboxidant.so=${work}/pinned.so" "classes.dex=${work}/f.c"
make_apk "${work}/drifted.apk" "lib/arm64-v8a/liboxidant.so=${work}/floating.so"
make_apk "${work}/norust.apk" "lib/arm64-v8a/libflutter.so=${work}/c-only.so"
t_case "an APK whose liboxidant matches"
t_assert_rc 0 bash "$gate" --expect 1.98.1 --apk "${work}/good.apk"
t_case "an APK whose liboxidant drifted"
t_assert_rc 1 bash "$gate" --expect 1.98.1 --apk "${work}/drifted.apk"
t_case "an APK without liboxidant"
t_assert_rc 1 bash "$gate" --expect 1.98.1 --apk "${work}/norust.apk"

t_summary
