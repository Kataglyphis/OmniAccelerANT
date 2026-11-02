#!/usr/bin/env bash
# Run the existing CPU self-check and verify its loaded ORT belongs to the package.
set -euo pipefail
# shellcheck source=scripts/linux/lib/gpu-script-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gpu-script-common.sh"
gpu_require_argc $# 2 3 'check-packaged-onnx-runtime.sh bundle BUNDLE | appimage APPIMAGE PACKAGE_NAME'
unset LD_PRELOAD LD_AUDIT LD_DEBUG LD_DEBUG_OUTPUT
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$script_dir/lib/verify-onnx-loader-trace.sh"
kind=$1
target=$(realpath -e "$2")
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/omni-ort-check.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
work=$(realpath -e "$work")
mkdir "$work/logs"
case "$kind" in
  bundle)
    [[ $# -eq 2 && -x "$target/omni_accelerant" && -f "$target/lib/libonnxruntime.so" ]] || { echo 'Missing bundle app or runtime' >&2; exit 1; }
    runtime_root=$(realpath -e "$target/lib")
    case "$runtime_root" in "$target/"*) ;; *) echo 'Runtime directory escapes bundle' >&2; exit 1 ;; esac
    resolved=$(realpath -e "$target/lib/libonnxruntime.so")
    case "$resolved" in "$runtime_root/"*) ;; *) echo 'Runtime escapes bundle' >&2; exit 1 ;; esac
    launcher="$target/omni_accelerant"
    ;;
  appimage)
    [[ $# -eq 3 && -x "$target" && "$3" =~ ^omni-accelerant(-(nvidia|amd))?$ ]] || { echo 'Invalid AppImage or package name' >&2; exit 1; }
    variant=$3
    runtime_root=$work
    launcher=$target
    export APPIMAGE_EXTRACT_AND_RUN=1 TMPDIR="$work"
    ;;
  *) echo 'Unsupported package type' >&2; exit 2 ;;
esac
env -u LD_PRELOAD -u LD_AUDIT -u LD_LIBRARY_PATH -u LD_DEBUG -u LD_DEBUG_OUTPUT \
  -u KATAGLYPHIS_ONNX_MODEL -u KATAGLYPHIS_DIRECTML_DEVICE_ID -u ORT_DYLIB_PATH \
  -u ORT_LIB_LOCATION -u ONNX_ROOT -u KATAGLYPHIS_ORT_DEVICE -u KATAGLYPHIS_ONNX_BACKEND \
  KATAGLYPHIS_ORT_DEVICE=cpu KATAGLYPHIS_ONNX_BACKEND=ort \
  LD_DEBUG=libs LD_DEBUG_OUTPUT="$work/logs/loader" xvfb-run -a timeout 90 "$launcher" --onnx-check
omni_verify_ort_loader_trace "$kind" "$runtime_root" "${variant:-}" "$work/logs/loader"
echo 'Packaged CPU inference loaded the bundle ONNX Runtime'
