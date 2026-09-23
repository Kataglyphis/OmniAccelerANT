#!/usr/bin/env bash
# check-bundle-closure.sh over synthetic bundles: when it hands a bundle to the hub's G6 ONNX Runtime
# census, and that the census verdict decides. Needs python3 and readelf; run-native-linux.sh runs it.
set -u
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${TESTS_DIR}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/tests/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/tests/test-harness.sh
source "${_harness}"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "${TESTS_DIR}/../lib/bundle-runtime.sh"
GATE="${TESTS_DIR}/../check-bundle-closure.sh"
PY="$(command -v python3 || command -v python)"

_work="$(mktemp -d)"
trap 'rm -rf "${_work}"' EXIT

# _elf <path> <needed,csv> <runpath> <text>... : an x86-64 ELF .so whose dynamic section readelf can name.
_elf() {
  mkdir -p "$(dirname "$1")"
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "${PY}" - \
    "$(cd "$(dirname "$1")" && { pwd -W 2>/dev/null || pwd; })/$(basename "$1")" "${@:2}" <<'PY'
import struct
import sys

path, needed, runpath, texts = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
strtab, dyn = b"\0", []
for tag, value in [(1, n) for n in needed.split(",") if n] + ([(29, runpath)] if runpath else []):
    dyn.append((tag, len(strtab)))
    strtab += value.encode() + b"\0"
dyn_off = 64 + 2 * 56
dyn_size = 16 * (len(dyn) + 3)
str_off = dyn_off + dyn_size
payload = b"".join(b"\0" + t.encode() + b"\0" for t in texts)
total = max(str_off + len(strtab) + len(payload), 2048)
data = b"\x7fELF" + bytes([2, 1, 1, 0]) + b"\0" * 8
data += struct.pack("<HHIQQQIHHHHHH", 3, 62, 1, 0, 64, 0, 0, 64, 56, 2, 64, 0, 0)
data += struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, total, total, 0x1000)
data += struct.pack("<IIQQQQQQ", 2, 6, dyn_off, dyn_off, dyn_off, dyn_size, dyn_size, 8)
data += b"".join(struct.pack("<qQ", t, v) for t, v in dyn)
data += struct.pack("<qQ", 5, str_off) + struct.pack("<qQ", 10, len(strtab)) + struct.pack("<qQ", 0, 0)
data += strtab + payload
open(path, "wb").write(data + b"\0" * (total - len(data)))
PY
}
CHAIN_SRC=/opt/onnxruntime/onnxruntime/core/session/inference_session.cc
WINML_SRC='C:\__w\1\s\onnxruntime\core\session\inference_session.cc'

# _bundle <name> : a bundle holding only the GStreamer plugins the gate requires; prints its root.
_bundle() {
  local root="${_work}/$1" plugin
  for plugin in "${GST_BUNDLED_PLUGIN_NAMES[@]}"; do _elf "${root}/lib/gstreamer-1.0/libgst${plugin}.so" "" ""; done
  printf '%s' "${root}"
}
_gate() { bash "${GATE}" --bundle-dir "$1" --ort-reference "${_ref}/lib" 2>&1; }
_gate_rc() { t_rc bash "${GATE}" --bundle-dir "$1" --ort-reference "${_ref}/lib"; }

_ref="${_work}/ref"
_elf "${_ref}/lib/libonnxruntime.so.1" "" "" "${CHAIN_SRC}" OrtGetApiBase

t_case "the chain ORT beside its importer passes; G6 ran and said so"
_green="$(_bundle green)"
cp "${_ref}/lib/libonnxruntime.so.1" "${_green}/lib/"
_elf "${_green}/lib/libAccelerANTgine.so" libonnxruntime.so.1 '$ORIGIN' OrtGetApiBase
t_assert_eq 0 "$(_gate_rc "${_green}")" "clean bundle"
t_assert_contains "$(_gate "${_green}")" "ORT census PASS" "the census ran"

t_case "a foreign ORT under the ORT name fails on G6's verdict (mutation)"
_elf "${_green}/lib/libonnxruntime.so.1" "" "" "${WINML_SRC}" OrtGetApiBase
t_assert_eq 1 "$(_gate_rc "${_green}")" "foreign ORT"
t_assert_contains "$(_gate "${_green}")" "FOREIGN" "named by G6"

t_case "an ORT user with no ORT file anywhere is censused and fails (mutation: a name-only trigger)"
_user="$(_bundle user)"
_elf "${_user}/lib/liboxidant.so" "" "" OrtGetApiBase
t_assert_eq 1 "$(_gate_rc "${_user}")" "dlopen-only user, nothing to load"
t_assert_contains "$(_gate "${_user}")" "UNRESOLVED" "G6 says what it would load"

t_case "a renamed foreign ORT is censused by its ABI, not skipped for its name (mutation)"
_renamed="$(_bundle renamed)"
_elf "${_renamed}/lib/libhelper.so" "" "" "${WINML_SRC}" OrtGetApiBase
t_assert_eq 1 "$(_gate_rc "${_renamed}")" "renamed ORT"
t_assert_contains "$(_gate "${_renamed}")" "FOREIGN" "found by content"

t_case "a bundle with no ORT and no ORT user skips the census"
_plain="$(_bundle plain)"
t_assert_eq 0 "$(_gate_rc "${_plain}")" "nothing ORT-related"
t_assert_eq "" "$(_gate "${_plain}" | grep -F 'ORT census')" "no census line"

t_case "a bundle the ORT-user scan cannot read is censused, not skipped (mutation: rc 2 as 'no user')"
mkdir -p "${_work}/stub"
printf '#!/usr/bin/env bash\nexit 2\n' > "${_work}/stub/grep"
chmod +x "${_work}/stub/grep"
t_assert_eq 1 "$(PATH="${_work}/stub:${PATH}" _gate_rc "${_plain}")" "read error = census, which finds nothing"

t_case "a hub without G6 is a failure that names the hub doc, never a skip"
mkdir -p "${_work}/old-hub"
t_assert_eq 1 "$(ANTFRASTRUCTURE_DIR="${_work}/old-hub" _gate_rc "${_green}")" "old hub"
t_assert_contains "$(ANTFRASTRUCTURE_DIR="${_work}/old-hub" _gate "${_green}")" \
  "third_party/ANTfrastructure/docs/onnxruntime-single-source.md" "the pointer resolves from this repo"

t_summary
