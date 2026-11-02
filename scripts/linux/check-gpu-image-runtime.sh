#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/linux/lib/gpu-script-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gpu-script-common.sh"
gpu_require_argc $# 1 1 'check-gpu-image-runtime.sh cuda|migraphx'
case "$1" in cuda|migraphx) provider=$1 ;; *) gpu_die 2 'Invalid GPU provider' ;; esac
lib="${ORT_LIB_LOCATION:?ORT_LIB_LOCATION must name the GPU chain runtime}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hub="${ANTFRASTRUCTURE_DIR:-$repo/third_party/ANTfrastructure}/linux/scripts/06-packaging"
[[ -f "$lib/../include/onnxruntime_cxx_api.h" ]] || gpu_die 1 'GPU ONNX Runtime headers are missing'
libraries=()
for name in libonnxruntime.so.1 libonnxruntime_providers_shared.so "libonnxruntime_providers_${provider}.so"; do
  [[ -f "$lib/$name" ]] || gpu_die 1 "GPU image is missing $name"
  libraries+=(--library "$lib/$name")
done
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
python3 "$hub/stage-ort-wheel-licenses.py" --require-unstripped \
  --wheel-dir "${ORT_CHAIN_WHEEL_DIR:-/opt/onnxruntime-wheels}" --destination "$work" \
  --strip "${STRIP:-strip}" "${libraries[@]}"
echo "PASS: $provider image runtime matches one GPU wheel"
