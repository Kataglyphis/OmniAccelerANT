#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
source_file="$root/packages/kataglyphis_native_inference/linux/runtime_paths.cc"
"${CXX:-c++}" -std=c++20 -shared -fPIC "$source_file" -ldl -o "$work/cpu.so"
"${CXX:-c++}" -std=c++20 -shared -fPIC -DKATAGLYPHIS_DEFAULT_ORT_DEVICE='"cuda"' \
  "$source_file" -ldl -o "$work/cuda.so"
"${CXX:-c++}" -std=c++20 -shared -fPIC -DKATAGLYPHIS_DEFAULT_ORT_DEVICE='"migraphx"' \
  "$source_file" -ldl -o "$work/migraphx.so"

# check_env <library> <NAME=expected>...: what the library's load-time constructor left in the environment.
check_env() {
  python3 - "$@" <<'PY'
import ctypes
import sys

ctypes.CDLL(sys.argv[1])
getenv = ctypes.CDLL(None).getenv
getenv.argtypes = [ctypes.c_char_p]
getenv.restype = ctypes.c_char_p
for spec in sys.argv[2:]:
    name, wanted = spec.split("=", 1)
    value = getenv(name.encode())
    actual = None if value is None else value.decode()
    expected = None if wanted == "<unset>" else wanted
    if actual != expected:
        raise SystemExit(f"{name}: expected {expected!r}, got {actual!r}")
PY
}
check() { check_env "$1" "KATAGLYPHIS_ORT_DEVICE=$2" "KATAGLYPHIS_ONNX_BACKEND=$3"; }
export -f check_env check
env -u KATAGLYPHIS_ORT_DEVICE -u KATAGLYPHIS_ONNX_BACKEND bash -c 'check "$@"' _ "$work/cpu.so" '<unset>' '<unset>'
env -u KATAGLYPHIS_ORT_DEVICE -u KATAGLYPHIS_ONNX_BACKEND bash -c 'check "$@"' _ "$work/cuda.so" cuda ort
env -u KATAGLYPHIS_ONNX_BACKEND KATAGLYPHIS_ORT_DEVICE=cpu bash -c 'check "$@"' _ "$work/cuda.so" cpu '<unset>'
env -u KATAGLYPHIS_ONNX_BACKEND KATAGLYPHIS_ORT_DEVICE=CUDA bash -c 'check "$@"' _ "$work/cuda.so" CUDA ort
env -u KATAGLYPHIS_ONNX_BACKEND KATAGLYPHIS_ORT_DEVICE=MiGraphX bash -c 'check "$@"' _ "$work/migraphx.so" MiGraphX ort
env KATAGLYPHIS_ORT_DEVICE=cuda KATAGLYPHIS_ONNX_BACKEND=tract bash -c 'check "$@"' _ "$work/cuda.so" cuda tract
for invalid in migraphx typo ''; do
  if env -u KATAGLYPHIS_ONNX_BACKEND KATAGLYPHIS_ORT_DEVICE="$invalid" \
    bash -c 'check "$@"' _ "$work/cuda.so" "$invalid" '<unset>' > "$work/invalid.log" 2>&1; then
    echo "Unsupported device '$invalid' unexpectedly succeeded" >&2
    exit 1
  fi
  grep -Fq 'Unsupported KATAGLYPHIS_ORT_DEVICE for this GPU package:' "$work/invalid.log"
done
touch "$work/libonnxruntime.so.1"
check_ort_path() { check_env "$1" "ORT_DYLIB_PATH=$2"; }
export -f check_ort_path
env -u ORT_DYLIB_PATH -u KATAGLYPHIS_ORT_DEVICE bash -c 'check_ort_path "$@"' _ "$work/cuda.so" '<unset>'
ln -s libonnxruntime.so.1 "$work/libonnxruntime.so"
env -u ORT_DYLIB_PATH -u KATAGLYPHIS_ORT_DEVICE bash -c 'check_ort_path "$@"' _ "$work/cuda.so" "$work/libonnxruntime.so"
ORT_DYLIB_PATH=/explicit/path env -u KATAGLYPHIS_ORT_DEVICE bash -c 'check_ort_path "$@"' _ "$work/cuda.so" /explicit/path
# The bundle's model is whatever .onnx its lock put there; two of them name no default.
check_model() {
  python3 - "$1" "$2" <<'PY'
import ctypes
import sys

ctypes.CDLL(sys.argv[1])
getenv = ctypes.CDLL(None).getenv
getenv.argtypes = [ctypes.c_char_p]
getenv.restype = ctypes.c_char_p
value = getenv(b"KATAGLYPHIS_ONNX_MODEL")
actual = None if value is None else value.decode()
expected = None if sys.argv[2] == "<unset>" else sys.argv[2]
if actual != expected:
    raise SystemExit(f"KATAGLYPHIS_ONNX_MODEL: expected {expected!r}, got {actual!r}")
PY
}
export -f check_model
mkdir -p "$work/bundle/lib" "$work/bundle/data/resources/models"
cp "$work/cpu.so" "$work/bundle/lib/plugin.so"
env -u KATAGLYPHIS_ONNX_MODEL bash -c 'check_model "$@"' _ "$work/bundle/lib/plugin.so" '<unset>'
: > "$work/bundle/data/resources/models/fixture_detector.onnx"
env -u KATAGLYPHIS_ONNX_MODEL bash -c 'check_model "$@"' _ "$work/bundle/lib/plugin.so" \
  "$work/bundle/lib/../data/resources/models/fixture_detector.onnx"
KATAGLYPHIS_ONNX_MODEL=/explicit bash -c 'check_model "$@"' _ "$work/bundle/lib/plugin.so" /explicit
: > "$work/bundle/data/resources/models/second.onnx"
env -u KATAGLYPHIS_ONNX_MODEL bash -c 'check_model "$@"' _ "$work/bundle/lib/plugin.so" '<unset>'
echo 'ONNX Runtime default-device checks passed'
