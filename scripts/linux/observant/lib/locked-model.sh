#!/usr/bin/env bash
# locked_model_name <lock>: the file name of the lock's first .onnx row, so no packager names the model; fails with none.
locked_model_name() {
  local name
  name="$(awk '!/^[[:space:]]*#/ && $2 ~ /\.onnx$/ { print $2; exit }' "${1:?lock required}")"
  [ -n "${name}" ] || { printf 'no .onnx model in %s\n' "$1" >&2; return 1; }
  printf '%s\n' "${name}"
}
