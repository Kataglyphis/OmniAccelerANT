#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
source_file="$root/packages/kataglyphis_native_inference/linux/runtime_paths.cc"
"${CXX:-c++}" -std=c++20 -shared -fPIC "$source_file" -ldl -o "$work/cpu.so"
"${CXX:-c++}" -std=c++20 -shared -fPIC -DKATAGLYPHIS_DEFAULT_ORT_DEVICE='"cuda"' \
  "$source_file" -ldl -o "$work/cuda.so"
"${CXX:-c++}" -std=c++20 -shared -fPIC -DKATAGLYPHIS_DEFAULT_ORT_DEVICE='"migraphx"' \
  "$source_file" -ldl -o "$work/migraphx.so"

check() {
  python3 - "$1" "$2" "$3" <<'PY'
import ctypes
import sys

ctypes.CDLL(sys.argv[1])
getenv = ctypes.CDLL(None).getenv
getenv.argtypes = [ctypes.c_char_p]
getenv.restype = ctypes.c_char_p
for name, expected in zip(("KATAGLYPHIS_ORT_DEVICE", "KATAGLYPHIS_ONNX_BACKEND"), sys.argv[2:]):
    value = getenv(name.encode())
    actual = None if value is None else value.decode()
    expected = None if expected == "<unset>" else expected
    if actual != expected:
        raise SystemExit(f"{name}: expected {expected!r}, got {actual!r}")
PY
}
export -f check
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
echo 'ONNX Runtime default-device checks passed'
