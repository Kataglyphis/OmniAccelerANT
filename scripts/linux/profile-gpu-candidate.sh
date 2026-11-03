#!/usr/bin/env bash
# Check packaged detector outputs and ORT placement on CPU and the requested GPU.
set -euo pipefail
# shellcheck source=scripts/linux/lib/gpu-script-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gpu-script-common.sh"
gpu_require_argc $# 4 5 'profile-gpu-candidate.sh BUNDLE cuda|migraphx FIXTURE NEW_EVIDENCE_DIR [LAUNCHER]'
bundle=$(realpath -e "$1") provider=$2 fixture=$(realpath -e "$3") evidence=$4 launcher=${5:-"$bundle/omni_accelerant"}
case "$provider" in cuda|migraphx) ;; *) gpu_die 2 'Unsupported GPU provider' ;; esac
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script_dir=$GPU_SCRIPT_DIR
# shellcheck source=/dev/null
source "$script_dir/lib/verify-onnx-loader-trace.sh"
hub="$repo/third_party/ANTfrastructure"
helper="$hub/linux/scripts/lib/gpu-profile-env.sh"
shared="$hub/shared/python"
[[ -x "$bundle/omni_accelerant" && -f "$bundle/lib/libonnxruntime.so" && -x "$launcher" && -f "$fixture" && -f "$helper" ]] || gpu_die 1 'Candidate, ONNX Runtime, fixture or pinned GPU environment helper missing'
ort=$(realpath -e "$bundle/lib/libonnxruntime.so")
gpu_assert_inside "$ort" "$bundle/lib" 'Packaged ONNX Runtime escapes the bundle'
image_runtime_root=
if [[ $# -eq 5 ]]; then
  [[ ${APPIMAGE_EXTRACT_AND_RUN:-} == 1 && -n ${TMPDIR:-} ]] || gpu_die 1 'AppImage profile needs an isolated extraction directory'
  image_runtime_root=$(realpath -e "$TMPDIR")
fi
# shellcheck source=/dev/null
source "$helper"
declare -F gpu_without_migraphx_overrides >/dev/null || gpu_die 1 'Pinned GPU environment helper lacks its API'
[[ -f "$shared/verify_ort_profile.py" && -f "$shared/compare_detector_parity.py" ]] || gpu_die 1 'Pinned profiling or parity helper missing'
[[ $(python3 -I "$shared/verify_ort_profile.py" --help) == *--min-runs* && $(python3 -I "$shared/compare_detector_parity.py" --help) == *--pairwise* ]] || gpu_die 1 'Pinned profiling or parity helper is too old'
printf '%s  %s\n' '6d375ac20fadfd400b3033084f8b0581dcc145f7c14e3b24b97975e379c52999' "$fixture" | sha256sum -c -
python3 -I "$repo/scripts/windows/verify_detector_model.py" "$hub/linux/scripts/lib/fetch-data-lock.py" \
  "$repo/third_party/OxidANT/resources/models/models.lock" "$bundle/data/resources/models" --root "$bundle"
mkdir -- "$evidence"
evidence=$(realpath -e "$evidence")
launcher=$(realpath -e "$launcher")
for mode in cpu gpu; do
  clean=(env -u LD_PRELOAD -u LD_AUDIT -u KATAGLYPHIS_DIRECTML_DEVICE_ID -u KATAGLYPHIS_ONNX_MODEL
    -u LD_DEBUG -u LD_DEBUG_OUTPUT
    -u ORT_DYLIB_PATH -u ORT_LIB_LOCATION -u ONNX_ROOT -u KATAGLYPHIS_ONNX_BACKEND -u KATAGLYPHIS_ORT_DEVICE
    -u GST_PLUGIN_PATH -u GST_PLUGIN_PATH_1_0 -u GST_PLUGIN_SYSTEM_PATH -u GST_PLUGIN_SYSTEM_PATH_1_0
    -u GST_PLUGIN_SCANNER -u GST_PLUGIN_SCANNER_1_0 -u GST_REGISTRY -u GST_REGISTRY_1_0 -u GST_REGISTRY_FORK)
  device=$provider
  if [[ "$mode" == cpu ]]; then
    clean+=(-u LD_LIBRARY_PATH)
    device=cpu
    extra=(KATAGLYPHIS_ORT_DEVICE=cpu KATAGLYPHIS_ONNX_BACKEND=ort)
  else
    extra=(KATAGLYPHIS_ORT_DEVICE="$provider" KATAGLYPHIS_ONNX_BACKEND=ort)
  fi
  if [[ -n "${PROFILE_DISK_PLAN:-}" ]]; then
    disk_stage=runtime
    [[ $# -ne 5 ]] || disk_stage=launch
    python3 -I "$script_dir/preflight-profile-packages.py" check --plan "$PROFILE_DISK_PLAN" \
      --root "${PROFILE_DISK_ROOT:?}" --stage "$disk_stage"
  fi
  (cd "$evidence" && gpu_without_migraphx_overrides "${clean[@]}" "${extra[@]}" \
    GST_REGISTRY_1_0="$evidence/$mode-gst-registry.bin" LD_DEBUG=libs LD_DEBUG_OUTPUT="$evidence/$mode-loader" xvfb-run -a timeout 180 "$launcher" \
    --onnx-profile-image "$fixture" "$evidence/$mode-1.json" "$evidence/$mode-2.json" "$evidence/$mode-profile")
  shopt -s nullglob
  if [[ -n "$image_runtime_root" ]]; then
    omni_verify_ort_loader_trace appimage "$image_runtime_root" "${bundle##*/}" "$evidence/$mode-loader"
  else
    omni_verify_ort_loader_trace bundle "$bundle/lib" '' "$evidence/$mode-loader"
  fi
  profiles=("$evidence/$mode-profile"*.json)
  [[ ${#profiles[@]} -eq 1 ]] || gpu_die 1 "Expected one $mode ORT profile"
  python3 -I "$shared/verify_ort_profile.py" "${profiles[0]}" --device "$device" --min-runs 2
done
python3 -I "$shared/compare_detector_parity.py" "$evidence/cpu-1.json" "$evidence/cpu-2.json"
python3 -I "$shared/compare_detector_parity.py" "$evidence/cpu-1.json" "$evidence/gpu-1.json"
python3 -I "$shared/compare_detector_parity.py" "$evidence/cpu-1.json" "$evidence/gpu-2.json"
python3 -I "$shared/compare_detector_parity.py" "$evidence/gpu-1.json" "$evidence/gpu-2.json" --pairwise
