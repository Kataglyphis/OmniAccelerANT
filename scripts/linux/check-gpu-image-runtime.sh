#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/linux/lib/gpu-script-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gpu-script-common.sh"
gpu_require_argc $# 1 1 'check-gpu-image-runtime.sh cuda|migraphx'
case "$1" in cuda|migraphx) provider=$1 ;; *) gpu_die 2 'Invalid GPU provider' ;; esac
lib="${ORT_LIB_LOCATION:?ORT_LIB_LOCATION must name the chain runtime this provider loads into}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hub="${ANTFRASTRUCTURE_DIR:-$repo/third_party/ANTfrastructure}/linux/scripts/06-packaging"
[[ -f "$lib/../include/onnxruntime_cxx_api.h" ]] || gpu_die 1 'ONNX Runtime headers are missing beside ORT_LIB_LOCATION'
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
names=(libonnxruntime.so.1)
# The GPU prefix holds its wheel's own bytes; the CPU core AMD's plugin loads into is the wheel's library stripped.
exact=(--require-unstripped)
if [[ "$provider" == migraphx ]]; then
  exact=()
  # No wheel carries the plugin: the package checks compare a package's module and texts with these.
  gpu_source_plugin_texts
  [[ -f "$(ort_amdgpu_ep_dir)/$ORT_AMDGPU_EP_MODULE" ]] || gpu_die 1 "This image has no MIGraphX plugin module at $(ort_amdgpu_ep_dir)/$ORT_AMDGPU_EP_MODULE"
  stage_amdgpu_ep_notices "$work/plugin"
else
  names+=(libonnxruntime_providers_shared.so libonnxruntime_providers_cuda.so)
fi
libraries=()
for name in "${names[@]}"; do
  [[ -f "$lib/$name" ]] || gpu_die 1 "GPU image is missing $name"
  libraries+=(--library "$lib/$name")
done
python3 "$hub/stage-ort-wheel-licenses.py" "${exact[@]}" \
  --wheel-dir "${ORT_CHAIN_WHEEL_DIR:-/opt/onnxruntime-wheels}" --destination "$work" \
  --strip "${STRIP:-strip}" "${libraries[@]}"
echo "PASS: $provider image runtime matches one chain wheel"
