#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$root/scripts/linux/lib/gpu-ci-smoke.sh"
capture() { printf '%s|%s' "${KATAGLYPHIS_ORT_DEVICE-unset}" "${KATAGLYPHIS_ONNX_BACKEND-unset}"; }
unset KATAGLYPHIS_ORT_PROVIDER KATAGLYPHIS_ORT_DEVICE KATAGLYPHIS_ONNX_BACKEND
test "$(omni_ci_package_smoke capture)" = 'unset|unset'
export KATAGLYPHIS_ORT_DEVICE=directml KATAGLYPHIS_ONNX_BACKEND=tract
test "$(omni_ci_package_smoke capture)" = 'directml|tract'
for provider in cuda migraphx; do
  export KATAGLYPHIS_ORT_PROVIDER="$provider"
  test "$(omni_ci_package_smoke capture)" = 'cpu|ort'
  omni_ci_package_smoke capture > /dev/null
  test "$KATAGLYPHIS_ORT_DEVICE|$KATAGLYPHIS_ONNX_BACKEND" = 'directml|tract'
  rc=0
  omni_ci_package_smoke bash -c 'exit 7' || rc=$?
  test "$rc" -eq 7
done
export KATAGLYPHIS_ORT_PROVIDER=unknown
if omni_ci_package_smoke capture > /dev/null 2>&1; then
  echo 'Unknown GPU provider unexpectedly passed the smoke guard' >&2
  exit 1
fi
echo 'GPU package CPU-smoke checks passed'
