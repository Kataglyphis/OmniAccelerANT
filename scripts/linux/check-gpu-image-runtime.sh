#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then echo 'usage: check-gpu-image-runtime.sh cuda|migraphx' >&2; exit 2; fi
case "$1" in cuda|migraphx) provider=$1 ;; *) echo 'Invalid GPU provider' >&2; exit 2 ;; esac
lib="${ORT_LIB_LOCATION:?ORT_LIB_LOCATION must name the GPU chain runtime}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hub="${ANTFRASTRUCTURE_DIR:-$repo/third_party/ANTfrastructure}/linux/scripts/06-packaging"
[[ -f "$lib/../include/onnxruntime_cxx_api.h" ]] || { echo 'GPU ONNX Runtime headers are missing' >&2; exit 1; }
libraries=()
for name in libonnxruntime.so.1 libonnxruntime_providers_shared.so "libonnxruntime_providers_${provider}.so"; do
  [[ -f "$lib/$name" ]] || { echo "GPU image is missing $name" >&2; exit 1; }
  libraries+=(--library "$lib/$name")
done
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
python3 "$hub/stage-ort-wheel-licenses.py" --require-unstripped \
  --wheel-dir "${ORT_CHAIN_WHEEL_DIR:-/opt/onnxruntime-wheels}" --destination "$work" \
  --strip "${STRIP:-strip}" "${libraries[@]}"
echo "PASS: $provider image runtime matches one GPU wheel"
