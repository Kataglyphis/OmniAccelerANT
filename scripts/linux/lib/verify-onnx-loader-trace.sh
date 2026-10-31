#!/usr/bin/env bash
# Check the traced ONNX Runtime paths for Omni bundle or AppImage launches.
omni_verify_ort_loader_trace() {
  local kind=$1 runtime_root=$2 variant=$3 prefix=$4 runtime resolved suffix extraction
  local -a logs loaded
  shopt -s nullglob
  logs=("$prefix."*)
  [[ ${#logs[@]} -gt 0 ]] || { echo 'Missing dynamic loader trace' >&2; return 1; }
  mapfile -t loaded < <(awk 'index($0,"calling init: ") && index($0,"libonnxruntime.so") { print substr($0,index($0,"calling init: ")+14) }' "${logs[@]}")
  [[ ${#loaded[@]} -gt 0 ]] || { echo 'Missing ONNX Runtime loader evidence' >&2; return 1; }
  for runtime in "${loaded[@]}"; do
    [[ "$runtime" =~ /libonnxruntime\.so(\.[0-9]+)*$ ]] || { echo 'Malformed ONNX Runtime loader evidence' >&2; return 1; }
    if [[ "$kind" == appimage ]]; then
      suffix="/usr/lib/$variant/lib/${runtime##*/}"
      [[ "$runtime" == "$runtime_root/"*"$suffix" ]] || { echo 'ONNX Runtime loaded outside AppImage' >&2; return 1; }
      extraction=${runtime#"$runtime_root/"}
      extraction=${extraction%"$suffix"}
      [[ "$extraction" =~ ^appimage_extracted_[0-9a-f]{32}$ ]] || { echo 'Invalid AppImage extraction path' >&2; return 1; }
    elif [[ "$kind" == bundle ]]; then
      case "$runtime" in "$runtime_root/"libonnxruntime.so*) ;; *) echo 'ONNX Runtime loaded outside bundle' >&2; return 1 ;; esac
      resolved=$(realpath -e "$runtime") || return 1
      case "$resolved" in "$runtime_root/"*) ;; *) echo 'ONNX Runtime symlink escapes bundle' >&2; return 1 ;; esac
    else
      echo 'Unsupported ONNX Runtime trace type' >&2; return 1
    fi
  done
}
