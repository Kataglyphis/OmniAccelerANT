#!/usr/bin/env bash
# Hosted runners can check a GPU bundle's CPU path without pretending to test GPU execution.
omni_ci_package_smoke() (
  case "${KATAGLYPHIS_ORT_PROVIDER:-cpu}" in
    cpu) ;;
    cuda|migraphx)
      export KATAGLYPHIS_ORT_DEVICE=cpu KATAGLYPHIS_ONNX_BACKEND=ort
      echo '[Info] GPU package smoke: using ONNX Runtime CPU; GPU inference needs a hardware check.' >&2
      ;;
    *) echo "Error: invalid KATAGLYPHIS_ORT_PROVIDER for smoke: $KATAGLYPHIS_ORT_PROVIDER" >&2; return 2 ;;
  esac
  "$@"
)
