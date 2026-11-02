#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/linux/tests/fixture-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/fixture-common.sh"
root="$(fixture_root)"
check="$root/scripts/linux/check-packaged-onnx-runtime.sh"
fixture_workdir
mkdir -p "$work/bin" "$work/bundle/lib" "$work/runner"
fixture_xvfb_stub "$work/bin"
fixture_stub "$work/bundle/omni_accelerant" <<'STUB'
[[ $# == 1 && "$1" == --onnx-check && ${KATAGLYPHIS_ORT_DEVICE:-} == cpu && ${KATAGLYPHIS_ONNX_BACKEND:-} == ort ]]
[[ -z ${LD_LIBRARY_PATH+x} && -z ${ORT_DYLIB_PATH+x} && -z ${ONNX_ROOT+x} ]]
runtime="${BASH_SOURCE[0]%/*}/lib/libonnxruntime.so"
[[ ${BAD_RUNTIME:-} != outside ]] || runtime=/host/libonnxruntime.so
[[ ${BAD_RUNTIME:-} != malformed ]] || runtime=libonnxruntime.so
if [[ ${BAD_RUNTIME:-} != missing ]]; then printf 'calling init: %s\n' "$runtime" > "$LD_DEBUG_OUTPUT.fixture"; fi
if [[ ${BAD_RUNTIME:-} == mixed ]]; then printf 'calling init: /host/libonnxruntime.so\n' >> "$LD_DEBUG_OUTPUT.fixture"; fi
STUB
fixture_stub "$work/appimage" <<'STUB'
[[ $# == 1 && "$1" == --onnx-check && ${APPIMAGE_EXTRACT_AND_RUN:-} == 1 ]]
runtime="$TMPDIR/appimage_extracted_0123456789abcdef0123456789abcdef/usr/lib/omni-accelerant-nvidia/lib/libonnxruntime.so"
[[ ${BAD_RUNTIME:-} != outside ]] || runtime=/host/libonnxruntime.so
[[ ${BAD_RUNTIME:-} != malformed ]] || runtime="$TMPDIR/appimage_extracted_invalid/usr/lib/omni-accelerant-nvidia/lib/libonnxruntime.so"
if [[ ${BAD_RUNTIME:-} != missing ]]; then printf 'calling init: %s\n' "$runtime" > "$LD_DEBUG_OUTPUT.fixture"; fi
if [[ ${BAD_RUNTIME:-} == mixed ]]; then printf 'calling init: /host/libonnxruntime.so\n' >> "$LD_DEBUG_OUTPUT.fixture"; fi
STUB
chmod +x "$work/bundle/omni_accelerant" "$work/appimage"
touch "$work/bundle/lib/libonnxruntime.so"
export PATH="$work/bin:$PATH" RUNNER_TEMP="$work/runner"
export LD_LIBRARY_PATH=/host-sdk ORT_DYLIB_PATH=/host/libonnxruntime.so ONNX_ROOT=/host
bash "$check" bundle "$work/bundle"
bash "$check" appimage "$work/appimage" omni-accelerant-nvidia
for fault in outside malformed missing mixed; do
  if BAD_RUNTIME=$fault bash "$check" bundle "$work/bundle" >/dev/null 2>&1; then
    echo "Bundle accepted $fault runtime trace" >&2; exit 1
  fi
  if BAD_RUNTIME=$fault bash "$check" appimage "$work/appimage" omni-accelerant-nvidia >/dev/null 2>&1; then
    echo "AppImage accepted $fault runtime trace" >&2; exit 1
  fi
done
rm "$work/bundle/lib/libonnxruntime.so"
ln -s /etc/hosts "$work/bundle/lib/libonnxruntime.so"
fixture_refuses_quiet 'Escaping runtime symlink accepted' bash "$check" bundle "$work/bundle"
rm "$work/bundle/lib/libonnxruntime.so"
rmdir "$work/bundle/lib"
mkdir "$work/external"
touch "$work/external/libonnxruntime.so"
ln -s "$work/external" "$work/bundle/lib"
fixture_refuses_quiet 'Escaping runtime directory accepted' bash "$check" bundle "$work/bundle"
echo 'Packaged ONNX Runtime loader checks passed'
